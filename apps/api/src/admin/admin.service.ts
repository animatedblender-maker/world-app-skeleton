import { pool } from '../db.js';

export type AdminSettings = {
  insight_window_hours: number;
  insight_min_posts: number;
  insight_cache_minutes: number;
  insight_max_posts: number;
  insight_max_lookback_hours: number;
  ollama_enabled: boolean;
  ollama_model: string;
};

export type ReportedPostItem = {
  post_id: string;
  latest_report_at: string;
  report_count: number;
  open_report_count: number;
  ticket_status: 'open' | 'in_review' | 'actioned' | 'ignored';
  reasons: string[];
  post_excerpt: string;
  country_code: string | null;
  author_id: string | null;
  author_name: string | null;
  post_visibility: string | null;
  moderation_status: 'active' | 'sensitive' | 'hidden' | 'deleted';
  moderation_note: string | null;
  moderated_at: string | null;
  moderation_actor: string | null;
};

export type ModerationAction =
  | 'in_review'
  | 'ignore'
  | 'mark_sensitive'
  | 'clear_sensitive'
  | 'hide_post'
  | 'delete_post'
  | 'restore_post';

export type AdminOverview = {
  total_profiles: number;
  online_users: number;
  posts_last_24h: number;
  reports_last_7d: number;
  active_campaigns: number;
  total_campaigns: number;
};

export type AdsAdminSummary = {
  active_campaigns: number;
  draft_campaigns: number;
  paused_campaigns: number;
  total_creatives: number;
  total_budget_cents: number;
};

const DEFAULT_SETTINGS: AdminSettings = {
  insight_window_hours: 24,
  insight_min_posts: 3,
  insight_cache_minutes: 5,
  insight_max_posts: 250,
  insight_max_lookback_hours: 24 * 30,
  ollama_enabled: true,
  ollama_model: String(process.env.OLLAMA_MODEL || '').trim(),
};

let settingsTableEnsured = false;
let moderationSchemaEnsured = false;

function toInt(value: any, fallback: number, min: number, max: number): number {
  const next = Number(value);
  if (!Number.isFinite(next)) return fallback;
  return Math.max(min, Math.min(max, Math.round(next)));
}

function normalizeSettings(value: any): AdminSettings {
  const raw = value && typeof value === 'object' ? value : {};
  return {
    insight_window_hours: toInt(raw.insight_window_hours, DEFAULT_SETTINGS.insight_window_hours, 1, 24 * 30),
    insight_min_posts: toInt(raw.insight_min_posts, DEFAULT_SETTINGS.insight_min_posts, 1, 1000),
    insight_cache_minutes: toInt(raw.insight_cache_minutes, DEFAULT_SETTINGS.insight_cache_minutes, 1, 24 * 60),
    insight_max_posts: toInt(raw.insight_max_posts, DEFAULT_SETTINGS.insight_max_posts, 10, 1000),
    insight_max_lookback_hours: toInt(
      raw.insight_max_lookback_hours,
      DEFAULT_SETTINGS.insight_max_lookback_hours,
      1,
      24 * 365
    ),
    ollama_enabled:
      typeof raw.ollama_enabled === 'boolean' ? raw.ollama_enabled : DEFAULT_SETTINGS.ollama_enabled,
    ollama_model: String(raw.ollama_model || DEFAULT_SETTINGS.ollama_model || '').trim(),
  };
}

async function ensureSettingsTable(): Promise<void> {
  if (settingsTableEnsured) return;
  await pool.query(`
    create table if not exists public.app_settings (
      key text primary key,
      value jsonb not null default '{}'::jsonb,
      updated_at timestamptz not null default now()
    )
  `);
  settingsTableEnsured = true;
}

async function ensureModerationSchema(): Promise<void> {
  if (moderationSchemaEnsured) return;
  await pool.query(`
    alter table public.posts
      add column if not exists moderation_status text not null default 'active',
      add column if not exists moderation_note text,
      add column if not exists moderated_at timestamptz,
      add column if not exists moderation_actor text
  `);
  await pool.query(`
    do $$
    begin
      if not exists (
        select 1
        from pg_constraint
        where conname = 'posts_moderation_status_check'
      ) then
        alter table public.posts
          add constraint posts_moderation_status_check
          check (moderation_status = any (array['active','sensitive','hidden','deleted']));
      end if;
    end$$;
  `);
  await pool.query(`
    alter table public.post_reports
      add column if not exists status text not null default 'open',
      add column if not exists moderator_note text,
      add column if not exists moderator_actor text,
      add column if not exists resolution_action text,
      add column if not exists resolved_at timestamptz
  `);
  await pool.query(`
    do $$
    begin
      if not exists (
        select 1
        from pg_constraint
        where conname = 'post_reports_status_check'
      ) then
        alter table public.post_reports
          add constraint post_reports_status_check
          check (status = any (array['open','in_review','actioned','ignored']));
      end if;
      if not exists (
        select 1
        from pg_constraint
        where conname = 'post_reports_resolution_action_check'
      ) then
        alter table public.post_reports
          add constraint post_reports_resolution_action_check
          check (
            resolution_action is null
            or resolution_action = any (
              array['ignore','mark_sensitive','clear_sensitive','hide_post','delete_post','restore_post']
            )
          );
      end if;
    end$$;
  `);
  await pool.query(`
    create index if not exists post_reports_post_status_created_idx
      on public.post_reports (post_id, status, created_at desc)
  `);
  moderationSchemaEnsured = true;
}

