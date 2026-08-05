-- Matterya-owned email confirmation tokens (signup).
-- Users are created unconfirmed via service role; the API mails a branded link
-- to https://matterya.com/confirm-email?token=… and confirms via admin API.

create table if not exists public.email_confirmations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  token text not null,
  expires_at timestamptz not null,
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists email_confirmations_token_uidx
  on public.email_confirmations (token);

create index if not exists email_confirmations_email_created_idx
  on public.email_confirmations (lower(email), created_at desc);

create index if not exists email_confirmations_user_id_idx
  on public.email_confirmations (user_id);

comment on table public.email_confirmations is
  'One-time Matterya signup confirmation tokens. Email is sent by the API (Resend/SMTP), not Supabase Auth templates.';

-- API uses service role / pool (bypasses RLS). Still lock down for anon clients.
alter table public.email_confirmations enable row level security;

drop policy if exists email_confirmations_no_client on public.email_confirmations;
-- No client policies: only service role / backend pool.
