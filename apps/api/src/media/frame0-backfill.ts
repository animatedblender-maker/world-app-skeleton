/**
 * Zero-worker Frame 0 backfill — one-shot CLI (Mac / CI / temp box).
 *
 * Default: run ffmpeg extract **inline** (no Kafka, no permanent worker).
 *
 *   cd apps/api
 *   npm run media:frame0-backfill
 *   npm run media:frame0-backfill -- --limit=20
 *   npm run media:frame0-backfill -- --dry-run
 *   npm run media:frame0-backfill -- --concurrency=4
 *   npm run media:frame0-backfill -- --via-kafka   # optional: enqueue only (needs consumer)
 *
 * Hard rule: poster = first displayed video frame (t=0). See docs/MEDIA_FRAME0.md
 */
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getBucket } from '../content-pipeline/r2.js';
import { enqueueMediaProcessJob } from './enqueue.js';
import {
  ffmpegAvailable,
  frame0DerivativesExist,
  listPostsNeedingFrame0,
  processFrame0,
  resolveFfmpegPath,
} from './frame0.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '..', '.env'), override: true });

function argValue(args: string[], name: string): string | undefined {
  const hit = args.find((a) => a.startsWith(`${name}=`));
  return hit?.slice(name.length + 1);
}

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const viaKafka = args.includes('--via-kafka');
const limit = Math.max(1, Number(argValue(args, '--limit') || 50) || 50);
const concurrencyRaw = Number(argValue(args, '--concurrency') || 4) || 4;
const concurrency = Math.min(8, Math.max(1, concurrencyRaw));

async function mapPool<T, R>(
  items: T[],
  pool: number,
  fn: (item: T, index: number) => Promise<R>
): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]!, i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(pool, items.length) }, () => worker()));
  return out;
}

const hasFf = await ffmpegAvailable();
if (!viaKafka && !dryRun && !hasFf) {
  console.error(
    `[frame0-backfill] ffmpeg not available (tried ${resolveFfmpegPath()}). ` +
      'Install ffmpeg, or rely on ffmpeg-static in node_modules.'
  );
  process.exit(1);
}

const rows = await listPostsNeedingFrame0(limit);
console.log(
  `[frame0-backfill] mode=${viaKafka ? 'kafka-enqueue' : 'inline'} ` +
    `candidates=${rows.length} dryRun=${dryRun} limit=${limit} concurrency=${concurrency} ` +
    `ffmpeg=${hasFf ? resolveFfmpegPath() : 'n/a'}`
);

let ok = 0;
let skipped = 0;
let failed = 0;

if (viaKafka) {
  for (const row of rows) {
    if (dryRun) {
      console.log(`  would enqueue post=${row.postId} key=${row.r2Key}`);
      ok += 1;
      continue;
    }
    const r = await enqueueMediaProcessJob({
      postId: row.postId,
      r2Key: row.r2Key,
      r2Bucket: getBucket(),
      mediaPath: row.mediaPath,
      source: 'backfill',
      requestedOutputs: 'frame0',
      requestedBy: 'frame0-backfill-cli',
    });
    if (r.enqueued) ok += 1;
    else {
      failed += 1;
      console.warn(`  enqueue failed post=${row.postId}: ${r.error}`);
    }
  }
} else {
  const results = await mapPool(rows, dryRun ? 1 : concurrency, async (row) => {
    const bucket = getBucket();
    if (dryRun) {
      const exists = await frame0DerivativesExist(row.r2Key, bucket).catch(() => false);
      console.log(
        `  would ${exists ? 'refresh-db' : 'extract'} post=${row.postId} key=${row.r2Key}`
      );
      return exists ? ('skipped' as const) : ('ok' as const);
    }
    try {
      const existed = await frame0DerivativesExist(row.r2Key, bucket);
      const ready = await processFrame0({
        postId: row.postId,
        r2Bucket: bucket,
        r2Key: row.r2Key,
        source: 'backfill',
        requestedOutputs: 'frame0',
        mediaPath: row.mediaPath,
        requestedBy: 'frame0-backfill-cli',
        requestedAt: new Date().toISOString(),
      });
      console.log(
        `  ${existed ? 'refreshed' : 'ready'} post=${row.postId} outputs=${ready.outputs.length} thumb=${ready.thumbPath}`
      );
      return existed ? ('skipped' as const) : ('ok' as const);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(`  FAILED post=${row.postId} key=${row.r2Key}: ${msg}`);
      return 'failed' as const;
    }
  });
  for (const r of results) {
    if (r === 'ok') ok += 1;
    else if (r === 'skipped') skipped += 1;
    else failed += 1;
  }
}

const summary = {
  ok: failed === 0,
  mode: viaKafka ? 'kafka-enqueue' : 'inline',
  candidates: rows.length,
  processedOrEnqueued: ok,
  skippedExisting: skipped,
  failed,
  concurrency: viaKafka ? 1 : concurrency,
};
console.log(JSON.stringify(summary, null, 2));
process.exit(failed === 0 ? 0 : 1);
