/**
 * Local / ops CLI:
 *   npx tsx src/content-pipeline/cli.ts              # flood ALL new R2 packs
 *   npx tsx src/content-pipeline/cli.ts --dry-run
 *   npx tsx src/content-pipeline/cli.ts --resign-only
 *   npx tsx src/content-pipeline/cli.ts --cap-40     # optional throttle
 *   npx tsx src/content-pipeline/cli.ts --timed      # 50s soft deadline
 */
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runContentPipeline } from './run.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '..', '.env'), override: true });

const args = new Set(process.argv.slice(2));
const dryRun = args.has('--dry-run');
const resignOnly = args.has('--resign-only');
const ingestOnly = args.has('--ingest-only');

// Default: flood every new R2 pack. Optional throttles only when flags are set.
const cap = args.has('--cap-40') ? 40 : args.has('--cap-200') ? 200 : undefined;

const stats = await runContentPipeline({
  dryRun,
  resignOnly,
  ingestOnly,
  // undefined = ALL new packs (flood Matterya)
  maxOriginals: cap,
  maxShares: cap != null ? cap * 2 : undefined,
  maxResign: 2000,
  maxMs: args.has('--timed') ? 50_000 : 0,
});

console.log(JSON.stringify(stats, null, 2));
process.exit(stats.ok ? 0 : 1);
