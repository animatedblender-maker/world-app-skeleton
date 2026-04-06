import { pool } from '../db.js';

export type AdminSettings = {
  insight_window_hours: number;
  insight_min_posts: number;
  insight_cache_minutes: number;
  ollama_enabled: boolean;
  ollama_model: string;
};

export type ReportedPostItem = {
  report_id: string;
  created_at: string;
  reason: string;
  post_id: string;
  post_excerpt: string;
  country_code: string | null;
  reporter_id: string;
  reporter_name: string | null;
  author_id: string | null;
  author_name: string | null;
};

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
  ollama_enabled: true,
  ollama_model: String(process.env.OLLAMA_MODEL || '').trim(),
};

let settingsTableEnsured = false;

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
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 40));
  const { rows } = await pool.query<ReportedPostItem>(
    `
    select
      r.id::text as report_id,
      r.created_at::text as created_at,
      r.reason,
      r.post_id::text as post_id,
      left(trim(concat(coalesce(p.title, ''), ' ', coalesce(p.body, ''))), 180) as post_excerpt,
      p.country_code,
      r.reporter_id::text as reporter_id,
      rr.display_name as reporter_name,
      p.author_id::text as author_id,
      ap.display_name as author_name
    from public.post_reports r
    join public.posts p on p.id = r.post_id
    left join public.profiles rr on rr.user_id = r.reporter_id
    left join public.profiles ap on ap.user_id = p.author_id
    order by r.created_at desc
    limit $1
    `,
    [safeLimit]
  );
  return rows;
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
