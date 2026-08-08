-- Allow service_role to seed engagement rows (was missing table GRANT → 42501).
grant select, insert, update, delete on public.post_likes to service_role;
grant select, insert, update, delete on public.post_comment_likes to service_role;
grant select on public.post_like_counts to service_role;
