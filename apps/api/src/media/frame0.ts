/**
 * Frame 0 poster extract — first displayed video frame only.
 * Hard rule: poster pixels == video frame at t=0 (never a later “meaningful” frame).
 * Runs in-process on matterya-api via bundled `ffmpeg-static` (no extra Render worker).
 * @see docs/MEDIA_FRAME0.md
 */
import { spawn } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { access, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { GetObjectCommand, HeadObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { pool } from '../db.js';
import {
  createR2Client,
  extractR2KeyFromMediaPath,
  getBucket,
  PRESIGN_SECONDS,
  presignGet,
  r2Configured,
} from '../content-pipeline/r2.js';
import { publicObjectUrl } from './r2-playback.js';
import type { MediaProcessPayload, MediaReadyPayload } from '../kafka/types.js';
import { supabaseAdminConfigured, supabaseUrl } from '../supabase-admin.js';

function supabaseServiceRole(): string {
  return (process.env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim();
}

/** PostgREST helper (service role). Used when DATABASE_URL/pg is broken. */
async function postsRest<T = unknown>(
  pathAndQuery: string,
  init: RequestInit = {}
): Promise<T> {
  if (!supabaseAdminConfigured()) {
    throw new Error('SUPABASE_ADMIN_NOT_CONFIGURED');
  }
  const url = `${supabaseUrl()}/rest/v1/${pathAndQuery.replace(/^\//, '')}`;
  const headers = new Headers(init.headers);
  const key = supabaseServiceRole();
  headers.set('apikey', key);
  headers.set('Authorization', `Bearer ${key}`);
  if (init.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  if (!headers.has('Prefer') && (init.method === 'PATCH' || init.method === 'POST')) {
    headers.set('Prefer', 'return=minimal');
  }
  const res = await fetch(url, { ...init, headers });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`postsRest ${res.status}: ${text.slice(0, 300)}`);
  }
  if (res.status === 204) return undefined as T;
  const text = await res.text();
  if (!text) return undefined as T;
  return JSON.parse(text) as T;
}

function isPgUnavailable(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return /password authentication failed|ECONNREFUSED|ENOTFOUND|connect ETIMEDOUT|no pg_hba|timeout exceeded when trying to connect|connect ENOENT|28P01/i.test(
    msg
  );
}

const require = createRequire(import.meta.url);

export const FRAME0_SIZES = [256, 512, 1080] as const;
export type Frame0Size = (typeof FRAME0_SIZES)[number];

/** Default list / Sparks / Hubs poster. */
export const FRAME0_DEFAULT_SIZE: Frame0Size = 512;

/**
 * Preserve **display** aspect (= what AVPlayer shows), not raw coded pixels.
 * - Apply sample aspect ratio (SAR) so anamorphic files don't look squashed/stretched
 * - Fit long edge to `size` without distorting (force_original_aspect_ratio=decrease)
 * ffmpeg autorotates by stream displaymatrix by default when filtering.
 */
export function frame0ScaleFilter(longEdge: Frame0Size): string {
  // setsar=1 after expanding iw*sar so poster W/H matches on-screen video.
  return `scale=iw*sar:ih,setsar=1,scale=${longEdge}:${longEdge}:force_original_aspect_ratio=decrease`;
}

/** Resolve ffmpeg binary: FFMPEG_PATH → ffmpeg-static → PATH `ffmpeg`. */
export function resolveFfmpegPath(): string {
  const fromEnv = process.env.FFMPEG_PATH?.trim();
  if (fromEnv) return fromEnv;
  try {
    const bundled = require('ffmpeg-static') as string | null;
    if (bundled && typeof bundled === 'string') return bundled;
  } catch {
    /* optional dep missing in odd installs */
  }
  return 'ffmpeg';
}

export function packPrefixFromVideoKey(videoKey: string): string {
  const clean = videoKey.replace(/^\/+/, '');
  if (clean.endsWith('/video.mp4')) return clean.slice(0, -'/video.mp4'.length);
  if (clean.endsWith('.mp4')) {
    const i = clean.lastIndexOf('/');
    return i >= 0 ? clean.slice(0, i) : clean.replace(/\.mp4$/i, '');
  }
  const i = clean.lastIndexOf('/');
  return i >= 0 ? clean.slice(0, i) : clean;
}

export function frame0ObjectKey(videoKey: string, size: Frame0Size): string {
  return `${packPrefixFromVideoKey(videoKey)}/frame0_${size}.webp`;
}

export async function ffmpegAvailable(): Promise<boolean> {
  const bin = resolveFfmpegPath();
  if (bin !== 'ffmpeg') {
    try {
      await access(bin);
    } catch {
      return false;
    }
  }
  return new Promise((resolve) => {
    const child = spawn(bin, ['-version'], { stdio: 'ignore' });
    child.on('error', () => resolve(false));
    child.on('close', (code) => resolve(code === 0));
  });
}

function runCmd(bin: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    child.stderr?.on('data', (d) => {
      err += String(d);
      if (err.length > 4000) err = err.slice(-4000);
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${bin} exited ${code}: ${err.slice(-800)}`));
    });
  });
}

async function downloadR2ObjectToFile(
  bucket: string,
  key: string,
  destPath: string
): Promise<void> {
  const client = createR2Client();
  const out = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  if (!out.Body) throw new Error(`empty R2 body for ${key}`);
  // Body is a readable stream in Node AWS SDK v3.
  await pipeline(out.Body as NodeJS.ReadableStream, createWriteStream(destPath));
}

async function putWebp(bucket: string, key: string, bytes: Buffer): Promise<void> {
  const client = createR2Client();
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: bytes,
      ContentType: 'image/webp',
      CacheControl: 'public, max-age=31536000, immutable',
    })
  );
}

async function objectExists(bucket: string, key: string): Promise<boolean> {
  const client = createR2Client();
  try {
    await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch {
    return false;
  }
}

async function resolvePosterUrl(key: string): Promise<string> {
  const forcePublic =
    process.env.R2_FORCE_PUBLIC === '1' || process.env.R2_FORCE_PUBLIC === 'true';
  if (forcePublic) {
    const permanent = publicObjectUrl(key);
    if (permanent) return permanent;
  }
  const client = createR2Client();
  try {
    return await presignGet(client, key);
  } catch {
    const permanent = publicObjectUrl(key);
    if (permanent) return permanent;
    throw new Error(`cannot resolve poster URL for ${key}`);
  }
}

export type ProcessFrame0Options = {
  /** Re-encode even if frame0_*.webp already exist (fix wrong aspect). */
  force?: boolean;
};

/**
 * Extract FRAME 0 → WebP ladder → R2 → update posts.thumb_url (+ shares).
 * Poster display aspect must match the video's on-screen aspect (SAR + rotation).
 */
export async function processFrame0(
  payload: MediaProcessPayload,
  opts: ProcessFrame0Options = {}
): Promise<MediaReadyPayload> {
  if (!r2Configured()) {
    throw new Error('R2 not configured');
  }
  const ffmpegBin = resolveFfmpegPath();
  if (!(await ffmpegAvailable())) {
    throw new Error(
      `ffmpeg not available (tried ${ffmpegBin}). Install ffmpeg-static or set FFMPEG_PATH.`
    );
  }

  const bucket = (payload.r2Bucket || getBucket()).trim();
  const videoKey = payload.r2Key.replace(/^\/+/, '');
  if (!videoKey) throw new Error('missing r2Key');

  const outputKeys = FRAME0_SIZES.map((s) => frame0ObjectKey(videoKey, s));
  const already = opts.force ? false : await frame0DerivativesExist(videoKey, bucket);

  if (!already) {
    const workDir = await mkdtemp(join(tmpdir(), 'matterya-frame0-'));
    const srcPath = join(workDir, 'source.mp4');
    try {
      await downloadR2ObjectToFile(bucket, videoKey, srcPath);

      for (const size of FRAME0_SIZES) {
        const outKey = frame0ObjectKey(videoKey, size);
        const localWebp = join(workDir, `frame0_${size}.webp`);

        // Seek before -i; first displayed frame only — never scene-detect / mid-clip.
        // SAR normalize so poster aspect === what players show (not coded WxH alone).
        await runCmd(ffmpegBin, [
          '-y',
          '-ss',
          '0',
          '-i',
          srcPath,
          '-frames:v',
          '1',
          '-vf',
          frame0ScaleFilter(size),
          '-c:v',
          'libwebp',
          '-quality',
          '80',
          localWebp,
        ]);

        const bytes = await readFile(localWebp);
        if (!bytes.length) throw new Error(`empty webp for size ${size}`);
        await putWebp(bucket, outKey, bytes);
      }
    } finally {
      await rm(workDir, { recursive: true, force: true }).catch(() => undefined);
    }
  }

  const posterUrls: Record<string, string> = {};
  for (const size of FRAME0_SIZES) {
    posterUrls[String(size)] = await resolvePosterUrl(frame0ObjectKey(videoKey, size));
  }

  const defaultKey = frame0ObjectKey(videoKey, FRAME0_DEFAULT_SIZE);
  const thumbUrl = posterUrls[String(FRAME0_DEFAULT_SIZE)];
  const thumbPath = `r2:${bucket}/${defaultKey}`;

  await applyFrame0ToPosts({
    postId: payload.postId,
    thumbUrl,
    thumbPath,
    posterUrls,
    videoKey,
  });

  return {
    postId: payload.postId,
    r2Bucket: bucket,
    r2Key: videoKey,
    outputs: outputKeys,
    thumbUrl,
    thumbPath,
    completedOutputs: 'frame0',
    completedAt: new Date().toISOString(),
  };
}

async function applyFrame0ToPosts(opts: {
  postId: string;
  thumbUrl: string;
  thumbPath: string;
  posterUrls: Record<string, string>;
  videoKey: string;
}): Promise<void> {
  try {
    await applyFrame0ToPostsPg(opts);
  } catch (err) {
    if (!isPgUnavailable(err) || !supabaseAdminConfigured()) throw err;
    console.warn(
      `[frame0] pg unavailable (${err instanceof Error ? err.message : err}); applying via Supabase REST`
    );
    await applyFrame0ToPostsRest(opts);
  }
}

async function applyFrame0ToPostsPg(opts: {
  postId: string;
  thumbUrl: string;
  thumbPath: string;
  posterUrls: Record<string, string>;
  videoKey: string;
}): Promise<void> {
  const client = await pool.connect();
  try {
    const { rows } = await client.query<{ id: string; media_url: string | null }>(
      `
      select id, media_url
      from public.posts
      where id = $1::uuid
         or shared_post_id = $1::uuid
      `,
      [opts.postId]
    );

    for (const row of rows) {
      const nextMediaUrl = mergePostersIntoMediaUrl(row.media_url, {
        posters: opts.posterUrls,
        frame0_key: frame0ObjectKey(opts.videoKey, FRAME0_DEFAULT_SIZE),
        r2_key: opts.videoKey,
      });
      await client.query(
        `
        update public.posts
        set thumb_url = $2,
            thumb_path = $3,
            media_url = coalesce($4, media_url),
            updated_at = now()
        where id = $1::uuid
        `,
        [row.id, opts.thumbUrl, opts.thumbPath, nextMediaUrl]
      );
    }

    // Shares that point at the same R2 object via media_path but lack shared_post_id.
    await client.query(
      `
      update public.posts
      set thumb_url = $2,
          thumb_path = $3,
          updated_at = now()
      where media_type = 'video'
        and (
          media_path like ('r2-share:%/' || $1)
          or media_path like ('r2-hubshare:%/' || $1)
        )
        and (thumb_url is null or thumb_url = '' or thumb_path is distinct from $3)
        and id <> $4::uuid
        and (shared_post_id is null or shared_post_id is distinct from $4::uuid)
      `,
      [opts.videoKey, opts.thumbUrl, opts.thumbPath, opts.postId]
    );
  } finally {
    client.release();
  }
}

async function applyFrame0ToPostsRest(opts: {
  postId: string;
  thumbUrl: string;
  thumbPath: string;
  posterUrls: Record<string, string>;
  videoKey: string;
}): Promise<void> {
  const rows = await postsRest<Array<{ id: string; media_url: string | null }>>(
    `posts?select=id,media_url&or=(id.eq.${opts.postId},shared_post_id.eq.${opts.postId})`
  );

  for (const row of rows ?? []) {
    const nextMediaUrl = mergePostersIntoMediaUrl(row.media_url, {
      posters: opts.posterUrls,
      frame0_key: frame0ObjectKey(opts.videoKey, FRAME0_DEFAULT_SIZE),
      r2_key: opts.videoKey,
    });
    const body: Record<string, unknown> = {
      thumb_url: opts.thumbUrl,
      thumb_path: opts.thumbPath,
      updated_at: new Date().toISOString(),
    };
    if (nextMediaUrl != null) body.media_url = nextMediaUrl;
    await postsRest(`posts?id=eq.${row.id}`, {
      method: 'PATCH',
      body: JSON.stringify(body),
    });
  }

  // Shares keyed by media_path (r2-share / r2-hubshare) without shared_post_id.
  const shareOr = `or=(media_path.like.r2-share:%/${opts.videoKey},media_path.like.r2-hubshare:%/${opts.videoKey})`;
  const shares = await postsRest<Array<{ id: string; thumb_path: string | null; shared_post_id: string | null }>>(
    `posts?select=id,thumb_path,shared_post_id&media_type=eq.video&${shareOr}&id=neq.${opts.postId}`
  );
  for (const share of shares ?? []) {
    if (share.shared_post_id && share.shared_post_id === opts.postId) continue;
    if (share.thumb_path === opts.thumbPath) continue;
    await postsRest(`posts?id=eq.${share.id}`, {
      method: 'PATCH',
      body: JSON.stringify({
        thumb_url: opts.thumbUrl,
        thumb_path: opts.thumbPath,
        updated_at: new Date().toISOString(),
      }),
    });
  }
}

function mergePostersIntoMediaUrl(
  mediaUrl: string | null,
  extra: { posters: Record<string, string>; frame0_key: string; r2_key: string }
): string | null {
  if (!mediaUrl) return null;
  const raw = mediaUrl.trim();
  if (!raw.startsWith('{')) return mediaUrl;
  try {
    const obj = JSON.parse(raw) as Record<string, unknown>;
    obj.posters = extra.posters;
    obj.frame0_key = extra.frame0_key;
    if (!obj.r2_key) obj.r2_key = extra.r2_key;
    obj.poster_rule = 'frame0';
    return JSON.stringify(obj);
  } catch {
    return mediaUrl;
  }
}

function mapFrame0Candidates(
  rows: Array<{ id: string; media_path: string; media_url: string | null }>
): Array<{ postId: string; mediaPath: string; r2Key: string }> {
  const out: Array<{ postId: string; mediaPath: string; r2Key: string }> = [];
  for (const r of rows) {
    // Skip share wrappers (catalog originals only).
    if (r.media_path.startsWith('r2-share:') || r.media_path.startsWith('r2-hubshare:')) {
      continue;
    }
    const key =
      extractR2KeyFromMediaPath(r.media_path) ||
      (r.media_url?.startsWith('{')
        ? (() => {
            try {
              return String((JSON.parse(r.media_url) as { r2_key?: string }).r2_key || '');
            } catch {
              return '';
            }
          })()
        : '');
    if (!key) continue;
    out.push({ postId: r.id, mediaPath: r.media_path, r2Key: key });
  }
  return out;
}

async function listPostsNeedingFrame0Pg(
  limit: number
): Promise<Array<{ postId: string; mediaPath: string; r2Key: string }>> {
  const { rows } = await pool.query<{
    id: string;
    media_path: string;
    media_url: string | null;
  }>(
    `
    select id, media_path, media_url
    from public.posts
    where media_type = 'video'
      and media_path like 'r2:%'
      and media_path not like 'r2-share:%'
      and media_path not like 'r2-hubshare:%'
      and (
        thumb_url is null
        or thumb_url = ''
        or thumb_path is null
        or thumb_path = ''
        or thumb_path not like '%/frame0_512.webp'
      )
    order by
      -- Sparks first (vertical ShortForm + country packs) — hubs LongForm after.
      case
        when media_path like '%/ShortForm/%' then 0
        when media_path like '%/LongForm/%' then 2
        else 1
      end,
      created_at desc
    limit $1
    `,
    [Math.max(1, limit)]
  );
  return mapFrame0Candidates(rows);
}

async function listPostsNeedingFrame0Rest(
  limit: number
): Promise<Array<{ postId: string; mediaPath: string; r2Key: string }>> {
  // PostgREST `like` uses `*` as wildcard (not SQL `%`).
  // `r2:*` already excludes `r2-share:` / `r2-hubshare:` (those use a hyphen after r2).
  const filter =
    `posts?select=id,media_path,media_url` +
    `&media_type=eq.video` +
    `&media_path=like.r2:*` +
    `&or=(thumb_url.is.null,thumb_url.eq.,thumb_path.is.null,thumb_path.eq.,thumb_path.not.like.*/frame0_512.webp)` +
    `&order=created_at.desc` +
    `&limit=${Math.max(1, limit)}`;
  const rows = await postsRest<Array<{ id: string; media_path: string; media_url: string | null }>>(
    filter
  );
  const mapped = mapFrame0Candidates(rows ?? []);
  return limit > 0 && limit < 1_000_000 ? mapped.slice(0, limit) : mapped;
}

/**
 * Rows missing Frame 0 posters (catalog originals).
 * Pass `limit <= 0` (or omit a huge number) to claim **all** needing posts.
 */
export async function listPostsNeedingFrame0(limit = 50): Promise<
  Array<{ postId: string; mediaPath: string; r2Key: string }>
> {
  const effective = limit <= 0 ? 1_000_000 : limit;
  try {
    return await listPostsNeedingFrame0Pg(effective);
  } catch (err) {
    if (!isPgUnavailable(err) || !supabaseAdminConfigured()) throw err;
    console.warn(
      `[frame0] pg unavailable (${err instanceof Error ? err.message : err}); listing via Supabase REST`
    );
    return listPostsNeedingFrame0Rest(effective);
  }
}

/** Skip work if all three WebPs already exist (idempotent re-run). */
export async function frame0DerivativesExist(videoKey: string, bucket?: string): Promise<boolean> {
  const b = (bucket || getBucket()).trim();
  for (const size of FRAME0_SIZES) {
    const ok = await objectExists(b, frame0ObjectKey(videoKey, size));
    if (!ok) return false;
  }
  return true;
}

/** Dev helper: write a tiny marker file so tests can assert key layout without video. */
export async function writeFrame0LayoutMarker(videoKey: string): Promise<string[]> {
  const keys = FRAME0_SIZES.map((s) => frame0ObjectKey(videoKey, s));
  const dir = await mkdtemp(join(tmpdir(), 'matterya-frame0-layout-'));
  for (const k of keys) {
    await writeFile(join(dir, k.replace(/\//g, '__')), `${k}\n`);
  }
  await rm(dir, { recursive: true, force: true }).catch(() => undefined);
  return keys;
}

export { PRESIGN_SECONDS };
