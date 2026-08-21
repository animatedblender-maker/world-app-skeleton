/**
 * In-process Frame 0 backfill runner — shared by CLI + Ops UI.
 * Zero permanent worker: one batch at a time, ffmpeg-static inline.
 */
import { appendFile, mkdir } from 'node:fs/promises';
import { getBucket, r2Configured } from '../content-pipeline/r2.js';
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
  getFrame0StatusPayload,
  writeFrame0Progress,
  type Frame0RunProgress,
} from './frame0-progress.js';

export type Frame0RunOpts = {
  limit?: number;
  concurrency?: number;
  force?: boolean;
  dryRun?: boolean;
  requestedBy?: string;
};

let active: Promise<void> | null = null;

export function isFrame0BackfillRunning(): boolean {
  return active != null;
}

async function logLine(msg: string): Promise<void> {
  const line = msg.endsWith('\n') ? msg : `${msg}\n`;
  process.stdout.write(line);
  await appendFile(FRAME0_LOG_FILE, line, 'utf8').catch(() => undefined);
}

async function mapPool<T>(
  items: T[],
  pool: number,
  fn: (item: T, index: number) => Promise<void>
): Promise<void> {
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      await fn(items[i]!, i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(pool, items.length) }, () => worker()));
}

/**
 * Start a backfill batch. Returns immediately if started (or already running).
 * Work continues in the background.
 */
export async function startFrame0Backfill(
  opts: Frame0RunOpts = {}
): Promise<{ started: boolean; reason?: string; run?: Partial<Frame0RunProgress> }> {
  if (active) {
    return { started: false, reason: 'already_running' };
  }
  if (!r2Configured()) {
    return { started: false, reason: 'r2_not_configured' };
  }
  const dryRun = opts.dryRun === true;
  const force = opts.force === true;
  if (!dryRun && !(await ffmpegAvailable())) {
    return {
      started: false,
      reason: `ffmpeg_unavailable:${resolveFfmpegPath()}`,
    };
  }

  // limit <= 0 → all needing posts (no batch cap).
  const rawLimit = Number(opts.limit);
  const limit =
    Number.isFinite(rawLimit) && rawLimit <= 0
      ? 0
      : Math.max(1, Number.isFinite(rawLimit) ? rawLimit : 0);
  const concurrency = Math.min(8, Math.max(1, Number(opts.concurrency) || 4));
  const requestedBy = opts.requestedBy || 'ops-ui';

  await mkdir(FRAME0_PROGRESS_DIR, { recursive: true }).catch(() => undefined);

  const runPromise = (async () => {
    const startedAt = new Date().toISOString();
    let ok = 0;
    let skipped = 0;
    let failed = 0;
    let bumpChain: Promise<void> = Promise.resolve();

    const rows = await listPostsNeedingFrame0(limit <= 0 ? 0 : limit);
    await logLine(
      `[frame0-backfill] mode=inline source=${requestedBy} candidates=${rows.length} ` +
        `dryRun=${dryRun} force=${force} limit=${limit} concurrency=${concurrency} ` +
        `ffmpeg=${await ffmpegAvailable().then((h) => (h ? resolveFfmpegPath() : 'n/a'))}`
    );

    await writeFrame0Progress({
      running: true,
      mode: 'inline',
      dryRun,
      force,
      limit,
      concurrency,
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

    const bump = (partial: {
      deltaOk?: number;
      deltaSkipped?: number;
      deltaFailed?: number;
      lastPostId?: string;
      lastThumbPath?: string;
      lastError?: string | null;
    }) => {
      bumpChain = bumpChain.then(async () => {
        if (partial.deltaOk) ok += partial.deltaOk;
        if (partial.deltaSkipped) skipped += partial.deltaSkipped;
        if (partial.deltaFailed) failed += partial.deltaFailed;
        await writeFrame0Progress({
          running: true,
          mode: 'inline',
          dryRun,
          force,
          limit,
          concurrency,
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
    };

    await mapPool(rows, dryRun ? 1 : concurrency, async (row) => {
      const bucket = getBucket();
      if (dryRun) {
        const exists =
          !force && (await frame0DerivativesExist(row.r2Key, bucket).catch(() => false));
        await logLine(
          `  would ${exists ? 'refresh-db' : 'extract'} post=${row.postId} key=${row.r2Key}`
        );
        if (exists) await bump({ deltaSkipped: 1, lastPostId: row.postId, lastError: null });
        else await bump({ deltaOk: 1, lastPostId: row.postId, lastError: null });
        return;
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
            requestedBy,
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
        } else {
          await bump({
            deltaOk: 1,
            lastPostId: row.postId,
            lastThumbPath: ready.thumbPath,
            lastError: null,
          });
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        await logLine(`  FAILED post=${row.postId} key=${row.r2Key}: ${msg}`);
        await bump({ deltaFailed: 1, lastPostId: row.postId, lastError: msg });
      }
    });

    await bumpChain;
    const summary = {
      ok: failed === 0,
      mode: 'inline',
      candidates: rows.length,
      processedOrEnqueued: ok,
      skippedExisting: skipped,
      failed,
      concurrency,
      requestedBy,
    };
    await logLine(JSON.stringify(summary, null, 2));
    await writeFrame0Progress({
      running: false,
      mode: 'inline',
      dryRun,
      force,
      limit,
      concurrency,
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
  })();

  active = runPromise.finally(() => {
    active = null;
  });

  // Don't await — return so HTTP can respond.
  void active;

  return {
    started: true,
    run: { running: true, limit, concurrency, mode: 'inline' },
  };
}

export async function frame0OpsSnapshot() {
  const status = await getFrame0StatusPayload();
  return {
    ...status,
    runnerBusy: isFrame0BackfillRunning(),
  };
}
