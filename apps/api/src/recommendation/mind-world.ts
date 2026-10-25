/**
 * MIND-022 — World / country feed thin slice (geoprivacy: country code only).
 */
import { pool } from '../db.js';
import { rankCandidates } from './rank.service.js';

export type WorldCountryItem = {
  id: string;
  title: string | null;
  authorId: string | null;
  countryCode: string | null;
  score?: number;
  sources?: string[];
};

export async function worldCountryFeed(opts: {
  countryCode: string;
  limit?: number;
  viewerId?: string | null;
  sessionId?: string | null;
}): Promise<{
  countryCode: string;
  items: WorldCountryItem[];
  ranked: boolean;
  latencyMs: number;
}> {
  const started = Date.now();
  const code = String(opts.countryCode || '')
    .trim()
    .toUpperCase()
    .slice(0, 8);
  const limit = Math.min(Math.max(opts.limit ?? 24, 1), 48);
  if (!code || code.length < 2) {
    return {
      countryCode: code,
      items: [],
      ranked: false,
      latencyMs: Date.now() - started,
    };
  }

  const { rows } = await pool.query<{
    id: string;
    title: string | null;
    author_id: string | null;
    country_code: string | null;
  }>(
    `
    select p.id::text, p.title, p.author_id::text, p.country_code
    from public.posts p
    where upper(coalesce(p.country_code, '')) = $1
      and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted', 'sensitive')
      and coalesce(p.visibility, 'public') = 'public'
      and coalesce(p.media_type, '') is distinct from 'moment'
    order by coalesce(p.updated_at, p.created_at) desc
    limit $2
    `,
    [code, Math.min(limit * 3, 96)]
  );

  const base: WorldCountryItem[] = rows.map((r) => ({
    id: r.id,
    title: r.title,
    authorId: r.author_id,
    countryCode: r.country_code,
  }));

  if (!opts.viewerId || base.length === 0) {
    return {
      countryCode: code,
      items: base.slice(0, limit),
      ranked: false,
      latencyMs: Date.now() - started,
    };
  }

  try {
    const ranked = await rankCandidates({
      entityId: opts.viewerId,
      surface: 'explore',
      candidateIds: base.map((b) => b.id),
      sessionId: opts.sessionId,
      limit,
    });
    const byId = new Map(base.map((b) => [b.id, b]));
    const items: WorldCountryItem[] = ranked.items.map((r) => ({
      ...(byId.get(r.id) ?? {
        id: r.id,
        title: null,
        authorId: null,
        countryCode: code,
      }),
      score: r.score,
      sources: r.sources,
    }));
    return {
      countryCode: code,
      items,
      ranked: true,
      latencyMs: Date.now() - started,
    };
  } catch {
    return {
      countryCode: code,
      items: base.slice(0, limit),
      ranked: false,
      latencyMs: Date.now() - started,
    };
  }
}
