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

async function one(sql) {
  return (await p.query(sql)).rows[0];
}

console.log(
  'longform_frame0',
  await one(`
    select count(*)::int as n from public.posts
    where media_path like '%LongForm/%' and thumb_path like '%/frame0_512.webp'
  `)
);
console.log(
  'spark_frame0',
  await one(`
    select count(*)::int as n from public.posts
    where media_type = 'video'
      and media_path like 'r2:%'
      and media_path not like '%LongForm/%'
      and media_path not like 'r2-share:%'
      and media_path not like 'r2-hubshare:%'
      and thumb_path like '%/frame0_512.webp'
  `)
);
console.log(
  'spark_needing',
  await one(`
    select count(*)::int as n from public.posts
    where media_type = 'video'
      and media_path like 'r2:%'
      and media_path not like '%LongForm/%'
      and media_path not like 'r2-share:%'
      and media_path not like 'r2-hubshare:%'
      and (thumb_path is null or thumb_path = '' or thumb_path not like '%/frame0_512.webp')
  `)
);

const samples = await p.query(`
  select left(media_path, 80) as path,
         left(coalesce(thumb_url, ''), 120) as thumb,
         left(coalesce(thumb_path, ''), 90) as tpath
  from public.posts
  where media_type = 'video'
    and media_path like 'r2:%'
    and media_path not like '%LongForm/%'
    and media_path not like 'r2-share:%'
  order by created_at desc
  limit 8
`);
console.log('samples', samples.rows);
await p.end();
