-- RecSys scale foundation (Phase 0→1)
-- "Warehouse" for Matterya = durable fact tables in Postgres + Kafka stream.
-- Export to BigQuery/Snowflake later without rewriting product paths.

-- Decision log: every ranked page (reconstruct feeds offline / train models).
create table if not exists public.recommendation_decisions (
  id              uuid primary key default gen_random_uuid(),
  request_id      text not null,
  entity_id       uuid references auth.users(id) on delete set null,
  surface         text not null,
  policy_version  text not null default 'server.v1',
  session_id      text,
  candidate_count int not null default 0,
  served_count    int not null default 0,
  item_ids        uuid[] not null default '{}',
  scores          real[] not null default '{}',
  sources         jsonb not null default '[]'::jsonb,
  latency_ms      int,
  meta            jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);

create index if not exists recommendation_decisions_entity_time_idx
  on public.recommendation_decisions (entity_id, created_at desc);

create index if not exists recommendation_decisions_surface_time_idx
  on public.recommendation_decisions (surface, created_at desc);

create index if not exists recommendation_decisions_request_idx
  on public.recommendation_decisions (request_id);

comment on table public.recommendation_decisions is
  'Ranked feed pages — warehouse fact for offline training + debugging.';

-- Online feature store (lite): user→creator affinity for ranking.
create table if not exists public.recsys_user_creator_affinity (
  entity_id       uuid not null references auth.users(id) on delete cascade,
  creator_id      uuid not null,
  score           real not null default 0,
  positive_events int not null default 0,
  negative_events int not null default 0,
  last_event_at   timestamptz,
  updated_at      timestamptz not null default now(),
  primary key (entity_id, creator_id)
);

create index if not exists recsys_affinity_entity_score_idx
  on public.recsys_user_creator_affinity (entity_id, score desc);

comment on table public.recsys_user_creator_affinity is
  'Online feature: how much this user likes each creator (from engagement).';

-- Item popularity / quality counters (global cold-start).
create table if not exists public.recsys_item_stats (
  content_id      uuid primary key,
  impressions     bigint not null default 0,
  dwells          bigint not null default 0,
  likes           bigint not null default 0,
  hides           bigint not null default 0,
  not_interested  bigint not null default 0,
  watch_complete  bigint not null default 0,
  quality_score   real not null default 0,
  updated_at      timestamptz not null default now()
);

create index if not exists recsys_item_stats_quality_idx
  on public.recsys_item_stats (quality_score desc);

-- Scale indexes on engagement facts (warehouse queries).
create index if not exists entity_engagement_surface_time_idx
  on public.entity_engagement_events (surface, occurred_at desc)
  where surface is not null;

create index if not exists entity_engagement_author_time_idx
  on public.entity_engagement_events (author_id, occurred_at desc)
  where author_id is not null;
