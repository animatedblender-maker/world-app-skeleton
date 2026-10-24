/**
 * MIND Phase 1 contracts — Matterya names mapped from the engineering handbook.
 * Handbook alias: mind_feed_exposure → feed_video_delivery (ADR 0001).
 */

export const MIND_POLICY_VERSION = 'mind.phase1.v6';

/** Handbook FeedSurface → Matterya ledger / rank surface keys. */
export type MindSurface =
  | 'home_for_you'
  | 'hubs_for_you'
  | 'masquerade_for_you'
  | 'home_following'
  | 'sparks'
  | 'explore';

export const MIND_LEDGER_SURFACES = [
  'home_for_you',
  'hubs_for_you',
  'masquerade_for_you',
] as const;

export type MindLedgerSurface = (typeof MIND_LEDGER_SURFACES)[number];

/** Engagement types we treat as first-class for ranking (existing Kafka/PG names). */
export const MIND_POSITIVE_EVENTS = [
  'EngagementLiked',
  'EngagementSaved',
  'EngagementWatchComplete',
  'EngagementScrollDwell',
  'EngagementShared',
  'EngagementCommented',
  'EngagementHubVideoOpened',
  'EngagementPersonFollowed',
] as const;

export const MIND_NEGATIVE_EVENTS = [
  'EngagementScrollSkip',
  'EngagementHide',
  'EngagementNotInterested',
  'EngagementUnliked',
  'EngagementUnsaved',
  'EngagementPersonUnfollowed',
] as const;

export type MindDeliveryPolicy = 'ledger' | 'cursor';

export type MindFeedMeta = {
  requestId: string;
  modelVersion: string;
  deliveryPolicy: MindDeliveryPolicy;
  surface: MindSurface | string;
};

export function mindLedgerEnabled(): boolean {
  const v = process.env.MIND_LEDGER_ENABLED;
  if (v == null || v === '') return true;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

export function newMindRequestId(): string {
  return `mind_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

/** Keys never persisted from client `meta` (handbook §5 event hygiene). */
const META_DENY =
  /^(email|password|token|authorization|cookie|access_token|refresh_token|ssn|phone|raw_query|query|gps|lat|lng|latitude|longitude|exact_location)$/i;

/**
 * Strict allowlist scrub for client-provided engagement meta.
 * Drops denied keys, non-primitive nests deeper than one level, and caps size.
 */
export function sanitizeEngagementMeta(
  meta: Record<string, unknown> | null | undefined
): Record<string, unknown> | null {
  if (!meta || typeof meta !== 'object' || Array.isArray(meta)) return null;
  const out: Record<string, unknown> = {};
  let n = 0;
  for (const [k, v] of Object.entries(meta)) {
    if (n >= 24) break;
    if (!k || k.length > 40 || META_DENY.test(k)) continue;
    if (v == null) continue;
    if (typeof v === 'string') {
      out[k] = v.slice(0, 200);
      n += 1;
    } else if (typeof v === 'number' || typeof v === 'boolean') {
      out[k] = v;
      n += 1;
    }
  }
  return Object.keys(out).length ? out : null;
}

/** Client event type keys accepted by ingest (handbook taxonomy → Kafka names). */
export const MIND_CLIENT_EVENT_KEYS = [
  'like',
  'unlike',
  'comment',
  'share',
  'save',
  'unsave',
  'watch_partial',
  'watch_complete',
  'scroll_dwell',
  'scroll_skip',
  'profile_open',
  'person_follow',
  'person_unfollow',
  'hub_open',
  'hub_leave',
  'hub_shelf',
  'hub_video_open',
  'screen_open',
  'screen_leave',
  'impression',
  'ranked_served',
  'viewport_visible',
  'hide',
  'not_interested',
] as const;
