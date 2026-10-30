import dotenv from 'dotenv';
import pg from 'pg';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { GetObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, '..', '.env'), override: true });

const { createR2Client, getBucket, PRESIGN_SECONDS } = await import(
  '../src/content-pipeline/r2.ts'
);

const p = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const { rows } = await p.query(
  `
  select thumb_url, thumb_path
  from public.posts
  where thumb_path like '%/frame0_512.webp'
  order by updated_at desc
  limit 1
  `
);
const row = rows[0];
if (!row) {
  console.log('no rows');
  process.exit(1);
}
const stored = row.thumb_url;
console.log('path', row.thumb_path);
console.log('stored', stored.slice(0, 160));
console.log('amz_date', (stored.match(/X-Amz-Date=([^&]+)/) || [])[1]);
console.log('expires', (stored.match(/X-Amz-Expires=([^&]+)/) || [])[1]);
console.log('cred', (stored.match(/X-Amz-Credential=([^&]+)/) || [])[1]?.slice(0, 80));

async function probe(label, url, init = {}) {
  const res = await fetch(url, init);
  let body = '';
  try {
    body = await res.text();
  } catch {
    body = '';
  }
  console.log(label, res.status, res.headers.get('content-type'), body.slice(0, 220));
}

await probe('stored-GET', stored);
await probe('stored-HEAD', stored, { method: 'HEAD' });
await probe('stored-Range', stored, { headers: { Range: 'bytes=0-64' } });

const key = String(row.thumb_path).replace(/^r2:[^/]+\//, '');
const client = createR2Client();
const head = await client.send(new HeadObjectCommand({ Bucket: getBucket(), Key: key }));
console.log('sdk-HEAD', head.ContentType, head.ContentLength);

const fresh = await getSignedUrl(
  client,
  new GetObjectCommand({ Bucket: getBucket(), Key: key }),
  { expiresIn: PRESIGN_SECONDS }
);
console.log('fresh', fresh.slice(0, 160));
await probe('fresh-GET', fresh);

await p.end();
