/**
 * Matterya Studio (Hubs) — owner-only analytics + catalog.
 * Phase A: real aggregates from engagement + delivery + posts.
 * Deepens later into CTR/retention/traffic-source product tables.
 */
import { pool } from '../db.js';
import { ChannelsService, type ChannelRow } from '../graphql/modules/channels/channels.service.js';

const channels = new ChannelsService();

export type StudioRange = '7d' | '28d' | '90d';

function rangeDays(range: StudioRange): number {
  if (range === '7d') return 7;
  if (range === '90d') return 90;
  return 28;
}

function parseRange(raw: unknown): StudioRange {
  const v = String(raw ?? '28d').trim().toLowerCase();
  if (v === '7d' || v === '7') return '7d';
  if (v === '90d' || v === '90') return '90d';
  return '28d';
}

/** Channel videos that count as Studio content (not feed reshare / archive). */
const CHANNEL_VIDEO_WHERE = `
  p.channel_id = $1::uuid
  and p.channel_hidden_at is null
  and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
  and lower(coalesce(p.media_type, '')) in ('video', 'reel')
  and coalesce(p.body, '') not like '%__hub_origin__|%'
  and coalesce(p.body, '') not like '%__spark_share__|%'
  and coalesce(p.shared_post_id::text, '') = ''
  and coalesce(p.media_url, '') not like '%archive.org%'
`;

export type StudioChannelPayload = {
  hasChannel: boolean;
  channel: ChannelRow | null;
};

export async function getStudioChannel(userId: string): Promise<StudioChannelPayload> {
  const channel = await channels.myChannel(userId);
  return { hasChannel: !!channel, channel };
}

export type StudioDashboard = {
  range: StudioRange;
  rangeDays: number;
  channelId: string;
  kpis: {
    views: number;
    watchMs: number;
    impressions: number;
    clicks: number;
    ctr: number | null;
    avgViewDurationMs: number | null;
    avgViewPercentage: number | null;
    completes: number;
    skips: number;
    likes: number;
    comments: number;
    subscribers: number;
    videos: number;
  };
  daily: { day: string; views: number; watchMs: number; impressions: number }[];
  topVideos: StudioVideoRow[];
  note: string;
};

export type StudioVideoRow = {
  id: string;
  title: string | null;
  thumbUrl: string | null;
  mediaType: string | null;
  createdAt: string | null;
  hubSlug: string | null;
  views: number;
  watchMs: number;
  impressions: number;
  clicks: number;
  ctr: number | null;
  completes: number;
  qualityScore: number | null;
};

function ctr(impressions: number, clicks: number): number | null {
  if (impressions <= 0) return null;
  return Math.round((clicks / impressions) * 10000) / 10000;
}

export async function getStudioDashboard(
  userId: string,
  rangeRaw?: unknown
): Promise<StudioDashboard | { error: string; status: number }> {
  const range = parseRange(rangeRaw);
  const days = rangeDays(range);
  const channel = await channels.myChannel(userId);
  if (!channel) {
    return { error: 'channel_required', status: 404 };
  }

  const videoIds = await loadChannelVideoIds(channel.id);
  const kpis = await loadKpis(channel.id, videoIds, days);
  const daily = await loadDailySeries(videoIds, days);
  const topVideos = await listStudioVideos(channel.id, {
    limit: 8,
    sort: 'views',
    days,
  });

  // Subscribers ≈ channel follows if table exists; else 0.
  let subscribers = 0;
  try {
    const { rows } = await pool.query<{ n: number }>(
      `
      select count(*)::int as n
      from public.user_follows
      where following_id = $1::uuid
      `,
      [channel.owner_user_id]
    );
    subscribers = Number(rows[0]?.n) || 0;
  } catch {
    subscribers = 0;
  }

  return {
    range,
    rangeDays: days,
    channelId: channel.id,
    kpis: {
      ...kpis,
      subscribers,
      videos: channel.video_count ?? videoIds.length,
      ctr: ctr(kpis.impressions, kpis.clicks),
      avgViewDurationMs:
        kpis.views > 0 ? Math.round(kpis.watchMs / kpis.views) : null,
      avgViewPercentage: null, // filled when progress rollups land (Phase A→C)
    },
    daily,
    topVideos,
    note:
      'Matterya Studio Phase A — organic Hubs metrics from engagement + delivery. CTR needs impression/play pairing; retention curves land next.',
  };
}

export async function getStudioVideosPage(
  userId: string,
  opts: { range?: unknown; cursor?: string | null; limit?: number; sort?: string }
): Promise<
  | { range: StudioRange; videos: StudioVideoRow[]; nextCursor: string | null }
  | { error: string; status: number }
