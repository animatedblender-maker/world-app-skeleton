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

alter table public.post_comment_likes enable row level security;

drop policy if exists post_comment_likes_select_if_comment_readable on public.post_comment_likes;
create policy post_comment_likes_select_if_comment_readable
  on public.post_comment_likes
  for select
  using (
    exists (
      select 1
      from public.post_comments c
      join public.posts p on p.id = c.post_id
      where c.id = post_comment_likes.comment_id
        and (
          p.visibility in ('public', 'country')
          or p.author_id = auth.uid()
          or (
            p.visibility = 'followers'
            and auth.uid() is not null
            and exists (
              select 1
              from public.user_follows f
              where f.follower_id = auth.uid() and f.following_id = p.author_id
            )
          )
        )
    )
  );

drop policy if exists post_comment_likes_insert_own on public.post_comment_likes;
create policy post_comment_likes_insert_own
  on public.post_comment_likes
  for insert
  with check (auth.uid() = user_id);

drop policy if exists post_comment_likes_delete_own on public.post_comment_likes;
create policy post_comment_likes_delete_own
  on public.post_comment_likes
  for delete
  using (auth.uid() = user_id);