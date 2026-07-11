create table if not exists public.ios_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_token text not null unique,
  bundle_id text,
  kind text not null default 'alert',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ios_device_tokens_user_id_idx
  on public.ios_device_tokens(user_id);