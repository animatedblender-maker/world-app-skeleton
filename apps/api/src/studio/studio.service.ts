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

// ─── Earn (ledger + balances; withdrawals gated by STUDIO_PAYOUTS_LIVE) ───────

/** Stub RPM used only for clearly labeled estimates until ads revshare ships. */
const EARN_ESTIMATE_RPM_USD = 1.5;
const EARN_VIEWS_GATE = 1000;
const EARN_VIDEOS_GATE = 1;
const EARN_MIN_PAYOUT_USD = 50;
const EARN_MIN_PAYOUT_MINOR = EARN_MIN_PAYOUT_USD * 100;

export type StudioMonetizationState =
  | 'not_applied'
  | 'pending'
  | 'approved'
  | 'payouts_enabled'
  | 'rejected'
  | 'hold'
  | 'disabled';

export type StudioEarnChecklistItem = {
  id: string;
  label: string;
  met: boolean;
  detail: string;
};

export type StudioEarnPayoutRow = {
  id: string;
  amountUsd: number;
  currency: 'USD';
  state: string;
  createdAt: string;
  paidAt: string | null;
};

export type StudioEarnLedgerRow = {
  id: string;
  entryType: string;
  amountUsd: number;
  currency: 'USD';
  memo: string;
  createdAt: string;
};

export type StudioEarn = {
  range: StudioRange;
  rangeDays: number;
  channelId: string;
  /** True only when STUDIO_PAYOUTS_LIVE is enabled on the API. */
  payoutsLive: boolean;
  status:
    | 'preview'
    | 'on_track'
    | 'ready_when_live'
    | 'pending_review'
    | 'approved'
    | 'live'
    | 'hold';
  statusLabel: string;
  statusDetail: string;
  checklist: StudioEarnChecklistItem[];
  monetization: {
    state: StudioMonetizationState;
    canApply: boolean;
    appliedAt: string | null;
    minPayoutUsd: number;
  };
  balance: {
    currency: 'USD';
    availableUsd: number;
    pendingUsd: number;
    lifetimeEarnedUsd: number;
    lifetimePaidUsd: number;
  };
  payouts: StudioEarnPayoutRow[];
  ledger: StudioEarnLedgerRow[];
  metrics: {
    views: number;
    impressions: number;
    watchMs: number;
    watchHours: number;
    videos: number;
    promotedVideos: number;
    subscribers: number;
  };
  estimate: {
    currency: 'USD';
    /** Clearly an estimate — never present as a balance. */
    estimatedRevenueUsd: number;
    rpmUsd: number;
    basis: 'impressions' | 'views';
    label: string;
    disclaimer: string;
  };
  promotion: {
    disclosedCount: number;
    note: string;
  };
  ads: {
    path: string;
    label: string;
    detail: string;
  };
  note: string;
};

function studioPayoutsLive(): boolean {
  const v = String(process.env.STUDIO_PAYOUTS_LIVE ?? '')
    .trim()
    .toLowerCase();
  return v === '1' || v === 'true' || v === 'yes' || v === 'on';
}

function minorToUsd(minor: number): number {
  return Math.round((Number(minor) || 0)) / 100;
}

async function ensureEarnBalanceRow(channelId: string): Promise<void> {
  await pool.query(
    `
    insert into public.studio_earn_balances (channel_id)
    values ($1::uuid)
    on conflict (channel_id) do nothing
    `,
    [channelId]
  );
}

async function loadMonetization(
  channelId: string,
  ownerUserId: string
): Promise<{ state: StudioMonetizationState; appliedAt: string | null }> {
  try {
    const { rows } = await pool.query<{
      state: string;
      applied_at: string | null;
    }>(
      `
      select state, applied_at::text as applied_at
      from public.studio_creator_monetization
      where channel_id = $1::uuid
      limit 1
      `,
      [channelId]
    );
    const row = rows[0];
    if (!row) return { state: 'not_applied', appliedAt: null };
    const state = (row.state || 'not_applied') as StudioMonetizationState;
    return { state, appliedAt: row.applied_at };
  } catch (err: any) {
    // Table missing until migration applied — treat as not_applied.
    if (String(err?.message || '').includes('studio_creator_monetization')) {
      return { state: 'not_applied', appliedAt: null };
    }
    throw err;
  }
}

