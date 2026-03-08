import{a as l}from"./chunk-LJDR2ADK.js";import{a}from"./chunk-7DJA5TI4.js";import{k as n,n as s}from"./chunk-SPQ2JWKS.js";var f=class e{constructor(o,t){this.gql=o;this.fakeData=t}async counts(o){let t=await this.fakeData.getFollowCounts(o);if(t)return t;let i=`
      query FollowCounts($userId: ID!) {
        followCounts(user_id: $userId) {
          followers
          following
        }
      }
    `,{followCounts:r}=await this.gql.request(i,{userId:o});return r??{followers:0,following:0}}async isFollowing(o,t){if(o===t||await this.isFakeUser(t))return!1;let i=`
      query IsFollowing($target: ID!) {
        isFollowing(user_id: $target)
      }
    `,{isFollowing:r}=await this.gql.request(i,{target:t});return!!r}async follow(o,t){if(o===t||await this.isFakeUser(t))return;await this.gql.request(`
      mutation FollowUser($target: ID!) {
        followUser(target_id: $target)
      }
    `,{target:t})}async unfollow(o,t){if(o===t||await this.isFakeUser(t))return;await this.gql.request(`
      mutation UnfollowUser($target: ID!) {
        unfollowUser(target_id: $target)
      }
    `,{target:t})}async listFollowingIds(o){let t=`
      query FollowingIds {
        followingIds
      }
    `,{followingIds:i}=await this.gql.request(t);return i??[]}async isFakeUser(o){return o?!!await this.fakeData.getProfileById(o):!1}static \u0275fac=function(t){return new(t||e)(s(a),s(l))};static \u0275prov=n({token:e,factory:e.\u0275fac,providedIn:"root"})};export{f as a};
