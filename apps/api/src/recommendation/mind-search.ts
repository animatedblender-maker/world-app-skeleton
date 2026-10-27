/**
 * MIND-020 — Hybrid search (keyword + Voyage ANN + Voyage rerank).
 * Expands intent (synonyms) so "dancing" can match choreo / valle / bailando
 * without requiring the literal word. Public posts only.
 */
import { pool } from '../db.js';
import { annCandidates, mindEmbeddingsEnabled } from './mind-embeddings.js';
import {
  MIND_RERANK_CANDIDATE_CAP,
  mindRerankEnabled,
  rerankPassage,
  voyageRerank,
} from './mind-rerank.js';

export function mindHybridSearchEnabled(): boolean {
  const v = process.env.MIND_HYBRID_SEARCH_ENABLED;
  if (v == null || v === '') return true;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

export type HybridSearchHit = {
  id: string;
  score: number;
  sources: string[];
  title: string | null;
  authorId: string | null;
};

export type HybridSearchResult = {
  query: string;
  items: HybridSearchHit[];
  lexicalCount: number;
  semanticCount: number;
  hybrid: boolean;
  /** True when Voyage rerank reordered the candidate head. */
  reranked: boolean;
  rerankModel: string | null;
  /** Synonyms / related terms used for retrieval. */
  expandedTerms: string[];
  latencyMs: number;
};

/**
 * Intent → related terms. Matched when the query equals or contains the key
 * as a whole word. Keeps Search contextual instead of literal-only.
 */
const INTENT_SYNONYMS: Record<string, string[]> = {
  dancing: [
    'dance',
    'dancer',
    'choreography',
    'choreo',
    'ballet',
    'salsa',
    'bailando',
    'valle',
    'groove',
    'ballroom',
    'hip hop',
    'belly dance',
    'tallava',
  ],
  dance: [
    'dancing',
    'dancer',
    'choreography',
    'choreo',
    'ballet',
    'salsa',
    'bailando',
    'valle',
    'groove',
    'ballroom',
  ],
  cooking: ['cook', 'recipe', 'chef', 'kitchen', 'baking', 'food', 'cuisine'],
  food: ['cooking', 'recipe', 'chef', 'restaurant', 'street food', 'cuisine'],
  travel: ['trip', 'vacation', 'tourism', 'journey', 'backpack', 'explore'],
  comedy: ['funny', 'humor', 'humour', 'sketch', 'stand up', 'joke', 'laugh'],
  music: ['song', 'singer', 'concert', 'band', 'rap', 'melody', 'instrumental'],
  sports: ['football', 'soccer', 'basketball', 'athletic', 'workout', 'fitness'],
  fitness: ['workout', 'gym', 'training', 'exercise', 'sports'],
  cats: ['cat', 'kitten', 'feline', 'meow'],
  dogs: ['dog', 'puppy', 'canine'],
};

export type ExpandedQuery = {
  primary: string;
  terms: string[];
  /** Richer string for Voyage ANN + rerank (context, not just one word). */
  semanticQuery: string;
};

export function expandSearchQuery(raw: string): ExpandedQuery {
  const primary = String(raw ?? '')
    .trim()
    .replace(/^@+/, '')
    .slice(0, 200);
  if (!primary) return { primary: '', terms: [], semanticQuery: '' };

  const lower = primary.toLowerCase();
  const terms = new Set<string>([primary]);
  for (const [key, syns] of Object.entries(INTENT_SYNONYMS)) {
    const re = new RegExp(`\\b${key.replace(/\s+/g, '\\s+')}\\b`, 'i');
    if (re.test(lower) || lower === key) {
      terms.add(key);
      for (const s of syns) terms.add(s);
    }
  }
  // Also split multi-word queries into tokens (≥3 chars).
  for (const tok of lower.split(/[^a-z0-9]+/).filter((t) => t.length >= 3)) {
    terms.add(tok);
  }

  const list = [...terms].slice(0, 16);
  const semanticQuery = [primary, ...list.filter((t) => t.toLowerCase() !== lower)]
    .slice(0, 12)
    .join(' ');

  return { primary, terms: list, semanticQuery };
}

function escapeLike(s: string): string {
  return s.replace(/[%_\\]/g, '\\$&');
}

async function lexicalSearch(
  terms: string[],
  limit: number,
  viewerId: string | null
): Promise<HybridSearchHit[]> {
  const cleaned = terms
    .map((t) => t.trim().toLowerCase())
    .filter((t) => t.length >= 2)
    .slice(0, 12);
  if (cleaned.length === 0) return [];
  const primary = cleaned[0]!;
  const max = Math.max(1, Math.min(500, limit));

  // Build OR across synonym terms for title/body/username.
  const likeParams: string[] = [];
  const orParts: string[] = [];
  for (let i = 0; i < cleaned.length; i++) {
    const term = cleaned[i]!;
    likeParams.push(`%${escapeLike(term)}%`);
    const idx = i + 1;
    orParts.push(
      `(lower(coalesce(p.title, '')) like $${idx} escape '\\'
        or lower(coalesce(pr.username, '')) like $${idx} escape '\\'
        or lower(coalesce(pr.display_name, '')) like $${idx} escape '\\'
        or lower(left(coalesce(p.body, ''), 240)) like $${idx} escape '\\')`
    );
  }
  const viewerIdx = likeParams.length + 1;
  const primaryExactIdx = viewerIdx + 1;
  const primaryPrefixIdx = viewerIdx + 2;
  const limitIdx = viewerIdx + 3;

  try {
    const { rows } = await pool.query<{
      id: string;
      title: string | null;
      author_id: string | null;
      rank_bucket: number;
    }>(
      `
      select
        p.id::text,
        p.title,
        p.author_id::text,
        case
          when lower(coalesce(pr.username, '')) = $${primaryExactIdx} then 0
          when lower(coalesce(p.title, '')) like $${primaryPrefixIdx} escape '\\' then 1
          when lower(coalesce(pr.username, '')) like $${primaryPrefixIdx} escape '\\' then 2
          else 3
        end as rank_bucket
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      where coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted', 'sensitive')
        and coalesce(p.media_type, '') is distinct from 'moment'
        and (
          p.visibility = 'public'
          or ($${viewerIdx}::uuid is not null and p.author_id = $${viewerIdx}::uuid)
        )
        and (${orParts.join(' or ')})
      order by rank_bucket asc, p.created_at desc
      limit $${limitIdx}
      `,
      [
        ...likeParams,
        viewerId,
        primary,
        `${escapeLike(primary)}%`,
        max,
      ]
    );
    return rows.map((r, i) => ({
      id: r.id,
      title: r.title,
      authorId: r.author_id,
      score: 10 - r.rank_bucket - i * 0.01,
      sources: ['lexical'],
    }));
  } catch (err: any) {
    console.warn('[mind-search] lexical', err?.message ?? err);
    return [];
  }
}

/** Reciprocal rank fusion — semantic slightly heavier so context beats pure substring. */
function rrfMerge(
  lexical: HybridSearchHit[],
  semanticIds: string[],
  k = 60
): HybridSearchHit[] {
  const scores = new Map<string, { score: number; hit: HybridSearchHit }>();
  lexical.forEach((h, i) => {
    const s = 1 / (k + i + 1);
    scores.set(h.id, {
      score: s * 1.0,
      hit: { ...h, sources: ['lexical'] },
    });
  });
  semanticIds.forEach((id, i) => {
    const s = 1 / (k + i + 1);
    const prev = scores.get(id);
    if (prev) {
      prev.score += s * 1.35;
      if (!prev.hit.sources.includes('semantic')) prev.hit.sources.push('semantic');
    } else {
      scores.set(id, {
        score: s * 1.35,
        hit: {
          id,
          score: 0,
          sources: ['semantic'],
          title: null,
          authorId: null,
        },
      });
    }
  });
  return [...scores.values()]
    .sort((a, b) => b.score - a.score)
    .map((x) => ({ ...x.hit, score: Math.round(x.score * 1000) / 1000 }));
}

/**
 * Keep contextual hits that omit the literal primary word — otherwise rerank
 * collapses everything back to titles containing "dancing".
 */
function interleaveNonLiteral(
  hits: HybridSearchHit[],
  primary: string,
  pageSize: number
): HybridSearchHit[] {
  const stem = primary.trim().toLowerCase();
  if (stem.length < 3 || hits.length < 4) return hits;
  const re = new RegExp(stem.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
  const literal: HybridSearchHit[] = [];
  const contextual: HybridSearchHit[] = [];
  for (const h of hits) {
    const t = h.title || '';
    if (!t.trim()) {
      // Empty titles are useless in UI — park at end.
      continue;
    }
    if (re.test(t)) literal.push(h);
    else contextual.push(h);
  }
  if (contextual.length === 0) return hits.filter((h) => (h.title || '').trim());

  const out: HybridSearchHit[] = [];
  const seen = new Set<string>();
  const wantContextual = Math.max(2, Math.ceil(pageSize * 0.35));
  let ci = 0;
  let li = 0;
  // Lead with a few contextual hits, then weave.
  while (out.length < hits.length && (ci < contextual.length || li < literal.length)) {
    const preferContextual =
      out.filter((h) => !re.test(h.title || '')).length < wantContextual;
    if (preferContextual && ci < contextual.length) {
      const h = contextual[ci++]!;
      if (seen.add(h.id)) out.push(h);
      continue;
    }
    if (li < literal.length) {
      const h = literal[li++]!;
      if (seen.add(h.id)) out.push(h);
      continue;
    }
    if (ci < contextual.length) {
      const h = contextual[ci++]!;
      if (seen.add(h.id)) out.push(h);
    }
  }
  return out;
}

export async function hybridSearch(opts: {
  query: string;
  limit?: number;
  offset?: number;
  viewerId?: string | null;
}): Promise<HybridSearchResult> {
  const started = Date.now();
  const expanded = expandSearchQuery(opts.query ?? '');
  const query = expanded.primary;
  const limit = Math.min(Math.max(opts.limit ?? 20, 1), 100);
  const offset = Math.max(0, Math.min(400, opts.offset ?? 0));
  const viewerId = opts.viewerId ?? null;
  const fetchCount = Math.min(500, offset + limit);

  if (!query) {
    return {
      query,
      items: [],
      lexicalCount: 0,
      semanticCount: 0,
      hybrid: false,
      reranked: false,
      rerankModel: null,
      expandedTerms: [],
      latencyMs: Date.now() - started,
    };
  }

  const useHybrid = mindHybridSearchEnabled() && mindEmbeddingsEnabled();
  const lexical = await lexicalSearch(expanded.terms, fetchCount, viewerId);
  let semanticIds: string[] = [];
  if (useHybrid) {
    try {
      semanticIds = await annCandidates({
        queryText: expanded.semanticQuery || query,
        limit: Math.min(Math.max(fetchCount * 2, 64), 120),
        excludeIds: [],
      });
    } catch {
      semanticIds = [];
    }
  }

  let ranked =
    useHybrid && semanticIds.length
      ? rrfMerge(lexical, semanticIds)
      : lexical;

  // Fill title/body for the rerank head (and page) before Voyage.
  const headN = Math.min(MIND_RERANK_CANDIDATE_CAP, ranked.length);
  const needMeta = ranked.slice(0, Math.max(headN, offset + limit));
  await fillHitMeta(needMeta);

  let reranked = false;
  let rerankModel: string | null = null;
  if (mindRerankEnabled() && ranked.length >= 2) {
    const head = ranked.slice(0, headN);
    const docs = head.map((h) =>
      rerankPassage(h.title, (h as HitWithBody).body)
    );
    // Rerank with expanded semantic query so synonyms aren't punished.
    const result = await voyageRerank({
      query: expanded.semanticQuery || query,
      documents: docs,
      topK: head.length,
    });
    if (result) {
      const reordered = result.order
        .map((i) => head[i])
        .filter((h): h is HybridSearchHit => !!h);
      const seen = new Set(reordered.map((h) => h.id));
      for (const h of head) {
        if (!seen.has(h.id)) reordered.push(h);
      }
      for (const h of reordered) {
        if (!h.sources.includes('rerank')) h.sources = [...h.sources, 'rerank'];
      }
      ranked = [...reordered, ...ranked.slice(headN)];
      reranked = true;
      rerankModel = result.model;
    }
  }

  ranked = interleaveNonLiteral(ranked, query, limit);
  const items = ranked.slice(offset, offset + limit);

  return {
    query,
    items,
    lexicalCount: lexical.length,
    semanticCount: semanticIds.length,
    hybrid: useHybrid && semanticIds.length > 0,
    reranked,
    rerankModel,
    expandedTerms: expanded.terms,
    latencyMs: Date.now() - started,
  };
}

type HitWithBody = HybridSearchHit & { body?: string | null };

async function fillHitMeta(hits: HybridSearchHit[]): Promise<void> {
  if (hits.length === 0) return;
  const ids = [...new Set(hits.map((i) => i.id))];
  try {
    const { rows } = await pool.query<{
      id: string;
      title: string | null;
      body: string | null;
      author_id: string | null;
    }>(
      `select id::text, title, left(coalesce(body, ''), 1200) as body, author_id::text
       from public.posts where id = any($1::uuid[])`,
      [ids]
    );
    const meta = new Map(rows.map((r) => [r.id, r]));
    for (const it of hits) {
      const m = meta.get(it.id);
      if (!m) continue;
      if (!it.title) it.title = m.title;
      if (!it.authorId) it.authorId = m.author_id;
      (it as HitWithBody).body = m.body;
    }
  } catch {
    /* ignore — rerank will use title-only / fallback passage */
  }
}
