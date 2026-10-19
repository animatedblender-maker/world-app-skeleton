-- KNN neighbors (cosine on entity_personality.feature_vector)
-- + Instagram-style message privacy (everyone | following | requests)

create table if not exists public.entity_neighbors (
  entity_id     uuid not null references auth.users(id) on delete cascade,
  neighbor_id   uuid not null references auth.users(id) on delete cascade,
  distance      real not null,
  model_version text not null default 'knn-v1',
  updated_at    timestamptz not null default now(),
  primary key (entity_id, neighbor_id),
  check (entity_id <> neighbor_id)
);

create index if not exists entity_neighbors_entity_dist_idx
  on public.entity_neighbors (entity_id, distance asc);

create index if not exists entity_neighbors_updated_idx
  on public.entity_neighbors (updated_at desc);

comment on table public.entity_neighbors is
  'Cosine-KNN neighbors from entity_personality.feature_vector for collaborative ranking.';

-- Message acceptance: everyone | following | requests
alter table public.profiles
  add column if not exists message_privacy text;

update public.profiles
set message_privacy = 'everyone'
where message_privacy is null;

alter table public.profiles
  alter column message_privacy set default 'everyone';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_message_privacy_check'
  ) then
    alter table public.profiles
      add constraint profiles_message_privacy_check
      check (message_privacy in ('everyone', 'following', 'requests'));
  end if;
end $$;

comment on column public.profiles.message_privacy is
  'everyone = inbox; following = only people you follow; requests = non-followers → Message Requests.';

-- Per-member request flag (recipient side for stranger DMs)
alter table public.conversation_members
  add column if not exists is_request boolean not null default false;

alter table public.conversation_members
  add column if not exists request_status text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'conversation_members_request_status_check'
  ) then
    alter table public.conversation_members
      add constraint conversation_members_request_status_check
      check (
        request_status is null
        or request_status in ('pending', 'accepted', 'declined')
      );
  end if;
end $$;

create index if not exists conversation_members_requests_idx
  on public.conversation_members (user_id, is_request, request_status)
  where is_request = true;
