import { randomUUID } from 'node:crypto';
import { pool } from '../db.js';
import { enqueueOutbox } from '../kafka/outbox.js';
import {
  ContentEventTypes,
  EngagementEventTypes,
  KafkaTopics,
  type ContentPostedPayload,
  type EngagementPayload,
} from '../kafka/types.js';

/** Client-facing event type → Kafka eventType + default strength */
const CLIENT_TYPES: Record<
  string,
  { eventType: string; defaultStrength: number; needsContent?: boolean }
> = {
  like: { eventType: EngagementEventTypes.Liked, defaultStrength: 0.55, needsContent: true },
  unlike: { eventType: EngagementEventTypes.Unliked, defaultStrength: -0.55, needsContent: true },
  comment: { eventType: EngagementEventTypes.Commented, defaultStrength: 0.85, needsContent: true },
  share: { eventType: EngagementEventTypes.Shared, defaultStrength: 0.75, needsContent: true },
  save: { eventType: EngagementEventTypes.Saved, defaultStrength: 0.7, needsContent: true },
  unsave: { eventType: EngagementEventTypes.Unsaved, defaultStrength: -0.4, needsContent: true },
  watch_partial: {
    eventType: EngagementEventTypes.WatchPartial,
    defaultStrength: 0.35,
    needsContent: true,
  },
  watch_complete: {
    eventType: EngagementEventTypes.WatchComplete,
    defaultStrength: 0.9,
    needsContent: true,
  },
  /** Stopped scrolling and looked at a post */
  scroll_dwell: {
    eventType: EngagementEventTypes.ScrollDwell,
    defaultStrength: 0.4,
    needsContent: true,
  },
  /** Scrolled past quickly */
  scroll_skip: {
    eventType: EngagementEventTypes.ScrollSkip,
    defaultStrength: -0.25,
    needsContent: true,
  },
  profile_open: { eventType: EngagementEventTypes.ProfileOpened, defaultStrength: 0.2 },
  person_follow: { eventType: EngagementEventTypes.PersonFollowed, defaultStrength: 0.7 },
  person_unfollow: { eventType: EngagementEventTypes.PersonUnfollowed, defaultStrength: -0.3 },
  hub_open: { eventType: EngagementEventTypes.HubOpened, defaultStrength: 0.35 },
  hub_leave: { eventType: EngagementEventTypes.HubLeft, defaultStrength: 0.1 },
  hub_shelf: { eventType: EngagementEventTypes.HubShelfSelected, defaultStrength: 0.3 },
  hub_video_open: {
    eventType: EngagementEventTypes.HubVideoOpened,
    defaultStrength: 0.55,
    needsContent: true,
  },
  screen_open: { eventType: EngagementEventTypes.ScreenOpened, defaultStrength: 0.05 },
  screen_leave: { eventType: EngagementEventTypes.ScreenLeft, defaultStrength: 0.05 },
  /** RecSys Phase 0 decision / exposure */
  impression: {
    eventType: EngagementEventTypes.Impression,
    defaultStrength: 0.15,
    needsContent: true,
  },
  ranked_served: {
    eventType: EngagementEventTypes.RankedServed,
    defaultStrength: 0.05,
  },
  viewport_visible: {
    eventType: EngagementEventTypes.ViewportVisible,
    defaultStrength: 0.25,
    needsContent: true,
  },
  hide: {
    eventType: EngagementEventTypes.Hide,
    defaultStrength: -0.85,
    needsContent: true,
  },
  not_interested: {
    eventType: EngagementEventTypes.NotInterested,
    defaultStrength: -0.7,
    needsContent: true,
  },
};

export type ClientEngagementEvent = {
  type: string;
  contentId?: string | null;
  authorId?: string | null;
  countryCode?: string | null;
  hubSlug?: string | null;
  mediaType?: string | null;
  isSpark?: boolean;
  strength?: number;
  durationMs?: number | null;
  progress?: number | null;
  surface?: string | null;
  deviceClass?: string | null;
  occurredAt?: string | null;
  meta?: Record<string, unknown> | null;
};

export type EngagementBatchInput = {
  entityId: string;
  sessionId?: string | null;
  events: ClientEngagementEvent[];
};

export type IngestResult = {
  accepted: number;
  rejected: number;
  eventIds: string[];
  kafkaTopic: string;
};

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

function resolveStrength(ev: ClientEngagementEvent, defaults: number): number {
  if (typeof ev.strength === 'number' && Number.isFinite(ev.strength)) {
    return clamp(ev.strength, -1, 1);
  }
  if (ev.type === 'watch_partial' && typeof ev.progress === 'number') {
    return clamp(0.15 + 0.75 * clamp(ev.progress, 0, 1), 0, 1);
  }
  if (ev.type === 'scroll_dwell' && typeof ev.durationMs === 'number') {
    return clamp(ev.durationMs / 8000, 0, 1);
  }
  return defaults;
}

/**
 * Persist engagement rows + enqueue Kafka outbox (same transaction).
 * After the outbox publisher runs (~500ms), messages appear on matterya.engagement.
 */
export async function ingestEngagementBatch(
  input: EngagementBatchInput
): Promise<IngestResult> {
  const entityId = String(input.entityId ?? '').trim();
  if (!entityId) throw new Error('entityId is required');

  const raw = Array.isArray(input.events) ? input.events : [];
  // Cap batch size — clients should flush often, not dump hours of telemetry.
  const slice = raw.slice(0, 100);
  const sessionId = input.sessionId ? String(input.sessionId).slice(0, 128) : null;

  let accepted = 0;
  let rejected = 0;
  const eventIds: string[] = [];

  const client = await pool.connect();
  try {
    await client.query('begin');

    for (const ev of slice) {
      const typeKey = String(ev?.type ?? '')
        .trim()
        .toLowerCase()
        .replace(/-/g, '_');
      const mapped = CLIENT_TYPES[typeKey];
      if (!mapped) {
        rejected += 1;
        continue;
      }

      const contentId = ev.contentId ? String(ev.contentId).trim() : null;
      if (mapped.needsContent && !contentId) {
        rejected += 1;
        continue;
      }

      const eventId = randomUUID();
      const strength = resolveStrength(ev, mapped.defaultStrength);
      const occurredAt = ev.occurredAt
        ? new Date(ev.occurredAt).toISOString()
        : new Date().toISOString();
      if (Number.isNaN(Date.parse(occurredAt))) {
        rejected += 1;
        continue;
      }

      const payload: EngagementPayload = {
        entityId,
        contentId,
        authorId: ev.authorId ? String(ev.authorId) : null,
        countryCode: ev.countryCode ? String(ev.countryCode).toUpperCase().slice(0, 8) : null,
        hubSlug: ev.hubSlug ? String(ev.hubSlug).slice(0, 64) : null,
        mediaType: ev.mediaType ? String(ev.mediaType).slice(0, 32) : null,
        isSpark: !!ev.isSpark,
        strength,
        durationMs:
          typeof ev.durationMs === 'number' && Number.isFinite(ev.durationMs)
            ? Math.max(0, Math.floor(ev.durationMs))
            : null,
        progress:
          typeof ev.progress === 'number' && Number.isFinite(ev.progress)
            ? clamp(ev.progress, 0, 1)
            : null,
        sessionId,
        surface: ev.surface ? String(ev.surface).slice(0, 32) : null,
        deviceClass: ev.deviceClass ? String(ev.deviceClass).slice(0, 16) : null,
        meta: ev.meta && typeof ev.meta === 'object' ? ev.meta : null,
      };

      try {
        await client.query(
          `
          insert into public.entity_engagement_events (
            event_id, event_type, entity_id, content_id, author_id,
            country_code, hub_slug, media_type, is_spark, strength,
            duration_ms, progress, surface, device_class, session_id, meta, occurred_at
          )
          values (
            $1, $2, $3, $4, $5,
            $6, $7, $8, $9, $10,
            $11, $12, $13, $14, $15, $16::jsonb, $17::timestamptz
          )
          on conflict (event_id) do nothing
          `,
          [
            eventId,
            mapped.eventType,
            entityId,
            contentId,
            payload.authorId,
            payload.countryCode,
            payload.hubSlug,
            payload.mediaType,
            payload.isSpark ?? false,
            strength,
            payload.durationMs,
            payload.progress,
            payload.surface,
            payload.deviceClass,
            sessionId,
            JSON.stringify(payload.meta ?? {}),
            occurredAt,
          ]
        );
      } catch (err: any) {
        // Table missing until migration — still publish to Kafka so live view works.
        if (err?.code !== '42P01') {
          console.warn('[engagement] insert failed', err?.message ?? err);
          rejected += 1;
          continue;
        }
      }

      await enqueueOutbox(client, {
        topic: KafkaTopics.ENGAGEMENT,
        partitionKey: entityId,
        eventType: mapped.eventType,
        eventId,
        producer: 'matterya-api-engagement',
        payload: payload as unknown as Record<string, unknown>,
      });

      eventIds.push(eventId);
      accepted += 1;
    }

    await client.query('commit');
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }

  return {
    accepted,
    rejected,
    eventIds,
    kafkaTopic: KafkaTopics.ENGAGEMENT,
  };
}

/**
 * Emit a content upload event the moment a post lands on the platform.
 * - Postgres `entity_engagement_events` (report Uploads tab)
 * - Kafka `matterya.posts` (ContentPosted) + `matterya.engagement` (live activity feed)
 */
