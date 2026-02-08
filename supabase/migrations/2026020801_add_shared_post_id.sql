-- Add support for shared posts referencing an original post
alter table public.posts
  add column if not exists shared_post_id uuid references public.posts(id) on delete set null;

create index if not exists posts_shared_post_id_idx on public.posts(shared_post_id);
