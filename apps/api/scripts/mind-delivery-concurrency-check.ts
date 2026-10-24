/**
 * MIND-008: two concurrent reserves for the same user+surface must not
 * double-book the same canonical id.
 *
 *   cd apps/api && npx tsx scripts/mind-delivery-concurrency-check.ts
 *
 * Requires DATABASE_URL (apps/api/.env loaded by dotenv in main paths —
 * this script loads .env itself).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const envPath = path.join(root, '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!m) continue;
    if (!process.env[m[1]!]) {
      process.env[m[1]!] = m[2]!.replace(/^["']|["']$/g, '');
    }
  }
}

const { pool } = await import('../src/db.js');
const { reserveDeliveryBatch, ensureFeedDeliverySchema } = await import(
  '../src/recommendation/delivery.service.js'
);

async function main() {
  const ok = await ensureFeedDeliverySchema();
  if (!ok) throw new Error('schema ensure failed');

  // Prefer a real auth user (FK on feed_batch.user_id). Fall back to synthetic.
  let userId = randomUUID();
  try {
    const { rows } = await pool.query<{ id: string }>(
      `select id::text as id from auth.users limit 1`
    );
    if (rows[0]?.id) userId = rows[0].id;
  } catch {
    console.warn('auth.users unavailable — using synthetic uuid (FK may fail)');
  }

  const surface = 'home_for_you' as const;
  const tag = randomUUID().slice(0, 8);
  const shared = Array.from({ length: 20 }, (_, i) => ({
    id: randomUUID(),
    canonicalKey: `mind-test-${tag}-${i}`,
  }));

  const [a, b] = await Promise.all([
    reserveDeliveryBatch({
      userId,
      surface,
      idempotencyKey: `mind-conc-a-${randomUUID()}`,
      candidates: shared,
      limit: 8,
    }),
    reserveDeliveryBatch({
      userId,
      surface,
      idempotencyKey: `mind-conc-b-${randomUUID()}`,
      candidates: shared,
      limit: 8,
    }),
  ]);

  if (!a || !b) throw new Error('one reserve returned null');

  const vidsA = a.videoIds;
  const vidsB = b.videoIds;
  const overlap = vidsA.filter((id) => vidsB.includes(id));
  console.log('batchA', vidsA.length, 'batchB', vidsB.length, 'overlap', overlap.length);

  // Primary key is on canonical — video ids should be disjoint when drawing from same pool.
  if (overlap.length) {
    throw new Error(`FAIL overlap video ids: ${overlap.join(',')}`);
  }
  console.log('mind-delivery-concurrency-check OK');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
