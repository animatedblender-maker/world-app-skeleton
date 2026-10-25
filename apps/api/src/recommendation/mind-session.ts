/**
 * MIND-017 — Short-TTL session features for in-session re-rank.
 * Aggregates recent engagement for (entity, session) and blends into rank.
 */
import { pool } from '../db.js';

export function mindSessionFeaturesEnabled(): boolean {
  const v = process.env.MIND_SESSION_FEATURES_ENABLED;
  if (v == null || v === '') return true;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

export type SessionFeatures = {
  hubs: Map<string, number>;
  countries: Map<string, number>;
  creators: Map<string, number>;
  media: Map<string, number>;
  eventsCounted: number;
  sessionId: string;
};

type CacheEntry = { at: number; features: SessionFeatures };
const cache = new Map<string, CacheEntry>();
const TTL_MS = 60_000;

const POS = new Set([
  'EngagementLiked',
  'EngagementSaved',
  'EngagementWatchComplete',
  'EngagementScrollDwell',
  'EngagementShared',
  'EngagementCommented',
  'EngagementHubVideoOpened',
]);

export async function loadSessionFeatures(
  entityId: string,
  sessionId: string | null | undefined
): Promise<SessionFeatures | null> {
  if (!mindSessionFeaturesEnabled()) return null;
  const sid = String(sessionId ?? '').trim().slice(0, 128);
  if (!entityId || !sid) return null;

  const ck = `${entityId}|${sid}`;
  const hit = cache.get(ck);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.features;

  const features: SessionFeatures = {
    hubs: new Map(),
    countries: new Map(),
    creators: new Map(),
    media: new Map(),
    eventsCounted: 0,
    sessionId: sid,
  };

  try {
    const { rows } = await pool.query<{
      event_type: string;
      author_id: string | null;
      strength: number;
      hub_slug: string | null;
      country_code: string | null;
      media_type: string | null;
      is_reel: boolean | null;
    }>(
      `
      select e.event_type, e.author_id::text, e.strength,
             p.hub_slug, p.country_code, p.media_type, p.is_reel
      from public.entity_engagement_events e
      left join public.posts p on p.id = e.content_id
      where e.entity_id = $1::uuid
        and e.session_id = $2
        and e.occurred_at > now() - interval '90 minutes'
      order by e.occurred_at desc
      limit 200
      `,
      [entityId, sid]
    );
    features.eventsCounted = rows.length;
    for (const r of rows) {
      const pos = POS.has(r.event_type) || Number(r.strength) > 0;
      const w = pos ? Math.abs(Number(r.strength) || 0.5) : -Math.abs(Number(r.strength) || 0.3);
      if (r.author_id) {
        features.creators.set(
          r.author_id,
          (features.creators.get(r.author_id) ?? 0) + w
        );
      }
      const hub = (r.hub_slug ?? '').trim().toLowerCase();
      if (hub) features.hubs.set(hub, (features.hubs.get(hub) ?? 0) + w);
      const cc = (r.country_code ?? '').trim().toLowerCase();
      if (cc) features.countries.set(cc, (features.countries.get(cc) ?? 0) + w);
      const media = r.is_reel
        ? 'spark'
        : (r.media_type ?? '').trim().toLowerCase() || 'none';
      features.media.set(media, (features.media.get(media) ?? 0) + w);
    }
  } catch {
    /* ignore */
  }

  cache.set(ck, { at: Date.now(), features });
  if (cache.size > 2000) {
    const first = cache.keys().next().value;
    if (first) cache.delete(first);
  }
  return features;
}

/** Soft match score in [0, ~1.2] for a post against session features. */
export function sessionMatchScore(
  session: SessionFeatures | null,
  post: {
    authorId?: string | null;
    countryCode?: string | null;
    hubSlug?: string | null;
    mediaType?: string | null;
    isSpark?: boolean;
  }
): { score: number; hit: boolean } {
  if (!session || session.eventsCounted < 2) return { score: 0, hit: false };
  let a = 0;
  const hub = (post.hubSlug ?? '').trim().toLowerCase();
  const cc = (post.countryCode ?? '').trim().toLowerCase();
  const author = (post.authorId ?? '').trim();
  const media = post.isSpark
    ? 'spark'
    : (post.mediaType ?? 'none').trim().toLowerCase();

  if (hub && session.hubs.has(hub)) {
    a += 0.35 * Math.min(1, Math.abs(session.hubs.get(hub)!));
  }
  if (cc && session.countries.has(cc)) {
    a += 0.3 * Math.min(1, Math.abs(session.countries.get(cc)!));
  }
  if (author && session.creators.has(author)) {
    a += 0.4 * Math.min(1, Math.abs(session.creators.get(author)!));
  }
  if (media && session.media.has(media)) {
    a += 0.15 * Math.min(1, Math.abs(session.media.get(media)!));
  }
  return { score: Math.max(0, Math.min(1.2, a)), hit: a > 0.05 };
}

export function bustSessionCache(entityId: string, sessionId?: string | null): void {
  if (sessionId) {
    cache.delete(`${entityId}|${sessionId}`);
    return;
  }
  for (const k of cache.keys()) {
    if (k.startsWith(`${entityId}|`)) cache.delete(k);
  }
}
