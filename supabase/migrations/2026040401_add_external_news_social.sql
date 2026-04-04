create table if not exists public.external_news_comments (
  id uuid primary key default gen_random_uuid(),
  news_item_id text not null,
  parent_id uuid references public.external_news_comments(id) on delete set null,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint external_news_comments_body_check check (char_length(body) between 1 and 5000)
);

create table if not exists public.external_news_likes (
  news_item_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (news_item_id, user_id)
);

create table if not exists public.external_news_shares (
  id uuid primary key default gen_random_uuid(),
  news_item_id text not null,
  post_id uuid not null unique references public.posts(id) on delete cascade,
  shared_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists external_news_comments_item_idx
  on public.external_news_comments(news_item_id, created_at desc);

create index if not exists external_news_comments_author_idx
  on public.external_news_comments(author_id, created_at desc);

create index if not exists external_news_likes_item_idx
  on public.external_news_likes(news_item_id, created_at desc);

create index if not exists external_news_shares_item_idx
  on public.external_news_shares(news_item_id, created_at desc);

alter table public.external_news_comments enable row level security;
alter table public.external_news_likes enable row level security;
alter table public.external_news_shares enable row level security;

drop policy if exists "external_news_comments_select_authed" on public.external_news_comments;
create policy "external_news_comments_select_authed"
  on public.external_news_comments
  for select
  to authenticated
  using (true);

drop policy if exists "external_news_comments_insert_own" on public.external_news_comments;
create policy "external_news_comments_insert_own"
  on public.external_news_comments
  for insert
  to authenticated
  with check (auth.uid() = author_id);

drop policy if exists "external_news_comments_update_own" on public.external_news_comments;
create policy "external_news_comments_update_own"
  on public.external_news_comments
  for update
  to authenticated
  using (auth.uid() = author_id)
  with check (auth.uid() = author_id);

drop policy if exists "external_news_comments_delete_own" on public.external_news_comments;
create policy "external_news_comments_delete_own"
  on public.external_news_comments
  for delete
  to authenticated
  using (auth.uid() = author_id);

drop policy if exists "external_news_likes_select_authed" on public.external_news_likes;
create policy "external_news_likes_select_authed"
  on public.external_news_likes
  for select
  to authenticated
  using (true);

drop policy if exists "external_news_likes_insert_own" on public.external_news_likes;
create policy "external_news_likes_insert_own"
  on public.external_news_likes
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "external_news_likes_delete_own" on public.external_news_likes;
create policy "external_news_likes_delete_own"
  on public.external_news_likes
  for delete
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "external_news_shares_select_authed" on public.external_news_shares;
create policy "external_news_shares_select_authed"
  on public.external_news_shares
  for select
  to authenticated
  using (true);

drop policy if exists "external_news_shares_insert_own" on public.external_news_shares;
create policy "external_news_shares_insert_own"
  on public.external_news_shares
  for insert
  to authenticated
  with check (auth.uid() = shared_by);

drop trigger if exists trg_external_news_comments_updated_at on public.external_news_comments;
create trigger trg_external_news_comments_updated_at
before update on public.external_news_comments
for each row execute function public.set_updated_at();
