-- Kafka transactional outbox + consumer idempotency.
-- API writes domain events into kafka_outbox in the same DB transaction as the mutation.
-- A publisher process drains unpublished rows into Kafka.

create table if not exists public.kafka_outbox (
  id uuid primary key default gen_random_uuid(),
  topic text not null,
  partition_key text not null,
  event_id uuid not null,
  event_type text not null,
  event_version int not null default 1,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  attempts int not null default 0,
  last_error text
);

create unique index if not exists kafka_outbox_event_id_uidx
  on public.kafka_outbox (event_id);

create index if not exists kafka_outbox_unpublished_idx
  on public.kafka_outbox (created_at)
  where published_at is null;

create index if not exists kafka_outbox_topic_created_idx
  on public.kafka_outbox (topic, created_at desc);

-- Per-consumer-group idempotency so redelivery does not double-send push, etc.
create table if not exists public.kafka_processed_events (
  consumer_group text not null,
  event_id uuid not null,
  event_type text,
  processed_at timestamptz not null default now(),
  primary key (consumer_group, event_id)
);

create index if not exists kafka_processed_events_processed_at_idx
  on public.kafka_processed_events (processed_at desc);

comment on table public.kafka_outbox is
  'Transactional outbox for Kafka domain events. Rows are inserted with business writes and published asynchronously.';

comment on table public.kafka_processed_events is
  'Idempotency ledger for Kafka consumers (event_id + consumer_group).';
