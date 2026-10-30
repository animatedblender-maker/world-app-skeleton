import dotenv from 'dotenv';
import pg from 'pg';
import { createRequire } from 'module';
import { spawn } from 'child_process';
import { mkdtemp, writeFile, readFile } from 'fs/promises';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { GetObjectCommand } from '@aws-sdk/client-s3';

const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, '..', '.env'), override: true });

const { createR2Client, getBucket } = await import('../src/content-pipeline/r2.ts');
const require = createRequire(import.meta.url);
const ffmpeg = require('ffmpeg-static');

function run(bin, args) {
  return new Promise((resolve, reject) => {
    const c = spawn(bin, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    let err = '';
    c.stdout.on('data', (d) => (out += d));
    c.stderr.on('data', (d) => (err += d));
    c.on('close', (code) => (code === 0 ? resolve(out || err) : reject(new Error((err || out).slice(-800)))));
  });
}

function dims(info) {
  const m = info.match(/Video:\s*[^\n]*?(\d{2,5})x(\d{2,5})/);
  return m ? { w: Number(m[1]), h: Number(m[2]) } : null;
}

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const { rows } = await pool.query(`
  select id, media_path, thumb_path
  from public.posts
  where media_type = 'video'
    and media_path like 'r2:%'
    and media_path not like '%LongForm/%'
    and thumb_path like '%/frame0_512.webp'
  order by created_at desc
  limit 6
`);

console.log('spark_rows', rows.length);
const client = createR2Client();
const bucket = getBucket();
const dir = await mkdtemp(join(tmpdir(), 'f0chk-'));

for (const row of rows) {
  const posterKey = String(row.thumb_path).replace(/^r2:[^/]+\//, '');
  const videoKey = String(row.media_path).replace(/^r2:[^/]+\//, '');
  const webpPath = join(dir, `${row.id}.webp`);
  const mp4Path = join(dir, `${row.id}.mp4`);
  try {
    const w = await client.send(new GetObjectCommand({ Bucket: bucket, Key: posterKey }));
    await writeFile(webpPath, Buffer.from(await w.Body.transformToByteArray()));
    const pInfo = await run(ffmpeg, ['-i', webpPath]);
    const pDim = dims(pInfo);

    const v = await client.send(new GetObjectCommand({ Bucket: bucket, Key: videoKey }));
    await writeFile(mp4Path, Buffer.from(await v.Body.transformToByteArray()));
    const vInfo = await run(ffmpeg, ['-i', mp4Path]);
    const vDim = dims(vInfo);
    const sar = (vInfo.match(/SAR\s+(\d+:\d+|\d+\/\d+)/) || [])[1] || '?';
    const dar = (vInfo.match(/DAR\s+(\d+:\d+|\d+\/\d+)/) || [])[1] || '?';

    const pAspect = pDim ? pDim.w / pDim.h : 0;
    const vAspect = vDim ? vDim.w / vDim.h : 0;
    const mismatch = pDim && vDim ? Math.abs(pAspect - vAspect) > 0.03 : true;

    console.log(
      JSON.stringify({
        id: row.id.slice(0, 8),
        key: videoKey.slice(0, 72),
        poster: pDim ? `${pDim.w}x${pDim.h}` : '?',
        video: vDim ? `${vDim.w}x${vDim.h}` : '?',
        sar,
        dar,
        pAspect: Number(pAspect.toFixed(3)),
        vAspect: Number(vAspect.toFixed(3)),
        mismatch,
        webpBytes: (await readFile(webpPath)).length,
      })
    );
  } catch (e) {
    console.log('fail', row.id, String(e.message || e).slice(0, 180));
  }
}

await pool.end();
