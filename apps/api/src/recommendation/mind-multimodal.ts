/**
 * MIND multimodal — Voyage voyage-multimodal-3.5 for Sparks videos AND image posts.
 *
 * Table stays `mind_sparks_multimodal_embeddings` (shared vector space).
 * Soft ANN on Sparks + Home. Missing embed = UNKNOWN (never demote).
 * Kill-switch: MIND_MULTIMODAL_ENABLED (defaults ON when VOYAGE_API_KEY is set).
 *
 * Note: many image posts live under r2:matterya-sparks/Posts/… — path alone is
 * not enough to tell Sparks video from stills; use media_type.
 */
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve as pathResolve } from 'node:path';
import { pool } from '../db.js';
import { freshenThumbUrlString } from '../media/r2-playback.js';

export const MIND_MM_MODEL = 'voyage-multimodal-3.5';
export const MIND_MM_MODEL_VERSION = 'voyage:voyage-multimodal-3.5';
export const MIND_MM_DIMS = 1024;
export const MIND_MM_SOURCE = 'sparks_thumb';
export const MIND_MM_SOURCE_IMAGE = 'image';

/** Exclude LongForm hub packs from multimodal. */
const MM_NOT_LONGFORM_SQL = `
  coalesce(p.media_path, '') not ilike '%LongForm%'
  and coalesce(p.media_path, '') not ilike '%longform%'
`;

/** Short-form Sparks / reels / TikTok / ShortForm videos (not stills). */
export const SPARKS_VIDEO_SQL = `
  (${MM_NOT_LONGFORM_SQL})
  and lower(coalesce(p.media_type, '')) not in ('image', 'photo', 'gif', 'picture')
  and (
    lower(coalesce(p.media_type, '')) in ('reel', 'spark', 'video')
    or coalesce(p.media_type, '') ilike '%reel%'
    or coalesce(p.media_path, '') ilike '%matterya-sparks%'
    or coalesce(p.media_path, '') ilike '%ShortForm%'
    or coalesce(p.media_path, '') ilike '%shortform%'
    or coalesce(p.media_path, '') ilike '%TikTok%'
  )
`;

/** Still image posts (Home image lane + matterya-sparks image uploads). */
export const IMAGE_POST_SQL = `
  (${MM_NOT_LONGFORM_SQL})
  and (
    lower(coalesce(p.media_type, '')) in ('image', 'photo', 'gif', 'picture')
    or coalesce(p.media_type, '') ilike '%image%'
  )
`;

/** Sparks videos OR image posts — full multimodal inventory. */
export const SPARKS_POST_SQL = `
  ((${SPARKS_VIDEO_SQL}) or (${IMAGE_POST_SQL}))
`;

const MM_HAS_THUMB_SQL = `
  (
    nullif(p.thumb_url, '') is not null
    or nullif(p.thumb_path, '') is not null
    or (
      lower(coalesce(p.media_type, '')) in ('image', 'photo', 'gif', 'picture')
      and (
        nullif(p.media_url, '') is not null
        or nullif(p.media_path, '') is not null
      )
    )
  )
`;

function mmSourceForMediaType(mediaType: string | null | undefined): string {
  const mt = String(mediaType ?? '').trim().toLowerCase();
  if (mt === 'image' || mt === 'photo' || mt === 'gif' || mt === 'picture' || mt.includes('image')) {
    return MIND_MM_SOURCE_IMAGE;
  }
  return MIND_MM_SOURCE;
}

function mmKindForMediaType(mediaType: string | null | undefined): 'spark' | 'image' {
  return mmSourceForMediaType(mediaType) === MIND_MM_SOURCE_IMAGE ? 'image' : 'spark';
}

export function mindMultimodalEnabled(): boolean {
  const raw = process.env.MIND_MULTIMODAL_ENABLED?.trim().toLowerCase();
  if (raw === '0' || raw === 'false' || raw === 'off' || raw === 'no') return false;
  return !!process.env.VOYAGE_API_KEY?.trim();
}

function voyageKey(): string | null {
  return process.env.VOYAGE_API_KEY?.trim() || null;
}

function fingerprint(s: string): string {
  return createHash('sha256').update(s.toLowerCase().trim()).digest('hex').slice(0, 32);
}

function vectorLiteral(v: number[]): string {
  return `[${v.join(',')}]`;
}

let schemaReady = false;

