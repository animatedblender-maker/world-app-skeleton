/**
 * Dedicated Frame 0 / media worker process.
 *
 * Runs ONLY:
 *  - Kafka outbox publisher (MediaReady / MediaFailed)
 *  - matterya.media consumer (ffmpeg Frame 0 → R2 → thumb_url)
 *
 * Does NOT start the GraphQL API or catalog R2 ingest consumer.
 *
 *   npm run start:media-worker
 *   docker build -f Dockerfile.media-worker -t matterya-media-worker .
 *
 * @see docs/MEDIA_FRAME0.md
 */
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { disconnectKafka, ensureTopics, getProducer } from '../kafka/client.js';
import { kafkaEnabled } from '../kafka/config.js';
import { startMediaConsumer } from '../kafka/consumers/media.consumer.js';
import { startOutboxPublisher, stopOutboxPublisher } from '../kafka/publisher.js';
import { ffmpegAvailable } from './frame0.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '..', '.env'), override: true });

async function main(): Promise<void> {
  console.log('🎬 matterya-media-worker starting…');

  if (!kafkaEnabled()) {
    console.error('❌ KAFKA_ENABLED must be true for the media worker');
    process.exit(1);
  }
  if (!process.env.DATABASE_URL?.trim()) {
    console.error('❌ DATABASE_URL is required (outbox + posts.thumb_url updates)');
    process.exit(1);
  }

  const hasFf = await ffmpegAvailable();
  if (!hasFf) {
    console.error('❌ ffmpeg not on PATH — use Dockerfile.media-worker image');
    process.exit(1);
  }
  console.log('✅ ffmpeg available');

  // Always use a dedicated identity (API uses matterya-api-workers).
  // Consumer code appends "-media" → group matterya-media-worker-media.
  process.env.KAFKA_CLIENT_ID = 'matterya-media-worker';
  process.env.KAFKA_CONSUMER_GROUP = 'matterya-media-worker';

  await ensureTopics();
  await getProducer();
  startOutboxPublisher();
  await startMediaConsumer();

  console.log('✅ matterya-media-worker ready (topic matterya.media — Frame 0)');
  console.log(`   clientId=${process.env.KAFKA_CLIENT_ID}`);
  console.log(`   consumerGroup=${process.env.KAFKA_CONSUMER_GROUP}`);
}

async function shutdown(signal: string): Promise<void> {
  console.log(`[media-worker] ${signal} — shutting down`);
  stopOutboxPublisher();
  await disconnectKafka();
  process.exit(0);
}

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));

main().catch((err) => {
  console.error('❌ matterya-media-worker failed to start', err);
  process.exit(1);
});