export async function emitContentPosted(payload: ContentPostedPayload): Promise<void> {
  const entityId = String(payload.entityId ?? '').trim();
  const contentId = String(payload.contentId ?? '').trim();
  if (!entityId || !contentId) return;

  const client = await pool.connect();
  const eventId = randomUUID();
  const summary =
    payload.summary?.trim() ||
    `Someone uploaded ${payload.isSpark ? 'a Spark' : 'a post'} to Matterya`;
  const surface =
    payload.surface ??
    (payload.destination === 'hubs'
      ? 'hubs'
      : payload.destination === 'sparks'
        ? 'sparks'
        : payload.destination === 'share'
          ? 'feed'
          : 'feed');

  const engagementPayload: EngagementPayload = {
    entityId,
    contentId,
    authorId: payload.authorId ?? entityId,
    countryCode: payload.countryCode ?? null,
    hubSlug: payload.hubSlug ?? payload.channelName ?? null,
    mediaType: payload.mediaType ?? null,
    isSpark: !!payload.isSpark,
    strength: 1,
    surface,
    meta: {
      summary,
      destination: payload.destination ?? 'feed',
      title: payload.title ?? null,
      channelId: payload.channelId ?? null,
      channelName: payload.channelName ?? null,
      channelRole: payload.channelRole ?? null,
      countryName: payload.countryName ?? null,
      isHubLongForm: !!payload.isHubLongForm,
      isMoment: !!payload.isMoment,
      sharedPostId: payload.sharedPostId ?? null,
      mediaUrl: payload.mediaUrl ? String(payload.mediaUrl).slice(0, 400) : null,
    },
  };

  try {
    await client.query('begin');
    try {
      await client.query(
        `
        insert into public.entity_engagement_events (
          event_id, event_type, entity_id, content_id, author_id,
          country_code, hub_slug, media_type, is_spark, strength,
          duration_ms, progress, surface, device_class, session_id, meta, occurred_at
        )
        values (
          $1, $2, $3, $4, $5,
          $6, $7, $8, $9, $10,
          null, null, $11, $12, null, $13::jsonb, now()
        )
        on conflict (event_id) do nothing
        `,
        [
          eventId,
          ContentEventTypes.Posted,
          entityId,
          contentId,
          payload.authorId ?? entityId,
          payload.countryCode ?? null,
          payload.hubSlug ?? payload.channelName ?? null,
          payload.mediaType ?? null,
          !!payload.isSpark,
          1,
          surface,
          'server',
          JSON.stringify(engagementPayload.meta ?? {}),
        ]
      );
    } catch (err: any) {
      // Table missing — still try Kafka outbox.
      if (err?.code !== '42P01') throw err;
    }

    // Domain topic for content lifecycle (R2 sync / stats consumers).
    await enqueueOutbox(client, {
      topic: KafkaTopics.POSTS,
      partitionKey: contentId,
      eventType: ContentEventTypes.Posted,
      eventId,
      producer: 'matterya-api-posts',
      payload: { ...payload, summary } as unknown as Record<string, unknown>,
    });
    // Live activity topic (same console / report feed as likes & watches).
    await enqueueOutbox(client, {
      topic: KafkaTopics.ENGAGEMENT,
      partitionKey: entityId,
      eventType: ContentEventTypes.Posted,
      eventId: randomUUID(),
      producer: 'matterya-api-posts',
      payload: engagementPayload as unknown as Record<string, unknown>,
    });
    await client.query('commit');
    console.log(`[upload] ${summary}`);
  } catch (err) {
    await client.query('rollback');
    console.warn('[upload] emitContentPosted failed', err);
  } finally {
    client.release();
  }
}

/** Server-side emit for GraphQL likes/comments (same path → Kafka live feed). */
export async function emitServerEngagement(opts: {
  entityId: string;
  eventType: string;
  payload: EngagementPayload;
}): Promise<void> {
  const client = await pool.connect();
  const eventId = randomUUID();
  try {
    await client.query('begin');
    try {
      await client.query(
        `
        insert into public.entity_engagement_events (
          event_id, event_type, entity_id, content_id, author_id,
          country_code, hub_slug, media_type, is_spark, strength,
          duration_ms, progress, surface, device_class, session_id, meta, occurred_at
        )
        values (
          $1, $2, $3, $4, $5,
          $6, $7, $8, $9, $10,
          $11, $12, $13, $14, $15, $16::jsonb, now()
        )
        on conflict (event_id) do nothing
        `,
        [
          eventId,
          opts.eventType,
          opts.entityId,
          opts.payload.contentId ?? null,
          opts.payload.authorId ?? null,
          opts.payload.countryCode ?? null,
          opts.payload.hubSlug ?? null,
          opts.payload.mediaType ?? null,
          opts.payload.isSpark ?? false,
          opts.payload.strength,
          opts.payload.durationMs ?? null,
          opts.payload.progress ?? null,
          opts.payload.surface ?? 'api',
          opts.payload.deviceClass ?? null,
          opts.payload.sessionId ?? null,
          JSON.stringify(opts.payload.meta ?? {}),
        ]
      );
    } catch (err: any) {
      if (err?.code !== '42P01') throw err;
    }

    await enqueueOutbox(client, {
      topic: KafkaTopics.ENGAGEMENT,
      partitionKey: opts.entityId,
      eventType: opts.eventType,
      eventId,
      producer: 'matterya-api-graphql',
      payload: opts.payload as unknown as Record<string, unknown>,
    });
    await client.query('commit');
  } catch (err) {
    await client.query('rollback');
    console.warn('[engagement] emitServerEngagement failed', err);
  } finally {
    client.release();
  }
}

/** Plain-language labels for people (not eng jargon). */
export const ACTION_LABELS: Record<string, string> = {
  [EngagementEventTypes.Liked]: 'Liked a post',
  [EngagementEventTypes.Unliked]: 'Removed a like',
  [EngagementEventTypes.Commented]: 'Left a comment',
  [EngagementEventTypes.Shared]: 'Shared a post',
  [EngagementEventTypes.Saved]: 'Saved a post',
  [EngagementEventTypes.Unsaved]: 'Unsaved a post',
  [EngagementEventTypes.WatchPartial]: 'Watched part of a video',
  [EngagementEventTypes.WatchComplete]: 'Watched a video to the end',
  [EngagementEventTypes.ScrollDwell]: 'Stopped and looked at a post',
  [EngagementEventTypes.ScrollSkip]: 'Scrolled past a post',
  [EngagementEventTypes.ProfileOpened]: 'Opened a profile',
  [EngagementEventTypes.PersonFollowed]: 'Followed someone',
  [EngagementEventTypes.PersonUnfollowed]: 'Unfollowed someone',
  [EngagementEventTypes.HubOpened]: 'Opened Hubs',
  [EngagementEventTypes.HubLeft]: 'Left Hubs',
  [EngagementEventTypes.HubShelfSelected]: 'Browsed a Hubs category',
  [EngagementEventTypes.HubVideoOpened]: 'Opened a Hubs video',
  [EngagementEventTypes.ScreenOpened]: 'Opened a screen',
  [EngagementEventTypes.ScreenLeft]: 'Left a screen',
  [EngagementEventTypes.Impression]: 'Feed impression (ranked)',
  [EngagementEventTypes.RankedServed]: 'Ranking decision served',
  [EngagementEventTypes.ViewportVisible]: 'Post entered viewport',
  [EngagementEventTypes.Hide]: 'Hid a post',
  [EngagementEventTypes.NotInterested]: 'Not interested',
  [ContentEventTypes.Posted]: 'Uploaded content',
  [ContentEventTypes.Shared]: 'Shared content',
  [ContentEventTypes.Deleted]: 'Deleted content',
};

const SURFACE_LABELS: Record<string, string> = {
  home: 'Home feed',
  home_for_you: 'Home · For you',
  home_following: 'Home · Following',
  feed: 'Home feed',
  hubs: 'Matterya Hubs',
  hubs_for_you: 'Hubs · For you',
  reels: 'Sparks',
  sparks: 'Sparks',
  profile: 'Profile',
  search: 'Search',
  country: 'Country feed',
  api: 'App action',
  chat: 'Chat',
  server: 'Platform / backend',
  explore: 'Explore',
};

function actionLabel(eventType: string): string {
  return ACTION_LABELS[eventType] ?? eventType.replace(/^Engagement/, '').replace(/([A-Z])/g, ' $1').trim();
}

function surfaceLabel(surface: string | null | undefined): string {
  if (!surface) return '—';
  return SURFACE_LABELS[surface.toLowerCase()] ?? surface;
}

function formatWhen(iso: string | Date): { when: string; whenLocal: string; timestamp: string } {
  const d = typeof iso === 'string' ? new Date(iso) : iso;
  const timestamp = d.toISOString();
  // Human UTC + keep raw ISO for sorting/export
  const when = timestamp.replace('T', ' ').replace(/\.\d{3}Z$/, ' UTC');
  const whenLocal = d.toLocaleString('en-GB', {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
    timeZoneName: 'short',
  });
  return { when, whenLocal, timestamp };
}

function formatLookTime(durationMs: number | null | undefined): string | null {
  if (durationMs == null || !Number.isFinite(durationMs) || durationMs <= 0) return null;
  if (durationMs < 1000) return `${Math.round(durationMs)} ms`;
  const s = durationMs / 1000;
  if (s < 60) return `${s.toFixed(1)} seconds`;
  const m = Math.floor(s / 60);
  const rem = Math.round(s % 60);
  return `${m} min ${rem}s`;
}

export type ActivityRow = {
  /** Exact moment (ISO-8601 UTC) */
  timestamp: string;
  /** Readable UTC */
  when: string;
  /** Readable in server local timezone */
  whenLocal: string;
  /** What they did, in plain English */
  action: string;
  /** Internal event type (for Kafka matching) */
  actionCode: string;
  personId: string;
  personName: string | null;
  personUsername: string | null;
  postId: string | null;
  postPreview: string | null;
  where: string;
  lookTime: string | null;
  interest: string;
};

