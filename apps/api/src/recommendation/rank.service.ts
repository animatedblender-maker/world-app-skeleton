/**
 * Server-side recommendation ranker (scale path).
 *
 * Planes:
 *  - Events: entity_engagement_events (+ Kafka matterya.engagement)
 *  - Features: entity_personality, recsys_user_creator_affinity, recsys_item_stats
 *  - Rank: multi-source score + diversity re-rank
 *  - Log: recommendation_decisions (warehouse fact)
 *
 * Not a toy client shuffle — this is the serving contract clients call as we scale.
 */
import { randomUUID } from 'node:crypto';
import { pool } from '../db.js';

export type RankSurface =
  | 'home_for_you'
  | 'home_following'
  | 'sparks'
  | 'hubs_for_you'
  | 'explore';

export type RankRequest = {
  entityId: string;
  surface: RankSurface | string;
  candidateIds: string[];
  sessionId?: string | null;
  followingIds?: string[];
  limit?: number;
};

export type RankedItem = {
  id: string;
  score: number;
  sources: string[];
};

export type RankResponse = {
  requestId: string;
  policyVersion: string;
  surface: string;
  items: RankedItem[];
  latencyMs: number;
  featureHits: {
    affinityCreators: number;
    itemStats: number;
    personality: boolean;
  };
};

const POLICY_VERSION = 'server.v2';

/** Short-lived rank cache — same candidate set within ~20s reuses work (feed soft-rerank). */
const RANK_CACHE_TTL_MS = 20_000;
const rankCache = new Map<
  string,
  { at: number; response: RankResponse }
>();

function rankCacheKey(input: RankRequest): string {
  const ids = (input.candidateIds ?? []).slice(0, 120).join(',');
  return `${input.entityId}|${input.surface}|${input.limit ?? 48}|${ids}`;
}

const POSITIVE_TYPES = new Set([
  'EngagementLiked',
  'EngagementSaved',
  'EngagementWatchComplete',
  'EngagementScrollDwell',
  'EngagementShared',
  'EngagementCommented',
  'EngagementHubVideoOpened',
  'EngagementPersonFollowed',
]);

const NEGATIVE_TYPES = new Set([
  'EngagementScrollSkip',
  'EngagementHide',
  'EngagementNotInterested',
  'EngagementUnliked',
  'EngagementUnsaved',
  'EngagementPersonUnfollowed',
]);

function isUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    s
  );
}

/**
 * Rank candidate post IDs for a user + surface.
 * Unknown IDs are kept at the end with low score (client may mix non-UUID hub seeds).
 */
