/**
 * Interest-bubble KNN for Matterya ranking.
 *
 * Builds a fixed-length feature_vector on entity_personality from affinity maps,
 * then stores cosine-nearest neighbors in entity_neighbors for collaborative boosts.
 *
 * Bubbles = top hubs / countries / creators on the viewer's personality.
 * Ranker soft-boosts in-bubble content and neighbor co-engagement; soft-demotes outside.
 */
import { pool } from '../db.js';

export const FEATURE_VERSION = 1;
export const FEATURE_DIM = 32;
export const KNN_MODEL = 'knn-v1';
/** Neighbors kept per entity. */
export const KNN_K = 40;
/** Max active personalities scanned when rebuilding one user. */
const KNN_CANDIDATE_POOL = 800;

export type InterestBubbles = {
  hubs: Map<string, number>;
  countries: Map<string, number>;
  creators: Map<string, number>;
  media: Map<string, number>;
  eventsCounted: number;
  featureVector: number[];
};

function isUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    s
  );
}

function asAffinityMap(raw: unknown): Map<string, number> {
  const out = new Map<string, number>();
  if (!raw || typeof raw !== 'object') return out;
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    const key = String(k).trim().toLowerCase();
    if (!key) continue;
    const n = Number(v);
    if (!Number.isFinite(n) || n === 0) continue;
    out.set(key, n);
  }
  return out;
}

/** Stable hash → slot in [0, slots). */
function slotForKey(key: string, slots: number, salt = 0): number {
  let h = (2166136261 ^ salt) >>> 0;
  for (let i = 0; i < key.length; i++) {
    h ^= key.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return slots <= 0 ? 0 : h % slots;
}

/**
 * Feature vector layout (v1, length 32):
 * [0] curiosity  [1] social  [2] depth  [3] impulsiveness
 * [4] locality   [5] creator_loyalty
 * [6..15] hub affinity slots (10)
 * [16..20] media: image, video, spark, link, none
 * [21..25] country affinity slots (5)
 * [26..31] creator affinity slots (6)
 */
export function buildFeatureVector(args: {
  traits?: Record<string, unknown> | null;
  hubAffinity?: Map<string, number>;
  countryAffinity?: Map<string, number>;
  creatorAffinity?: Map<string, number>;
  mediaAffinity?: Map<string, number>;
}): number[] {
  const v = new Array<number>(FEATURE_DIM).fill(0);
  const traits = args.traits ?? {};
  const num = (k: string, d = 0.5) => {
    const n = Number((traits as any)[k]);
    return Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : d;
  };
  v[0] = num('curiosity');
  v[1] = num('social');
  v[2] = num('depth');
  v[3] = num('impulsiveness');
  v[4] = num('locality');
  v[5] = num('creator_loyalty');

  const fillSlots = (
    map: Map<string, number> | undefined,
    start: number,
    count: number,
    salt: number
  ) => {
    if (!map?.size) return;
    let max = 0;
    for (const s of map.values()) max = Math.max(max, Math.abs(s));
    if (max <= 0) return;
    for (const [key, score] of map) {
      const i = start + slotForKey(key, count, salt);
      const n = score / max;
      v[i] = Math.max(v[i], Math.max(-1, Math.min(1, n)));
    }
  };

  fillSlots(args.hubAffinity, 6, 10, 11);
  const media = args.mediaAffinity;
  if (media?.size) {
    let max = 0;
    for (const s of media.values()) max = Math.max(max, Math.abs(s));
    if (max > 0) {
      const keys = ['image', 'video', 'spark', 'link', 'none'] as const;
      keys.forEach((k, i) => {
        v[16 + i] = Math.max(-1, Math.min(1, (media.get(k) ?? 0) / max));
      });
    }
  }
  fillSlots(args.countryAffinity, 21, 5, 22);
  fillSlots(args.creatorAffinity, 26, 6, 33);

  // L2 normalize for cosine
  let norm = 0;
  for (const x of v) norm += x * x;
  norm = Math.sqrt(norm);
  if (norm > 1e-8) {
    for (let i = 0; i < v.length; i++) v[i] /= norm;
  }
  return v;
}

export function cosineDistance(a: number[], b: number[]): number {
  const n = Math.min(a.length, b.length);
  if (n === 0) return 1;
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < n; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na < 1e-12 || nb < 1e-12) return 1;
  const sim = dot / (Math.sqrt(na) * Math.sqrt(nb));
  return 1 - Math.max(-1, Math.min(1, sim));
}

