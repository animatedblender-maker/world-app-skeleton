-- Masquerade posts: image / video attachments (Matterya Spaces).
-- Safe to re-run.

alter table anonymous.posts
  add column if not exists media_type text;

alter table anonymous.posts
  add column if not exists media_url text;

alter table anonymous.posts
  add column if not exists thumb_url text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'anonymous_posts_media_type_check'
  ) then
    alter table anonymous.posts
      add constraint anonymous_posts_media_type_check
      check (media_type is null or media_type in ('image', 'video', 'gif'));
  end if;
end $$;

comment on column anonymous.posts.media_type is 'Optional attachment kind for Masquerade Space posts';
comment on column anonymous.posts.media_url is 'Public or signed URL for image/video';
comment on column anonymous.posts.thumb_url is 'Optional poster/thumb for video posts';
