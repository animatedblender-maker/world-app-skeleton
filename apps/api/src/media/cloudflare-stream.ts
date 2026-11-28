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
  meta: { matterya_post_id: string; name?: string; r2_video_key?: string }
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
        ...(meta.r2_video_key ? { r2_video_key: meta.r2_video_key } : {}),
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

/** Normalize to the pack `…/video.mp4` key used as the Stream dedupe fingerprint. */
export function streamVideoKeyFromPost(post: {
  media_url?: string | null;
  media_path?: string | null;
}): string | null {
  const key =
    extractR2KeyFromMediaPath(String(post.media_path ?? '')) ||
    extractR2KeyFromMediaUrl(post.media_url ?? null) ||
    null;
  if (!key) return null;
  const videoKey = key.endsWith('/video.mp4')
    ? key
    : key.replace(/\/frame0_\d+\.webp$/i, '/video.mp4');
  return /video\.mp4$/i.test(videoKey) ? videoKey : null;
}

/**
 * Reuse an existing Stream UID from any post that shares the same R2 video.mp4
 * (original + feed-share rows look like "duplicates" in Stream if we copy twice).
 */
async function findExistingStreamUidForVideoKey(
  videoKey: string
): Promise<{ uid: string; ready: boolean } | null> {
  // Match media_path or embedded r2_key / path substring in media_url JSON.
  const { rows } = await pool.query<{ stream_uid: string; stream_ready_at: Date | null }>(
    `
    select stream_uid, stream_ready_at
    from public.posts
    where stream_uid is not null
      and (
        media_path ilike '%' || $1 || '%'
        or media_url ilike '%' || $1 || '%'
        or media_url ilike '%' || replace($1, '/', '%2F') || '%'
      )
    order by stream_ready_at desc nulls last
    limit 1
    `,
    [videoKey]
  );
  const uid = rows[0]?.stream_uid?.trim();
  if (!uid) return null;
  return { uid, ready: Boolean(rows[0]?.stream_ready_at) };
}

/**
 * Ingest one post: resolve R2 video → Stream copy → save uid.
 * Dedupes by R2 video.mp4 key so share/original twins share one Stream asset.
 * Uses a Postgres advisory lock on the video key so concurrent feed/sparks
 * workers (and multi-instance Render) cannot race two Stream copies.
 * Returns null when Stream env missing or no R2 key.
 */
export async function ingestPostToStream(post: {
  id: string;
  media_url?: string | null;
  media_path?: string | null;
  title?: string | null;
}): Promise<{ uid: string; hls: string | null; ready: boolean; reused?: boolean } | null> {
  if (!streamConfigured()) return null;
  const videoKey = streamVideoKeyFromPost(post);
  if (!videoKey) return null;

  const client = await pool.connect();
  try {
    // Serialize all ingests for this R2 key across API processes.
    await client.query('select pg_advisory_lock(hashtext($1::text))', [videoKey]);

    // Already have uid on this post — no-op.
    const existingSelf = await client.query<{
      stream_uid: string | null;
      stream_ready_at: Date | null;
    }>(`select stream_uid, stream_ready_at from public.posts where id = $1::uuid`, [post.id]);
    if (existingSelf.rows[0]?.stream_uid) {
      const uid = existingSelf.rows[0].stream_uid!;
      return {
        uid,
        hls: streamHlsUrl(uid),
        ready: Boolean(existingSelf.rows[0].stream_ready_at),
        reused: true,
      };
    }

    // Twin post (same R2 file) already ingested — reuse UID, do not copy again.
    const twin = await findExistingStreamUidForVideoKey(videoKey);
    if (twin) {
      await savePostStreamUid(post.id, twin.uid, twin.ready);
      return {
        uid: twin.uid,
        hls: streamHlsUrl(twin.uid),
        ready: twin.ready,
        reused: true,
      };
    }

    // Stream pulls once from a signed R2 GET (same PRESIGN_SECONDS as feed).
    const r2 = createR2Client();
    const sourceUrl = await presignGet(r2, videoKey);
    if (!sourceUrl) return null;

    const copied = await streamCopyFromUrl(sourceUrl, {
      matterya_post_id: post.id,
      name: post.title || post.id,
      r2_video_key: videoKey,
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

    // Stamp every other post that points at the same R2 video.mp4.
    await client.query(
      `
      update public.posts
      set stream_uid = $2,
          stream_ready_at = case when $3::boolean then coalesce(stream_ready_at, now()) else stream_ready_at end
      where stream_uid is null
        and id <> $1::uuid
        and (
          media_path ilike '%' || $4 || '%'
          or media_url ilike '%' || $4 || '%'
          or media_url ilike '%' || replace($4, '/', '%2F') || '%'
        )
      `,
      [post.id, copied.uid, ready, videoKey]
    );

    return {
      uid: copied.uid,
      hls: streamHlsUrl(copied.uid),
      ready,
      reused: false,
    };
  } finally {
    try {
      await client.query('select pg_advisory_unlock(hashtext($1::text))', [videoKey]);
    } catch {
      /* ignore unlock errors */
    }
    client.release();
  }
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
