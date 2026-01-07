import{a as d}from"./chunk-NOJK5XQQ.js";import{Ba as y,a as p,k as l,n as u}from"./chunk-XHC7PKXJ.js";var c=class t{constructor(e){this.auth=e}endpoint=d.graphqlEndpoint||"http://localhost:3000/graphql";async request(e,n){let m=await this.safeGetToken(),i,o="";try{i=await fetch(this.endpoint,{method:"POST",headers:p({"content-type":"application/json",accept:"application/json"},m?{authorization:`Bearer ${m}`}:{}),body:JSON.stringify({query:e,variables:n??{}})}),o=await i.text()}catch(r){let s=`GraphQL NETWORK error (endpoint=${this.endpoint}): ${r?.message??r}`;throw console.error("[gql] NETWORK",s),new Error(s)}let a=null;try{a=o?JSON.parse(o):null}catch{let r=`GraphQL NON-JSON response (HTTP ${i.status} ${i.statusText}) from ${this.endpoint}:
${o.slice(0,600)}`;throw console.error("[gql] NON-JSON",r),new Error(r)}if(!i.ok){let r=`GraphQL HTTP error ${i.status} ${i.statusText} from ${this.endpoint}:
${JSON.stringify(a).slice(0,800)}`;throw console.error("[gql] HTTP",r),new Error(r)}if(a?.errors?.length){console.error("[gql] GQL ERRORS",a.errors);let s=a.errors[0]?.message??`GraphQL error: ${JSON.stringify(a.errors).slice(0,800)}`;throw new Error(s)}return a.data}async safeGetToken(){try{return await this.auth.getAccessToken()||null}catch(e){return console.warn("[gql] token missing:",e),null}}static \u0275fac=function(n){return new(n||t)(u(y))};static \u0275prov=l({token:t,factory:t.\u0275fac,providedIn:"root"})};var h=`
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
`,P=`
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
`,q=`
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
`,v=`
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
`,$=`
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
`,S=`
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
`,_=class t{constructor(e){this.gql=e}async countries(){return this.gql.request(h)}async meProfile(){return this.gql.request(P)}async updateProfile(e){return this.gql.request(q,{input:e})}async profileByUsername(e){return this.gql.request(v,{username:e})}async profileById(e){return this.gql.request($,{user_id:e})}isComplete(e){return e?!!e.display_name&&!!e.country_code&&e.country_name!=="Unknown":!1}async searchProfiles(e,n=6){return e.trim()?this.gql.request(S,{query:e.trim(),limit:n}):{searchProfiles:[]}}static \u0275fac=function(n){return new(n||t)(u(c))};static \u0275prov=l({token:t,factory:t.\u0275fac,providedIn:"root"})};export{c as a,_ as b};
