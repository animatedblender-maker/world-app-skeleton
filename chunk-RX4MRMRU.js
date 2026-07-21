import{a as y}from"./chunk-NQC6INBE.js";import{a as f}from"./chunk-LQQHCQP3.js";import{c as m}from"./chunk-O6RSSF7I.js";import{b as p,k as r,n as a}from"./chunk-X6NOM4Z7.js";import{a as n,b as d}from"./chunk-2NFLSA4Y.js";var h=`
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
`,g=`
query NotificationsUnreadCount {
  notificationsUnreadCount
}
`,C=`
mutation MarkNotificationRead($id: ID!) {
  markNotificationRead(id: $id)
}
`,q=`
mutation MarkAllNotificationsRead {
  markAllNotificationsRead
}
`,v=class i{constructor(t,e){this.gql=t;this.auth=e}endpoint=f.graphqlEndpoint||"http://localhost:3000/graphql";async list(t=40,e){try{return await this.gql.request(h,{limit:t,before:e??null})}catch{return await this.quietRequest(h,{limit:t,before:e??null},{notifications:[]})}}async unreadCount(){try{return await this.gql.request(g)}catch{return await this.quietRequest(g,void 0,{notificationsUnreadCount:0})}}async markRead(t){return this.gql.request(C,{id:t})}async markAllRead(){return this.gql.request(q)}async quietRequest(t,e,s){try{let c=await this.auth.getAccessToken(),u=await fetch(this.endpoint,{method:"POST",headers:n({"content-type":"application/json",accept:"application/json"},c?{authorization:`Bearer ${c}`}:{}),body:JSON.stringify({query:t,variables:e??{}})}),l=await u.text(),o=l?JSON.parse(l):null;return!u.ok||o?.errors?.length||!o?.data?s:o.data}catch{return s}}static \u0275fac=function(e){return new(e||i)(a(y),a(m))};static \u0275prov=r({token:i,factory:i.\u0275fac,providedIn:"root"})};var N=class i{stateSubject=new p({open:!1,mode:"post",countryCode:null,countryName:null});state$=this.stateSubject.asObservable();get snapshot(){return this.stateSubject.value}open(t,e){this.stateSubject.next({open:!0,mode:t,countryCode:e?.countryCode?.trim().toUpperCase()||null,countryName:e?.countryName?.trim()||null})}close(){let t=this.stateSubject.value;t.open&&this.stateSubject.next(d(n({},t),{open:!1}))}static \u0275fac=function(e){return new(e||i)};static \u0275prov=r({token:i,factory:i.\u0275fac,providedIn:"root"})};export{v as a,N as b};
