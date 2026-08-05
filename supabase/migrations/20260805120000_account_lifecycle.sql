-- Account lifecycle: deactivate (recoverable) + delete (permanent soft tombstone).
-- Hard auth-user removal is performed by the API with the Supabase service role;
-- this migration adds the profile flags the API and clients rely on.

alter table public.profiles
  add column if not exists account_status text not null default 'active',
  add column if not exists deactivated_at timestamptz,
  add column if not exists deleted_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_account_status_check'
  ) then
    alter table public.profiles
      add constraint profiles_account_status_check
      check (account_status = any (array['active', 'deactivated', 'deleted']));
  end if;
end $$;

comment on column public.profiles.account_status is
  'active | deactivated (hidden, reactivatable) | deleted (tombstone / pending purge)';

comment on column public.profiles.deactivated_at is
  'When the user deactivated; cleared on reactivate.';

comment on column public.profiles.deleted_at is
  'When the user requested permanent deletion.';

create index if not exists profiles_account_status_idx
  on public.profiles (account_status)
  where account_status <> 'active';

-- Hide non-active accounts from public profile reads (RLS layer of defense).
-- Owner can still select their own row so reactivate / meProfile works.
drop policy if exists profiles_select_active_public on public.profiles;
create policy profiles_select_active_public
  on public.profiles
  for select
  using (
    account_status = 'active'
    or auth.uid() = user_id
  );
