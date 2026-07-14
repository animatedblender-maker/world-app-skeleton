alter table public.streaming_platform_connections enable row level security;
alter table public.now_playing_status enable row level security;
alter table public.moment_room_comments enable row level security;

grant select, insert, update, delete on public.streaming_platform_connections to authenticated;
grant select, insert, update, delete on public.now_playing_status to authenticated;
grant select, insert on public.moment_room_comments to authenticated;

create policy streaming_connections_select_own
  on public.streaming_platform_connections
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy streaming_connections_insert_own
  on public.streaming_platform_connections
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy streaming_connections_update_own
  on public.streaming_platform_connections
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy streaming_connections_delete_own
  on public.streaming_platform_connections
  for delete
  to authenticated
  using (auth.uid() = user_id);

grant select on public.user_follows to authenticated;

create or replace function public.is_following_user(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_follows
    where follower_id = auth.uid()
      and following_id = target_user_id
  );
$$;

grant execute on function public.is_following_user(uuid) to authenticated;

create policy now_playing_select_visible
  on public.now_playing_status
  for select
  to authenticated
  using (
    auth.uid() = user_id
    or (
      is_sharing = true
      and public.is_following_user(user_id)
    )
  );

create policy now_playing_insert_own
  on public.now_playing_status
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy now_playing_update_own
  on public.now_playing_status
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy now_playing_delete_own
  on public.now_playing_status
  for delete
  to authenticated
  using (auth.uid() = user_id);

create policy moment_comments_select_auth
  on public.moment_room_comments
  for select
  to authenticated
  using (true);

create policy moment_comments_insert_own
  on public.moment_room_comments
  for insert
  to authenticated
  with check (auth.uid() = author_id);