export async function rankCandidates(input: RankRequest): Promise<RankResponse> {
  const started = Date.now();
  const requestId = randomUUID();
  const entityId = String(input.entityId ?? '').trim();
  const surface = String(input.surface ?? 'home_for_you').slice(0, 40);
  const limit = Math.min(Math.max(Number(input.limit) || 48, 1), 200);
  const sessionId = input.sessionId ? String(input.sessionId).slice(0, 128) : null;

  const rawIds = Array.isArray(input.candidateIds)
    ? input.candidateIds.map((id) => String(id).trim()).filter(Boolean)
    : [];
  // Dedupe preserve order
  const seen = new Set<string>();
  const candidateIds: string[] = [];
  for (const id of rawIds) {
    if (seen.has(id)) continue;
    seen.add(id);
    candidateIds.push(id);
    if (candidateIds.length >= 500) break;
  }

  if (!entityId || candidateIds.length === 0) {
    return {
      requestId,
      policyVersion: POLICY_VERSION,
      surface,
      items: candidateIds.slice(0, limit).map((id) => ({
        id,
        score: 0,
        sources: ['passthrough'],
      })),
      latencyMs: Date.now() - started,
      featureHits: { affinityCreators: 0, itemStats: 0, personality: false },
    };
  }

  // Cache hit — IG-class: soft re-rank must be sub-50ms when candidates unchanged.
  const ck = rankCacheKey({
    entityId,
    surface,
    candidateIds,
    sessionId,
    followingIds: input.followingIds,
    limit,
  });
  const cached = rankCache.get(ck);
  if (cached && Date.now() - cached.at < RANK_CACHE_TTL_MS) {
    return {
      ...cached.response,
      requestId,
      latencyMs: Date.now() - started,
    };
  }

  const following = new Set(
    (input.followingIds ?? []).map((x) => String(x).trim()).filter(Boolean)
  );
  const uuidCandidates = candidateIds.filter(isUuid);

  // Parallel feature reads
  const [affinityMap, itemStats, postMeta, hidden] = await Promise.all([
    loadCreatorAffinity(entityId),
    loadItemStats(uuidCandidates),
    loadPostMeta(uuidCandidates),
    loadHiddenContent(entityId),
  ]);

  type Scored = {
    id: string;
    score: number;
    sources: string[];
    authorId: string | null;
  };

  const scored: Scored[] = [];
  for (const id of candidateIds) {
    if (hidden.has(id)) continue;

    const meta = postMeta.get(id);
    const authorId = meta?.authorId ?? null;
    const sources: string[] = [];
    let score = 0.01;

    // Following relationship
    if (authorId && following.has(authorId)) {
      score += 3.0;
      sources.push('following');
    }

    // Personalized creator affinity
    if (authorId && affinityMap.has(authorId)) {
      const a = affinityMap.get(authorId)!;
      score += Math.max(-2, Math.min(4, a * 2.2));
      sources.push('affinity');
    }

    // Global item quality (cold start / social proof) — stronger weight in v2
    const st = itemStats.get(id);
    if (st) {
      score += Math.max(-1.5, Math.min(3.2, st * 1.15));
      sources.push('item_stats');
    }

    // Freshness from created_at
    if (meta?.createdAt) {
      const ageH = (Date.now() - meta.createdAt.getTime()) / 3_600_000;
      if (ageH < 24) {
        score += 1.2 - ageH / 24;
        sources.push('fresh');
      } else if (ageH < 168) {
        score += 0.3;
      }
    }

    // Surface policy tweaks
    if (surface === 'home_following') {
      if (!(authorId && following.has(authorId))) {
        score -= 10; // hard soft-block non-follows
      } else {
        score += 1;
      }
    }
    if (surface === 'sparks') {
      if (meta?.isSpark === false) score -= 2.5;
      else if (meta?.isSpark === true) {
        score += 0.6;
        sources.push('surface_fit');
      }
    }
    if ((surface === 'hubs_for_you' || surface.includes('hubs')) && meta?.isSpark) {
      score -= 1.5;
    }

    if (sources.length === 0) sources.push('explore');

    scored.push({ id, score, sources, authorId });
  }

  // Sort by score, then greedy diversity (creator window)
  scored.sort((a, b) => b.score - a.score);
  const picked = greedyDiversity(scored, limit, surface === 'sparks' ? 1 : 2, 8);

  const latencyMs = Date.now() - started;

  // Fire-and-forget warehouse log + optional affinity refresh
  void logDecision({
    requestId,
    entityId,
    surface,
    sessionId,
    candidateCount: candidateIds.length,
    items: picked,
    latencyMs,
  }).catch(() => {});

  // Keep personality warm while traffic is live
  if (Math.random() < 0.15) {
    void refreshUserFeatures(entityId).catch(() => {});
  }

  const response: RankResponse = {
    requestId,
    policyVersion: POLICY_VERSION,
    surface,
    items: picked.map((p) => ({
      id: p.id,
      score: Math.round(p.score * 1000) / 1000,
      sources: p.sources,
    })),
    latencyMs,
    featureHits: {
      affinityCreators: affinityMap.size,
      itemStats: itemStats.size,
      personality: affinityMap.size > 0,
    },
  };

  rankCache.set(ck, { at: Date.now(), response });
  // Bound memory
  if (rankCache.size > 500) {
    const first = rankCache.keys().next().value;
    if (first) rankCache.delete(first);
  }

  return response;
}

function greedyDiversity(
  scored: {
    id: string;
    score: number;
    sources: string[];
    authorId: string | null;
  }[],
  limit: number,
  maxSameCreator: number,
  window: number
) {
  const out: typeof scored = [];
  const used = new Set<string>();
  const remaining = [...scored];

  while (out.length < limit && remaining.length) {
    let bestI = -1;
    let bestM = -Infinity;
    for (let i = 0; i < remaining.length; i++) {
      const c = remaining[i];
      if (used.has(c.id)) continue;
      let m = c.score;
      const recent = out.slice(-window);
      const same = recent.filter((x) => x.authorId && x.authorId === c.authorId).length;
      if (same >= maxSameCreator) m -= 8;
      else if (same > 0) m -= same * 1.5;
      if (out.length && out[out.length - 1].authorId === c.authorId) m -= 4;
      if (m > bestM) {
        bestM = m;
        bestI = i;
      }
    }
    if (bestI < 0) break;
    const [pick] = remaining.splice(bestI, 1);
    used.add(pick.id);
    out.push(pick);
  }
  return out;
}

