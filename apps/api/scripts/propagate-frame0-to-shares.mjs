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

const before = await p.query(`
  select
    count(*) filter (where media_path like 'r2-share:%')::int as spark_shares,
    count(*) filter (where media_path like 'r2-share:%' and thumb_path like '%/frame0_512.webp')::int as spark_with,
    count(*) filter (where media_path like 'r2-hubshare:%')::int as hub_shares,
    count(*) filter (where media_path like 'r2-hubshare:%' and thumb_path like '%/frame0_512.webp')::int as hub_with
  from public.posts
  where media_type = 'video'
`);
console.log('before', before.rows[0]);

const r1 = await p.query(`
  with upd as (
    update public.posts s
    set thumb_url = o.thumb_url,
        thumb_path = o.thumb_path,
        updated_at = now()
    from public.posts o
    where s.shared_post_id = o.id
      and o.thumb_path like '%/frame0_512.webp'
      and length(trim(coalesce(o.thumb_url, ''))) > 0
      and (
        s.thumb_path is distinct from o.thumb_path
        or length(trim(coalesce(s.thumb_url, ''))) = 0
      )
    returning s.id
  )
  select count(*)::int as n from upd
`);
console.log('copied_via_shared_post_id', r1.rows[0]);

const after = await p.query(`
  select
    count(*) filter (where media_path like 'r2-share:%' and thumb_path like '%/frame0_512.webp')::int as spark_with,
    count(*) filter (where media_path like 'r2-hubshare:%' and thumb_path like '%/frame0_512.webp')::int as hub_with
  from public.posts
  where media_type = 'video'
`);
console.log('after', after.rows[0]);
await p.end();
