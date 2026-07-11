alter table public.ios_device_tokens
  add column if not exists apns_environment text not null default 'sandbox';

create index if not exists ios_device_tokens_user_env_idx
  on public.ios_device_tokens(user_id, apns_environment);