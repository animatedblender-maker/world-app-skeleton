-- Expand simple auto-mod: mark posts with adult keywords as sensitive (18+).
-- Same whole-word list as apps/api/src/moderation/nsfw.ts ADULT_KEYWORDS.
-- PostgreSQL: explicit boundaries (\b is not portable here).

update public.posts
set
  moderation_status = 'sensitive',
  moderation_note = coalesce(nullif(moderation_note, ''), 'auto:adult_keyword'),
  moderated_at = coalesce(moderated_at, now()),
  moderation_actor = coalesce(nullif(moderation_actor, ''), 'system:adult_keyword'),
  updated_at = now()
where coalesce(moderation_status, 'active') = 'active'
  and (
    coalesce(title, '') ~* '(^|[^a-z0-9])(nsfw|sex|sexy|sexual|porn|porno|pornography|xxx|onlyfans|hentai|erotic|nude|nudes|naked|blowjob|handjob|cumshot|orgasm|masturbate|masturbation|masturbating|gooning|milf|incest)([^a-z0-9]|$)'
    or coalesce(body, '') ~* '(^|[^a-z0-9])(nsfw|sex|sexy|sexual|porn|porno|pornography|xxx|onlyfans|hentai|erotic|nude|nudes|naked|blowjob|handjob|cumshot|orgasm|masturbate|masturbation|masturbating|gooning|milf|incest)([^a-z0-9]|$)'
  );
