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

/** Stable 0…1 jitter so soft-recycle pages rotate instead of freezing the same tops. */
function forYouJitter(seed: string, id: string): number {
  let h = 2166136261;
  const s = `${seed}:${id}`;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return ((h >>> 0) % 10_000) / 10_000;
}

const FEED_SELECT = `
    select p.id, p.space_id, p.title, p.body, p.state, p.score, p.comment_count,
           p.created_at, p.edited_at, p.media_type, p.media_url, p.thumb_url,
           p.flagged_at, p.flag_reason,
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
        or (
          s.visibility = 'adult_public'
          and s.admission = 'free'
        )
      )`;

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
  let cursorCreatedAt: string | null = null;
  if (opts.cursor) {
    try {
      const raw = Buffer.from(opts.cursor, 'base64url').toString('utf8');
      const [created_at, id] = raw.split('|');
      if (created_at && id) {
        cursorCreatedAt = created_at;
        params.push(created_at, id);
        cursorClause = ` and (p.created_at, p.id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`;
      }
    } catch {
      /* ignore */
    }
  }

  const isForYou = sort === 'for_you';
  // Wide enough to rotate; capped so first paint stays light/fast (was 480 and felt heavy).
  const fetchLimit = useSocial
    ? isForYou
      ? Math.min(Math.max(limit * 6, 180), 260)
      : Math.min(limit * 5, 160)
    : limit + 1;
  params.push(fetchLimit);

  const { rows: recentRows } = await pool.query<any>(
    `
    ${FEED_SELECT}
      ${cursorClause}
    order by p.created_at desc, p.id desc
    limit $${params.length}
    `,
    params
  );

  // First For you page: also sample older inventory so ledger can serve beyond the newest slice.
  // Do NOT order explore by raw Reddit score — 50k–100k viral posts otherwise re-flood every page.
  let rows = recentRows as any[];
  if (isForYou && !cursorCreatedAt && recentRows.length) {
    const oldest = recentRows[recentRows.length - 1]?.created_at;
    if (oldest) {
      const exploreLimit = Math.min(240, fetchLimit);
      const half = Math.max(40, Math.floor(exploreLimit / 2));
      try {
        const { rows: olderHot } = await pool.query<any>(
          `
          ${FEED_SELECT}
            and p.created_at < $2::timestamptz
          order by ln(2 + greatest(p.score, 0)) desc, p.created_at desc
          limit $3
          `,
          [opts.profile.id, oldest, half]
        );
        // TABLESAMPLE-ish via random offset into older inventory (avoids same viral head).
        const { rows: olderRand } = await pool.query<any>(
          `
          ${FEED_SELECT}
            and p.created_at < $2::timestamptz
          order by random()
          limit $3
          `,
          [opts.profile.id, oldest, half]
        );
        const seen = new Set(rows.map((r: any) => String(r.id)));
        for (const r of [...olderRand, ...olderHot]) {
          if (seen.has(String(r.id))) continue;
          seen.add(String(r.id));
          rows.push(r);
        }
      } catch {
        /* keep recent-only pool */
      }
    }
  }

  let selected = rows as any[];

  if (useSocial && rows.length) {
    const now = Date.now();
    const viewerId = String(opts.profile.id);
    // Brief own-post sticky (≤2h, max 1) so a brand-new post isn't wiped by Hot —
    // never pin for days (that froze a real user's own card on top of For you).
    const ownPinHours = isForYou ? 2 : 6;
    const ownRows = rows.filter((r: any) => {
      if (String(r.author_id) !== viewerId) return false;
      const created = r.created_at instanceof Date ? r.created_at : new Date(r.created_at);
      const ageHours = Math.max(0, (now - created.getTime()) / 3600_000);
      return ageHours <= ownPinHours;
    });
    const ownIds = new Set(ownRows.map((r: any) => String(r.id)));

    // For you: stronger membership affinity + slightly longer half-life than Hot.
    const membershipJoined = isForYou ? 1.35 : 1;
    const membershipPublic = isForYou ? 0.28 : 0.35;
    const halfLifeHours = isForYou ? 22 : 18;
    // Soft recycle must not re-pin the same viral tops — nearly drop seen cards.
    const seenPenalty = isForYou ? 0.04 : 0.28;

    const scored = rows
      .filter((r: any) => !ownIds.has(String(r.id)))
      .map((r: any) => {
        const created = r.created_at instanceof Date ? r.created_at : new Date(r.created_at);
        const ageHours = Math.max(0, (now - created.getTime()) / 3600_000);
        const ups = Math.max(0, Number(r.score) || 0);
        const membershipBoost =
          Number(r.is_member) === 1 ? membershipJoined : membershipPublic;
        let score = socialHotScore({
          ups,
          commentCount: Number(r.comment_count) || 0,
          ageHours,
          membershipBoost,
          halfLifeHours,
        });
        // Tiny log boost from raw score — never let 98k-upvote Reddit posts own the page.
        if (isForYou) {
          score += 0.04 * Math.log1p(ups);
          // Wide per-request jitter so each open/refresh rotates when scores cluster.
          score *= 0.45 + 1.1 * forYouJitter(requestId, String(r.id));
        }
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
    const ownPinCount = isForYou ? 1 : 2;
    const rankedSlots = Math.max(1, limit + 1 - Math.min(ownRows.length, ownPinCount));
    // Always ledger — fall back to anon profile id when account link is missing
    // (seeded personas / older claims left 5k+ profiles with only ~1 link).
    const ledgerUser =
      (await resolveLedgerUserId(opts.profile.id)) ?? String(opts.profile.id);
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
          .map((c) => ({
            ...c,
            // Extra jitter on recycle so the same 12 don't stick after exhaustion.
            score: c.score * seenPenalty * (0.7 + 0.6 * forYouJitter(`${requestId}:seen`, c.id)),
          }));
        recycleCount = seen.length;
        eligible = [...fresh, ...seen];
      }
    }
    candidateMix = [
      { lane: 'masquerade_own', count: Math.min(ownRows.length, ownPinCount) },
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

    // Newest own posts first (brief window), then ranked feed (dedupe).
    const ownSorted = [...ownRows].sort((a: any, b: any) => {
      const ta = a.created_at instanceof Date ? a.created_at.getTime() : new Date(a.created_at).getTime();
      const tb = b.created_at instanceof Date ? b.created_at.getTime() : new Date(b.created_at).getTime();
      return tb - ta;
    });
    selected = [...ownSorted.slice(0, ownPinCount), ...rankedRows];
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
      flagged: !!r.flagged_at,
      flagged_at: iso(r.flagged_at),
      flag_reason: r.flag_reason ?? null,
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

/**
 * Map anonymous profile → Matterya account for the shared delivery ledger.
 * Callers must fall back to the anon profile id when this returns null —
 * most seeded/legacy profiles have no account link (links ≪ profiles).
 */
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
