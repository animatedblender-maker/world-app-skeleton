import { randomUUID } from 'node:crypto';
import { pool } from '../db.js';
import { enqueueOutbox } from '../kafka/outbox.js';
import {
  EngagementEventTypes,
  KafkaTopics,
  type EngagementPayload,
} from '../kafka/types.js';

/** Client-facing event type → Kafka eventType + default strength */
const CLIENT_TYPES: Record<
  string,
  { eventType: string; defaultStrength: number }
> = {
  like: { eventType: EngagementEventTypes.Liked, defaultStrength: 0.55 },
  unlike: { eventType: EngagementEventTypes.Unliked, defaultStrength: -0.55 },
  comment: { eventType: EngagementEventTypes.Commented, defaultStrength: 0.85 },
  share: { eventType: EngagementEventTypes.Shared, defaultStrength: 0.75 },
  save: { eventType: EngagementEventTypes.Saved, defaultStrength: 0.7 },
  unsave: { eventType: EngagementEventTypes.Unsaved, defaultStrength: -0.4 },
  watch_partial: { eventType: EngagementEventTypes.WatchPartial, defaultStrength: 0.35 },
  watch_complete: { eventType: EngagementEventTypes.WatchComplete, defaultStrength: 0.9 },
  /** User scrolled and stopped looking at a post */
  scroll_dwell: { eventType: EngagementEventTypes.ScrollDwell, defaultStrength: 0.4 },
  /** User scrolled past quickly */
  scroll_skip: { eventType: EngagementEventTypes.ScrollSkip, defaultStrength: -0.25 },
  profile_open: { eventType: EngagementEventTypes.ProfileOpened, defaultStrength: 0.2 },
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
      // Attention events should be about a piece of content.
      if (
        !contentId &&
        (typeKey.startsWith('scroll_') ||
          typeKey.startsWith('watch_') ||
          typeKey === 'like' ||
          typeKey === 'comment')
      ) {
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
};

const SURFACE_LABELS: Record<string, string> = {
  home: 'Home feed',
  hubs: 'Hubs',
  reels: 'Sparks',
  profile: 'Profile',
  search: 'Search',
  country: 'Country feed',
  api: 'App action',
  chat: 'Chat',
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
             max(left(coalesce(nullif(trim(po.title), ''), nullif(trim(po.body), ''), 'Post'), 120)) as preview
      from public.entity_engagement_events e
      left join public.posts po on po.id = e.content_id
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
             e.occurred_at,
             p.display_name,
             p.username,
             left(coalesce(nullif(trim(po.title), ''), nullif(trim(po.body), ''), null), 100) as post_preview
      from public.entity_engagement_events e
      left join public.profiles p on p.user_id = e.entity_id
      left join public.posts po on po.id = e.content_id
      where e.occurred_at > now() - ($1::text || ' hours')::interval
      order by e.occurred_at desc
      limit 500
      `,
      [String(hours)]
    );

    const total = Number(totalRows[0]?.n ?? 0);
    const lookTimes = Number(lookRows[0]?.n ?? 0);
    const avgLookMs = Number(lookRows[0]?.avg_ms ?? 0);

    const interactions: ActivityRow[] = allInteractions.map((r: any) => {
      const t = formatWhen(r.occurred_at);
      const interest = Number(r.strength);
      let interestLabel = 'Neutral';
      if (interest >= 0.7) interestLabel = 'Strong interest';
      else if (interest >= 0.35) interestLabel = 'Interest';
      else if (interest > 0) interestLabel = 'Mild interest';
      else if (interest < 0) interestLabel = 'Low interest / passed by';

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
        postPreview: r.post_preview ?? null,
        where: surfaceLabel(r.surface),
        lookTime: formatLookTime(r.duration_ms != null ? Number(r.duration_ms) : null),
        interest: interestLabel,
      };
    });

    const summaryParts = [
      `${total} interaction${total === 1 ? '' : 's'} in the last ${hours} hour${hours === 1 ? '' : 's'}.`,
    ];
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

/** Simple HTML dashboard — open in browser with admin key. */
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

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>${esc(report.title)}</title>
  <style>
    body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif; margin: 24px; color: #111; background: #fafafa; }
    h1 { font-size: 1.5rem; margin: 0 0 8px; }
    .sub { color: #555; margin-bottom: 24px; max-width: 52rem; line-height: 1.45; }
    .cards { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 28px; }
    .card { background: #fff; border: 1px solid #e5e5e5; border-radius: 12px; padding: 14px 18px; min-width: 140px; }
    .card b { display: block; font-size: 1.4rem; }
    .card span { color: #666; font-size: 0.85rem; }
    h2 { font-size: 1.05rem; margin: 28px 0 10px; }
    table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #e5e5e5; border-radius: 12px; overflow: hidden; font-size: 13px; }
    th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #eee; vertical-align: top; }
    th { background: #f3f3f3; font-weight: 600; position: sticky; top: 0; }
    tr:hover td { background: #f9f9ff; }
    .meta { color: #888; font-size: 12px; margin-top: 24px; }
  </style>
</head>
<body>
  <h1>${esc(report.title)}</h1>
  <p class="sub">${esc(report.summary)}</p>
  <div class="cards">
    <div class="card"><b>${esc(report.totalInteractions)}</b><span>Total interactions</span></div>
    <div class="card"><b>${esc(report.windowHours)}h</b><span>Time window</span></div>
    <div class="card"><b>${esc(report.stoppedToLook.times)}</b><span>Stopped to look</span></div>
    <div class="card"><b>${esc(report.stoppedToLook.averageLookTime)}</b><span>Avg look time</span></div>
  </div>

  <h2>What people did</h2>
  <table><thead><tr><th>Action</th><th>Count</th></tr></thead><tbody>${breakdown || '<tr><td colspan="2">None yet</td></tr>'}</tbody></table>

  <h2>Most active people</h2>
  <table><thead><tr><th>Name</th><th>Username</th><th>Interactions</th></tr></thead><tbody>${people || '<tr><td colspan="3">None yet</td></tr>'}</tbody></table>

  <h2>Every interaction (with time)</h2>
  <p class="sub">Showing ${esc(report.interactionCountReturned)} of ${esc(report.totalInteractions)} (newest first). Each row has an exact timestamp.</p>
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
  <p class="meta">Generated ${esc(report.generatedAt)} · Live Kafka topic: matterya.engagement</p>
</body>
</html>`;
}