export type HumanEngagementReport = {
  title: string;
  summary: string;
  generatedAt: string;
  windowHours: number;
  totalInteractions: number;
  /** Counts of each action type, plain labels */
  activityBreakdown: { action: string; actionCode: string; count: number }[];
  /** People most active in this window */
  mostActivePeople: {
    personId: string;
    name: string | null;
    username: string | null;
    interactions: number;
  }[];
  /** Posts that got the most attention */
  mostViewedPosts: {
    postId: string;
    preview: string | null;
    interactions: number;
    averageInterest: string;
  }[];
  /** Stopped-and-looked stats */
  stoppedToLook: {
    times: number;
    averageLookTime: string;
  };
  /**
   * Every interaction in the window (newest first), each with a timestamp.
   * Cap protects the API; use limit query to page if needed later.
   */
  interactions: ActivityRow[];
  interactionCountReturned: number;
  /**
   * Every content upload in the window (feed / Spark / Hubs channel / share).
   * Powered by Kafka ContentPosted → entity_engagement_events.
   */
  uploads: UploadActivityRow[];
  uploadCount: number;
  /** Meta-style KPI strip (likes, shares, watches, …) */
  kpis: EngagementKpis;
  /**
   * Timeline buckets for the chart (hour or day depending on window).
   * `label` is short for the axis; `title` is full tooltip text.
   */
  hourly: { hour: string; count: number; label: string; title: string }[];
  /** Plain-English chart caption (peak time, total, bucket size). */
  timelineCaption: string;
  /** Breakdown by surface (home, hubs, sparks, …) */
  bySurface: { surface: string; count: number }[];
  /** Recent server ranking decisions (recsys warehouse) */
  rankDecisions: RankDecisionRow[];
  rankDecisionCount: number;
};

export type EngagementKpis = {
  uniquePeople: number;
  likes: number;
  unlikes: number;
  shares: number;
  saves: number;
  comments: number;
  watchesComplete: number;
  watchesPartial: number;
  dwells: number;
  skips: number;
  hides: number;
  notInterested: number;
  impressions: number;
  viewportVisible: number;
  follows: number;
  profileOpens: number;
  hubOpens: number;
  hubVideoOpens: number;
};

export type RankDecisionRow = {
  requestId: string;
  surface: string;
  policyVersion: string;
  servedCount: number;
  candidateCount: number;
  latencyMs: number | null;
  when: string;
  timestamp: string;
};

export type UploadActivityRow = {
  timestamp: string;
  when: string;
  whenLocal: string;
  /** Plain English: "Maya uploaded a Spark … from Germany" */
  summary: string;
  personId: string;
  personName: string | null;
  personUsername: string | null;
  postId: string | null;
  title: string | null;
  destination: string;
  where: string;
  country: string | null;
  channelName: string | null;
  mediaType: string | null;
  isSpark: boolean;
  isHubLongForm: boolean;
};

function emptyKpis(): EngagementKpis {
  return {
    uniquePeople: 0,
    likes: 0,
    unlikes: 0,
    shares: 0,
    saves: 0,
    comments: 0,
    watchesComplete: 0,
    watchesPartial: 0,
    dwells: 0,
    skips: 0,
    hides: 0,
    notInterested: 0,
    impressions: 0,
    viewportVisible: 0,
    follows: 0,
    profileOpens: 0,
    hubOpens: 0,
    hubVideoOpens: 0,
  };
}

function countType(
  byType: { event_type: string; count: string }[],
  ...codes: string[]
): number {
  const set = new Set(codes);
  return byType
    .filter((r) => set.has(r.event_type))
    .reduce((s, r) => s + Number(r.count), 0);
}

/** Build chart series with human labels + one-line caption (no overlapping numbers). */
function buildTimelineSeries(
  windowHours: number,
  rows: { hour: string; count: number }[]
): {
  hourly: { hour: string; count: number; label: string; title: string }[];
  timelineCaption: string;
} {
  const byDay = windowHours > 48;
  const unit = byDay ? 'day' : 'hour';

  const series = rows.map((r) => {
    const raw = String(r.hour || '');
    // hour keys: 2026-08-16T14:00:00Z or legacy "YYYY-MM-DD HH24:00"
    // day keys: 2026-08-16
    let d: Date | null = null;
    if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
      d = new Date(raw + 'T00:00:00Z');
    } else {
      const normalized = raw.includes('T')
        ? raw
        : raw.replace(' ', 'T').replace(/:00$/, ':00:00Z').replace(/(\d{2}):00$/, '$1:00:00Z');
      const tryD = new Date(normalized.endsWith('Z') ? normalized : normalized + 'Z');
      d = Number.isNaN(tryD.getTime()) ? null : tryD;
    }

    let label = raw;
    let title = `${raw} — ${r.count} signals`;
    if (d && !Number.isNaN(d.getTime())) {
      if (byDay) {
        label = d.toLocaleDateString('en-GB', {
          weekday: 'short',
          day: 'numeric',
          month: 'short',
          timeZone: 'UTC',
        });
        title = `${d.toLocaleDateString('en-GB', {
          weekday: 'long',
          day: 'numeric',
          month: 'long',
          year: 'numeric',
          timeZone: 'UTC',
        })} UTC — ${r.count} signals (likes, looks, watches, etc.)`;
      } else {
        label = d.toLocaleTimeString('en-GB', {
          hour: '2-digit',
          minute: '2-digit',
          hour12: false,
          timeZone: 'UTC',
        });
        title = `${d.toLocaleString('en-GB', {
          weekday: 'short',
          day: 'numeric',
          month: 'short',
          hour: '2-digit',
          minute: '2-digit',
          hour12: false,
          timeZone: 'UTC',
        })} UTC — ${r.count} signals in that hour`;
      }
    }

    return { hour: raw, count: r.count, label, title };
  });

  if (series.length === 0) {
    return {
      hourly: [],
      timelineCaption: byDay
        ? 'Each bar is one day. No activity in this window yet.'
        : 'Each bar is one hour. No activity in this window yet.',
    };
  }

  let peak = series[0];
  let total = 0;
  for (const s of series) {
    total += s.count;
    if (s.count > peak.count) peak = s;
  }

  const caption = byDay
    ? `Each bar = one day (UTC). Total ${total.toLocaleString()} signals. Busiest day: ${peak.label} (${peak.count}). Hover a bar for details.`
    : `Each bar = one hour (UTC). Total ${total.toLocaleString()} signals. Busiest hour: ${peak.label} (${peak.count}). Hover a bar for details.`;

  return { hourly: series, timelineCaption: caption };
}

