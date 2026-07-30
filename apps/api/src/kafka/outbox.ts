import { randomUUID } from 'node:crypto';
import type { PoolClient } from '../db.js';
import type { DomainEvent, KafkaTopic } from './types.js';

export type EnqueueOutboxInput<TPayload = Record<string, unknown>> = {
  topic: KafkaTopic | string;
  partitionKey: string;
  eventType: string;
  payload: TPayload;
  eventVersion?: number;
  correlationId?: string | null;
  producer?: string;
  /** Optional fixed event id (defaults to new UUID). */
  eventId?: string;
};

/**
 * Insert a domain event into kafka_outbox on the same transaction as a business write.
 * Must be called with the mutation's PoolClient before commit.
 */
export async function enqueueOutbox<TPayload extends Record<string, unknown>>(
  client: PoolClient,
  input: EnqueueOutboxInput<TPayload>
): Promise<DomainEvent<TPayload>> {
  const eventId = input.eventId ?? randomUUID();
  const occurredAt = new Date().toISOString();
  const event: DomainEvent<TPayload> = {
    eventId,
    eventType: input.eventType,
    eventVersion: input.eventVersion ?? 1,
    occurredAt,
    producer: input.producer ?? 'api-graphql',
    partitionKey: input.partitionKey,
    correlationId: input.correlationId ?? null,
    payload: input.payload,
  };

  await client.query(
    `
    insert into public.kafka_outbox (
      topic,
      partition_key,
      event_id,
      event_type,
      event_version,
      payload
    )
    values ($1, $2, $3, $4, $5, $6::jsonb)
    on conflict (event_id) do nothing
    `,
    [
      input.topic,
      input.partitionKey,
      event.eventId,
      event.eventType,
      event.eventVersion,
      JSON.stringify(event),
    ]
  );

  return event;
}

export type OutboxRow = {
  id: string;
  topic: string;
  partition_key: string;
  event_id: string;
  event_type: string;
  event_version: number;
  payload: DomainEvent;
  created_at: string;
  attempts: number;
};

export async function claimUnpublishedOutbox(
  client: PoolClient,
  limit: number
): Promise<OutboxRow[]> {
  const { rows } = await client.query<OutboxRow>(
    `
    select
      id,
      topic,
      partition_key,
      event_id,
      event_type,
      event_version,
      payload,
      created_at,
      attempts
    from public.kafka_outbox
    where published_at is null
      and attempts < 25
    order by created_at asc
    limit $1
    for update skip locked
    `,
    [limit]
  );
  return rows;
}

export async function markOutboxPublished(client: PoolClient, ids: string[]): Promise<void> {
  if (!ids.length) return;
  await client.query(
    `
    update public.kafka_outbox
    set published_at = now(), last_error = null
    where id = any($1::uuid[])
    `,
    [ids]
  );
}

export async function markOutboxFailed(
  client: PoolClient,
  id: string,
  error: string
): Promise<void> {
  await client.query(
    `
    update public.kafka_outbox
    set attempts = attempts + 1,
        last_error = left($2, 1000)
    where id = $1
    `,
    [id, error]
  );
}

/** Returns true if this consumer should process the event (first time). */
export async function claimProcessedEvent(
  client: PoolClient,
  consumerGroup: string,
  eventId: string,
  eventType?: string
): Promise<boolean> {
  const { rowCount } = await client.query(
    `
    insert into public.kafka_processed_events (consumer_group, event_id, event_type)
    values ($1, $2, $3)
    on conflict (consumer_group, event_id) do nothing
    `,
    [consumerGroup, eventId, eventType ?? null]
  );
  return (rowCount ?? 0) > 0;
}
