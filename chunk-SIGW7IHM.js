import{a as _}from"./chunk-7DJA5TI4.js";import{k as o,n as a}from"./chunk-SPQ2JWKS.js";var m=class s{constructor(e){this.gql=e}async countryConflictUpdates(e,t=10,n=0){let i=`
      query CountryConflictUpdates($country_code: String!, $limit: Int, $offset: Int) {
        countryConflictUpdates(country_code: $country_code, limit: $limit, offset: $offset) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{countryConflictUpdates:r}=await this.gql.request(i,{country_code:e,limit:t,offset:n});return r??[]}async globalConflictUpdates(e=10,t=0){let n=`
      query GlobalConflictUpdates($limit: Int, $offset: Int) {
        globalConflictUpdates(limit: $limit, offset: $offset) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{globalConflictUpdates:i}=await this.gql.request(n,{limit:e,offset:t});return i??[]}async item(e){let t=`
      query ExternalNewsItem($news_item_id: ID!) {
        externalNewsItem(news_item_id: $news_item_id) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{externalNewsItem:n}=await this.gql.request(t,{news_item_id:e});return n??null}async comments(e,t=25,n){let i=`
      query ExternalNewsComments($news_item_id: ID!, $limit: Int, $before: String) {
        externalNewsComments(news_item_id: $news_item_id, limit: $limit, before: $before) {
          id
          news_item_id
          parent_id
          author_id
          body
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{externalNewsComments:r}=await this.gql.request(i,{news_item_id:e,limit:t,before:n??null});return r??[]}async addComment(e,t,n){let i=`
      mutation AddExternalNewsComment($news_item_id: ID!, $body: String!, $parent_id: ID) {
        addExternalNewsComment(news_item_id: $news_item_id, body: $body, parent_id: $parent_id) {
          id
          news_item_id
          parent_id
          author_id
          body
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{addExternalNewsComment:r}=await this.gql.request(i,{news_item_id:e,body:String(t??"").trim(),parent_id:n??null});return r}async shareToCountry(e,t){let n=`
      mutation ShareExternalNewsToCountry($news_item_id: ID!, $body: String, $visibility: String) {
        shareExternalNewsToCountry(news_item_id: $news_item_id, body: $body, visibility: $visibility) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{shareExternalNewsToCountry:i}=await this.gql.request(n,{news_item_id:e,body:t??null,visibility:"country"});return i}async like(e){let t=`
      mutation LikeExternalNews($news_item_id: ID!) {
        likeExternalNews(news_item_id: $news_item_id) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{likeExternalNews:n}=await this.gql.request(t,{news_item_id:e});return n}async unlike(e){let t=`
      mutation UnlikeExternalNews($news_item_id: ID!) {
        unlikeExternalNews(news_item_id: $news_item_id) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{unlikeExternalNews:n}=await this.gql.request(t,{news_item_id:e});return n}static \u0275fac=function(t){return new(t||s)(a(_))};static \u0275prov=o({token:s,factory:s.\u0275fac,providedIn:"root"})};export{m as a};
