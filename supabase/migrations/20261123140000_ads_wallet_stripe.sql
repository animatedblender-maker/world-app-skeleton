-- Matterya Ads prepaid wallet (Stripe Checkout top-ups + impression debits).

alter table public.ad_advertisers
  add column if not exists stripe_customer_id text,
  add column if not exists wallet_balance_cents integer not null default 0,
  add column if not exists default_payment_method_id text;

create unique index if not exists ad_advertisers_stripe_customer_uidx
  on public.ad_advertisers (stripe_customer_id)
  where stripe_customer_id is not null;

create table if not exists public.ad_wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  amount_cents integer not null,
  balance_after_cents integer not null,
  campaign_id uuid references public.ad_campaigns (id) on delete set null,
  impression_id uuid references public.ad_impressions (id) on delete set null,
  stripe_event_id text,
  stripe_checkout_session_id text,
  note text,
  created_at timestamptz not null default now(),
  constraint ad_wallet_ledger_kind_check
    check (kind in ('topup', 'debit_impression', 'adjust', 'refund')),
  -- topup/debit must be nonzero; adjust may be 0 (e.g. payment-method saved audit)
  constraint ad_wallet_ledger_amount_check check (
    (kind = 'adjust') or (amount_cents <> 0)
  )
);

create unique index if not exists ad_wallet_ledger_stripe_event_uidx
  on public.ad_wallet_ledger (stripe_event_id)
  where stripe_event_id is not null;

create unique index if not exists ad_wallet_ledger_impression_debit_uidx
  on public.ad_wallet_ledger (impression_id)
  where impression_id is not null and kind = 'debit_impression';

create index if not exists ad_wallet_ledger_user_idx
  on public.ad_wallet_ledger (user_id, created_at desc);

create index if not exists ad_advertisers_wallet_balance_idx
  on public.ad_advertisers (wallet_balance_cents)
  where wallet_balance_cents > 0;

comment on column public.ad_advertisers.wallet_balance_cents is
  'Prepaid Ads balance in EUR cents. Delivery debits ~10¢ per counted impression.';