export async function ensureMultimodalSchema(): Promise<boolean> {
  if (schemaReady) return true;
  try {
    await pool.query(`create extension if not exists vector`);
    await pool.query(`
      create table if not exists public.mind_sparks_multimodal_embeddings (
        post_id uuid primary key references public.posts (id) on delete cascade,
        model_version text not null,
        dims int not null,
        embedding vector(${MIND_MM_DIMS}) not null,
        source text not null default '${MIND_MM_SOURCE}',
        thumb_fingerprint text,
        updated_at timestamptz not null default now()
      )
    `);
    await pool.query(`
      create index if not exists mind_sparks_mm_hnsw
        on public.mind_sparks_multimodal_embeddings
        using hnsw (embedding vector_cosine_ops)
    `);
    schemaReady = true;
    return true;
  } catch (err: any) {
    console.warn('[mind-multimodal] ensure schema failed', err?.message ?? err);
    return false;
  }
}

type MmContentPart =
  | { type: 'text'; text: string }
  | { type: 'image_url'; image_url: string }
  | { type: 'image_base64'; image_base64: string };

type VoyageMmResponse = {
  data: { embedding: number[]; index: number }[];
  model?: string;
  usage?: { total_tokens?: number; image_pixels?: number };
};

async function embedMultimodal(
  inputs: { content: MmContentPart[] }[],
  inputType: 'document' | 'query' = 'document'
): Promise<number[][]> {
  const key = voyageKey();
  if (!key) throw new Error('VOYAGE_API_KEY missing');
  if (inputs.length === 0) return [];

  const res = await fetch('https://api.voyageai.com/v1/multimodalembeddings', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: MIND_MM_MODEL,
      input_type: inputType,
      inputs,
      // voyage-multimodal-3.5 default dims = 1024 (= MIND_MM_DIMS).
    }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`voyage multimodal ${res.status}: ${body.slice(0, 280)}`);
  }
  const json = (await res.json()) as VoyageMmResponse;
  const sorted = [...(json.data ?? [])].sort((a, b) => a.index - b.index);
  return sorted.map((d) => d.embedding);
}

type ThumbBytes = { dataUrl: string; buf: Buffer; mime: string; ext: string };

/** Download thumb → data URL so Voyage never hits expired/robots-blocked R2 URLs. */
async function thumbToBytes(url: string): Promise<ThumbBytes | null> {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 12_000);
    const res = await fetch(url, {
      signal: ctrl.signal,
      headers: { Accept: 'image/*,*/*' },
    });
    clearTimeout(t);
    if (!res.ok) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    // Cap ~4MB — Voyage rejects oversized images.
    if (buf.length < 64 || buf.length > 4_000_000) return null;
    const ctype = (res.headers.get('content-type') || 'image/webp').split(';')[0]!.trim();
    const mime =
      ctype === 'image/png' ||
      ctype === 'image/jpeg' ||
      ctype === 'image/jpg' ||
      ctype === 'image/webp' ||
      ctype === 'image/gif'
        ? ctype === 'image/jpg'
          ? 'image/jpeg'
          : ctype
        : 'image/webp';
    const ext =
      mime === 'image/png'
        ? 'png'
        : mime === 'image/gif'
          ? 'gif'
          : mime === 'image/webp'
            ? 'webp'
            : 'jpg';
    return { dataUrl: `data:${mime};base64,${buf.toString('base64')}`, buf, mime, ext };
  } catch {
    return null;
  }
}

/** Optional live gallery: set MIND_MM_FRAME_DIR to cache thumbs as they embed. */
function cacheFrameForProgress(
  postId: string,
  title: string | null,
  thumb: ThumbBytes,
  kind: 'spark' | 'image'
): void {
  const dir = process.env.MIND_MM_FRAME_DIR?.trim();
  if (!dir) return;
  try {
    const frames = pathResolve(dir, 'frames');
    mkdirSync(frames, { recursive: true });
    const file = `${postId}.${thumb.ext}`;
    writeFileSync(pathResolve(frames, file), thumb.buf);
    const recentPath = pathResolve(dir, 'recent.json');
    let recent: { id: string; title: string; file: string; at: string; kind: string }[] =
      [];
    if (existsSync(recentPath)) {
      try {
        recent = JSON.parse(readFileSync(recentPath, 'utf8'));
        if (!Array.isArray(recent)) recent = [];
      } catch {
        recent = [];
      }
    }
    recent = [
      {
        id: postId,
        title: String(title ?? '').slice(0, 80),
        file,
        at: new Date().toISOString(),
        kind,
      },
      ...recent.filter((r) => r.id !== postId),
    ].slice(0, 72);
    writeFileSync(recentPath, JSON.stringify(recent, null, 2));
  } catch {
    /* gallery is best-effort */
  }
}

