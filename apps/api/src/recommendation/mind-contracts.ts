/**
 * MIND Phase 1 contracts — Matterya names mapped from the engineering handbook.
 * Handbook alias: mind_feed_exposure → feed_video_delivery (ADR 0001).
 */

export const MIND_POLICY_VERSION = 'mind.phase1.v2';

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
