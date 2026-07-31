-- Run once in Supabase SQL Editor (production).
-- Enables people activity reports + Kafka engagement persistence.

-- 1) Privacy column used by feed/comments (safe if already exists)
alter table public.profiles
  add column if not exists is_private boolean not null default false;

-- 2) Comment likes (safe if already exists)
create table if not exists public.post_comment_likes (
  comment_id uuid not null references public.post_comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

-- 3) Activity log (every interaction + timestamp)
create table if not exists public.entity_engagement_events (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null unique,
  event_type      text not null,
  entity_id       uuid not null references auth.users(id) on delete cascade,
  content_id      uuid,
  author_id       uuid,
  country_code    text,
  hub_slug        text,
  media_type      text,
  is_spark        boolean not null default false,
  strength        real not null default 0,
  duration_ms     integer,
  progress        real,
  surface         text,
  device_class    text,
  session_id      text,
  meta            jsonb not null default '{}'::jsonb,
  occurred_at     timestamptz not null,
  ingested_at     timestamptz not null default now()
);

create index if not exists entity_engagement_entity_time_idx
  on public.entity_engagement_events (entity_id, occurred_at desc);
create index if not exists entity_engagement_type_time_idx
  on public.entity_engagement_events (event_type, occurred_at desc);
create index if not exists entity_engagement_content_idx
  on public.entity_engagement_events (content_id, occurred_at desc)
  where content_id is not null;
create index if not exists entity_engagement_ingested_idx
  on public.entity_engagement_events (ingested_at desc);

-- 4) Personality store (for later ranking / ads)
create table if not exists public.entity_personality (
  entity_id           uuid primary key references auth.users(id) on delete cascade,
  traits              jsonb not null default '{}'::jsonb,
  country_affinity    jsonb not null default '{}'::jsonb,
  hub_affinity        jsonb not null default '{}'::jsonb,
  creator_affinity    jsonb not null default '{}'::jsonb,
  media_affinity      jsonb not null default '{}'::jsonb,
  tends_to            text[] not null default '{}',
  stats               jsonb not null default '{}'::jsonb,
  feature_vector      real[] not null default '{}',
  feature_version     int not null default 1,
  events_counted      bigint not null default 0,
  window_start        timestamptz,
  window_end          timestamptz,
  updated_at          timestamptz not null default now(),
  model_version       text not null default 'rules-v0'
);
