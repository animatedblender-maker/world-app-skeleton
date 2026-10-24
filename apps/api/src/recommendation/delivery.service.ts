/**
 * At-most-once For You delivery (Matterya_Video_Feed_Algorithm_Architecture §4–5).
 *
 * - Canonical key prefers R2 object key, then share-origin, then post id.
 * - Idempotent batches: same (user, surface, idempotency_key) returns the committed order.
 * - Anonymous / missing tables → caller falls back to cursor weave (no ledger).
 */
import { randomUUID } from 'node:crypto';
import { pool, type PoolClient } from '../db.js';
import { mindLedgerEnabled } from './mind-contracts.js';

export type FeedSurface = 'home_for_you' | 'hubs_for_you' | 'masquerade_for_you';

export type DeliveryCandidate = {
  id: string;
  canonicalKey: string;
};

let schemaReady: Promise<boolean> | null = null;

/** Best-effort CREATE IF NOT EXISTS so Manual Deploy works before migration apply. */
export function ensureFeedDeliverySchema(): Promise<boolean> {
  if (schemaReady) return schemaReady;
  schemaReady = (async () => {
    try {
      await pool.query(`
        create table if not exists public.feed_batch (
          batch_id         uuid primary key default gen_random_uuid(),
          user_id          uuid not null,
          surface          text not null,
          idempotency_key  text not null,
          created_at       timestamptz not null default now(),
          expires_at       timestamptz not null default (now() + interval '7 days'),
          status           text not null default 'building'
                           check (status in ('building', 'complete', 'failed')),
          unique (user_id, surface, idempotency_key)
        );
        create table if not exists public.feed_video_delivery (
          user_id              uuid not null,
          surface              text not null,
          canonical_video_id   text not null,
          first_video_id       uuid not null,
          delivery_id          uuid not null unique default gen_random_uuid(),
          batch_id             uuid not null,
          delivered_at         timestamptz not null default now(),
          primary key (user_id, surface, canonical_video_id)
        );
        create table if not exists public.feed_batch_item (
          batch_id     uuid not null,
          position     int not null,
          delivery_id  uuid not null,
          video_id     uuid not null,
          primary key (batch_id, position)
        );
        create index if not exists feed_video_delivery_user_time_idx
          on public.feed_video_delivery (user_id, surface, delivered_at desc);
      `);
      return true;
    } catch (err: any) {
      console.warn('[feed-delivery] schema ensure failed', err?.message ?? err);
      schemaReady = null;
      return false;
    }
  })();
  return schemaReady;
}

/** Pack folder id inside R2 keys (ShortForm, Reddit Posts/amiugly, Masquerade, …). */
const PACK_FOLDER_RE = /\/((?:ss|fy|om|pn|au)_[a-z0-9]+)(?:\/|$)/i;

/**
 * Object key from signed/public R2 HTTPS (JSON urls[] or plain).
 * Matches ledger shape `r2:posts/united_states/au_…/media/01.jpg`.
 */
