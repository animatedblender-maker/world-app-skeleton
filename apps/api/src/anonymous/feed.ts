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
import {
  MIND_POLICY_VERSION,
  mindLedgerEnabled,
  newMindRequestId,
  type MindDeliveryPolicy,
  type MindFeedMeta,
} from '../recommendation/mind-contracts.js';
import type { CandidateMix } from '../recommendation/mind-candidates.js';
import { assertSurfaceNamespace } from '../recommendation/mind-isolation.js';

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
 * Feed from joined Spaces + public (adult_public + free) Spaces only.
 * Restricted / private / paid Spaces never appear unless the viewer is an active member.
 * For you / hot: Wilson + time decay + membership → MMR diversity → at-most-once delivery.
 */
export async function getFeed(opts: {
  profile: AnonymousProfilePublic;
  sort: string;
  cursor?: string | null;
  limit: number;
}): Promise<{
  posts: PostPublic[];
  next_cursor: string | null;
  mind?: MindFeedMeta & { candidateMix?: CandidateMix[] };
}> {
  const limit = Math.min(Math.max(opts.limit || 20, 1), 50);
  const sort = (opts.sort || 'for_you').toLowerCase();
  const useSocial = sort === 'hot' || sort === 'for_you';
  const requestId = newMindRequestId();
  let deliveryPolicy: MindDeliveryPolicy = 'cursor';
  assertSurfaceNamespace('masquerade_for_you', 'masquerade');
  let candidateMix: CandidateMix[] = [];

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
        -- Joined: include that Space's posts (private / restricted / paid ok).
        m.id is not null
        -- Not joined: public Spaces only — never restricted/private/paid.
        or (
          s.visibility = 'adult_public'
          and s.admission = 'free'
        )
      )
      ${cursorClause}
    order by p.created_at desc, p.id desc
    limit $${params.length}
    `,
    params
  );

  let selected = rows as any[];

  if (useSocial && rows.length) {
    const now = Date.now();
    const viewerId = String(opts.profile.id);
    const isForYou = sort === 'for_you';
    // Keep the viewer's own posts at the top for ~3 days — Hot/ledger was wiping
    // brand-new score-0 posts on the next soft refresh (showed once, then gone).
    const ownRows = rows.filter((r: any) => {
      if (String(r.author_id) !== viewerId) return false;
      const created = r.created_at instanceof Date ? r.created_at : new Date(r.created_at);
      const ageHours = Math.max(0, (now - created.getTime()) / 3600_000);
      return ageHours <= 72;
    });
    const ownIds = new Set(ownRows.map((r: any) => String(r.id)));

    // For you: stronger membership affinity + slightly longer half-life than Hot.
    const membershipJoined = isForYou ? 1.35 : 1;
    const membershipPublic = isForYou ? 0.28 : 0.35;
    const halfLifeHours = isForYou ? 22 : 18;
    const seenPenalty = isForYou ? 0.18 : 0.28;

    const scored = rows
      .filter((r: any) => !ownIds.has(String(r.id)))
      .map((r: any) => {
        const created = r.created_at instanceof Date ? r.created_at : new Date(r.created_at);
        const ageHours = Math.max(0, (now - created.getTime()) / 3600_000);
        const ups = Math.max(0, Number(r.score) || 0);
        const membershipBoost =
          Number(r.is_member) === 1 ? membershipJoined : membershipPublic;
        const score = socialHotScore({
          ups,
          commentCount: Number(r.comment_count) || 0,
          ageHours,
          membershipBoost,
          halfLifeHours,
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

    // Prefer never-seen keys, but always fill a full page.
    // Soft recycle only when unviewed inventory is short — seen cards get a
    // hard score penalty so fresh content still wins MMR (MIND §2 / §11).
    const rankedSlots = Math.max(1, limit + 1 - Math.min(ownRows.length, 3));
    const ledgerUser = await resolveLedgerUserId(opts.profile.id);
    let eligible = scored;
    let freshCount = scored.length;
    let recycleCount = 0;
    if (ledgerUser && mindLedgerEnabled()) {
      const delivered = await loadDeliveredCanonicalKeys(
        ledgerUser,
        'masquerade_for_you'
      );
      const fresh = scored.filter((c) => !delivered.has(c.mediaKey));
      freshCount = fresh.length;
      if (fresh.length >= rankedSlots) {
        eligible = fresh;
      } else {
        const seen = scored
          .filter((c) => delivered.has(c.mediaKey))
          .map((c) => ({ ...c, score: c.score * seenPenalty }));
        recycleCount = seen.length;
        eligible = [...fresh, ...seen];
      }
    }
    candidateMix = [
      { lane: 'masquerade_own', count: Math.min(ownRows.length, 3) },
      { lane: 'masquerade_fresh', count: freshCount },
      { lane: 'masquerade_soft_recycle', count: recycleCount },
    ];

    // Prefer fresh text/video mix — image-only Reddit packs were freezing the top of Hot.
    // For you: slightly higher MMR diversity so Spaces/creators rotate more.
    const picked = mmrPick(eligible, {
      limit: rankedSlots,
      lambda: isForYou ? 0.68 : 0.72,
      maxSameCreator: 1,
      creatorWindow: isForYou ? 12 : 10,
      // Big Spaces (e.g. HighlyStrange) must not own the whole first page.
      maxSameSpace: isForYou ? 1 : 2,
      spaceWindow: isForYou ? 12 : 10,
      exclusiveFamilies: ['tiktok', 'image', 'video'],
      // Image/video at most ~1 in 4 so media cards cannot pin the whole first page.
      exclusiveEveryN: 4,
    });

    // Serve full MMR page (never shrink on partial reserve). Await ledger so
    // deliveryPolicy is truthful and concurrent tabs share the same reservations.
    let rankedRows = picked.slice(0, rankedSlots).map((c) => c.row);
    if (ledgerUser && picked.length && mindLedgerEnabled()) {
      try {
        const reserved = await reserveDeliveryBatch({
          userId: ledgerUser,
          surface: 'masquerade_for_you',
          idempotencyKey: `masq:${opts.profile.id}:${requestId}`,
          candidates: picked.slice(0, rankedSlots).map((c) => ({
            id: c.id,
            canonicalKey: c.mediaKey,
          })),
          limit: rankedSlots,
        });
        if (reserved && reserved.videoIds.length) {
          deliveryPolicy = 'ledger';
          const byId = new Map(picked.map((c) => [c.id, c]));
          const reservedOrdered = reserved.videoIds
            .map((id) => byId.get(id)?.row)
            .filter((r): r is (typeof picked)[number]['row'] => !!r);
          const reservedSet = new Set(reserved.videoIds);
          const fill = picked
            .filter((c) => !reservedSet.has(c.id))
            .map((c) => c.row);
          rankedRows = [...reservedOrdered, ...fill].slice(0, rankedSlots);
        } else {
          deliveryPolicy = 'cursor';
        }
      } catch {
        deliveryPolicy = 'cursor';
      }
    }

    // Newest own posts first, then ranked feed (dedupe).
    const ownSorted = [...ownRows].sort((a: any, b: any) => {
      const ta = a.created_at instanceof Date ? a.created_at.getTime() : new Date(a.created_at).getTime();
      const tb = b.created_at instanceof Date ? b.created_at.getTime() : new Date(b.created_at).getTime();
      return tb - ta;
    });
    selected = [...ownSorted.slice(0, 3), ...rankedRows];
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
  return {
    posts,
    next_cursor,
    mind: {
      requestId,
      modelVersion: MIND_POLICY_VERSION,
      deliveryPolicy,
      surface: 'masquerade_for_you',
      candidateMix,
    },
  };
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
