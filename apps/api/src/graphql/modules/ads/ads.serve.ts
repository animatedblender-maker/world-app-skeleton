import { randomUUID } from 'node:crypto';

import { pool } from '../../../db.js';
import { normalizeClickUrl, normalizeCountryCode } from './ads.urls.js';

export type ServeVideoAdInput = {
  placement: string;
  country_code?: string | null;
  content_country_code?: string | null;
  post_id?: string | null;
};

type AdCreativeRow = {
  id: string;
  campaign_id: string;
  title: string | null;
  body: string | null;
  media_kind: string;
  media_url: string;
  click_url: string | null;
  cta_label: string | null;
  duration_seconds: number;
  created_at: string;
  updated_at: string;
};

type AdCampaignRow = {
  id: string;
  advertiser_user_id: string;
  name: string;
  status: string;
  placement: string;
  target_country_codes: string[] | null;
  budget_cents: number;
  daily_budget_cents: number;
  start_at: string | null;
  end_at: string | null;
  created_at: string;
  updated_at: string;
  impression_count: number;
  click_count: number;
};

type AdSlotRow = {
  campaign_id: string;
  advertiser_user_id: string;
  campaign_name: string;
  campaign_status: string;
  placement: string;
  target_country_codes: string[] | null;
  budget_cents: number;
  daily_budget_cents: number;
  campaign_start_at: string | null;
  campaign_end_at: string | null;
  campaign_created_at: string;
  campaign_updated_at: string;
  creative_id: string;
  creative_title: string | null;
  creative_body: string | null;
  media_kind: string;
  media_url: string;
  click_url: string | null;
  cta_label: string | null;
  duration_seconds: number;
  creative_created_at: string;
  creative_updated_at: string;
  impression_count: number;
  click_count: number;
};

function normalizeUuidOrNull(value: string | null): string | null {
  const raw = String(value ?? '').trim();
  if (!raw) return null;
  const uuidRe =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRe.test(raw) ? raw : null;
}

function mapCampaignRow(row: AdCampaignRow): AdCampaignRow {
  return {
    id: row.id,
    advertiser_user_id: row.advertiser_user_id,
    name: row.name,
    status: row.status,
    placement: row.placement,
    target_country_codes: Array.isArray(row.target_country_codes) ? row.target_country_codes : [],
    budget_cents: Number(row.budget_cents ?? 0),
    daily_budget_cents: Number(row.daily_budget_cents ?? 0),
    start_at: row.start_at ?? null,
    end_at: row.end_at ?? null,
    created_at: row.created_at,
    updated_at: row.updated_at,
    impression_count: Number(row.impression_count ?? 0),
    click_count: Number(row.click_count ?? 0),
  };
}