/** Load viewer interest bubbles (+ feature vector) from entity_personality. */
export async function loadInterestBubbles(
  entityId: string
): Promise<InterestBubbles | null> {
  if (!entityId || !isUuid(entityId)) return null;
  try {
    const { rows } = await pool.query<{
      traits: Record<string, unknown> | null;
      country_affinity: unknown;
      hub_affinity: unknown;
      creator_affinity: unknown;
      media_affinity: unknown;
      feature_vector: number[] | null;
      events_counted: string | number | null;
    }>(
      `
      select traits, country_affinity, hub_affinity, creator_affinity, media_affinity,
             feature_vector, events_counted
      from public.entity_personality
      where entity_id = $1::uuid
      limit 1
      `,
      [entityId]
    );
    const row = rows[0];
    if (!row) return null;
    const hubs = asAffinityMap(row.hub_affinity);
    const countries = asAffinityMap(row.country_affinity);
    const creators = asAffinityMap(row.creator_affinity);
    const media = asAffinityMap(row.media_affinity);
    let featureVector = Array.isArray(row.feature_vector)
      ? row.feature_vector.map((x) => Number(x) || 0)
      : [];
    if (featureVector.length < FEATURE_DIM) {
      featureVector = buildFeatureVector({
        traits: row.traits,
        hubAffinity: hubs,
        countryAffinity: countries,
        creatorAffinity: creators,
        mediaAffinity: media,
      });
    }
    return {
      hubs,
      countries,
      creators,
      media,
      eventsCounted: Number(row.events_counted) || 0,
      featureVector,
    };
  } catch {
    return null;
  }
}

/**
 * Derive affinities from engagement when personality maps are empty,
 * then persist feature_vector on entity_personality.
 */
export async function upsertPersonalityFeatureVector(
  entityId: string
): Promise<{ ok: boolean; dim: number }> {
  if (!entityId || !isUuid(entityId)) return { ok: false, dim: 0 };

  let hub = new Map<string, number>();
  let country = new Map<string, number>();
  let creator = new Map<string, number>();
  let media = new Map<string, number>();
  let traits: Record<string, number> = {
    curiosity: 0.5,
    social: 0.5,
    depth: 0.5,
    impulsiveness: 0.5,
    locality: 0.5,
    creator_loyalty: 0.5,
  };
  let eventsCounted = 0;

  try {
    const { rows } = await pool.query<{
      traits: Record<string, unknown> | null;
      country_affinity: unknown;
      hub_affinity: unknown;
      creator_affinity: unknown;
      media_affinity: unknown;
      events_counted: string | number | null;
    }>(
      `
      select traits, country_affinity, hub_affinity, creator_affinity, media_affinity, events_counted
      from public.entity_personality
      where entity_id = $1::uuid
      `,
      [entityId]
    );
    const row = rows[0];
    if (row) {
      hub = asAffinityMap(row.hub_affinity);
      country = asAffinityMap(row.country_affinity);
      creator = asAffinityMap(row.creator_affinity);
      media = asAffinityMap(row.media_affinity);
      eventsCounted = Number(row.events_counted) || 0;
      if (row.traits && typeof row.traits === 'object') {
        for (const k of Object.keys(traits)) {
          const n = Number((row.traits as any)[k]);
          if (Number.isFinite(n)) traits[k] = Math.max(0, Math.min(1, n));
        }
      }
    }
  } catch {
    /* table missing */
  }

  // Fill empty maps from recent engagement facts.
  if (hub.size === 0 || country.size === 0 || creator.size === 0) {
    try {
      const { rows } = await pool.query<{
        hub_slug: string | null;
        country_code: string | null;
        author_id: string | null;
        media_type: string | null;
        is_spark: boolean | null;
        s: number;
      }>(
        `
        select
          lower(nullif(trim(hub_slug), '')) as hub_slug,
          lower(nullif(trim(country_code), '')) as country_code,
          author_id::text,
          lower(nullif(trim(media_type), '')) as media_type,
          is_spark,
          sum(strength)::real as s
        from public.entity_engagement_events
        where entity_id = $1::uuid
          and occurred_at > now() - interval '45 days'
          and strength <> 0
        group by 1, 2, 3, 4, 5
        `,
        [entityId]
      );
      for (const r of rows) {
        const s = Number(r.s) || 0;
        if (!s) continue;
        if (r.hub_slug) hub.set(r.hub_slug, (hub.get(r.hub_slug) ?? 0) + s);
        if (r.country_code) {
          country.set(r.country_code, (country.get(r.country_code) ?? 0) + s);
        }
        if (r.author_id) {
          creator.set(r.author_id, (creator.get(r.author_id) ?? 0) + s);
        }
        const mt = r.is_spark ? 'spark' : r.media_type || 'none';
        media.set(mt, (media.get(mt) ?? 0) + s);
      }
      eventsCounted = Math.max(eventsCounted, rows.length);
    } catch {
      /* ignore */
    }
  }

  const topN = (m: Map<string, number>, n: number) => {
    const entries = [...m.entries()].sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]));
    const sliced = entries.slice(0, n);
    let max = 0;
    for (const [, s] of sliced) max = Math.max(max, Math.abs(s));
    const out: Record<string, number> = {};
    for (const [k, s] of sliced) {
      out[k] = max > 0 ? s / max : s;
    }
    return out;
  };

  const vector = buildFeatureVector({
    traits,
    hubAffinity: hub,
    countryAffinity: country,
    creatorAffinity: creator,
    mediaAffinity: media,
  });

  try {
    await pool.query(
      `
      insert into public.entity_personality as t (
        entity_id, traits, country_affinity, hub_affinity, creator_affinity, media_affinity,
        feature_vector, feature_version, events_counted, updated_at, model_version
      )
      values (
        $1::uuid, $2::jsonb, $3::jsonb, $4::jsonb, $5::jsonb, $6::jsonb,
        $7::real[], $8, $9, now(), 'rules-v1+knn'
      )
      on conflict (entity_id) do update set
        country_affinity = case
          when coalesce(jsonb_typeof(t.country_affinity), 'null') = 'object'
            and t.country_affinity <> '{}'::jsonb
          then t.country_affinity else excluded.country_affinity end,
        hub_affinity = case
          when coalesce(jsonb_typeof(t.hub_affinity), 'null') = 'object'
            and t.hub_affinity <> '{}'::jsonb
          then t.hub_affinity else excluded.hub_affinity end,
        creator_affinity = case
          when coalesce(jsonb_typeof(t.creator_affinity), 'null') = 'object'
            and t.creator_affinity <> '{}'::jsonb
          then t.creator_affinity else excluded.creator_affinity end,
        media_affinity = case
          when coalesce(jsonb_typeof(t.media_affinity), 'null') = 'object'
            and t.media_affinity <> '{}'::jsonb
          then t.media_affinity else excluded.media_affinity end,
        feature_vector = excluded.feature_vector,
        feature_version = excluded.feature_version,
        events_counted = greatest(t.events_counted, excluded.events_counted),
        updated_at = now(),
        model_version = excluded.model_version
      `,
      [
        entityId,
        JSON.stringify(traits),
        JSON.stringify(topN(country, 20)),
        JSON.stringify(topN(hub, 20)),
        JSON.stringify(topN(creator, 40)),
        JSON.stringify(topN(media, 10)),
        vector,
        FEATURE_VERSION,
        eventsCounted,
      ]
    );
    return { ok: true, dim: vector.length };
  } catch {
    return { ok: false, dim: 0 };
  }
}

