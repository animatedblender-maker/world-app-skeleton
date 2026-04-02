import{a}from"./chunk-7DJA5TI4.js";import{k as n,n as e}from"./chunk-SPQ2JWKS.js";var s=`
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
`,c=`
query NotificationsUnreadCount {
  notificationsUnreadCount
}
`,l=`
mutation MarkNotificationRead($id: ID!) {
  markNotificationRead(id: $id)
}
`,u=`
mutation MarkAllNotificationsRead {
  markAllNotificationsRead
}
`,o=class i{constructor(t){this.gql=t}async list(t=40,r){return this.gql.request(s,{limit:t,before:r??null})}async unreadCount(){return this.gql.request(c)}async markRead(t){return this.gql.request(l,{id:t})}async markAllRead(){return this.gql.request(u)}static \u0275fac=function(r){return new(r||i)(e(a))};static \u0275prov=n({token:i,factory:i.\u0275fac,providedIn:"root"})};export{o as a};