export async function getEngagementReport(windowHours = 24): Promise<HumanEngagementReport> {
  // Allow up to 30 days for founder insights (was 7).
  const hours = Math.max(1, Math.min(720, windowHours));
  const generatedAt = new Date().toISOString();
  const empty: HumanEngagementReport = {
    title: 'Matterya Insights',
    summary: `No interactions recorded in the last ${hours} hours yet.`,
    generatedAt,
    windowHours: hours,
    totalInteractions: 0,
    activityBreakdown: [],
    mostActivePeople: [],
    mostViewedPosts: [],
    stoppedToLook: { times: 0, averageLookTime: '—' },
    interactions: [],
    interactionCountReturned: 0,
    uploads: [],
    uploadCount: 0,
    kpis: emptyKpis(),
    hourly: [],
    timelineCaption: '',
    bySurface: [],
    rankDecisions: [],
    rankDecisionCount: 0,
  };

  try {
    const intervalSql = `now() - make_interval(hours => $1::int)`;
    // Larger windows return fewer detail rows so filters stay snappy.
    const interactionLimit = hours <= 24 ? 600 : hours <= 168 ? 400 : 250;
    const uploadLimit = hours <= 24 ? 400 : 200;

    // All independent queries in parallel (was sequential waterfall).
    const [
      totalRes,
      byTypeRes,
      uniquePeopleRes,
      topPeopleRes,
      topPostsRes,
      lookRes,
      hourlyRes,
      surfaceRes,
      allInteractionsRes,
      uploadRes,
      rankRes,
    ] = await Promise.all([
      pool.query<{ n: string }>(
        `select count(*)::text as n from public.entity_engagement_events where occurred_at > ${intervalSql}`,
        [hours]
      ),
      pool.query<{ event_type: string; count: string }>(
        `
        select event_type, count(*)::text as count
        from public.entity_engagement_events
        where occurred_at > ${intervalSql}
        group by event_type
        order by count(*) desc
        `,
        [hours]
      ),
      pool.query<{ n: string }>(
        `
        select count(distinct entity_id)::text as n
        from public.entity_engagement_events
        where occurred_at > ${intervalSql}
        `,
        [hours]
      ),
      pool.query<{
        entity_id: string;
        count: string;
        display_name: string | null;
        username: string | null;
      }>(
        `
        select e.entity_id::text,
               count(*)::text as count,
               max(p.display_name) as display_name,
               max(p.username) as username
        from public.entity_engagement_events e
        left join public.profiles p on p.user_id = e.entity_id
        where e.occurred_at > ${intervalSql}
        group by e.entity_id
        order by count(*) desc
        limit 40
        `,
        [hours]
      ),
      pool.query<{
        content_id: string;
        count: string;
        avg_strength: string;
        preview: string | null;
      }>(
        `
        select e.content_id::text,
               count(*)::text as count,
               avg(e.strength)::text as avg_strength,
               max(
                 left(
                   coalesce(
                     nullif(trim(po.title), ''),
                     nullif(trim(regexp_replace(po.body, E'[\\n\\r]+', ' ', 'g')), ''),
                     nullif(trim(po.media_type), ''),
                     'Post ' || left(e.content_id::text, 8)
                   ),
                   140
                 )
               ) as preview
        from public.entity_engagement_events e
        left join public.posts po on po.id::text = e.content_id::text
        where e.occurred_at > ${intervalSql}
          and e.content_id is not null
        group by e.content_id
        order by count(*) desc
        limit 40
        `,
        [hours]
      ),
      pool.query<{ n: string; avg_ms: string }>(
        `
        select count(*)::text as n, coalesce(avg(duration_ms), 0)::text as avg_ms
        from public.entity_engagement_events
        where occurred_at > ${intervalSql}
          and event_type = $2
        `,
        [hours, EngagementEventTypes.ScrollDwell]
      ),
      // Short windows: per hour. Long windows: per day (readable chart, no 720 overlapping labels).
      pool.query<{ hour: string; count: string }>(
        hours <= 48
          ? `
        select to_char(date_trunc('hour', occurred_at at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:00:00"Z"') as hour,
               count(*)::text as count
        from public.entity_engagement_events
        where occurred_at > ${intervalSql}
        group by 1
        order by 1 asc
        `
          : `
        select to_char(date_trunc('day', occurred_at at time zone 'UTC'), 'YYYY-MM-DD') as hour,
               count(*)::text as count
        from public.entity_engagement_events
        where occurred_at > ${intervalSql}
        group by 1
        order by 1 asc
        `,
        [hours]
      ),
      pool.query<{ surface: string; count: string }>(
        `
        select coalesce(nullif(trim(surface), ''), '(unknown)') as surface,
               count(*)::text as count
        from public.entity_engagement_events
        where occurred_at > ${intervalSql}
        group by 1
        order by count(*) desc
        limit 20
        `,
        [hours]
      ),
      pool.query(
        `
        select e.event_id::text,
               e.event_type,
               e.entity_id::text,
               e.content_id::text,
               e.strength,
               e.duration_ms,
               e.surface,
               e.hub_slug,
               e.media_type,
               e.meta,
               e.occurred_at,
               p.display_name,
               p.username,
               left(
                 coalesce(
                   nullif(trim(po.title), ''),
                   nullif(trim(regexp_replace(coalesce(po.body, ''), E'[\\n\\r]+', ' ', 'g')), ''),
                   case when e.hub_slug is not null and e.hub_slug <> '' then 'Hub: ' || e.hub_slug end,
                   case when e.media_type is not null and e.media_type <> '' and e.media_type <> 'none'
                     then initcap(e.media_type) || ' post' end,
                   case when e.content_id is not null then 'Post ' || left(e.content_id::text, 8) end,
                   null
                 ),
                 120
               ) as post_preview
        from public.entity_engagement_events e
        left join public.profiles p on p.user_id = e.entity_id
        left join public.posts po on po.id::text = e.content_id::text
        where e.occurred_at > ${intervalSql}
        order by e.occurred_at desc
        limit ${interactionLimit}
        `,
        [hours]
      ),
      pool.query(
        `
        select e.event_id::text,
               e.entity_id::text,
               e.content_id::text,
               e.media_type,
               e.is_spark,
               e.surface,
               e.country_code,
               e.hub_slug,
               e.meta,
               e.occurred_at,
               p.display_name,
               p.username,
               po.title as post_title
        from public.entity_engagement_events e
        left join public.profiles p on p.user_id = e.entity_id
        left join public.posts po on po.id::text = e.content_id::text
        where e.occurred_at > ${intervalSql}
          and e.event_type = $2
        order by e.occurred_at desc
        limit ${uploadLimit}
        `,
        [hours, ContentEventTypes.Posted]
      ),
      pool
        .query<{
          request_id: string;
          surface: string;
          policy_version: string;
          served_count: number;
          candidate_count: number;
          latency_ms: number | null;
          created_at: Date;
        }>(
          `
          select request_id, surface, policy_version, served_count, candidate_count, latency_ms, created_at
          from public.recommendation_decisions
          where created_at > ${intervalSql}
          order by created_at desc
          limit 100
          `,
          [hours]
        )
        .catch(() => ({ rows: [] as any[] })),
    ]);

    const totalRows = totalRes.rows;
    const byType = byTypeRes.rows;
    const uniquePeopleRows = uniquePeopleRes.rows;
    const topPeople = topPeopleRes.rows;
    const topPosts = topPostsRes.rows;
    const lookRows = lookRes.rows;
    const hourlyRows = hourlyRes.rows;
    const surfaceRows = surfaceRes.rows;
    const allInteractions = allInteractionsRes.rows;
    const uploadRows = uploadRes.rows;
    const rankRows = rankRes.rows;

    const total = Number(totalRows[0]?.n ?? 0);
    const lookTimes = Number(lookRows[0]?.n ?? 0);
    const avgLookMs = Number(lookRows[0]?.avg_ms ?? 0);

    const rankDecisions: RankDecisionRow[] = rankRows.map((r) => {
      const t = formatWhen(r.created_at);
      return {
        requestId: r.request_id,
        surface: r.surface,
        policyVersion: r.policy_version,
        servedCount: Number(r.served_count) || 0,
        candidateCount: Number(r.candidate_count) || 0,
        latencyMs: r.latency_ms != null ? Number(r.latency_ms) : null,
        when: t.when,
        timestamp: t.timestamp,
      };
    });

    const kpis: EngagementKpis = {
      uniquePeople: Number(uniquePeopleRows[0]?.n ?? 0),
      likes: countType(byType, EngagementEventTypes.Liked),
      unlikes: countType(byType, EngagementEventTypes.Unliked),
      shares: countType(byType, EngagementEventTypes.Shared),
      saves: countType(byType, EngagementEventTypes.Saved),
      comments: countType(byType, EngagementEventTypes.Commented),
      watchesComplete: countType(byType, EngagementEventTypes.WatchComplete),
      watchesPartial: countType(byType, EngagementEventTypes.WatchPartial),
      dwells: countType(byType, EngagementEventTypes.ScrollDwell),
      skips: countType(byType, EngagementEventTypes.ScrollSkip),
      hides: countType(byType, EngagementEventTypes.Hide),
      notInterested: countType(byType, EngagementEventTypes.NotInterested),
      impressions: countType(byType, EngagementEventTypes.Impression),
      viewportVisible: countType(byType, EngagementEventTypes.ViewportVisible),
      follows: countType(byType, EngagementEventTypes.PersonFollowed),
      profileOpens: countType(byType, EngagementEventTypes.ProfileOpened),
      hubOpens: countType(byType, EngagementEventTypes.HubOpened),
      hubVideoOpens: countType(byType, EngagementEventTypes.HubVideoOpened),
    };

    const interactions: ActivityRow[] = allInteractions.map((r: any) => {
      const t = formatWhen(r.occurred_at);
      const interest = Number(r.strength);
      let interestLabel = 'Neutral';
      if (interest >= 0.7) interestLabel = 'Strong interest';
      else if (interest >= 0.35) interestLabel = 'Interest';
      else if (interest > 0) interestLabel = 'Mild interest';
      else if (interest < 0) interestLabel = 'Low interest / passed by';

      const meta = (r.meta && typeof r.meta === 'object' ? r.meta : {}) as Record<string, unknown>;
      const summaryPreview =
        typeof meta.summary === 'string' && meta.summary.trim()
          ? meta.summary.trim()
          : r.post_preview ?? null;

      return {
        timestamp: t.timestamp,
        when: t.when,
        whenLocal: t.whenLocal,
        action: actionLabel(r.event_type),
        actionCode: r.event_type,
        personId: r.entity_id,
        personName: r.display_name ?? null,
        personUsername: r.username ?? null,
        postId: r.content_id,
        postPreview: summaryPreview,
        where: surfaceLabel(r.surface),
        lookTime: formatLookTime(r.duration_ms != null ? Number(r.duration_ms) : null),
        interest: interestLabel,
      };
    });

    const uploads: UploadActivityRow[] = uploadRows.map((r: any) => {
      const t = formatWhen(r.occurred_at);
      const meta = (r.meta && typeof r.meta === 'object' ? r.meta : {}) as Record<string, unknown>;
      const summary =
        typeof meta.summary === 'string' && meta.summary.trim()
          ? meta.summary.trim()
          : `${r.display_name || r.username || 'Someone'} uploaded content`;
      const countryName =
        typeof meta.countryName === 'string' && meta.countryName.trim()
          ? meta.countryName.trim()
          : r.country_code
            ? String(r.country_code).toUpperCase()
            : null;
      return {
        timestamp: t.timestamp,
        when: t.when,
        whenLocal: t.whenLocal,
        summary,
        personId: r.entity_id,
        personName: r.display_name ?? null,
        personUsername: r.username ?? null,
        postId: r.content_id,
        title:
          (typeof meta.title === 'string' && meta.title.trim()) ||
          (r.post_title ? String(r.post_title).trim() : null) ||
          null,
        destination: String(meta.destination ?? r.surface ?? 'feed'),
        where: surfaceLabel(r.surface),
        country: countryName,
        channelName:
          typeof meta.channelName === 'string' && meta.channelName.trim()
            ? meta.channelName.trim()
            : r.hub_slug
              ? String(r.hub_slug)
              : null,
        mediaType: r.media_type ?? null,
        isSpark: !!r.is_spark || meta.destination === 'sparks',
        isHubLongForm: !!meta.isHubLongForm,
      };
    });

    const summaryParts = [
      `${total.toLocaleString()} signals · ${kpis.uniquePeople} people · last ${hours}h.`,
    ];
    if (kpis.likes || kpis.shares || kpis.dwells) {
      summaryParts.push(
        `${kpis.likes} likes · ${kpis.shares} shares · ${kpis.dwells} looks · ${kpis.watchesComplete} full watches.`
      );
    }
    if (uploads.length > 0) {
      summaryParts.push(`${uploads.length} uploads.`);
    }

    return {
      title: 'Matterya Insights',
      summary: summaryParts.join(' '),
      generatedAt,
      windowHours: hours,
      totalInteractions: total,
      activityBreakdown: byType.map((r) => ({
        action: actionLabel(r.event_type),
        actionCode: r.event_type,
        count: Number(r.count),
      })),
      mostActivePeople: topPeople.map((r) => ({
        personId: r.entity_id,
        name: r.display_name,
        username: r.username,
        interactions: Number(r.count),
      })),
      mostViewedPosts: topPosts.map((r) => ({
        postId: r.content_id,
        preview: r.preview,
        interactions: Number(r.count),
        averageInterest: Number(r.avg_strength).toFixed(2),
      })),
      stoppedToLook: {
        times: lookTimes,
        averageLookTime: formatLookTime(avgLookMs) ?? '—',
      },
      interactions,
      interactionCountReturned: interactions.length,
      uploads,
      uploadCount: uploads.length,
      kpis,
      ...buildTimelineSeries(
        hours,
        hourlyRows.map((r) => ({ hour: r.hour, count: Number(r.count) }))
      ),
      bySurface: surfaceRows.map((r) => ({
        surface: r.surface,
        count: Number(r.count),
      })),
      rankDecisions,
      rankDecisionCount: rankDecisions.length,
    };
  } catch (err: any) {
    if (err?.code === '42P01') {
      return {
        ...empty,
        summary:
          'Activity tables are not installed yet. Run the engagement migration on Supabase, then interactions will appear here with timestamps.',
      };
    }
    throw err;
  }
}

