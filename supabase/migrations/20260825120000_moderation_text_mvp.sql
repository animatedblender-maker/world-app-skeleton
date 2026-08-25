-- Text-first moderation MVP (Detoxify/stub + policy).
-- DO NOT apply automatically — product owner applies in Supabase when ready.
-- Maps policy → posts.moderation_status / post_comments.moderation_status for feed eligibility.

create table if not exists public.moderation_results (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  raw_scores jsonb not null default '{}'::jsonb,
  provider text not null default 'stub',
  model_version text not null default 'none',
  policy_decision text not null,
  policy_version text not null default 'text-mvp-1',
  created_at timestamptz not null default now(),
  constraint moderation_results_entity_type_check
    check (entity_type in ('post', 'comment')),
  constraint moderation_results_policy_decision_check
    check (policy_decision in ('safe', 'limited', 'review', 'held'))
);

create index if not exists moderation_results_entity_created_idx
  on public.moderation_results (entity_type, entity_id, created_at desc);

create index if not exists moderation_results_decision_created_idx
  on public.moderation_results (policy_decision, created_at desc);

alter table public.posts
  add column if not exists moderation_policy_version text;

alter table public.post_comments
  add column if not exists moderation_status text not null default 'active',
  add column if not exists moderation_note text,
  add column if not exists moderated_at timestamptz,
  add column if not exists moderation_actor text,
  add column if not exists moderation_policy_version text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'post_comments_moderation_status_check'
  ) then
    alter table public.post_comments
      add constraint post_comments_moderation_status_check
      check (moderation_status = any (array['active','sensitive','hidden','deleted']));
  end if;
end$$;

create index if not exists post_comments_moderation_status_idx
  on public.post_comments (moderation_status, created_at desc);

comment on table public.moderation_results is
  'Raw text-moderation scores + policy decision; serving uses posts/comments.moderation_status';
