-- Full-platform moderation: tickets, claim assignment, action log, category archive.
-- Remove as → move live row into moderation_archive.*; Mark as → stay live + tagged.

create schema if not exists moderation_archive;

-- ── Canonical tickets (one open ticket per target) ───────────────────────────
create table if not exists public.moderation_tickets (
  id uuid primary key default gen_random_uuid(),
  platform text not null
    check (platform in ('feed', 'sparks', 'hubs', 'masquerade', 'messages')),
  target_kind text not null
    check (target_kind in ('post', 'comment', 'message', 'space', 'profile', 'conversation')),
  target_id uuid not null,
  -- Public auth user and/or Masquerade profile (whichever applies).
  reporter_user_id uuid references auth.users (id) on delete set null,
  reporter_profile_id uuid,
  category text not null
    check (category in (
      'spam', 'harassment', 'hate', 'mature', 'violence',
      'self_harm', 'misinfo', 'scam', 'doxxing', 'other'
    )),
  status text not null default 'open'
    check (status in ('open', 'claimed', 'resolved', 'dismissed')),
  source text not null default 'user'
    check (source in ('user', 'auto')),
  report_count integer not null default 1,
  last_report_at timestamptz not null default now(),
  preview_title text,
  preview_body text,
  preview_media_url text,
  -- Claim-next assignment
  assigned_to text,
  claimed_at timestamptz,
  -- Resolution
  mod_action text
    check (mod_action is null or mod_action in ('remove', 'mark', 'skip')),
  mod_category text
    check (
      mod_category is null
      or mod_category in (
        'spam', 'harassment', 'hate', 'mature', 'violence',
        'self_harm', 'misinfo', 'scam', 'doxxing', 'other'
      )
    ),
  mod_note text,
  moderated_at timestamptz,
  moderated_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists moderation_tickets_open_target_uidx
  on public.moderation_tickets (target_kind, target_id)
  where status in ('open', 'claimed');

create index if not exists moderation_tickets_claim_idx
  on public.moderation_tickets (status, last_report_at asc)
  where status = 'open' and assigned_to is null;

create index if not exists moderation_tickets_assigned_idx
  on public.moderation_tickets (assigned_to, status)
  where assigned_to is not null;

create index if not exists moderation_tickets_platform_status_idx
  on public.moderation_tickets (platform, status, last_report_at desc);

-- ── Append-only action log (analysis) ────────────────────────────────────────
create table if not exists public.moderation_action_log (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid references public.moderation_tickets (id) on delete set null,
  actor text not null,
  action text not null
    check (action in ('claim', 'remove', 'mark', 'skip', 'release', 'report')),
  category text,
  target_kind text,
  target_id uuid,
  platform text,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists moderation_action_log_created_idx
  on public.moderation_action_log (created_at desc);

create index if not exists moderation_action_log_ticket_idx
  on public.moderation_action_log (ticket_id, created_at desc);

create index if not exists moderation_action_log_actor_idx
  on public.moderation_action_log (actor, created_at desc);

create index if not exists moderation_action_log_category_idx
  on public.moderation_action_log (category, created_at desc)
  where category is not null;

-- ── Category archive (same Postgres; removed content by category) ────────────
create table if not exists moderation_archive.posts (
  id uuid primary key default gen_random_uuid(),
  original_post_id uuid not null,
  removed_category text not null,
  ticket_id uuid,
  removed_at timestamptz not null default now(),
  removed_by text,
  snapshot jsonb not null,
  title text,
  body text,
  media_type text,
  media_url text,
  thumb_url text,
  author_id uuid,
  platform text
);

create index if not exists moderation_archive_posts_category_idx
  on moderation_archive.posts (removed_category, removed_at desc);

create index if not exists moderation_archive_posts_original_idx
  on moderation_archive.posts (original_post_id);

create table if not exists moderation_archive.comments (
  id uuid primary key default gen_random_uuid(),
  original_comment_id uuid not null,
  removed_category text not null,
  ticket_id uuid,
  removed_at timestamptz not null default now(),
  removed_by text,
  snapshot jsonb not null,
  post_id uuid,
  author_id uuid,
  body text,
  platform text
);

create index if not exists moderation_archive_comments_category_idx
  on moderation_archive.comments (removed_category, removed_at desc);

create table if not exists moderation_archive.messages (
  id uuid primary key default gen_random_uuid(),
  original_message_id uuid not null,
  removed_category text not null,
  ticket_id uuid,
  removed_at timestamptz not null default now(),
  removed_by text,
  snapshot jsonb not null,
  conversation_id uuid,
  sender_id uuid,
  body text,
  platform text default 'messages'
);

create index if not exists moderation_archive_messages_category_idx
  on moderation_archive.messages (removed_category, removed_at desc);

-- Message reports (public DMs)
create table if not exists public.message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null,
  reporter_id uuid not null references auth.users (id) on delete cascade,
  category text not null
    check (category in (
      'spam', 'harassment', 'hate', 'mature', 'violence',
      'self_harm', 'misinfo', 'scam', 'doxxing', 'other'
    )),
  reason text not null,
  status text not null default 'open'
    check (status in ('open', 'in_review', 'resolved', 'dismissed')),
  ticket_id uuid references public.moderation_tickets (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists message_reports_message_status_idx
  on public.message_reports (message_id, status, created_at desc);

alter table public.message_reports enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'message_reports'
      and policyname = 'Users can create message reports'
  ) then
    create policy "Users can create message reports"
      on public.message_reports
      for insert
      to authenticated
      with check (auth.uid() = reporter_id);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'message_reports'
      and policyname = 'Users can view own message reports'
  ) then
    create policy "Users can view own message reports"
      on public.message_reports
      for select
      to authenticated
      using (auth.uid() = reporter_id);
  end if;
end$$;

-- Tag column for Mark as (live content stays up)
alter table public.posts
  add column if not exists mod_mark_category text;

alter table public.post_comments
  add column if not exists mod_mark_category text;

comment on table public.moderation_tickets is
  'Unified cross-platform moderation tickets; claim-next assignment.';
comment on table public.moderation_action_log is
  'Append-only log of claim/remove/mark/skip for later analysis.';
comment on schema moderation_archive is
  'Removed content snapshots keyed by removed_category (Mature content, Spam, …).';
