create table if not exists public.streaming_platform_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null,
  is_linked boolean not null default false,
  sharing_enabled boolean not null default true,
  linked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, platform)
);

create table if not exists public.now_playing_status (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null,
  title text not null,
  subtitle text,
  moment_label text,
  progress_ms integer not null default 0,
  duration_ms integer not null default 0,
  is_sharing boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (user_id, platform)
);

create table if not exists public.moment_room_comments (
  id uuid primary key default gen_random_uuid(),
  room_key text not null,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  reactions integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists streaming_connections_user_idx
  on public.streaming_platform_connections (user_id);

create index if not exists now_playing_user_idx
  on public.now_playing_status (user_id);

create index if not exists now_playing_updated_idx
  on public.now_playing_status (updated_at desc);

create index if not exists moment_room_comments_room_idx
  on public.moment_room_comments (room_key, created_at desc);