async function resolveSparkThumbUrl(row: {
  thumb_url: string | null;
  thumb_path: string | null;
  media_url: string | null;
  media_path: string | null;
  media_type?: string | null;
}): Promise<string | null> {
  const hint = row.media_path || row.media_url;
  const fresh = await freshenThumbUrlString(row.thumb_url, row.thumb_path, hint);
  if (fresh && /^https?:\/\//i.test(fresh)) return fresh;
  if (row.thumb_url && /^https?:\/\//i.test(row.thumb_url)) return row.thumb_url;
  // Image posts often use media_url as the still itself.
  if (row.media_url && /^https?:\/\//i.test(row.media_url)) {
    const mt = String(row.media_type ?? '').toLowerCase();
    if (mt === 'image' || mt === 'photo' || mt === 'gif' || mt.includes('image')) {
      return row.media_url;
    }
  }
  return null;
}

function captionText(title: string | null, body: string | null): string {
  const t = [title, body]
    .map((s) => String(s ?? '').trim())
    .filter(Boolean)
    .join(' ')
    .slice(0, 400);
  return t || 'matterya spark';
}

/** Process-local permanent skips (bad resolution / unreadable thumbs) so backfill advances. */
const mmPermanentSkip = new Set<string>();

function isPermanentMmError(msg: string): boolean {
  const m = msg.toLowerCase();
  return (
    m.includes('resolution is not within') ||
    m.includes('image resolution') ||
    m.includes('not within the permitted range') ||
    m.includes('larger than 20 mb') ||
    m.includes('more than 16 million pixels')
  );
}

export async function upsertMultimodalForPost(postId: string): Promise<boolean> {
  if (!mindMultimodalEnabled() || !postId) return false;
  if (mmPermanentSkip.has(postId)) return false;
  const ok = await ensureMultimodalSchema();
  if (!ok) return false;

  try {
    const { rows } = await pool.query<{
      id: string;
      title: string | null;
      body: string | null;
      thumb_url: string | null;
      thumb_path: string | null;
      media_url: string | null;
      media_path: string | null;
      media_type: string | null;
    }>(
      `
      select p.id::text, p.title, p.body, p.thumb_url, p.thumb_path,
             p.media_url, p.media_path, p.media_type
      from public.posts p
      where p.id = $1::uuid
        and (${SPARKS_POST_SQL})
      limit 1
      `,
      [postId]
    );
    const row = rows[0];
    if (!row) {
      mmPermanentSkip.add(postId);
      return false;
    }

    const thumbUrl = await resolveSparkThumbUrl(row);
    if (!thumbUrl) {
      mmPermanentSkip.add(postId);
      return false;
    }

    const thumb = await thumbToBytes(thumbUrl);
    if (!thumb) {
      mmPermanentSkip.add(postId);
      return false;
    }

    const text = captionText(row.title, row.body);
    const [emb] = await embedMultimodal(
      [
        {
          content: [
            { type: 'text', text },
            { type: 'image_base64', image_base64: thumb.dataUrl },
          ],
        },
      ],
      'document'
    );
    if (!emb || emb.length !== MIND_MM_DIMS) return false;

    const fp = fingerprint(thumbUrl);
    const source = mmSourceForMediaType(row.media_type);
    const kind = mmKindForMediaType(row.media_type);
    await pool.query(
      `
      insert into public.mind_sparks_multimodal_embeddings as e (
        post_id, model_version, dims, embedding, source, thumb_fingerprint, updated_at
      ) values (
        $1::uuid, $2, $3, $4::vector, $5, $6, now()
      )
      on conflict (post_id) do update set
        model_version = excluded.model_version,
        dims = excluded.dims,
        embedding = excluded.embedding,
        source = excluded.source,
        thumb_fingerprint = excluded.thumb_fingerprint,
        updated_at = now()
      `,
      [postId, MIND_MM_MODEL_VERSION, MIND_MM_DIMS, vectorLiteral(emb), source, fp]
    );
    cacheFrameForProgress(postId, row.title, thumb, kind);
    return true;
  } catch (err: any) {
    const msg = String(err?.message ?? err);
    console.warn('[mind-multimodal] upsert failed', postId, msg);
    if (isPermanentMmError(msg)) mmPermanentSkip.add(postId);
    return false;
  }
}

const mmQueue: string[] = [];
const mmQueued = new Set<string>();
let mmPumping = false;

/** Fire-and-forget Sparks multimodal embed (safe from request handlers). */
export function scheduleMultimodalForPost(postId: string | null | undefined): void {
  if (!mindMultimodalEnabled()) return;
  const id = String(postId ?? '').trim();
  if (!id) return;
  if (mmQueued.has(id)) return;
  mmQueued.add(id);
  mmQueue.push(id);
  void pumpMmQueue();
}

async function pumpMmQueue(): Promise<void> {
  if (mmPumping) return;
  mmPumping = true;
  try {
    while (mmQueue.length) {
      const id = mmQueue.shift()!;
      mmQueued.delete(id);
      await upsertMultimodalForPost(id);
      // Images are heavier than text — pace politely.
      await new Promise((r) => setTimeout(r, 700));
    }
  } finally {
    mmPumping = false;
    if (mmQueue.length) void pumpMmQueue();
  }
}

/** Catch-up backfill — interleaves Sparks videos + image posts so both advance. */
export async function backfillMultimodal(opts?: {
  limit?: number;
  offset?: number;
  /** Prefer one lane; default alternates half/half. */
  kind?: 'spark' | 'image' | 'both';
}): Promise<{
  scanned: number;
  upserted: number;
  skipped: number;
  sparks: number;
  images: number;
}> {
  if (!mindMultimodalEnabled()) {
    return { scanned: 0, upserted: 0, skipped: 0, sparks: 0, images: 0 };
  }
  const ok = await ensureMultimodalSchema();
  if (!ok) return { scanned: 0, upserted: 0, skipped: 0, sparks: 0, images: 0 };

  const limit = Math.min(Math.max(opts?.limit ?? 200, 1), 2000);
  const offset = Math.max(opts?.offset ?? 0, 0);
  const kind = opts?.kind ?? 'both';

  const skipList = [...mmPermanentSkip].filter((id) =>
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
  );

  const pendingClause = `
    (${MM_HAS_THUMB_SQL})
    and (
      e.post_id is null
      or e.model_version is distinct from $3
    )
    and (
      $4::uuid[] is null
      or cardinality($4::uuid[]) = 0
      or p.id <> all($4::uuid[])
    )
  `;

  async function pick(laneSql: string, laneLimit: number): Promise<string[]> {
    if (laneLimit <= 0) return [];
    const { rows } = await pool.query<{ id: string }>(
      `
      select p.id::text
      from public.posts p
      left join public.mind_sparks_multimodal_embeddings e on e.post_id = p.id
      where (${laneSql})
        and (${pendingClause})
      order by p.created_at desc nulls last
      offset $1
      limit $2
      `,
      [offset, laneLimit, MIND_MM_MODEL_VERSION, skipList.length ? skipList : null]
    );
    return rows.map((r) => r.id);
  }

  let ids: string[] = [];
  if (kind === 'spark') {
    ids = await pick(SPARKS_VIDEO_SQL, limit);
  } else if (kind === 'image') {
    ids = await pick(IMAGE_POST_SQL, limit);
  } else {
    const half = Math.ceil(limit / 2);
    const other = Math.max(limit - half, 0);
    const [sparkIds, imageIds] = await Promise.all([
      pick(SPARKS_VIDEO_SQL, half),
      pick(IMAGE_POST_SQL, other),
    ]);
    // Interleave so the live gallery shows both kinds.
    const out: string[] = [];
    const max = Math.max(sparkIds.length, imageIds.length);
    for (let i = 0; i < max; i++) {
      if (i < sparkIds.length) out.push(sparkIds[i]!);
      if (i < imageIds.length) out.push(imageIds[i]!);
    }
    ids = out.slice(0, limit);
  }

  let upserted = 0;
  let skipped = 0;
  let sparks = 0;
  let images = 0;
  for (const id of ids) {
    const before = mmPermanentSkip.has(id);
    const okOne = await upsertMultimodalForPost(id);
    if (okOne) {
      upserted += 1;
      // Best-effort kind from skip-free success: re-check via recent.json is heavy;
      // count from DB source on next status. Approximate via post lookup skipped —
      // use a light query only when frame dir writes kind. Count from return path:
      sparks += 0;
    } else {
      skipped += 1;
      void before;
    }
    await new Promise((r) => setTimeout(r, 250));
  }

  // Tally kinds for this batch from recent.json if present.
  try {
    const dir = process.env.MIND_MM_FRAME_DIR?.trim();
    if (dir && existsSync(pathResolve(dir, 'recent.json'))) {
      const recent = JSON.parse(readFileSync(pathResolve(dir, 'recent.json'), 'utf8')) as {
        id: string;
        kind?: string;
      }[];
      const batchSet = new Set(ids);
      for (const r of recent) {
        if (!batchSet.has(r.id)) continue;
        if (r.kind === 'image') images += 1;
        else if (r.kind === 'spark') sparks += 1;
      }
    }
  } catch {
    /* ignore */
  }

  return { scanned: ids.length, upserted, skipped, sparks, images };
}

/** Text-query ANN over Sparks multimodal space (visual + caption). */
export async function multimodalAnnCandidates(opts: {
  queryText: string;
  limit?: number;
  excludeIds?: string[];
}): Promise<string[]> {
  if (!mindMultimodalEnabled()) return [];
  const ok = await ensureMultimodalSchema();
  if (!ok) return [];
  const limit = Math.min(Math.max(opts.limit ?? 32, 1), 64);
  const q = opts.queryText.trim().slice(0, 500);
  if (!q) return [];

  try {
    const [emb] = await embedMultimodal(
      [{ content: [{ type: 'text', text: q }] }],
      'query'
    );
    if (!emb || emb.length !== MIND_MM_DIMS) return [];
    const exclude = (opts.excludeIds ?? []).filter((id) =>
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
    );
    const { rows } = await pool.query<{ post_id: string }>(
      `
      select e.post_id::text
      from public.mind_sparks_multimodal_embeddings e
      join public.posts p on p.id = e.post_id
      where ($2::uuid[] is null or cardinality($2::uuid[]) = 0 or e.post_id <> all($2::uuid[]))
      order by e.embedding <=> $1::vector
      limit $3
      `,
      [vectorLiteral(emb), exclude.length ? exclude : null, limit]
    );
    return rows.map((r) => r.post_id);
  } catch (err: any) {
    console.warn('[mind-multimodal] ann failed', err?.message ?? err);
    return [];
  }
}

export type MultimodalStatus = {
  enabled: boolean;
  configured: boolean;
  model: string;
  modelVersion: string;
  dims: number;
  rows: number;
  source: string;
  /** Total Sparks-video + image posts with a usable thumb/still. */
  sparksEligible: number;
  videoEligible: number;
  imageEligible: number;
  videoRows: number;
  imageRows: number;
};

export async function getMultimodalStatus(): Promise<MultimodalStatus> {
  const base: MultimodalStatus = {
    enabled: mindMultimodalEnabled(),
    configured: !!voyageKey(),
    model: MIND_MM_MODEL,
    modelVersion: MIND_MM_MODEL_VERSION,
    dims: MIND_MM_DIMS,
    rows: 0,
    source: 'sparks_thumb+image',
    sparksEligible: 0,
    videoEligible: 0,
    imageEligible: 0,
    videoRows: 0,
    imageRows: 0,
  };
  try {
    await ensureMultimodalSchema();
    const [emb, videoElig, imageElig, bySource] = await Promise.all([
      pool.query<{ n: string }>(
        `select count(*)::text as n from public.mind_sparks_multimodal_embeddings`
      ),
      pool.query<{ n: string }>(
        `
        select count(*)::text as n
        from public.posts p
        where (${SPARKS_VIDEO_SQL}) and (${MM_HAS_THUMB_SQL})
        `
      ),
      pool.query<{ n: string }>(
        `
        select count(*)::text as n
        from public.posts p
        where (${IMAGE_POST_SQL}) and (${MM_HAS_THUMB_SQL})
        `
      ),
      pool.query<{ source: string; n: string }>(
        `
        select coalesce(source, '') as source, count(*)::text as n
        from public.mind_sparks_multimodal_embeddings
        group by 1
        `
      ),
    ]);
    base.rows = Number(emb.rows[0]?.n) || 0;
    base.videoEligible = Number(videoElig.rows[0]?.n) || 0;
    base.imageEligible = Number(imageElig.rows[0]?.n) || 0;
    base.sparksEligible = base.videoEligible + base.imageEligible;
    for (const r of bySource.rows) {
      if (r.source === MIND_MM_SOURCE_IMAGE) base.imageRows = Number(r.n) || 0;
      else base.videoRows += Number(r.n) || 0;
    }
  } catch (err: any) {
    console.warn('[mind-multimodal] status failed', err?.message ?? err);
  }
  return base;
}
