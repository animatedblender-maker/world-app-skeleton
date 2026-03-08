import{a as m}from"./chunk-LJDR2ADK.js";import{a as f}from"./chunk-7DJA5TI4.js";import{k as c,n as u}from"./chunk-SPQ2JWKS.js";var p=`
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
`,g=`
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
`,P=`
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
`,h=`
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
`,q=`
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
`,d=`
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
`,y=class o{constructor(r,e){this.gql=r;this.fakeData=e}async countries(){return this.gql.request(p)}async meProfile(){return this.gql.request(g)}async updateProfile(r){return this.gql.request(P,{input:r})}async profileByUsername(r){let e=String(r||"").trim().replace(/^@/,"");if(!e)return{profileByUsername:null};try{let n=await this.gql.request(h,{username:e});if(n?.profileByUsername)return n}catch{}let t=await this.fakeData.getProfileByUsername(e);return t?{profileByUsername:t}:{profileByUsername:null}}async profileById(r){let e=String(r||"").trim();if(!e)return{profileById:null};try{let n=await this.gql.request(q,{user_id:e});if(n?.profileById)return n}catch{}let t=await this.fakeData.getProfileById(e);return t?{profileById:t}:{profileById:null}}isComplete(r){return r?!!r.display_name&&!!r.country_name&&r.country_name!=="Unknown":!1}async searchProfiles(r,e=6){let t=String(r||"").trim();if(!t)return{searchProfiles:[]};let n=e<=0?void 0:e,l=e<=0?5e3:e,[a,i]=await Promise.allSettled([this.gql.request(d,{query:t,limit:n}),this.fakeData.searchProfiles(t,l)]),s=a.status==="fulfilled"?a.value.searchProfiles??[]:[],_=i.status==="fulfilled"?i.value:[];return{searchProfiles:this.mergeProfiles(s,_,e)}}async searchProfilesReal(r,e=6){let t=String(r||"").trim();if(!t)return{searchProfiles:[]};let n=e<=0?void 0:e;try{return await this.gql.request(d,{query:t,limit:n})}catch{return{searchProfiles:[]}}}mergeProfiles(r,e,t){let n=[],l=new Set,a=i=>{let s=i.user_id||i.username||"";!s||l.has(s)||(l.add(s),n.push(i))};return r.forEach(a),e.forEach(a),t<=0?n:n.slice(0,Math.max(1,t))}static \u0275fac=function(e){return new(e||o)(u(f),u(m))};static \u0275prov=c({token:o,factory:o.\u0275fac,providedIn:"root"})};export{y as a};
