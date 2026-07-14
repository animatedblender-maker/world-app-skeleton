create table if not exists public.post_comment_likes (
  comment_id uuid not null references public.post_comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

create index if not exists post_comment_likes_comment_idx
  on public.post_comment_likes (comment_id);

create index if not exists post_comment_likes_user_idx
  on public.post_comment_likes (user_id);