/**
 * Permanent R2 playback resolution.
 *
 * Objects live forever in the bucket. What used to expire were *presigned GET links*
 * baked into posts.media_url. This module always returns a *currently valid* play URL:
 *
 * 1) Mint a fresh **signed** GET when R2 credentials exist (preferred — public r2.dev often 403).
 * 2) Fall back to R2_PUBLIC_BASE_URL only if presign unavailable or R2_FORCE_PUBLIC=1.
 * 3) Rewrite media_url JSON so clients never keep a dead X-Amz-Signature / dead public link.
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
 * Prefer **real presigned GET** when credentials exist (public r2.dev often 403).
 * Public base is last-resort only (or when R2_FORCE_PUBLIC=1).
 */
export async function resolvePlayUrlForKey(key: string): Promise<string | null> {
  const clean = key.replace(/^\/+/, '').trim();
  if (!clean) return null;

  const forcePublic = process.env.R2_FORCE_PUBLIC === '1' || process.env.R2_FORCE_PUBLIC === 'true';
  if (forcePublic) {
    const permanent = publicObjectUrl(clean);
    if (permanent) return permanent;
  }

  const now = Date.now();
  const hit = urlCache.get(clean);
  if (hit && hit.staleAt > now) return hit.url;

  const c = getClient();
  if (c) {
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
      if (hit?.url) return hit.url;
      // Fall through to public base only if presign failed.
    }
  }

  // No credentials / presign failed → try public base (may 403 if bucket private).
  return publicObjectUrl(clean);
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

/** True if media_url already has a usable signed/public link with enough lifetime left. */
function existingPlayUrlStillFresh(mediaUrl: string | null | undefined): string | null {
  if (!mediaUrl) return null;
  const raw = String(mediaUrl).trim();
  let candidate: string | null = null;
  if (raw.startsWith('http')) candidate = raw;
  else if (raw.startsWith('{')) {
    try {
      const obj = JSON.parse(raw) as { urls?: string[] };
      const u = obj.urls?.[0];
      if (u && String(u).startsWith('http')) candidate = String(u);
    } catch {
      return null;
    }
  }
  if (!candidate) return null;
  try {
    const u = new URL(candidate);
    // Unsigned R2 hosts are NOT trustworthy — pub-*.r2.dev often 403 when ACL is private.
    // Force re-presign so Hubs/feed always get a live signed GET.
    if (!u.searchParams.has('X-Amz-Signature') && !u.searchParams.has('X-Amz-Algorithm')) {
      if (
        u.hostname.includes('r2.dev') ||
        u.hostname.includes('r2.cloudflarestorage.com')
      ) {
        return null;
      }
      // Non-R2 public (supabase / custom CDN) — keep.
      if (u.hostname.includes('supabase') || u.hostname.includes('matterya.com')) {
        return candidate;
      }
    }
    const exp = u.searchParams.get('X-Amz-Expires');
    const date = u.searchParams.get('X-Amz-Date');
    if (!exp || !date) return null;
    const expSecs = Number(exp);
    if (!Number.isFinite(expSecs) || expSecs <= 0) return null;
    // yyyyMMdd'T'HHmmss'Z'
    const m = date.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/);
    if (!m) return null;
    const start = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
    const deadline = start + expSecs * 1000;
    // Keep if more than 6h remain — skip expensive re-presign on every feed page.
    if (deadline - Date.now() > 6 * 3600 * 1000) return candidate;
    return null;
  } catch {
    return null;
  }
}

/**
 * Rewrite posts.media_url so `urls[0]` is a currently playable link.
 * Preserves r2_key / reel / kind metadata.
 * Fast path: skip re-presign when the existing signed URL still has hours left
 * (was re-signing every post on every feed request → multi-second lag).
 */