async function loadCreatorAffinity(entityId: string): Promise<Map<string, number>> {
  const map = new Map<string, number>();
  try {
    const { rows } = await pool.query<{ creator_id: string; score: number }>(
      `
      select creator_id::text, score
      from public.recsys_user_creator_affinity
      where entity_id = $1::uuid
      order by score desc
      limit 400
      `,
      [entityId]
    );
    for (const r of rows) map.set(r.creator_id, Number(r.score) || 0);
  } catch {
    // table may not exist until migration
  }

  // Fallback: derive from recent engagement if affinity empty
  if (map.size === 0) {
    try {
      const { rows } = await pool.query<{ author_id: string; s: number }>(
        `
        select author_id::text, sum(strength)::real as s
        from public.entity_engagement_events
        where entity_id = $1::uuid
          and author_id is not null
          and occurred_at > now() - interval '30 days'
        group by author_id
        order by s desc
        limit 200
        `,
        [entityId]
      );
      for (const r of rows) {
        if (r.author_id) map.set(r.author_id, Number(r.s) || 0);
      }
    } catch {
      /* ignore */
    }
  }
  return map;
}

async function loadItemStats(ids: string[]): Promise<Map<string, number>> {
  const map = new Map<string, number>();
  if (!ids.length) return map;
  try {
    const { rows } = await pool.query<{ content_id: string; quality_score: number }>(
      `
      select content_id::text, quality_score
      from public.recsys_item_stats
      where content_id = any($1::uuid[])
      `,
      [ids]
    );
    for (const r of rows) map.set(r.content_id, Number(r.quality_score) || 0);
  } catch {
    /* ignore */
  }
  return map;
}

async function loadPostMeta(
  ids: string[]
): Promise<
  Map<string, { authorId: string | null; createdAt: Date | null; isSpark: boolean }>
> {
  const map = new Map<
    string,
    { authorId: string | null; createdAt: Date | null; isSpark: boolean }
  >();
  if (!ids.length) return map;
  try {
    const { rows } = await pool.query<{
      id: string;
      author_id: string | null;
      created_at: Date;
      is_reel: boolean | null;
      media_type: string | null;
    }>(
      `
      select id::text, author_id::text, created_at, is_reel, media_type
      from public.posts
      where id = any($1::uuid[])
      `,
      [ids]
    );
    for (const r of rows) {
      map.set(r.id, {
        authorId: r.author_id,
        createdAt: r.created_at ? new Date(r.created_at) : null,
        isSpark: !!(r.is_reel || r.media_type === 'reel' || r.media_type === 'spark'),
      });
    }
  } catch {
    /* ignore */
  }
  return map;
}

async function loadHiddenContent(entityId: string): Promise<Set<string>> {
  const set = new Set<string>();
  try {
    const { rows } = await pool.query<{ content_id: string }>(
      `
      select content_id::text
      from public.entity_engagement_events
      where entity_id = $1::uuid
        and event_type in ('EngagementHide', 'EngagementNotInterested')
        and content_id is not null
        and occurred_at > now() - interval '90 days'
      limit 2000
      `,
      [entityId]
    );
    for (const r of rows) if (r.content_id) set.add(r.content_id);
  } catch {
    /* ignore */
  }
  return set;
}

async function logDecision(args: {
  requestId: string;
  entityId: string;
  surface: string;
  sessionId: string | null;
  candidateCount: number;
  items: { id: string; score: number; sources: string[] }[];
  latencyMs: number;
}): Promise<void> {
  const uuidItems = args.items.filter((i) => isUuid(i.id));
  try {
    await pool.query(
      `
      insert into public.recommendation_decisions (
        request_id, entity_id, surface, policy_version, session_id,
        candidate_count, served_count, item_ids, scores, sources, latency_ms, meta
      )
      values (
        $1, $2::uuid, $3, $4, $5,
        $6, $7, $8::uuid[], $9::real[], $10::jsonb, $11, $12::jsonb
      )
      `,
      [
        args.requestId,
        args.entityId,
        args.surface,
        POLICY_VERSION,
        args.sessionId,
        args.candidateCount,
        uuidItems.length,
        uuidItems.map((i) => i.id),
        uuidItems.map((i) => i.score),
        JSON.stringify(uuidItems.map((i) => ({ id: i.id, sources: i.sources }))),
        args.latencyMs,
        JSON.stringify({ nonUuidDropped: args.items.length - uuidItems.length }),
      ]
    );
  } catch {
    /* migration not applied yet */
  }
}

