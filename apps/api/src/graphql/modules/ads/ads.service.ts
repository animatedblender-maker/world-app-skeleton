import { pool } from '../../../db.js';
import {
  logClick as attributionLogClick,
  logImpression as attributionLogImpression,
} from './ads.attribution.js';
import {
  getCreateEntitlement as billingGetCreateEntitlement,
  redeemCreatePurchase as billingRedeemCreatePurchase,
  resolveUserEmail as billingResolveUserEmail,
  type AdCreateEntitlement,
} from './ads.billing.js';
import {
  debugServeVideoAd as serveDebugServeVideoAd,
  serveVideoAd as serveServeVideoAd,
  type ServeVideoAdInput,
} from './ads.serve.js';
import {
  normalizeClickUrl,
  normalizeCountryCodeArray,
  normalizeMediaUrl,
} from './ads.urls.js';

export type { AdCreateEntitlement, ServeVideoAdInput };
export {
  AD_CAMPAIGN_CREATE_PRODUCT_ID,
  isAdsFreeCreateEmail,
} from './ads.billing.js';

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

export class AdsService {
  async resolveUserEmail(
    userId: string,
    jwtEmail?: string | null
  ): Promise<string | null> {
    return billingResolveUserEmail(userId, jwtEmail);
  }

  async getCreateEntitlement(
    userId: string,
    jwtEmail?: string | null
  ): Promise<AdCreateEntitlement> {
    return billingGetCreateEntitlement(userId, jwtEmail);
  }

  async redeemCreatePurchase(
    userId: string,
    input: {
      product_id: string;
      transaction_id: string;
      original_transaction_id?: string | null;
      jws?: string | null;
    }
  ): Promise<AdCreateEntitlement> {
    return billingRedeemCreatePurchase(userId, input);
  }

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
    input: AdCampaignInput,
    _opts?: { email?: string | null }
  ): Promise<AdCampaignRow & { creatives: AdCreativeRow[] }> {
    await this.ensureAdvertiser(userId);
    // Create is free. Advertisers set their own total/daily budgets; delivery
    // paces against those (see ads.serve). App Store create-IAP is retired.
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
    const campaignId = rows[0]!.id;
    const campaign = await this.campaignById(campaignId, userId);
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
    const normalized = this.normalizeCampaignInput({
      name: input?.name ?? existing.name,
      placement: input?.placement ?? existing.placement,
      status: input?.status ?? existing.status,
      target_country_codes: input?.target_country_codes ?? existing.target_country_codes,
      budget_cents: input?.budget_cents ?? existing.budget_cents,
      daily_budget_cents: input?.daily_budget_cents ?? existing.daily_budget_cents,
      start_at: input?.start_at ?? existing.start_at,
      end_at: input?.end_at ?? existing.end_at,
    });
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

  async deleteCampaign(campaignId: string, userId: string): Promise<boolean> {
    const { rowCount } = await pool.query(
      `
      delete from public.ad_campaigns
      where id = $1 and advertiser_user_id = $2
      `,
      [campaignId, userId]
    );
    return Number(rowCount ?? 0) > 0;
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

  async serveVideoAd(userId: string | null, input: ServeVideoAdInput) {
    return serveServeVideoAd(userId, input);
  }

  async debugServeVideoAd(input: ServeVideoAdInput) {
    return serveDebugServeVideoAd(input);
  }

  async logImpression(impressionToken: string, userId: string | null): Promise<boolean> {
    return attributionLogImpression(impressionToken, userId);
  }

  async logClick(impressionToken: string, userId: string | null): Promise<boolean> {
    return attributionLogClick(impressionToken, userId);
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
      target_country_codes: normalizeCountryCodeArray(input?.target_country_codes ?? []),
      budget_cents: Math.max(0, Math.floor(Number(input?.budget_cents ?? 0) || 0)),
      daily_budget_cents: Math.max(0, Math.floor(Number(input?.daily_budget_cents ?? 0) || 0)),
      start_at: this.normalizeDateTimeValue(input?.start_at ?? null),
      end_at: this.normalizeDateTimeValue(input?.end_at ?? null),
    };
  }

  private normalizeCreativeInput(input: AdCreativeInput): Required<AdCreativeInput> {
    const mediaUrl = normalizeMediaUrl(input?.media_url ?? null);
    if (!mediaUrl) throw new Error('Creative media URL must be a safe HTTP(S) URL.');
    const mediaKind = String(input?.media_kind ?? 'video').trim().toLowerCase();
    if (mediaKind !== 'video' && mediaKind !== 'image') {
      throw new Error('Creative media kind must be video or image.');
    }
    if (mediaKind === 'video' && !this.isDirectVideoUrl(mediaUrl)) {
      throw new Error(
        'Creative video URL must be a direct HTTP(S) file URL ending in .mp4, .webm, .mov, or .m4v.'
      );
    }
    const rawClick = String(input?.click_url ?? '').trim();
    const clickUrl = normalizeClickUrl(input?.click_url ?? null);
    if (rawClick && !clickUrl) {
      throw new Error(
        'Creative click URL must be http(s) without credentials or blocked hosts.'
      );
    }
    return {
      title: String(input?.title ?? '').trim() || null,
      body: String(input?.body ?? '').trim() || null,
      media_kind: mediaKind,
      media_url: mediaUrl,
      click_url: clickUrl,
      cta_label: String(input?.cta_label ?? '').trim() || null,
      duration_seconds: Math.max(3, Math.min(30, Math.floor(Number(input?.duration_seconds ?? 8) || 8))),
    };
  }

  private isDirectVideoUrl(url: string): boolean {
    const value = String(url || '').trim();
    if (!/^https?:\/\//i.test(value)) return false;
    return /\.(mp4|webm|mov|m4v)(\?.*)?(#.*)?$/i.test(value);
  }

  private normalizeDateTimeValue(value: string | null): string | null {
    const raw = String(value ?? '').trim();
    if (!raw) return null;
    const epochMs = /^[0-9]{10,16}$/.test(raw) ? Number(raw) : Number.NaN;
    const date = Number.isFinite(epochMs) ? new Date(epochMs) : new Date(raw);
    if (Number.isNaN(date.getTime())) {
      throw new Error(`Invalid datetime value: ${raw}`);
    }
    return date.toISOString();
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
      click_url: normalizeClickUrl(row.click_url ?? null),
      cta_label: row.cta_label ?? null,
      duration_seconds: Number(row.duration_seconds ?? 0),
      created_at: row.created_at,
      updated_at: row.updated_at,
    };
  }
}
