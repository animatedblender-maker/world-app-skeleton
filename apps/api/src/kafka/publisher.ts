import { pool, type PoolClient } from '../db.js';
import { getProducer } from './client.js';
import {
  kafkaPublisherBatchSize,
  kafkaPublisherIntervalMs,
} from './config.js';
import {
  claimUnpublishedOutbox,
  markOutboxFailed,
  markOutboxPublished,
} from './outbox.js';
import type { DomainEvent } from './types.js';

let timer: NodeJS.Timeout | null = null;
let running = false;
let lastDbWarnAt = 0;

/**
 * Drains public.kafka_outbox → Kafka.
 * Never crashes the process if Postgres is down / DATABASE_URL missing.
 */
export function startOutboxPublisher(): void {
  if (timer) return;
  if (!process.env.DATABASE_URL?.trim()) {
    console.warn(
      '⚠️ Kafka outbox publisher not started: DATABASE_URL is not set. ' +
        'Add it to apps/api/.env (Supabase → Settings → Database).'
    );
    return;
  }
  const interval = kafkaPublisherIntervalMs();
  timer = setInterval(() => {
    void flushOutboxOnce();
  }, interval);
  void flushOutboxOnce();
  console.log(`✅ Kafka outbox publisher every ${interval}ms`);
}

export function stopOutboxPublisher(): void {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
}

export async function flushOutboxOnce(): Promise<number> {
  if (running) return 0;
  if (!process.env.DATABASE_URL?.trim()) return 0;

  running = true;
  let client: PoolClient | undefined;
  let published = 0;
  try {
    client = await pool.connect();
    await client.query('begin');
    const rows = await claimUnpublishedOutbox(client, kafkaPublisherBatchSize());
    if (!rows.length) {
      await client.query('commit');
      return 0;
    }

    const producer = await getProducer();
    const okIds: string[] = [];

    for (const row of rows) {
      try {
        const event = normalizePayload(row.payload);
        await producer.send({
          topic: row.topic,
          messages: [
            {
              key: row.partition_key,
              value: JSON.stringify(event),
              headers: {
                eventType: row.event_type,
                eventId: row.event_id,
                eventVersion: String(row.event_version ?? 1),
              },
            },
          ],
        });
        okIds.push(row.id);
        published += 1;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        await markOutboxFailed(client, row.id, msg);
        console.warn(`[kafka-outbox] publish failed ${row.event_id}: ${msg}`);
      }
    }

    if (okIds.length) {
      await markOutboxPublished(client, okIds);
    }
    await client.query('commit');
  } catch (err) {
    if (client) {
      await client.query('rollback').catch(() => undefined);
    }
    const now = Date.now();
    if (now - lastDbWarnAt > 15_000) {
      lastDbWarnAt = now;
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(
        `[kafka-outbox] DB unavailable (will retry). Fix DATABASE_URL if needed — ${msg}`
      );
    }
  } finally {
    client?.release();
    running = false;
  }
  return published;
}

function normalizePayload(raw: unknown): DomainEvent {
  if (raw && typeof raw === 'object' && 'eventId' in (raw as object)) {
    return raw as DomainEvent;
  }
  if (typeof raw === 'string') {
    return JSON.parse(raw) as DomainEvent;
  }
  throw new Error('Invalid outbox payload');
}
