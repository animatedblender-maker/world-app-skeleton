-- Channel cover / banner image (separate from avatar).
alter table public.channels
  add column if not exists cover_url text;
