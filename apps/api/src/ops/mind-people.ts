/**
 * MIND Ops — per-user interest dossier (real Public profiles only).
 * Search + full “what we know” payload for /mind People tab.
 *
 * Pipeline seed owners use `@seed.matterya.internal` (see content-pipeline/owners.ts).
 * Those — plus harness/test Matterya emails — are excluded from People.
 */
import { pool } from '../db.js';
import { loadInterestBubbles } from '../recommendation/knn.service.js';

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** SQL fragment: profile alias `p` is a real human (not pipeline seed / harness). */
const REAL_USER_SQL = `
  coalesce(p.deleted_at, null) is null
  and coalesce(p.account_status, 'active') not in ('deleted', 'banned')
  and coalesce(p.email, '') not ilike '%@seed.matterya.internal'
  and coalesce(p.email, '') not ilike '%@matterya.dev'
  and coalesce(p.email, '') not ilike 'ios.test%@gmail.com'
  and coalesce(p.email, '') not ilike 'flutter_test%@%'
  and coalesce(p.email, '') not ilike 'android_crash_test%@%'
  and coalesce(p.email, '') not ilike 'iostester@%'
  and coalesce(p.bio, '') is distinct from 'Matterya seed profile'
`;

function isUuid(s: string): boolean {
  return UUID_RE.test(s);
}

/** True when this email/bio marks a seed or automated test account. */
export function isSeedOrHarnessProfile(opts: {
  email?: string | null;
  bio?: string | null;
}): boolean {
  const email = String(opts.email || '').toLowerCase();
  const bio = String(opts.bio || '');
  if (email.endsWith('@seed.matterya.internal')) return true;
  if (email.endsWith('@matterya.dev')) return true;
  if (email.startsWith('ios.test') && email.endsWith('@gmail.com')) return true;
  if (email.startsWith('flutter_test')) return true;
  if (email.startsWith('android_crash_test')) return true;
  if (email.startsWith('iostester@')) return true;
  if (bio === 'Matterya seed profile') return true;
  return false;
}

function topMap(
  m: Map<string, number> | Record<string, number> | null | undefined,
  limit = 12
): { key: string; score: number }[] {
  const entries: [string, number][] = [];
  if (!m) return [];
  if (m instanceof Map) {
    for (const [k, v] of m) entries.push([k, Number(v) || 0]);
  } else {
    for (const [k, v] of Object.entries(m)) entries.push([k, Number(v) || 0]);
  }
  return entries
    .filter(([k, v]) => k && Number.isFinite(v) && v !== 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([key, score]) => ({ key, score: Math.round(score * 1000) / 1000 }));
}

export type PeopleSearchHit = {
  userId: string;
  displayName: string;
  username: string | null;
  avatarUrl: string | null;
  countryCode: string | null;
  countryName: string | null;
  events7d: number;
  affinityCreators: number;
};

