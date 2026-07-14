-- Configure Supabase Storage posts bucket for large video uploads and social playback.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'posts',
  'posts',
  true,
  52428800,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4',
    'video/quicktime',
    'video/webm',
    'video/m4v',
    'application/octet-stream'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Allow any signed-in user to read post media in the posts bucket.
drop policy if exists "posts_read_authenticated_social" on storage.objects;
create policy "posts_read_authenticated_social"
on storage.objects
as permissive
for select
to authenticated
using (bucket_id = 'posts');

-- Public read so stored /object/public/posts/... URLs work in feeds and reels.
drop policy if exists "posts_read_public" on storage.objects;
create policy "posts_read_public"
on storage.objects
as permissive
for select
to public
using (bucket_id = 'posts');

-- Authenticated users upload into their own posts folder.
drop policy if exists "posts_insert_own" on storage.objects;
create policy "posts_insert_own"
on storage.objects
as permissive
for insert
to authenticated
with check (
  bucket_id = 'posts'
  and (storage.foldername(name))[1] = auth.uid()::text
);