-- Allow any signed-in user to read post media in the posts bucket.
-- Post visibility is enforced in public.posts; media objects are social content.
drop policy if exists "posts_read_authenticated_social" on storage.objects;
create policy "posts_read_authenticated_social"
on storage.objects
as permissive
for select
to authenticated
using (bucket_id = 'posts');