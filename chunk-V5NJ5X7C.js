import{a as m}from"./chunk-36NYYCNU.js";import{a as f}from"./chunk-TYADZYHJ.js";import{c as d}from"./chunk-ZPCH672B.js";import{k as l,n as r}from"./chunk-JPJ3TCZX.js";import{a as u}from"./chunk-2NFLSA4Y.js";var p=`
query Notifications($limit: Int, $before: String) {
  notifications(limit: $limit, before: $before) {
    id
    user_id
    actor_id
    type
    entity_type
    entity_id
    read_at
    created_at
    actor {
      user_id
      display_name
      username
      avatar_url
    }
  }
}
`,y=`
query NotificationsUnreadCount {
  notificationsUnreadCount
}
`,h=`
mutation MarkNotificationRead($id: ID!) {
  markNotificationRead(id: $id)
}
`,q=`
mutation MarkAllNotificationsRead {
  markAllNotificationsRead
}
`,g=class n{constructor(t,i){this.gql=t;this.auth=i}endpoint=f.graphqlEndpoint||"http://localhost:3000/graphql";async list(t=40,i){try{return await this.gql.request(p,{limit:t,before:i??null})}catch{return await this.quietRequest(p,{limit:t,before:i??null},{notifications:[]})}}async unreadCount(){try{return await this.gql.request(y)}catch{return await this.quietRequest(y,void 0,{notificationsUnreadCount:0})}}async markRead(t){return this.gql.request(h,{id:t})}async markAllRead(){return this.gql.request(q)}async quietRequest(t,i,a){try{let o=await this.auth.getAccessToken(),s=await fetch(this.endpoint,{method:"POST",headers:u({"content-type":"application/json",accept:"application/json"},o?{authorization:`Bearer ${o}`}:{}),body:JSON.stringify({query:t,variables:i??{}})}),c=await s.text(),e=c?JSON.parse(c):null;return!s.ok||e?.errors?.length||!e?.data?a:e.data}catch{return a}}static \u0275fac=function(i){return new(i||n)(r(m),r(d))};static \u0275prov=l({token:n,factory:n.\u0275fac,providedIn:"root"})};export{g as a};