async function loadBalance(channelId: string): Promise<{
  availableUsd: number;
  pendingUsd: number;
  lifetimeEarnedUsd: number;
  lifetimePaidUsd: number;
}> {
  try {
    await ensureEarnBalanceRow(channelId);
    const { rows } = await pool.query<{
      available_minor: number;
      pending_minor: number;
      lifetime_earned_minor: number;
      lifetime_paid_minor: number;
    }>(
      `
      select available_minor, pending_minor, lifetime_earned_minor, lifetime_paid_minor
      from public.studio_earn_balances
      where channel_id = $1::uuid
      limit 1
      `,
      [channelId]
    );
    const row = rows[0];
    return {
      availableUsd: minorToUsd(row?.available_minor ?? 0),
      pendingUsd: minorToUsd(row?.pending_minor ?? 0),
      lifetimeEarnedUsd: minorToUsd(row?.lifetime_earned_minor ?? 0),
      lifetimePaidUsd: minorToUsd(row?.lifetime_paid_minor ?? 0),
    };
  } catch (err: any) {
    if (String(err?.message || '').includes('studio_earn_balances')) {
      return {
        availableUsd: 0,
        pendingUsd: 0,
        lifetimeEarnedUsd: 0,
        lifetimePaidUsd: 0,
      };
    }
    throw err;
  }
}

async function loadPayouts(channelId: string, limit = 20): Promise<StudioEarnPayoutRow[]> {
  try {
    const { rows } = await pool.query<{
      id: string;
      amount_minor: number;
      currency: string;
      state: string;
      created_at: string;
      paid_at: string | null;
    }>(
      `
      select id::text as id,
             amount_minor,
             currency,
             state,
             created_at::text as created_at,
             paid_at::text as paid_at
      from public.studio_earn_payouts
      where channel_id = $1::uuid
      order by created_at desc
      limit $2
      `,
      [channelId, limit]
    );
    return rows.map((r) => ({
      id: r.id,
      amountUsd: minorToUsd(r.amount_minor),
      currency: 'USD' as const,
      state: r.state,
      createdAt: r.created_at,
      paidAt: r.paid_at,
    }));
  } catch (err: any) {
    if (String(err?.message || '').includes('studio_earn_payouts')) return [];
    throw err;
  }
}

async function loadLedger(channelId: string, limit = 20): Promise<StudioEarnLedgerRow[]> {
  try {
    const { rows } = await pool.query<{
      id: string;
      entry_type: string;
      amount_minor: number;
      currency: string;
      memo: string;
      created_at: string;
    }>(
      `
      select id::text as id,
             entry_type,
             amount_minor,
             currency,
             coalesce(memo, '') as memo,
             created_at::text as created_at
      from public.studio_earn_ledger
      where channel_id = $1::uuid
      order by created_at desc
      limit $2
      `,
      [channelId, limit]
    );
    return rows.map((r) => ({
      id: r.id,
      entryType: r.entry_type,
      amountUsd: minorToUsd(r.amount_minor),
      currency: 'USD' as const,
      memo: r.memo || '',
      createdAt: r.created_at,
    }));
  } catch (err: any) {
    if (String(err?.message || '').includes('studio_earn_ledger')) return [];
    throw err;
  }
}

