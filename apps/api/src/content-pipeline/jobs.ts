import { pool } from '../db.js';
import { kafkaEnabled } from '../kafka/config.js';
import { enqueueOutbox } from '../kafka/outbox.js';
import {
  ContentEventTypes,
  KafkaTopics,
  R2IngestEventTypes,
  type R2IngestRequestedPayload,
} from '../kafka/types.js';
import { r2Configured } from './r2.js';
import { runContentPipeline } from './run.js';
import type { PipelineOptions, PipelineStats } from './types.js';

/** Last run snapshot for the ops page (process memory). */
let lastRun: {
  at: string;
  stats: PipelineStats;
  source: string;
} | null = null;

let running = false;

export function getPipelineStatus() {
  const publicBase = process.env.R2_PUBLIC_BASE_URL?.trim() || '';
  // When set, pipeline + GraphQL write permanent public URLs (no X-Amz expiry).
  // When unset, falls back to 7-day presigned GETs.
  return {
    running,
    r2Configured: r2Configured(),
    r2PublicBaseConfigured: publicBase.length > 0,
    r2PublicBaseHost: publicBase
      ? (() => {
          try {
            return new URL(publicBase).host;
          } catch {
            return 'invalid';
          }
        })()
      : null,
    mediaUrlMode: publicBase ? 'public_permanent' : 'presigned_7d',
    kafkaEnabled: kafkaEnabled(),
    lastRun,
  };
}

/**
 * Enqueue a pipeline tick on Kafka (matterya.r2.ingest).
 * Returns true if enqueued; false if Kafka off / outbox failed (caller should run inline).
 */
export async function enqueueR2IngestJob(
  opts: PipelineOptions & { requestedBy?: string } = {}
): Promise<{ enqueued: boolean; eventId?: string; error?: string }> {
  if (!kafkaEnabled()) {
    return { enqueued: false, error: 'kafka_disabled' };
  }
  const client = await pool.connect();
  try {
    await client.query('begin');
    const payload: R2IngestRequestedPayload = {
      dryRun: !!opts.dryRun,
      resignOnly: !!opts.resignOnly,
      ingestOnly: !!opts.ingestOnly,
      maxOriginals: opts.maxOriginals,
      maxShares: opts.maxShares,
      maxResign: opts.maxResign,
      maxMs: opts.maxMs,
      requestedBy: opts.requestedBy ?? 'api',
      requestedAt: new Date().toISOString(),
    };
    const event = await enqueueOutbox(client, {
      topic: KafkaTopics.R2_INGEST,
      partitionKey: 'r2-global',
      eventType: R2IngestEventTypes.Requested,
      producer: 'content-pipeline',
      payload: payload as unknown as Record<string, unknown>,
    });
    await client.query('commit');
    console.log(`[r2-ingest] enqueued ${event.eventId} via Kafka outbox`);
    return { enqueued: true, eventId: event.eventId };
  } catch (err: any) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    const msg = err?.message ?? String(err);
    console.warn('[r2-ingest] enqueue failed', msg);
    return { enqueued: false, error: msg };
  } finally {
    client.release();
  }
}

/**
 * Run the pipeline now (blocks). Records lastRun for the ops page.
 * Always safe without Kafka — still emits ContentPosted via emitContentPosted → outbox when Kafka/DB ok.
 */
export async function runPipelineNow(
  opts: PipelineOptions & { source?: string } = {}
): Promise<PipelineStats> {
  if (running) {
    return {
      ok: false,
      dryRun: !!opts.dryRun,
      discovered: 0,
      insertedOriginals: 0,
      insertedShares: 0,
      frame0Done: 0,
      frame0Failed: 0,
      repairedCaptions: 0,
      repairedComments: 0,
      skippedNoOwner: 0,
      skippedExisting: 0,
      skippedIncomplete: 0,
      resigned: 0,
      errors: ['pipeline_already_running'],
      ms: 0,
    };
  }
  running = true;
  try {
    const stats = await runContentPipeline(opts);
    lastRun = {
      at: new Date().toISOString(),
      stats,
      source: opts.source ?? 'inline',
    };
    // Announce completion on Kafka when enabled (best-effort).
    if (kafkaEnabled() && !opts.dryRun) {
      void publishIngestCompleted(stats, opts.source ?? 'inline');
    }
    return stats;
  } finally {
    running = false;
  }
}

/**
 * Preferred entry for cron + ops page:
 * - If Kafka on → enqueue job (consumer runs pipeline)
 * - Else → run inline
 * - forceInline: always run in this process (ops page “Run now”)
 */
export async function requestPipelineRun(
  opts: PipelineOptions & { requestedBy?: string; forceInline?: boolean; source?: string } = {}
): Promise<{
  mode: 'kafka' | 'inline';
  eventId?: string;
  stats?: PipelineStats;
  error?: string;
}> {
  if (!opts.forceInline && kafkaEnabled()) {
    const q = await enqueueR2IngestJob(opts);
    if (q.enqueued) {
      return { mode: 'kafka', eventId: q.eventId };
    }
    // Fall through to inline if enqueue failed.
  }
  const stats = await runPipelineNow({
    ...opts,
    source: opts.source ?? opts.requestedBy ?? 'inline',
  });
  return { mode: 'inline', stats, error: stats.ok ? undefined : stats.errors[0] };
}

async function publishIngestCompleted(stats: PipelineStats, source: string): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('begin');
    await enqueueOutbox(client, {
      topic: KafkaTopics.R2_INGEST,
      partitionKey: 'r2-global',
      eventType: R2IngestEventTypes.Completed,
      producer: 'content-pipeline',
      payload: {
        source,
        ...stats,
        completedAt: new Date().toISOString(),
      } as unknown as Record<string, unknown>,
    });
    // Also a lightweight posts-side signal for ops/metrics consumers.
    await enqueueOutbox(client, {
      topic: KafkaTopics.POSTS,
      partitionKey: 'r2-ingest',
      eventType: ContentEventTypes.Updated,
      producer: 'content-pipeline',
      payload: {
        summary: `R2 pipeline: +${stats.insertedOriginals} originals, +${stats.insertedShares} shares, ${stats.resigned} resigned`,
        insertedOriginals: stats.insertedOriginals,
        insertedShares: stats.insertedShares,
        resigned: stats.resigned,
        source,
      } as unknown as Record<string, unknown>,
    });
    await client.query('commit');
  } catch (err) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    console.warn('[r2-ingest] completed event failed', err);
  } finally {
    client.release();
  }
}
