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
