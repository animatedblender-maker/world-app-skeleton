create table if not exists public.ad_advertisers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  website_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ad_campaigns (
  id uuid primary key default gen_random_uuid(),
  advertiser_user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  status text not null default 'draft',
  placement text not null,
  target_country_codes text[] not null default '{}',
  budget_cents integer not null default 0,
  daily_budget_cents integer not null default 0,
  start_at timestamptz,
  end_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ad_campaigns_name_check check (char_length(name) between 1 and 120),
  constraint ad_campaigns_status_check check (status in ('draft', 'active', 'paused', 'ended')),
  constraint ad_campaigns_placement_check check (placement in ('video', 'reel'))
);

create table if not exists public.ad_creatives (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.ad_campaigns(id) on delete cascade,
  title text,
  body text,
  media_kind text not null default 'video',
  media_url text not null,
  click_url text,
  cta_label text,
  duration_seconds integer not null default 8,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ad_creatives_media_kind_check check (media_kind in ('video', 'image')),
  constraint ad_creatives_duration_seconds_check check (duration_seconds between 1 and 60)
);

create table if not exists public.ad_impressions (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.ad_campaigns(id) on delete cascade,
  creative_id uuid not null references public.ad_creatives(id) on delete cascade,
  viewer_user_id uuid references auth.users(id) on delete set null,
  placement text not null,
  country_code text,
  content_country_code text,
  post_id uuid references public.posts(id) on delete set null,
  impression_token text not null unique,
  served_at timestamptz not null default now(),
  viewed_at timestamptz,
  clicked_at timestamptz
);

create table if not exists public.ad_clicks (
  id uuid primary key default gen_random_uuid(),
  impression_id uuid not null references public.ad_impressions(id) on delete cascade,
  campaign_id uuid not null references public.ad_campaigns(id) on delete cascade,
  creative_id uuid not null references public.ad_creatives(id) on delete cascade,
  viewer_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists ad_campaigns_owner_idx
  on public.ad_campaigns(advertiser_user_id, created_at desc);

create index if not exists ad_campaigns_status_placement_idx
  on public.ad_campaigns(status, placement, created_at desc);

create index if not exists ad_campaigns_target_country_codes_idx
  on public.ad_campaigns using gin(target_country_codes);

create index if not exists ad_creatives_campaign_idx
  on public.ad_creatives(campaign_id, created_at desc);

create index if not exists ad_impressions_campaign_idx
  on public.ad_impressions(campaign_id, served_at desc);

create index if not exists ad_impressions_token_idx
  on public.ad_impressions(impression_token);

create index if not exists ad_clicks_campaign_idx
  on public.ad_clicks(campaign_id, created_at desc);

alter table public.ad_advertisers enable row level security;
alter table public.ad_campaigns enable row level security;
alter table public.ad_creatives enable row level security;
alter table public.ad_impressions enable row level security;
alter table public.ad_clicks enable row level security;
