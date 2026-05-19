alter table public.posts
  add column if not exists moderation_status text not null default 'active',
  add column if not exists moderation_note text,
  add column if not exists moderated_at timestamptz,
  add column if not exists moderation_actor text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'posts_moderation_status_check'
  ) then
    alter table public.posts
      add constraint posts_moderation_status_check
      check (moderation_status = any (array['active','sensitive','hidden','deleted']));
  end if;
end$$;

alter table public.post_reports
  add column if not exists status text not null default 'open',
  add column if not exists moderator_note text,
  add column if not exists moderator_actor text,
  add column if not exists resolution_action text,
  add column if not exists resolved_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'post_reports_status_check'
  ) then
    alter table public.post_reports
      add constraint post_reports_status_check
      check (status = any (array['open','in_review','actioned','ignored']));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'post_reports_resolution_action_check'
  ) then
    alter table public.post_reports
      add constraint post_reports_resolution_action_check
      check (
        resolution_action is null
        or resolution_action = any (
          array['ignore','mark_sensitive','clear_sensitive','hide_post','delete_post','restore_post']
        )
      );
  end if;
end$$;

create index if not exists post_reports_post_status_created_idx
  on public.post_reports (post_id, status, created_at desc);

create index if not exists posts_moderation_status_idx
  on public.posts (moderation_status, created_at desc);