/** Rebuild cosine-KNN neighbors for one entity. */
export async function rebuildNeighborsForEntity(
  entityId: string,
  k = KNN_K
): Promise<{ neighbors: number }> {
  if (!entityId || !isUuid(entityId)) return { neighbors: 0 };
  await upsertPersonalityFeatureVector(entityId);

  let selfVec: number[] | null = null;
  try {
    const { rows } = await pool.query<{ feature_vector: number[] | null }>(
      `
      select feature_vector
      from public.entity_personality
      where entity_id = $1::uuid
      limit 1
      `,
      [entityId]
    );
    const fv = rows[0]?.feature_vector;
    if (Array.isArray(fv) && fv.length >= 8) {
      selfVec = fv.map((x) => Number(x) || 0);
    }
  } catch {
    return { neighbors: 0 };
  }
  if (!selfVec) return { neighbors: 0 };

  type Cand = { id: string; vector: number[] };
  const cands: Cand[] = [];
  try {
    const { rows } = await pool.query<{
      entity_id: string;
      feature_vector: number[] | null;
    }>(
      `
      select entity_id::text, feature_vector
      from public.entity_personality
      where entity_id <> $1::uuid
        and feature_vector is not null
        and cardinality(feature_vector) >= 8
        and updated_at > now() - interval '90 days'
      order by updated_at desc
      limit $2
      `,
      [entityId, KNN_CANDIDATE_POOL]
    );
    for (const r of rows) {
      if (!Array.isArray(r.feature_vector)) continue;
      cands.push({
        id: r.entity_id,
        vector: r.feature_vector.map((x) => Number(x) || 0),
      });
    }
  } catch {
    return { neighbors: 0 };
  }

  const scored = cands
    .map((c) => ({ id: c.id, distance: cosineDistance(selfVec!, c.vector) }))
    .filter((c) => Number.isFinite(c.distance))
    .sort((a, b) => a.distance - b.distance)
    .slice(0, Math.min(Math.max(k, 1), 80));

  try {
    await pool.query(`delete from public.entity_neighbors where entity_id = $1::uuid`, [
      entityId,
    ]);
    for (const n of scored) {
      await pool.query(
        `
        insert into public.entity_neighbors (entity_id, neighbor_id, distance, model_version, updated_at)
        values ($1::uuid, $2::uuid, $3::real, $4, now())
        on conflict (entity_id, neighbor_id) do update set
          distance = excluded.distance,
          model_version = excluded.model_version,
          updated_at = now()
        `,
        [entityId, n.id, n.distance, KNN_MODEL]
      );
    }
  } catch {
    return { neighbors: 0 };
  }
  return { neighbors: scored.length };
}

