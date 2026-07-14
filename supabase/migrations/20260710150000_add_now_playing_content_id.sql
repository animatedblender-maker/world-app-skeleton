alter table public.now_playing_status
  add column if not exists content_id text;