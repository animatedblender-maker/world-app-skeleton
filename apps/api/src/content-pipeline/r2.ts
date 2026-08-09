import {
  GetObjectCommand,
  ListObjectsV2Command,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
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
 * Layout:
 *   Sparks:   <Country>/<id>/video.mp4
 *   LongForm: LongForm/<Country>/<id>/video.mp4
 */
export async function discoverPacks(
  client: S3Client,
  opts: { maxKeysPerPrefix?: number } = {}
): Promise<R2Pack[]> {
  const maxKeys = opts.maxKeysPerPrefix ?? 5000;
  const packs: R2Pack[] = [];
  const seen = new Set<string>();

  for (const c of FOCUS_COUNTRIES) {
    // Sparks under country root
    const sparkIds = await listVideoPackIds(client, `${c.folder}/`, maxKeys);
    for (const videoId of sparkIds) {
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

    // LongForm
    const lfIds = await listVideoPackIds(client, `LongForm/${c.folder}/`, maxKeys);
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

async function listVideoPackIds(
  client: S3Client,
  prefix: string,
  maxKeys: number
): Promise<string[]> {
  const ids = new Set<string>();
  let token: string | undefined;
  let listed = 0;
  do {
    const page = await client.send(
      new ListObjectsV2Command({
        Bucket: getBucket(),
        Prefix: prefix,
        ContinuationToken: token,
        MaxKeys: 1000,
      })
    );
    for (const obj of page.Contents ?? []) {
      const key = obj.Key || '';
      listed += 1;
      // …/<id>/video.mp4
      const m = key.match(/\/([^/]+)\/video\.mp4$/i);
      if (m?.[1]) ids.add(m[1]);
    }
    token = page.IsTruncated ? page.NextContinuationToken : undefined;
    if (listed >= maxKeys) break;
  } while (token);
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
