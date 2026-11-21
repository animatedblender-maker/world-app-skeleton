-- Per-create IAP credits for Matterya Ads (consumable StoreKit purchase).
-- Free create is email-gated in API (animatedblender@gmail.com); everyone else
-- redeems one unused credit per new campaign.

create table if not exists public.ad_create_credits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  transaction_id text not null,
  original_transaction_id text,
  jws text,
  campaign_id uuid references public.ad_campaigns(id) on delete set null,
  purchased_at timestamptz not null default now(),
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint ad_create_credits_transaction_unique unique (transaction_id)
);

create index if not exists ad_create_credits_user_open_idx
  on public.ad_create_credits (user_id, purchased_at desc)
  where consumed_at is null;

comment on table public.ad_create_credits is
  'Consumable IAP credits: one unused row unlocks one createAdCampaign for non-free accounts.';