> {
  const range = parseRange(opts.range);
  const days = rangeDays(range);
  const channel = await channels.myChannel(userId);
  if (!channel) return { error: 'channel_required', status: 404 };

  const limit = Math.min(Math.max(opts.limit ?? 30, 1), 50);
  const videos = await listStudioVideos(channel.id, {
    limit: limit + 1,
    sort: opts.sort ?? 'views',
    days,
    cursor: opts.cursor ?? null,
  });
  let nextCursor: string | null = null;
  let page = videos;
  if (videos.length > limit) {
    page = videos.slice(0, limit);
    nextCursor = page[page.length - 1]?.createdAt ?? page[page.length - 1]?.id ?? null;
  }
  return { range, videos: page, nextCursor };
}

export type StudioVideoAnalytics = {
  range: StudioRange;
  video: StudioVideoRow;
  funnel: {
    impressions: number;
    clicks: number;
    ctr: number | null;
    views: number;
    completes: number;
    skips: number;
    likes: number;
    comments: number;
    watchMs: number;
  };
  sources: { source: string; views: number }[];
  retention: { bucket: number; reached: number }[];
  daily: { day: string; views: number; watchMs: number; impressions: number }[];
  note: string;
};

export async function getStudioVideoAnalytics(
  userId: string,
  videoId: string,
  rangeRaw?: unknown
): Promise<StudioVideoAnalytics | { error: string; status: number }> {
  const range = parseRange(rangeRaw);
  const days = rangeDays(range);
  const channel = await channels.myChannel(userId);
  if (!channel) return { error: 'channel_required', status: 404 };

  const owned = await assertChannelOwnsVideo(channel.id, videoId);
  if (!owned) return { error: 'not_found', status: 404 };

  const rows = await listStudioVideos(channel.id, {
    limit: 1,
    sort: 'views',
    days,
    onlyId: videoId,
  });
  const video = rows[0];
  if (!video) return { error: 'not_found', status: 404 };

  const funnel = await loadVideoFunnel(videoId, days);
  const sources = await loadTrafficSources(videoId, days);
  const retention = await loadRetentionBuckets(videoId, days);
  const daily = await loadDailySeries([videoId], days);

  return {
    range,
    video,
    funnel: {
      ...funnel,
      ctr: ctr(funnel.impressions, funnel.clicks),
    },
    sources,
    retention,
    daily,
    note:
      'Traffic sources use engagement.surface when present; missing source → unknown. Retention uses progress events when available.',
  };
}

// ─── internals ───────────────────────────────────────────────────────────────

async function loadChannelVideoIds(channelId: string): Promise<string[]> {
  try {
    const { rows } = await pool.query<{ id: string }>(
      `
      select p.id::text as id
      from public.posts p
      where ${CHANNEL_VIDEO_WHERE}
      order by p.created_at desc
      limit 2000
      `,
      [channelId]
    );
    return rows.map((r) => r.id);
  } catch {
    return [];
  }
}

async function assertChannelOwnsVideo(
  channelId: string,
  videoId: string
): Promise<boolean> {
  try {
    const { rows } = await pool.query<{ ok: boolean }>(
      `
      select exists(
        select 1 from public.posts p
        where p.id = $2::uuid and ${CHANNEL_VIDEO_WHERE}
      ) as ok
      `,
      [channelId, videoId]
    );
    return !!rows[0]?.ok;
  } catch {
    return false;
  }
}