/**
 * Roll engagement facts → online features (affinity + item stats + personality stub).
 * Safe to call often; designed for post-ingest + cron.
 */
export async function refreshUserFeatures(entityId: string): Promise<{ ok: boolean }> {
  if (!entityId || !isUuid(entityId)) return { ok: false };

  try {
    // Creator affinity from 30d window
    await pool.query(
      `
      insert into public.recsys_user_creator_affinity as t
        (entity_id, creator_id, score, positive_events, negative_events, last_event_at, updated_at)
      select
        entity_id,
        author_id as creator_id,
        sum(strength)::real as score,
        count(*) filter (where strength > 0)::int,
        count(*) filter (where strength < 0)::int,
        max(occurred_at),
        now()
      from public.entity_engagement_events
      where entity_id = $1::uuid
        and author_id is not null
        and occurred_at > now() - interval '30 days'
      group by entity_id, author_id
      on conflict (entity_id, creator_id) do update set
        score = excluded.score,
        positive_events = excluded.positive_events,
        negative_events = excluded.negative_events,
        last_event_at = excluded.last_event_at,
        updated_at = now()
      `,
      [entityId]
    );
  } catch {
    /* table missing */
  }

  try {
    // Touch personality row so reports / future models have a home
    await pool.query(
      `
      insert into public.entity_personality (entity_id, events_counted, window_end, updated_at, model_version)
      select
        $1::uuid,
        count(*)::bigint,
        max(occurred_at),
        now(),
        'rules-v1'
      from public.entity_engagement_events
      where entity_id = $1::uuid
        and occurred_at > now() - interval '30 days'
      on conflict (entity_id) do update set
        events_counted = excluded.events_counted,
        window_end = excluded.window_end,
        updated_at = now(),
        model_version = 'rules-v1'
      `,
      [entityId]
    );
  } catch {
    /* ignore */
  }

  return { ok: true };
}

/**
 * Aggregate global item stats from engagement (batch job / cron).
 */
export async function refreshItemStats(hours = 72): Promise<{ updated: number }> {
  const h = Math.min(Math.max(hours, 1), 720);
  try {
    const { rowCount } = await pool.query(
      `
      insert into public.recsys_item_stats as t
        (content_id, impressions, dwells, likes, hides, not_interested, watch_complete, quality_score, updated_at)
      select
        content_id,
        count(*) filter (where event_type in ('EngagementImpression', 'EngagementViewportVisible'))::bigint,
        count(*) filter (where event_type = 'EngagementScrollDwell')::bigint,
        count(*) filter (where event_type = 'EngagementLiked')::bigint,
        count(*) filter (where event_type = 'EngagementHide')::bigint,
        count(*) filter (where event_type = 'EngagementNotInterested')::bigint,
        count(*) filter (where event_type = 'EngagementWatchComplete')::bigint,
        (
          coalesce(sum(strength) filter (where strength > 0), 0)
          - coalesce(sum(abs(strength)) filter (where strength < 0), 0) * 1.2
        )::real,
        now()
      from public.entity_engagement_events
      where content_id is not null
        and occurred_at > now() - make_interval(hours => $1::int)
      group by content_id
      on conflict (content_id) do update set
        impressions = excluded.impressions,
        dwells = excluded.dwells,
        likes = excluded.likes,
        hides = excluded.hides,
        not_interested = excluded.not_interested,
        watch_complete = excluded.watch_complete,
        quality_score = excluded.quality_score,
        updated_at = now()
      `,
      [h]
    );
    return { updated: rowCount ?? 0 };
  } catch {
    return { updated: 0 };
  }
}

// silence unused lint for sets used as documentation of taxonomy
void POSITIVE_TYPES;
void NEGATIVE_TYPES;
