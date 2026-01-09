import{a as d}from"./chunk-257XYEMG.js";import{Ba as y,a as p,k as l,n as c}from"./chunk-XHC7PKXJ.js";var u=class n{constructor(e){this.auth=e}endpoint=d.graphqlEndpoint||"http://localhost:3000/graphql";async request(e,i){let m=await this.safeGetToken(),o,s="";try{o=await fetch(this.endpoint,{method:"POST",headers:p({"content-type":"application/json",accept:"application/json"},m?{authorization:`Bearer ${m}`}:{}),body:JSON.stringify({query:e,variables:i??{}})}),s=await o.text()}catch(r){let a=`GraphQL NETWORK error (endpoint=${this.endpoint}): ${r?.message??r}`;throw console.error("[gql] NETWORK",a),new Error(a)}let t=null;try{t=s?JSON.parse(s):null}catch{let r=`GraphQL NON-JSON response (HTTP ${o.status} ${o.statusText}) from ${this.endpoint}:
${s.slice(0,600)}`;throw console.error("[gql] NON-JSON",r),new Error(r)}if(!o.ok){let r=`GraphQL HTTP error ${o.status} ${o.statusText} from ${this.endpoint}:
${JSON.stringify(t).slice(0,800)}`;throw console.error("[gql] HTTP",r),new Error(r)}if(t?.errors?.length){console.error("[gql] GQL ERRORS",t.errors),console.error("[gql] GQL ERRORS JSON",JSON.stringify(t.errors));let r=t.errors[0],a=typeof r?.extensions?.code=="string"?r.extensions.code:null,_=a?`${r?.message??"GraphQL error."} (code=${a})`:r?.message??`GraphQL error: ${JSON.stringify(t.errors).slice(0,800)}`;throw new Error(_)}return t.data}async safeGetToken(){try{return await this.auth.getAccessToken()||null}catch(e){return console.warn("[gql] token missing:",e),null}}static \u0275fac=function(i){return new(i||n)(c(y))};static \u0275prov=l({token:n,factory:n.\u0275fac,providedIn:"root"})};var P=`
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
`,q=`
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
`,S=`
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
`,$=`
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
`,v=`
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
`,E=`
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
`,f=class n{constructor(e){this.gql=e}async countries(){return this.gql.request(P)}async meProfile(){return this.gql.request(q)}async updateProfile(e){return this.gql.request(S,{input:e})}async profileByUsername(e){return this.gql.request($,{username:e})}async profileById(e){return this.gql.request(v,{user_id:e})}isComplete(e){return e?!!e.display_name&&!!e.country_code&&e.country_name!=="Unknown":!1}async searchProfiles(e,i=6){return e.trim()?this.gql.request(E,{query:e.trim(),limit:i}):{searchProfiles:[]}}static \u0275fac=function(i){return new(i||n)(c(u))};static \u0275prov=l({token:n,factory:n.\u0275fac,providedIn:"root"})};export{u as a,f as b};