function mapCreativeRow(row: AdCreativeRow): AdCreativeRow {
  return {
    id: row.id,
    campaign_id: row.campaign_id,
    title: row.title ?? null,
    body: row.body ?? null,
    media_kind: row.media_kind,
    media_url: row.media_url,
    // Re-normalize on serve so legacy unsafe click_url never reaches clients.
    click_url: normalizeClickUrl(row.click_url ?? null),
    cta_label: row.cta_label ?? null,
    duration_seconds: Number(row.duration_seconds ?? 0),
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

export async function serveVideoAd(
  userId: string | null,
  input: ServeVideoAdInput
): Promise<
  | {
      impression_token: string;
      skip_after_seconds: number;
      campaign: AdCampaignRow & { creatives: AdCreativeRow[] };
      creative: AdCreativeRow;
    }
  | null
> {
  const placement = String(input.placement || '').trim().toLowerCase();
  if (placement !== 'video' && placement !== 'reel') {
    throw new Error('Unsupported ad placement.');
  }
  const requestedCountry = normalizeCountryCode(input.country_code ?? null);
  const contentCountry = normalizeCountryCode(input.content_country_code ?? null);
  const effectiveCountry = requestedCountry || contentCountry;

  const { rows } = await pool.query<AdSlotRow>(
    `
    with campaign_stats as (
      select
        i.campaign_id,
        count(*) filter (where i.served_at >= date_trunc('day', now()))::int as day_serves,
        count(*) filter (where i.viewed_at is not null)::int as impression_count,
        count(*) filter (where i.clicked_at is not null)::int as click_count
      from public.ad_impressions i
      group by i.campaign_id
    )
    select
      c.id as campaign_id,
      c.advertiser_user_id,
      c.name as campaign_name,
      c.status as campaign_status,
      c.placement,
      c.target_country_codes,
      c.budget_cents,
      c.daily_budget_cents,
      c.start_at as campaign_start_at,
      c.end_at as campaign_end_at,
      c.created_at as campaign_created_at,
      c.updated_at as campaign_updated_at,
      cr.id as creative_id,
      cr.title as creative_title,
      cr.body as creative_body,
      cr.media_kind,
      cr.media_url,
      cr.click_url,
      cr.cta_label,
      cr.duration_seconds,
      cr.created_at as creative_created_at,
      cr.updated_at as creative_updated_at,
      case
        when cardinality(c.target_country_codes) = 0 then 1
        when $2::text is not null and $2::text = any(c.target_country_codes) then 0
        when $3::text is not null and $3::text = any(c.target_country_codes) then 0
        else 2
      end as country_rank,
      coalesce(stats.impression_count, 0)::int as impression_count,
      coalesce(stats.click_count, 0)::int as click_count
    from public.ad_campaigns c
    join public.ad_creatives cr on cr.campaign_id = c.id
    join public.ad_advertisers adv on adv.user_id = c.advertiser_user_id
    left join campaign_stats stats on stats.campaign_id = c.id
    where c.status = 'active'
      and (
        c.placement = $1
        or ($1 = 'reel' and c.placement = 'video')
      )
      and cr.media_kind = 'video'
      and cr.media_url ~* '^https?://'
      and cr.media_url ~* '\\.(mp4|webm|mov|m4v)(\\?.*)?(#.*)?$'
      and (c.start_at is null or c.start_at <= now())
      and (c.end_at is null or c.end_at >= now())
      -- Prepaid wallet must cover at least one impression (€0.10).
      and coalesce(adv.wallet_balance_cents, 0) >= 10
      and (
        c.daily_budget_cents <= 0
        or coalesce(stats.day_serves, 0) < greatest(1, c.daily_budget_cents / 10)
      )
      and (
        c.budget_cents <= 0
        or coalesce(stats.impression_count, 0) < greatest(1, c.budget_cents / 10)
      )
    order by
      country_rank asc,
      (case
        when c.budget_cents > 0
          then greatest(0, c.budget_cents - coalesce(stats.impression_count, 0) * 10)
        else c.daily_budget_cents
      end) desc,
      coalesce(stats.day_serves, 0) asc,
      c.created_at asc,
      cr.created_at asc
    limit 1
    `,
    [placement, effectiveCountry, contentCountry]
  );

  const row = rows[0];
  if (!row) return null;

  let impressionToken = randomUUID();
  const safePostId = normalizeUuidOrNull(input.post_id ?? null);
  try {
    await pool.query(
      `
      insert into public.ad_impressions (
        campaign_id,
        creative_id,
        viewer_user_id,
        placement,
        country_code,
        content_country_code,
        post_id,
        impression_token
      )
      values ($1, $2, $3, $4, $5, $6, $7, $8)
      `,
      [
        row.campaign_id,
        row.creative_id,
        userId,
        placement,
        requestedCountry,
        contentCountry,
        safePostId,
        impressionToken,
      ]
    );
  } catch (error) {
    // Do not block ad playback if impression write fails.
    // Playback is higher priority than analytics.
    console.error('[ads] failed to insert ad_impression', {
      campaign_id: row.campaign_id,
      creative_id: row.creative_id,
      placement,
      requestedCountry,
      contentCountry,
      post_id: safePostId,
      error,
    });
    impressionToken = randomUUID();
  }

  const mappedCreative = mapCreativeRow({
    id: row.creative_id,
    campaign_id: row.campaign_id,
    title: row.creative_title,
    body: row.creative_body,
    media_kind: row.media_kind,
    media_url: row.media_url,
    click_url: row.click_url,
    cta_label: row.cta_label,
    duration_seconds: row.duration_seconds,
    created_at: row.creative_created_at,
    updated_at: row.creative_updated_at,
  });

  return {
    impression_token: impressionToken,
    skip_after_seconds: Math.min(5, Math.max(2, Math.floor(Number(row.duration_seconds ?? 8) / 2))),
    campaign: {
      ...mapCampaignRow({
        id: row.campaign_id,
        advertiser_user_id: row.advertiser_user_id,
        name: row.campaign_name,
        status: row.campaign_status,
        placement: row.placement,
        target_country_codes: row.target_country_codes,
        budget_cents: row.budget_cents,
        daily_budget_cents: row.daily_budget_cents,
        start_at: row.campaign_start_at,
        end_at: row.campaign_end_at,
        created_at: row.campaign_created_at,
        updated_at: row.campaign_updated_at,
        impression_count: row.impression_count,
        click_count: row.click_count,
      }),
      creatives: [mappedCreative],
    },
    creative: mappedCreative,
  };
}

export async function debugServeVideoAd(input: ServeVideoAdInput): Promise<{
  ok: boolean;
  reason: string;
  placement: string;
  country_code: string | null;
  content_country_code: string | null;
  active_campaigns: number;
  country_match_campaigns: number;
  selected_campaign_id: string | null;
}> {
  const placement = String(input.placement || '').trim().toLowerCase();
  if (placement !== 'video' && placement !== 'reel') {
    throw new Error('Unsupported ad placement.');
  }
  const requestedCountry = normalizeCountryCode(input.country_code ?? null);
  const contentCountry = normalizeCountryCode(input.content_country_code ?? null);
  const effectiveCountry = requestedCountry || contentCountry;

  const { rows: countRows } = await pool.query<{
    active_campaigns: number;
    country_match_campaigns: number;
  }>(
    `
    with campaign_stats as (
      select
        i.campaign_id,
        count(*) filter (where i.served_at >= date_trunc('day', now()))::int as day_serves
      from public.ad_impressions i
      group by i.campaign_id
    )
    select
      count(distinct c.id)::int as active_campaigns,
      count(distinct c.id) filter (
        where cardinality(c.target_country_codes) = 0
          or ($2::text is not null and $2::text = any(c.target_country_codes))
          or ($3::text is not null and $3::text = any(c.target_country_codes))
      )::int as country_match_campaigns
    from public.ad_campaigns c
    join public.ad_creatives cr on cr.campaign_id = c.id
    left join campaign_stats stats on stats.campaign_id = c.id
    where c.status = 'active'
      and c.placement = $1
      and cr.media_kind = 'video'
      and cr.media_url ~* '^https?://'
      and cr.media_url ~* '\\.(mp4|webm|mov|m4v)(\\?.*)?(#.*)?$'
      and (c.start_at is null or c.start_at <= now())
      and (c.end_at is null or c.end_at >= now())
      and (
        c.daily_budget_cents <= 0
        or coalesce(stats.day_serves, 0) < greatest(1, c.daily_budget_cents / 10)
      )
    `,
    [placement, effectiveCountry, contentCountry]
  );
  const activeCampaigns = Number(countRows[0]?.active_campaigns ?? 0);
  const countryMatchCampaigns = Number(countRows[0]?.country_match_campaigns ?? 0);

  const { rows } = await pool.query<AdSlotRow & { country_rank: number }>(
    `
    with campaign_stats as (
      select
        i.campaign_id,
        count(*) filter (where i.served_at >= date_trunc('day', now()))::int as day_serves,
        count(*) filter (where i.viewed_at is not null)::int as impression_count,
        count(*) filter (where i.clicked_at is not null)::int as click_count
      from public.ad_impressions i
      group by i.campaign_id
    )
    select
      c.id as campaign_id,
      c.advertiser_user_id,
      c.name as campaign_name,
      c.status as campaign_status,
      c.placement,
      c.target_country_codes,
      c.budget_cents,
      c.daily_budget_cents,
      c.start_at as campaign_start_at,
      c.end_at as campaign_end_at,
      c.created_at as campaign_created_at,
      c.updated_at as campaign_updated_at,
      cr.id as creative_id,
      cr.title as creative_title,
      cr.body as creative_body,
      cr.media_kind,
      cr.media_url,
      cr.click_url,
      cr.cta_label,
      cr.duration_seconds,
      cr.created_at as creative_created_at,
      cr.updated_at as creative_updated_at,
      case
        when cardinality(c.target_country_codes) = 0 then 1
        when $2::text is not null and $2::text = any(c.target_country_codes) then 0
        when $3::text is not null and $3::text = any(c.target_country_codes) then 0
        else 2
      end as country_rank,
      coalesce(stats.impression_count, 0)::int as impression_count,
      coalesce(stats.click_count, 0)::int as click_count
    from public.ad_campaigns c
    join public.ad_creatives cr on cr.campaign_id = c.id
    left join campaign_stats stats on stats.campaign_id = c.id
    where c.status = 'active'
      and c.placement = $1
      and cr.media_kind = 'video'
      and cr.media_url ~* '^https?://'
      and cr.media_url ~* '\\.(mp4|webm|mov|m4v)(\\?.*)?(#.*)?$'
      and (c.start_at is null or c.start_at <= now())
      and (c.end_at is null or c.end_at >= now())
      and (
        c.daily_budget_cents <= 0
        or coalesce(stats.day_serves, 0) < greatest(1, c.daily_budget_cents / 10)
      )
    order by
      country_rank asc,
      coalesce(stats.day_serves, 0) asc,
      c.created_at asc,
      cr.created_at asc
    limit 1
    `,
    [placement, effectiveCountry, contentCountry]
  );
  const selected = rows[0];

  if (selected) {
    const targetCodes = Array.isArray(selected.target_country_codes) ? selected.target_country_codes : [];
    const exactMatch =
      (!!effectiveCountry && targetCodes.includes(effectiveCountry)) ||
      (!!contentCountry && targetCodes.includes(contentCountry));
    const usedFallback = targetCodes.length > 0 && !exactMatch;
    return {
      ok: true,
      reason: usedFallback
        ? 'Selected a fallback campaign (no exact country match).'
        : 'Selected campaign successfully.',
      placement,
      country_code: requestedCountry,
      content_country_code: contentCountry,
      active_campaigns: activeCampaigns,
      country_match_campaigns: countryMatchCampaigns,
      selected_campaign_id: selected.campaign_id,
    };
  }

  let reason = 'No campaign selected.';
  if (activeCampaigns === 0) {
    reason = 'No active campaign eligible for this placement (status/schedule/budget/creative).';
  } else if (countryMatchCampaigns === 0) {
    reason = 'Active campaigns exist, but none match country and no global campaign is available.';
  }

  return {
    ok: false,
    reason,
    placement,
    country_code: requestedCountry,
    content_country_code: contentCountry,
    active_campaigns: activeCampaigns,
    country_match_campaigns: countryMatchCampaigns,
    selected_campaign_id: null,
  };
}
