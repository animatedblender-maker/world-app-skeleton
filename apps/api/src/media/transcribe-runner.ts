/**
 * Batch / continuous transcription runner (Groq Whisper).
 *
 *   npm run media:transcribe -- --limit=30 --backfill
 *   npm run media:transcribe -- --loop --limit=10
 *
 * Requires GROQ_API_KEY + ffmpeg (ffmpeg-static is fine).
 */
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ffmpegAvailable } from './frame0.js';
import { processTranscriptQueue, transcriptionConfigured } from './transcribe.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '..', '.env'), override: true });

function argFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
}

function argValue(name: string, fallback: number): number {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  if (!hit) return fallback;
  const n = Number(hit.split('=')[1]);
  return Number.isFinite(n) ? n : fallback;
}

async function once(): Promise<void> {
  const limit = argValue('limit', 20);
  const backfill = argFlag('backfill');
  const result = await processTranscriptQueue({ limit, backfillMissing: backfill });
  console.log(
    `[transcribe] processed=${result.processed} ready=${result.ready} failed=${result.failed} skipped=${result.skipped}`
  );
}

async function main(): Promise<void> {
  if (!transcriptionConfigured()) {
    console.error('❌ GROQ_API_KEY is required (set in apps/api/.env)');
    process.exit(1);
  }
  if (!(await ffmpegAvailable())) {
    console.error('❌ ffmpeg not available');
    process.exit(1);
  }

  if (argFlag('loop')) {
    const limit = argValue('limit', 3);
    const sleepMs = argValue('sleepMs', 90_000);
    console.log(`[transcribe] loop mode limit=${limit} sleepMs=${sleepMs}`);
    for (;;) {
      const result = await processTranscriptQueue({ limit, backfillMissing: true });
      console.log(
        `[transcribe] processed=${result.processed} ready=${result.ready} failed=${result.failed} skipped=${result.skipped}`
      );
      // Groq free tier is tight — default ~90s between batches.
      await new Promise((r) => setTimeout(r, sleepMs));
    }
  }

  await once();
}

main().catch((err) => {
  console.error('❌ transcribe runner failed', err);
  process.exit(1);
});
