import { disconnectKafka, ensureTopics, getProducer } from './client.js';
import { kafkaEnabled } from './config.js';
import { startEngagementConsumer } from './consumers/engagement.consumer.js';
import { startMessagesConsumer } from './consumers/messages.consumer.js';
import { startOutboxPublisher, stopOutboxPublisher } from './publisher.js';

let started = false;

/**
 * Boot Kafka outbox publisher + consumers when KAFKA_ENABLED=true.
 * Safe no-op when disabled so local/prod without brokers still works.
 */
export async function startKafkaPipeline(): Promise<void> {
  if (!kafkaEnabled()) {
    console.log('ℹ️  Kafka pipeline disabled (set KAFKA_ENABLED=true to enable)');
    return;
  }
  if (started) return;
  started = true;

  try {
    await ensureTopics();
    await getProducer();
    startOutboxPublisher();
    if (process.env.DATABASE_URL?.trim()) {
      await startMessagesConsumer();
      await startEngagementConsumer();
    } else {
      console.warn(
        '⚠️ Kafka consumers not started: DATABASE_URL is not set. ' +
          'Add Supabase DB URL to apps/api/.env, then restart.'
      );
    }
    console.log('✅ Kafka broker connected (outbox/consumer need DATABASE_URL for full pipeline)');
    console.log('   Live engagement: topic matterya.engagement (Console UI or API [kafka-live] logs)');
  } catch (err) {
    started = false;
    console.error('❌ Kafka pipeline failed to start — API continues without it', err);
    console.error(
      '   Check KAFKA_BROKERS and that Redpanda is up: npm run kafka:up (from repo root)'
    );
  }
}

export async function stopKafkaPipeline(): Promise<void> {
  stopOutboxPublisher();
  await disconnectKafka();
  started = false;
}

export { kafkaEnabled, kafkaShadowMode } from './config.js';
export { enqueueOutbox } from './outbox.js';
export {
  KafkaTopics,
  MessageEventTypes,
  EngagementEventTypes,
  ContentEventTypes,
} from './types.js';
export type {
  MessageSentPayload,
  MessageEditedPayload,
  MessageDeletedPayload,
  EngagementPayload,
  ContentPostedPayload,
} from './types.js';
