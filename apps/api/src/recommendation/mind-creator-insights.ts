/**
 * MIND-025 — Thin creator insights read API (owner-only).
 * No payout math; organic engagement + delivery proxies only.
 */
import { pool } from '../db.js';

export type CreatorInsights = {
  userId: string;
  posts30d: number;
  sparks30d: number;
  engagementReceived7d: number;
  positives7d: number;
  negatives7d: number;
  deliveries7d: number;
  topHubs: { key: string; count: number }[];
  note: string;
};

export async function getCreatorInsights(
  userId: string
): Promise<CreatorInsights | null> {
  if (!userId) return null;

  let posts30d = 0;
  let sparks30d = 0;
  try {
    const { rows } = await pool.query<{ posts: number; sparks: number }>(
      `
      select
        count(*)::int as posts,
        count(*) filter (
          where is_reel = true or lower(coalesce(media_type, '')) in ('reel', 'spark')
        )::int as sparks
      from public.posts
      where author_id = $1::uuid
        and created_at > now() - interval '30 days'
        and coalesce(moderation_status, 'active') not in ('deleted')
      `,
      [userId]
    );
    posts30d = Number(rows[0]?.posts) || 0;
    sparks30d = Number(rows[0]?.sparks) || 0;
  } catch {
    /* ignore */
  }

  let engagementReceived7d = 0;
  let positives7d = 0;
  let negatives7d = 0;
  try {
    const { rows } = await pool.query<{
      n: number;
      pos: number;
      neg: number;
    }>(
      `
      select
        count(*)::int as n,
        count(*) filter (where strength > 0)::int as pos,
        count(*) filter (where strength < 0)::int as neg
      from public.entity_engagement_events
      where author_id = $1::uuid
        and occurred_at > now() - interval '7 days'
      `,
      [userId]
    );
    engagementReceived7d = Number(rows[0]?.n) || 0;
    positives7d = Number(rows[0]?.pos) || 0;
    negatives7d = Number(rows[0]?.neg) || 0;
  } catch {
    /* ignore */
  }

  let deliveries7d = 0;
  try {
    const { rows } = await pool.query<{ n: number }>(
      `
      select count(*)::int as n
      from public.feed_video_delivery d
      join public.posts p on p.id::text = d.canonical_video_id
      where p.author_id = $1::uuid
        and d.created_at > now() - interval '7 days'
      `,
      [userId]
    );
    deliveries7d = Number(rows[0]?.n) || 0;
  } catch {
    deliveries7d = 0;
  }

  let topHubs: { key: string; count: number }[] = [];
  try {
    const { rows } = await pool.query<{ hub: string; n: number }>(
      `
      select lower(hub_slug) as hub, count(*)::int as n
      from public.posts
      where author_id = $1::uuid
        and hub_slug is not null
        and created_at > now() - interval '90 days'
      group by 1
      order by n desc
      limit 8
      `,
      [userId]
    );
    topHubs = rows
      .filter((r) => r.hub)
      .map((r) => ({ key: r.hub, count: Number(r.n) || 0 }));
  } catch {
    topHubs = [];
  }

  return {
    userId,
    posts30d,
    sparks30d,
    engagementReceived7d,
    positives7d,
    negatives7d,
    deliveries7d,
    topHubs,
    note: 'Organic only — ads/payouts stay on separate product surfaces.',
  };
}
