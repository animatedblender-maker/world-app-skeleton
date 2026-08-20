/**
 * Enqueue Frame 0 / media processing jobs onto matterya.media via Kafka outbox.
 */
import { pool } from '../db.js';
import { kafkaEnabled } from '../kafka/config.js';
import { enqueueOutbox } from '../kafka/outbox.js';
import {
  KafkaTopics,
  MediaEventTypes,
  type MediaProcessPayload,
  type MediaRequestedOutputs,
  type MediaSourceKind,
} from '../kafka/types.js';
import { getBucket } from '../content-pipeline/r2.js';

export type EnqueueMediaJobInput = {
  postId: string;
  r2Key: string;
  r2Bucket?: string;
  mediaPath?: string | null;
  source: MediaSourceKind;
  requestedOutputs?: MediaRequestedOutputs;
  requestedBy?: string;
  /** When true, also emit media.upload.completed (same payload). Default: ProcessRequested only. */
  asUploadCompleted?: boolean;
};

/**
 * Best-effort enqueue. Never throws into catalog ingest.
 * Returns enqueued=false when Kafka off or DB outbox fails.
 */
/** Zero-worker mode: Frame 0 via CLI / client only — do not enqueue Kafka media jobs. */
export function frame0ZeroWorkerMode(): boolean {
  const raw = (process.env.FRAME0_ZERO_WORKER ?? '').trim().toLowerCase();
  return raw === '1' || raw === 'true' || raw === 'yes';
}

export async function enqueueMediaProcessJob(
  input: EnqueueMediaJobInput
): Promise<{ enqueued: boolean; eventId?: string; error?: string }> {
  if (frame0ZeroWorkerMode()) {
    return { enqueued: false, error: 'frame0_zero_worker' };
  }
  if (!kafkaEnabled()) {
    return { enqueued: false, error: 'kafka_disabled' };
  }
  const r2Key = input.r2Key.replace(/^\/+/, '').trim();
  if (!input.postId || !r2Key) {
    return { enqueued: false, error: 'missing_postId_or_r2Key' };
  }

  const payload: MediaProcessPayload = {
    postId: input.postId,
    r2Bucket: (input.r2Bucket || getBucket()).trim(),
    r2Key,
    source: input.source,
    requestedOutputs: input.requestedOutputs ?? 'frame0',
    mediaPath: input.mediaPath ?? `r2:${input.r2Bucket || getBucket()}/${r2Key}`,
    requestedBy: input.requestedBy ?? 'api',
    requestedAt: new Date().toISOString(),
  };

  const client = await pool.connect();
  try {
    await client.query('begin');
    const eventType = input.asUploadCompleted
      ? MediaEventTypes.UploadCompleted
      : MediaEventTypes.ProcessRequested;
    const event = await enqueueOutbox(client, {
      topic: KafkaTopics.MEDIA,
      partitionKey: input.postId,
      eventType,
      producer: 'media-pipeline',
      payload: payload as unknown as Record<string, unknown>,
    });
    await client.query('commit');
    console.log(`[media] enqueued ${eventType} post=${input.postId} key=${r2Key.slice(0, 80)}`);
    return { enqueued: true, eventId: event.eventId };
  } catch (err: unknown) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    const msg = err instanceof Error ? err.message : String(err);
    console.warn('[media] enqueue failed', msg);
    return { enqueued: false, error: msg };
  } finally {
    client.release();
  }
}