function r2ObjectKeyFromMediaBlob(media: string): string | null {
  const r2Json = media.match(/"r2_key"\s*:\s*"([^"]+)"/i)?.[1];
  if (r2Json) return r2Json.replace(/^\/+/, '');
  // Durable Masquerade refs are bare `r2:bucket/key` or `r2:key`.
  const r2Bare = media.match(/(?:^|\n)r2:(?:matterya-sparks\/)?([^\s?]+)/i)?.[1];
  if (r2Bare) return r2Bare.replace(/^\/+/, '');

  const url = media.match(/https?:\/\/[^"'\\\s?]+/i)?.[0];
  if (!url) return null;
  try {
    const u = new URL(url);
    const host = u.hostname.toLowerCase();
    if (
      !host.includes('r2.cloudflarestorage.com') &&
      !host.includes('r2.dev') &&
      !host.includes('matterya')
    ) {
      return null;
    }
    const parts = u.pathname.replace(/^\/+/, '').split('/').filter(Boolean);
    if (!parts.length) return null;
    // Path-style: /matterya-sparks/<key…>
    if (parts[0] === 'matterya-sparks' && parts.length >= 2) {
      return parts.slice(1).join('/');
    }
    if (parts.length >= 2) return parts.join('/');
  } catch {
    /* ignore */
  }
  return null;
}

function packIdFromKey(key: string): string | null {
  return key.match(PACK_FOLDER_RE)?.[1]?.toLowerCase() ?? null;
}

/** Stable identity for original + share of the same R2 pack (video or image). */
export function canonicalVideoKey(row: {
  id: string;
  media_url?: string | null;
  thumb_url?: string | null;
  shared_post_id?: string | null;
  body?: string | null;
  media_type?: string | null;
}): string {
  const media = `${row.media_url ?? ''}\n${row.thumb_url ?? ''}`;
  const objectKey = r2ObjectKeyFromMediaBlob(media);
  if (objectKey) {
    const key = objectKey.toLowerCase();
    const packFromR2 = packIdFromKey(`/${key}/`) ?? packIdFromKey(key);
    // Prefer pack id so video.mp4 + media/01.jpg (and resign URL churn) collapse.
    if (packFromR2) return `pack:${packFromR2}`;
    return `r2:${key}`;
  }

  const shared = String(row.shared_post_id ?? '').trim();
  if (shared) return `clip:${shared.toLowerCase()}`;

  const body = String(row.body ?? '');
  const stamp =
    body.match(/__spark__\|[^|\n]*sid=([0-9a-f-]{36})/i)?.[1] ??
    body.match(/__hub_origin__\|[^|\n]*sid=([0-9a-f-]{36})/i)?.[1] ??
    body.match(/sid=([0-9a-f-]{36})/i)?.[1];
  if (stamp && stamp.toLowerCase() !== String(row.id).toLowerCase()) {
    return `clip:${stamp.toLowerCase()}`;
  }

  // TikTok country packs: …/United_States/1234567890/video.mp4 (or media/01.jpg)
  const pack = media.match(
    /(?:united_states|germany|albania|egypt|kosovo)\/(\d{8,})\//i
  )?.[1];
  if (pack) return `tt:${pack}`;

  // SecretsStrange / ShortForm / funny / amiugly pack folders.
  const ss = media.match(PACK_FOLDER_RE)?.[1];
  if (ss) return `pack:${ss.toLowerCase()}`;

  const url = media.match(/https?:\/\/[^"'\\\s?]+/i)?.[0];
  if (url) {
    const bare = url.toLowerCase().split('?')[0];
    if (
      bare.includes('.mp4') ||
      bare.includes('/shortform/') ||
      bare.includes('/longform/') ||
      bare.includes('/posts/') ||
      /\.(jpe?g|png|webp|gif)$/i.test(bare) ||
      bare.includes('/media/')
    ) {
      const dir = bare.replace(/\/[^/]+$/, '');
      if (
        dir.includes('/united_states/') ||
        dir.includes('/germany/') ||
        dir.includes('/albania/') ||
        dir.includes('/egypt/')
      ) {
        return `url:${dir}`;
      }
      return `url:${bare}`;
    }
  }

  return `clip:${String(row.id).toLowerCase()}`;
}

/**
 * All identities that mean "same underlying media" for delivery exclusion.
 * Covers legacy ledger rows (`r2:posts/…`) after pack: preference, and clip ids.
 */
export function canonicalVideoAliasKeys(row: {
  id: string;
  media_url?: string | null;
  thumb_url?: string | null;
  shared_post_id?: string | null;
  body?: string | null;
  media_type?: string | null;
}): string[] {
  const keys = new Set<string>();
  const primary = canonicalVideoKey(row);
  keys.add(primary);

  const media = `${row.media_url ?? ''}\n${row.thumb_url ?? ''}`;
  const objectKey = r2ObjectKeyFromMediaBlob(media)?.toLowerCase();
  if (objectKey) {
    keys.add(`r2:${objectKey}`);
    const pack = packIdFromKey(`/${objectKey}/`) ?? packIdFromKey(objectKey);
    if (pack) keys.add(`pack:${pack}`);
    // Legacy full-URL keys from earlier canonicalVideoKey revisions.
    const url = media.match(/https?:\/\/[^"'\\\s?]+/i)?.[0];
    if (url) {
      const bare = url.toLowerCase().split('?')[0];
      keys.add(`url:${bare}`);
      keys.add(`url:${bare.replace(/\/[^/]+$/, '')}`);
    }
  }

  const shared = String(row.shared_post_id ?? '').trim().toLowerCase();
  if (shared) keys.add(`clip:${shared}`);
  keys.add(`clip:${String(row.id).toLowerCase()}`);
  return [...keys];
}

export async function loadDeliveredCanonicalKeys(
  userId: string,
  surface: FeedSurface,
  limit = 50_000
): Promise<Set<string>> {
  const ok = await ensureFeedDeliverySchema();
  if (!ok) return new Set();
  try {
    const { rows } = await pool.query<{ canonical_video_id: string }>(
      `
      select canonical_video_id
      from public.feed_video_delivery
      where user_id = $1::uuid and surface = $2
      order by delivered_at desc
      limit $3
      `,
      [userId, surface, limit]
    );
    return new Set(rows.map((r) => String(r.canonical_video_id)));
  } catch (err: any) {
    console.warn('[feed-delivery] load delivered failed', err?.message ?? err);
    return new Set();
  }
}

export type ReservedBatch = {
  batchId: string;
  videoIds: string[];
  deliveryIds: string[];
  replay: boolean;
};

/** Return a previously committed batch for this idempotency key, if any. */
export async function loadCommittedBatch(
  userId: string,
  surface: FeedSurface,
  idempotencyKey: string
): Promise<ReservedBatch | null> {
  const ok = await ensureFeedDeliverySchema();
  if (!ok) return null;
  const key = String(idempotencyKey ?? '').trim().slice(0, 128);
  if (!key) return null;
  try {
    const { rows: batches } = await pool.query<{
      batch_id: string;
      status: string;
    }>(
      `
      select batch_id, status
      from public.feed_batch
      where user_id = $1::uuid and surface = $2 and idempotency_key = $3
      limit 1
      `,
      [userId, surface, key]
    );
    const batch = batches[0];
    if (!batch || batch.status !== 'complete') return null;
    const { rows: items } = await pool.query<{
      video_id: string;
      delivery_id: string;
    }>(
      `
      select video_id::text as video_id, delivery_id::text as delivery_id
      from public.feed_batch_item
      where batch_id = $1::uuid
      order by position asc
      `,
      [batch.batch_id]
    );
    if (!items.length) return null;
    return {
      batchId: batch.batch_id,
      videoIds: items.map((i) => i.video_id),
      deliveryIds: items.map((i) => i.delivery_id),
      replay: true,
    };
  } catch (err: any) {
    console.warn('[feed-delivery] loadCommittedBatch failed', err?.message ?? err);
    return null;
  }
}

/**
 * Atomically reserve unseen candidates for this user+surface.
 * Candidates must already be ranked (best first). Skips already-delivered canonicals.
 */
export async function reserveDeliveryBatch(input: {
  userId: string;
  surface: FeedSurface;
  idempotencyKey: string;
  candidates: DeliveryCandidate[];
  limit: number;
}): Promise<ReservedBatch | null> {
  // MIND-009: kill switch → callers fall back to cursor weave.
  if (!mindLedgerEnabled()) return null;

  const ok = await ensureFeedDeliverySchema();
  if (!ok) return null;

  const userId = String(input.userId).trim();
  const surface = input.surface;
  const key = String(input.idempotencyKey ?? '').trim().slice(0, 128) || randomUUID();
  const want = Math.min(Math.max(Number(input.limit) || 12, 1), 40);

  const prior = await loadCommittedBatch(userId, surface, key);
  if (prior) return prior;

  // Dedupe candidates by canonical, preserve rank order.
  const seenCanon = new Set<string>();
  const ordered: DeliveryCandidate[] = [];
  for (const c of input.candidates) {
    const id = String(c.id ?? '').trim();
    const canon = String(c.canonicalKey ?? '').trim();
    if (!id || !canon) continue;
    if (seenCanon.has(canon)) continue;
    seenCanon.add(canon);
    ordered.push({ id, canonicalKey: canon });
  }
  if (!ordered.length) return null;

  const client = await pool.connect();
  try {
    await client.query('begin');
    // Serialize reservations per user+surface for this request window.
    await client.query(`select pg_advisory_xact_lock(hashtext($1))`, [
      `${userId}:${surface}`,
    ]);

    // Re-check idempotency inside the lock.
    const again = await loadCommittedBatchTx(client, userId, surface, key);
    if (again) {
      await client.query('commit');
      return again;
    }

    const batchId = randomUUID();
    await client.query(
      `
      insert into public.feed_batch
        (batch_id, user_id, surface, idempotency_key, status, expires_at)
      values ($1::uuid, $2::uuid, $3, $4, 'building', now() + interval '7 days')
      on conflict (user_id, surface, idempotency_key) do nothing
      `,
      [batchId, userId, surface, key]
    );

    // If another worker won the insert, re-read.
    const { rows: owned } = await client.query<{ batch_id: string; status: string }>(
      `
      select batch_id, status from public.feed_batch
      where user_id = $1::uuid and surface = $2 and idempotency_key = $3
      `,
      [userId, surface, key]
    );
    const batch = owned[0];
    if (!batch) {
      await client.query('rollback');
      return null;
    }
    if (batch.status === 'complete') {
      const committed = await loadCommittedBatchTx(client, userId, surface, key);
      await client.query('commit');
      return committed;
    }
    const activeBatchId = batch.batch_id;

    const videoIds: string[] = [];
    const deliveryIds: string[] = [];
    let position = 0;

    for (const c of ordered) {
      if (position >= want) break;
      const deliveryId = randomUUID();
      const { rowCount } = await client.query(
        `
        insert into public.feed_video_delivery
          (user_id, surface, canonical_video_id, first_video_id, delivery_id, batch_id)
        values ($1::uuid, $2, $3, $4::uuid, $5::uuid, $6::uuid)
        on conflict (user_id, surface, canonical_video_id) do nothing
        `,
        [userId, surface, c.canonicalKey, c.id, deliveryId, activeBatchId]
      );
      if (!rowCount) continue;
      await client.query(
        `
        insert into public.feed_batch_item (batch_id, position, delivery_id, video_id)
        values ($1::uuid, $2, $3::uuid, $4::uuid)
        `,
        [activeBatchId, position, deliveryId, c.id]
      );
      videoIds.push(c.id);
      deliveryIds.push(deliveryId);
      position += 1;
    }

    await client.query(
      `
      update public.feed_batch
      set status = 'complete'
      where batch_id = $1::uuid
      `,
      [activeBatchId]
    );
    await client.query('commit');

    if (!videoIds.length) {
      return { batchId: activeBatchId, videoIds: [], deliveryIds: [], replay: false };
    }
    return {
      batchId: activeBatchId,
      videoIds,
      deliveryIds,
      replay: false,
    };
  } catch (err: any) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    console.warn('[feed-delivery] reserve failed', err?.message ?? err);
    return null;
  } finally {
    client.release();
  }
}

async function loadCommittedBatchTx(
  client: PoolClient,
  userId: string,
  surface: FeedSurface,
  key: string
): Promise<ReservedBatch | null> {
  const { rows: batches } = await client.query<{
    batch_id: string;
    status: string;
  }>(
    `
    select batch_id, status
    from public.feed_batch
    where user_id = $1::uuid and surface = $2 and idempotency_key = $3
    limit 1
    `,
    [userId, surface, key]
  );
  const batch = batches[0];
  if (!batch || batch.status !== 'complete') return null;
  const { rows: items } = await client.query<{
    video_id: string;
    delivery_id: string;
  }>(
    `
    select video_id::text as video_id, delivery_id::text as delivery_id
    from public.feed_batch_item
    where batch_id = $1::uuid
    order by position asc
    `,
    [batch.batch_id]
  );
  if (!items.length) return null;
  return {
    batchId: batch.batch_id,
    videoIds: items.map((i) => i.video_id),
    deliveryIds: items.map((i) => i.delivery_id),
    replay: true,
  };
}

/** Filter + order rows to match a reserved video id list. */
export function orderRowsByIds<T extends { id: string }>(
  rows: T[],
  ids: string[]
): T[] {
  const map = new Map(rows.map((r) => [r.id, r]));
  const out: T[] = [];
  for (const id of ids) {
    const row = map.get(id);
    if (row) out.push(row);
  }
  return out;
}
