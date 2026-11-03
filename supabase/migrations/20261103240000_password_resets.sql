-- Matterya-owned password reset tokens.
-- API mails a branded link from no-reply@matterya.com to
-- https://matterya.com/reset-password?token=… and sets the password via admin API.
-- Never use Supabase Auth recovery emails for product mail.

create table if not exists public.password_resets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  token text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists password_resets_token_uidx
  on public.password_resets (token);

create index if not exists password_resets_email_created_idx
  on public.password_resets (lower(email), created_at desc);

create index if not exists password_resets_user_id_idx
  on public.password_resets (user_id);

comment on table public.password_resets is
  'One-time Matterya password-reset tokens. Email is sent by the API (Resend), not Supabase Auth templates.';

alter table public.password_resets enable row level security;

drop policy if exists password_resets_no_client on public.password_resets;
-- No client policies: only service role / backend pool.
