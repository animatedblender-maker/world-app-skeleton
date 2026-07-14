create table if not exists public.post_comment_reports (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references public.post_comments(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null,
  status text not null default 'open',
  resolution_note text,
  resolution_action text,
  moderated_by uuid references auth.users(id) on delete set null,
  moderated_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.post_comment_reports enable row level security;

alter table public.post_comment_reports
  add constraint post_comment_reports_reason_check
  check (char_length(reason) >= 1 and char_length(reason) <= 2000);

alter table public.post_comment_reports
  add constraint post_comment_reports_status_check
  check (status in ('open', 'in_review', 'resolved', 'dismissed'));

alter table public.post_comment_reports
  add constraint post_comment_reports_resolution_action_check
  check (
    resolution_action is null
    or resolution_action in ('ignore', 'delete_comment', 'warn_user', 'ban_user')
  );

create index if not exists post_comment_reports_comment_status_created_idx
  on public.post_comment_reports (comment_id, status, created_at desc);

create policy "Users can create comment reports"
  on public.post_comment_reports
  for insert
  to authenticated
  with check (auth.uid() = reporter_id);

create policy "Users can view own comment reports"
  on public.post_comment_reports
  for select
  to authenticated
  using (auth.uid() = reporter_id);