export async function freshenMediaUrlString(
  mediaUrl: string | null | undefined,
  mediaPath?: string | null
): Promise<string | null> {
  if (!mediaUrl && !mediaPath) return mediaUrl ?? null;

  // Hot path: existing link still good → return as-is (no R2/S3 call).
  if (existingPlayUrlStillFresh(mediaUrl) && mediaUrl) {
    return mediaUrl;
  }

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

/**
 * Re-presign Frame 0 / poster thumb_url so clients never open a dead X-Amz signature.
 * Prefer thumb_path (`r2:bucket/…/frame0_512.webp`); else parse key from the signed URL
 * or derive `…/frame0_512.webp` from the video pack (media_path / media_url).
 */
export async function freshenThumbUrlString(
  thumbUrl: string | null | undefined,
  thumbPath?: string | null,
  mediaHint?: string | null
): Promise<string | null> {
  if (!thumbUrl && !thumbPath && !mediaHint) return thumbUrl ?? null;

  if (thumbUrl && existingPlayUrlStillFresh(thumbUrl)) {
    return thumbUrl;
  }

  let key =
    (thumbPath ? extractR2KeyFromMediaPath(String(thumbPath)) : null) ||
    extractR2Key(thumbUrl, thumbPath) ||
    null;

  // Derive frame0 key from the video pack when thumb_path missing but media is R2.
  if (!key && mediaHint) {
    const videoKey =
      extractR2KeyFromMediaPath(String(mediaHint)) || extractR2Key(mediaHint, null);
    if (videoKey) {
      key = videoKey.endsWith('/video.mp4')
        ? videoKey.replace(/\/video\.mp4$/i, '/frame0_512.webp')
        : /frame0_\d+\.webp$/i.test(videoKey)
          ? videoKey
          : null;
    }
  }

  if (key?.endsWith('/video.mp4')) {
    key = key.replace(/\/video\.mp4$/i, '/frame0_512.webp');
  }

  if (!key) return thumbUrl ?? null;
  // Only mint for poster objects (never return a video URL as thumb).
  if (!/frame0_\d+\.webp$/i.test(key) && !/\.(webp|jpe?g|png)$/i.test(key)) {
    return thumbUrl ?? null;
  }

  const live = await resolvePlayUrlForKey(key);
  return live || thumbUrl || null;
}

/** Freshen media_url + thumb_url (and nested shared_post) before GraphQL response. */
export async function freshenPostsMedia<T extends Record<string, any>>(rows: T[]): Promise<T[]> {
  if (!rows?.length) return rows ?? [];
  // Only work when we can resolve (public base OR credentials).
  if (!r2PublicBaseUrl() && !r2Configured()) return rows;

  // Bounded concurrency — unbounded Promise.all over 40–100 posts hammered R2 + froze feed.
  const concurrency = 6;
  const out: T[] = new Array(rows.length);
  let idx = 0;
  async function worker() {
    while (idx < rows.length) {
      const i = idx++;
      const row = rows[i];
      const next: any = { ...row };
      const mediaPath = next.media_path ?? null;
      if (next.media_url || mediaPath) {
        const fresh = await freshenMediaUrlString(next.media_url, mediaPath);
        if (fresh) next.media_url = fresh;
      }
      if (next.thumb_url || next.thumb_path || mediaPath) {
        const freshThumb = await freshenThumbUrlString(
          next.thumb_url,
          next.thumb_path ?? null,
          mediaPath
        );
        if (freshThumb) next.thumb_url = freshThumb;
      }
      if (next.shared_post && typeof next.shared_post === 'object') {
        const sp: any = { ...next.shared_post };
        if (sp.media_url || sp.media_path) {
          const freshSp = await freshenMediaUrlString(sp.media_url, sp.media_path ?? null);
          if (freshSp) sp.media_url = freshSp;
        }
        if (sp.thumb_url || sp.thumb_path || sp.media_path) {
          const freshSpThumb = await freshenThumbUrlString(
            sp.thumb_url,
            sp.thumb_path ?? null,
            sp.media_path ?? null
          );
          if (freshSpThumb) sp.thumb_url = freshSpThumb;
        }
        next.shared_post = sp;
      }
      out[i] = next as T;
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, rows.length) }, () => worker()));
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
