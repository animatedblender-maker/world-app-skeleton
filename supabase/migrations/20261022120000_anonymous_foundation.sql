-- Matterya Anonymous foundation (identity_vault / anonymous / billing).
-- MANUAL APPLY: paste this entire file into Supabase SQL Editor (or psql) and run once.
-- Runtime-safe: IF NOT EXISTS / OR REPLACE / ON CONFLICT DO NOTHING throughout.
-- Do NOT expose identity_vault to anon/authenticated/public clients.

-- ═══════════════════════════════════════════════════════════════════════════
-- Schemas
-- ═══════════════════════════════════════════════════════════════════════════

create schema if not exists identity_vault;
create schema if not exists anonymous;
create schema if not exists billing;

comment on schema identity_vault is
  'Restricted account↔anonymous_profile mapping. Backend service role / postgres only.';
comment on schema anonymous is
  'Public Anonymous product data (pseudonyms, spaces, posts). No account_id columns.';
comment on schema billing is
  'Paid Spaces scaffolding (disabled until ANONYMOUS_PAID_ENABLED + StoreKit/legal).';

-- ═══════════════════════════════════════════════════════════════════════════
-- identity_vault (never grant to anon / authenticated / public)
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists identity_vault.account_anonymous_links (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  anon_profile_id uuid not null,
  created_at timestamptz not null default now(),
  constraint account_anonymous_links_account_unique unique (account_id),
  constraint account_anonymous_links_profile_unique unique (anon_profile_id)
);

-- Age attestation may happen before an Anonymous profile exists (vault-only).
create table if not exists identity_vault.age_attestations (
  account_id uuid primary key,
  attested_at timestamptz not null default now()
);

create index if not exists account_anonymous_links_account_idx
  on identity_vault.account_anonymous_links (account_id);

create index if not exists account_anonymous_links_profile_idx
  on identity_vault.account_anonymous_links (anon_profile_id);

revoke all on schema identity_vault from public;
revoke all on all tables in schema identity_vault from public;
grant usage on schema identity_vault to postgres;
grant all on all tables in schema identity_vault to postgres;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on schema identity_vault from anon;
    revoke all on all tables in schema identity_vault from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on schema identity_vault from authenticated;
    revoke all on all tables in schema identity_vault from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant usage on schema identity_vault to service_role;
    grant all on all tables in schema identity_vault to service_role;
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- anonymous.profiles
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists anonymous.profiles (
  id uuid primary key default gen_random_uuid(),
  username text not null,
  normalized_username text not null,
  avatar_seed text not null default replace(gen_random_uuid()::text, '-', ''),
  state text not null default 'active'
    check (state in ('active', 'suspended', 'deleted')),
  age_attested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint anonymous_profiles_normalized_username_unique unique (normalized_username)
);

create index if not exists anonymous_profiles_state_idx
  on anonymous.profiles (state);

create table if not exists anonymous.username_tombstones (
  normalized_username text primary key,
  retired_at timestamptz not null default now(),
  reason text
);

-- ═══════════════════════════════════════════════════════════════════════════
-- Spaces
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists anonymous.spaces (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  normalized_slug text not null,
  title text not null,
  description text not null default '',
  owner_profile_id uuid references anonymous.profiles (id),
  category text not null default 'general',
  tags text[] not null default '{}',
  visibility text not null default 'adult_public'
    check (visibility in ('adult_public', 'restricted', 'private')),
  admission text not null default 'free'
    check (admission in ('free', 'approval', 'paid', 'paid_plus_approval')),
  billing_mode text not null default 'free'
    check (billing_mode in ('free', 'one_time', 'subscription', 'free_plus_premium')),
  status text not null default 'active'
    check (status in ('draft', 'review_pending', 'active', 'read_only', 'archived', 'suspended', 'closed', 'rejected')),
  language text not null default 'en',
  member_count integer not null default 0,
  post_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint anonymous_spaces_normalized_slug_unique unique (normalized_slug)
);

create index if not exists anonymous_spaces_category_status_idx
  on anonymous.spaces (category, status);

create index if not exists anonymous_spaces_visibility_status_idx
  on anonymous.spaces (visibility, status);

create index if not exists anonymous_spaces_owner_idx
  on anonymous.spaces (owner_profile_id);

create table if not exists anonymous.space_rules (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references anonymous.spaces (id) on delete cascade,
  position integer not null default 0,
  text text not null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  constraint anonymous_space_rules_space_position_unique unique (space_id, position)
);

create index if not exists anonymous_space_rules_space_idx
  on anonymous.space_rules (space_id);

