/**
 * MIND-018 — Creator opportunity / under-exposure boost.
 * Soft-boost eligible creators with low recent delivery so discovery stays fair.
 */
import { pool } from '../db.js';

export function mindOpportunityEnabled(): boolean {
  const v = process.env.MIND_OPPORTUNITY_ENABLED;
  if (v == null || v === '') return true;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

/** creator_id → opportunity score in [0, 1] (higher = more under-exposed). */
export async function loadCreatorOpportunity(
  authorIds: string[]
): Promise<Map<string, number>> {
  const map = new Map<string, number>();
  if (!mindOpportunityEnabled() || !authorIds.length) return map;
  const ids = [...new Set(authorIds.filter(Boolean))].slice(0, 400);
  if (!ids.length) return map;

  try {
    // Deliveries in 7d via posts authored by candidates (proxy for exposure).
    const { rows } = await pool.query<{
      author_id: string;
      deliveries: number;
      posts: number;
    }>(
      `
      with authors as (
        select unnest($1::uuid[]) as author_id
      ),
      post_counts as (
        select p.author_id, count(*)::int as posts
        from public.posts p
        join authors a on a.author_id = p.author_id
        where coalesce(p.moderation_status, 'active') = 'active'
          and p.created_at > now() - interval '30 days'
        group by p.author_id
      ),
      del as (
        select p.author_id, count(*)::int as deliveries
        from public.feed_video_delivery d
        join public.posts p on p.id::text = d.canonical_video_id
        join authors a on a.author_id = p.author_id
        where d.created_at > now() - interval '7 days'
        group by p.author_id
      )
      select a.author_id::text,
             coalesce(d.deliveries, 0)::int as deliveries,
             coalesce(pc.posts, 0)::int as posts
      from authors a
      left join del d on d.author_id = a.author_id
      left join post_counts pc on pc.author_id = a.author_id
      `,
      [ids]
    );

    for (const r of rows) {
      const posts = Number(r.posts) || 0;
      const deliveries = Number(r.deliveries) || 0;
      // Need at least one recent post; skip barren accounts.
      if (posts < 1) continue;
      // Under-exposed: few deliveries relative to having content.
      // Cap opportunity so mega-viral never get this boost.
      if (deliveries > 400) continue;
      const raw = 1 - Math.min(1, deliveries / 120);
      // Prefer creators with some content but low reach.
      const score = Math.round(raw * Math.min(1, posts / 3) * 1000) / 1000;
      if (score >= 0.25) map.set(r.author_id, score);
    }
  } catch {
    /* feed_video_delivery join may fail on schema drift — fail soft */
  }
  return map;
}
