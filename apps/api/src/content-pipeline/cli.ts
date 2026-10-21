/**
 * Local / ops CLI:
 *   npx tsx src/content-pipeline/cli.ts              # flood ALL new R2 packs + Frame 0
 *   npx tsx src/content-pipeline/cli.ts --dry-run
 *   npx tsx src/content-pipeline/cli.ts --resign-only
 *   npx tsx src/content-pipeline/cli.ts --no-frame0  # skip inline Frame 0
 *   npx tsx src/content-pipeline/cli.ts --fast       # no Frame0 + comments capped at 40 (posts ASAP)
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
const fast = args.has('--fast');

// Default: flood every new R2 pack. Optional throttles only when flags are set.
const cap = args.has('--cap-40') ? 40 : args.has('--cap-200') ? 200 : undefined;

const stats = await runContentPipeline({
  dryRun,
  resignOnly,
  ingestOnly,
  // undefined = ALL new packs (flood Matterya)
  maxOriginals: cap,
  maxShares: cap != null ? cap * 2 : undefined,
  // undefined = resign ALL R2 rows that need it
  maxResign: undefined,
  maxMs: args.has('--timed') ? 50_000 : 0,
  frame0Inline: fast ? false : !args.has('--no-frame0'),
  // Fast flood: still seed a comment slice (reddit/image posts need threads).
  // Full threads: omit --fast. Zero comments: pass --no-comments.
  maxCommentsPerPost: args.has('--no-comments') ? 0 : fast ? 40 : undefined,
});

console.log(JSON.stringify(stats, null, 2));
process.exit(stats.ok ? 0 : 1);
