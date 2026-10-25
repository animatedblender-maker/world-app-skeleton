/**
 * MIND Phase 2b — Content embeddings (Voyage voyage-4-lite + pgvector).
 *
 * Indexes title+body text for Public posts. Soft ANN lane for Home/Hubs.
 * Missing embedding = UNKNOWN (never demote). Masquerade stays isolated.
 */
import { createHash } from 'node:crypto';
import { pool } from '../db.js';

export const MIND_EMBED_MODEL = 'voyage-4-lite';
export const MIND_EMBED_MODEL_VERSION = 'voyage:voyage-4-lite';
export const MIND_EMBED_DIMS = 1024;

export function mindEmbeddingsEnabled(): boolean {
  const raw = process.env.MIND_EMBEDDINGS_ENABLED?.trim().toLowerCase();
  if (raw === '0' || raw === 'false' || raw === 'off' || raw === 'no') return false;
  return !!process.env.VOYAGE_API_KEY?.trim();
}

export function voyageConfigured(): boolean {
  return !!process.env.VOYAGE_API_KEY?.trim();
}

function voyageKey(): string | null {
  return process.env.VOYAGE_API_KEY?.trim() || null;
}

function fingerprint(text: string): string {
  const n = text.toLowerCase().replace(/\s+/g, ' ').trim();
  return createHash('sha256').update(n).digest('hex').slice(0, 32);
}

function passageText(title: string | null, body: string | null): string {
  const t = [title, body]
    .map((s) => String(s ?? '').trim())
    .filter(Boolean)
    .join('\n')
    .slice(0, 8000);
  return t || 'matterya post';
}

let schemaReady = false;

export async function ensureEmbeddingSchema(): Promise<boolean> {
  if (schemaReady) return true;
  try {
    await pool.query(`create extension if not exists vector`);
    await pool.query(`
      create table if not exists public.mind_content_embeddings (
        post_id uuid primary key references public.posts (id) on delete cascade,
        model_version text not null,
        dims int not null,
        embedding vector(${MIND_EMBED_DIMS}) not null,
        source text not null default 'title_body',
        text_fingerprint text,
        updated_at timestamptz not null default now()
      )
    `);
    await pool.query(`
      create index if not exists mind_content_embeddings_hnsw
        on public.mind_content_embeddings
        using hnsw (embedding vector_cosine_ops)
    `);
    schemaReady = true;
    return true;
  } catch (err: any) {
    console.warn('[mind-embeddings] ensure schema failed', err?.message ?? err);
    return false;
  }
}

type VoyageEmbedResponse = {
  data: { embedding: number[]; index: number }[];
  model?: string;
  usage?: { total_tokens?: number };
};

export async function embedTexts(
  texts: string[],
  inputType: 'document' | 'query' = 'document'
): Promise<number[][]> {
  const key = voyageKey();
  if (!key) throw new Error('VOYAGE_API_KEY missing');
  if (texts.length === 0) return [];

  const res = await fetch('https://api.voyageai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: MIND_EMBED_MODEL,
      input: texts,
      input_type: inputType,
    }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`voyage embed ${res.status}: ${body.slice(0, 240)}`);
  }
  const json = (await res.json()) as VoyageEmbedResponse;
  const sorted = [...(json.data ?? [])].sort((a, b) => a.index - b.index);
  return sorted.map((d) => d.embedding);
}

function vectorLiteral(v: number[]): string {
  return `[${v.join(',')}]`;
}

export async function upsertEmbeddingForPost(postId: string): Promise<boolean> {
  if (!mindEmbeddingsEnabled() || !postId) return false;
  const ok = await ensureEmbeddingSchema();
  if (!ok) return false;

  try {
    const { rows } = await pool.query<{ title: string | null; body: string | null }>(
      `select title, body from public.posts where id = $1::uuid limit 1`,
      [postId]
    );
    const row = rows[0];
    if (!row) return false;
    const text = passageText(row.title, row.body);
    const fp = fingerprint(text);
    const [emb] = await embedTexts([text], 'document');
    if (!emb || emb.length !== MIND_EMBED_DIMS) return false;

    await pool.query(
      `
      insert into public.mind_content_embeddings as e (
        post_id, model_version, dims, embedding, source, text_fingerprint, updated_at
      ) values (
        $1::uuid, $2, $3, $4::vector, 'title_body', $5, now()
      )
      on conflict (post_id) do update set
        model_version = excluded.model_version,
        dims = excluded.dims,
        embedding = excluded.embedding,
        source = excluded.source,
        text_fingerprint = excluded.text_fingerprint,
        updated_at = now()
      `,
      [postId, MIND_EMBED_MODEL_VERSION, MIND_EMBED_DIMS, vectorLiteral(emb), fp]
    );
    return true;
  } catch (err: any) {
    console.warn('[mind-embeddings] upsert failed', postId, err?.message ?? err);
    return false;
  }
}

