/**
 * Open Claim-next tickets for flagged Masquerade posts missing from the queue.
 *
 * Usage (from apps/api):
 *   npx tsx src/moderation/backfill-auto-tickets.ts
 *   npx tsx src/moderation/backfill-auto-tickets.ts --limit=200
 *   npx tsx src/moderation/backfill-auto-tickets.ts --dry-run
 */
import 'dotenv/config';
import { pool } from '../db.js';
import { backfillAutoTicketsFromFlaggedPosts } from './tickets.js';

function argFlag(name: string): boolean {
  return process.argv.includes(name);
}

function argValue(name: string): string | null {
  const pref = `${name}=`;
  const hit = process.argv.find((a) => a.startsWith(pref));
  return hit ? hit.slice(pref.length) : null;
}

async function main(): Promise<number> {
  const dryRun = argFlag('--dry-run');
  const limit = Math.max(1, Number(argValue('--limit') || 500) || 500);

  const { rows } = await pool.query<{ n: string }>(
    `
    select count(*)::text as n
    from anonymous.posts p
    where p.state = 'active'
      and p.flagged_at is not null
      and not exists (
        select 1 from public.moderation_tickets t
        where t.target_kind = 'post'
          and t.target_id = p.id
          and t.status in ('open', 'claimed')
      )
    `
  );
  const missing = Number(rows[0]?.n || 0);
  console.log(`[backfill-auto-tickets] missing=${missing} limit=${limit} dryRun=${dryRun}`);

  if (dryRun || missing === 0) {
    await pool.end();
    return 0;
  }

  const result = await backfillAutoTicketsFromFlaggedPosts(limit);
  console.log(`[backfill-auto-tickets] created=${result.created} scanned=${result.scanned}`);
  await pool.end();
  return 0;
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
