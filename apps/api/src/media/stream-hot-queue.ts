/**
 * Hot-path Stream ingest: when /v1/feed or /v1/sparks serves a video without
 * stream_uid, copy that R2 pack to Cloudflare Stream in the background.
 *
 * - Never blocks the HTTP response
 * - Dedupes by post id + R2 video key (ingestPostToStream reuses twins)
 * - Caps concurrency so Feed traffic cannot storm Stream API
 * - No-op when CF_* env is missing
 */
import { streamConfigured, ingestPostToStream } from './cloudflare-stream.js';

type HotJob = {
  id: string;
  title?: string | null;
  media_url?: string | null;
  media_path?: string | null;
};

const MAX_CONCURRENT = 2;
const MAX_QUEUE = 80;
/** Cap new copies per process hour — hot head, not whole catalog. */
const MAX_INGESTS_PER_HOUR = 120;

const pending = new Map<string, HotJob>();
const inFlight = new Set<string>();
let active = 0;
let startedThisHour = 0;
let hourBucket = Math.floor(Date.now() / 3_600_000);

function looksVideo(job: HotJob): boolean {
  const m = `${job.media_url || ''} ${job.media_path || ''}`.toLowerCase();
  return (
    m.includes('video.mp4') ||
    m.includes('shortform') ||
    m.includes('.m3u8') ||
    m.includes('reel') ||
    m.includes('spark')
  );
}

function rollHour() {
  const b = Math.floor(Date.now() / 3_600_000);
  if (b !== hourBucket) {
    hourBucket = b;
    startedThisHour = 0;
  }
}

function pump() {
  if (!streamConfigured()) return;
  rollHour();
  while (active < MAX_CONCURRENT && pending.size > 0) {
    if (startedThisHour >= MAX_INGESTS_PER_HOUR) break;
    const next = pending.values().next().value as HotJob | undefined;
    if (!next) break;
    pending.delete(next.id);
    if (inFlight.has(next.id)) continue;
    inFlight.add(next.id);
    active += 1;
    startedThisHour += 1;
    void (async () => {
      try {
        const result = await ingestPostToStream({
          id: next.id,
          title: next.title,
          media_url: next.media_url,
          media_path: next.media_path,
        });
        if (result?.uid) {
          console.log(
            `[stream-hot] ${result.reused ? 'reuse' : 'ok'} post=${next.id} uid=${result.uid}`
          );
        }
      } catch (err: any) {
        console.error(`[stream-hot] fail post=${next.id}`, err?.message ?? err);
      } finally {
        inFlight.delete(next.id);
        active -= 1;
        pump();
      }
    })();
  }
}

/**
 * Enqueue videos from a thin surface page that still need Stream.
 * Safe to call on every /v1/feed and /v1/sparks response.
 */
export function enqueueHotStreamFromCards(
  cards: Array<{
    id?: string | null;
    title?: string | null;
    media_url?: string | null;
    media_path?: string | null;
    media_type?: string | null;
    stream_uid?: string | null;
    playback?: { hls?: string | null } | null;
  }>
): { queued: number } {
  if (!streamConfigured() || !cards?.length) return { queued: 0 };
  rollHour();
  if (startedThisHour >= MAX_INGESTS_PER_HOUR && pending.size === 0) {
    return { queued: 0 };
  }

  let queued = 0;
  for (const card of cards) {
    if (pending.size >= MAX_QUEUE) break;
    const id = String(card.id || '').trim();
    if (!id) continue;
    if (card.stream_uid || card.playback?.hls) continue;
    const mt = String(card.media_type || '').toLowerCase();
    const job: HotJob = {
      id,
      title: card.title,
      media_url: card.media_url,
      media_path: card.media_path ?? null,
    };
    const isVideo =
      mt.includes('video') ||
      mt === 'reel' ||
      mt === 'spark' ||
      looksVideo(job);
    if (!isVideo) continue;
    if (pending.has(id) || inFlight.has(id)) continue;
    pending.set(id, job);
    queued += 1;
  }
  if (queued) pump();
  return { queued };
}

export function hotStreamQueueStats() {
  rollHour();
  return {
    pending: pending.size,
    inFlight: inFlight.size,
    active,
    startedThisHour,
    maxPerHour: MAX_INGESTS_PER_HOUR,
    configured: streamConfigured(),
  };
}