export async function getAdminSettings(): Promise<AdminSettings> {
  await ensureSettingsTable();
  const { rows } = await pool.query<{ value: any }>(
    `
    select value
    from public.app_settings
    where key = 'admin.global'
    limit 1
    `
  );
  return normalizeSettings(rows[0]?.value ?? {});
}

export async function updateAdminSettings(patch: Partial<AdminSettings>): Promise<AdminSettings> {
  await ensureSettingsTable();
  const current = await getAdminSettings();
  const next = normalizeSettings({ ...current, ...(patch ?? {}) });
  await pool.query(
    `
    insert into public.app_settings (key, value, updated_at)
    values ('admin.global', $1::jsonb, now())
    on conflict (key) do update set
      value = excluded.value,
      updated_at = now()
    `,
    [JSON.stringify(next)]
  );
  return next;
}

export async function getAdminOverview(): Promise<AdminOverview> {
  await ensureModerationSchema();
  const [
    profilesRes,
    onlineRes,
    postsRes,
    reportsRes,
    campaignsRes,
  ] = await Promise.all([
    pool.query<{ count: string }>(`select count(*)::text as count from public.profiles`),
    pool.query<{ count: string }>(
      `
      select count(*)::text as count
      from public.user_presence
      where is_online = true
        and last_seen_at > now() - interval '90 seconds'
      `
    ),
    pool.query<{ count: string }>(
      `
      select count(*)::text as count
      from public.posts
      where created_at > now() - interval '24 hours'
      `
    ),
    pool.query<{ count: string }>(
      `
      select count(*)::text as count
      from public.post_reports
      where created_at > now() - interval '7 days'
      `
    ),
    pool.query<{ active_count: string; total_count: string }>(
      `
      select
        count(*) filter (where status = 'active')::text as active_count,
        count(*)::text as total_count
      from public.ad_campaigns
      `
    ).catch(() => ({ rows: [{ active_count: '0', total_count: '0' }] })),
  ]);

  return {
    total_profiles: Number(profilesRes.rows[0]?.count ?? 0),
    online_users: Number(onlineRes.rows[0]?.count ?? 0),
    posts_last_24h: Number(postsRes.rows[0]?.count ?? 0),
    reports_last_7d: Number(reportsRes.rows[0]?.count ?? 0),
    active_campaigns: Number(campaignsRes.rows[0]?.active_count ?? 0),
    total_campaigns: Number(campaignsRes.rows[0]?.total_count ?? 0),
  };
}

export async function listReportedPosts(limit = 40): Promise<ReportedPostItem[]> {
  await ensureModerationSchema();
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 40));
  const { rows } = await pool.query<ReportedPostItem>(
    `
    with report_rollup as (
      select
        r.post_id,
        max(r.created_at) as latest_report_at,
        count(*)::int as report_count,
        count(*) filter (where r.status in ('open', 'in_review'))::int as open_report_count,
        count(*) filter (where r.status = 'open')::int as open_count,
        count(*) filter (where r.status = 'in_review')::int as in_review_count,
        count(*) filter (where r.status = 'actioned')::int as actioned_count,
        count(*) filter (where r.status = 'ignored')::int as ignored_count
      from public.post_reports r
      group by r.post_id
    ),
    latest_reasons as (
      select
        q.post_id,
        array_agg(q.reason order by q.created_at desc) as reasons
      from (
        select
          r.post_id,
          r.reason,
          r.created_at,
          row_number() over (partition by r.post_id order by r.created_at desc) as rn
        from public.post_reports r
      ) q
      where q.rn <= 5
      group by q.post_id
    )
    select
      rr.post_id::text as post_id,
      rr.latest_report_at::text as latest_report_at,
      rr.report_count,
      rr.open_report_count,
      case
        when rr.open_count > 0 then 'open'
        when rr.in_review_count > 0 then 'in_review'
        when rr.actioned_count > 0 then 'actioned'
        else 'ignored'
      end::text as ticket_status,
      coalesce(lr.reasons, array[]::text[]) as reasons,
      left(trim(concat(coalesce(p.title, ''), ' ', coalesce(p.body, ''))), 180) as post_excerpt,
      p.country_code,
      p.author_id::text as author_id,
      ap.display_name as author_name,
      p.visibility as post_visibility,
      coalesce(p.moderation_status, 'active')::text as moderation_status,
      p.moderation_note,
      p.moderated_at::text as moderated_at,
      p.moderation_actor
    from report_rollup rr
    join public.posts p on p.id = rr.post_id
    left join latest_reasons lr on lr.post_id = rr.post_id
    left join public.profiles ap on ap.user_id = p.author_id
    order by rr.latest_report_at desc
    limit $1
    `,
    [safeLimit]
  );
  return rows;
}

