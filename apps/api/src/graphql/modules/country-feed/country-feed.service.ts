import { pool } from '../../../db.js';
import { getCountryMood, type CountryMood } from '../insights/insights.service.js';
import { PresenceService } from '../presence/presence.service.js';

export type TrendTopic = {
  label: string;
  post_count: number;
};

export type LocationActivity = {
  name: string;
  post_count: number;
  online_now: number;
};

export type CountryPulse = {
  country_code: string;
  trending: TrendTopic[];
  mood: CountryMood;
  active_locations: LocationActivity[];
};

export type CountryRecommendation = {
  kind: string;
  label: string;
  reason: string;
  user_id: string | null;
  username: string | null;
  avatar_url: string | null;
};

export type ForeignPresenceCountry = {
  country_code: string;
  country_name: string;
  online_now: number;
  posts_last_24h: number;
  score: number;
};

export type LocalForeignPresence = {
  local_online_now: number;
  foreign_online_now: number;
  local_posts_last_24h: number;
  foreign_posts_last_24h: number;
  top_foreign_countries: ForeignPresenceCountry[];
};

export type CountryIntelligence = {
  country_code: string;
  country_name: string | null;
  online_now: number;
  total_users: number;
  posts_last_24h: number;
  insight_summary: string;
  recommendations: CountryRecommendation[];
  presence: LocalForeignPresence;
};

const TREND_STOPWORDS = new Set(
  [
    'the',
    'and',
    'for',
    'with',
    'from',
    'that',
    'this',
    'have',
    'has',
    'had',
    'are',
    'was',
    'were',
    'will',
    'would',
    'could',
    'should',
    'about',
    'into',
    'your',
    'their',
    'there',
    'they',
    'them',
    'what',
    'when',
    'where',
    'which',
    'while',
    'than',
    'then',
    'just',
    'like',
    'also',
    'some',
    'more',
    'most',
    'only',
    'over',
    'into',
    'around',
    'still',
    'very',
    'much',
    'been',
    'being',
    'because',
    'after',
    'before',
    'through',
    'under',
    'between',
    'you',
    'our',
    'his',
    'her',
    'its',
    'not',
    'but',
    'can',
    'cant',
    'dont',
    'its',
    'im',
    'we',
    'she',
    'he',
    'they',
    'i',
    'a',
    'an',
    'to',
    'of',
    'in',
    'on',
    'at',
    'by',
    'as',
    'is',
    'it',
    'or',
    'be',
    'if',
    'my',
    'me',
    'us',
  ]
);

function normalizeCountryCode(value: string | null | undefined): string {
  return String(value ?? '').trim().toUpperCase();
}