/** Search real profiles by name / username / uuid (excludes seeds + harness). */
export async function searchPeople(
  query: string,
  limit = 20
): Promise<PeopleSearchHit[]> {
  const q = String(query || '').trim();
  const lim = Math.min(Math.max(limit, 1), 40);
  if (!q) {
    // Default: most active *real* users (7d engagement). Scan a wider eng pool
    // then filter seeds — otherwise top-N engagers are almost all seed owners.
    const { rows } = await pool.query<{
      user_id: string;
      display_name: string | null;
      username: string | null;
      avatar_url: string | null;
      country_code: string | null;
      country_name: string | null;
      events7d: string;
      affinity_creators: string;
    }>(
      `
      with eng as (
        select entity_id, count(*)::int as n
        from public.entity_engagement_events
        where occurred_at > now() - interval '7 days'
        group by entity_id
      )
      select
        p.user_id::text,
        p.display_name,
        p.username,
        p.avatar_url,
        p.country_code,
        p.country_name,
        coalesce(e.n, 0)::text as events7d,
        coalesce((
          select count(*)::int from public.recsys_user_creator_affinity a
          where a.entity_id = p.user_id
        ), 0)::text as affinity_creators
      from public.profiles p
      join eng e on e.entity_id = p.user_id
      where ${REAL_USER_SQL}
      order by e.n desc
      limit $1
      `,
      [lim]
    );
    return rows.map((r) => ({
      userId: r.user_id,
      displayName: r.display_name || r.username || 'User',
      username: r.username,
      avatarUrl: r.avatar_url,
      countryCode: r.country_code,
      countryName: r.country_name,
      events7d: Number(r.events7d) || 0,
      affinityCreators: Number(r.affinity_creators) || 0,
    }));
  }

  if (isUuid(q)) {
    const { rows } = await pool.query<{
      user_id: string;
      display_name: string | null;
      username: string | null;
      avatar_url: string | null;
      country_code: string | null;
      country_name: string | null;
      email: string | null;
      bio: string | null;
    }>(
      `
      select p.user_id::text, p.display_name, p.username, p.avatar_url,
             p.country_code, p.country_name, p.email, p.bio
      from public.profiles p
      where p.user_id = $1::uuid
        and ${REAL_USER_SQL}
      limit 1
      `,
      [q]
    );
    if (!rows[0]) return [];
    const r = rows[0];
    return [
      {
        userId: r.user_id,
        displayName: r.display_name || r.username || 'User',
        username: r.username,
        avatarUrl: r.avatar_url,
        countryCode: r.country_code,
        countryName: r.country_name,
        events7d: 0,
        affinityCreators: 0,
      },
    ];
  }

  const like = `%${q.replace(/[%_]/g, '')}%`;
  const { rows } = await pool.query<{
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_code: string | null;
    country_name: string | null;
    events7d: string;
    affinity_creators: string;
  }>(
    `
    select
      p.user_id::text,
      p.display_name,
      p.username,
      p.avatar_url,
      p.country_code,
      p.country_name,
      coalesce((
        select count(*)::int from public.entity_engagement_events e
        where e.entity_id = p.user_id and e.occurred_at > now() - interval '7 days'
      ), 0)::text as events7d,
      coalesce((
        select count(*)::int from public.recsys_user_creator_affinity a
        where a.entity_id = p.user_id
      ), 0)::text as affinity_creators
    from public.profiles p
    where ${REAL_USER_SQL}
      and (
        p.display_name ilike $1
        or p.username ilike $1
        or p.email ilike $1
      )
    order by 7 desc nulls last, p.display_name asc nulls last
    limit $2
    `,
    [like, lim]
  );
  return rows.map((r) => ({
    userId: r.user_id,
    displayName: r.display_name || r.username || 'User',
    username: r.username,
    avatarUrl: r.avatar_url,
    countryCode: r.country_code,
    countryName: r.country_name,
    events7d: Number(r.events7d) || 0,
    affinityCreators: Number(r.affinity_creators) || 0,
  }));
}

