/**
 * Collapse Stream twin uploads (same R2 pack / same title+size+duration) to one UID.
 * 1) Pick a canonical UID per fingerprint
 * 2) Repoint all posts.stream_uid in that group to the canonical
 * 3) DELETE the other Stream videos
 *
 * Usage:
 *   npm run media:stream-dedupe -- --dry-run
 *   npm run media:stream-dedupe
 */
import 'dotenv/config';
import { pool } from '../db.js';
import { streamConfigured } from './cloudflare-stream.js';

const CF_API = 'https://api.cloudflare.com/client/v4';

async function cfFetch(path: string, init?: RequestInit): Promise<any> {
  const account = process.env.CF_ACCOUNT_ID!.trim();
  const token = process.env.CF_STREAM_API_TOKEN!.trim();
  const res = await fetch(`${CF_API}/accounts/${account}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(init?.headers || {}),
    },
  });
  const json = (await res.json().catch(() => ({}))) as any;
  if (!res.ok || json?.success === false) {
    const err =
      json?.errors?.[0]?.message ||
      json?.messages?.[0] ||
      `HTTP ${res.status}`;
    throw new Error(`Cloudflare Stream: ${err}`);
  }
  return json;
}

async function listAllStreamVideos(): Promise<any[]> {
  const all: any[] = [];
  for (let page = 1; page <= 50; page++) {
    const json = await cfFetch(`/stream?per_page=100&page=${page}`);
    const batch = json.result || [];
    all.push(...batch);
    if (batch.length < 100) break;
  }
  return all;
}

function fingerprint(v: any): string {
  const key = v.meta?.r2_video_key;
  if (key) return `r2:${key}`;
  const name = String(v.meta?.name || '').trim().toLowerCase();
  const size = v.size || 0;
  const dur = Number(v.duration || 0).toFixed(2);
  return `fp:${name}|${size}|${dur}`;
}

async function main() {
  if (!streamConfigured()) {
    console.error('Missing CF_* env');
    process.exit(1);
  }
  const dry = process.argv.includes('--dry-run');

  const videos = await listAllStreamVideos();
  const groups = new Map<string, any[]>();
  for (const v of videos) {
    const fp = fingerprint(v);
    if (!groups.has(fp)) groups.set(fp, []);
    groups.get(fp)!.push(v);
  }

  const plans: {
    fp: string;
    keep: string;
    drop: string[];
    name: string;
  }[] = [];

  for (const [fp, list] of groups) {
    if (list.length < 2) continue;
    // Prefer ready + oldest created (first ingest) as canonical
    const sorted = [...list].sort((a, b) => {
      const ar = a.readyToStream ? 1 : 0;
      const br = b.readyToStream ? 1 : 0;
      if (br !== ar) return br - ar;
      return String(a.created).localeCompare(String(b.created));
    });
    const keep = sorted[0].uid as string;
    const drop = sorted.slice(1).map((v) => v.uid as string);
    plans.push({
      fp: fp.slice(0, 100),
      keep,
      drop,
      name: String(sorted[0].meta?.name || '').slice(0, 50),
    });
  }

  const dropCount = plans.reduce((n, p) => n + p.drop.length, 0);
  console.log(
    JSON.stringify(
      {
        dry,
        stream_total: videos.length,
        duplicate_groups: plans.length,
        will_delete: dropCount,
        sample: plans.slice(0, 6),
      },
      null,
      2
    )
  );

  if (dry || !plans.length) {
    await pool.end();
    return;
  }

  let repointed = 0;
  let deleted = 0;
  let failed = 0;

  for (const plan of plans) {
    // Repoint DB rows from drop UIDs → keep
    for (const dropUid of plan.drop) {
      const r = await pool.query(
        `
        update public.posts
        set stream_uid = $1,
            stream_ready_at = coalesce(stream_ready_at, now())
        where stream_uid = $2
        `,
        [plan.keep, dropUid]
      );
      repointed += r.rowCount ?? 0;
    }
    for (const dropUid of plan.drop) {
      try {
        await cfFetch(`/stream/${encodeURIComponent(dropUid)}`, { method: 'DELETE' });
        deleted += 1;
        console.log(`[dedupe] deleted ${dropUid} → keep ${plan.keep} (${plan.name})`);
      } catch (err: any) {
        failed += 1;
        console.error(`[dedupe] fail delete ${dropUid}`, err?.message ?? err);
      }
    }
  }

  const { rows } = await pool.query<{ n: string }>(
    `select count(distinct stream_uid)::text as n from public.posts where stream_uid is not null`
  );
  console.log(
    JSON.stringify(
      {
        repointed_posts: repointed,
        deleted,
        failed,
        distinct_stream_uids_in_db: Number(rows[0]?.n || 0),
      },
      null,
      2
    )
  );
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
