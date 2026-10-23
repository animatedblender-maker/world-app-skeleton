import { pool } from '../db.js';
import type { AnonymousProfilePublic } from './identity.js';
import type { PostPublic } from './content.js';
import { withResolvedMediaMany } from './media.js';
import {
  canonicalVideoKey,
  loadDeliveredCanonicalKeys,
  reserveDeliveryBatch,
} from '../recommendation/delivery.service.js';
import { mmrPick, socialHotScore } from '../recommendation/social-score.js';

function iso(v: Date | string | null | undefined): string | null {
  if (v == null) return null;
  return v instanceof Date ? v.toISOString() : String(v);
}

function masqueradeFamily(row: {
  media_type?: string | null;
  media_url?: string | null;
  thumb_url?: string | null;
}): string {
  const mt = String(row.media_type ?? '').toLowerCase();
  if (mt === 'video') return 'video';
  if (mt === 'image' || mt === 'gif' || mt === 'photo') return 'image';
  const blob = `${row.media_url ?? ''}\n${row.thumb_url ?? ''}`.toLowerCase();
  if (/(?:united_states|germany|albania|egypt|kosovo)\/\d{8,}\//i.test(blob)) {
    return 'tiktok';
  }
  return 'text';
}

/**
 * Feed from joined Spaces + adult_public Spaces.
 * For you / hot: Wilson + time decay + membership → MMR diversity → at-most-once delivery.
 */
export async function getFeed(opts: {
  profile: AnonymousProfilePublic;
  sort: string;
  cursor?: string | null;
  limit: number;
}): Promise<{ posts: PostPublic[]; next_cursor: string | null }> {
  const limit = Math.min(Math.max(opts.limit || 20, 1), 50);
  const sort = (opts.sort || 'for_you').toLowerCase();
  const useSocial = sort === 'hot' || sort === 'for_you';

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

  // Over-fetch for social ranking; new/chrono stays tight.
  const fetchLimit = useSocial ? Math.min(limit * 6, 180) : limit + 1;
  params.push(fetchLimit);

  const { rows } = await pool.query<any>(
    `
    select p.id, p.space_id, p.title, p.body, p.state, p.score, p.comment_count,
           p.created_at, p.edited_at, p.media_type, p.media_url, p.thumb_url,
           s.slug as space_slug, s.title as space_title,
           a.id as author_id, a.username as author_username, a.avatar_seed as author_avatar_seed,
           coalesce(v.value, 0) as my_vote,
           case when m.id is not null then 1 else 0 end as is_member
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
    order by p.created_at desc, p.id desc
    limit $${params.length}
    `,
    params
  );

  let selected = rows as any[];

  if (useSocial && rows.length) {
    const now = Date.now();
    const scored = rows.map((r: any) => {
      const created = r.created_at instanceof Date ? r.created_at : new Date(r.created_at);
      const ageHours = Math.max(0, (now - created.getTime()) / 3600_000);
      const ups = Math.max(0, Number(r.score) || 0);
      const membershipBoost = Number(r.is_member) === 1 ? 1 : 0.35;
      const score = socialHotScore({
        ups,
        commentCount: Number(r.comment_count) || 0,
        ageHours,
        membershipBoost,
        halfLifeHours: 18,
      });
      return {
        row: r,
        id: String(r.id),
        score,
        authorId: String(r.author_id ?? ''),
        family: masqueradeFamily(r),
        mediaKey: canonicalVideoKey({
          id: String(r.id),
          media_url: r.media_url,
          thumb_url: r.thumb_url,
          media_type: r.media_type,
        }),
        spaceId: String(r.space_id ?? ''),
      };
    });

    // At-most-once: drop already delivered canonical keys for this masquerade profile.
    // Ledger is keyed by Matterya account when available; fall back to anon profile id.
    const ledgerUser = await resolveLedgerUserId(opts.profile.id);
    let eligible = scored;
    if (ledgerUser) {
      const delivered = await loadDeliveredCanonicalKeys(ledgerUser, 'masquerade_for_you');
      eligible = scored.filter((c) => !delivered.has(c.mediaKey));
    }

    const picked = mmrPick(eligible, {
      limit: limit + 1,
      lambda: 0.7,
      maxSameCreator: 2,
      creatorWindow: 8,
      exclusiveFamilies: ['tiktok', 'image', 'video'],
      exclusiveEveryN: 3,
    });

    if (ledgerUser && picked.length) {
      const reserved = await reserveDeliveryBatch({
        userId: ledgerUser,
        surface: 'masquerade_for_you',
        idempotencyKey: `masq:${opts.profile.id}:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`,
        candidates: picked.slice(0, limit).map((c) => ({
          id: c.id,
          canonicalKey: c.mediaKey,
        })),
        limit,
      });
      if (reserved?.videoIds?.length) {
        const byId = new Map(picked.map((c) => [c.id, c]));
        selected = reserved.videoIds
          .map((id) => byId.get(id)?.row)
          .filter(Boolean);
      } else {
        selected = picked.slice(0, limit + 1).map((c) => c.row);
      }
    } else {
      selected = picked.slice(0, limit + 1).map((c) => c.row);
    }
  }

  const page = selected.slice(0, limit);
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
  if (selected.length > limit || (useSocial && page.length >= limit)) {
    const last = page[page.length - 1];
    if (last) {
      next_cursor = Buffer.from(`${iso(last.created_at)}|${last.id}`, 'utf8').toString(
        'base64url'
      );
    }
  }
  return { posts, next_cursor };
}

/** Map anonymous profile → Matterya account for the shared delivery ledger. */
async function resolveLedgerUserId(anonProfileId: string): Promise<string | null> {
  try {
    const { rows } = await pool.query<{ account_id: string }>(
      `
      select account_id::text as account_id
      from identity_vault.account_anonymous_links
      where anon_profile_id = $1::uuid
      limit 1
      `,
      [anonProfileId]
    );
    return rows[0]?.account_id ?? null;
  } catch {
    return null;
  }
}