/** Batch upsert title/body embeddings. Disk-IO friendly pauses between Voyage calls. */
export async function backfillEmbeddings(opts?: {
  limit?: number;
  batchSize?: number;
  offset?: number;
}): Promise<{ scanned: number; upserted: number; tokensApprox: number }> {
  if (!mindEmbeddingsEnabled()) return { scanned: 0, upserted: 0, tokensApprox: 0 };
  const ok = await ensureEmbeddingSchema();
  if (!ok) return { scanned: 0, upserted: 0, tokensApprox: 0 };

  const limit = Math.min(Math.max(opts?.limit ?? 500, 1), 5000);
  const batchSize = Math.min(Math.max(opts?.batchSize ?? 64, 1), 128);
  const offset = Math.max(opts?.offset ?? 0, 0);

  const { rows } = await pool.query<{ id: string; title: string | null; body: string | null }>(
    `
    select p.id::text, p.title, p.body
    from public.posts p
    left join public.mind_content_embeddings e on e.post_id = p.id
    where e.post_id is null
       or e.model_version is distinct from $3
    order by p.created_at desc nulls last
    offset $1
    limit $2
    `,
    [offset, limit, MIND_EMBED_MODEL_VERSION]
  );

  let upserted = 0;
  let tokensApprox = 0;
  for (let i = 0; i < rows.length; i += batchSize) {
    const chunk = rows.slice(i, i + batchSize);
    const texts = chunk.map((r) => passageText(r.title, r.body));
    tokensApprox += texts.reduce((a, t) => a + Math.ceil(t.length / 4), 0);
    try {
      const embs = await embedTexts(texts, 'document');
      for (let j = 0; j < chunk.length; j++) {
        const emb = embs[j];
        if (!emb || emb.length !== MIND_EMBED_DIMS) continue;
        const fp = fingerprint(texts[j]!);
        await pool.query(
          `
          insert into public.mind_content_embeddings as e (
            post_id, model_version, dims, embedding, source, text_fingerprint, updated_at
          ) values (
            $1::uuid, $2, $3, $4::vector, 'title_body', $5, now()
          )
          on conflict (post_id) do update set
            model_version = excluded.model_version,
            dims = excluded.dims,
            embedding = excluded.embedding,
            source = excluded.source,
            text_fingerprint = excluded.text_fingerprint,
            updated_at = now()
          `,
          [chunk[j]!.id, MIND_EMBED_MODEL_VERSION, MIND_EMBED_DIMS, vectorLiteral(emb), fp]
        );
        upserted += 1;
      }
    } catch (err: any) {
      console.warn('[mind-embeddings] batch failed', err?.message ?? err);
    }
    await new Promise((r) => setTimeout(r, 200));
  }

  return { scanned: rows.length, upserted, tokensApprox };
}

/** ANN nearest neighbors by cosine distance (Public posts only). */
export async function annCandidates(opts: {
  queryText: string;
  limit?: number;
  excludeIds?: string[];
}): Promise<string[]> {
  if (!mindEmbeddingsEnabled()) return [];
  const ok = await ensureEmbeddingSchema();
  if (!ok) return [];
  const limit = Math.min(Math.max(opts.limit ?? 24, 1), 64);
  const q = opts.queryText.trim().slice(0, 2000);
  if (!q) return [];

  try {
    const [emb] = await embedTexts([q], 'query');
    if (!emb || emb.length !== MIND_EMBED_DIMS) return [];
    const exclude = (opts.excludeIds ?? []).filter((id) =>
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
    );
    const { rows } = await pool.query<{ post_id: string }>(
      `
      select e.post_id::text
      from public.mind_content_embeddings e
      join public.posts p on p.id = e.post_id
      where ($2::uuid[] is null or cardinality($2::uuid[]) = 0 or e.post_id <> all($2::uuid[]))
      order by e.embedding <=> $1::vector
      limit $3
      `,
      [vectorLiteral(emb), exclude.length ? exclude : null, limit]
    );
    return rows.map((r) => r.post_id);
  } catch (err: any) {
    console.warn('[mind-embeddings] ann failed', err?.message ?? err);
    return [];
  }
}

export type EmbeddingsStatus = {
  enabled: boolean;
  configured: boolean;
  model: string;
  modelVersion: string;
  dims: number;
  rows: number;
  source: string;
};

export async function getEmbeddingsStatus(): Promise<EmbeddingsStatus> {
  const base: EmbeddingsStatus = {
    enabled: mindEmbeddingsEnabled(),
    configured: voyageConfigured(),
    model: MIND_EMBED_MODEL,
    modelVersion: MIND_EMBED_MODEL_VERSION,
    dims: MIND_EMBED_DIMS,
    rows: 0,
    source: 'title_body',
  };
  try {
    await ensureEmbeddingSchema();
    const { rows } = await pool.query<{ n: string }>(
      `select count(*)::text as n from public.mind_content_embeddings`
    );
    base.rows = Number(rows[0]?.n) || 0;
  } catch (err: any) {
    console.warn('[mind-embeddings] status failed', err?.message ?? err);
  }
  return base;
}
