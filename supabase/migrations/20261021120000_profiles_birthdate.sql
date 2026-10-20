-- Birthdate on profiles (required for new signups; under-18 handling comes later).
-- Owner-only in API redact — never expose publicly.

alter table public.profiles
  add column if not exists birthdate date;

comment on column public.profiles.birthdate is
  'User date of birth (YYYY-MM-DD). Collected at signup; under-18 policy TBD.';

create index if not exists profiles_birthdate_idx
  on public.profiles (birthdate)
  where birthdate is not null;

-- Prefer birthdate from Auth user_metadata on new-user profile upsert.
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_display_name text;
  v_username text;
  v_country_code text;
  v_country_name text;
  v_city_name text;
  v_avatar_url text;
  v_bio text;
  v_birthdate date;
begin
  v_display_name :=
    coalesce(
      nullif(new.raw_user_meta_data->>'display_name', ''),
      split_part(coalesce(new.email, ''), '@', 1),
      'New User'
    );

  v_username := nullif(new.raw_user_meta_data->>'username', '');

  v_country_code := upper(nullif(new.raw_user_meta_data->>'country_code', ''));
  v_country_name := nullif(new.raw_user_meta_data->>'country_name', '');

  v_city_name := nullif(new.raw_user_meta_data->>'city_name', '');
  v_avatar_url := nullif(new.raw_user_meta_data->>'avatar_url', '');
  v_bio := nullif(new.raw_user_meta_data->>'bio', '');

  begin
    v_birthdate := nullif(new.raw_user_meta_data->>'birthdate', '')::date;
  exception when others then
    v_birthdate := null;
  end;

  if v_country_name is null then
    v_country_name := 'Unknown';
  end if;

  insert into public.profiles (
    user_id, email, display_name, username,
    avatar_url, country_name, country_code, city_name, bio, birthdate
  )
  values (
    new.id, new.email, v_display_name, v_username,
    v_avatar_url, v_country_name, v_country_code, v_city_name, v_bio, v_birthdate
  )
  on conflict (user_id) do update
    set email        = excluded.email,
        display_name = excluded.display_name,
        username     = coalesce(excluded.username, public.profiles.username),
        avatar_url   = coalesce(excluded.avatar_url, public.profiles.avatar_url),
        country_name = coalesce(excluded.country_name, public.profiles.country_name),
        country_code = coalesce(excluded.country_code, public.profiles.country_code),
        city_name    = coalesce(excluded.city_name, public.profiles.city_name),
        bio          = coalesce(excluded.bio, public.profiles.bio),
        birthdate    = coalesce(excluded.birthdate, public.profiles.birthdate),
        updated_at   = now();

  return new;
end;
$function$;
