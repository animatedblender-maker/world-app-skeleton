/**
 * Collapse Stream twin uploads (same R2 pack / same title+size+duration) to one UID.
 * 1) Pick a canonical UID per fingerprint
 * 2) Repoint all posts.stream_uid in that group to the canonical
 * 3) DELETE the other Stream videos
 *
 * Usage:
 *   npm run media:stream-dedupe -- --dry-run
 *   npm run media:stream-dedupe
 *
 * Note: Cloudflare's /stream list can repeat the same uid across pages —
 * we uniquify by uid before grouping so we never DELETE the keep uid.
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
  const byUid = new Map<string, any>();
  let rawRows = 0;
  for (let page = 1; page <= 200; page++) {
    const json = await cfFetch(`/stream?per_page=100&page=${page}`);
    const batch = json.result || [];
    rawRows += batch.length;
    let newOnPage = 0;
    for (const v of batch) {
      const uid = String(v.uid || '');
      if (!uid) continue;
      if (!byUid.has(uid)) {
        byUid.set(uid, v);
        newOnPage += 1;
      }
    }
    if (batch.length < 100) break;
    // Cloudflare sometimes re-serves the same page of uids — stop when no progress.
    if (newOnPage === 0) break;
  }
  console.error(
    `[dedupe] listed raw_rows=${rawRows} unique_uids=${byUid.size}`
  );
  return [...byUid.values()];
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
  let storedMinutes = 0;
  const groups = new Map<string, any[]>();
  for (const v of videos) {
    storedMinutes += Number(v.duration || 0) / 60;
    const fp = fingerprint(v);
    if (!groups.has(fp)) groups.set(fp, []);
    groups.get(fp)!.push(v);
  }

  const plans: {
    fp: string;
    keep: string;
    drop: string[];
    name: string;
    drop_minutes: number;
  }[] = [];

  for (const [fp, list] of groups) {
    // Unique by uid inside the group (defensive).
    const byUid = new Map<string, any>();
    for (const v of list) byUid.set(String(v.uid), v);
    const unique = [...byUid.values()];
    if (unique.length < 2) continue;

    // Prefer ready + oldest created (first ingest) as canonical
    const sorted = [...unique].sort((a, b) => {
      const ar = a.readyToStream ? 1 : 0;
      const br = b.readyToStream ? 1 : 0;
      if (br !== ar) return br - ar;
      return String(a.created).localeCompare(String(b.created));
    });
    const keep = String(sorted[0].uid);
    const drop = sorted
      .slice(1)
      .map((v) => String(v.uid))
      .filter((uid) => uid && uid !== keep);
    if (!drop.length) continue;
    const dropMinutes = sorted
      .slice(1)
      .reduce((n, v) => n + Number(v.duration || 0) / 60, 0);
    plans.push({
      fp: fp.slice(0, 100),
      keep,
      drop,
      name: String(sorted[0].meta?.name || '').slice(0, 50),
      drop_minutes: Math.round(dropMinutes * 10) / 10,
    });
  }

  const dropCount = plans.reduce((n, p) => n + p.drop.length, 0);
  const reclaimMinutes = plans.reduce((n, p) => n + p.drop_minutes, 0);
  console.log(
    JSON.stringify(
      {
        dry,
        stream_unique: videos.length,
        stored_minutes: Math.round(storedMinutes * 10) / 10,
        duplicate_groups: plans.length,
        will_delete: dropCount,
        reclaim_minutes_est: Math.round(reclaimMinutes * 10) / 10,
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
  const deletedUids = new Set<string>();

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
      if (dropUid === plan.keep) continue;
      if (deletedUids.has(dropUid)) continue;
      try {
        await cfFetch(`/stream/${encodeURIComponent(dropUid)}`, { method: 'DELETE' });
        deletedUids.add(dropUid);
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
