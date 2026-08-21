/**
 * Zero-worker Frame 0 backfill — one-shot CLI (Mac / CI / temp box).
 *
 * Default: run ffmpeg extract **inline** (no Kafka, no permanent worker).
 *
 *   cd apps/api
 *   npm run media:frame0-backfill
 *   npm run media:frame0-backfill -- --all
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
import { appendFile, mkdir } from 'node:fs/promises';
import { getBucket, r2Configured } from '../content-pipeline/r2.js';
import { enqueueMediaProcessJob } from './enqueue.js';
import {
  ffmpegAvailable,
  frame0DerivativesExist,
  listPostsNeedingFrame0,
  processFrame0,
  resolveFfmpegPath,
} from './frame0.js';
import {
  FRAME0_LOG_FILE,
  FRAME0_PROGRESS_DIR,
  writeFrame0Progress,
} from './frame0-progress.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '..', '.env'), override: true });

await mkdir(FRAME0_PROGRESS_DIR, { recursive: true }).catch(() => undefined);

async function logLine(msg: string): Promise<void> {
  const line = msg.endsWith('\n') ? msg : `${msg}\n`;
  process.stdout.write(line);
  await appendFile(FRAME0_LOG_FILE, line, 'utf8').catch(() => undefined);
}

function argValue(args: string[], name: string): string | undefined {
  const hit = args.find((a) => a.startsWith(`${name}=`));
  return hit?.slice(name.length + 1);
}

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const viaKafka = args.includes('--via-kafka');
/** Re-extract even when frame0_*.webp exist (fix SAR/aspect mismatches). */
const force = args.includes('--force');
/** `--all`, `--limit=0`, or omit `--limit` → every post missing Frame 0. */
const limitArg = argValue(args, '--limit');
const all = args.includes('--all') || limitArg === '0' || limitArg === undefined;
const limit = all ? 0 : Math.max(1, Number(limitArg) || 0);
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

if (!viaKafka && !dryRun && !r2Configured()) {
  console.error(
    '[frame0-backfill] R2 not configured. Set in apps/api/.env:\n' +
      '  R2_ACCESS_KEY_ID\n' +
      '  R2_SECRET_ACCESS_KEY   ← usually the missing one\n' +
      '  R2_ACCOUNT_ID  (or R2_ENDPOINT)\n' +
      '  R2_BUCKET=matterya-sparks\n' +
      'Copy from Render → matterya-api → Environment.'
  );
  process.exit(1);
}

const rows = await listPostsNeedingFrame0(limit);
const startedAt = new Date().toISOString();
await logLine(
  `[frame0-backfill] mode=${viaKafka ? 'kafka-enqueue' : 'inline'} ` +
    `candidates=${rows.length} dryRun=${dryRun} force=${force} limit=${limit} concurrency=${concurrency} ` +
    `ffmpeg=${hasFf ? resolveFfmpegPath() : 'n/a'}`
);

let ok = 0;
let skipped = 0;
let failed = 0;

await writeFrame0Progress({
  running: true,
  mode: viaKafka ? 'kafka-enqueue' : 'inline',
  dryRun,
  force,
  limit,
  concurrency: viaKafka ? 1 : concurrency,
  candidates: rows.length,
  ok: 0,
  skipped: 0,
  failed: 0,
  processed: 0,
  startedAt,
  finishedAt: null,
  pid: process.pid,
  logPath: FRAME0_LOG_FILE,
});

