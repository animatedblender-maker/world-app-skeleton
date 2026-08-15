/**
 * Permanent R2 playback resolution.
 *
 * Objects live forever in the bucket. What used to expire were *presigned GET links*
 * baked into posts.media_url. This module always returns a *currently valid* play URL:
 *
 * 1) If R2_PUBLIC_BASE_URL is set → stable public URL (no expiry) — preferred.
 * 2) Else mint a fresh presigned GET (cached in-process for most of its lifetime).
 * 3) Rewrite media_url JSON so clients never keep a dead X-Amz-Signature.
 */
import {
  createR2Client,
  encodeMediaUrl,
  extractR2KeyFromMediaPath,
  extractR2KeyFromMediaUrl,
  getBucket,
  packKindFromR2Key,
  PRESIGN_SECONDS,
  presignGet,
  r2Configured,
} from '../content-pipeline/r2.js';
import type { S3Client } from '@aws-sdk/client-s3';

/** Re-mint when less than this many seconds remain on a cached presign. */
const RESIGN_SLACK_SECONDS = 12 * 3600; // 12h before expiry

type CacheEntry = {
  url: string;
  /** epoch ms when this URL should be considered stale */
  staleAt: number;
};

const urlCache = new Map<string, CacheEntry>();
let client: S3Client | null = null;

function getClient(): S3Client | null {
  if (!r2Configured()) return null;
  if (!client) {
    try {
      client = createR2Client();
    } catch {
      return null;
    }
  }
  return client;
}

/** Optional permanent public base, e.g. https://media.matterya.com or r2.dev public bucket URL. */
export function r2PublicBaseUrl(): string | null {
  const raw = process.env.R2_PUBLIC_BASE_URL?.trim();
  if (!raw) return null;
  return raw.replace(/\/+$/, '');
}

export function publicObjectUrl(key: string): string | null {
  const base = r2PublicBaseUrl();
  if (!base) return null;
  const clean = key.replace(/^\/+/, '');
  return `${base}/${clean}`;
}

/**
 * Resolve a durable play URL for an R2 object key.
 * Public base wins (never expires). Else cached presign.
 */
export async function resolvePlayUrlForKey(key: string): Promise<string | null> {
  const clean = key.replace(/^\/+/, '').trim();
  if (!clean) return null;

  const permanent = publicObjectUrl(clean);
  if (permanent) return permanent;

  const now = Date.now();
  const hit = urlCache.get(clean);
  if (hit && hit.staleAt > now) return hit.url;

  const c = getClient();
  if (!c) return null;

  try {
    const url = await presignGet(c, clean);
    // Consider stale 12h before actual expiry so clients always get headroom.
    const ttlMs = Math.max(60_000, (PRESIGN_SECONDS - RESIGN_SLACK_SECONDS) * 1000);
    urlCache.set(clean, { url, staleAt: now + ttlMs });
    // Bound memory (28k+ keys possible over time).
    if (urlCache.size > 50_000) {
      const first = urlCache.keys().next().value;
      if (first) urlCache.delete(first);
    }
    return url;
  } catch (err) {
    console.warn('[r2-playback] presign failed', clean.slice(0, 80), err);
    return hit?.url ?? null;
  }
}

/** Extract R2 object key from media_url JSON / path / plain signed URL path. */
export function extractR2Key(
  mediaUrl: string | null | undefined,
  mediaPath?: string | null | undefined
): string | null {
  if (mediaPath) {
    const fromPath = extractR2KeyFromMediaPath(String(mediaPath));
    if (fromPath) return fromPath;
  }
  if (mediaUrl) {
    const fromJson = extractR2KeyFromMediaUrl(String(mediaUrl));
    if (fromJson) return fromJson;
    // Plain signed URL: …/matterya-sparks/<key>?X-Amz-…
    const raw = String(mediaUrl).trim();
    try {
      if (raw.startsWith('http')) {
        const u = new URL(raw);
        if (
          u.hostname.includes('r2.cloudflarestorage.com') ||
          u.hostname.includes('matterya') ||
          u.searchParams.has('X-Amz-Signature') ||
          u.searchParams.has('X-Amz-Algorithm')
        ) {
          // Path-style: /bucket/key… or /key…
          const parts = u.pathname.replace(/^\/+/, '').split('/');
          const bucket = getBucket();
          if (parts[0] === bucket) {
            return parts.slice(1).join('/') || null;
          }
          // Sometimes key is entire path after leading slash
          if (parts.length >= 2 && parts[parts.length - 1].includes('video')) {
            return parts.join('/');
          }
        }
      }
    } catch {
      /* ignore */
    }
  }
  return null;
}

