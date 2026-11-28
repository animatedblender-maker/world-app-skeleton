/**
 * Copy Sparks (ShortForm) from R2 → Cloudflare Stream for HLS playback.
 *
 * Usage:
 *   cd apps/api
 *   npm run media:stream-ingest -- --limit=20
 *   npm run media:stream-ingest -- --limit=50 --concurrency=2
 *
 * Requires in .env (or Render):
 *   CF_ACCOUNT_ID, CF_STREAM_API_TOKEN, CF_STREAM_CUSTOMER_CODE
 *   DATABASE_URL, R2_*
 */
import 'dotenv/config';
import { pool } from '../db.js';
import { ingestPostToStream, streamConfigured } from './cloudflare-stream.js';

type Row = {
  id: string;
  title: string | null;
  media_url: string | null;
  media_path: string | null;
};

function arg(name: string, fallback?: string): string | undefined {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  if (hit) return hit.slice(name.length + 3);
  if (process.argv.includes(`--${name}`)) return 'true';
  return fallback;
}

async function main() {
  if (!streamConfigured()) {
    console.error(
      'Missing CF_ACCOUNT_ID / CF_STREAM_API_TOKEN / CF_STREAM_CUSTOMER_CODE — add to apps/api/.env or Render'
    );
    process.exit(1);
  }

  const limit = Math.min(Math.max(Number(arg('limit', '20')) || 20, 1), 200);
  const concurrency = Math.min(Math.max(Number(arg('concurrency', '2')) || 2, 1), 4);
  const dry = arg('dry-run') === 'true' || process.argv.includes('--dry-run');

  // Prefer Home Feed ShortForm head (same shape users scroll) without stream_uid yet.
  const feedHead = process.argv.includes('--feed-head');
  const { rows } = await pool.query<Row>(
    feedHead
      ? `
    select
      p.id,
      p.title,
      p.media_url,
      p.media_path
    from public.posts p
    where p.stream_uid is null
      and coalesce(p.moderation_status, 'active') in ('active', 'sensitive')
      and coalesce(p.media_path, '') not like '%/LongForm/%'
      and (
        coalesce(p.media_path, '') like '%/ShortForm/%'
        or p.media_url ilike '%ShortForm%'
        or p.media_type in ('video', 'reel', 'spark')
      )
      and (p.media_url is not null or p.media_path is not null)
    order by
      case when coalesce(p.media_path, '') like '%/ShortForm/%' then 0 else 1 end,
      greatest(p.updated_at, p.created_at) desc nulls last
    limit $1
    `
      : `
    select
      p.id,
      p.title,
      p.media_url,
      p.media_path
    from public.posts p
    where p.stream_uid is null
      and coalesce(p.moderation_status, 'active') in ('active', 'sensitive')
      and (
        p.media_type in ('video', 'reel', 'spark')
        or p.media_url ilike '%ShortForm%'
        or p.media_url ilike '%shortform%'
        or p.media_path ilike '%ShortForm%'
        or p.media_url ilike '%/video.mp4%'
        or p.media_path ilike '%/video.mp4%'
      )
      and (
        p.media_url is not null
        or p.media_path is not null
      )
    order by greatest(p.updated_at, p.created_at) desc nulls last
    limit $1
    `,
    [limit]
  );

  console.log(
    JSON.stringify(
      { ok: true, candidates: rows.length, limit, concurrency, dry },
      null,
      2
    )
  );

  if (!rows.length || dry) {
    await pool.end();
    return;
  }

  let ok = 0;
  let fail = 0;
  let idx = 0;

  async function worker() {
    while (idx < rows.length) {
      const i = idx++;
      const row = rows[i];
      try {
        const result = await ingestPostToStream({
          id: row.id,
          title: row.title,
          media_url: row.media_url,
          media_path: row.media_path,
        });
        if (result?.uid) {
          ok += 1;
          console.log(
            `[stream] ${result.reused ? 'reuse' : 'ok'} post=${row.id} uid=${result.uid} ready=${result.ready} hls=${result.hls ? 'yes' : 'no'}`
          );
        } else {
          fail += 1;
          console.warn(`[stream] skip post=${row.id} (no r2 key or copy failed)`);
        }
      } catch (err: any) {
        fail += 1;
        console.error(`[stream] fail post=${row.id}`, err?.message ?? err);
      }
    }
  }

  await Promise.all(Array.from({ length: concurrency }, () => worker()));
  console.log(JSON.stringify({ ok, fail, total: rows.length }, null, 2));
  await pool.end();
}

main().catch(async (err) => {
  console.error(err);
  try {
    await pool.end();
  } catch {
    /* ignore */
  }
  process.exit(1);
});
