-- Hubs channel subscribers (distinct from profile followers / channel_members staff).
-- Earn apply requires 500 channel subscribers + 2000 watch hours.

create table if not exists public.channel_subscribers (
  channel_id uuid not null references public.channels (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (channel_id, user_id)
);

create index if not exists channel_subscribers_user_idx
  on public.channel_subscribers (user_id, created_at desc);

create index if not exists channel_subscribers_channel_created_idx
  on public.channel_subscribers (channel_id, created_at desc);

alter table public.channel_subscribers enable row level security;

comment on table public.channel_subscribers is
  'Matterya Hubs channel Subscribe — not profile Follow, not channel_members.';
