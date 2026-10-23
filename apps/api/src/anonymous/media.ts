/**
 * Resolve playable media URLs for Masquerade posts.
 * Stored values may be r2:bucket/key, bare keys, or https links (signed/public).
 *
 * Feed must stay fast: skip re-sign when the stored https URL still has headroom,
 * and bound concurrency so a page of posts cannot stall Render.
 */
import { getBucket } from '../content-pipeline/r2.js';
import { extractR2Key, resolvePlayUrlForKey } from '../media/r2-playback.js';

/** Re-sign when fewer than this many seconds remain on the Amz signature. */
const FRESH_HEADROOM_SECONDS = 6 * 3600;

function keyFromStored(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const s = String(raw).trim();
  if (!s) return null;

  // r2:bucket/key
  const m = s.match(/^r2(?:-share|-hubshare)?:(?:[^/]+)\/(.+)$/);
  if (m?.[1]) return m[1];

  // Already a path-like key without scheme
  if (!s.startsWith('http') && !s.startsWith('{') && s.includes('/')) {
    const bucket = getBucket();
    if (s.startsWith(`${bucket}/`)) return s.slice(bucket.length + 1);
    return s.replace(/^\/+/, '');
  }

  return extractR2Key(s);
}

/** True when stored https still has signature headroom — pass through (no R2 round-trip). */
function stillFreshHttps(raw: string): string | null {
  const s = raw.trim();
  if (!s.startsWith('http')) return null;
  try {
    const u = new URL(s);
    if (u.hostname.includes('r2.dev')) return null;
    if (
      u.hostname.includes('r2.cloudflarestorage.com') &&
      !u.searchParams.has('X-Amz-Signature') &&
      !u.searchParams.has('X-Amz-Algorithm')
    ) {
      return null;
    }
    const exp = u.searchParams.get('X-Amz-Expires');
    const date = u.searchParams.get('X-Amz-Date');
    if (!exp || !date) {
      // Non-signed public https — keep.
      if (!u.hostname.includes('r2.cloudflarestorage.com')) return s;
      return null;
    }
    const expSecs = Number(exp);
    if (!Number.isFinite(expSecs) || expSecs <= 0) return null;
    const m = date.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/);
    if (!m) return null;
    const start = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
    const expiresAt = start + expSecs * 1000;
    if (expiresAt - Date.now() < FRESH_HEADROOM_SECONDS * 1000) return null;
    return s;
  } catch {
    return null;
  }
}

export async function resolveAnonymousMediaUrl(
  stored: string | null | undefined
): Promise<string | null> {
  if (!stored) return null;
  const s = String(stored).trim();
  if (!s) return null;

  const fresh = stillFreshHttps(s);
  if (fresh) return fresh;

  try {
    const key = keyFromStored(s);
    if (key) {
      const play = await resolvePlayUrlForKey(key);
      if (play) return play;
    }
  } catch {
    /* fall through */
  }

  // Fresh https that we couldn't re-key — pass through (may still work if signed).
  if (s.startsWith('http')) return s;
  return null;
}

export async function withResolvedMedia<T extends {
  media_url?: string | null;
  thumb_url?: string | null;
}>(post: T): Promise<T> {
  try {
    const [media_url, thumb_url] = await Promise.all([
      resolveAnonymousMediaUrl(post.media_url),
      resolveAnonymousMediaUrl(post.thumb_url),
    ]);
    return { ...post, media_url, thumb_url };
  } catch {
    return post;
  }
}

export async function withResolvedMediaMany<T extends {
  media_url?: string | null;
  thumb_url?: string | null;
}>(posts: T[]): Promise<T[]> {
  if (!posts.length) return posts;
  // Bounded concurrency — unbounded Promise.all over a feed page can stall cold R2.
  const concurrency = 6;
  const out: T[] = new Array(posts.length);
  let idx = 0;
  async function worker() {
    while (idx < posts.length) {
      const i = idx++;
      out[i] = await withResolvedMedia(posts[i]);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(concurrency, posts.length) }, () => worker())
  );
  return out;
}

/** Canonical durable storage form for seeded R2 objects. */
export function r2MediaRef(key: string): string {
  const clean = key.replace(/^\/+/, '');
  return `r2:${getBucket()}/${clean}`;
}
