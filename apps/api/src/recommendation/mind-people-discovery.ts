/**
 * MIND-021 — People discovery (privacy-safe).
 * Suggested creators from public signals only — no dossier dump, no email.
 */
import { pool } from '../db.js';

const REAL_USER_SQL = `
  coalesce(p.deleted_at, null) is null
  and coalesce(p.account_status, 'active') not in ('deleted', 'banned')
  and coalesce(p.email, '') not ilike '%@seed.matterya.internal'
  and coalesce(p.email, '') not ilike '%@matterya.dev'
  and coalesce(p.bio, '') is distinct from 'Matterya seed profile'
`;

export type PeopleSuggestion = {
  userId: string;
  displayName: string;
  username: string | null;
  avatarUrl: string | null;
  countryCode: string | null;
  reason: string;
  score: number;
};

export async function suggestPeople(opts: {
  viewerId?: string | null;
  limit?: number;
  countryCode?: string | null;
}): Promise<PeopleSuggestion[]> {
  const limit = Math.min(Math.max(opts.limit ?? 12, 1), 40);
  const viewerId = opts.viewerId ?? null;
  const cc = (opts.countryCode ?? '').trim().toUpperCase() || null;

  try {
    const { rows } = await pool.query<{
      user_id: string;
      display_name: string | null;
      username: string | null;
      avatar_url: string | null;
      country_code: string | null;
      reason: string;
      score: number;
    }>(
      `
      with recent_posts as (
        select author_id, count(*)::int as posts_14d
        from public.posts
        where created_at > now() - interval '14 days'
          and coalesce(moderation_status, 'active') = 'active'
        group by author_id
      ),
      ranked as (
        select
          p.user_id,
          p.display_name,
          p.username,
          p.avatar_url,
          p.country_code,
          case
            when $2::text is not null and upper(coalesce(p.country_code, '')) = $2 then 'same_country'
            when coalesce(p.is_verified, false) then 'verified'
            else 'active_creator'
          end as reason,
          (
            least(5, coalesce(rp.posts_14d, 0)::real / 4.0)
            + case when coalesce(p.is_verified, false) then 2 else 0 end
            + case when $2::text is not null and upper(coalesce(p.country_code, '')) = $2 then 1.5 else 0 end
          ) as score
        from public.profiles p
        join recent_posts rp on rp.author_id = p.user_id
        where ${REAL_USER_SQL}
          and ($1::uuid is null or p.user_id <> $1::uuid)
          and (
            $1::uuid is null
            or not exists (
              select 1 from public.user_follows f
              where f.follower_id = $1::uuid and f.following_id = p.user_id
            )
          )
      )
      select user_id::text, display_name, username, avatar_url, country_code,
             reason, score
      from ranked
      order by score desc
      limit $3
      `,
      [viewerId, cc, limit]
    );

    return rows.map((r) => ({
      userId: r.user_id,
      displayName: r.display_name || r.username || 'Creator',
      username: r.username,
      avatarUrl: r.avatar_url,
      countryCode: r.country_code,
      reason: r.reason,
      score: Math.round(Number(r.score) * 1000) / 1000,
    }));
  } catch (err: any) {
    console.warn('[mind-people-discovery]', err?.message ?? err);
    return [];
  }
}
