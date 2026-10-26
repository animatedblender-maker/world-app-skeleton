/**
 * Voyage rerank for Search / Explore hybrid results.
 * Retrieve (lexical + ANN) → rerank top-K docs → fail-open on error/timeout.
 */
import { voyageConfigured } from './mind-embeddings.js';

export const MIND_RERANK_MODEL =
  process.env.MIND_RERANK_MODEL?.trim() || 'rerank-2.5-lite';

/** Max candidates sent to Voyage (latency + token budget). */
export const MIND_RERANK_CANDIDATE_CAP = 64;

const RERANK_TIMEOUT_MS = Math.min(
  2000,
  Math.max(200, Number(process.env.MIND_RERANK_TIMEOUT_MS) || 450)
);

export function mindRerankEnabled(): boolean {
  const raw = process.env.MIND_RERANK_ENABLED?.trim().toLowerCase();
  if (raw === '0' || raw === 'false' || raw === 'off' || raw === 'no') return false;
  // Default ON when Voyage key is present (same gate as embeddings).
  if (raw === '1' || raw === 'true' || raw === 'on' || raw === 'yes') return true;
  return voyageConfigured();
}

export type RerankStatus = {
  enabled: boolean;
  configured: boolean;
  model: string;
  timeoutMs: number;
  candidateCap: number;
};

export function getRerankStatus(): RerankStatus {
  return {
    enabled: mindRerankEnabled(),
    configured: voyageConfigured(),
    model: MIND_RERANK_MODEL,
    timeoutMs: RERANK_TIMEOUT_MS,
    candidateCap: MIND_RERANK_CANDIDATE_CAP,
  };
}

type VoyageRerankResponse = {
  data?: { index: number; relevance_score: number }[];
  model?: string;
  usage?: { total_tokens?: number };
};

function voyageKey(): string | null {
  return process.env.VOYAGE_API_KEY?.trim() || null;
}

/**
 * Rerank documents for a query. Returns indices into `documents` sorted by
 * descending relevance, or `null` when disabled / failed (caller keeps prior order).
 */
export async function voyageRerank(opts: {
  query: string;
  documents: string[];
  topK?: number;
}): Promise<{ order: number[]; model: string; tokens: number } | null> {
  if (!mindRerankEnabled()) return null;
  const key = voyageKey();
  if (!key) return null;
  const query = String(opts.query ?? '').trim().slice(0, 2000);
  const documents = opts.documents
    .map((d) => String(d ?? '').trim().slice(0, 4000))
    .filter(Boolean);
  if (!query || documents.length < 2) return null;

  const topK = Math.min(
    Math.max(1, opts.topK ?? documents.length),
    documents.length,
    MIND_RERANK_CANDIDATE_CAP
  );

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), RERANK_TIMEOUT_MS);
  try {
    const res = await fetch('https://api.voyageai.com/v1/rerank', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MIND_RERANK_MODEL,
        query,
        documents: documents.slice(0, MIND_RERANK_CANDIDATE_CAP),
        top_k: topK,
        return_documents: false,
        truncation: true,
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      console.warn(
        `[mind-rerank] voyage ${res.status}: ${body.slice(0, 180)}`
      );
      return null;
    }
    const json = (await res.json()) as VoyageRerankResponse;
    const rows = Array.isArray(json.data) ? json.data : [];
    const order = rows
      .filter((r) => Number.isFinite(r.index) && r.index >= 0 && r.index < documents.length)
      .sort((a, b) => (b.relevance_score ?? 0) - (a.relevance_score ?? 0))
      .map((r) => r.index);
    if (order.length === 0) return null;
    // Append any missing indices so we never drop candidates.
    const seen = new Set(order);
    for (let i = 0; i < documents.length; i++) {
      if (!seen.has(i)) order.push(i);
    }
    return {
      order,
      model: json.model || MIND_RERANK_MODEL,
      tokens: Number(json.usage?.total_tokens) || 0,
    };
  } catch (err: any) {
    if (err?.name === 'AbortError') {
      console.warn(`[mind-rerank] timeout ${RERANK_TIMEOUT_MS}ms`);
    } else {
      console.warn('[mind-rerank]', err?.message ?? err);
    }
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Build a short passage for rerank from title/body. */
export function rerankPassage(
  title: string | null | undefined,
  body: string | null | undefined
): string {
  const t = [title, body]
    .map((s) => String(s ?? '').trim())
    .filter(Boolean)
    .join('\n')
    .slice(0, 1200);
  return t || 'matterya post';
}