/** Neighbor IDs ordered by similarity (low distance). */
export async function loadNeighborIds(
  entityId: string,
  limit = KNN_K
): Promise<string[]> {
  if (!entityId || !isUuid(entityId)) return [];
  try {
    const { rows } = await pool.query<{ neighbor_id: string }>(
      `
      select neighbor_id::text
      from public.entity_neighbors
      where entity_id = $1::uuid
      order by distance asc
      limit $2
      `,
      [entityId, Math.min(Math.max(limit, 1), 80)]
    );
    return rows.map((r) => r.neighbor_id).filter(Boolean);
  } catch {
    return [];
  }
}

/**
 * Collaborative signal: creators / content that neighbors engaged positively.
 * Returns creatorId → boost and contentId → boost.
 */
export async function loadNeighborEngagementBoosts(
  entityId: string
): Promise<{ creators: Map<string, number>; content: Map<string, number> }> {
  const creators = new Map<string, number>();
  const content = new Map<string, number>();
  const neighbors = await loadNeighborIds(entityId, 30);
  if (!neighbors.length) return { creators, content };

  try {
    const { rows } = await pool.query<{
      author_id: string | null;
      content_id: string | null;
      s: number;
    }>(
      `
      select author_id::text, content_id::text, sum(strength)::real as s
      from public.entity_engagement_events
      where entity_id = any($1::uuid[])
        and strength > 0
        and occurred_at > now() - interval '21 days'
      group by author_id, content_id
      having sum(strength) > 0.4
      order by s desc
      limit 400
      `,
      [neighbors]
    );
    for (const r of rows) {
      const s = Math.min(3, Number(r.s) || 0);
      if (r.author_id) {
        creators.set(r.author_id, Math.max(creators.get(r.author_id) ?? 0, s));
      }
      if (r.content_id) {
        content.set(r.content_id, Math.max(content.get(r.content_id) ?? 0, s));
      }
    }
  } catch {
    /* ignore */
  }
  return { creators, content };
}

/** Bubble match score in [0, 1] for a post against viewer affinities. */
export function bubbleMatchScore(
  bubbles: InterestBubbles | null,
  post: {
    authorId?: string | null;
    countryCode?: string | null;
    hubSlug?: string | null;
    mediaType?: string | null;
    isSpark?: boolean;
  }
): { score: number; inBubble: boolean; reasons: string[] } {
  if (!bubbles || bubbles.eventsCounted < 8) {
    return { score: 0.35, inBubble: true, reasons: ['cold_start'] };
  }
  let a = 0;
  const reasons: string[] = [];
  const cc = (post.countryCode ?? '').trim().toLowerCase();
  const hub = (post.hubSlug ?? '').trim().toLowerCase();
  const author = (post.authorId ?? '').trim();
  const media = post.isSpark
    ? 'spark'
    : (post.mediaType ?? 'none').trim().toLowerCase();

  if (cc && bubbles.countries.has(cc)) {
    a += 0.4 * Math.min(1, Math.abs(bubbles.countries.get(cc)!));
    reasons.push('country_bubble');
  }
  if (hub && bubbles.hubs.has(hub)) {
    a += 0.3 * Math.min(1, Math.abs(bubbles.hubs.get(hub)!));
    reasons.push('hub_bubble');
  }
  if (author && bubbles.creators.has(author)) {
    a += 0.25 * Math.min(1, Math.abs(bubbles.creators.get(author)!));
    reasons.push('creator_bubble');
  }
  if (media && bubbles.media.has(media)) {
    a += 0.1 * Math.min(1, Math.abs(bubbles.media.get(media)!));
    reasons.push('media_bubble');
  }

  const score = Math.max(0, Math.min(1, a));
  // Soft bubble: in-bubble if any affinity hit or cold; exploration still allowed.
  const inBubble = reasons.length > 0 || score >= 0.15;
  return { score, inBubble, reasons };
}
