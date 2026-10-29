/**
 * Masquerade search — Spaces, posts, and anonymous usernames.
 * Prefix-first matching; post hits include signed media so result cards show
 * images/videos the same way the feed does (not only after opening the post).
 * Never returns Matterya account ids / ordinary profiles.
 */
import { pool } from '../db.js';
import type { AnonymousProfilePublic } from './identity.js';
import type { PostPublic } from './content.js';
import type { SpacePublic } from './spaces.js';
import { mapSpace } from './spaces.js';
import { withResolvedMediaMany } from './media.js';

function iso(v: Date | string | null | undefined): string | null {
  if (v == null) return null;
  return v instanceof Date ? v.toISOString() : String(v);
}

function normalizeQuery(q: string): string {
  return String(q || '')
    .trim()
    .replace(/^@+/, '')
    .slice(0, 80);
}

function escapeLike(s: string): string {
  return s.replace(/[%_\\]/g, '\\$&');
}

export async function searchMasquerade(opts: {
  profile: AnonymousProfilePublic;
  q: string;
  limit?: number;
}): Promise<{
  people: AnonymousProfilePublic[];
  spaces: SpacePublic[];
  posts: PostPublic[];
}> {
  const q = normalizeQuery(opts.q);
  if (q.length < 1) {
    return { people: [], spaces: [], posts: [] };
  }
  // Keep result pages small — search is for discovery, not a feed dump.
  const limit = Math.min(Math.max(opts.limit ?? 12, 1), 24);
  const qLower = q.toLowerCase();
  const escaped = escapeLike(qLower);
  const prefix = `${escaped}%`;
  const contains = `%${escaped}%`;

  const [peopleRes, spacesRes, postsRes] = await Promise.all([
    pool.query<{
      id: string;
      username: string;
      avatar_seed: string;
      state: string;
      age_attested_at: Date | string | null;
      created_at: Date | string;
    }>(
      `
      select id, username, avatar_seed, state, age_attested_at, created_at
      from anonymous.profiles
      where state = 'active'
        and (
          normalized_username = $1
          or normalized_username like $2 escape '\\'
          or lower(username) like $2 escape '\\'
          or ($4::int >= 3 and (
            normalized_username like $3 escape '\\'
            or lower(username) like $3 escape '\\'
          ))
        )
      order by
        case when normalized_username = $1 then 0
             when normalized_username like $2 escape '\\' then 1
             else 2 end,
        created_at desc
      limit $5
      `,
      [qLower, prefix, contains, qLower.length, limit]
    ),
    pool.query<any>(
      `
      select s.id, s.slug, s.title, s.description, s.category, s.visibility, s.admission,
             s.billing_mode, s.status, s.language, s.member_count, s.post_count,
             s.owner_profile_id, s.created_at, s.updated_at,
             o.username as owner_username,
             exists(
               select 1 from anonymous.space_memberships m
               where m.space_id = s.id
                 and m.anon_profile_id = $4::uuid
                 and m.state = 'active'
             ) as is_joined
      from anonymous.spaces s
      left join anonymous.profiles o on o.id = s.owner_profile_id
      where s.status in ('active', 'read_only')
        and s.visibility = 'adult_public'
        and s.admission = 'free'
        and (
          lower(s.slug) = $1
          or lower(s.slug) like $2 escape '\\'
          or lower(s.title) like $2 escape '\\'
          or ($5::int >= 3 and (
            lower(s.title) like $3 escape '\\'
            or lower(s.slug) like $3 escape '\\'
            or lower(coalesce(s.category, '')) like $3 escape '\\'
          ))
        )
      order by
        case when lower(s.slug) = $1 then 0
             when lower(s.slug) like $2 escape '\\' or lower(s.title) like $2 escape '\\' then 1
             else 2 end,
        s.member_count desc nulls last,
        s.created_at desc
      limit $6
      `,
      [qLower, prefix, contains, opts.profile.id, qLower.length, limit]
    ),
    pool.query<any>(
      `
      select p.id, p.space_id, p.title, p.body, p.state, p.score, p.comment_count,
             p.created_at, p.edited_at, p.media_type, p.media_url, p.thumb_url,
             a.id as author_id, a.username as author_username, a.avatar_seed as author_avatar_seed,
             s.slug as space_slug, s.title as space_title
      from anonymous.posts p
      join anonymous.profiles a on a.id = p.author_profile_id
      join anonymous.spaces s on s.id = p.space_id
      where p.state = 'active'
        and s.status in ('active', 'read_only')
        and s.visibility = 'adult_public'
        and s.admission = 'free'
        and (
          lower(a.username) like $2 escape '\\'
          or lower(coalesce(p.title, '')) like $2 escape '\\'
          or lower(s.slug) like $2 escape '\\'
          or lower(s.title) like $2 escape '\\'
          or ($3::int >= 3 and (
            lower(coalesce(p.title, '')) like $1 escape '\\'
            or lower(a.username) like $1 escape '\\'
            or lower(left(p.body, 280)) like $1 escape '\\'
          ))
        )
      order by p.created_at desc
      limit $4
      `,
      [contains, prefix, qLower.length, limit]
    ),
  ]);

  const people: AnonymousProfilePublic[] = peopleRes.rows.map((r) => ({
    id: r.id,
    username: r.username,
    avatar_seed: r.avatar_seed,
    state: r.state,
    age_attested_at: iso(r.age_attested_at),
    created_at: iso(r.created_at)!,
  }));

  const spaces: SpacePublic[] = spacesRes.rows.map((row) =>
    mapSpace(row, !!row.is_joined || !!row.joined)
  );

  // Sign media for result cards — same shape as feed / space lists (≤24 rows).
  const posts: PostPublic[] = await withResolvedMediaMany(
    postsRes.rows.map((r) => ({
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
      my_vote: 0,
      media_type: r.media_type ?? null,
      media_url: r.media_url ?? null,
      thumb_url: r.thumb_url ?? null,
    }))
  );

  return { people, spaces, posts };
}
