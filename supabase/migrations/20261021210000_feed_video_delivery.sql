-- Matterya Video Feed Algorithm Architecture §4 — at-most-once For You delivery.
-- Surfaces: home_for_you | hubs_for_you
-- canonical_video_id is TEXT (r2:… / clip:uuid) so R2 packs and share-origin collapse.

create table if not exists public.feed_batch (
  batch_id         uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  surface          text not null,
  idempotency_key  text not null,
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null default (now() + interval '7 days'),
  status           text not null default 'building'
                   check (status in ('building', 'complete', 'failed')),
  unique (user_id, surface, idempotency_key)
);

create index if not exists feed_batch_user_surface_time_idx
  on public.feed_batch (user_id, surface, created_at desc);

create table if not exists public.feed_video_delivery (
  user_id              uuid not null references auth.users(id) on delete cascade,
  surface              text not null,
  canonical_video_id   text not null,
  first_video_id       uuid not null,
  delivery_id          uuid not null unique default gen_random_uuid(),
  batch_id             uuid not null references public.feed_batch(batch_id) on delete cascade,
  delivered_at         timestamptz not null default now(),
  primary key (user_id, surface, canonical_video_id)
);

create index if not exists feed_video_delivery_user_time_idx
  on public.feed_video_delivery (user_id, surface, delivered_at desc);

create index if not exists feed_video_delivery_batch_idx
  on public.feed_video_delivery (batch_id);

create table if not exists public.feed_batch_item (
  batch_id     uuid not null references public.feed_batch(batch_id) on delete cascade,
  position     int not null,
  delivery_id  uuid not null,
  video_id     uuid not null,
  primary key (batch_id, position)
);

create index if not exists feed_batch_item_video_idx
  on public.feed_batch_item (video_id);

comment on table public.feed_video_delivery is
  'At-most-once For You delivery ledger (canonical clip per user+surface).';
comment on table public.feed_batch is
  'Idempotent ranked batches — retry same key returns the committed order.';