/** Serialize progress writes so concurrent workers don't clobber counters. */
let bumpChain: Promise<void> = Promise.resolve();
function bump(partial: {
  deltaOk?: number;
  deltaSkipped?: number;
  deltaFailed?: number;
  lastPostId?: string;
  lastThumbPath?: string;
  lastError?: string | null;
}): Promise<void> {
  bumpChain = bumpChain.then(async () => {
    if (partial.deltaOk) ok += partial.deltaOk;
    if (partial.deltaSkipped) skipped += partial.deltaSkipped;
    if (partial.deltaFailed) failed += partial.deltaFailed;
    await writeFrame0Progress({
      running: true,
      mode: viaKafka ? 'kafka-enqueue' : 'inline',
      dryRun,
      force,
      limit,
      concurrency: viaKafka ? 1 : concurrency,
      candidates: rows.length,
      ok,
      skipped,
      failed,
      processed: ok + skipped + failed,
      startedAt,
      lastPostId: partial.lastPostId,
      lastThumbPath: partial.lastThumbPath,
      lastError: partial.lastError === undefined ? undefined : partial.lastError,
      pid: process.pid,
      logPath: FRAME0_LOG_FILE,
    });
  });
  return bumpChain;
}

if (viaKafka) {
  for (const row of rows) {
    if (dryRun) {
      await logLine(`  would enqueue post=${row.postId} key=${row.r2Key}`);
      await bump({ deltaOk: 1, lastPostId: row.postId, lastError: null });
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
    if (r.enqueued) {
      await bump({ deltaOk: 1, lastPostId: row.postId, lastError: null });
    } else {
      await logLine(`  enqueue failed post=${row.postId}: ${r.error}`);
      await bump({
        deltaFailed: 1,
        lastPostId: row.postId,
        lastError: r.error || 'enqueue failed',
      });
    }
  }
} else {
  await mapPool(rows, dryRun ? 1 : concurrency, async (row) => {
    const bucket = getBucket();
    if (dryRun) {
      const exists = !force && (await frame0DerivativesExist(row.r2Key, bucket).catch(() => false));
      await logLine(
        `  would ${exists ? 'refresh-db' : 'extract'} post=${row.postId} key=${row.r2Key}`
      );
      if (exists) {
        await bump({ deltaSkipped: 1, lastPostId: row.postId, lastError: null });
        return 'skipped' as const;
      }
      await bump({ deltaOk: 1, lastPostId: row.postId, lastError: null });
      return 'ok' as const;
    }
    try {
      const existed = !force && (await frame0DerivativesExist(row.r2Key, bucket));
      const ready = await processFrame0(
        {
          postId: row.postId,
          r2Bucket: bucket,
          r2Key: row.r2Key,
          source: 'backfill',
          requestedOutputs: 'frame0',
          mediaPath: row.mediaPath,
          requestedBy: 'frame0-backfill-cli',
          requestedAt: new Date().toISOString(),
        },
        { force }
      );
      await logLine(
        `  ${existed ? 'refreshed' : 'ready'} post=${row.postId} outputs=${ready.outputs.length} thumb=${ready.thumbPath}`
      );
      if (existed) {
        await bump({
          deltaSkipped: 1,
          lastPostId: row.postId,
          lastThumbPath: ready.thumbPath,
          lastError: null,
        });
        return 'skipped' as const;
      }
      await bump({
        deltaOk: 1,
        lastPostId: row.postId,
        lastThumbPath: ready.thumbPath,
        lastError: null,
      });
      return 'ok' as const;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      await logLine(`  FAILED post=${row.postId} key=${row.r2Key}: ${msg}`);
      await bump({ deltaFailed: 1, lastPostId: row.postId, lastError: msg });
      return 'failed' as const;
    }
  });
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
await logLine(JSON.stringify(summary, null, 2));
await writeFrame0Progress({
  running: false,
  mode: viaKafka ? 'kafka-enqueue' : 'inline',
  dryRun,
  force,
  limit,
  concurrency: viaKafka ? 1 : concurrency,
  candidates: rows.length,
  ok,
  skipped,
  failed,
  processed: ok + skipped + failed,
  startedAt,
  finishedAt: new Date().toISOString(),
  pid: process.pid,
  logPath: FRAME0_LOG_FILE,
  lastError: failed ? `${failed} failed` : null,
});
process.exit(failed === 0 ? 0 : 1);
