-- Slug-first Hubs shelves: optional stored parent/persona slug on posts.
-- API classifies from title/body when null; when set, SQL can filter cheaply.

alter table public.posts
  add column if not exists hub_slug text;

comment on column public.posts.hub_slug is
  'Hubs shelf slug (parent e.g. music, or persona e.g. music_jazz). Null = classify at serve time.';

create index if not exists posts_hub_slug_created_idx
  on public.posts (hub_slug, created_at desc)
  where hub_slug is not null
    and media_url is not null
    and visibility = 'public';
