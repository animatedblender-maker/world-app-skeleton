/**
 * Instant Frame 0 posters from R2 pack path (no client ffmpeg).
 *
 *   GET  /v1/poster/:postId          → { ok, url, key, size }
 *   POST /v1/poster/batch            → { ok, posters: { [postId]: url } }
 *
 * Derives `{pack}/frame0_512.webp` from posts.media_path / media_url.r2_key.
 */
import type { Request, Response } from 'express';
import { pool } from '../db.js';
import { extractR2KeyFromMediaPath, extractR2KeyFromMediaUrl } from '../content-pipeline/r2.js';
import { resolvePlayUrlForKey } from './r2-playback.js';

export const FRAME0_DEFAULT_POSTER_SIZE = 512;

export function frame0KeyFromVideoKey(videoKey: string, size = FRAME0_DEFAULT_POSTER_SIZE): string {
  const clean = videoKey.replace(/^\/+/, '');
  if (clean.endsWith('/video.mp4')) {
    return `${clean.slice(0, -'/video.mp4'.length)}/frame0_${size}.webp`;
  }
  if (/\.mp4$/i.test(clean)) {
    const i = clean.lastIndexOf('/');
    const prefix = i >= 0 ? clean.slice(0, i) : clean.replace(/\.mp4$/i, '');
    return `${prefix}/frame0_${size}.webp`;
  }
  if (/frame0_\d+\.webp$/i.test(clean)) return clean;
  const i = clean.lastIndexOf('/');
  const prefix = i >= 0 ? clean.slice(0, i) : clean;
  return `${prefix}/frame0_${size}.webp`;
}

export function videoKeyFromPostRow(row: {
  media_path?: string | null;
  media_url?: string | null;
}): string | null {
  const fromPath = row.media_path ? extractR2KeyFromMediaPath(String(row.media_path)) : null;
  if (fromPath) return fromPath;
  return extractR2KeyFromMediaUrl(row.media_url ?? null);
}

async function lookupPostKeys(
  postIds: string[]
): Promise<Map<string, { videoKey: string; thumbUrl: string | null }>> {
  const out = new Map<string, { videoKey: string; thumbUrl: string | null }>();
  if (!postIds.length) return out;
  const { rows } = await pool.query<{
    id: string;
    media_path: string | null;
    media_url: string | null;
    thumb_url: string | null;
    origin_media_path: string | null;
    origin_media_url: string | null;
    origin_thumb_url: string | null;
  }>(
    `
    select
      p.id,
      p.media_path,
      p.media_url,
      p.thumb_url,
      o.media_path as origin_media_path,
      o.media_url as origin_media_url,
      o.thumb_url as origin_thumb_url
    from public.posts p
    left join public.posts o on o.id = p.shared_post_id
    where p.id = any($1::uuid[])
    `,
    [postIds]
  );
  for (const r of rows) {
    const videoKey =
      videoKeyFromPostRow({ media_path: r.media_path, media_url: r.media_url }) ||
      videoKeyFromPostRow({ media_path: r.origin_media_path, media_url: r.origin_media_url });
    if (!videoKey) continue;
    const thumbUrl =
      (r.thumb_url && String(r.thumb_url).includes('frame0_') ? r.thumb_url : null) ||
      (r.origin_thumb_url && String(r.origin_thumb_url).includes('frame0_')
        ? r.origin_thumb_url
        : null);
    out.set(String(r.id), { videoKey, thumbUrl });
  }
  return out;
}

export async function handlePosterGet(req: Request, res: Response): Promise<void> {
  try {
    const postId = String(req.params.postId || '').trim();
    if (!postId) {
      res.status(400).json({ error: 'post_id_required' });
      return;
    }
    const size = Number(req.query.size) === 1080 || Number(req.query.size) === 256
      ? Number(req.query.size)
      : FRAME0_DEFAULT_POSTER_SIZE;
    const map = await lookupPostKeys([postId]);
    const hit = map.get(postId);
    if (!hit) {
      res.status(404).json({ error: 'not_found' });
      return;
    }
    const key = frame0KeyFromVideoKey(hit.videoKey, size);
    const url = await resolvePlayUrlForKey(key);
    if (!url) {
      res.status(404).json({ error: 'poster_unavailable', key });
      return;
    }
    res.json({ ok: true, post_id: postId, url, key, size });
  } catch (err: any) {
    console.error('[poster]', err?.message ?? err);
    res.status(500).json({ error: 'poster_failed', message: err?.message ?? 'error' });
  }
}

export async function handlePosterBatch(req: Request, res: Response): Promise<void> {
  try {
    const raw = (req.body?.postIds ?? req.body?.post_ids ?? []) as unknown;
    const ids = (Array.isArray(raw) ? raw : [])
      .map((x) => String(x || '').trim())
      .filter(Boolean)
      .slice(0, 24);
    if (!ids.length) {
      res.status(400).json({ error: 'post_ids_required' });
      return;
    }
    const size = Number(req.body?.size) === 1080 || Number(req.body?.size) === 256
      ? Number(req.body.size)
      : FRAME0_DEFAULT_POSTER_SIZE;
    const map = await lookupPostKeys(ids);
    const posters: Record<string, string> = {};
    const keys: Record<string, string> = {};
    await Promise.all(
      ids.map(async (id) => {
        const hit = map.get(id);
        if (!hit) return;
        const key = frame0KeyFromVideoKey(hit.videoKey, size);
        const url = await resolvePlayUrlForKey(key);
        if (url) {
          posters[id] = url;
          keys[id] = key;
        }
      })
    );
    res.json({ ok: true, posters, keys, size, count: Object.keys(posters).length });
  } catch (err: any) {
    console.error('[poster/batch]', err?.message ?? err);
    res.status(500).json({ error: 'poster_batch_failed', message: err?.message ?? 'error' });
  }
}