export async function getStudioEarn(
  userId: string,
  rangeRaw?: unknown
): Promise<StudioEarn | { error: string; status: number }> {
  const range = parseRange(rangeRaw);
  const days = rangeDays(range);
  const channel = await channels.myChannel(userId);
  if (!channel) return { error: 'channel_required', status: 404 };

  const videoIds = await loadChannelVideoIds(channel.id);
  const kpis = await loadKpis(channel.id, videoIds, days);
  const videoCount = channel.video_count ?? videoIds.length;
  const payoutsLive = studioPayoutsLive();

  let subscribers = 0;
  try {
    const { rows } = await pool.query<{ n: number }>(
      `select count(*)::int as n from public.user_follows where following_id = $1::uuid`,
      [channel.owner_user_id]
    );
    subscribers = Number(rows[0]?.n) || 0;
  } catch {
    subscribers = 0;
  }

  let promotedVideos = 0;
  try {
    const { rows } = await pool.query<{ n: number }>(
      `
      select count(*)::int as n
      from public.posts p
      where ${CHANNEL_VIDEO_WHERE}
        and coalesce(p.has_paid_promotion, false) = true
      `,
      [channel.id]
    );
    promotedVideos = Number(rows[0]?.n) || 0;
  } catch {
    promotedVideos = 0;
  }

  const views = kpis.views;
  const impressions = kpis.impressions;
  const watchMs = kpis.watchMs;
  const watchHours = Math.round((watchMs / 3_600_000) * 100) / 100;

  const hasChannel = true;
  const hasVideos = videoCount >= EARN_VIDEOS_GATE;
  const hasViews = views >= EARN_VIEWS_GATE;
  const guidelinesOk = true;
  const eligibilityMet = hasChannel && hasVideos && hasViews && guidelinesOk;

  const monetization = await loadMonetization(channel.id, channel.owner_user_id);
  const balance = await loadBalance(channel.id);
  const payouts = await loadPayouts(channel.id);
  const ledger = await loadLedger(channel.id);

  const payoutsOpen =
    payoutsLive &&
    (monetization.state === 'payouts_enabled' || monetization.state === 'approved');

  const checklist: StudioEarnChecklistItem[] = [
    {
      id: 'channel',
      label: 'Hubs channel',
      met: hasChannel,
      detail: 'You own a Matterya Hubs channel.',
    },
    {
      id: 'videos',
      label: 'Publish a Hubs video or Spark',
      met: hasVideos,
      detail: hasVideos
        ? `${videoCount} channel video${videoCount === 1 ? '' : 's'} live.`
        : 'Publish at least one Hubs video or Spark from your channel.',
    },
    {
      id: 'views',
      label: `${EARN_VIEWS_GATE.toLocaleString()} views in the selected range`,
      met: hasViews,
      detail: hasViews
        ? `${views.toLocaleString()} views in the last ${days} days.`
        : `${views.toLocaleString()} / ${EARN_VIEWS_GATE.toLocaleString()} views in the last ${days} days.`,
    },
    {
      id: 'guidelines',
      label: 'Follow Matterya guidelines',
      met: guidelinesOk,
      detail: 'Keep content safe for the community. Paid promotion and AI disclosures help.',
    },
    {
      id: 'application',
      label: 'Apply for Earn',
      met: monetization.state !== 'not_applied' && monetization.state !== 'rejected',
      detail:
        monetization.state === 'not_applied'
          ? 'Apply when you meet the checklist — Matterya reviews channel eligibility.'
          : monetization.state === 'pending'
            ? 'Application received — under review.'
            : monetization.state === 'rejected'
              ? 'Previous application was not approved. You can re-apply after fixing issues.'
              : `Monetization state: ${monetization.state}.`,
    },
    {
      id: 'payouts',
      label: 'Creator payouts open',
      met: payoutsOpen,
      detail: payoutsLive
        ? payoutsOpen
          ? 'Withdrawals are enabled for eligible balances.'
          : 'Payouts are open platform-wide; finish approval to withdraw.'
        : 'Platform withdrawals are not open yet. Balances and history are live from the ledger.',
    },
  ];

  let status: StudioEarn['status'] = 'preview';
  let statusLabel = 'Earn preview';
  let statusDetail =
    'Publish Hubs videos, grow views, and disclose paid promotion / AI content when relevant.';

  if (monetization.state === 'hold' || monetization.state === 'disabled') {
    status = 'hold';
    statusLabel = 'Earn on hold';
    statusDetail = 'Your Earn account is on hold. Contact support if you need a review.';
  } else if (monetization.state === 'pending') {
    status = 'pending_review';
    statusLabel = 'Application under review';
    statusDetail = 'We received your Earn application. Keep publishing while we review.';
  } else if (
    (monetization.state === 'approved' || monetization.state === 'payouts_enabled') &&
    payoutsLive
  ) {
    status = 'live';
    statusLabel = 'Earn is live';
    statusDetail =
      'Balances below are from the Studio ledger. Request a payout when you reach the minimum.';
  } else if (monetization.state === 'approved' || monetization.state === 'payouts_enabled') {
    status = 'approved';
    statusLabel = 'Approved — payouts opening soon';
    statusDetail =
      'Your channel is approved. Ledger balances are live; withdrawals open when Matterya enables payouts.';
  } else if (eligibilityMet) {
    status = 'ready_when_live';
    statusLabel = 'Ready to apply';
    statusDetail = 'You meet the early checklist. Apply for Earn to join the review queue.';
  } else if (hasVideos) {
    status = 'on_track';
    statusLabel = 'Building toward Earn';
    statusDetail = 'Keep publishing and growing views — Earn uses organic Hubs performance like this.';
  }

  const canApply =
    eligibilityMet &&
    (monetization.state === 'not_applied' || monetization.state === 'rejected');

  const basis: 'impressions' | 'views' = impressions > 0 ? 'impressions' : 'views';
  const basisCount = basis === 'impressions' ? impressions : views;
  const estimatedRevenueUsd =
    Math.round(((basisCount / 1000) * EARN_ESTIMATE_RPM_USD) * 100) / 100;

  return {
    range,
    rangeDays: days,
    channelId: channel.id,
    payoutsLive,
    status,
    statusLabel,
    statusDetail,
    checklist,
    monetization: {
      state: monetization.state,
      canApply,
      appliedAt: monetization.appliedAt,
      minPayoutUsd: EARN_MIN_PAYOUT_USD,
    },
    balance: {
      currency: 'USD',
      ...balance,
    },
    payouts,
    ledger,
    metrics: {
      views,
      impressions,
      watchMs,
      watchHours,
      videos: videoCount,
      promotedVideos,
      subscribers,
    },
    estimate: {
      currency: 'USD',
      estimatedRevenueUsd,
      rpmUsd: EARN_ESTIMATE_RPM_USD,
      basis,
      label: 'Estimated reach value (not a balance)',
      disclaimer:
        `Uses a $${EARN_ESTIMATE_RPM_USD.toFixed(2)} stub RPM on ${basis} for planning only. ` +
        'This is not money owed. Real balances come from the Studio ledger when ads revshare credits your channel.',
    },
    promotion: {
      disclosedCount: promotedVideos,
      note:
        promotedVideos > 0
          ? `${promotedVideos} video${promotedVideos === 1 ? '' : 's'} marked “Includes paid promotion”.`
          : 'When a video includes sponsorship, turn on “Includes paid promotion” in the Hubs composer.',
    },
    ads: {
      path: '/ads',
      label: 'Matterya Ads',
      detail: payoutsLive
        ? 'Run campaigns on Matterya Ads. Creator revshare credits appear in your Earn ledger.'
        : 'Run your own campaigns while creator withdrawals wait for payouts to open.',
    },
    note: payoutsLive
      ? 'Studio Earn ledger is live. Available balance can be withdrawn when you meet the minimum.'
      : 'Studio Earn ledger and balances are live (starting at $0). Withdrawals stay closed until STUDIO_PAYOUTS_LIVE is enabled.',
  };
}

