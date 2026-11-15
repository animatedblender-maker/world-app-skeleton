-- Studio Earn ledger / balances / payouts (Hubs channel creators).
-- Balances start at 0 until ads revshare credits the ledger.
-- Withdrawals stay gated by STUDIO_PAYOUTS_LIVE on the API.

create table if not exists public.studio_creator_monetization (
  channel_id uuid primary key references public.channels (id) on delete cascade,
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  state text not null default 'not_applied'
    check (state in (
      'not_applied', 'pending', 'approved', 'payouts_enabled', 'rejected', 'hold', 'disabled'
    )),
  applied_at timestamptz,
  reviewed_at timestamptz,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint studio_creator_monetization_owner_unique unique (owner_user_id)
);

create index if not exists studio_creator_monetization_state_idx
  on public.studio_creator_monetization (state, updated_at desc);

create table if not exists public.studio_earn_balances (
  channel_id uuid primary key references public.channels (id) on delete cascade,
  currency text not null default 'USD',
  available_minor integer not null default 0 check (available_minor >= 0),
  pending_minor integer not null default 0 check (pending_minor >= 0),
  lifetime_earned_minor integer not null default 0 check (lifetime_earned_minor >= 0),
  lifetime_paid_minor integer not null default 0 check (lifetime_paid_minor >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.studio_earn_ledger (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels (id) on delete cascade,
  entry_type text not null
    check (entry_type in (
      'credit', 'debit', 'hold', 'release', 'adjustment', 'payout', 'payout_reversal'
    )),
  amount_minor integer not null check (amount_minor <> 0),
  currency text not null default 'USD',
  memo text not null default '',
  source_ref text,
  created_at timestamptz not null default now()
);

create index if not exists studio_earn_ledger_channel_created_idx
  on public.studio_earn_ledger (channel_id, created_at desc);

create table if not exists public.studio_earn_payouts (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels (id) on delete cascade,
  amount_minor integer not null check (amount_minor > 0),
  currency text not null default 'USD',
  state text not null default 'pending'
    check (state in ('pending', 'processing', 'paid', 'failed', 'cancelled')),
  provider_ref text,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  constraint studio_earn_payouts_idempotency_unique unique (idempotency_key)
);

create index if not exists studio_earn_payouts_channel_created_idx
  on public.studio_earn_payouts (channel_id, created_at desc);

alter table public.studio_creator_monetization enable row level security;
alter table public.studio_earn_balances enable row level security;
alter table public.studio_earn_ledger enable row level security;
alter table public.studio_earn_payouts enable row level security;
