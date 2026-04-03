import{a as o}from"./chunk-N75FU62O.js";import{k as r,n as d}from"./chunk-PMN7SPTA.js";var c=class a{constructor(t){this.gql=t}async myCampaigns(){let t=`
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
    `,{myAdCampaigns:e}=await this.gql.request(t);return e??[]}async createCampaign(t){let e=`
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
    `,{createAdCampaign:n}=await this.gql.request(e,{input:t});return n}async updateCampaign(t,e){let n=`
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
    `,{updateAdCampaign:i}=await this.gql.request(n,{campaignId:t,input:e});return i}async createCreative(t,e){let n=`
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
    `,{createAdCreative:i}=await this.gql.request(n,{campaignId:t,input:e});return i}async deleteCampaign(t){let e=`
      mutation DeleteAdCampaign($campaignId: ID!) {
        deleteAdCampaign(campaign_id: $campaignId)
      }
    `,{deleteAdCampaign:n}=await this.gql.request(e,{campaignId:t});return!!n}async serveVideoAd(t){let e=`
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
    `,{serveVideoAd:n}=await this.gql.request(e,t);return n}async debugServeVideoAd(t){let e=`
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
    `,{debugServeVideoAd:n}=await this.gql.request(e,t);return n}async logImpression(t){let e=`
      mutation LogAdImpression($token: String!) {
        logAdImpression(impression_token: $token) { ok }
      }
    `,{logAdImpression:n}=await this.gql.request(e,{token:t});return!!n?.ok}async logClick(t){let e=`
      mutation LogAdClick($token: String!) {
        logAdClick(impression_token: $token) { ok }
      }
    `,{logAdClick:n}=await this.gql.request(e,{token:t});return!!n?.ok}static \u0275fac=function(e){return new(e||a)(d(o))};static \u0275prov=r({token:a,factory:a.\u0275fac,providedIn:"root"})};export{c as a};
