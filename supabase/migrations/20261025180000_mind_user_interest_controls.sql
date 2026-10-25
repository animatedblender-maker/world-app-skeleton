-- MIND-019 — Explicit user interest controls (overrides inferred personality).
-- Matches ensureInterestControlsSchema() in mind-interest-controls.ts.

create table if not exists public.mind_user_interest_controls (
  entity_id uuid primary key,
  muted_hubs text[] not null default '{}',
  muted_creators uuid[] not null default '{}',
  boosted_topics text[] not null default '{}',
  chrono_preferred boolean not null default false,
  updated_at timestamptz not null default now()
);

comment on table public.mind_user_interest_controls is
  'MIND-019 user interest controls — muted hubs/creators, boosted topics, chrono preference.';
