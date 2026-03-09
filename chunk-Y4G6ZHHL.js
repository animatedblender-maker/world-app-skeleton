import{a as d}from"./chunk-7DJA5TI4.js";import{a as u}from"./chunk-LQQHCQP3.js";import{k as c,n as l}from"./chunk-SPQ2JWKS.js";import{a as o,b as s}from"./chunk-2NFLSA4Y.js";var m=`
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
`,p=`
query NotificationsUnreadCount {
  notificationsUnreadCount
}
`,g=`
mutation MarkNotificationRead($id: ID!) {
  markNotificationRead(id: $id)
}
`,_=`
mutation MarkAllNotificationsRead {
  markAllNotificationsRead
}
`,f=class a{constructor(r){this.gql=r}async list(r=40,t){return{notifications:((await this.gql.request(m,{limit:r,before:t??null})).notifications??[]).map(i=>s(o({},i),{actor:i.actor?s(o({},i.actor),{avatar_url:this.normalizeAvatarUrl(i.actor.avatar_url)}):i.actor}))}}async unreadCount(){return this.gql.request(p)}async markRead(r){return this.gql.request(g,{id:r})}async markAllRead(){return this.gql.request(_)}normalizeAvatarUrl(r){let t=String(r??"").trim();if(!t)return null;if(t.startsWith("data:")||t.startsWith("blob:"))return t;let e=n=>{let i=n.replace(/^\/+/,"").replace(/^storage\/v1\/object\/(?:public|sign)\/avatars\/+/i,"").replace(/^avatars\/+/i,"");return i?`${u.supabaseUrl}/storage/v1/object/public/avatars/${i}`:null};if(/^https?:\/\//i.test(t)){try{let n=new URL(t);if(/\/storage\/v1\/object\/(?:public|sign)\/avatars\//i.test(n.pathname))return e(decodeURIComponent(n.pathname))}catch{return t}return t}return e(t)}static \u0275fac=function(t){return new(t||a)(l(d))};static \u0275prov=c({token:a,factory:a.\u0275fac,providedIn:"root"})};export{f as a};
