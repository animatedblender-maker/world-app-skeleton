import{a as p}from"./chunk-6PQF7OTW.js";import{a as o}from"./chunk-C7BVNPGH.js";import{b as l}from"./chunk-MF2Z2AUA.js";import{o as s,r as c}from"./chunk-OML24CZB.js";var m=`
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
`,b=`
mutation MarkAllNotificationsRead {
  markAllNotificationsRead
}
`,d=class e{constructor(i){this.gql=i}async list(i=40,t){return this.gql.request(m,{limit:i,before:t??null})}async unreadCount(){return this.gql.request(y)}async markRead(i){return this.gql.request(h,{id:i})}async markAllRead(){return this.gql.request(b)}static \u0275fac=function(t){return new(t||e)(c(p))};static \u0275prov=s({token:e,factory:e.\u0275fac,providedIn:"root"})};var f=class e{constructor(i){this.auth=i}swUrl="/sw.js";registrationPromise=null;isSupported(){return typeof window<"u"&&"serviceWorker"in navigator&&"PushManager"in window&&!!o.pushPublicKey}async syncIfGranted(){this.isSupported()&&"Notification"in window&&Notification.permission==="granted"&&await this.ensureSubscription()}async enableFromUserGesture(){!this.isSupported()||!("Notification"in window)||(Notification.permission==="default"?await Notification.requestPermission():Notification.permission)!=="granted"||await this.ensureSubscription()}async ensureSubscription(){let i=await this.getRegistration(),r=await i.pushManager.getSubscription()??await i.pushManager.subscribe({userVisibleOnly:!0,applicationServerKey:this.urlBase64ToUint8Array(o.pushPublicKey)});await this.sendSubscription(r)}async getRegistration(){return this.registrationPromise||(this.registrationPromise=navigator.serviceWorker.register(this.swUrl)),this.registrationPromise}async sendSubscription(i){let t=await this.auth.getAccessToken();if(!t)return;let r=i.toJSON();if(!r?.endpoint||!r?.keys?.p256dh||!r?.keys?.auth)return;let n=o.apiBaseUrl||o.graphqlEndpoint.replace(/\/graphql$/,"");await fetch(`${n}/push/subscribe`,{method:"POST",headers:{"content-type":"application/json",Authorization:`Bearer ${t}`},body:JSON.stringify({subscription:r,userAgent:navigator.userAgent})})}urlBase64ToUint8Array(i){let t="=".repeat((4-i.length%4)%4),r=(i+t).replace(/-/g,"+").replace(/_/g,"/"),n=window.atob(r),u=new Uint8Array(n.length);for(let a=0;a<n.length;++a)u[a]=n.charCodeAt(a);return u.buffer}static \u0275fac=function(t){return new(t||e)(c(l))};static \u0275prov=s({token:e,factory:e.\u0275fac,providedIn:"root"})};export{d as a,f as b};