async function loadKpis(
  _channelId: string,
  videoIds: string[],
  days: number
): Promise<{
  views: number;
  watchMs: number;
  impressions: number;
  clicks: number;
  completes: number;
  skips: number;
  likes: number;
  comments: number;
}> {
  const empty = {
    views: 0,
    watchMs: 0,
    impressions: 0,
    clicks: 0,
    completes: 0,
    skips: 0,
    likes: 0,
    comments: 0,
  };
  if (!videoIds.length) return empty;

  try {
    const { rows } = await pool.query<{
      impressions: number;
      clicks: number;
      views: number;
      completes: number;
      skips: number;
      likes: number;
      comments: number;
      watch_ms: number;
    }>(
      `
      select
        count(*) filter (
          where event_type in ('EngagementImpression', 'EngagementViewportVisible', 'impression', 'viewport_visible')
        )::int as impressions,
        count(*) filter (
          where event_type in (
            'EngagementHubVideoOpened', 'hub_video_open',
            'EngagementWatchPartial', 'watch_partial',
            'EngagementWatchComplete', 'watch_complete'
          )
        )::int as clicks,
        count(*) filter (
          where event_type in (
            'EngagementWatchPartial', 'watch_partial',
            'EngagementWatchComplete', 'watch_complete',
            'EngagementScrollDwell', 'scroll_dwell'
          )
        )::int as views,
        count(*) filter (
          where event_type in ('EngagementWatchComplete', 'watch_complete')
        )::int as completes,
        count(*) filter (
          where event_type in ('EngagementScrollSkip', 'scroll_skip')
        )::int as skips,
        count(*) filter (
          where event_type in ('EngagementLiked', 'like')
        )::int as likes,
        count(*) filter (
          where event_type in ('EngagementCommented', 'comment')
        )::int as comments,
        coalesce(sum(duration_ms) filter (
          where duration_ms is not null and duration_ms > 0
            and event_type in (
              'EngagementWatchPartial', 'watch_partial',
              'EngagementWatchComplete', 'watch_complete',
              'EngagementScrollDwell', 'scroll_dwell'
            )
        ), 0)::bigint as watch_ms
      from public.entity_engagement_events
      where content_id = any($1::uuid[])
        and occurred_at > now() - make_interval(days => $2::int)
      `,
      [videoIds, days]
    );
    const r = rows[0];
    return {
      views: Number(r?.views) || 0,
      watchMs: Number(r?.watch_ms) || 0,
      impressions: Number(r?.impressions) || 0,
      clicks: Number(r?.clicks) || 0,
      completes: Number(r?.completes) || 0,
      skips: Number(r?.skips) || 0,
      likes: Number(r?.likes) || 0,
      comments: Number(r?.comments) || 0,
    };
  } catch {
    return empty;
  }
}

async function loadDailySeries(
  videoIds: string[],
  days: number
): Promise<{ day: string; views: number; watchMs: number; impressions: number }[]> {
  if (!videoIds.length) return [];
  try {
    const { rows } = await pool.query<{
      day: string;
      views: number;
      watch_ms: number;
      impressions: number;
    }>(
      `
      select
        to_char(date_trunc('day', occurred_at), 'YYYY-MM-DD') as day,
        count(*) filter (
          where event_type in (
            'EngagementWatchPartial', 'watch_partial',
            'EngagementWatchComplete', 'watch_complete',
            'EngagementScrollDwell', 'scroll_dwell'
          )
        )::int as views,
        coalesce(sum(duration_ms) filter (where duration_ms is not null and duration_ms > 0), 0)::bigint as watch_ms,
        count(*) filter (
          where event_type in ('EngagementImpression', 'EngagementViewportVisible', 'impression', 'viewport_visible')
        )::int as impressions
      from public.entity_engagement_events
      where content_id = any($1::uuid[])
        and occurred_at > now() - make_interval(days => $2::int)
      group by 1
      order by 1 asc
      `,
      [videoIds, days]
    );
    return rows.map((r) => ({
      day: r.day,
      views: Number(r.views) || 0,
      watchMs: Number(r.watch_ms) || 0,
      impressions: Number(r.impressions) || 0,
    }));
  } catch {
    return [];
  }
}