export async function moderateReportedPost(
  postId: string,
  action: ModerationAction,
  note?: string | null,
  actor?: string | null
): Promise<ReportedPostItem | null> {
  await ensureModerationSchema();
  const safePostId = String(postId || '').trim();
  if (!safePostId) throw new Error('post_id is required');
  const allowedActions = new Set<ModerationAction>([
    'in_review',
    'ignore',
    'mark_sensitive',
    'clear_sensitive',
    'hide_post',
    'delete_post',
    'restore_post',
  ]);
  if (!allowedActions.has(action)) throw new Error('invalid_action');
  const safeActor = String(actor || '').trim() || 'admin';
  const safeNote = String(note || '').trim() || null;
  const client = await pool.connect();
  try {
    await client.query('begin');

    if (action === 'in_review') {
      await client.query(
        `
        update public.post_reports
        set
          status = 'in_review',
          moderator_actor = $2,
          moderator_note = coalesce($3, moderator_note)
        where post_id = $1
          and status = 'open'
        `,
        [safePostId, safeActor, safeNote]
      );
    } else if (action === 'ignore') {
      await client.query(
        `
        update public.post_reports
        set
          status = 'ignored',
          moderator_actor = $2,
          moderator_note = coalesce($3, moderator_note),
          resolution_action = 'ignore',
          resolved_at = now()
        where post_id = $1
          and status in ('open', 'in_review')
        `,
        [safePostId, safeActor, safeNote]
      );
    } else {
      const nextStatus =
        action === 'mark_sensitive' ? 'sensitive' :
        action === 'clear_sensitive' || action === 'restore_post' ? 'active' :
        action === 'hide_post' ? 'hidden' :
        'deleted';

      await client.query(
        `
        update public.posts
        set
          moderation_status = $2,
          moderation_note = $3,
          moderated_at = now(),
          moderation_actor = $4
        where id = $1
        `,
        [safePostId, nextStatus, safeNote, safeActor]
      );

      await client.query(
        `
        update public.post_reports
        set
          status = 'actioned',
          moderator_actor = $2,
          moderator_note = coalesce($3, moderator_note),
          resolution_action = $4,
          resolved_at = now()
        where post_id = $1
          and status in ('open', 'in_review')
        `,
        [safePostId, safeActor, safeNote, action]
      );
    }

    await client.query('commit');
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }

  const reports = await listReportedPosts(200);
  return reports.find((item) => item.post_id === safePostId) ?? null;
}

export async function getAdsAdminSummary(): Promise<AdsAdminSummary> {
  const { rows } = await pool
    .query<{
      active_campaigns: string;
      draft_campaigns: string;
      paused_campaigns: string;
      total_creatives: string;
      total_budget_cents: string;
    }>(
      `
      select
        count(*) filter (where c.status = 'active')::text as active_campaigns,
        count(*) filter (where c.status = 'draft')::text as draft_campaigns,
        count(*) filter (where c.status = 'paused')::text as paused_campaigns,
        count(distinct cr.id)::text as total_creatives,
        coalesce(sum(c.budget_cents), 0)::text as total_budget_cents
      from public.ad_campaigns c
      left join public.ad_creatives cr on cr.campaign_id = c.id
      `
    )
    .catch(() => ({
      rows: [
        {
          active_campaigns: '0',
          draft_campaigns: '0',
          paused_campaigns: '0',
          total_creatives: '0',
          total_budget_cents: '0',
        },
      ],
    }));

  const row = rows[0] ?? {
    active_campaigns: '0',
    draft_campaigns: '0',
    paused_campaigns: '0',
    total_creatives: '0',
    total_budget_cents: '0',
  };

  return {
    active_campaigns: Number(row.active_campaigns ?? 0),
    draft_campaigns: Number(row.draft_campaigns ?? 0),
    paused_campaigns: Number(row.paused_campaigns ?? 0),
    total_creatives: Number(row.total_creatives ?? 0),
    total_budget_cents: Number(row.total_budget_cents ?? 0),
  };
}
