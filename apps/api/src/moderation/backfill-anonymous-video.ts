/**
 * One-shot / resumable local NSFW scan for existing Masquerade video posts.
 *
 * Usage (from apps/api):
 *   npx tsx src/moderation/backfill-anonymous-video.ts
 *   npx tsx src/moderation/backfill-anonymous-video.ts --limit=200
 *   npx tsx src/moderation/backfill-anonymous-video.ts --dry-run
 *
 * Skips posts that already have an auto_scan_video_* / auto_flag_nsfw_video action.
 * Frames never leave the host (see video-local.ts).
 */
import 'dotenv/config';
import { pool } from '../db.js';
import { moderateAnonymousPost } from './anonymous-auto.js';

type Row = {
  id: string;
  space_id: string;
  title: string | null;
  body: string | null;
  media_type: string | null;
  media_url: string | null;
  space_slug: string;
  space_category: string | null;
};

function argFlag(name: string): boolean {
  return process.argv.includes(name);
}

function argValue(name: string): string | null {
  const pref = `${name}=`;
  const hit = process.argv.find((a) => a.startsWith(pref));
  return hit ? hit.slice(pref.length) : null;
}

async function alreadyScanned(postId: string): Promise<boolean> {
  // Failures are retryable — only successful scans / holds skip.
  const { rows } = await pool.query<{ n: string }>(
    `
    select count(*)::text as n
    from anonymous.moderation_actions
    where target_type = 'post'
      and target_id = $1::uuid
      and action in (
        'auto_scan_video_ok',
        'auto_flag_nsfw_video',
        'auto_hold'
      )
    `,
    [postId]
  );
  return Number(rows[0]?.n || 0) > 0;
}

async function main(): Promise<number> {
  const dryRun = argFlag('--dry-run');
  const limit = Math.max(1, Number(argValue('--limit') || 5000) || 5000);
  const onlySlug = argValue('--space'); // optional filter

  console.log(
    `[backfill-anon-video] limit=${limit} dryRun=${dryRun} space=${onlySlug || '*'}`
  );

  const params: unknown[] = [];
  let spaceClause = '';
  if (onlySlug) {
    params.push(onlySlug);
    spaceClause = `and s.slug = $${params.length}`;
  }
  params.push(limit);

  const { rows } = await pool.query<Row>(
    `
    select p.id, p.space_id, p.title, p.body, p.media_type, p.media_url,
           s.slug as space_slug, s.category as space_category
    from anonymous.posts p
    join anonymous.spaces s on s.id = p.space_id
    where p.media_type = 'video'
      and p.state = 'active'
      and p.media_url is not null
      and btrim(p.media_url) <> ''
      ${spaceClause}
    order by p.created_at desc
    limit $${params.length}
    `,
    params
  );

  console.log(`[backfill-anon-video] candidates=${rows.length}`);

  let scanned = 0;
  let skipped = 0;
  let held = 0;
  let flagged = 0;
  let failed = 0;

  for (const row of rows) {
    if (await alreadyScanned(row.id)) {
      skipped += 1;
      continue;
    }
    if (dryRun) {
      console.log(`[dry] would scan ${row.id} @${row.space_slug}`);
      scanned += 1;
      continue;
    }

    const started = Date.now();
    try {
      const result = await moderateAnonymousPost({
        postId: row.id,
        spaceId: row.space_id,
        spaceSlug: row.space_slug,
        spaceCategory: row.space_category,
        title: row.title,
        body: row.body,
        mediaType: row.media_type,
        mediaUrl: row.media_url,
      });
      scanned += 1;
      if (result?.held) held += 1;
      if (result?.flagged) flagged += 1;
      if (result?.video && !result.video.ok) failed += 1;
      const ms = Date.now() - started;
      console.log(
        `[ok] ${row.id.slice(0, 8)} @${row.space_slug} flagged=${!!result?.flagged} held=${!!result?.held} ` +
          `nsfw=${result?.video?.ok ? result.video.maxNsfw.toFixed(3) : result?.video?.error || 'n/a'} ${ms}ms`
      );
    } catch (err: any) {
      failed += 1;
      console.warn(`[err] ${row.id} ${err?.message ?? err}`);
    }

    if (scanned > 0 && scanned % 25 === 0) {
      console.log(
        `[progress] scanned=${scanned} skipped=${skipped} held=${held} flagged=${flagged} failed=${failed}`
      );
    }
  }

  console.log(
    `[done] scanned=${scanned} skipped=${skipped} held=${held} flagged=${flagged} failed=${failed}`
  );
  return 0;
}

main()
  .then((code) => {
    void pool.end().catch(() => undefined);
    process.exit(code);
  })
  .catch((err) => {
    console.error(err);
    void pool.end().catch(() => undefined);
    process.exit(1);
  });
