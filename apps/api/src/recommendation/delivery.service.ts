/**
 * At-most-once For You delivery (Matterya_Video_Feed_Algorithm_Architecture §4–5).
 *
 * - Canonical key prefers R2 object key, then share-origin, then post id.
 * - Idempotent batches: same (user, surface, idempotency_key) returns the committed order.
 * - Anonymous / missing tables → caller falls back to cursor weave (no ledger).
 */
import { randomUUID } from 'node:crypto';
import { pool, type PoolClient } from '../db.js';

export type FeedSurface = 'home_for_you' | 'hubs_for_you';

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

/** Stable identity for original + share of the same R2 pack. */
export function canonicalVideoKey(row: {
  id: string;
  media_url?: string | null;
  shared_post_id?: string | null;
  body?: string | null;
}): string {
  const media = String(row.media_url ?? '');
  const r2 = media.match(/"r2_key"\s*:\s*"([^"]+)"/i)?.[1];
  if (r2) return `r2:${r2.toLowerCase()}`;

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

  const url = media.match(/https?:\/\/[^"'\\\s?]+/i)?.[0];
  if (url) {
    const bare = url.toLowerCase().split('?')[0];
    if (
      bare.includes('.mp4') ||
      bare.includes('/shortform/') ||
      bare.includes('/longform/')
    ) {
      return `url:${bare}`;
    }
  }
  return `clip:${String(row.id).toLowerCase()}`;
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
