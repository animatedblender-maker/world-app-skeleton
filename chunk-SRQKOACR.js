import{a as o}from"./chunk-7DJA5TI4.js";import{k as d,n as r}from"./chunk-SPQ2JWKS.js";var c=class i{constructor(e){this.gql=e}async myCampaigns(){let e=`
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
    `,{myAdCampaigns:t}=await this.gql.request(e);return t??[]}async createCampaign(e){let t=`
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
    `,{createAdCampaign:n}=await this.gql.request(t,{input:e});return n}async updateCampaign(e,t){let n=`
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
    `,{updateAdCampaign:a}=await this.gql.request(n,{campaignId:e,input:t});return a}async createCreative(e,t){let n=`
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
    `,{createAdCreative:a}=await this.gql.request(n,{campaignId:e,input:t});return a}async updateCreative(e,t){let n=`
      mutation UpdateAdCreative($creativeId: ID!, $input: AdCreativeInput!) {
        updateAdCreative(creative_id: $creativeId, input: $input) {
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
    `,{updateAdCreative:a}=await this.gql.request(n,{creativeId:e,input:t});return a}async deleteCampaign(e){let t=`
      mutation DeleteAdCampaign($campaignId: ID!) {
        deleteAdCampaign(campaign_id: $campaignId)
      }
    `,{deleteAdCampaign:n}=await this.gql.request(t,{campaignId:e});return!!n}async serveVideoAd(e){let t=`
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
    `,{serveVideoAd:n}=await this.gql.request(t,e);return n}async debugServeVideoAd(e){let t=`
      query DebugServeVideoAd(
        $placement: String!
        $country_code: String
        $content_country_code: String
        $post_id: ID
      ) {
        debugServeVideoAd(
          placement: $placement
          country_code: $country_code
          content_country_code: $content_country_code
          post_id: $post_id
        ) {
          ok
          reason
          placement
          country_code
          content_country_code
          active_campaigns
          country_match_campaigns
          selected_campaign_id
        }
      }
    `,{debugServeVideoAd:n}=await this.gql.request(t,e);return n}async logImpression(e){let t=`
      mutation LogAdImpression($token: String!) {
        logAdImpression(impression_token: $token) { ok }
      }
    `,{logAdImpression:n}=await this.gql.request(t,{token:e});return!!n?.ok}async logClick(e){let t=`
      mutation LogAdClick($token: String!) {
        logAdClick(impression_token: $token) { ok }
      }
    `,{logAdClick:n}=await this.gql.request(t,{token:e});return!!n?.ok}static \u0275fac=function(t){return new(t||i)(r(o))};static \u0275prov=d({token:i,factory:i.\u0275fac,providedIn:"root"})};export{c as a};
