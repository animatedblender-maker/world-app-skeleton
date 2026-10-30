-- Mark posts that contain the NSFW word as sensitive (18+).
-- Under-18 viewers are filtered out in /v1/feed and /v1/sparks.
-- PostgreSQL: use explicit boundaries (\b is not portable here).

update public.posts
set
  moderation_status = 'sensitive',
  moderation_note = coalesce(nullif(moderation_note, ''), 'auto:nsfw_keyword'),
  moderated_at = coalesce(moderated_at, now()),
  moderation_actor = coalesce(nullif(moderation_actor, ''), 'system:nsfw_keyword'),
  updated_at = now()
where coalesce(moderation_status, 'active') = 'active'
  and (
    coalesce(title, '') ~* '(^|[^a-z0-9])nsfw([^a-z0-9]|$)'
    or coalesce(body, '') ~* '(^|[^a-z0-9])nsfw([^a-z0-9]|$)'
  );
