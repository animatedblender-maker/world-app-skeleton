-- Channel admins infrastructure
-- One living channel per creator account; creator (owner) selects admins with full ops.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  handle text,
  about text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint channels_name_nonempty check (char_length(trim(name)) > 0),
  constraint channels_one_per_owner unique (owner_user_id)
);

create unique index if not exists channels_handle_unique
  on public.channels (lower(handle))
  where handle is not null and btrim(handle) <> '';

create table if not exists public.channel_members (
  channel_id uuid not null references public.channels (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('owner', 'admin')),
  invited_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (channel_id, user_id)
);

create index if not exists channel_members_user_idx
  on public.channel_members (user_id);

create index if not exists channel_members_channel_role_idx
  on public.channel_members (channel_id, role);

alter table public.posts
  add column if not exists channel_id uuid references public.channels (id) on delete set null,
  add column if not exists posted_by_user_id uuid references auth.users (id) on delete set null,
  add column if not exists channel_hidden_at timestamptz,
  add column if not exists channel_hidden_by uuid references auth.users (id) on delete set null;

create index if not exists posts_channel_id_idx
  on public.posts (channel_id)
  where channel_id is not null;

-- ---------------------------------------------------------------------------
-- Helpers (security definer — usable from API + RLS)
-- ---------------------------------------------------------------------------

create or replace function public.is_channel_owner(p_channel_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.channels c
    where c.id = p_channel_id
      and c.owner_user_id = p_user_id
  );
$$;

create or replace function public.is_channel_admin_or_owner(p_channel_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.channel_members m
    where m.channel_id = p_channel_id
      and m.user_id = p_user_id
      and m.role in ('owner', 'admin')
  )
  or public.is_channel_owner(p_channel_id, p_user_id);
$$;

create or replace function public.channel_id_for_owner(p_owner_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select c.id
  from public.channels c
  where c.owner_user_id = p_owner_user_id
  limit 1;
$$;

revoke all on function public.is_channel_owner(uuid, uuid) from public;
revoke all on function public.is_channel_admin_or_owner(uuid, uuid) from public;
revoke all on function public.channel_id_for_owner(uuid) from public;
grant execute on function public.is_channel_owner(uuid, uuid) to authenticated, service_role;
grant execute on function public.is_channel_admin_or_owner(uuid, uuid) to authenticated, service_role;
grant execute on function public.channel_id_for_owner(uuid) to authenticated, service_role;

-- Keep owner_user_id in sync with owner membership row.
create or replace function public.channels_ensure_owner_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.channel_members (channel_id, user_id, role, invited_by)
  values (new.id, new.owner_user_id, 'owner', new.owner_user_id)
  on conflict (channel_id, user_id) do update
    set role = 'owner';
  return new;
end;
$$;

drop trigger if exists channels_ensure_owner_member_trg on public.channels;
create trigger channels_ensure_owner_member_trg
  after insert on public.channels
  for each row
  execute function public.channels_ensure_owner_member();

create or replace function public.channels_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists channels_touch_updated_at_trg on public.channels;
create trigger channels_touch_updated_at_trg
  before update on public.channels
  for each row
  execute function public.channels_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Backfill from LivingChannelMarker in profiles.bio
-- Format: line starting with __living_channel__|name=...
-- ---------------------------------------------------------------------------

insert into public.channels (owner_user_id, name, handle, about, avatar_url)
select
  p.user_id,
  coalesce(
    nullif(
      trim(
        both from
        regexp_replace(
          (select line
           from unnest(string_to_array(coalesce(p.bio, ''), E'\n')) as line
           where line like '\_\_living_channel\_\_|%' escape '\'
           limit 1),
          '^.*name=',
          ''
        )
      ),
      ''
    ),
    nullif(trim(both from coalesce(p.display_name, '')), ''),
    nullif(trim(both from coalesce(p.username, '')), ''),
    'Channel'
  ) as name,
  nullif(trim(both from coalesce(p.username, '')), '') as handle,
  nullif(
    trim(
      both from
      regexp_replace(
        coalesce(p.bio, ''),
        E'(?m)^__living_channel__\\|.*$',
        '',
        'g'
      )
    ),
    ''
  ) as about,
  p.avatar_url
from public.profiles p
where p.bio is not null
  and p.bio like '%__living_channel__|%'
  and not exists (
    select 1 from public.channels c where c.owner_user_id = p.user_id
  )
on conflict (owner_user_id) do nothing;

-- Bind existing hub-channel posts to the owner's channel.
update public.posts p
set
  channel_id = c.id,
  posted_by_user_id = coalesce(p.posted_by_user_id, p.author_id)
from public.channels c
where c.owner_user_id = p.author_id
  and p.channel_id is null
  and (
    p.body like '%__hub_channel__|%'
    or p.media_type in ('video', 'reel')
  );

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.channels enable row level security;
alter table public.channel_members enable row level security;

drop policy if exists channels_select_all on public.channels;
create policy channels_select_all on public.channels
  for select
  using (true);

drop policy if exists channels_insert_own on public.channels;
create policy channels_insert_own on public.channels
  for insert
  with check (auth.uid() = owner_user_id);

drop policy if exists channels_update_staff on public.channels;
create policy channels_update_staff on public.channels
  for update
  using (public.is_channel_admin_or_owner(id, auth.uid()))
  with check (public.is_channel_admin_or_owner(id, auth.uid()));

drop policy if exists channels_delete_owner on public.channels;
create policy channels_delete_owner on public.channels
  for delete
  using (public.is_channel_owner(id, auth.uid()));

drop policy if exists channel_members_select_all on public.channel_members;
create policy channel_members_select_all on public.channel_members
  for select
  using (true);

drop policy if exists channel_members_insert_staff on public.channel_members;
create policy channel_members_insert_staff on public.channel_members
  for insert
  with check (
    public.is_channel_admin_or_owner(channel_id, auth.uid())
    and role = 'admin'
  );

drop policy if exists channel_members_delete_staff on public.channel_members;
create policy channel_members_delete_staff on public.channel_members
  for delete
  using (
    public.is_channel_admin_or_owner(channel_id, auth.uid())
    and role = 'admin'
  );

drop policy if exists channel_members_update_owner on public.channel_members;
create policy channel_members_update_owner on public.channel_members
  for update
  using (public.is_channel_owner(channel_id, auth.uid()))
  with check (public.is_channel_owner(channel_id, auth.uid()));

grant select on public.channels to authenticated, anon;
grant insert, update, delete on public.channels to authenticated;
grant select on public.channel_members to authenticated, anon;
grant insert, update, delete on public.channel_members to authenticated;
grant all on public.channels to service_role;
grant all on public.channel_members to service_role;
