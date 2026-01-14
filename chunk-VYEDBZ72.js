import{a}from"./chunk-QGWRKH4Y.js";import{l as n,o as i}from"./chunk-EMTWPIOC.js";var s=`
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
`,l=`
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
`,o=`
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
`,c=`
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
`,_=`
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
`,m=`
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
`,u=class r{constructor(e){this.gql=e}async countries(){return this.gql.request(s)}async meProfile(){return this.gql.request(l)}async updateProfile(e){return this.gql.request(o,{input:e})}async profileByUsername(e){return this.gql.request(c,{username:e})}async profileById(e){return this.gql.request(_,{user_id:e})}isComplete(e){return e?!!e.display_name&&!!e.country_code&&e.country_name!=="Unknown":!1}async searchProfiles(e,t=6){return e.trim()?this.gql.request(m,{query:e.trim(),limit:t}):{searchProfiles:[]}}static \u0275fac=function(t){return new(t||r)(i(a))};static \u0275prov=n({token:r,factory:r.\u0275fac,providedIn:"root"})};export{u as a};
