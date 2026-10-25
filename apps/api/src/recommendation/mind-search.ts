/**
 * MIND-020 — Hybrid search (keyword + Voyage ANN).
 * Public posts only. Masquerade stays on its own keyword path.
 */
import { pool } from '../db.js';
import { annCandidates, mindEmbeddingsEnabled } from './mind-embeddings.js';

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
  latencyMs: number;
};

async function lexicalSearch(
  query: string,
  limit: number,
  viewerId: string | null
): Promise<HybridSearchHit[]> {
  const term = String(query ?? '').trim().replace(/^@+/, '');
  if (!term) return [];
  const q = term.toLowerCase();
  const escaped = q.replace(/[%_\\]/g, '\\$&');
  const prefix = `${escaped}%`;
  const contains = `%${escaped}%`;
  const max = Math.max(1, Math.min(40, limit));

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
          when lower(coalesce(pr.username, '')) = $3 then 0
          when lower(coalesce(p.title, '')) like $2 escape '\\' then 1
          when lower(coalesce(pr.username, '')) like $2 escape '\\' then 2
          else 3
        end as rank_bucket
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      where coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted', 'sensitive')
        and coalesce(p.media_type, '') is distinct from 'moment'
        and (
          p.visibility = 'public'
          or ($4::uuid is not null and p.author_id = $4::uuid)
        )
        and (
          lower(coalesce(pr.username, '')) like $2 escape '\\'
          or lower(coalesce(pr.display_name, '')) like $2 escape '\\'
          or lower(coalesce(p.title, '')) like $2 escape '\\'
          or ($5::int >= 3 and (
            lower(coalesce(p.title, '')) like $1 escape '\\'
            or lower(coalesce(pr.username, '')) like $1 escape '\\'
            or lower(coalesce(pr.display_name, '')) like $1 escape '\\'
            or lower(left(coalesce(p.body, ''), 240)) like $1 escape '\\'
          ))
        )
      order by rank_bucket asc, p.created_at desc
      limit $6
      `,
      [contains, prefix, q, viewerId, q.length, max]
    );
    return rows.map((r, i) => ({
      id: r.id,
      title: r.title,
      authorId: r.author_id,
      score: 10 - r.rank_bucket - i * 0.01,
      sources: ['lexical'],
    }));
  } catch {
    return [];
  }
}

/** Reciprocal rank fusion merge. */
function rrfMerge(
  lexical: HybridSearchHit[],
  semanticIds: string[],
  k = 60
): HybridSearchHit[] {
  const scores = new Map<string, { score: number; hit: HybridSearchHit }>();
  lexical.forEach((h, i) => {
    const s = 1 / (k + i + 1);
    scores.set(h.id, {
      score: s * 1.15,
      hit: { ...h, sources: ['lexical'] },
    });
  });
  semanticIds.forEach((id, i) => {
    const s = 1 / (k + i + 1);
    const prev = scores.get(id);
    if (prev) {
      prev.score += s;
      if (!prev.hit.sources.includes('semantic')) prev.hit.sources.push('semantic');
    } else {
      scores.set(id, {
        score: s,
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

export async function hybridSearch(opts: {
  query: string;
  limit?: number;
  viewerId?: string | null;
}): Promise<HybridSearchResult> {
  const started = Date.now();
  const query = String(opts.query ?? '').trim().slice(0, 200);
  const limit = Math.min(Math.max(opts.limit ?? 20, 1), 40);
  const viewerId = opts.viewerId ?? null;

  if (!query) {
    return {
      query,
      items: [],
      lexicalCount: 0,
      semanticCount: 0,
      hybrid: false,
      latencyMs: Date.now() - started,
    };
  }

  const useHybrid = mindHybridSearchEnabled() && mindEmbeddingsEnabled();
  const lexical = await lexicalSearch(query, limit, viewerId);
  let semanticIds: string[] = [];
  if (useHybrid) {
    try {
      semanticIds = await annCandidates({
        queryText: query,
        limit: Math.min(limit * 2, 48),
        excludeIds: [],
      });
    } catch {
      semanticIds = [];
    }
  }

  const items = useHybrid && semanticIds.length
    ? rrfMerge(lexical, semanticIds).slice(0, limit)
    : lexical.slice(0, limit);

  // Fill title/author for semantic-only hits
  const missing = items.filter((i) => !i.title).map((i) => i.id);
  if (missing.length) {
    try {
      const { rows } = await pool.query<{
        id: string;
        title: string | null;
        author_id: string | null;
      }>(
        `select id::text, title, author_id::text from public.posts where id = any($1::uuid[])`,
        [missing]
      );
      const meta = new Map(rows.map((r) => [r.id, r]));
      for (const it of items) {
        const m = meta.get(it.id);
        if (m) {
          it.title = m.title;
          it.authorId = m.author_id;
        }
      }
    } catch {
      /* ignore */
    }
  }

  return {
    query,
    items,
    lexicalCount: lexical.length,
    semanticCount: semanticIds.length,
    hybrid: useHybrid && semanticIds.length > 0,
    latencyMs: Date.now() - started,
  };
}
