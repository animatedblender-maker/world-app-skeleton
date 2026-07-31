-- Private profiles support (API already references this column).
-- Without it, feed/comment SQL that touches pr.is_private throws and GraphQL returns
-- "Unexpected error" — which the iOS app surfaces as missing comments / empty profiles.

alter table public.profiles
  add column if not exists is_private boolean not null default false;

comment on column public.profiles.is_private is
  'When true, non-owners cannot browse the author feed and avatars are redacted.';

create index if not exists profiles_is_private_idx
  on public.profiles (is_private)
  where is_private = true;
