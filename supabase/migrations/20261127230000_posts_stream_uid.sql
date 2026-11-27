-- Cloudflare Stream playback plane (Feed/Sparks HLS).
-- R2 remains archive/source; stream_uid is set when Stream copy is readyToStream.

alter table public.posts
  add column if not exists stream_uid text;

alter table public.posts
  add column if not exists stream_ready_at timestamptz;

create index if not exists posts_stream_uid_idx
  on public.posts (stream_uid)
  where stream_uid is not null;

comment on column public.posts.stream_uid is
  'Cloudflare Stream video UID; HLS at customer-<code>.cloudflarestream.com/<uid>/manifest/video.m3u8';
comment on column public.posts.stream_ready_at is
  'When Stream reported readyToStream for this post';
