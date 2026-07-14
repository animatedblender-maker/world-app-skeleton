-- RLS on now_playing_status referenced user_follows without table access for
-- the authenticated role. Use a security definer helper instead.

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

drop policy if exists now_playing_select_visible on public.now_playing_status;

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