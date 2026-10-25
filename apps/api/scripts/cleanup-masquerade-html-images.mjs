#!/usr/bin/env node
/**
 * Hard-delete Masquerade photo posts whose R2 "jpg" is HTML scrape poison.
 *
 * Fast path: parallel Range GETs (default 24 workers).
 *
 *   node scripts/cleanup-masquerade-html-images.mjs [--dry-run] [--limit=5000] [--concurrency=24]
 */
import { readFileSync } from 'fs';
import { GetObjectCommand } from '@aws-sdk/client-s3';

for (const line of readFileSync('.env', 'utf8').split('\n')) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^"|"$/g, '');
}

const dryRun = process.argv.includes('--dry-run');
const limitArg = process.argv.find((a) => a.startsWith('--limit='));
const concArg = process.argv.find((a) => a.startsWith('--concurrency='));
const limit = limitArg ? Math.max(1, Number(limitArg.split('=')[1]) || 2000) : 5000;
const concurrency = concArg ? Math.max(1, Number(concArg.split('=')[1]) || 24) : 24;

const { pool } = await import('../dist/db.js');
const { createR2Client, getBucket } = await import('../dist/content-pipeline/r2.js');

function isHtmlPoison(buf) {
  if (!buf?.length) return false;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return false;
  if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) return false;
  if (buf.slice(0, 6).toString('ascii') === 'GIF87a' || buf.slice(0, 6).toString('ascii') === 'GIF89a')
    return false;
  if (buf.slice(0, 4).toString('ascii') === 'RIFF') return false;
  if (buf[0] === 0x1f && buf[1] === 0x8b) return false;
  const ascii = buf.toString('latin1');
  return (
    ascii.includes('<!DOCTYPE') ||
    ascii.includes('<html') ||
    ascii.includes('<HTML') ||
    /^(\r\n)+</.test(ascii)
  );
}

const client = createR2Client();
const bucket = getBucket();

const { rows } = await pool.query(
  `
  select id::text as id, media_url
  from anonymous.posts
  where state = 'active'
    and media_type in ('image', 'gif', 'photo')
    and coalesce(media_url, '') <> ''
  order by created_at desc
  limit $1
  `,
  [limit]
);

console.log(`Scanning ${rows.length} image posts (workers=${concurrency}, dryRun=${dryRun})…`);

const badIds = [];
let ok = 0;
let err = 0;
let done = 0;

async function sniff(r) {
  const key = String(r.media_url).replace(/^r2:[^/]+\//, '');
  try {
    const out = await client.send(
      new GetObjectCommand({ Bucket: bucket, Key: key, Range: 'bytes=0-63' })
    );
    const buf = Buffer.from(await out.Body.transformToByteArray());
    if (isHtmlPoison(buf)) badIds.push(r.id);
    else ok += 1;
  } catch {
    err += 1;
  } finally {
    done += 1;
    if (done % 200 === 0 || done === rows.length) {
      console.log(`  …${done}/${rows.length} bad=${badIds.length}`);
    }
  }
}

let cursor = 0;
async function worker() {
  while (cursor < rows.length) {
    const i = cursor++;
    await sniff(rows[i]);
  }
}
await Promise.all(Array.from({ length: Math.min(concurrency, rows.length) }, () => worker()));

console.log({ scanned: rows.length, ok, htmlPoison: badIds.length, err });

if (!badIds.length) {
  await pool.end();
  process.exit(0);
}

if (dryRun) {
  console.log('dry-run sample ids', badIds.slice(0, 10));
  await pool.end();
  process.exit(0);
}

await pool.query(
  `delete from anonymous.votes where target_type = 'post' and target_id = any($1::uuid[])`,
  [badIds]
);
try {
  await pool.query(
    `delete from anonymous.reports where target_type = 'post' and target_id = any($1::uuid[])`,
    [badIds]
  );
} catch {
  /* optional */
}

const { rowCount } = await pool.query(`delete from anonymous.posts where id = any($1::uuid[])`, [
  badIds,
]);
console.log(`Hard-deleted ${rowCount} poisoned photo posts`);
await pool.end();
