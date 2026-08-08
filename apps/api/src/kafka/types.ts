/** Canonical domain event envelope for Matterya Kafka topics. */
export type DomainEvent<TPayload = Record<string, unknown>> = {
  eventId: string;
  eventType: string;
  eventVersion: number;
  occurredAt: string;
  producer: string;
  partitionKey: string;
  correlationId?: string | null;
  payload: TPayload;
};

export const KafkaTopics = {
  MESSAGES: 'matterya.messages',
  POSTS: 'matterya.posts',
  ENGAGEMENT: 'matterya.engagement',
  FOLLOWS: 'matterya.follows',
  CALLS: 'matterya.calls',
  NOTIFICATIONS: 'matterya.notifications',
  DLQ: 'matterya.dlq',
} as const;

export type KafkaTopic = (typeof KafkaTopics)[keyof typeof KafkaTopics];

export type MessageSentPayload = {
  messageId: string;
  conversationId: string;
  senderId: string;
  body: string;
  mediaType?: string | null;
  mediaPath?: string | null;
  senderName: string;
  preview: string;
  recipientIds: string[];
  isCallLog: boolean;
  isReaction: boolean;
};

export type MessageEditedPayload = {
  messageId: string;
  conversationId: string;
  senderId: string;
  body: string;
  preview: string;
};

export type MessageDeletedPayload = {
  messageId: string;
  conversationId: string;
  senderId: string;
};

export const MessageEventTypes = {
  Sent: 'MessageSent',
  Edited: 'MessageEdited',
  Deleted: 'MessageDeleted',
} as const;

/** Content lifecycle on matterya.posts */
export const ContentEventTypes = {
  Drafted: 'ContentDrafted',
  Posted: 'ContentPosted',
  Updated: 'ContentUpdated',
  Deleted: 'ContentDeleted',
  Shared: 'ContentShared',
} as const;

/**
 * Attention + explicit engagement on matterya.engagement.
 * Watch live in Redpanda Console → Topics → matterya.engagement → Messages.
 */
export const EngagementEventTypes = {
  Liked: 'EngagementLiked',
  Unliked: 'EngagementUnliked',
  Commented: 'EngagementCommented',
  Shared: 'EngagementShared',
  Saved: 'EngagementSaved',
  Unsaved: 'EngagementUnsaved',
  WatchPartial: 'EngagementWatchPartial',
  WatchComplete: 'EngagementWatchComplete',
  ScrollDwell: 'EngagementScrollDwell',
  ScrollSkip: 'EngagementScrollSkip',
  ProfileOpened: 'EngagementProfileOpened',
  /** Followed another person */
  PersonFollowed: 'EngagementPersonFollowed',
  PersonUnfollowed: 'EngagementPersonUnfollowed',
  /** Opened / left Hubs tab or a hub shelf */
  HubOpened: 'EngagementHubOpened',
  HubLeft: 'EngagementHubLeft',
  HubShelfSelected: 'EngagementHubShelfSelected',
  HubVideoOpened: 'EngagementHubVideoOpened',
  /** Generic surface open (feed, search, globe, messages, …) */
  ScreenOpened: 'EngagementScreenOpened',
  ScreenLeft: 'EngagementScreenLeft',
} as const;

export type EngagementPayload = {
  entityId: string;
  contentId?: string | null;
  authorId?: string | null;
  countryCode?: string | null;
  hubSlug?: string | null;
  mediaType?: string | null;
  isSpark?: boolean;
  /** 0..1 interest strength (negative allowed for skips). */
  strength: number;
  durationMs?: number | null;
  progress?: number | null;
  sessionId?: string | null;
  surface?: string | null;
  deviceClass?: string | null;
  /** Free-form extra for debugging (keep small). */
  meta?: Record<string, unknown> | null;
};

/**
 * Fired on every platform publish (feed / Spark / Hubs channel / share).
 * Also mirrored into entity_engagement_events for the admin Uploads report tab.
 */
export type ContentPostedPayload = {
  /** Who performed the upload (actor / posted_by). */
  entityId: string;
  contentId: string;
  /** Channel owner or post author (may differ from actor for admin publishes). */
  authorId?: string | null;
  mediaType?: string | null;
  visibility?: string | null;
  countryCode?: string | null;
  countryName?: string | null;
  cityName?: string | null;
  hubSlug?: string | null;
  isSpark?: boolean;
  isHubLongForm?: boolean;
  isMoment?: boolean;
  sharedPostId?: string | null;
  channelId?: string | null;
  channelName?: string | null;
  /** owner | admin when published to a Hubs channel */
  channelRole?: string | null;
  title?: string | null;
  /** Plain-language line for the report, e.g. "Maya uploaded a Spark to Matterya Sparks from Germany". */
  summary: string;
  surface?: string | null;
  mediaUrl?: string | null;
  /** feed | hubs | sparks | share | moment | backend */
  destination?: string | null;
};
