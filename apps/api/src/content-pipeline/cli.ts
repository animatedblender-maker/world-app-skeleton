/**
 * Local / ops CLI:
 *   npx tsx src/content-pipeline/cli.ts
 *   npx tsx src/content-pipeline/cli.ts --dry-run
 *   npx tsx src/content-pipeline/cli.ts --resign-only
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

const stats = await runContentPipeline({
  dryRun,
  resignOnly,
  ingestOnly,
  maxOriginals: args.has('--full') ? 200 : 40,
  maxShares: args.has('--full') ? 400 : 80,
  maxResign: args.has('--full') ? 1000 : 200,
  maxMs: args.has('--full') ? 240_000 : 50_000,
});

console.log(JSON.stringify(stats, null, 2));
process.exit(stats.ok ? 0 : 1);
