import { Injectable } from '@angular/core';

import { GqlService } from './gql.service';

export type AdCreativeModel = {
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

export type AdCampaignModel = {
  id: string;
  advertiser_user_id: string;
  name: string;
  status: string;
  placement: string;
  target_country_codes: string[];
  budget_cents: number;
  daily_budget_cents: number;
  start_at: string | null;
  end_at: string | null;
  created_at: string;
  updated_at: string;
  impression_count: number;
  click_count: number;
  creatives: AdCreativeModel[];
};

export type AdSlotModel = {
  impression_token: string;
  skip_after_seconds: number;
  campaign: AdCampaignModel;
  creative: AdCreativeModel;
};

@Injectable({ providedIn: 'root' })
export class AdsService {
  constructor(private gql: GqlService) {}

  async myCampaigns(): Promise<AdCampaignModel[]> {
    const query = `
      query MyAdCampaigns {
        myAdCampaigns {
          id
          advertiser_user_id
          name
          status
          placement
          target_country_codes
          budget_cents
          daily_budget_cents
          start_at
          end_at
          created_at
          updated_at
          impression_count
          click_count
          creatives {
            id
            campaign_id
            title
            body
            media_kind
            media_url
            click_url
            cta_label
            duration_seconds
            created_at
            updated_at
          }
        }
      }
    `;
    const { myAdCampaigns } = await this.gql.request<{ myAdCampaigns: AdCampaignModel[] }>(query);
    return myAdCampaigns ?? [];
  }

  async createCampaign(input: {
    name: string;
    placement: 'video' | 'reel';
    status?: string | null;
    target_country_codes?: string[] | null;
    budget_cents?: number | null;
    daily_budget_cents?: number | null;
    start_at?: string | null;
    end_at?: string | null;
  }): Promise<AdCampaignModel> {
    const mutation = `
      mutation CreateAdCampaign($input: AdCampaignInput!) {
        createAdCampaign(input: $input) {
          id
          advertiser_user_id
          name
          status
          placement
          target_country_codes
          budget_cents
          daily_budget_cents
          start_at
          end_at
          created_at
          updated_at
          impression_count
          click_count
          creatives {
            id
            campaign_id
            title
            body
            media_kind
            media_url
            click_url
            cta_label
            duration_seconds
            created_at
            updated_at
          }
        }
      }
    `;
    const { createAdCampaign } = await this.gql.request<{ createAdCampaign: AdCampaignModel }>(
      mutation,
      { input }
    );
    return createAdCampaign;
  }

  async updateCampaign(
    campaignId: string,
    input: {
      name: string;
      placement: 'video' | 'reel';
      status?: string | null;
      target_country_codes?: string[] | null;
      budget_cents?: number | null;
      daily_budget_cents?: number | null;
      start_at?: string | null;
      end_at?: string | null;
    }
  ): Promise<AdCampaignModel> {
    const mutation = `
      mutation UpdateAdCampaign($campaignId: ID!, $input: AdCampaignInput!) {
        updateAdCampaign(campaign_id: $campaignId, input: $input) {
          id
          advertiser_user_id
          name
          status
          placement
          target_country_codes
          budget_cents
          daily_budget_cents
          start_at
          end_at
          created_at
          updated_at
          impression_count
          click_count
          creatives {
            id
            campaign_id
            title
            body
            media_kind
            media_url
            click_url
            cta_label
            duration_seconds
            created_at
            updated_at
          }
        }
      }
    `;
    const { updateAdCampaign } = await this.gql.request<{ updateAdCampaign: AdCampaignModel }>(
      mutation,
      { campaignId, input }
    );
    return updateAdCampaign;
  }

  async createCreative(
    campaignId: string,
    input: {
      title?: string | null;
      body?: string | null;
      media_kind?: 'video' | 'image' | null;
      media_url: string;
      click_url?: string | null;
      cta_label?: string | null;
      duration_seconds?: number | null;
    }
  ): Promise<AdCreativeModel> {
    const mutation = `
      mutation CreateAdCreative($campaignId: ID!, $input: AdCreativeInput!) {
        createAdCreative(campaign_id: $campaignId, input: $input) {
          id
          campaign_id
          title
          body
          media_kind
          media_url
          click_url
          cta_label
          duration_seconds
          created_at
          updated_at
        }
      }
    `;
    const { createAdCreative } = await this.gql.request<{ createAdCreative: AdCreativeModel }>(
      mutation,
      { campaignId, input }
    );
    return createAdCreative;
  }

  async deleteCampaign(campaignId: string): Promise<boolean> {
    const mutation = `
      mutation DeleteAdCampaign($campaignId: ID!) {
        deleteAdCampaign(campaign_id: $campaignId)
      }
    `;
    const { deleteAdCampaign } = await this.gql.request<{ deleteAdCampaign: boolean }>(mutation, {
      campaignId,
    });
    return !!deleteAdCampaign;
  }

  async serveVideoAd(input: {
    placement: 'video' | 'reel';
    country_code?: string | null;
    content_country_code?: string | null;
    post_id?: string | null;
  }): Promise<AdSlotModel | null> {
    const query = `
      query ServeVideoAd(
        $placement: String!
        $country_code: String
        $content_country_code: String
        $post_id: ID
      ) {
        serveVideoAd(
          placement: $placement
          country_code: $country_code
          content_country_code: $content_country_code
          post_id: $post_id
        ) {
          impression_token
          skip_after_seconds
          campaign {
            id
            advertiser_user_id
            name
            status
            placement
            target_country_codes
            budget_cents
            daily_budget_cents
            start_at
            end_at
            created_at
            updated_at
            impression_count
            click_count
            creatives {
              id
              campaign_id
              title
              body
              media_kind
              media_url
              click_url
              cta_label
              duration_seconds
              created_at
              updated_at
            }
          }
          creative {
            id
            campaign_id
            title
            body
            media_kind
            media_url
            click_url
            cta_label
            duration_seconds
            created_at
            updated_at
          }
        }
      }
    `;
    const { serveVideoAd } = await this.gql.request<{ serveVideoAd: AdSlotModel | null }>(query, input);
    return serveVideoAd;
  }

  async logImpression(impressionToken: string): Promise<boolean> {
    const mutation = `
      mutation LogAdImpression($token: String!) {
        logAdImpression(impression_token: $token) { ok }
      }
    `;
    const { logAdImpression } = await this.gql.request<{ logAdImpression: { ok: boolean } }>(
      mutation,
      { token: impressionToken }
    );
    return !!logAdImpression?.ok;
  }

  async logClick(impressionToken: string): Promise<boolean> {
    const mutation = `
      mutation LogAdClick($token: String!) {
        logAdClick(impression_token: $token) { ok }
      }
    `;
    const { logAdClick } = await this.gql.request<{ logAdClick: { ok: boolean } }>(mutation, {
      token: impressionToken,
    });
    return !!logAdClick?.ok;
  }
}
