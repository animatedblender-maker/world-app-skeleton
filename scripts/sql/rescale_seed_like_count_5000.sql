-- =============================================================================
-- One-shot: fix R2 / catalog Sparks stuck at like_count = 5000
--
-- Cause: content pipeline used Math.min(5000, digg|like|play_count|views…),
-- so view counts ≥ 5000 all stored as exactly 5000.
--
-- This rescales those seed floors to a deterministic 15–899 range from post id
-- (varied, not all the same). Real Matterya likes still win when
-- count(post_likes) > like_count (API uses greatest(...)).
--
-- Run in Supabase SQL editor (or psql) against production.
-- Review SELECT first, then run UPDATE.
-- =============================================================================

-- Preview how many rows will change
SELECT
  count(*) AS rows_at_5000,
  count(*) FILTER (
    WHERE media_path LIKE 'r2:%'
       OR media_path LIKE 'r2-share:%'
       OR media_path LIKE 'r2-hubshare:%'
  ) AS r2_related
FROM public.posts
WHERE like_count = 5000;

-- Optional: sample before
-- SELECT id, like_count, left(coalesce(media_path, ''), 60) AS path
-- FROM public.posts WHERE like_count = 5000 LIMIT 20;

BEGIN;

UPDATE public.posts p
SET
  like_count = 15 + (
    -- Deterministic 0..884 from md5(id) so re-runs stay stable
    (('x' || substr(md5(p.id::text), 1, 8))::bit(32)::bigint % 885)
  )::int,
  updated_at = now()
WHERE p.like_count = 5000
  AND (
    -- R2 catalog originals / shares / hub-shares
    coalesce(p.media_path, '') LIKE 'r2:%'
    OR coalesce(p.media_path, '') LIKE 'r2-share:%'
    OR coalesce(p.media_path, '') LIKE 'r2-hubshare:%'
    -- Spark markers
    OR position('__spark__|' in coalesce(p.body, '')) > 0
    OR lower(coalesce(p.media_type, '')) IN ('reel', 'spark')
    OR position('"reel":true' in lower(coalesce(p.media_url, ''))) > 0
    OR position('"source":"r2' in lower(coalesce(p.media_url, ''))) > 0
  );

-- Rows still at 5000 after (e.g. real user posts that somehow hit exactly 5000 — leave them)
-- SELECT count(*) FROM public.posts WHERE like_count = 5000;

COMMIT;

-- Verify distribution
SELECT
  min(like_count) AS min_likes,
  max(like_count) AS max_likes,
  round(avg(like_count)) AS avg_likes,
  count(*) FILTER (WHERE like_count = 5000) AS still_exactly_5000
FROM public.posts
WHERE
  coalesce(media_path, '') LIKE 'r2:%'
  OR position('__spark__|' in coalesce(body, '')) > 0;