/** Full Ops dossier — everything MIND knows about one real user. */
export async function getUserDossier(userId: string): Promise<Record<string, unknown> | null> {
  const id = String(userId || '').trim();
  if (!isUuid(id)) return null;

  const profileQ = pool.query<{
    user_id: string;
    display_name: string | null;
    username: string | null;
    email: string | null;
    avatar_url: string | null;
    country_code: string | null;
    country_name: string | null;
    city_name: string | null;
    bio: string | null;
    birthdate: string | null;
    is_verified: boolean | null;
    is_private: boolean | null;
    account_status: string | null;
    created_at: Date | null;
    last_seen: Date | null;
  }>(
    `
    select user_id::text, display_name, username, email, avatar_url,
           country_code, country_name, city_name, bio, birthdate::text,
           is_verified, is_private, account_status, created_at, last_seen
    from public.profiles
    where user_id = $1::uuid
    limit 1
    `,
    [id]
  );

  const personalityQ = pool.query<{
    events_counted: string | null;
    model_version: string | null;
    feature_version: string | null;
    updated_at: Date | null;
    window_end: Date | null;
    country_affinity: unknown;
    hub_affinity: unknown;
    creator_affinity: unknown;
    media_affinity: unknown;
    traits: unknown;
  }>(
    `
    select events_counted::text, model_version, feature_version, updated_at, window_end,
           country_affinity, hub_affinity, creator_affinity, media_affinity, traits
    from public.entity_personality
    where entity_id = $1::uuid
    limit 1
    `,
    [id]
  );

  const affinityQ = pool.query<{
    creator_id: string;
    score: string;
    positive_events: string;
    negative_events: string;
    last_event_at: Date | null;
    display_name: string | null;
    username: string | null;
  }>(
    `
    select a.creator_id::text, a.score::text, a.positive_events::text, a.negative_events::text,
           a.last_event_at, p.display_name, p.username
    from public.recsys_user_creator_affinity a
    left join public.profiles p on p.user_id = a.creator_id
    where a.entity_id = $1::uuid
    order by a.score desc nulls last
    limit 40
    `,
    [id]
  );

  const eventsQ = pool.query<{
    event_type: string;
    n: string;
  }>(
    `
    select event_type, count(*)::text as n
    from public.entity_engagement_events
    where entity_id = $1::uuid
      and occurred_at > now() - interval '7 days'
    group by event_type
    order by count(*) desc
    limit 30
    `,
    [id]
  );

  const recentQ = pool.query<{
    event_type: string;
    content_id: string | null;
    hub_slug: string | null;
    country_code: string | null;
    media_type: string | null;
    is_spark: boolean | null;
    surface: string | null;
    occurred_at: Date;
  }>(
    `
    select event_type, content_id::text, hub_slug, country_code, media_type,
           is_spark, surface, occurred_at
    from public.entity_engagement_events
    where entity_id = $1::uuid
    order by occurred_at desc nulls last
    limit 40
    `,
    [id]
  );

  const deliveryQ = pool.query<{
    surface: string;
    n: string;
  }>(
    `
    select surface, count(*)::text as n
    from public.feed_video_delivery
    where user_id = $1::uuid
    group by surface
    order by count(*) desc
    `,
    [id]
  );

  const decisionsQ = pool.query<{
    surface: string;
    policy_version: string | null;
    served_count: string | null;
    latency_ms: string | null;
    meta: unknown;
    created_at: Date;
  }>(
    `
    select surface, policy_version, served_count::text, latency_ms::text, meta, created_at
    from public.recommendation_decisions
    where entity_id = $1::uuid
    order by created_at desc nulls last
    limit 15
    `,
    [id]
  );

  const neighborsQ = pool.query<{
    neighbor_id: string;
    distance: string;
    display_name: string | null;
    username: string | null;
  }>(
    `
    select n.neighbor_id::text, n.distance::text, p.display_name, p.username
    from public.entity_neighbors n
    left join public.profiles p on p.user_id = n.neighbor_id
    where n.entity_id = $1::uuid
    order by n.distance asc nulls last
    limit 12
    `,
    [id]
  );

  const followingQ = pool.query<{ n: string }>(
    `
    select count(*)::text as n from public.user_follows
    where follower_id = $1::uuid
    `,
    [id]
  ).catch(() => ({ rows: [{ n: '0' }] as { n: string }[] }));

  const followersQ = pool.query<{ n: string }>(
    `
    select count(*)::text as n from public.user_follows
    where following_id = $1::uuid
    `,
    [id]
  ).catch(() => ({ rows: [{ n: '0' }] as { n: string }[] }));

  const postsQ = pool.query<{ n: string; sparks: string; videos: string }>(
    `
    select
      count(*)::text as n,
      count(*) filter (where media_type = 'reel')::text as sparks,
      count(*) filter (where media_type = 'video')::text as videos
    from public.posts
    where author_id = $1::uuid
    `,
    [id]
  ).catch(() => ({ rows: [{ n: '0', sparks: '0', videos: '0' }] }));

  const [
    profileRes,
    personalityRes,
    affinityRes,
    eventsRes,
    recentRes,
    deliveryRes,
    decisionsRes,
    neighborsRes,
    followingRes,
    followersRes,
    postsRes,
    bubbles,
  ] = await Promise.all([
    profileQ,
    personalityQ,
    affinityQ,
    eventsQ,
    recentQ,
    deliveryQ,
    decisionsQ,
    neighborsQ,
    followingQ,
    followersQ,
    postsQ,
    loadInterestBubbles(id),
  ]);

  const profile = profileRes.rows[0];
  if (!profile) return null;
  // Never serve pipeline seed / harness accounts as “real user” dossiers.
  if (isSeedOrHarnessProfile({ email: profile.email, bio: profile.bio })) {
    return null;
  }

  const personality = personalityRes.rows[0] || null;

  const hubTop = bubbles
    ? topMap(bubbles.hubs, 16)
    : topMap(
        (personality?.hub_affinity as Record<string, number>) || null,
        16
      );
  const countryTop = bubbles
    ? topMap(bubbles.countries, 12)
    : topMap(
        (personality?.country_affinity as Record<string, number>) || null,
        12
      );
  const mediaTop = bubbles
    ? topMap(bubbles.media, 10)
    : topMap(
        (personality?.media_affinity as Record<string, number>) || null,
        10
      );

  const annHitsRecent = decisionsRes.rows
    .map((d) => {
      const meta = d.meta as { featureHits?: { annHits?: number; topicHits?: number } } | null;
      return {
        at: d.created_at,
        surface: d.surface,
        annHits: meta?.featureHits?.annHits ?? null,
        topicHits: meta?.featureHits?.topicHits ?? null,
        served: Number(d.served_count) || 0,
        latencyMs: Number(d.latency_ms) || 0,
        policy: d.policy_version,
      };
    })
    .slice(0, 15);

  return {
    profile: {
      userId: profile.user_id,
      displayName: profile.display_name || profile.username || 'User',
      username: profile.username,
      email: profile.email,
      avatarUrl: profile.avatar_url,
      countryCode: profile.country_code,
      countryName: profile.country_name,
      cityName: profile.city_name,
      bio: profile.bio,
      birthdate: profile.birthdate,
      isVerified: !!profile.is_verified,
      isPrivate: !!profile.is_private,
      accountStatus: profile.account_status,
      createdAt: profile.created_at,
      lastSeen: profile.last_seen,
    },
    social: {
      following: Number(followingRes.rows[0]?.n) || 0,
      followers: Number(followersRes.rows[0]?.n) || 0,
      posts: Number(postsRes.rows[0]?.n) || 0,
      sparks: Number(postsRes.rows[0]?.sparks) || 0,
      videos: Number(postsRes.rows[0]?.videos) || 0,
    },
    interests: {
      hubs: hubTop,
      countries: countryTop,
      media: mediaTop,
      eventsCounted:
        bubbles?.eventsCounted ?? (Number(personality?.events_counted) || 0),
      modelVersion: personality?.model_version ?? null,
      featureVersion: personality?.feature_version ?? null,
      personalityUpdatedAt: personality?.updated_at ?? null,
      hasFeatureVector: !!(bubbles?.featureVector && bubbles.featureVector.length > 0),
      featureVectorDims: bubbles?.featureVector?.length ?? 0,
      traits: personality?.traits ?? null,
    },
    creatorAffinity: affinityRes.rows.map((r) => ({
      creatorId: r.creator_id,
      name: r.display_name || r.username || r.creator_id.slice(0, 8),
      username: r.username,
      score: Number(r.score) || 0,
      positives: Number(r.positive_events) || 0,
      negatives: Number(r.negative_events) || 0,
      lastEventAt: r.last_event_at,
    })),
    engagement7d: eventsRes.rows.map((r) => ({
      type: r.event_type,
      count: Number(r.n) || 0,
    })),
    recentEvents: recentRes.rows.map((r) => ({
      type: r.event_type,
      contentId: r.content_id,
      hubSlug: r.hub_slug,
      countryCode: r.country_code,
      mediaType: r.media_type,
      isSpark: r.is_spark,
      surface: r.surface,
      at: r.occurred_at,
    })),
    deliveriesBySurface: deliveryRes.rows.map((r) => ({
      surface: r.surface,
      count: Number(r.n) || 0,
    })),
    recentDecisions: annHitsRecent,
    neighbors: neighborsRes.rows.map((r) => ({
      neighborId: r.neighbor_id,
      name: r.display_name || r.username || r.neighbor_id.slice(0, 8),
      username: r.username,
      distance: Number(r.distance) || 0,
    })),
    summary: {
      coldStart: (bubbles?.eventsCounted ?? 0) < 25,
      knownInterestSignals:
        hubTop.length +
        countryTop.length +
        affinityRes.rows.length +
        (Number(eventsRes.rows.reduce((s, r) => s + (Number(r.n) || 0), 0)) || 0),
    },
  };
}
