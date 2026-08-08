import type { EachMessagePayload } from 'kafkajs';
import { createConsumer } from '../client.js';
import { kafkaConsumerGroup } from '../config.js';
import { KafkaTopics } from '../types.js';

/**
 * Lightweight live logger for matterya.engagement.
 * Open API logs while using the app, or watch Redpanda Console for the same messages.
 */
export async function startEngagementConsumer(): Promise<void> {
  const groupId = `${kafkaConsumerGroup()}-engagement-live`;
  const consumer = await createConsumer(groupId);
  await consumer.subscribe({ topic: KafkaTopics.ENGAGEMENT, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ message }: EachMessagePayload) => {
      try {
        const raw = message.value?.toString('utf8');
        if (!raw) return;
        const event = JSON.parse(raw) as {
          eventType?: string;
          eventId?: string;
          partitionKey?: string;
          payload?: {
            entityId?: string;
            contentId?: string;
            strength?: number;
            durationMs?: number;
            surface?: string;
            progress?: number;
            summary?: string;
            meta?: { summary?: string };
          };
        };
        const p = event.payload ?? {};
        const labels: Record<string, string> = {
          EngagementLiked: 'Liked a post',
          EngagementUnliked: 'Removed a like',
          EngagementCommented: 'Left a comment',
          EngagementShared: 'Shared a post',
          EngagementSaved: 'Saved a post',
          EngagementWatchPartial: 'Watched part of a video',
          EngagementWatchComplete: 'Watched a video to the end',
          EngagementScrollDwell: 'Stopped and looked at a post',
          EngagementScrollSkip: 'Scrolled past a post',
          EngagementProfileOpened: 'Opened a profile',
          ContentPosted: 'Uploaded content',
          ContentShared: 'Shared content',
        };
        const action =
          (typeof p.summary === 'string' && p.summary.trim()) ||
          (typeof p.meta?.summary === 'string' && p.meta.summary.trim()) ||
          labels[event.eventType ?? ''] ||
          event.eventType ||
          '?';
        const when = new Date().toISOString();
        const bits = [
          when,
          action,
          `person=${(p.entityId ?? event.partitionKey ?? '').slice(0, 8)}…`,
          p.contentId ? `post=${String(p.contentId).slice(0, 8)}…` : null,
          p.durationMs != null ? `looked ${p.durationMs}ms` : null,
          p.progress != null ? `${Math.round(Number(p.progress) * 100)}% video` : null,
          p.surface ? `in ${p.surface}` : null,
        ].filter(Boolean);
        console.log(`[live activity] ${bits.join(' · ')}`);
      } catch {
        console.warn('[kafka-live] engagement message parse failed');
      }
    },
  });

  console.log(
    `✅ Kafka consumer listening on ${KafkaTopics.ENGAGEMENT} (group=${groupId}) — live signals`
  );
}
