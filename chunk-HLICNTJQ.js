import{a as g}from"./chunk-7DJA5TI4.js";import{b as l}from"./chunk-KO5X6LCN.js";import{b as m,k as _,n as u}from"./chunk-SPQ2JWKS.js";import{a as d,b as o}from"./chunk-2NFLSA4Y.js";var p=`
query Conversations($limit: Int) {
  conversations(limit: $limit) {
    id
    is_direct
    created_at
    updated_at
    last_message_at
    members {
      user_id
      display_name
      username
      avatar_url
      country_name
      country_code
      last_read_at
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      media_type
      media_path
      media_name
      media_mime
      media_size
      created_at
      updated_at
      sender {
        user_id
        display_name
        username
        avatar_url
        country_name
        country_code
      }
    }
  }
}
`,y=`
query ConversationById($conversationId: ID!) {
  conversationById(conversation_id: $conversationId) {
    id
    is_direct
    created_at
    updated_at
    last_message_at
    members {
      user_id
      display_name
      username
      avatar_url
      country_name
      country_code
      last_read_at
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      media_type
      media_path
      media_name
      media_mime
      media_size
      created_at
      updated_at
      sender {
        user_id
        display_name
        username
        avatar_url
        country_name
        country_code
      }
    }
  }
}
`,v=`
query MessagesByConversation($conversationId: ID!, $limit: Int, $before: String) {
  messagesByConversation(conversation_id: $conversationId, limit: $limit, before: $before) {
    id
    conversation_id
    sender_id
    body
    media_type
    media_path
    media_name
    media_mime
    media_size
    created_at
    updated_at
    sender {
      user_id
      display_name
      username
      avatar_url
      country_name
      country_code
    }
  }
}
`,h=`
mutation StartConversation($targetId: ID!) {
  startConversation(target_id: $targetId) {
    id
    is_direct
    created_at
    updated_at
    last_message_at
    members {
      user_id
      display_name
      username
      avatar_url
      country_name
      country_code
      last_read_at
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      created_at
      updated_at
      sender {
        user_id
        display_name
        username
        avatar_url
        country_name
        country_code
      }
    }
  }
}
`,S=`
mutation SendMessage($conversationId: ID!, $body: String, $mediaType: String, $mediaPath: String, $mediaName: String, $mediaMime: String, $mediaSize: Int) {
  sendMessage(
    conversation_id: $conversationId,
    body: $body,
    media_type: $mediaType,
    media_path: $mediaPath,
    media_name: $mediaName,
    media_mime: $mediaMime,
    media_size: $mediaSize
  ) {
    id
    conversation_id
    sender_id
    body
    media_type
    media_path
    media_name
    media_mime
    media_size
    created_at
    updated_at
    sender {
      user_id
      display_name
      username
      avatar_url
      country_name
      country_code
    }
  }
}
`,C=`
mutation UpdateMessage($messageId: ID!, $body: String!) {
  updateMessage(message_id: $messageId, body: $body) {
    id
    conversation_id
    sender_id
    body
    media_type
    media_path
    media_name
    media_mime
    media_size
    created_at
    updated_at
    sender {
      user_id
      display_name
      username
      avatar_url
      country_name
      country_code
    }
  }
}
`,M=`
mutation DeleteMessage($messageId: ID!) {
  deleteMessage(message_id: $messageId)
}
`,c=class s{constructor(e){this.gql=e;let a=this.readPendingStorage();a&&(this.pendingConversation=a),this.pendingConversationSubject.next(this.pendingConversation)}pendingStorageKey="worldapp.pendingConversation";pendingConversation=null;pendingConversationSubject=new m(null);pendingConversation$=this.pendingConversationSubject.asObservable();mediaCache=new Map;setPendingConversation(e){this.pendingConversation=e,this.writePendingStorage(e),this.pendingConversationSubject.next(e)}getPendingConversation(){return this.pendingConversation}clearPendingConversation(){this.pendingConversation=null,this.clearPendingStorage(),this.pendingConversationSubject.next(null)}async listConversations(e=30){let{conversations:a}=await this.gql.request(p,{limit:e}),t=(a??[]).map(n=>this.mapConversation(n));return await Promise.all(t.map(n=>this.hydrateConversation(n)))}async getConversationById(e){let{conversationById:a}=await this.gql.request(y,{conversationId:e});return a?await this.hydrateConversation(this.mapConversation(a)):null}async listMessages(e,a=40,t){let{messagesByConversation:n}=await this.gql.request(v,{conversationId:e,limit:a,before:t??null}),r=(n??[]).map(i=>this.mapMessage(i));return await Promise.all(r.map(i=>this.hydrateMessageMedia(i)))}async startConversation(e){let{startConversation:a}=await this.gql.request(h,{targetId:e});return this.mapConversation(a)}async sendMessage(e,a,t){let n=String(a??"").trim(),r={conversationId:e,body:n||null,mediaType:t?.type??null,mediaPath:t?.path??null,mediaName:t?.name??null,mediaMime:t?.mime??null,mediaSize:t?.size??null},{sendMessage:i}=await this.gql.request(S,r);return await this.hydrateMessageMedia(this.mapMessage(i))}async updateMessage(e,a){let t=String(a??"").trim(),{updateMessage:n}=await this.gql.request(C,{messageId:e,body:t});return await this.hydrateMessageMedia(this.mapMessage(n))}async deleteMessage(e){let{deleteMessage:a}=await this.gql.request(M,{messageId:e});return!!a}mapAuthor(e){return e?{user_id:e.user_id,display_name:e.display_name??null,username:e.username??null,avatar_url:e.avatar_url??null,country_name:e.country_name??null,country_code:e.country_code??null,last_read_at:e.last_read_at??null}:null}mapMessage(e){return{id:e.id,conversation_id:e.conversation_id,sender_id:e.sender_id,body:e.body??"",media_type:e.media_type??null,media_path:e.media_path??null,media_name:e.media_name??null,media_mime:e.media_mime??null,media_size:e.media_size??null,created_at:e.created_at,updated_at:e.updated_at??null,sender:e.sender?this.mapAuthor(e.sender):null}}mapConversation(e){return{id:e.id,is_direct:!!e.is_direct,created_at:e.created_at,updated_at:e.updated_at??e.created_at,last_message_at:e.last_message_at??null,members:Array.isArray(e.members)?e.members.map(a=>this.mapAuthor(a)):[],last_message:e.last_message?this.mapMessage(e.last_message):null}}async hydrateConversation(e){if(!e.last_message)return e;let a=await this.hydrateMessageMedia(e.last_message);return o(d({},e),{last_message:a})}async hydrateMessageMedia(e){if(!e.media_path)return e;let a=await this.getSignedUrl(e.media_path);return o(d({},e),{media_url:a})}async getSignedUrl(e){if(!e)return null;let a=this.mediaCache.get(e);if(a&&a.expiresAt>Date.now())return a.url;let{data:t,error:n}=await l.storage.from("messages").createSignedUrl(e,3600);return n||!t?.signedUrl?null:(this.mediaCache.set(e,{url:t.signedUrl,expiresAt:Date.now()+55*6e4}),t.signedUrl)}readPendingStorage(){if(typeof window>"u")return null;try{let e=window.sessionStorage.getItem(this.pendingStorageKey);return e?JSON.parse(e):null}catch{return this.clearPendingStorage(),null}}writePendingStorage(e){if(!(typeof window>"u"))try{window.sessionStorage.setItem(this.pendingStorageKey,JSON.stringify(e))}catch{}}clearPendingStorage(){if(!(typeof window>"u"))try{window.sessionStorage.removeItem(this.pendingStorageKey)}catch{}}static \u0275fac=function(a){return new(a||s)(u(g))};static \u0275prov=_({token:s,factory:s.\u0275fac,providedIn:"root"})};export{c as a};
