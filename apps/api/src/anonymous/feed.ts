import { pool } from '../db.js';
import type { AnonymousProfilePublic } from './identity.js';
import type { PostPublic } from './content.js';
import { withResolvedMediaMany } from './media.js';

function iso(v: Date | string | null | undefined): string | null {
  if (v == null) return null;
  return v instanceof Date ? v.toISOString() : String(v);
}

/**
 * Feed from joined Spaces + adult_public Spaces.
 * Private / unauthorized Spaces never appear.
 */
export async function getFeed(opts: {
  profile: AnonymousProfilePublic;
  sort: string;
  cursor?: string | null;
  limit: number;
}): Promise<{ posts: PostPublic[]; next_cursor: string | null }> {
  const limit = Math.min(Math.max(opts.limit || 20, 1), 50);
  const sort = (opts.sort || 'for_you').toLowerCase();

  let order = `p.created_at desc, p.id desc`;
  if (sort === 'hot' || sort === 'for_you') {
    order = `(
      0.4 * least(1.0, greatest(p.score, 0)::float / 20.0)
      + 0.35 * exp(-extract(epoch from (now() - p.created_at))/3600.0 / 18.0)
      + 0.25 * case when m.id is not null then 1.0 else 0.35 end
    ) desc, p.created_at desc, p.id desc`;
  }

  const params: unknown[] = [opts.profile.id];
  let cursorClause = '';
  if (opts.cursor) {
    try {
      const raw = Buffer.from(opts.cursor, 'base64url').toString('utf8');
      const [created_at, id] = raw.split('|');
      if (created_at && id) {
        params.push(created_at, id);
        cursorClause = ` and (p.created_at, p.id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`;
      }
    } catch {
      /* ignore */
    }
  }
  params.push(limit + 1);

  const { rows } = await pool.query<any>(
    `
    select p.id, p.space_id, p.title, p.body, p.state, p.score, p.comment_count,
           p.created_at, p.edited_at, p.media_type, p.media_url, p.thumb_url,
           s.slug as space_slug, s.title as space_title,
           a.id as author_id, a.username as author_username, a.avatar_seed as author_avatar_seed,
           coalesce(v.value, 0) as my_vote
    from anonymous.posts p
    join anonymous.spaces s on s.id = p.space_id
    join anonymous.profiles a on a.id = p.author_profile_id
    left join anonymous.space_memberships m
      on m.space_id = s.id and m.anon_profile_id = $1::uuid and m.state = 'active'
    left join anonymous.votes v
      on v.target_type = 'post' and v.target_id = p.id and v.anon_profile_id = $1::uuid
    left join anonymous.blocks b
      on b.blocker_profile_id = $1::uuid and b.blocked_profile_id = p.author_profile_id
    where p.state = 'active'
      and s.status in ('active', 'read_only')
      and b.id is null
      and (
        m.id is not null
        or (s.visibility = 'adult_public' and s.admission = 'free')
      )
      and (s.visibility <> 'private' or m.id is not null)
      ${cursorClause}
    order by ${order}
    limit $${params.length}
    `,
    params
  );

  const page = rows.slice(0, limit);
  const posts: PostPublic[] = await withResolvedMediaMany(
    page.map((r) => ({
      id: r.id,
      space_id: r.space_id,
      space_slug: r.space_slug,
      space_title: r.space_title,
      author: {
        id: r.author_id,
        username: r.author_username,
        avatar_seed: r.author_avatar_seed,
      },
      title: r.title,
      body: r.body,
      state: r.state,
      score: Number(r.score) || 0,
      comment_count: Number(r.comment_count) || 0,
      created_at: iso(r.created_at)!,
      edited_at: iso(r.edited_at),
      my_vote: Number(r.my_vote) || 0,
      media_type: r.media_type ?? null,
      media_url: r.media_url ?? null,
      thumb_url: r.thumb_url ?? null,
    }))
  );

  let next_cursor: string | null = null;
  if (rows.length > limit) {
    const last = page[page.length - 1];
    next_cursor = Buffer.from(`${iso(last.created_at)}|${last.id}`, 'utf8').toString(
      'base64url'
    );
  }
  return { posts, next_cursor };
}