/** Meta-style Insights dashboard — extensive, responsive, founder-friendly. */
export function renderEngagementReportHtml(report: HumanEngagementReport): string {
  const esc = (s: unknown) =>
    String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');

  const k = report.kpis ?? emptyKpis();
  const hours = report.windowHours;
  const ranges = [
    { h: 1, label: '1h' },
    { h: 6, label: '6h' },
    { h: 24, label: '24h' },
    { h: 72, label: '3d' },
    { h: 168, label: '7d' },
    { h: 720, label: '30d' },
  ];
  const rangeBtns = ranges
    .map(
      (r) =>
        `<button type="button" class="range-btn${r.h === hours ? ' active' : ''}" data-hours="${r.h}">${esc(r.label)}</button>`
    )
    .join('');

  const maxHour = Math.max(1, ...report.hourly.map((h) => h.count));
  const nBars = report.hourly.length;
  // Label every Nth bar so axis stays readable (never print counts on every bar).
  const labelEvery = nBars <= 8 ? 1 : nBars <= 16 ? 2 : nBars <= 32 ? 4 : Math.ceil(nBars / 8);
  const bars = report.hourly
    .map((h, i) => {
      const pct = Math.max(3, Math.round((h.count / maxHour) * 100));
      const showLabel = i === 0 || i === nBars - 1 || i % labelEvery === 0;
      const title = esc(h.title || `${h.label}: ${h.count} signals`);
      return `<div class="bar-col" title="${title}" data-count="${esc(h.count)}" data-label="${esc(h.label)}">
        <div class="bar" style="height:${pct}%"></div>
        <span class="bar-label">${showLabel ? esc(h.label) : ''}</span>
      </div>`;
    })
    .join('');
  const timelineCaption = esc(
    report.timelineCaption ||
      'Each bar is a time bucket. Hover to see how many signals happened then.'
  );

  const kpi = (
    label: string,
    value: number | string,
    hint?: string
  ) =>
    `<div class="kpi"><div class="kpi-v">${esc(value)}</div><div class="kpi-l">${esc(label)}</div>${
      hint ? `<div class="kpi-h">${esc(hint)}</div>` : ''
    }</div>`;

  const breakdown = report.activityBreakdown
    .map((r) => {
      const pct =
        report.totalInteractions > 0
          ? Math.round((r.count / report.totalInteractions) * 100)
          : 0;
      return `<div class="breakdown-row">
        <div class="br-label">${esc(r.action)}</div>
        <div class="br-track"><div class="br-fill" style="width:${pct}%"></div></div>
        <div class="br-count">${esc(r.count)}</div>
      </div>`;
    })
    .join('');

  const surfaceRows = report.bySurface
    .map(
      (s) =>
        `<tr><td>${esc(s.surface)}</td><td class="num">${esc(s.count)}</td></tr>`
    )
    .join('');

  const people = report.mostActivePeople
    .map((p, i) => {
      const name = p.name || p.username || p.personId.slice(0, 8) + '…';
      const handle = p.username ? '@' + p.username : '—';
      return `<tr>
        <td class="num muted">${i + 1}</td>
        <td><div class="person"><span class="avatar">${esc(name.slice(0, 1).toUpperCase())}</span>
          <div><strong>${esc(name)}</strong><div class="muted small">${esc(handle)}</div></div></div></td>
        <td class="num">${esc(p.interactions)}</td>
      </tr>`;
    })
    .join('');

  const posts = report.mostViewedPosts
    .map(
      (p, i) => `<tr>
        <td class="num muted">${i + 1}</td>
        <td>${esc(p.preview || p.postId.slice(0, 10) + '…')}</td>
        <td class="num">${esc(p.interactions)}</td>
        <td class="num">${esc(p.averageInterest)}</td>
      </tr>`
    )
    .join('');

  const rows = report.interactions
    .map(
      (i) => `<tr data-search="${esc(
        [i.action, i.personName, i.personUsername, i.postPreview, i.where, i.actionCode]
          .filter(Boolean)
          .join(' ')
          .toLowerCase()
      )}">
      <td class="nowrap">${esc(i.when)}</td>
      <td><span class="pill">${esc(i.action)}</span></td>
      <td>${esc(i.personName || i.personUsername || i.personId.slice(0, 8) + '…')}</td>
      <td class="clip">${esc(i.postPreview || (i.postId ? i.postId.slice(0, 8) + '…' : '—'))}</td>
      <td>${esc(i.where)}</td>
      <td>${esc(i.lookTime || '—')}</td>
      <td class="muted small">${esc(i.interest)}</td>
    </tr>`
    )
    .join('');

  const uploadRows = (report.uploads ?? [])
    .map(
      (u) => `<tr>
      <td class="nowrap">${esc(u.when)}</td>
      <td>${esc(u.summary)}</td>
      <td>${esc(u.personName || u.personUsername || (u.personId ? u.personId.slice(0, 8) + '…' : '—'))}</td>
      <td class="clip">${esc(u.title || '—')}</td>
      <td>${esc(u.where)}</td>
      <td>${esc(u.country || '—')}</td>
      <td>${esc(u.channelName || '—')}</td>
      <td>${esc(u.mediaType || '—')}</td>
    </tr>`
    )
    .join('');

  const rankRows = (report.rankDecisions ?? [])
    .map(
      (r) => `<tr>
      <td class="nowrap">${esc(r.when)}</td>
      <td>${esc(r.surface)}</td>
      <td class="muted small">${esc(r.policyVersion)}</td>
      <td class="num">${esc(r.servedCount)}</td>
      <td class="num">${esc(r.candidateCount)}</td>
      <td class="num">${esc(r.latencyMs ?? '—')}${r.latencyMs != null ? ' ms' : ''}</td>
      <td class="muted small clip">${esc(r.requestId.slice(0, 12))}…</td>
    </tr>`
    )
    .join('');

  const reportJson = esc(JSON.stringify(report));

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
  <title>${esc(report.title)}</title>
  <style>
    :root {
      --bg: #0f0f10;
      --bg2: #18181b;
      --panel: #1f1f23;
      --panel2: #27272a;
      --border: #3f3f46;
      --text: #fafafa;
      --muted: #a1a1aa;
      --accent: #1877f2;
      --accent2: #e4a853;
      --good: #22c55e;
      --warn: #f59e0b;
      --bad: #ef4444;
      --radius: 14px;
      --font: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; min-height: 100%; background: var(--bg); color: var(--text); font-family: var(--font); }
    a { color: inherit; text-decoration: none; }
    button, input { font: inherit; }
    .shell { display: grid; grid-template-columns: 240px 1fr; min-height: 100vh; }
    @media (max-width: 960px) {
      .shell { grid-template-columns: 1fr; }
      .sidebar { position: sticky; top: 0; z-index: 40; border-right: 0; border-bottom: 1px solid var(--border); }
      .nav { display: flex; flex-wrap: wrap; gap: 4px; }
      .nav button { flex: 1 1 auto; }
    }
    .sidebar {
      background: var(--bg2); border-right: 1px solid var(--border);
      padding: 18px 14px 24px; display: flex; flex-direction: column; gap: 18px;
    }
    .brand { display: flex; align-items: center; gap: 10px; padding: 4px 8px; }
    .brand-mark {
      width: 36px; height: 36px; border-radius: 10px; background: linear-gradient(135deg,#1877f2,#e4a853);
      display: grid; place-items: center; font-weight: 800; font-size: 14px;
    }
    .brand h1 { margin: 0; font-size: 15px; font-weight: 700; letter-spacing: -0.02em; }
    .brand p { margin: 2px 0 0; color: var(--muted); font-size: 11px; }
    .nav { display: flex; flex-direction: column; gap: 4px; }
    .nav button {
      appearance: none; border: 0; background: transparent; color: var(--muted);
      text-align: left; padding: 10px 12px; border-radius: 10px; cursor: pointer; font-weight: 600; font-size: 13px;
    }
    .nav button:hover { background: var(--panel); color: var(--text); }
    .nav button.active { background: rgba(24,119,242,0.18); color: #fff; }
    .side-actions { margin-top: auto; display: flex; flex-direction: column; gap: 8px; }
    .btn {
      display: inline-flex; align-items: center; justify-content: center; gap: 8px;
      border-radius: 999px; border: 1px solid var(--border); background: var(--panel);
      color: var(--text); padding: 10px 14px; font-weight: 650; font-size: 13px; cursor: pointer;
    }
    .btn:hover { border-color: #71717a; }
    .btn.primary { background: var(--accent); border-color: transparent; color: #fff; }
    .btn.ghost { background: transparent; }
    .main { padding: 18px 18px 40px; max-width: 1400px; }
    .topbar {
      display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px;
      margin-bottom: 16px;
    }
    .topbar h2 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -0.03em; }
    .topbar .sub { margin: 4px 0 0; color: var(--muted); font-size: 13px; max-width: 48rem; line-height: 1.4; }
    .ranges { display: flex; flex-wrap: wrap; gap: 6px; }
    .range-btn {
      appearance: none; cursor: pointer;
      padding: 8px 12px; border-radius: 999px; border: 1px solid var(--border);
      background: var(--panel); color: var(--muted); font-size: 12px; font-weight: 700;
      transition: background .12s ease, color .12s ease, transform .08s ease, opacity .12s ease;
    }
    .range-btn:hover { background: #2a2a2e; color: #fff; }
    .range-btn.active { background: #fff; color: #111; border-color: #fff; }
    .range-btn:active { transform: scale(0.96); }
    .range-btn:disabled { opacity: 0.45; cursor: wait; }
    .main.is-loading { opacity: 0.55; pointer-events: none; transition: opacity .12s ease; }
    .loading-dot {
      display: none; width: 8px; height: 8px; border-radius: 50%; background: var(--accent);
      animation: pulse 0.7s ease infinite alternate; margin-left: 8px;
    }
    .main.is-loading .loading-dot { display: inline-block; }
    @keyframes pulse { from { opacity: 0.35; } to { opacity: 1; } }
    .kpi-grid {
      display: grid; grid-template-columns: repeat(auto-fill, minmax(132px, 1fr)); gap: 10px; margin: 14px 0 18px;
    }
    .kpi {
      background: linear-gradient(180deg, var(--panel) 0%, var(--bg2) 100%);
      border: 1px solid var(--border); border-radius: var(--radius); padding: 14px 14px 12px;
    }
    .kpi-v { font-size: 1.45rem; font-weight: 750; letter-spacing: -0.03em; font-variant-numeric: tabular-nums; }
    .kpi-l { margin-top: 4px; color: var(--muted); font-size: 12px; font-weight: 600; }
    .kpi-h { margin-top: 2px; color: #71717a; font-size: 11px; }
    .grid-2 { display: grid; grid-template-columns: 1.4fr 1fr; gap: 12px; }
    @media (max-width: 900px) { .grid-2 { grid-template-columns: 1fr; } }
    .card {
      background: var(--panel); border: 1px solid var(--border); border-radius: var(--radius); padding: 14px 16px 16px;
    }
    .card h3 { margin: 0 0 8px; font-size: 13px; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; color: var(--muted); }
    .chart-caption { margin: 0 0 12px; color: var(--muted); font-size: 12px; line-height: 1.45; max-width: 40rem; }
    .chart-tip {
      min-height: 1.35em; margin: 0 0 8px; font-size: 12px; font-weight: 600; color: #e4e4e7;
      font-variant-numeric: tabular-nums;
    }
    .chart-tip:empty::before { content: 'Hover a bar to see when and how many signals.'; color: var(--muted); font-weight: 500; }
    .bars {
      display: flex; align-items: flex-end; gap: 4px; height: 140px; padding: 8px 4px 0;
      overflow-x: auto; border-bottom: 1px solid var(--border);
    }
    .bar-col {
      flex: 1 1 0; min-width: 14px; max-width: 48px; height: 100%;
      display: flex; flex-direction: column; justify-content: flex-end; align-items: center; gap: 6px;
      cursor: default;
    }
    .bar {
      width: 70%; max-width: 28px; background: linear-gradient(180deg, #4dabff, #1877f2);
      border-radius: 5px 5px 2px 2px; min-height: 3px; transition: filter .12s ease, opacity .12s ease;
    }
    .bar-col:hover .bar { filter: brightness(1.15); }
    .bar-label {
      height: 28px; font-size: 10px; line-height: 1.15; color: var(--muted); text-align: center;
      white-space: pre-line; max-width: 100%; overflow: hidden;
    }
    .breakdown-row { display: grid; grid-template-columns: 1fr 2fr 48px; gap: 8px; align-items: center; margin-bottom: 8px; font-size: 12px; }
    .br-label { color: var(--text); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .br-track { height: 8px; background: var(--bg); border-radius: 99px; overflow: hidden; }
    .br-fill { height: 100%; background: var(--accent2); border-radius: 99px; }
    .br-count { text-align: right; font-variant-numeric: tabular-nums; color: var(--muted); font-weight: 650; }
    .panel { display: none; }
    .panel.active { display: block; }
    .toolbar { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; margin: 0 0 12px; }
    .search {
      flex: 1 1 220px; min-width: 180px; background: var(--bg); border: 1px solid var(--border);
      border-radius: 999px; padding: 10px 14px; color: var(--text);
    }
    .search:focus { outline: 2px solid rgba(24,119,242,0.35); border-color: var(--accent); }
    .table-wrap { overflow: auto; border: 1px solid var(--border); border-radius: var(--radius); background: var(--bg2); max-height: min(70vh, 820px); }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid #2a2a2e; vertical-align: top; }
    th { position: sticky; top: 0; background: #232327; z-index: 1; color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; }
    tr:hover td { background: rgba(255,255,255,0.03); }
    .num { text-align: right; font-variant-numeric: tabular-nums; }
    .nowrap { white-space: nowrap; font-variant-numeric: tabular-nums; }
    .clip { max-width: 280px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .muted { color: var(--muted); }
    .small { font-size: 11px; }
    .pill {
      display: inline-block; padding: 3px 8px; border-radius: 999px; background: rgba(24,119,242,0.15);
      color: #93c5fd; font-size: 11px; font-weight: 700;
    }
    .person { display: flex; align-items: center; gap: 10px; }
    .avatar {
      width: 32px; height: 32px; border-radius: 50%; background: #3f3f46; display: grid; place-items: center;
      font-weight: 800; font-size: 12px; flex: 0 0 auto;
    }
    .foot { margin-top: 20px; color: #71717a; font-size: 11px; }
    .empty { padding: 28px; text-align: center; color: var(--muted); }
  </style>
</head>
<body>
  <div class="shell">
    <aside class="sidebar">
      <div class="brand">
        <div class="brand-mark">M</div>
        <div>
          <h1>Insights</h1>
          <p>Live platform intelligence</p>
        </div>
      </div>
      <nav class="nav" role="tablist">
        <button type="button" class="active" data-tab="overview">Overview</button>
        <button type="button" data-tab="activity">Activity feed</button>
        <button type="button" data-tab="content">Top content</button>
        <button type="button" data-tab="people">People</button>
        <button type="button" data-tab="uploads">Uploads</button>
        <button type="button" data-tab="ranking">Ranking</button>
      </nav>
      <div class="side-actions">
        <button type="button" class="btn primary" id="btn-refresh">Refresh data</button>
        <button type="button" class="btn" id="btn-export">Export JSON</button>
        <a class="btn ghost" href="/reports/logout">Log out</a>
      </div>
    </aside>

    <main class="main">
      <div class="topbar">
        <div>
          <h2 id="insights-title">${esc(report.title)} <span class="loading-dot" aria-hidden="true"></span></h2>
          <p class="sub" id="insights-summary">${esc(report.summary)}</p>
        </div>
        <div class="ranges" id="range-bar" title="Time window">${rangeBtns}</div>
      </div>

      <div class="kpi-grid" id="kpi-grid">
        ${kpi('Total signals', report.totalInteractions.toLocaleString())}
        ${kpi('People', k.uniquePeople.toLocaleString(), 'unique actors')}
        ${kpi('Likes', k.likes.toLocaleString())}
        ${kpi('Shares', k.shares.toLocaleString())}
        ${kpi('Saves', k.saves.toLocaleString())}
        ${kpi('Comments', k.comments.toLocaleString())}
        ${kpi('Looks', k.dwells.toLocaleString(), 'stopped to read')}
        ${kpi('Skips', k.skips.toLocaleString())}
        ${kpi('Full watches', k.watchesComplete.toLocaleString())}
        ${kpi('Partial watches', k.watchesPartial.toLocaleString())}
        ${kpi('Impressions', k.impressions.toLocaleString())}
        ${kpi('In viewport', k.viewportVisible.toLocaleString())}
        ${kpi('Hides', k.hides.toLocaleString())}
        ${kpi('Not interested', k.notInterested.toLocaleString())}
        ${kpi('Follows', k.follows.toLocaleString())}
        ${kpi('Profile opens', k.profileOpens.toLocaleString())}
        ${kpi('Hub opens', k.hubOpens.toLocaleString())}
        ${kpi('Hub videos', k.hubVideoOpens.toLocaleString())}
        ${kpi('Uploads', (report.uploadCount ?? 0).toLocaleString())}
        ${kpi('Avg look', report.stoppedToLook.averageLookTime)}
      </div>

      <section id="panel-overview" class="panel active">
        <div class="grid-2">
          <div class="card" id="timeline-card">
            <h3>Activity over time</h3>
            <p class="chart-caption" id="timeline-caption">${timelineCaption}</p>
            <p class="chart-tip" id="timeline-tip" aria-live="polite"></p>
            <div class="bars" id="timeline-bars">${bars || '<div class="empty">No activity in this period yet</div>'}</div>
          </div>
          <div class="card">
            <h3>What people did</h3>
            ${breakdown || '<div class="empty">No breakdown yet — use the app</div>'}
          </div>
        </div>
        <div class="grid-2" style="margin-top:12px">
          <div class="card">
            <h3>Where (surface)</h3>
            <div class="table-wrap" style="max-height:280px">
              <table><thead><tr><th>Surface</th><th class="num">Count</th></tr></thead>
              <tbody>${surfaceRows || '<tr><td colspan="2" class="empty">—</td></tr>'}</tbody></table>
            </div>
          </div>
          <div class="card">
            <h3>Top people</h3>
            <div class="table-wrap" style="max-height:280px">
              <table><thead><tr><th></th><th>Person</th><th class="num">Signals</th></tr></thead>
              <tbody>${people || '<tr><td colspan="3" class="empty">—</td></tr>'}</tbody></table>
            </div>
          </div>
        </div>
      </section>

      <section id="panel-activity" class="panel">
        <div class="card">
          <div class="toolbar">
            <input class="search" id="activity-search" placeholder="Filter by action, person, post, surface…" />
            <span class="muted small" id="activity-count">Showing ${esc(report.interactionCountReturned)} of ${esc(report.totalInteractions)}</span>
          </div>
          <div class="table-wrap">
            <table id="activity-table">
              <thead>
                <tr>
                  <th>When (UTC)</th><th>Action</th><th>Person</th><th>Post</th>
                  <th>Where</th><th>Look time</th><th>Interest</th>
                </tr>
              </thead>
              <tbody>${rows || '<tr><td colspan="7" class="empty">No interactions yet — open the iOS app and use the feed.</td></tr>'}</tbody>
            </table>
          </div>
        </div>
      </section>

      <section id="panel-content" class="panel">
        <div class="card">
          <h3>Top content by attention</h3>
          <div class="table-wrap">
            <table>
              <thead><tr><th></th><th>Post</th><th class="num">Signals</th><th class="num">Avg interest</th></tr></thead>
              <tbody>${posts || '<tr><td colspan="4" class="empty">No content signals yet</td></tr>'}</tbody>
            </table>
          </div>
        </div>
      </section>

      <section id="panel-people" class="panel">
        <div class="card">
          <h3>Most active people</h3>
          <div class="table-wrap">
            <table>
              <thead><tr><th></th><th>Person</th><th class="num">Signals</th></tr></thead>
              <tbody>${people || '<tr><td colspan="3" class="empty">No people yet</td></tr>'}</tbody>
            </table>
          </div>
        </div>
      </section>

      <section id="panel-uploads" class="panel">
        <div class="card">
          <h3>Everything uploaded</h3>
          <p class="muted small" style="margin:0 0 12px">Kafka ContentPosted · feed / Sparks / Hubs</p>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>When</th><th>What happened</th><th>Who</th><th>Title</th>
                  <th>Where</th><th>Country</th><th>Channel</th><th>Type</th>
                </tr>
              </thead>
              <tbody>${uploadRows || '<tr><td colspan="8" class="empty">No uploads in this window</td></tr>'}</tbody>
            </table>
          </div>
        </div>
      </section>

      <section id="panel-ranking" class="panel">
        <div class="card">
          <h3>Server ranking decisions</h3>
          <p class="muted small" style="margin:0 0 12px">From recommendation_decisions · policy server.v1</p>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>When</th><th>Surface</th><th>Policy</th>
                  <th class="num">Served</th><th class="num">Candidates</th>
                  <th class="num">Latency</th><th>Request</th>
                </tr>
              </thead>
              <tbody>${rankRows || '<tr><td colspan="7" class="empty">No rank calls yet — open the home feed in the app after deploy.</td></tr>'}</tbody>
            </table>
          </div>
        </div>
      </section>

      <p class="foot">Generated ${esc(report.generatedAt)} · Kafka matterya.engagement · window ${esc(hours)}h · Matterya Insights</p>
    </main>
  </div>

  <script type="application/json" id="report-json">${reportJson}</script>
  <script>
    (function () {
      var cache = Object.create(null);
      var currentHours = ${hours};
      var inflight = null;
      var main = document.querySelector('.main');
      try {
        var boot = JSON.parse(document.getElementById('report-json').textContent || '{}');
        if (boot && boot.windowHours) cache[String(boot.windowHours)] = boot;
      } catch (e) {}

      function esc(s) {
        return String(s == null ? '' : s)
          .replace(/&/g, '&amp;').replace(/</g, '&lt;')
          .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
      }
      function n(v) { return Number(v || 0).toLocaleString(); }

      var tabs = document.querySelectorAll('.nav button[data-tab]');
      var panels = document.querySelectorAll('.panel');
      tabs.forEach(function (btn) {
        btn.addEventListener('click', function () {
          var id = btn.getAttribute('data-tab');
          tabs.forEach(function (b) { b.classList.remove('active'); });
          panels.forEach(function (p) { p.classList.remove('active'); });
          btn.classList.add('active');
          var panel = document.getElementById('panel-' + id);
          if (panel) panel.classList.add('active');
        });
      });

      function wireSearch() {
        var search = document.getElementById('activity-search');
        var table = document.getElementById('activity-table');
        var countEl = document.getElementById('activity-count');
        if (!search || !table) return;
        search.oninput = function () {
          var q = (search.value || '').toLowerCase().trim();
          var rows = table.querySelectorAll('tbody tr');
          var shown = 0;
          rows.forEach(function (tr) {
            var hay = tr.getAttribute('data-search') || '';
            var ok = !q || hay.indexOf(q) !== -1;
            tr.style.display = ok ? '' : 'none';
            if (ok) shown += 1;
          });
          if (countEl) countEl.textContent = 'Showing ' + shown + ' filtered rows';
        };
      }
      wireSearch();

      function wireTimelineHover(root) {
        var tip = document.getElementById('timeline-tip');
        if (!root || !tip) return;
        root.onmouseover = function (e) {
          var col = e.target.closest && e.target.closest('.bar-col');
          if (!col) return;
          var t = col.getAttribute('title') || '';
          tip.textContent = t;
        };
        root.onmouseleave = function () { tip.textContent = ''; };
      }
      wireTimelineHover(document.getElementById('timeline-bars'));

      function setRangeActive(h) {
        document.querySelectorAll('.range-btn').forEach(function (b) {
          b.classList.toggle('active', Number(b.getAttribute('data-hours')) === Number(h));
        });
      }

      function setLoading(on) {
        if (main) main.classList.toggle('is-loading', !!on);
        document.querySelectorAll('.range-btn').forEach(function (b) { b.disabled = !!on; });
      }

      function kpi(label, value, hint) {
        return '<div class="kpi"><div class="kpi-v">' + esc(value) + '</div><div class="kpi-l">' +
          esc(label) + '</div>' + (hint ? '<div class="kpi-h">' + esc(hint) + '</div>' : '') + '</div>';
      }

      function renderReport(report) {
        if (!report) return;
        currentHours = report.windowHours;
        var k = report.kpis || {};
        var sum = document.getElementById('insights-summary');
        if (sum) sum.textContent = report.summary || '';
        var grid = document.getElementById('kpi-grid');
        if (grid) {
          grid.innerHTML = [
            kpi('Total signals', n(report.totalInteractions)),
            kpi('People', n(k.uniquePeople), 'unique actors'),
            kpi('Likes', n(k.likes)),
            kpi('Shares', n(k.shares)),
            kpi('Saves', n(k.saves)),
            kpi('Comments', n(k.comments)),
            kpi('Looks', n(k.dwells), 'stopped to read'),
            kpi('Skips', n(k.skips)),
            kpi('Full watches', n(k.watchesComplete)),
            kpi('Partial watches', n(k.watchesPartial)),
            kpi('Impressions', n(k.impressions)),
            kpi('In viewport', n(k.viewportVisible)),
            kpi('Hides', n(k.hides)),
            kpi('Not interested', n(k.notInterested)),
            kpi('Follows', n(k.follows)),
            kpi('Profile opens', n(k.profileOpens)),
            kpi('Hub opens', n(k.hubOpens)),
            kpi('Hub videos', n(k.hubVideoOpens)),
            kpi('Uploads', n(report.uploadCount)),
            kpi('Avg look', report.stoppedToLook && report.stoppedToLook.averageLookTime || '—')
          ].join('');
        }

        var cap = document.getElementById('timeline-caption');
        if (cap) cap.textContent = report.timelineCaption || 'Hover a bar to see when and how many signals.';
        var tip = document.getElementById('timeline-tip');
        if (tip) tip.textContent = '';
        var maxHour = 1;
        (report.hourly || []).forEach(function (h) { if (h.count > maxHour) maxHour = h.count; });
        var series = report.hourly || [];
        var nBars = series.length;
        var labelEvery = nBars <= 8 ? 1 : nBars <= 16 ? 2 : nBars <= 32 ? 4 : Math.ceil(nBars / 8);
        var barsEl = document.getElementById('timeline-bars');
        if (barsEl) {
          barsEl.innerHTML = series.map(function (h, i) {
            var pct = Math.max(3, Math.round((h.count / maxHour) * 100));
            var showLabel = i === 0 || i === nBars - 1 || i % labelEvery === 0;
            var title = h.title || (h.label + ' — ' + h.count + ' signals');
            return '<div class="bar-col" title="' + esc(title) + '" data-count="' + esc(h.count) +
              '" data-label="' + esc(h.label) + '"><div class="bar" style="height:' + pct +
              '%"></div><span class="bar-label">' + (showLabel ? esc(h.label) : '') + '</span></div>';
          }).join('') || '<div class="empty">No activity in this period yet</div>';
          wireTimelineHover(barsEl);
        }

        var br = document.querySelector('#panel-overview .card:nth-child(2)');
        // breakdown is second card in first grid - find by h3
        document.querySelectorAll('#panel-overview .card').forEach(function (card) {
          var h3 = card.querySelector('h3');
          if (!h3) return;
          if (h3.textContent.indexOf('What people did') !== -1) {
            var total = report.totalInteractions || 1;
            card.innerHTML = '<h3>What people did</h3>' + ((report.activityBreakdown || []).map(function (r) {
              var pct = Math.round((r.count / total) * 100);
              return '<div class="breakdown-row"><div class="br-label">' + esc(r.action) +
                '</div><div class="br-track"><div class="br-fill" style="width:' + pct +
                '%"></div></div><div class="br-count">' + esc(r.count) + '</div></div>';
            }).join('') || '<div class="empty">No breakdown yet</div>');
          }
        });

        function peopleRows(list) {
          return (list || []).map(function (p, i) {
            var name = p.name || p.username || (p.personId || '').slice(0, 8) + '…';
            var handle = p.username ? '@' + p.username : '—';
            return '<tr><td class="num muted">' + (i + 1) + '</td><td><div class="person"><span class="avatar">' +
              esc(String(name).slice(0, 1).toUpperCase()) + '</span><div><strong>' + esc(name) +
              '</strong><div class="muted small">' + esc(handle) + '</div></div></div></td><td class="num">' +
              esc(p.interactions) + '</td></tr>';
          }).join('') || '<tr><td colspan="3" class="empty">—</td></tr>';
        }

        var surfaceHtml = (report.bySurface || []).map(function (s) {
          return '<tr><td>' + esc(s.surface) + '</td><td class="num">' + esc(s.count) + '</td></tr>';
        }).join('') || '<tr><td colspan="2" class="empty">—</td></tr>';

        document.querySelectorAll('#panel-overview .table-wrap table tbody').forEach(function (tb, idx) {
          if (idx === 0) tb.innerHTML = surfaceHtml;
          if (idx === 1) tb.innerHTML = peopleRows(report.mostActivePeople);
        });

        var actBody = document.querySelector('#activity-table tbody');
        if (actBody) {
          actBody.innerHTML = (report.interactions || []).map(function (i) {
            var hay = [i.action, i.personName, i.personUsername, i.postPreview, i.where, i.actionCode]
              .filter(Boolean).join(' ').toLowerCase();
            var person = i.personName || i.personUsername || (i.personId || '').slice(0, 8) + '…';
            var post = i.postPreview || (i.postId ? String(i.postId).slice(0, 8) + '…' : '—');
            return '<tr data-search="' + esc(hay) + '"><td class="nowrap">' + esc(i.when) +
              '</td><td><span class="pill">' + esc(i.action) + '</span></td><td>' + esc(person) +
              '</td><td class="clip">' + esc(post) + '</td><td>' + esc(i.where) + '</td><td>' +
              esc(i.lookTime || '—') + '</td><td class="muted small">' + esc(i.interest) + '</td></tr>';
          }).join('') || '<tr><td colspan="7" class="empty">No interactions yet</td></tr>';
        }
        var countEl = document.getElementById('activity-count');
        if (countEl) {
          countEl.textContent = 'Showing ' + (report.interactionCountReturned || 0) +
            ' of ' + (report.totalInteractions || 0);
        }

        var contentBody = document.querySelector('#panel-content tbody');
        if (contentBody) {
          contentBody.innerHTML = (report.mostViewedPosts || []).map(function (p, i) {
            return '<tr><td class="num muted">' + (i + 1) + '</td><td>' +
              esc(p.preview || (p.postId || '').slice(0, 10) + '…') +
              '</td><td class="num">' + esc(p.interactions) +
              '</td><td class="num">' + esc(p.averageInterest) + '</td></tr>';
          }).join('') || '<tr><td colspan="4" class="empty">No content signals yet</td></tr>';
        }

        var peopleBody = document.querySelector('#panel-people tbody');
        if (peopleBody) peopleBody.innerHTML = peopleRows(report.mostActivePeople);

        var upBody = document.querySelector('#panel-uploads tbody');
        if (upBody) {
          upBody.innerHTML = (report.uploads || []).map(function (u) {
            var who = u.personName || u.personUsername || (u.personId ? String(u.personId).slice(0, 8) + '…' : '—');
            return '<tr><td class="nowrap">' + esc(u.when) + '</td><td>' + esc(u.summary) +
              '</td><td>' + esc(who) + '</td><td class="clip">' + esc(u.title || '—') +
              '</td><td>' + esc(u.where) + '</td><td>' + esc(u.country || '—') +
              '</td><td>' + esc(u.channelName || '—') + '</td><td>' + esc(u.mediaType || '—') + '</td></tr>';
          }).join('') || '<tr><td colspan="8" class="empty">No uploads in this window</td></tr>';
        }

        var rankBody = document.querySelector('#panel-ranking tbody');
        if (rankBody) {
          rankBody.innerHTML = (report.rankDecisions || []).map(function (r) {
            return '<tr><td class="nowrap">' + esc(r.when) + '</td><td>' + esc(r.surface) +
              '</td><td class="muted small">' + esc(r.policyVersion) +
              '</td><td class="num">' + esc(r.servedCount) +
              '</td><td class="num">' + esc(r.candidateCount) +
              '</td><td class="num">' + esc(r.latencyMs != null ? r.latencyMs + ' ms' : '—') +
              '</td><td class="muted small clip">' + esc(String(r.requestId || '').slice(0, 12)) + '…</td></tr>';
          }).join('') || '<tr><td colspan="7" class="empty">No rank calls yet</td></tr>';
        }

        var jsonEl = document.getElementById('report-json');
        if (jsonEl) jsonEl.textContent = JSON.stringify(report);
        setRangeActive(report.windowHours);
        wireSearch();
        var search = document.getElementById('activity-search');
        if (search) search.value = '';
      }

      function fetchReport(hours, force) {
        var key = String(hours);
        if (!force && cache[key]) {
          renderReport(cache[key]);
          history.replaceState({ hours: hours }, '', '/reports?hours=' + hours);
          return Promise.resolve(cache[key]);
        }
        if (inflight && inflight.key === key) return inflight.p;
        setLoading(true);
        var p = fetch('/reports/data?hours=' + encodeURIComponent(hours), {
          credentials: 'same-origin',
          headers: { 'Accept': 'application/json' }
        })
          .then(function (r) {
            if (!r.ok) throw new Error('HTTP ' + r.status);
            return r.json();
          })
          .then(function (data) {
            var report = data.report || data;
            cache[key] = report;
            renderReport(report);
            history.replaceState({ hours: hours }, '', '/reports?hours=' + hours);
            return report;
          })
          .catch(function (err) {
            console.warn('[insights] load failed', err);
            // Fallback: full navigation only if we have nothing
            if (!cache[key]) window.location.href = '/reports?hours=' + hours;
          })
          .finally(function () {
            setLoading(false);
            inflight = null;
          });
        inflight = { key: key, p: p };
        return p;
      }

      document.getElementById('range-bar') && document.getElementById('range-bar').addEventListener('click', function (e) {
        var btn = e.target.closest('.range-btn');
        if (!btn) return;
        var h = Number(btn.getAttribute('data-hours'));
        if (!h || h === currentHours) {
          // same range → soft refresh only if forced later
          setRangeActive(h);
          if (cache[String(h)]) renderReport(cache[String(h)]);
          return;
        }
        setRangeActive(h);
        fetchReport(h, false);
      });

      var refresh = document.getElementById('btn-refresh');
      if (refresh) {
        refresh.addEventListener('click', function () {
          fetchReport(currentHours, true);
        });
      }

      var exp = document.getElementById('btn-export');
      if (exp) {
        exp.addEventListener('click', function () {
          var el = document.getElementById('report-json');
          var raw = el ? el.textContent || '{}' : '{}';
          var blob = new Blob([raw], { type: 'application/json' });
          var a = document.createElement('a');
          a.href = URL.createObjectURL(blob);
          a.download = 'matterya-insights-' + Date.now() + '.json';
          a.click();
          URL.revokeObjectURL(a.href);
        });
      }

      // Prefetch other ranges in the background for instant clicks.
      var PREFETCH = [1, 6, 24, 72, 168, 720];
      if (window.requestIdleCallback) {
        requestIdleCallback(function () { prefetchAll(); }, { timeout: 1200 });
      } else {
        setTimeout(prefetchAll, 400);
      }
      function prefetchAll() {
        PREFETCH.forEach(function (h, i) {
          if (String(h) === String(currentHours)) return;
          setTimeout(function () {
            if (cache[String(h)]) return;
            fetch('/reports/data?hours=' + h, {
              credentials: 'same-origin',
              headers: { 'Accept': 'application/json' }
            })
              .then(function (r) { return r.ok ? r.json() : null; })
              .then(function (data) {
                if (data && (data.report || data.windowHours)) {
                  cache[String(h)] = data.report || data;
                }
              })
              .catch(function () {});
          }, 120 * i);
        });
      }
    })();
  </script>
</body>
</html>`;
}
