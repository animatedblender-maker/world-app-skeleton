alter table public.ios_device_tokens
  add column if not exists kind text not null default 'alert';

create index if not exists ios_device_tokens_user_kind_idx
  on public.ios_device_tokens(user_id, kind);