/**
 * Rewrite posts.media_url so `urls[0]` is a currently playable link.
 * Preserves r2_key / reel / kind metadata.
 */
export async function freshenMediaUrlString(
  mediaUrl: string | null | undefined,
  mediaPath?: string | null
): Promise<string | null> {
  if (!mediaUrl && !mediaPath) return mediaUrl ?? null;
  const key = extractR2Key(mediaUrl, mediaPath);
  if (!key) return mediaUrl ?? null;

  const playUrl = await resolvePlayUrlForKey(key);
  if (!playUrl) return mediaUrl ?? null;

  const raw = (mediaUrl ?? '').trim();
  if (raw.startsWith('{')) {
    try {
      const obj = JSON.parse(raw) as Record<string, unknown>;
      const urls = Array.isArray(obj.urls) ? [...(obj.urls as string[])] : [];
      if (urls.length) urls[0] = playUrl;
      else urls.push(playUrl);
      obj.urls = urls;
      if (!obj.types) obj.types = ['video'];
      obj.r2_key = key;
      obj.signed_at = new Date().toISOString();
      if (r2PublicBaseUrl()) obj.public = true;
      return JSON.stringify(obj);
    } catch {
      /* fall through to encode */
    }
  }

  const kind = packKindFromR2Key(key);
  return encodeMediaUrl({
    signedUrl: playUrl,
    reel: kind === 'spark',
    r2Key: key,
    sourceId: key,
    kind,
  });
}

/** Freshen media_url (and nested shared_post.media_url) on post rows before GraphQL response. */
export async function freshenPostsMedia<T extends Record<string, any>>(rows: T[]): Promise<T[]> {
  if (!rows?.length) return rows ?? [];
  // Only work when we can resolve (public base OR credentials).
  if (!r2PublicBaseUrl() && !r2Configured()) return rows;

  const out = await Promise.all(
    rows.map(async (row) => {
      const next: any = { ...row };
      const mediaPath = next.media_path ?? null;
      if (next.media_url || mediaPath) {
        const fresh = await freshenMediaUrlString(next.media_url, mediaPath);
        if (fresh) next.media_url = fresh;
      }
      if (next.shared_post && typeof next.shared_post === 'object') {
        const sp: any = { ...next.shared_post };
        if (sp.media_url || sp.media_path) {
          const freshSp = await freshenMediaUrlString(sp.media_url, sp.media_path ?? null);
          if (freshSp) sp.media_url = freshSp;
        }
        next.shared_post = sp;
      }
      return next as T;
    })
  );
  return out;
}

export async function freshenOnePostMedia<T extends Record<string, any>>(row: T): Promise<T> {
  const [one] = await freshenPostsMedia([row]);
  return one ?? row;
}

/** Direct play URL for a post id (looks up DB). */
export async function resolvePlaybackForPostRow(row: {
  id?: string;
  media_url?: string | null;
  media_path?: string | null;
  shared_post?: { media_url?: string | null; media_path?: string | null } | null;
}): Promise<{ url: string; media_url: string; key: string } | null> {
  const key =
    extractR2Key(row.media_url, row.media_path) ||
    extractR2Key(row.shared_post?.media_url, row.shared_post?.media_path);
  if (!key) {
    // Non-R2: return plain media URL if present
    const plain = extractPlainVideoUrl(row.media_url) || extractPlainVideoUrl(row.shared_post?.media_url);
    if (plain) return { url: plain, media_url: row.media_url || plain, key: '' };
    return null;
  }
  const url = await resolvePlayUrlForKey(key);
  if (!url) return null;
  const media_url =
    (await freshenMediaUrlString(row.media_url || row.shared_post?.media_url, row.media_path)) ||
    encodeMediaUrl({
      signedUrl: url,
      reel: packKindFromR2Key(key) === 'spark',
      r2Key: key,
      sourceId: key,
      kind: packKindFromR2Key(key),
    });
  return { url, media_url, key };
}

function extractPlainVideoUrl(mediaUrl: string | null | undefined): string | null {
  if (!mediaUrl) return null;
  const raw = mediaUrl.trim();
  if (raw.startsWith('http')) return raw.split('?')[0] ? raw : null;
  if (raw.startsWith('{')) {
    try {
      const obj = JSON.parse(raw) as { urls?: string[] };
      const u = obj.urls?.[0];
      if (u && u.startsWith('http')) return u;
    } catch {
      /* ignore */
    }
  }
  return null;
}