async function listStudioVideos(
  channelId: string,
  opts: {
    limit: number;
    sort: string;
    days: number;
    cursor?: string | null;
    onlyId?: string;
  }
): Promise<StudioVideoRow[]> {
  try {
    const params: unknown[] = [channelId];
    let where = CHANNEL_VIDEO_WHERE;
    if (opts.onlyId) {
      params.push(opts.onlyId);
      where += ` and p.id = $${params.length}::uuid`;
    }
    if (opts.cursor && !opts.onlyId) {
      params.push(opts.cursor);
      where += ` and p.created_at < $${params.length}::timestamptz`;
    }
    params.push(opts.days);
    const daysParam = params.length;
    params.push(opts.limit);
    const limitParam = params.length;

    const sortKey = String(opts.sort || 'views').toLowerCase();
    const orderBy =
      sortKey === 'watch'
        ? 'coalesce(s.watch_ms, 0) desc, v.created_at desc'
        : sortKey === 'ctr'
          ? `case when coalesce(s.impressions, 0) > 0
               then coalesce(s.clicks, 0)::float / s.impressions
               else 0 end desc,
             coalesce(s.views, 0) desc,
             v.created_at desc`
          : sortKey === 'newest'
            ? 'v.created_at desc'
            : 'coalesce(s.views, 0) desc, v.created_at desc';

    const { rows } = await pool.query<{
      id: string;
      title: string | null;
      thumb_url: string | null;
      media_type: string | null;
      created_at: string | null;
      hub_slug: string | null;
      views: number;
      watch_ms: number;
      impressions: number;
      clicks: number;
      completes: number;
      quality_score: number | null;
    }>(
      `
      with vids as (
        select
          p.id,
          p.title,
          p.thumb_url,
          p.media_type,
          p.created_at,
          p.hub_slug
        from public.posts p
        where ${where}
        order by p.created_at desc
        limit 500
      ),
      stats as (
        select
          e.content_id,
          count(*) filter (
            where e.event_type in (
              'EngagementWatchPartial', 'watch_partial',
              'EngagementWatchComplete', 'watch_complete',
              'EngagementScrollDwell', 'scroll_dwell'
            )
          )::int as views,
          coalesce(sum(e.duration_ms) filter (where e.duration_ms is not null and e.duration_ms > 0), 0)::bigint as watch_ms,
          count(*) filter (
            where e.event_type in ('EngagementImpression', 'EngagementViewportVisible', 'impression', 'viewport_visible')
          )::int as impressions,
          count(*) filter (
            where e.event_type in (
              'EngagementHubVideoOpened', 'hub_video_open',
              'EngagementWatchPartial', 'watch_partial',
              'EngagementWatchComplete', 'watch_complete'
            )
          )::int as clicks,
          count(*) filter (
            where e.event_type in ('EngagementWatchComplete', 'watch_complete')
          )::int as completes
        from public.entity_engagement_events e
        join vids v on v.id = e.content_id
        where e.occurred_at > now() - make_interval(days => $${daysParam}::int)
        group by e.content_id
      )
      select
        v.id::text as id,
        v.title,
        v.thumb_url,
        v.media_type,
        v.created_at::text,
        v.hub_slug,
        coalesce(s.views, 0)::int as views,
        coalesce(s.watch_ms, 0)::bigint as watch_ms,
        coalesce(s.impressions, 0)::int as impressions,
        coalesce(s.clicks, 0)::int as clicks,
        coalesce(s.completes, 0)::int as completes,
        i.quality_score
      from vids v
      left join stats s on s.content_id = v.id
      left join public.recsys_item_stats i on i.content_id = v.id
      order by ${orderBy}
      limit $${limitParam}::int
      `,
      params
    );

    return rows.map((r) => ({
      id: r.id,
      title: r.title,
      thumbUrl: r.thumb_url,
      mediaType: r.media_type,
      createdAt: r.created_at,
      hubSlug: r.hub_slug,
      views: Number(r.views) || 0,
      watchMs: Number(r.watch_ms) || 0,
      impressions: Number(r.impressions) || 0,
      clicks: Number(r.clicks) || 0,
      ctr: ctr(Number(r.impressions) || 0, Number(r.clicks) || 0),
      completes: Number(r.completes) || 0,
      qualityScore:
        r.quality_score == null ? null : Number(r.quality_score) || 0,
    }));
  } catch (err) {
    console.warn('[studio] listStudioVideos failed', err);
    return [];
  }
}

async function loadVideoFunnel(
  videoId: string,
  days: number
): Promise<{
  impressions: number;
  clicks: number;
  views: number;
  completes: number;
  skips: number;
  likes: number;
  comments: number;
  watchMs: number;
}> {
  const k = await loadKpis('', [videoId], days);
  return k;
}

async function loadTrafficSources(
  videoId: string,
  days: number
): Promise<{ source: string; views: number }[]> {
  try {
    const { rows } = await pool.query<{ source: string; views: number }>(
      `
      select
        coalesce(nullif(trim(surface), ''), 'unknown') as source,
        count(*)::int as views
      from public.entity_engagement_events
      where content_id = $1::uuid
        and occurred_at > now() - make_interval(days => $2::int)
        and event_type in (
          'EngagementWatchPartial', 'watch_partial',
          'EngagementWatchComplete', 'watch_complete',
          'EngagementHubVideoOpened', 'hub_video_open',
          'EngagementScrollDwell', 'scroll_dwell'
        )
      group by 1
      order by views desc
      limit 12
      `,
      [videoId, days]
    );
    return rows.map((r) => ({
      source: r.source,
      views: Number(r.views) || 0,
    }));
  } catch {
    return [];
  }
}

async function loadRetentionBuckets(
  videoId: string,
  days: number
): Promise<{ bucket: number; reached: number }[]> {
  const buckets = [5, 10, 25, 50, 75, 95];
  try {
    const { rows } = await pool.query<{ progress: number }>(
      `
      select progress
      from public.entity_engagement_events
      where content_id = $1::uuid
        and occurred_at > now() - make_interval(days => $2::int)
        and progress is not null
        and progress > 0
      limit 20000
      `,
      [videoId, days]
    );
    if (!rows.length) return buckets.map((b) => ({ bucket: b, reached: 0 }));
    const total = rows.length;
    return buckets.map((b) => {
      const threshold = b / 100;
      const reached = rows.filter((r) => Number(r.progress) >= threshold).length;
      return {
        bucket: b,
        reached: Math.round((reached / total) * 1000) / 1000,
      };
    });
  } catch {
    return buckets.map((b) => ({ bucket: b, reached: 0 }));
  }
}
