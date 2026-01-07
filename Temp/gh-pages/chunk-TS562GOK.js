import{a as s}from"./chunk-Y72RG6DO.js";import{k as i,n as a}from"./chunk-XHC7PKXJ.js";var l=class e{constructor(t){this.gql=t}async listByCountry(t,r=25){let o=`
      query PostsByCountry($code: String!, $limit: Int) {
        postsByCountry(country_code: $code, limit: $limit) {
          id
          title
          body
          media_type
          media_url
          created_at
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
    `,{postsByCountry:n}=await this.gql.request(o,{code:t,limit:r});return(n??[]).map(c=>this.mapPost(c))}async createPost(t){if(!t.authorId)throw new Error("authorId is required to post.");let r=`
      mutation CreatePost($input: CreatePostInput!) {
        createPost(input: $input) {
          id
          title
          body
          media_type
          media_url
          created_at
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
    `,o={title:t.title?.trim()||null,body:t.body.trim(),country_name:t.countryName,country_code:t.countryCode,city_name:t.cityName??null},{createPost:n}=await this.gql.request(r,{input:o});return this.mapPost(n)}mapPost(t){return{id:t.id,title:t.title??null,body:t.body??"",media_type:t.media_type??"none",media_url:t.media_url??null,created_at:t.created_at,author_id:t.author_id,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:t.author.avatar_url,country_name:t.author.country_name,country_code:t.author.country_code}:null}}static \u0275fac=function(r){return new(r||e)(a(s))};static \u0275prov=i({token:e,factory:e.\u0275fac,providedIn:"root"})};var u=class e{constructor(t){this.gql=t}async counts(t){let r=`
      query FollowCounts($userId: ID!) {
        followCounts(user_id: $userId) {
          followers
          following
        }
      }
    `,{followCounts:o}=await this.gql.request(r,{userId:t});return o??{followers:0,following:0}}async isFollowing(t,r){if(t===r)return!1;let o=`
      query IsFollowing($target: ID!) {
        isFollowing(user_id: $target)
      }
    `,{isFollowing:n}=await this.gql.request(o,{target:r});return!!n}async follow(t,r){if(t===r)return;await this.gql.request(`
      mutation FollowUser($target: ID!) {
        followUser(target_id: $target)
      }
    `,{target:r})}async unfollow(t,r){if(t===r)return;await this.gql.request(`
      mutation UnfollowUser($target: ID!) {
        unfollowUser(target_id: $target)
      }
    `,{target:r})}async listFollowingIds(t){let r=`
      query FollowingIds {
        followingIds
      }
    `,{followingIds:o}=await this.gql.request(r);return o??[]}static \u0275fac=function(r){return new(r||e)(a(s))};static \u0275prov=i({token:e,factory:e.\u0275fac,providedIn:"root"})};export{l as a,u as b};
