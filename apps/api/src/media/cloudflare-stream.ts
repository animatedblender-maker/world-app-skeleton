/**
 * Cloudflare Stream — Feed/Sparks HLS playback plane.
 *
 * Env (Render / local `.env`, never commit secrets):
 *   CF_ACCOUNT_ID
 *   CF_STREAM_API_TOKEN   (Account API token with Stream:Edit)
 *   CF_STREAM_CUSTOMER_CODE  (from Stream dashboard → customer-XXXX.cloudflarestream.com)
 *
 * Copy from a time-limited R2 GET of video.mp4 → poll until readyToStream → store posts.stream_uid.
 */
import { pool } from '../db.js';
import {
  createR2Client,
  extractR2KeyFromMediaPath,
  extractR2KeyFromMediaUrl,
  presignGet,
} from '../content-pipeline/r2.js';

const CF_API = 'https://api.cloudflare.com/client/v4';

export function streamConfigured(): boolean {
  return Boolean(
    process.env.CF_ACCOUNT_ID?.trim() &&
      process.env.CF_STREAM_API_TOKEN?.trim() &&
      process.env.CF_STREAM_CUSTOMER_CODE?.trim()
  );
}

export function streamHlsUrl(uid: string): string | null {
  const code = process.env.CF_STREAM_CUSTOMER_CODE?.trim();
  const id = String(uid || '').trim();
  if (!code || !id) return null;
  return `https://customer-${code}.cloudflarestream.com/${id}/manifest/video.m3u8`;
}

export function streamThumbnailUrl(uid: string): string | null {
  const code = process.env.CF_STREAM_CUSTOMER_CODE?.trim();
  const id = String(uid || '').trim();
  if (!code || !id) return null;
  return `https://customer-${code}.cloudflarestream.com/${id}/thumbnails/thumbnail.jpg`;
}

type StreamCopyResult = {
  uid: string;
  readyToStream: boolean;
  status?: string;
};

async function cfFetch(path: string, init?: RequestInit): Promise<any> {
  const account = process.env.CF_ACCOUNT_ID!.trim();
  const token = process.env.CF_STREAM_API_TOKEN!.trim();
  const res = await fetch(`${CF_API}/accounts/${account}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(init?.headers || {}),
    },
  });
  const json = (await res.json().catch(() => ({}))) as any;
  if (!res.ok || json?.success === false) {
    const err =
      json?.errors?.[0]?.message ||
      json?.messages?.[0] ||
      `HTTP ${res.status}`;
    throw new Error(`Cloudflare Stream: ${err}`);
  }
  return json;
}

/** Upload-by-URL: Stream pulls from a short-lived R2 signed GET. */
export async function streamCopyFromUrl(
  sourceUrl: string,
  meta: { matterya_post_id: string; name?: string }
): Promise<StreamCopyResult> {
  if (!streamConfigured()) {
    throw new Error('Cloudflare Stream not configured (CF_ACCOUNT_ID / CF_STREAM_API_TOKEN / CF_STREAM_CUSTOMER_CODE)');
  }
  const json = await cfFetch('/stream/copy', {
    method: 'POST',
    body: JSON.stringify({
      url: sourceUrl,
      meta: {
        name: meta.name || meta.matterya_post_id,
        matterya_post_id: meta.matterya_post_id,
      },
      requireSignedURLs: false,
    }),
  });
  const result = json?.result ?? {};
  return {
    uid: String(result.uid || ''),
    readyToStream: Boolean(result.readyToStream),
    status: result.status?.state || result.state,
  };
}

export async function streamGetVideo(uid: string): Promise<StreamCopyResult> {
  const json = await cfFetch(`/stream/${encodeURIComponent(uid)}`, { method: 'GET' });
  const result = json?.result ?? {};
  return {
    uid: String(result.uid || uid),
    readyToStream: Boolean(result.readyToStream),
    status: result.status?.state || result.state,
  };
}

/** Persist Stream UID on the post once ready (or provisional while encoding). */
export async function savePostStreamUid(
  postId: string,
  uid: string,
  ready: boolean
): Promise<void> {
  await pool.query(
    `
    update public.posts
    set stream_uid = $2,
        stream_ready_at = case when $3::boolean then now() else stream_ready_at end
    where id = $1::uuid
    `,
    [postId, uid, ready]
  );
}

/**
 * Ingest one post: resolve R2 video → Stream copy → save uid.
 * Returns null when Stream env missing or no R2 key.
 */
export async function ingestPostToStream(post: {
  id: string;
  media_url?: string | null;
  media_path?: string | null;
  title?: string | null;
}): Promise<{ uid: string; hls: string | null; ready: boolean } | null> {
  if (!streamConfigured()) return null;
  const key =
    extractR2KeyFromMediaPath(String(post.media_path ?? '')) ||
    extractR2KeyFromMediaUrl(post.media_url ?? null) ||
    null;
  if (!key) return null;
  const videoKey = key.endsWith('/video.mp4')
    ? key
    : key.replace(/\/frame0_\d+\.webp$/i, '/video.mp4');
  if (!/video\.mp4$/i.test(videoKey)) return null;

  // Stream pulls once from a signed R2 GET (same PRESIGN_SECONDS as feed).
  const client = createR2Client();
  const sourceUrl = await presignGet(client, videoKey);
  if (!sourceUrl) return null;

  const copied = await streamCopyFromUrl(sourceUrl, {
    matterya_post_id: post.id,
    name: post.title || post.id,
  });
  if (!copied.uid) return null;

  let ready = copied.readyToStream;
  if (!ready) {
    // Brief poll — encoding often finishes in seconds for short Sparks.
    for (let i = 0; i < 8; i++) {
      await new Promise((r) => setTimeout(r, 1500));
      const st = await streamGetVideo(copied.uid);
      if (st.readyToStream) {
        ready = true;
        break;
      }
    }
  }

  await savePostStreamUid(post.id, copied.uid, ready);
  return {
    uid: copied.uid,
    hls: streamHlsUrl(copied.uid),
    ready,
  };
}

/** Playback fields for /v1/feed cards when stream_uid is set. */
export function playbackFieldsForStreamUid(uid: string | null | undefined): {
  hls: string | null;
  poster: string | null;
} {
  const id = String(uid || '').trim();
  if (!id) return { hls: null, poster: null };
  return {
    hls: streamHlsUrl(id),
    poster: streamThumbnailUrl(id),
  };
}