export async function applyStudioEarn(
  userId: string
): Promise<
  | { ok: true; monetization: StudioEarn['monetization'] }
  | { error: string; status: number }
> {
  const channel = await channels.myChannel(userId);
  if (!channel) return { error: 'channel_required', status: 404 };

  const earn = await getStudioEarn(userId, '28d');
  if ('error' in earn) return earn;
  if (!earn.monetization.canApply) {
    return { error: 'not_eligible', status: 400 };
  }

  try {
    await pool.query(
      `
      insert into public.studio_creator_monetization (
        channel_id, owner_user_id, state, applied_at, updated_at
      )
      values ($1::uuid, $2::uuid, 'pending', now(), now())
      on conflict (channel_id) do update set
        state = 'pending',
        applied_at = now(),
        reviewed_at = null,
        updated_at = now()
      `,
      [channel.id, channel.owner_user_id]
    );
    await ensureEarnBalanceRow(channel.id);
  } catch (err: any) {
    const msg = String(err?.message || err);
    if (msg.includes('studio_creator_monetization')) {
      return { error: 'schema_missing', status: 503 };
    }
    throw err;
  }

  const refreshed = await getStudioEarn(userId, '28d');
  if ('error' in refreshed) return refreshed;
  return { ok: true, monetization: refreshed.monetization };
}