function tokenizeTrendText(value: string | null | undefined): string[] {
  const text = String(value ?? '')
    .toLowerCase()
    .replace(/https?:\/\/\S+/g, ' ')
    .replace(/[\u0000-\u001f]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!text) return [];
  return text
    .split(' ')
    .map((token) =>
      token.replace(
        /^[^a-z0-9#\u00c0-\u024f\u0370-\u03ff\u0400-\u04ff\u0600-\u06ff]+|[^a-z0-9#\u00c0-\u024f\u0370-\u03ff\u0400-\u04ff\u0600-\u06ff-]+$/gi,
        ''
      )
    )
    .filter(Boolean);
}

function formatTrendLabel(word: string): string {
  if (!word) return '';
  if (word.startsWith('#')) return word;
  return `#${word}`;
}

async function fetchTrendTexts(countryCode: string): Promise<string[]> {
  const { rows: postRows } = await pool.query<{ title: string | null; body: string | null }>(
    `
    select title, body
    from public.posts
    where upper(coalesce(country_code, '')) = $1
      and created_at > now() - interval '7 days'
    order by created_at desc
    limit 220
    `,
    [countryCode]
  );

  const { rows: commentRows } = await pool.query<{ body: string | null }>(
    `
    select pc.body
    from public.post_comments pc
    join public.posts p on p.id = pc.post_id
    where upper(coalesce(p.country_code, '')) = $1
      and pc.created_at > now() - interval '7 days'
    order by pc.created_at desc
    limit 180
    `,
    [countryCode]
  );

  return [
    ...postRows.flatMap((row) => [row.title ?? '', row.body ?? '']),
    ...commentRows.map((row) => row.body ?? ''),
  ].filter(Boolean);
}

function buildTrendingTopics(texts: string[], limit = 6): TrendTopic[] {
  const counts = new Map<string, number>();
  for (const text of texts) {
    const seen = new Set<string>();
    for (const token of tokenizeTrendText(text)) {
      const normalized = token.replace(/^-+|-+$/g, '');
      if (!normalized) continue;
      const base = normalized.startsWith('#') ? normalized.slice(1) : normalized;
      if (base.length < 3) continue;
      if (TREND_STOPWORDS.has(base)) continue;
      const key = base;
      if (seen.has(key)) continue;
      seen.add(key);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }

  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, limit)
    .map(([word, count]) => ({
      label: formatTrendLabel(word),
      post_count: count,
    }));
}

async function activeLocations(countryCode: string, ttlSeconds: number): Promise<LocationActivity[]> {
  const { rows } = await pool.query<{
    name: string | null;
    post_count: number;
    online_now: number;
  }>(
    `
    with combined as (
      select
        nullif(trim(city_name), '') as name,
        count(*)::int as post_count,
        0::int as online_now
      from public.posts
      where upper(coalesce(country_code, '')) = $1
        and created_at > now() - interval '7 days'
      group by 1

      union all

      select
        nullif(trim(city_name), '') as name,
        0::int as post_count,
        count(*)::int as online_now
      from public.user_presence
      where upper(coalesce(country_code, '')) = $1
        and is_online = true
        and last_seen_at > (now() - ($2 || ' seconds')::interval)
      group by 1
    )
    select
      name,
      sum(post_count)::int as post_count,
      sum(online_now)::int as online_now
    from combined
    where name is not null
    group by name
    order by sum(online_now) desc, sum(post_count) desc, name asc
    limit 5
    `,
    [countryCode, ttlSeconds]
  );

  return rows.map((row) => ({
    name: String(row.name ?? '').trim(),
    post_count: Number(row.post_count ?? 0),
    online_now: Number(row.online_now ?? 0),
  }));
}

async function postsLast24h(countryCode: string): Promise<number> {
  const { rows } = await pool.query<{ total: string }>(
    `
    select count(*)::text as total
    from public.posts
    where upper(coalesce(country_code, '')) = $1
      and created_at > now() - interval '24 hours'
    `,
    [countryCode]
  );
  return Number(rows[0]?.total ?? 0);
}

async function localForeignPresence(countryCode: string, ttlSeconds: number): Promise<LocalForeignPresence> {
  const { rows } = await pool.query<{
    local_online_now: string;
    foreign_online_now: string;
    local_posts_last_24h: string;
    foreign_posts_last_24h: string;
  }>(
    `
    with online_users as (
      select
        pr.user_id,
        upper(coalesce(pr.country_code, '')) as home_country,
        upper(coalesce(up.country_code, '')) as viewing_country
      from public.user_presence up
      join public.profiles pr on pr.user_id = up.user_id
      where up.is_online = true
        and up.last_seen_at > (now() - ($2 || ' seconds')::interval)
        and upper(coalesce(up.country_code, '')) = $1
    ),
    feed_activity as (
      select
        pr.user_id,
        upper(coalesce(pr.country_code, '')) as home_country,
        (p.shared_post_id is not null) as is_share
      from public.posts p
      join public.profiles pr on pr.user_id = p.author_id
      where upper(coalesce(p.country_code, '')) = $1
        and p.created_at > now() - interval '24 hours'
    )
    select
      (select count(*)::text from online_users where home_country = $1) as local_online_now,
      (select count(*)::text from online_users where home_country <> $1 and home_country <> '') as foreign_online_now,
      (select count(*)::text from feed_activity where home_country = $1) as local_posts_last_24h,
      (select count(*)::text from feed_activity where home_country <> $1 and home_country <> '' and is_share = true) as foreign_posts_last_24h
    `,
    [countryCode, ttlSeconds]
  );

  const summary = rows[0];

  const { rows: foreignRows } = await pool.query<{
    country_code: string | null;
    country_name: string | null;
    online_now: number;
    posts_last_24h: number;
  }>(
    `
    with online_by_country as (
      select
        upper(coalesce(pr.country_code, '')) as country_code,
        max(pr.country_name) as country_name,
        count(*)::int as online_now
      from public.user_presence up
      join public.profiles pr on pr.user_id = up.user_id
      where up.is_online = true
        and up.last_seen_at > (now() - ($2 || ' seconds')::interval)
        and upper(coalesce(up.country_code, '')) = $1
        and upper(coalesce(pr.country_code, '')) <> $1
        and upper(coalesce(pr.country_code, '')) <> ''
      group by 1
    ),
    shares_by_country as (
      select
        upper(coalesce(pr.country_code, '')) as country_code,
        max(pr.country_name) as country_name,
        count(*)::int as posts_last_24h
      from public.posts p
      join public.profiles pr on pr.user_id = p.author_id
      where upper(coalesce(p.country_code, '')) = $1
        and p.created_at > now() - interval '24 hours'
        and p.shared_post_id is not null
        and upper(coalesce(pr.country_code, '')) <> $1
        and upper(coalesce(pr.country_code, '')) <> ''
      group by 1
    )
    select
      coalesce(online_by_country.country_code, shares_by_country.country_code) as country_code,
      coalesce(online_by_country.country_name, shares_by_country.country_name) as country_name,
      coalesce(online_by_country.online_now, 0) as online_now,
      coalesce(shares_by_country.posts_last_24h, 0) as posts_last_24h
    from online_by_country
    full outer join shares_by_country
      on shares_by_country.country_code = online_by_country.country_code
    order by (coalesce(online_by_country.online_now, 0) * 3 + coalesce(shares_by_country.posts_last_24h, 0) * 2) desc,
             coalesce(online_by_country.online_now, 0) desc,
             coalesce(shares_by_country.posts_last_24h, 0) desc
    limit 5
    `,
    [countryCode, ttlSeconds]
  );

  return {
    local_online_now: Number(summary?.local_online_now ?? 0),
    foreign_online_now: Number(summary?.foreign_online_now ?? 0),
    local_posts_last_24h: Number(summary?.local_posts_last_24h ?? 0),
    foreign_posts_last_24h: Number(summary?.foreign_posts_last_24h ?? 0),
    top_foreign_countries: foreignRows.map((row) => {
      const onlineNow = Number(row.online_now ?? 0);
      const posts24h = Number(row.posts_last_24h ?? 0);
      return {
        country_code: normalizeCountryCode(row.country_code),
        country_name: String(row.country_name ?? row.country_code ?? '').trim(),
        online_now: onlineNow,
        posts_last_24h: posts24h,
        score: onlineNow * 3 + posts24h * 2,
      };
    }),
  };
}

async function recommendations(countryCode: string, viewerId: string | null): Promise<CountryRecommendation[]> {
  const params: Array<string | number | null> = [countryCode, viewerId];
  const { rows } = await pool.query<{
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    posts_last_7d: number;
    posts_last_30d: number;
    online_now: boolean;
    global_posts_last_30d: number;
    global_online_now: boolean;
    followers_count: number;
    city_name: string | null;
  }>(
    `
    with recent_posts_7d as (
      select
        p.author_id,
        count(*)::int as posts_last_7d
      from public.posts p
      where upper(coalesce(p.country_code, '')) = $1
        and p.created_at > now() - interval '7 days'
      group by p.author_id
    ),
    recent_posts_30d as (
      select
        p.author_id,
        count(*)::int as posts_last_30d
      from public.posts p
      where upper(coalesce(p.country_code, '')) = $1
        and p.created_at > now() - interval '30 days'
      group by p.author_id
    ),
    online_locals as (
      select
        up.user_id,
        true as online_now
      from public.user_presence up
      join public.profiles pr on pr.user_id = up.user_id
      where up.is_online = true
        and up.last_seen_at > (now() - interval '90 seconds')
        and upper(coalesce(pr.country_code, '')) = $1
    ),
    global_recent_posts_30d as (
      select
        p.author_id,
        count(*)::int as global_posts_last_30d
      from public.posts p
      where p.created_at > now() - interval '30 days'
      group by p.author_id
    ),
    global_online as (
      select
        up.user_id,
        true as global_online_now
      from public.user_presence up
      where up.is_online = true
        and up.last_seen_at > (now() - interval '90 seconds')
    ),
    real_supabase_users as (
      select au.id as user_id
      from auth.users au
    )
    select
      pr.user_id,
      pr.display_name,
      pr.username,
      pr.avatar_url,
      coalesce(r7.posts_last_7d, 0)::int as posts_last_7d,
      coalesce(r30.posts_last_30d, 0)::int as posts_last_30d,
      coalesce(ol.online_now, false) as online_now,
      coalesce(gr30.global_posts_last_30d, 0)::int as global_posts_last_30d,
      coalesce(go.global_online_now, false) as global_online_now,
      coalesce(f.followers_count, 0)::int as followers_count,
      pr.city_name
    from public.profiles pr
    join real_supabase_users rsu on rsu.user_id = pr.user_id
    left join recent_posts_7d r7 on r7.author_id = pr.user_id
    left join recent_posts_30d r30 on r30.author_id = pr.user_id
    left join online_locals ol on ol.user_id = pr.user_id
    left join global_recent_posts_30d gr30 on gr30.author_id = pr.user_id
    left join global_online go on go.user_id = pr.user_id
    left join (
      select following_id, count(*)::int as followers_count
      from public.user_follows
      group by following_id
    ) f on f.following_id = pr.user_id
    where ($2::uuid is null or pr.user_id <> $2::uuid)
      and (
        $2::uuid is null or not exists (
          select 1
          from public.user_follows uf
          where uf.follower_id = $2::uuid
            and uf.following_id = pr.user_id
        )
      )
      and (
        coalesce(r7.posts_last_7d, 0) > 0
        or coalesce(ol.online_now, false) = true
        or coalesce(r30.posts_last_30d, 0) > 0
        or coalesce(go.global_online_now, false) = true
        or coalesce(gr30.global_posts_last_30d, 0) > 0
        or coalesce(f.followers_count, 0) > 0
      )
    order by
      (
        coalesce(r7.posts_last_7d, 0) * 120
        + (case when coalesce(ol.online_now, false) then 70 else 0 end)
        + coalesce(r30.posts_last_30d, 0) * 18
        + (case when coalesce(go.global_online_now, false) then 12 else 0 end)
        + coalesce(gr30.global_posts_last_30d, 0) * 4
        + least(coalesce(f.followers_count, 0), 40)
      ) desc,
      (upper(coalesce(pr.country_code, '')) = $1) desc,
      coalesce(r7.posts_last_7d, 0) desc,
      coalesce(ol.online_now, false) desc,
      coalesce(r30.posts_last_30d, 0) desc,
      coalesce(go.global_online_now, false) desc,
      coalesce(gr30.global_posts_last_30d, 0) desc,
      coalesce(f.followers_count, 0) desc,
      pr.created_at desc
    limit 6
    `,
    params
  );

  return rows.slice(0, 4).map((row) => ({
    kind: 'profile',
    label: row.display_name || row.username || 'Member',
    reason: (() => {
      if (row.posts_last_7d > 0) {
        return row.city_name
          ? `${row.posts_last_7d} recent posts from ${row.city_name}`
          : `${row.posts_last_7d} recent posts in this country`;
      }
      if (row.online_now) {
        return row.city_name ? `Online now from ${row.city_name}` : 'Online now in this country';
      }
      if (row.posts_last_30d > 0) {
        return row.city_name
          ? `${row.posts_last_30d} posts this month from ${row.city_name}`
          : `${row.posts_last_30d} posts this month in this country`;
      }
      if (row.global_online_now) {
        return 'Online now on Matterya';
      }
      if (row.global_posts_last_30d > 0) {
        return `${row.global_posts_last_30d} posts this month on Matterya`;
      }
      if (row.followers_count > 0) {
        return `${row.followers_count} followers on Matterya`;
      }
      return 'Active on Matterya';
    })(),
    user_id: row.user_id,
    username: row.username ?? null,
    avatar_url: row.avatar_url ?? null,
  }));
}

export class CountryFeedService {
  private presence = new PresenceService();

  async countryPulse(countryCode: string): Promise<CountryPulse> {
    const iso = normalizeCountryCode(countryCode);
    const [texts, mood] = await Promise.all([fetchTrendTexts(iso), getCountryMood(iso)]);
    const locations = await activeLocations(iso, this.presence.getTTL());
    return {
      country_code: iso,
      trending: buildTrendingTopics(texts),
      mood,
      active_locations: locations,
    };
  }

  async countryIntelligence(countryCode: string, viewerId: string | null): Promise<CountryIntelligence> {
    const iso = normalizeCountryCode(countryCode);
    const [stats, mood, posts24h, presence] = await Promise.all([
      this.presence.countryStats(iso),
      getCountryMood(iso),
      postsLast24h(iso),
      localForeignPresence(iso, this.presence.getTTL()),
    ]);
    let recs: CountryRecommendation[] = [];
    try {
      recs = await recommendations(iso, viewerId);
    } catch (err) {
      console.error('countryIntelligence recommendations failed', {
        countryCode: iso,
        viewerId,
        err,
      });
      recs = [];
    }

    return {
      country_code: iso,
      country_name: stats.name ?? null,
      online_now: stats.onlineNow,
      total_users: stats.totalUsers,
      posts_last_24h: posts24h,
      insight_summary: mood.insight,
      recommendations: recs,
      presence,
    };
  }
}
