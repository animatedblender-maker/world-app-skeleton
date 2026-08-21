import {
  GetObjectCommand,
  ListObjectsV2Command,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { pipelineLog } from './log.js';
import type { PackKind, R2Pack } from './types.js';

/** R2 practical max for presigned GET. */
export const PRESIGN_SECONDS = 7 * 24 * 3600;

export const FOCUS_COUNTRIES: Array<{
  folder: string;
  code: string;
  name: string;
}> = [
  { folder: 'United_States', code: 'US', name: 'United States' },
  { folder: 'Germany', code: 'DE', name: 'Germany' },
  { folder: 'Egypt', code: 'EG', name: 'Egypt' },
  { folder: 'Albania', code: 'AL', name: 'Albania' },
];

export function r2Configured(): boolean {
  const access = process.env.R2_ACCESS_KEY_ID?.trim();
  const secret = process.env.R2_SECRET_ACCESS_KEY?.trim();
  const account = process.env.R2_ACCOUNT_ID?.trim();
  const endpoint = process.env.R2_ENDPOINT?.trim();
  return !!(access && secret && (endpoint || account));
}

export function getBucket(): string {
  return (process.env.R2_BUCKET || 'matterya-sparks').trim();
}

export function createR2Client(): S3Client {
  const access = process.env.R2_ACCESS_KEY_ID?.trim() || '';
  const secret = process.env.R2_SECRET_ACCESS_KEY?.trim() || '';
  const account = process.env.R2_ACCOUNT_ID?.trim() || '';
  let endpoint = process.env.R2_ENDPOINT?.trim() || '';
  if (!endpoint && account) {
    endpoint = `https://${account}.r2.cloudflarestorage.com`;
  }
  if (!access || !secret || !endpoint) {
    throw new Error('R2 credentials incomplete (R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY / R2_ENDPOINT|R2_ACCOUNT_ID)');
  }
  return new S3Client({
    region: 'auto',
    endpoint,
    credentials: { accessKeyId: access, secretAccessKey: secret },
    forcePathStyle: true,
  });
}

export async function presignGet(client: S3Client, key: string): Promise<string> {
  // Always mint a real AWS/R2 signed GET when credentials exist.
  // Do NOT short-circuit to R2_PUBLIC_BASE_URL here — public r2.dev bases often 403
  // when bucket ACL is private (that made Hubs "never play" while shelves looked fine).
  // Callers that want a permanent public URL should use publicObjectUrl explicitly.
  const cmd = new GetObjectCommand({ Bucket: getBucket(), Key: key });
  return getSignedUrl(client, cmd, { expiresIn: PRESIGN_SECONDS });
}

export async function getObjectText(client: S3Client, key: string): Promise<string | null> {
  try {
    const out = await client.send(
      new GetObjectCommand({ Bucket: getBucket(), Key: key })
    );
    const body = out.Body;
    if (!body) return null;
    return await body.transformToString();
  } catch {
    return null;
  }
}

export async function getObjectJson(client: S3Client, key: string): Promise<unknown> {
  const text = await getObjectText(client, key);
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/**
 * List complete packs (video.mp4 present). meta.json optional but preferred.
 * Layout (bucket matterya-sparks):
 *   Sparks (TikTok):        <Country>/<tiktok_id>/video.mp4
 *   Sparks (YouTube Shorts): ShortForm/<Country>/<youtube_id>/video.mp4  ← still kind=spark
 *   LongForm (Hubs):         LongForm/<Country>/<youtube_id>/video.mp4
 *
 * ShortForm is Sparks — same product surface, different R2 folder only.
 * @see AGENT_HANDOFF_YOUTUBE_SHORTFORM.md
 *
 * Default: **paginate every prefix to completion** (no 5k object truncations).
 * Optional `maxPacksPerPrefix` only for dry-run / throttle — not used by Ops flood.
 */
export async function discoverPacks(
  client: S3Client,
  opts: { maxPacksPerPrefix?: number; maxKeysPerPrefix?: number } = {}
): Promise<R2Pack[]> {
  // Legacy alias: maxKeysPerPrefix meant “stop after N listed objects” and silently
  // dropped most of the bucket once frame0_*.webp inflated key counts. Prefer pack cap.
  const maxPacks =
    opts.maxPacksPerPrefix != null && opts.maxPacksPerPrefix > 0
      ? opts.maxPacksPerPrefix
      : opts.maxKeysPerPrefix != null && opts.maxKeysPerPrefix > 0
        ? opts.maxKeysPerPrefix
        : 0; // 0 = unlimited
  const packs: R2Pack[] = [];
  const seen = new Set<string>();

  for (const c of FOCUS_COUNTRIES) {
    // Sparks (TikTok) under country root — only Country/<id>/video.mp4 (depth 1)
    const sparkIds = await listVideoPackIds(client, `${c.folder}/`, maxPacks, {
      depth: 1,
    });
    for (const videoId of sparkIds) {
      if (videoId === 'LongForm' || videoId === 'ShortForm') continue;
      const videoKey = `${c.folder}/${videoId}/video.mp4`;
      const mediaPath = `r2:${getBucket()}/${videoKey}`;
      if (seen.has(mediaPath)) continue;
      seen.add(mediaPath);
      packs.push({
        kind: 'spark',
        countryFolder: c.folder,
        countryCode: c.code,
        countryName: c.name,
        videoId,
        videoKey,
        metaKey: `${c.folder}/${videoId}/meta.json`,
        commentsKey: `${c.folder}/${videoId}/comments.json`,
        mediaPath,
      });
    }

    // YouTube Shorts live under ShortForm/ but are **Sparks** in the app.
    const sfIds = await listVideoPackIds(client, `ShortForm/${c.folder}/`, maxPacks);
    for (const videoId of sfIds) {
      const videoKey = `ShortForm/${c.folder}/${videoId}/video.mp4`;
      const mediaPath = `r2:${getBucket()}/${videoKey}`;
      if (seen.has(mediaPath)) continue;
      seen.add(mediaPath);
      packs.push({
        kind: 'spark',
        countryFolder: c.folder,
        countryCode: c.code,
        countryName: c.name,
        videoId,
        videoKey,
        metaKey: `ShortForm/${c.folder}/${videoId}/meta.json`,
        commentsKey: `ShortForm/${c.folder}/${videoId}/comments.json`,
        mediaPath,
      });
    }

    // LongForm (YouTube long) — Hubs only
    const lfIds = await listVideoPackIds(client, `LongForm/${c.folder}/`, maxPacks);
    for (const videoId of lfIds) {
      const videoKey = `LongForm/${c.folder}/${videoId}/video.mp4`;
      const mediaPath = `r2:${getBucket()}/${videoKey}`;
      if (seen.has(mediaPath)) continue;
      seen.add(mediaPath);
      packs.push({
        kind: 'longform',
        countryFolder: c.folder,
        countryCode: c.code,
        countryName: c.name,
        videoId,
        videoKey,
        metaKey: `LongForm/${c.folder}/${videoId}/meta.json`,
        commentsKey: `LongForm/${c.folder}/${videoId}/comments.json`,
        mediaPath,
      });
    }
  }

  return packs;
}

/** Infer product kind from an R2 object key. ShortForm → spark. */
export function packKindFromR2Key(key: string): PackKind {
  if (key.includes('LongForm/') || key.startsWith('LongForm/')) return 'longform';
  // ShortForm/… and country-root TikTok packs are both Sparks.
  return 'spark';
}

/**
 * Paginate R2 until the prefix is exhausted (or optional pack-id cap).
 * @param maxPacks 0 = unlimited (default for pipeline flood)
 */
async function listVideoPackIds(
  client: S3Client,
  prefix: string,
  maxPacks: number,
  opts: { depth?: number } = {}
): Promise<string[]> {
  const ids = new Set<string>();
  let token: string | undefined;
  let pages = 0;
  // depth=1: only keys like `prefix/<id>/video.mp4` (not nested ShortForm under a country root)
  const depth = opts.depth;
  do {
    const page = await client.send(
      new ListObjectsV2Command({
        Bucket: getBucket(),
        Prefix: prefix,
        ContinuationToken: token,
        MaxKeys: 1000,
      })
    );
    pages += 1;
    for (const obj of page.Contents ?? []) {
      const key = obj.Key || '';
      // …/<id>/video.mp4
      const m = key.match(/\/([^/]+)\/video\.mp4$/i);
      if (!m?.[1]) continue;
      if (typeof depth === 'number') {
        // Relative path under prefix: `<id>/video.mp4` → depth 1
        const rel = key.startsWith(prefix) ? key.slice(prefix.length) : key;
        const parts = rel.split('/').filter(Boolean);
        // parts = [id, video.mp4] for depth 1
        if (parts.length !== depth + 1) continue;
      }
      ids.add(m[1]);
      if (maxPacks > 0 && ids.size >= maxPacks) {
        return [...ids];
      }
    }
    token = page.IsTruncated ? page.NextContinuationToken : undefined;
  } while (token);
  if (pages > 1 || ids.size > 200) {
    pipelineLog(
      `Listed ${ids.size} video pack(s) under ${prefix} (${pages} ListObjects page(s))`,
      'info'
    );
  }
  return [...ids];
}

export function encodeMediaUrl(opts: {
  signedUrl: string;
  reel: boolean;
  r2Key: string;
  sourceId: string;
  kind: PackKind;
}): string {
  const payload: Record<string, unknown> = {
    urls: [opts.signedUrl],
    types: ['video'],
    r2_key: opts.r2Key,
    source: 'r2_focus_seed',
    source_id: opts.sourceId,
    kind: opts.kind,
    signed_at: new Date().toISOString(),
  };
  if (opts.reel) payload.reel = true;
  return JSON.stringify(payload);
}

export function extractR2KeyFromMediaPath(mediaPath: string): string | null {
  // r2:bucket/key or r2-share:bucket/key
  const m = mediaPath.match(/^r2(?:-share|-hubshare)?:(?:[^/]+)\/(.+)$/);
  return m?.[1] ?? null;
}

export function extractR2KeyFromMediaUrl(mediaUrl: string | null): string | null {
  if (!mediaUrl) return null;
  const raw = mediaUrl.trim();
  if (raw.startsWith('{')) {
    try {
      const obj = JSON.parse(raw) as { r2_key?: string };
      if (obj.r2_key) return String(obj.r2_key);
    } catch {
      /* ignore */
    }
  }
  return null;
}
