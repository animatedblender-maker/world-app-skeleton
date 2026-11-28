-- Speed /v1/feed three-lane queries (was ~2s seq scan on posts from media_url ILIKE).

create index if not exists posts_home_spark_created_idx
  on public.posts (created_at desc, id desc)
  where visibility = 'public'
    and media_type in ('video', 'reel', 'spark')
    and media_url is not null
    and coalesce(media_path, '') not like '%/LongForm/%';

create index if not exists posts_home_shortform_created_idx
  on public.posts (created_at desc, id desc)
  where visibility = 'public'
    and media_type in ('video', 'reel', 'spark')
    and media_path like '%/ShortForm/%';

create index if not exists posts_home_hub_created_idx
  on public.posts (created_at desc, id desc)
  where visibility = 'public'
    and media_type = 'video'
    and media_path like '%/LongForm/%';

create index if not exists posts_home_image_created_idx
  on public.posts (created_at desc, id desc)
  where visibility = 'public'
    and lower(coalesce(media_type, '')) in ('image', 'photo', 'gif');
