import { randomUUID } from 'node:crypto';

import { pool } from '../../../db.js';

type AdAdvertiserRow = {
  user_id: string;
  display_name: string | null;
  website_url: string | null;
  created_at: string;
  updated_at: string;
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

export type AdCampaignInput = {
  name: string;
  placement: string;
  status?: string | null;
  target_country_codes?: Array<string | null> | null;
  budget_cents?: number | null;
  daily_budget_cents?: number | null;
  start_at?: string | null;
  end_at?: string | null;
};

export type AdCreativeInput = {
  title?: string | null;
  body?: string | null;
  media_kind?: string | null;
  media_url: string;
  click_url?: string | null;
  cta_label?: string | null;
  duration_seconds?: number | null;
};

export type ServeVideoAdInput = {
  placement: string;
  country_code?: string | null;
  content_country_code?: string | null;
  post_id?: string | null;
};

export class AdsService {
  async myAdvertiser(userId: string): Promise<AdAdvertiserRow> {
    await this.ensureAdvertiser(userId);
    const { rows } = await pool.query<AdAdvertiserRow>(
      `
      select user_id, display_name, website_url, created_at, updated_at
      from public.ad_advertisers
      where user_id = $1
      `,
      [userId]
    );
    return rows[0]!;
  }

  async myCampaigns(userId: string): Promise<Array<AdCampaignRow & { creatives: AdCreativeRow[] }>> {
    await this.ensureAdvertiser(userId);
    const campaigns = await this.listCampaignRows(
      `
      select
        c.id,
        c.advertiser_user_id,
        c.name,
        c.status,
        c.placement,
        c.target_country_codes,
        c.budget_cents,
        c.daily_budget_cents,
        c.start_at,
        c.end_at,
        c.created_at,
        c.updated_at,
        coalesce(stats.impression_count, 0)::int as impression_count,
        coalesce(stats.click_count, 0)::int as click_count
      from public.ad_campaigns c
      left join lateral (
        select
          count(*) filter (where i.viewed_at is not null) as impression_count,
          count(*) filter (where i.clicked_at is not null) as click_count
        from public.ad_impressions i
        where i.campaign_id = c.id
      ) stats on true
      where c.advertiser_user_id = $1
      order by c.created_at desc
      `,
      [userId]
    );
    return await this.attachCreatives(campaigns);
  }

  async campaignById(
    campaignId: string,
    userId: string
  ): Promise<(AdCampaignRow & { creatives: AdCreativeRow[] }) | null> {
    const campaigns = await this.listCampaignRows(
      `
      select
        c.id,
        c.advertiser_user_id,
        c.name,
        c.status,
        c.placement,
        c.target_country_codes,
        c.budget_cents,
        c.daily_budget_cents,
        c.start_at,
        c.end_at,
        c.created_at,
        c.updated_at,
        coalesce(stats.impression_count, 0)::int as impression_count,
        coalesce(stats.click_count, 0)::int as click_count
      from public.ad_campaigns c
      left join lateral (
        select
          count(*) filter (where i.viewed_at is not null) as impression_count,
          count(*) filter (where i.clicked_at is not null) as click_count
        from public.ad_impressions i
        where i.campaign_id = c.id
      ) stats on true
      where c.id = $1 and c.advertiser_user_id = $2
      limit 1
      `,
      [campaignId, userId]
    );
    if (!campaigns.length) return null;
    const enriched = await this.attachCreatives(campaigns);
    return enriched[0] ?? null;
  }

  async createCampaign(
    userId: string,
    input: AdCampaignInput
  ): Promise<AdCampaignRow & { creatives: AdCreativeRow[] }> {
    await this.ensureAdvertiser(userId);
    const normalized = this.normalizeCampaignInput(input);
    const { rows } = await pool.query<{ id: string }>(
      `
      insert into public.ad_campaigns (
        advertiser_user_id,
        name,
        status,
        placement,
        target_country_codes,
        budget_cents,
        daily_budget_cents,
        start_at,
        end_at
      )
      values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      returning id
      `,
      [
        userId,
        normalized.name,
        normalized.status,
        normalized.placement,
        normalized.target_country_codes,
        normalized.budget_cents,
        normalized.daily_budget_cents,
        normalized.start_at,
        normalized.end_at,
      ]
    );
    const campaign = await this.campaignById(rows[0]!.id, userId);
    if (!campaign) throw new Error('Campaign not found after creation.');
    return campaign;
  }

  async updateCampaign(
    campaignId: string,
    userId: string,
    input: AdCampaignInput
  ): Promise<AdCampaignRow & { creatives: AdCreativeRow[] }> {
    const existing = await this.campaignById(campaignId, userId);
    if (!existing) throw new Error('Campaign not found.');
    const normalized = this.normalizeCampaignInput({ ...existing, ...input });
    await pool.query(
      `
      update public.ad_campaigns
      set
        name = $3,
        status = $4,
        placement = $5,
        target_country_codes = $6,
        budget_cents = $7,
        daily_budget_cents = $8,
        start_at = $9,
        end_at = $10,
        updated_at = now()
      where id = $1 and advertiser_user_id = $2
      `,
      [
        campaignId,
        userId,
        normalized.name,
        normalized.status,
        normalized.placement,
        normalized.target_country_codes,
        normalized.budget_cents,
        normalized.daily_budget_cents,
        normalized.start_at,
        normalized.end_at,
      ]
    );
    return (await this.campaignById(campaignId, userId))!;
  }

  async createCreative(campaignId: string, userId: string, input: AdCreativeInput): Promise<AdCreativeRow> {
    const campaign = await this.campaignById(campaignId, userId);
    if (!campaign) throw new Error('Campaign not found.');
    const normalized = this.normalizeCreativeInput(input);
    const { rows } = await pool.query<AdCreativeRow>(
      `
      insert into public.ad_creatives (
        campaign_id,
        title,
        body,
        media_kind,
        media_url,
        click_url,
        cta_label,
        duration_seconds
      )
      values ($1, $2, $3, $4, $5, $6, $7, $8)
      returning
        id,
        campaign_id,
        title,
        body,
        media_kind,
        media_url,
        click_url,
        cta_label,
        duration_seconds,
        created_at,
        updated_at
      `,
      [
        campaignId,
        normalized.title,
        normalized.body,
        normalized.media_kind,
        normalized.media_url,
        normalized.click_url,
        normalized.cta_label,
        normalized.duration_seconds,
      ]
    );
    return rows[0]!;
  }

  async serveVideoAd(
    userId: string | null,
    input: ServeVideoAdInput
  ): Promise<
    | {
        impression_token: string;
        skip_after_seconds: number;
        campaign: AdCampaignRow;
        creative: AdCreativeRow;
      }
    | null
  > {
    const placement = String(input.placement || '').trim().toLowerCase();
    if (placement !== 'video' && placement !== 'reel') {
      throw new Error('Unsupported ad placement.');
    }
    const requestedCountry = this.normalizeCountryCode(input.country_code ?? null);
    const contentCountry = this.normalizeCountryCode(input.content_country_code ?? null);
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
        coalesce(stats.impression_count, 0)::int as impression_count,
        coalesce(stats.click_count, 0)::int as click_count
      from public.ad_campaigns c
      join public.ad_creatives cr on cr.campaign_id = c.id
      left join campaign_stats stats on stats.campaign_id = c.id
      where c.status = 'active'
        and c.placement = $1
        and cr.media_kind = 'video'
        and (c.start_at is null or c.start_at <= now())
        and (c.end_at is null or c.end_at >= now())
        and (
          cardinality(c.target_country_codes) = 0
          or $2::text = any(c.target_country_codes)
          or $3::text = any(c.target_country_codes)
        )
        and (
          c.daily_budget_cents <= 0
          or coalesce(stats.day_serves, 0) < greatest(1, c.daily_budget_cents / 10)
        )
      order by
        coalesce(stats.day_serves, 0) asc,
        c.created_at asc,
        cr.created_at asc
      limit 1
      `,
      [placement, effectiveCountry, contentCountry]
    );

    const row = rows[0];
    if (!row) return null;

    const impressionToken = randomUUID();
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
        input.post_id ?? null,
        impressionToken,
      ]
    );

    return {
      impression_token: impressionToken,
      skip_after_seconds: Math.min(5, Math.max(2, Math.floor(Number(row.duration_seconds ?? 8) / 2))),
      campaign: this.mapCampaignRow({
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
      creative: this.mapCreativeRow({
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
      }),
    };
  }

  async logImpression(impressionToken: string, userId: string | null): Promise<boolean> {
    const { rowCount } = await pool.query(
      `
      update public.ad_impressions
      set
        viewed_at = coalesce(viewed_at, now()),
        viewer_user_id = coalesce(viewer_user_id, $2)
      where impression_token = $1
      `,
      [impressionToken, userId]
    );
    return Number(rowCount ?? 0) > 0;
  }

  async logClick(impressionToken: string, userId: string | null): Promise<boolean> {
    const { rows } = await pool.query<{
      id: string;
      campaign_id: string;
      creative_id: string;
      viewer_user_id: string | null;
    }>(
      `
      update public.ad_impressions
      set
        clicked_at = coalesce(clicked_at, now()),
        viewer_user_id = coalesce(viewer_user_id, $2)
      where impression_token = $1
      returning id, campaign_id, creative_id, viewer_user_id
      `,
      [impressionToken, userId]
    );
    const row = rows[0];
    if (!row) return false;
    await pool.query(
      `
      insert into public.ad_clicks (
        impression_id,
        campaign_id,
        creative_id,
        viewer_user_id
      )
      values ($1, $2, $3, $4)
      on conflict do nothing
      `,
      [row.id, row.campaign_id, row.creative_id, row.viewer_user_id]
    );
    return true;
  }

  private async ensureAdvertiser(userId: string): Promise<void> {
    await pool.query(
      `
      insert into public.ad_advertisers (user_id, display_name)
      values (
        $1,
        (
          select nullif(trim(coalesce(p.display_name, p.username, '')), '')
          from public.profiles p
          where p.user_id = $1
        )
      )
      on conflict (user_id) do update
      set
        display_name = coalesce(
          excluded.display_name,
          public.ad_advertisers.display_name
        ),
        updated_at = now()
      `,
      [userId]
    );
  }

  private normalizeCampaignInput(input: AdCampaignInput): Required<AdCampaignInput> {
    const name = String(input?.name ?? '').trim();
    if (!name) throw new Error('Campaign name is required.');
    const placement = String(input?.placement ?? '').trim().toLowerCase();
    if (placement !== 'video' && placement !== 'reel') {
      throw new Error('Placement must be video or reel.');
    }
    const status = String(input?.status ?? 'draft').trim().toLowerCase();
    if (!['draft', 'active', 'paused', 'ended'].includes(status)) {
      throw new Error('Invalid campaign status.');
    }
    return {
      name,
      placement,
      status,
      target_country_codes: this.normalizeCountryCodeArray(input?.target_country_codes ?? []),
      budget_cents: Math.max(0, Math.floor(Number(input?.budget_cents ?? 0) || 0)),
      daily_budget_cents: Math.max(0, Math.floor(Number(input?.daily_budget_cents ?? 0) || 0)),
      start_at: input?.start_at ? String(input.start_at) : null,
      end_at: input?.end_at ? String(input.end_at) : null,
    };
  }

  private normalizeCreativeInput(input: AdCreativeInput): Required<AdCreativeInput> {
    const mediaUrl = String(input?.media_url ?? '').trim();
    if (!mediaUrl) throw new Error('Creative media URL is required.');
    const mediaKind = String(input?.media_kind ?? 'video').trim().toLowerCase();
    if (mediaKind !== 'video' && mediaKind !== 'image') {
      throw new Error('Creative media kind must be video or image.');
    }
    return {
      title: String(input?.title ?? '').trim() || null,
      body: String(input?.body ?? '').trim() || null,
      media_kind: mediaKind,
      media_url: mediaUrl,
      click_url: String(input?.click_url ?? '').trim() || null,
      cta_label: String(input?.cta_label ?? '').trim() || null,
      duration_seconds: Math.max(3, Math.min(30, Math.floor(Number(input?.duration_seconds ?? 8) || 8))),
    };
  }

  private normalizeCountryCode(code: string | null): string | null {
    const value = String(code ?? '').trim().toUpperCase();
    return value || null;
  }

  private normalizeCountryCodeArray(values: Array<string | null> | null): string[] {
    const unique = new Set<string>();
    for (const value of values ?? []) {
      const code = this.normalizeCountryCode(value);
      if (code) unique.add(code);
    }
    return [...unique];
  }

  private async listCampaignRows(query: string, params: any[]): Promise<AdCampaignRow[]> {
    const { rows } = await pool.query<AdCampaignRow>(query, params);
    return rows.map((row) => this.mapCampaignRow(row));
  }

  private async attachCreatives(
    campaigns: AdCampaignRow[]
  ): Promise<Array<AdCampaignRow & { creatives: AdCreativeRow[] }>> {
    if (!campaigns.length) return [];
    const ids = campaigns.map((campaign) => campaign.id);
    const { rows } = await pool.query<AdCreativeRow>(
      `
      select
        id,
        campaign_id,
        title,
        body,
        media_kind,
        media_url,
        click_url,
        cta_label,
        duration_seconds,
        created_at,
        updated_at
      from public.ad_creatives
      where campaign_id = any($1::uuid[])
      order by created_at asc
      `,
      [ids]
    );
    const byCampaign = new Map<string, AdCreativeRow[]>();
    for (const row of rows.map((row) => this.mapCreativeRow(row))) {
      if (!byCampaign.has(row.campaign_id)) byCampaign.set(row.campaign_id, []);
      byCampaign.get(row.campaign_id)!.push(row);
    }
    return campaigns.map((campaign) => ({
      ...campaign,
      creatives: byCampaign.get(campaign.id) ?? [],
    }));
  }

  private mapCampaignRow(row: AdCampaignRow): AdCampaignRow {
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

  private mapCreativeRow(row: AdCreativeRow): AdCreativeRow {
    return {
      id: row.id,
      campaign_id: row.campaign_id,
      title: row.title ?? null,
      body: row.body ?? null,
      media_kind: row.media_kind,
      media_url: row.media_url,
      click_url: row.click_url ?? null,
      cta_label: row.cta_label ?? null,
      duration_seconds: Number(row.duration_seconds ?? 0),
      created_at: row.created_at,
      updated_at: row.updated_at,
    };
  }
}
