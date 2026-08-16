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
  [ContentEventTypes.Posted]: 'Uploaded content',
  [ContentEventTypes.Shared]: 'Shared content',
  [ContentEventTypes.Deleted]: 'Deleted content',
};

const SURFACE_LABELS: Record<string, string> = {
  home: 'Home feed',
  feed: 'Home feed',
  hubs: 'Matterya Hubs',
  reels: 'Sparks',
  sparks: 'Sparks',
  profile: 'Profile',
  search: 'Search',
  country: 'Country feed',
  api: 'App action',
  chat: 'Chat',
  server: 'Platform / backend',
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

export async function getEngagementReport(windowHours = 24): Promise<HumanEngagementReport> {
  const hours = Math.max(1, Math.min(168, windowHours));
  const generatedAt = new Date().toISOString();
  const empty: HumanEngagementReport = {
    title: 'People activity report',
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
  };

  try {
    const { rows: totalRows } = await pool.query<{ n: string }>(
      `
      select count(*)::text as n
      from public.entity_engagement_events
      where occurred_at > now() - ($1::text || ' hours')::interval
      `,
      [String(hours)]
    );

    const { rows: byType } = await pool.query<{ event_type: string; count: string }>(
      `
      select event_type, count(*)::text as count
      from public.entity_engagement_events
      where occurred_at > now() - ($1::text || ' hours')::interval
      group by event_type
      order by count(*) desc
      `,
      [String(hours)]
    );

    const { rows: topPeople } = await pool.query<{
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
      where e.occurred_at > now() - ($1::text || ' hours')::interval
      group by e.entity_id
      order by count(*) desc
      limit 20
      `,
      [String(hours)]
    );

    const { rows: topPosts } = await pool.query<{
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
      where e.occurred_at > now() - ($1::text || ' hours')::interval
        and e.content_id is not null
      group by e.content_id
      order by count(*) desc
      limit 20
      `,
      [String(hours)]
    );

    const { rows: lookRows } = await pool.query<{ n: string; avg_ms: string }>(
      `
      select count(*)::text as n, coalesce(avg(duration_ms), 0)::text as avg_ms
      from public.entity_engagement_events
      where occurred_at > now() - ($1::text || ' hours')::interval
        and event_type = $2
      `,
      [String(hours), EngagementEventTypes.ScrollDwell]
    );

    // Every interaction with timestamp (newest first). Cap 500 for response size.
    const { rows: allInteractions } = await pool.query(
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
      where e.occurred_at > now() - ($1::text || ' hours')::interval
      order by e.occurred_at desc
      limit 500
      `,
      [String(hours)]
    );

    const total = Number(totalRows[0]?.n ?? 0);
    const lookTimes = Number(lookRows[0]?.n ?? 0);
    const avgLookMs = Number(lookRows[0]?.avg_ms ?? 0);

    // Uploads tab — every ContentPosted (R2 / app / backend publish).
    const { rows: uploadRows } = await pool.query(
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
      where e.occurred_at > now() - ($1::text || ' hours')::interval
        and e.event_type = $2
      order by e.occurred_at desc
      limit 500
      `,
      [String(hours), ContentEventTypes.Posted]
    );

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
      `${total} interaction${total === 1 ? '' : 's'} in the last ${hours} hour${hours === 1 ? '' : 's'}.`,
    ];
    if (uploads.length > 0) {
      summaryParts.push(
        `${uploads.length} content upload${uploads.length === 1 ? '' : 's'} synced (feed / Sparks / Hubs).`
      );
    }
    if (lookTimes > 0) {
      summaryParts.push(
        `People stopped to look at posts ${lookTimes} time${lookTimes === 1 ? '' : 's'} (avg ${formatLookTime(avgLookMs) ?? '—'}).`
      );
    }

    return {
      title: 'People activity report',
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

/** Simple HTML dashboard — open in browser with admin key. Tabs: Activity | Uploads. */
export function renderEngagementReportHtml(report: HumanEngagementReport): string {
  const esc = (s: unknown) =>
    String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');

  const breakdown = report.activityBreakdown
    .map(
      (r) =>
        `<tr><td>${esc(r.action)}</td><td style="text-align:right">${esc(r.count)}</td></tr>`
    )
    .join('');

  const people = report.mostActivePeople
    .map(
      (p) =>
        `<tr><td>${esc(p.name || p.username || p.personId.slice(0, 8) + '…')}</td><td>${esc(p.username ? '@' + p.username : '—')}</td><td style="text-align:right">${esc(p.interactions)}</td></tr>`
    )
    .join('');

  const rows = report.interactions
    .map(
      (i) => `<tr>
      <td style="white-space:nowrap;font-variant-numeric:tabular-nums">${esc(i.when)}</td>
      <td style="white-space:nowrap;color:#666;font-size:12px">${esc(i.timestamp)}</td>
      <td><strong>${esc(i.action)}</strong></td>
      <td>${esc(i.personName || i.personUsername || i.personId.slice(0, 8) + '…')}</td>
      <td>${esc(i.postPreview || (i.postId ? i.postId.slice(0, 8) + '…' : '—'))}</td>
      <td>${esc(i.where)}</td>
      <td>${esc(i.lookTime || '—')}</td>
      <td>${esc(i.interest)}</td>
    </tr>`
    )
    .join('');

  const uploadRows = (report.uploads ?? [])
    .map(
      (u) => `<tr>
      <td style="white-space:nowrap;font-variant-numeric:tabular-nums">${esc(u.when)}</td>
      <td style="white-space:nowrap;color:#666;font-size:12px">${esc(u.timestamp)}</td>
      <td>${esc(u.summary)}</td>
      <td>${esc(u.personName || u.personUsername || (u.personId ? u.personId.slice(0, 8) + '…' : '—'))}</td>
      <td>${esc(u.title || '—')}</td>
      <td>${esc(u.where)}</td>
      <td>${esc(u.country || '—')}</td>
      <td>${esc(u.channelName || '—')}</td>
      <td>${esc(u.mediaType || '—')}</td>
    </tr>`
    )
    .join('');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>${esc(report.title)}</title>
  <style>
    body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif; margin: 24px; color: #1c1917; background: #f8f6f2; }
    h1 { font-size: 1.5rem; margin: 0 0 8px; font-weight: 600; }
    .sub { color: #57534e; margin-bottom: 20px; max-width: 52rem; line-height: 1.45; }
    .cards { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 20px; }
    .card { background: #fff; border: 1px solid #e7e5e4; border-radius: 12px; padding: 14px 18px; min-width: 140px; }
    .card b { display: block; font-size: 1.4rem; color: #292524; }
    .card span { color: #78716c; font-size: 0.85rem; }
    .tabs { display: flex; gap: 8px; margin: 8px 0 20px; border-bottom: 1px solid #e7e5e4; padding-bottom: 0; }
    .tab { appearance: none; border: 0; background: transparent; padding: 10px 16px; font: inherit; font-weight: 600; font-size: 13px; color: #78716c; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; }
    .tab.active { color: #1c1917; border-bottom-color: #7c6a4d; }
    .panel { display: none; }
    .panel.active { display: block; }
    h2 { font-size: 1.05rem; margin: 28px 0 10px; }
    table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #e7e5e4; border-radius: 12px; overflow: hidden; font-size: 13px; }
    th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #f0eeea; vertical-align: top; }
    th { background: #f3f1ec; font-weight: 600; position: sticky; top: 0; }
    tr:hover td { background: #faf8f5; }
    .meta { color: #a8a29e; font-size: 12px; margin-top: 24px; }
  </style>
</head>
<body>
  <h1>${esc(report.title)}</h1>
  <p class="sub">${esc(report.summary)}</p>
  <div class="cards">
    <div class="card"><b>${esc(report.totalInteractions)}</b><span>Total interactions</span></div>
    <div class="card"><b>${esc(report.uploadCount ?? 0)}</b><span>Content uploads</span></div>
    <div class="card"><b>${esc(report.windowHours)}h</b><span>Time window</span></div>
    <div class="card"><b>${esc(report.stoppedToLook.times)}</b><span>Stopped to look</span></div>
    <div class="card"><b>${esc(report.stoppedToLook.averageLookTime)}</b><span>Avg look time</span></div>
  </div>

  <div class="tabs" role="tablist">
    <button type="button" class="tab active" data-tab="activity" role="tab">Activity</button>
    <button type="button" class="tab" data-tab="uploads" role="tab">Uploads</button>
  </div>

  <div id="panel-activity" class="panel active" role="tabpanel">
    <h2>What people did</h2>
    <table><thead><tr><th>Action</th><th>Count</th></tr></thead><tbody>${breakdown || '<tr><td colspan="2">None yet</td></tr>'}</tbody></table>

    <h2>Most active people</h2>
    <table><thead><tr><th>Name</th><th>Username</th><th>Interactions</th></tr></thead><tbody>${people || '<tr><td colspan="3">None yet</td></tr>'}</tbody></table>

    <h2>Every interaction (with time)</h2>
    <p class="sub">Showing ${esc(report.interactionCountReturned)} of ${esc(report.totalInteractions)} (newest first).</p>
    <table>
      <thead>
        <tr>
          <th>When (UTC)</th>
          <th>Exact timestamp</th>
          <th>Action</th>
          <th>Person</th>
          <th>Post</th>
          <th>Where</th>
          <th>How long they looked</th>
          <th>Interest</th>
        </tr>
      </thead>
      <tbody>${rows || '<tr><td colspan="8">No interactions yet — open the app and like or view posts.</td></tr>'}</tbody>
    </table>
  </div>

  <div id="panel-uploads" class="panel" role="tabpanel">
    <h2>Everything uploaded to the platform</h2>
    <p class="sub">
      Live sync via Kafka (<code>matterya.posts</code> + <code>matterya.engagement</code>).
      Shows who uploaded, when, where (feed / Sparks / Hubs channel), and a plain-language summary.
      Showing ${esc(report.uploadCount ?? 0)} upload(s) in this window.
    </p>
    <table>
      <thead>
        <tr>
          <th>When (UTC)</th>
          <th>Exact timestamp</th>
          <th>What happened</th>
          <th>Who</th>
          <th>Title</th>
          <th>Where</th>
          <th>Country</th>
          <th>Channel</th>
          <th>Type</th>
        </tr>
      </thead>
      <tbody>${uploadRows || '<tr><td colspan="9">No uploads yet — publish a feed post, Spark, or Hubs video (or seed R2 content through createPost).</td></tr>'}</tbody>
    </table>
  </div>

  <p class="meta">Generated ${esc(report.generatedAt)} · Kafka: matterya.posts · matterya.engagement</p>
  <script>
    document.querySelectorAll('.tab').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var id = btn.getAttribute('data-tab');
        document.querySelectorAll('.tab').forEach(function (b) { b.classList.remove('active'); });
        document.querySelectorAll('.panel').forEach(function (p) { p.classList.remove('active'); });
        btn.classList.add('active');
        var panel = document.getElementById('panel-' + id);
        if (panel) panel.classList.add('active');
      });
    });
  </script>
</body>
</html>`;
}
