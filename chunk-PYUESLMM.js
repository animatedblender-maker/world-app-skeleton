import{a as f}from"./chunk-F5Z5FJX6.js";import{a as m}from"./chunk-6PQF7OTW.js";import{o as c,r as u}from"./chunk-OML24CZB.js";var _=`
query Countries {
  countries {
    countries {
      id
      name
      iso
      continent
      center { lat lng }
    }
  }
}
`,y=`
query MeProfile {
  meProfile {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,p=`
mutation UpdateProfile($input: UpdateProfileInput!) {
  updateProfile(input: $input) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,g=`
query ProfileByUsername($username: String!) {
  profileByUsername(username: $username) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,P=`
query ProfileById($user_id: ID!) {
  profileById(user_id: $user_id) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,q=`
query SearchProfiles($query: String!, $limit: Int) {
  searchProfiles(query: $query, limit: $limit) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,d=class l{constructor(e,r){this.gql=e;this.fakeData=r}async countries(){return this.gql.request(_)}async meProfile(){return this.gql.request(y)}async updateProfile(e){return this.gql.request(p,{input:e})}async profileByUsername(e){let r=String(e||"").trim().replace(/^@/,"");if(r){let t=await this.fakeData.getProfileByUsername(r);if(t)return{profileByUsername:t}}return this.gql.request(g,{username:r})}async profileById(e){let r=String(e||"").trim();if(r){let t=await this.fakeData.getProfileById(r);if(t)return{profileById:t}}return this.gql.request(P,{user_id:r})}isComplete(e){return e?!!e.display_name&&!!e.country_code&&e.country_name!=="Unknown":!1}async searchProfiles(e,r=6){let t=String(e||"").trim();if(!t)return{searchProfiles:[]};let[n,i]=await Promise.allSettled([this.gql.request(q,{query:t,limit:r}),this.fakeData.searchProfiles(t,r)]),s=n.status==="fulfilled"?n.value.searchProfiles??[]:[],a=i.status==="fulfilled"?i.value:[];return{searchProfiles:this.mergeProfiles(s,a,r)}}mergeProfiles(e,r,t){let n=[],i=new Set,s=a=>{let o=a.user_id||a.username||"";!o||i.has(o)||(i.add(o),n.push(a))};return e.forEach(s),r.forEach(s),n.slice(0,Math.max(1,t))}static \u0275fac=function(r){return new(r||l)(u(m),u(f))};static \u0275prov=c({token:l,factory:l.\u0275fac,providedIn:"root"})};export{d as a};
