import { disconnectKafka, ensureTopics, getProducer } from './client.js';
import { kafkaEnabled } from './config.js';
import { startEngagementConsumer } from './consumers/engagement.consumer.js';
import { startMediaConsumer } from './consumers/media.consumer.js';
import { startMessagesConsumer } from './consumers/messages.consumer.js';
import { startR2IngestConsumer } from './consumers/r2-ingest.consumer.js';
import { startOutboxPublisher, stopOutboxPublisher } from './publisher.js';

let started = false;

/**
 * Frame 0 compute: prefer zero-worker (CLI backfill + client upload).
 * In-process Kafka consumer is opt-in emergency only when FRAME0_ZERO_WORKER is off
 * and MEDIA_WORKER_INPROCESS=true.
 */
function mediaWorkerInProcess(): boolean {
  const zero = (process.env.FRAME0_ZERO_WORKER ?? '').trim().toLowerCase();
  if (zero === '1' || zero === 'true' || zero === 'yes') return false;
  const raw = (process.env.MEDIA_WORKER_INPROCESS ?? 'false').trim().toLowerCase();
  return raw === '1' || raw === 'true' || raw === 'yes';
}

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
      await startR2IngestConsumer();
      // Frame 0: zero-worker by default (CLI backfill + client). Opt-in Kafka consumer only.
      if (mediaWorkerInProcess()) {
        await startMediaConsumer();
        console.log('   Media Frame 0: in-process consumer (MEDIA_WORKER_INPROCESS=true)');
      } else {
        console.log(
          '   Media Frame 0: zero-worker (CLI backfill / client upload — no permanent ffmpeg consumer)'
        );
      }
    } else {
      console.warn(
        '⚠️ Kafka consumers not started: DATABASE_URL is not set. ' +
          'Add Supabase DB URL to apps/api/.env, then restart.'
      );
    }
    console.log('✅ Kafka broker connected (outbox/consumer need DATABASE_URL for full pipeline)');
    console.log('   Live engagement: topic matterya.engagement');
    console.log('   R2 ingest jobs: topic matterya.r2.ingest');
    console.log('   Media Frame 0 topic: matterya.media');
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
  R2IngestEventTypes,
  MediaEventTypes,
} from './types.js';
export type {
  MessageSentPayload,
  MessageEditedPayload,
  MessageDeletedPayload,
  EngagementPayload,
  ContentPostedPayload,
  R2IngestRequestedPayload,
  MediaProcessPayload,
  MediaReadyPayload,
  MediaFailedPayload,
} from './types.js';
