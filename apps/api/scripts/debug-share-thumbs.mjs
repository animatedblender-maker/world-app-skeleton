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

const originals = await p.query(`
  select id, media_path, left(coalesce(thumb_path,''),80) as tpath
  from public.posts
  where thumb_path like '%/frame0_512.webp'
  order by updated_at desc
  limit 5
`);
console.log('originals_with_frame0', originals.rows);

for (const o of originals.rows) {
  const shares = await p.query(
    `
    select id, media_path, shared_post_id,
           left(coalesce(thumb_path,''),60) as tpath,
           length(coalesce(thumb_url,'')) as thumb_len
    from public.posts
    where shared_post_id = $1
       or media_path = $2
       or media_path = $3
    limit 10
    `,
    [
      o.id,
      'r2-share:' + String(o.media_path).slice(3),
      'r2-hubshare:' + String(o.media_path).slice(3),
    ]
  );
  console.log('for', o.id.slice(0, 8), 'path', String(o.media_path).slice(0, 50), 'shares', shares.rows);
}

const mismatch = await p.query(`
  select
    left(s.media_path, 70) as share_path,
    left(o.media_path, 70) as orig_path,
    s.shared_post_id is not null as has_sid,
    left(coalesce(o.thumb_path,''), 50) as orig_thumb,
    left(coalesce(s.thumb_path,''), 50) as share_thumb
  from public.posts s
  left join public.posts o on o.id = s.shared_post_id
  where s.media_type = 'video'
    and (s.media_path like 'r2-share:%' or s.media_path like 'r2-hubshare:%')
  order by s.created_at desc
  limit 8
`);
console.log('recent_shares', mismatch.rows);

await p.end();
