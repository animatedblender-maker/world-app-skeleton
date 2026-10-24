-- Official / admin verified badge (Matterya account).
alter table public.profiles
  add column if not exists is_verified boolean not null default false;

create index if not exists profiles_is_verified_idx
  on public.profiles (is_verified)
  where is_verified = true;

comment on column public.profiles.is_verified is
  'Official Matterya / admin accounts — show verified badge in Messages and profiles.';
