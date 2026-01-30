import{a as u}from"./chunk-IEDO2SVM.js";import{a as l}from"./chunk-QUP2GB72.js";import{o as s,r as n}from"./chunk-5AGQDJWJ.js";var d=`
mutation DetectLocation($lat: Float!, $lng: Float!) {
  detectLocation(lat: $lat, lng: $lng) {
    countryCode
    countryName
    cityName
    source
  }
}
`,f=class r{constructor(e){this.gql=e}async detectViaGpsThenServer(e=8e3){let t=await this.getBrowserCoords(e);return t?(await this.gql.request(d,{lat:t.lat,lng:t.lng})).detectLocation??null:null}getBrowserCoords(e){return new Promise(t=>{if(!("geolocation"in navigator))return t(null);let o=!1,i=a=>{o||(o=!0,t(a))},c=window.setTimeout(()=>i(null),e);navigator.geolocation.getCurrentPosition(a=>{clearTimeout(c),i({lat:a.coords.latitude,lng:a.coords.longitude})},()=>{clearTimeout(c),i(null)},{enableHighAccuracy:!1,timeout:e,maximumAge:6e4})})}static \u0275fac=function(t){return new(t||r)(n(l))};static \u0275prov=s({token:r,factory:r.\u0275fac,providedIn:"root"})};var g=class r{constructor(e,t){this.gql=e;this.fakeData=t}async counts(e){let t=await this.fakeData.getFollowCounts(e);if(t)return t;let o=`
      query FollowCounts($userId: ID!) {
        followCounts(user_id: $userId) {
          followers
          following
        }
      }
    `,{followCounts:i}=await this.gql.request(o,{userId:e});return i??{followers:0,following:0}}async isFollowing(e,t){if(e===t||await this.isFakeUser(t))return!1;let o=`
      query IsFollowing($target: ID!) {
        isFollowing(user_id: $target)
      }
    `,{isFollowing:i}=await this.gql.request(o,{target:t});return!!i}async follow(e,t){if(e===t||await this.isFakeUser(t))return;await this.gql.request(`
      mutation FollowUser($target: ID!) {
        followUser(target_id: $target)
      }
    `,{target:t})}async unfollow(e,t){if(e===t||await this.isFakeUser(t))return;await this.gql.request(`
      mutation UnfollowUser($target: ID!) {
        unfollowUser(target_id: $target)
      }
    `,{target:t})}async listFollowingIds(e){let t=`
      query FollowingIds {
        followingIds
      }
    `,{followingIds:o}=await this.gql.request(t);return o??[]}async isFakeUser(e){return e?!!await this.fakeData.getProfileById(e):!1}static \u0275fac=function(t){return new(t||r)(n(l),n(u))};static \u0275prov=s({token:r,factory:r.\u0275fac,providedIn:"root"})};export{f as a,g as b};