create table if not exists anonymous.space_memberships (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references anonymous.spaces (id) on delete cascade,
  anon_profile_id uuid not null references anonymous.profiles (id),
  state text not null default 'active'
    check (state in ('requested', 'active', 'left', 'banned', 'rejected')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  constraint anonymous_space_memberships_pair_unique unique (space_id, anon_profile_id)
);

create index if not exists anonymous_memberships_profile_state_idx
  on anonymous.space_memberships (anon_profile_id, state);

create index if not exists anonymous_memberships_space_state_idx
  on anonymous.space_memberships (space_id, state);

create table if not exists anonymous.space_roles (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null references anonymous.space_memberships (id) on delete cascade,
  role text not null
    check (role in ('owner', 'moderator', 'member')),
  granted_by uuid references anonymous.profiles (id),
  granted_at timestamptz not null default now(),
  constraint anonymous_space_roles_membership_role_unique unique (membership_id, role)
);

create index if not exists anonymous_space_roles_membership_idx
  on anonymous.space_roles (membership_id);

create table if not exists anonymous.space_bans (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references anonymous.spaces (id) on delete cascade,
  anon_profile_id uuid not null references anonymous.profiles (id),
  reason text,
  until timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references anonymous.profiles (id),
  constraint anonymous_space_bans_pair_unique unique (space_id, anon_profile_id)
);

create index if not exists anonymous_space_bans_profile_idx
  on anonymous.space_bans (anon_profile_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- Content
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists anonymous.posts (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references anonymous.spaces (id) on delete cascade,
  author_profile_id uuid not null references anonymous.profiles (id),
  title text,
  body text not null default '',
  state text not null default 'active'
    check (state in ('active', 'removed', 'deleted', 'held', 'locked')),
  score integer not null default 0,
  comment_count integer not null default 0,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists anonymous_posts_space_created_idx
  on anonymous.posts (space_id, created_at desc);

create index if not exists anonymous_posts_author_idx
  on anonymous.posts (author_profile_id);

create index if not exists anonymous_posts_score_idx
  on anonymous.posts (score desc, created_at desc);

create table if not exists anonymous.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references anonymous.posts (id) on delete cascade,
  parent_comment_id uuid references anonymous.comments (id) on delete cascade,
  author_profile_id uuid not null references anonymous.profiles (id),
  body text not null,
  depth integer not null default 0 check (depth >= 0 and depth <= 8),
  state text not null default 'active'
    check (state in ('active', 'removed', 'deleted', 'held')),
  score integer not null default 0,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);

create index if not exists anonymous_comments_post_created_idx
  on anonymous.comments (post_id, created_at);

create index if not exists anonymous_comments_parent_idx
  on anonymous.comments (parent_comment_id);

create table if not exists anonymous.votes (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('post', 'comment')),
  target_id uuid not null,
  anon_profile_id uuid not null references anonymous.profiles (id),
  value smallint not null check (value in (-1, 0, 1)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint anonymous_votes_voter_target_unique unique (target_type, target_id, anon_profile_id)
);

create index if not exists anonymous_votes_target_idx
  on anonymous.votes (target_type, target_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- Moderation / safety
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists anonymous.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_profile_id uuid not null references anonymous.profiles (id),
  target_type text not null
    check (target_type in ('post', 'comment', 'profile', 'space')),
  target_id uuid not null,
  reason text not null,
  state text not null default 'open'
    check (state in ('open', 'triaged', 'resolved', 'dismissed')),
  created_at timestamptz not null default now()
);

create index if not exists anonymous_reports_state_created_idx
  on anonymous.reports (state, created_at desc);

create table if not exists anonymous.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  actor_profile_id uuid references anonymous.profiles (id),
  target_type text not null,
  target_id uuid not null,
  action text not null,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists anonymous_moderation_actions_created_idx
  on anonymous.moderation_actions (created_at desc);

create table if not exists anonymous.blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_profile_id uuid not null references anonymous.profiles (id),
  blocked_profile_id uuid not null references anonymous.profiles (id),
  created_at timestamptz not null default now(),
  constraint anonymous_blocks_pair_unique unique (blocker_profile_id, blocked_profile_id),
  constraint anonymous_blocks_no_self check (blocker_profile_id <> blocked_profile_id)
);

create index if not exists anonymous_blocks_blocker_idx
  on anonymous.blocks (blocker_profile_id);

-- FK from vault link → anonymous profile (after profiles exist)
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'account_anonymous_links_profile_fk'
  ) then
    alter table identity_vault.account_anonymous_links
      add constraint account_anonymous_links_profile_fk
      foreign key (anon_profile_id) references anonymous.profiles (id);
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Billing scaffolding (paid Spaces off until flag + StoreKit/legal)
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists billing.platform_settings (
  key text primary key,
  value_json jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into billing.platform_settings (key, value_json)
values (
  'platform_fee',
  jsonb_build_object('fee_bps', 1000, 'fee_percent', 10, 'note', 'Default Matterya platform fee 10%')
)
on conflict (key) do nothing;

create table if not exists billing.creators (
  id uuid primary key default gen_random_uuid(),
  anon_profile_id uuid not null references anonymous.profiles (id),
  payout_account_ref text,
  monetization_state text not null default 'not_applied'
    check (monetization_state in (
      'not_applied', 'kyc_pending', 'approved', 'payouts_enabled', 'rejected', 'hold', 'disabled'
    )),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_creators_profile_unique unique (anon_profile_id)
);

create table if not exists billing.price_versions (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references anonymous.spaces (id) on delete cascade,
  region text not null default 'GLOBAL',
  currency text not null default 'EUR',
  amount_minor integer not null check (amount_minor >= 0),
  recurrence text not null default 'month'
    check (recurrence in ('one_time', 'week', 'month', 'year')),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  effective_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists billing_price_versions_space_idx
  on billing.price_versions (space_id, status);

create table if not exists billing.orders (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references anonymous.profiles (id),
  space_id uuid not null references anonymous.spaces (id),
  price_version_id uuid not null references billing.price_versions (id),
  channel text not null default 'web'
    check (channel in ('web', 'ios', 'android')),
  amount_minor integer not null,
  currency text not null default 'EUR',
  state text not null default 'created'
    check (state in (
      'created', 'awaiting_payment', 'paid', 'fulfilled',
      'failed', 'expired', 'refunded', 'partially_refunded', 'disputed', 'chargeback'
    )),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_orders_idempotency_unique unique (idempotency_key)
);

create index if not exists billing_orders_profile_space_idx
  on billing.orders (profile_id, space_id);

create table if not exists billing.provider_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  event_id text not null,
  payload_hash text,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint billing_provider_events_unique unique (provider, event_id)
);

create table if not exists billing.subscriptions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references anonymous.profiles (id),
  space_id uuid not null references anonymous.spaces (id),
  provider_ref text,
  plan_version uuid references billing.price_versions (id),
  period_end timestamptz,
  state text not null default 'active'
    check (state in (
      'trial', 'active', 'past_due', 'cancel_at_period_end',
      'cancelled', 'expired', 'paused'
    )),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists billing_subscriptions_profile_space_idx
  on billing.subscriptions (profile_id, space_id);

create table if not exists billing.entitlements (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references anonymous.profiles (id),
  space_id uuid not null references anonymous.spaces (id),
  scope text not null default 'access',
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  state text not null default 'pending'
    check (state in (
      'pending', 'active', 'grace', 'expired', 'suspended', 'revoked', 'refunded'
    )),
  source_order_id uuid references billing.orders (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists billing_entitlements_auth_idx
  on billing.entitlements (profile_id, space_id, expires_at);

create table if not exists billing.ledger_journals (
  id uuid primary key default gen_random_uuid(),
  source_event_id uuid,
  currency text not null default 'EUR',
  created_at timestamptz not null default now()
);

create table if not exists billing.ledger_lines (
  id uuid primary key default gen_random_uuid(),
  journal_id uuid not null references billing.ledger_journals (id) on delete cascade,
  ledger_account_id text not null,
  debit_minor integer not null default 0 check (debit_minor >= 0),
  credit_minor integer not null default 0 check (credit_minor >= 0),
  created_at timestamptz not null default now()
);

create index if not exists billing_ledger_lines_journal_idx
  on billing.ledger_lines (journal_id);

create table if not exists billing.payouts (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references billing.creators (id),
  amount_minor integer not null check (amount_minor >= 0),
  currency text not null default 'EUR',
  provider_ref text,
  state text not null default 'pending'
    check (state in ('pending', 'processing', 'paid', 'failed', 'cancelled')),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  constraint billing_payouts_idempotency_unique unique (idempotency_key)
);

-- Restrict billing / anonymous from browser roles (API uses service DATABASE_URL)
revoke all on schema billing from public;
revoke all on schema anonymous from public;
grant usage on schema billing to postgres;
grant usage on schema anonymous to postgres;
grant all on all tables in schema billing to postgres;
grant all on all tables in schema anonymous to postgres;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on schema billing from anon;
    revoke all on schema anonymous from anon;
    revoke all on all tables in schema billing from anon;
    revoke all on all tables in schema anonymous from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on schema billing from authenticated;
    revoke all on schema anonymous from authenticated;
    revoke all on all tables in schema billing from authenticated;
    revoke all on all tables in schema anonymous from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant usage on schema billing to service_role;
    grant usage on schema anonymous to service_role;
    grant all on all tables in schema billing to service_role;
    grant all on all tables in schema anonymous to service_role;
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Seed starter adult_public free Spaces (idempotent by normalized_slug)
-- ═══════════════════════════════════════════════════════════════════════════

insert into anonymous.spaces (
  slug, normalized_slug, title, description, category, tags,
  visibility, admission, billing_mode, status, language
)
values
  (
    'general', 'general', 'General',
    'Open adult discussion for anything that fits Matterya Anonymous rules.',
    'general', array['general', 'chat'],
    'adult_public', 'free', 'free', 'active', 'en'
  ),
  (
    'advice', 'advice', 'Advice',
    'Ask for perspective and share experiences. Not professional medical or legal advice.',
    'advice', array['advice', 'support'],
    'adult_public', 'free', 'free', 'active', 'en'
  ),
  (
    'creative', 'creative', 'Creative',
    'Writing, art ideas, worldbuilding, and creative collaboration (text-only for now).',
    'creative', array['creative', 'writing', 'art'],
    'adult_public', 'free', 'free', 'active', 'en'
  ),
  (
    'tech', 'tech', 'Tech',
    'Software, hardware, AI, and builder talk without linking to your public Matterya profile.',
    'tech', array['tech', 'dev', 'ai'],
    'adult_public', 'free', 'free', 'active', 'en'
  ),
  (
    'wellness', 'wellness', 'Wellness',
    'Mental and physical wellness discussion among adults. Crisis help belongs with real services.',
    'wellness', array['wellness', 'health'],
    'adult_public', 'free', 'free', 'active', 'en'
  ),
  (
    'offbeat', 'offbeat', 'Offbeat',
    'Weird, niche, and delightfully strange topics — still within platform policy.',
    'offbeat', array['offbeat', 'niche'],
    'adult_public', 'free', 'free', 'active', 'en'
  ),
  (
    'careers', 'careers', 'Careers',
    'Work, interviews, and career pivots discussed under your Anonymous handle.',
    'careers', array['careers', 'work'],
    'adult_public', 'free', 'free', 'active', 'en'
  ),
  (
    'books', 'books', 'Books',
    'What you are reading, recommending, or arguing about — spoilers tagged in-text please.',
    'books', array['books', 'reading'],
    'adult_public', 'free', 'free', 'active', 'en'
  )
on conflict (normalized_slug) do nothing;

-- Default rules for seeded spaces (skip if rules already present for that space)
insert into anonymous.space_rules (space_id, position, text, version)
select s.id, r.position, r.text, 1
from anonymous.spaces s
cross join (
  values
    (0, 'Be 18+. This entire section is adult-only.'),
    (1, 'No doxxing, threats, scams, or illegal content.'),
    (2, 'Do not share real names, contact info, or your ordinary Matterya identity.'),
    (3, 'Report abuse. Blocking and reporting are available to everyone.')
) as r(position, text)
where s.normalized_slug in (
  'general', 'advice', 'creative', 'tech', 'wellness', 'offbeat', 'careers', 'books'
)
  and not exists (
    select 1 from anonymous.space_rules sr where sr.space_id = s.id
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- Audit + outbox (spec §11.2) — append-only, restricted
-- ═══════════════════════════════════════════════════════════════════════════

create schema if not exists security;
create schema if not exists ops;

create table if not exists security.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor text,
  action text not null,
  target text,
  purpose text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists security_audit_events_created_idx
  on security.audit_events (created_at desc);

create table if not exists ops.outbox (
  id uuid primary key default gen_random_uuid(),
  type text not null,
  payload_ref text,
  payload jsonb not null default '{}'::jsonb,
  state text not null default 'pending'
    check (state in ('pending', 'processing', 'done', 'failed')),
  attempts integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ops_outbox_state_created_idx
  on ops.outbox (state, created_at);

revoke all on schema security from public;
revoke all on schema ops from public;
grant usage on schema security to postgres;
grant usage on schema ops to postgres;
grant all on all tables in schema security to postgres;
grant all on all tables in schema ops to postgres;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on schema security from anon;
    revoke all on schema ops from anon;
    revoke all on all tables in schema security from anon;
    revoke all on all tables in schema ops from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on schema security from authenticated;
    revoke all on schema ops from authenticated;
    revoke all on all tables in schema security from authenticated;
    revoke all on all tables in schema ops from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant usage on schema security to service_role;
    grant usage on schema ops to service_role;
    grant all on all tables in schema security to service_role;
    grant all on all tables in schema ops to service_role;
  end if;
end $$;
