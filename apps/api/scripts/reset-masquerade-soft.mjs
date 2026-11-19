#!/usr/bin/env node
/**
 * Soft-reset Masquerade for App Review:
 *  - set all active/requested space memberships → left
 *  - recompute spaces.member_count
 *  - delete identity_vault.account_anonymous_links (kick everyone out of Masquerade identity)
 *
 * Keeps spaces, posts, comments, personas in DB (hidden while MASQUERADE_PUBLIC=false).
 *
 * Usage (from apps/api):
 *   node scripts/reset-masquerade-soft.mjs           # dry-run counts
 *   node scripts/reset-masquerade-soft.mjs --apply   # write
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const apply = process.argv.includes('--apply');

function loadEnv() {
  const envPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!m) continue;
    const key = m[1];
    let val = m[2].trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (process.env[key] == null || process.env[key] === '') process.env[key] = val;
  }
}

loadEnv();
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL missing');
  process.exit(1);
}

const client = new pg.Client({
  connectionString: databaseUrl,
  ssl: databaseUrl.includes('localhost') ? false : { rejectUnauthorized: false },
});

await client.connect();
try {
  const { rows: mem } = await client.query(`
    select state, count(*)::int as n
    from anonymous.space_memberships
    group by state
    order by state
  `);
  const { rows: links } = await client.query(
    `select count(*)::int as n from identity_vault.account_anonymous_links`
  );
  const { rows: spaces } = await client.query(
    `select count(*)::int as n from anonymous.spaces where status = 'active'`
  );
  const { rows: posts } = await client.query(
    `select count(*)::int as n from anonymous.posts where state = 'active'`
  );

  console.log('memberships by state:', mem);
  console.log('account_anonymous_links:', links[0]?.n ?? 0);
  console.log('active spaces (kept):', spaces[0]?.n ?? 0);
  console.log('active posts (kept):', posts[0]?.n ?? 0);

  if (!apply) {
    console.log('\nDry-run only. Re-run with --apply to kick everyone out.');
    process.exit(0);
  }

  await client.query('begin');
  const left = await client.query(`
    update anonymous.space_memberships
    set state = 'left', left_at = coalesce(left_at, now())
    where state in ('active', 'requested')
  `);
  const counts = await client.query(`
    update anonymous.spaces s
    set member_count = (
      select count(*)::int
      from anonymous.space_memberships m
      where m.space_id = s.id and m.state = 'active'
    )
  `);
  const unlinked = await client.query(
    `delete from identity_vault.account_anonymous_links`
  );
  await client.query('commit');

  console.log('\nApplied:');
  console.log('  memberships → left:', left.rowCount);
  console.log('  spaces member_count refreshed:', counts.rowCount);
  console.log('  account_anonymous_links deleted:', unlinked.rowCount);
} catch (err) {
  try {
    await client.query('rollback');
  } catch {
    /* ignore */
  }
  console.error(err);
  process.exit(1);
} finally {
  await client.end();
}
