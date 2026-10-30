import dotenv from 'dotenv';
import pg from 'pg';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, '..', '.env'), override: true });

const p = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const { rows } = await p.query(`
  select id, media_path, left(thumb_url, 200) as thumb, thumb_path,
         case when thumb_url like '%X-Amz-Date=%' then
           substring(thumb_url from 'X-Amz-Date=([0-9TZ]+)')
         else null end as amz_date
  from public.posts
  where thumb_path like '%/frame0_512.webp'
  order by updated_at desc
  limit 6
`);

for (const r of rows) {
  const u = r.thumb;
  let status = 'n/a';
  let ct = '';
  let n = 0;
  try {
    const res = await fetch(u, { method: 'GET', headers: { Range: 'bytes=0-128' } });
    status = String(res.status);
    ct = res.headers.get('content-type') || '';
    n = (await res.arrayBuffer()).byteLength;
  } catch (e) {
    status = 'ERR ' + e.message;
  }
  console.log({
    id: r.id.slice(0, 8),
    path: String(r.media_path || '').slice(0, 60),
    amz: r.amz_date,
    status,
    ct,
    n,
  });
}

// shares missing frame0
const shares = await p.query(`
  select count(*)::int as n
  from public.posts
  where media_type = 'video'
    and (media_path like 'r2-share:%' or media_path like 'r2-hubshare:%' or shared_post_id is not null)
    and (thumb_path is null or thumb_path = '' or thumb_path not like '%/frame0_512.webp')
`);
console.log('shares_missing_frame0', shares.rows[0]);

const shareSample = await p.query(`
  select id, left(media_path,70) as path, left(coalesce(thumb_url,''),100) as thumb, left(coalesce(thumb_path,''),80) as tpath, shared_post_id
  from public.posts
  where media_type = 'video'
    and (media_path like 'r2-share:%' or media_path like 'r2-hubshare:%' or shared_post_id is not null)
  order by created_at desc
  limit 5
`);
console.log('share_samples', shareSample.rows);

await p.end();
