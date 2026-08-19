/**
 * In-process media worker: Frame 0 posters (first displayed video frame).
 * Consumes matterya.media — never put ffmpeg work on the catalog R2 ingest topic.
 */
import { pool } from '../../db.js';
import { enqueueOutbox } from '../outbox.js';
import { createConsumer } from '../client.js';
import { kafkaConsumerGroup } from '../config.js';
import { claimProcessedEvent } from '../outbox.js';
import {
  KafkaTopics,
  MediaEventTypes,
  type DomainEvent,
  type MediaFailedPayload,
  type MediaProcessPayload,
  type MediaReadyPayload,
} from '../types.js';
import { processFrame0 } from '../../media/frame0.js';

const PROCESSABLE = new Set<string>([
  MediaEventTypes.UploadCompleted,
  MediaEventTypes.ProcessRequested,
]);

export async function startMediaConsumer(): Promise<void> {
  const groupId = `${kafkaConsumerGroup()}-media`;
  const consumer = await createConsumer(groupId);
  await consumer.subscribe({ topic: KafkaTopics.MEDIA, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) return;
      let event: DomainEvent<MediaProcessPayload>;
      try {
        event = JSON.parse(message.value.toString('utf8')) as DomainEvent<MediaProcessPayload>;
      } catch {
        return;
      }
      if (!PROCESSABLE.has(event.eventType)) return;

      const client = await pool.connect();
      let firstTime = false;
      try {
        firstTime = await claimProcessedEvent(
          client,
          groupId,
          event.eventId,
          event.eventType
        );
      } finally {
        client.release();
      }
      if (!firstTime) return;

      const p = event.payload;
      if (!p?.postId || !p?.r2Key) {
        console.warn('[kafka-media] skip: missing postId/r2Key', event.eventId);
        return;
      }

      console.log(
        `[kafka-media] ${event.eventType} post=${p.postId} key=${p.r2Key.slice(0, 80)} source=${p.source}`
      );

      try {
        const ready = await processFrame0(p);
        await emitMediaReady(ready);
        console.log(
          `[kafka-media] MediaReady post=${p.postId} outputs=${ready.outputs.length} thumb=${ready.thumbPath}`
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error('[kafka-media] failed', p.postId, msg);
        await emitMediaFailed({
          postId: p.postId,
          r2Bucket: p.r2Bucket,
          r2Key: p.r2Key,
          error: msg,
          failedAt: new Date().toISOString(),
        });
      }
    },
  });

  console.log(`✅ Kafka consumer listening on ${KafkaTopics.MEDIA} (group=${groupId}) — Frame 0`);
}

async function emitMediaReady(payload: MediaReadyPayload): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('begin');
    await enqueueOutbox(client, {
      topic: KafkaTopics.MEDIA,
      partitionKey: payload.postId,
      eventType: MediaEventTypes.Ready,
      producer: 'media-worker',
      payload: payload as unknown as Record<string, unknown>,
    });
    await client.query('commit');
  } catch (err) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    console.warn('[kafka-media] emit MediaReady failed', err);
  } finally {
    client.release();
  }
}

async function emitMediaFailed(payload: MediaFailedPayload): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('begin');
    await enqueueOutbox(client, {
      topic: KafkaTopics.MEDIA,
      partitionKey: payload.postId,
      eventType: MediaEventTypes.Failed,
      producer: 'media-worker',
      payload: payload as unknown as Record<string, unknown>,
    });
    await client.query('commit');
  } catch (err) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    console.warn('[kafka-media] emit MediaFailed failed', err);
  } finally {
    client.release();
  }
}