export async function requestStudioPayout(
  userId: string,
  body?: { amountUsd?: unknown; idempotencyKey?: unknown }
): Promise<
  | { ok: true; payout: StudioEarnPayoutRow }
  | { error: string; status: number; reason?: string }
> {
  if (!studioPayoutsLive()) {
    return {
      error: 'payouts_closed',
      status: 503,
      reason: 'Creator withdrawals are not open yet (STUDIO_PAYOUTS_LIVE).',
    };
  }

  const channel = await channels.myChannel(userId);
  if (!channel) return { error: 'channel_required', status: 404 };

  const monetization = await loadMonetization(channel.id, channel.owner_user_id);
  if (monetization.state === 'hold' || monetization.state === 'disabled') {
    return { error: 'on_hold', status: 403 };
  }
  if (monetization.state !== 'approved' && monetization.state !== 'payouts_enabled') {
    return { error: 'not_approved', status: 403 };
  }

  await ensureEarnBalanceRow(channel.id);
  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows: balRows } = await client.query<{ available_minor: number }>(
      `
      select available_minor
      from public.studio_earn_balances
      where channel_id = $1::uuid
      for update
      `,
      [channel.id]
    );
    const availableMinor = Number(balRows[0]?.available_minor) || 0;

    let amountMinor = availableMinor;
    if (body?.amountUsd != null && body.amountUsd !== '') {
      const usd = Number(body.amountUsd);
      if (!Number.isFinite(usd) || usd <= 0) {
        await client.query('rollback');
        return { error: 'invalid_amount', status: 400 };
      }
      amountMinor = Math.round(usd * 100);
    }

    if (amountMinor < EARN_MIN_PAYOUT_MINOR) {
      await client.query('rollback');
      return {
        error: 'below_minimum',
        status: 400,
        reason: `Minimum payout is $${EARN_MIN_PAYOUT_USD}.`,
      };
    }
    if (amountMinor > availableMinor) {
      await client.query('rollback');
      return { error: 'insufficient_balance', status: 400 };
    }

    const idem =
      String(body?.idempotencyKey ?? '').trim() ||
      `studio-payout:${channel.id}:${amountMinor}:${Date.now()}`;

    const { rows: payRows } = await client.query<{
      id: string;
      amount_minor: number;
      currency: string;
      state: string;
      created_at: string;
      paid_at: string | null;
    }>(
      `
      insert into public.studio_earn_payouts (
        channel_id, amount_minor, currency, state, idempotency_key
      )
      values ($1::uuid, $2, 'USD', 'pending', $3)
      on conflict (idempotency_key) do update set channel_id = excluded.channel_id
      returning id::text as id, amount_minor, currency, state,
                created_at::text as created_at, paid_at::text as paid_at
      `,
      [channel.id, amountMinor, idem]
    );

    await client.query(
      `
      update public.studio_earn_balances
      set available_minor = available_minor - $2,
          pending_minor = pending_minor + $2,
          updated_at = now()
      where channel_id = $1::uuid
      `,
      [channel.id, amountMinor]
    );

    await client.query(
      `
      insert into public.studio_earn_ledger (
        channel_id, entry_type, amount_minor, currency, memo, source_ref
      )
      values ($1::uuid, 'payout', $2, 'USD', 'Payout requested', $3)
      `,
      [channel.id, -amountMinor, `payout:${payRows[0].id}`]
    );

    if (monetization.state === 'approved') {
      await client.query(
        `
        update public.studio_creator_monetization
        set state = 'payouts_enabled', updated_at = now()
        where channel_id = $1::uuid
        `,
        [channel.id]
      );
    }

    await client.query('commit');
    const row = payRows[0];
    return {
      ok: true,
      payout: {
        id: row.id,
        amountUsd: minorToUsd(row.amount_minor),
        currency: 'USD',
        state: row.state,
        createdAt: row.created_at,
        paidAt: row.paid_at,
      },
    };
  } catch (err: any) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    const msg = String(err?.message || err);
    if (msg.includes('studio_earn_')) {
      return { error: 'schema_missing', status: 503 };
    }
    throw err;
  } finally {
    client.release();
  }
}

