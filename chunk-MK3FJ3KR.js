import{a as f}from"./chunk-LJDR2ADK.js";import{a as m}from"./chunk-7DJA5TI4.js";import{k as c,n as u}from"./chunk-SPQ2JWKS.js";var d=`
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
`,_=`
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
`,h=`
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
`,y=class s{constructor(e,r){this.gql=e;this.fakeData=r}async countries(){return this.gql.request(d)}async meProfile(){return this.gql.request(_)}async updateProfile(e){return this.gql.request(p,{input:e})}async profileByUsername(e){let r=String(e||"").trim().replace(/^@/,"");if(!r)return{profileByUsername:null};try{let n=await this.gql.request(g,{username:r});if(n?.profileByUsername)return n}catch{}let t=await this.fakeData.getProfileByUsername(r);return t?{profileByUsername:t}:{profileByUsername:null}}async profileById(e){let r=String(e||"").trim();if(!r)return{profileById:null};try{let n=await this.gql.request(P,{user_id:r});if(n?.profileById)return n}catch{}let t=await this.fakeData.getProfileById(r);return t?{profileById:t}:{profileById:null}}isComplete(e){return e?!!e.display_name&&!!e.country_name&&e.country_name!=="Unknown":!1}async searchProfiles(e,r=6){let t=String(e||"").trim();if(!t)return{searchProfiles:[]};let[n,i]=await Promise.allSettled([this.gql.request(h,{query:t,limit:r}),this.fakeData.searchProfiles(t,r)]),l=n.status==="fulfilled"?n.value.searchProfiles??[]:[],a=i.status==="fulfilled"?i.value:[];return{searchProfiles:this.mergeProfiles(l,a,r)}}mergeProfiles(e,r,t){let n=[],i=new Set,l=a=>{let o=a.user_id||a.username||"";!o||i.has(o)||(i.add(o),n.push(a))};return e.forEach(l),r.forEach(l),n.slice(0,Math.max(1,t))}static \u0275fac=function(r){return new(r||s)(u(m),u(f))};static \u0275prov=c({token:s,factory:s.\u0275fac,providedIn:"root"})};export{y as a};
