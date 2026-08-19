/**
 * Enqueue Frame 0 jobs for catalog videos missing thumb_url / frame0_512.
 *
 *   npx tsx src/media/frame0-backfill.ts
 *   npx tsx src/media/frame0-backfill.ts --limit=100
 *   npx tsx src/media/frame0-backfill.ts --dry-run
 */
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getBucket } from '../content-pipeline/r2.js';
import { enqueueMediaProcessJob } from './enqueue.js';
import { listPostsNeedingFrame0 } from './frame0.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '..', '.env'), override: true });

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const limitArg = args.find((a) => a.startsWith('--limit='));
const limit = limitArg ? Math.max(1, Number(limitArg.split('=')[1]) || 50) : 50;

const rows = await listPostsNeedingFrame0(limit);
console.log(`[frame0-backfill] candidates=${rows.length} dryRun=${dryRun} limit=${limit}`);

let enqueued = 0;
let failed = 0;
for (const row of rows) {
  if (dryRun) {
    console.log(`  would enqueue post=${row.postId} key=${row.r2Key}`);
    enqueued += 1;
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
  if (r.enqueued) enqueued += 1;
  else {
    failed += 1;
    console.warn(`  enqueue failed post=${row.postId}: ${r.error}`);
  }
}

console.log(JSON.stringify({ ok: failed === 0, candidates: rows.length, enqueued, failed }, null, 2));
process.exit(failed === 0 ? 0 : 1);
