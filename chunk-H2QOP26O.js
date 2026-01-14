import{a as o}from"./chunk-QGWRKH4Y.js";import{f as s,l as r,o as i}from"./chunk-EMTWPIOC.js";var _=`
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
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      created_at
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
`,l=`
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
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      created_at
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
`,m=`
query MessagesByConversation($conversationId: ID!, $limit: Int, $before: String) {
  messagesByConversation(conversation_id: $conversationId, limit: $limit, before: $before) {
    id
    conversation_id
    sender_id
    body
    created_at
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
`,v=`
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
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      created_at
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
`,g=`
mutation SendMessage($conversationId: ID!, $body: String!) {
  sendMessage(conversation_id: $conversationId, body: $body) {
    id
    conversation_id
    sender_id
    body
    created_at
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
`,y=`
query MessagesUnreadCount {
  messagesUnreadCount
}
`,d=class a{constructor(e){this.gql=e;let n=this.readPendingStorage();n&&(this.pendingConversation=n),this.pendingConversationSubject.next(this.pendingConversation)}pendingStorageKey="worldapp.pendingConversation";pendingConversation=null;pendingConversationSubject=new s(null);pendingConversation$=this.pendingConversationSubject.asObservable();setPendingConversation(e){this.pendingConversation=e,this.writePendingStorage(e),this.pendingConversationSubject.next(e)}getPendingConversation(){return this.pendingConversation}clearPendingConversation(){this.pendingConversation=null,this.clearPendingStorage(),this.pendingConversationSubject.next(null)}async listConversations(e=30){let{conversations:n}=await this.gql.request(_,{limit:e});return(n??[]).map(t=>this.mapConversation(t))}async getConversationById(e){let{conversationById:n}=await this.gql.request(l,{conversationId:e});return n?this.mapConversation(n):null}async listMessages(e,n=40,t){let{messagesByConversation:u}=await this.gql.request(m,{conversationId:e,limit:n,before:t??null});return(u??[]).map(c=>this.mapMessage(c))}async startConversation(e){let{startConversation:n}=await this.gql.request(v,{targetId:e});return this.mapConversation(n)}async sendMessage(e,n){let{sendMessage:t}=await this.gql.request(g,{conversationId:e,body:n.trim()});return this.mapMessage(t)}async unreadCount(){let{messagesUnreadCount:e}=await this.gql.request(y);return typeof e=="number"?e:0}mapAuthor(e){return e?{user_id:e.user_id,display_name:e.display_name??null,username:e.username??null,avatar_url:e.avatar_url??null,country_name:e.country_name??null,country_code:e.country_code??null}:null}mapMessage(e){return{id:e.id,conversation_id:e.conversation_id,sender_id:e.sender_id,body:e.body??"",created_at:e.created_at,sender:e.sender?this.mapAuthor(e.sender):null}}mapConversation(e){return{id:e.id,is_direct:!!e.is_direct,created_at:e.created_at,updated_at:e.updated_at??e.created_at,last_message_at:e.last_message_at??null,members:Array.isArray(e.members)?e.members.map(n=>this.mapAuthor(n)):[],last_message:e.last_message?this.mapMessage(e.last_message):null}}readPendingStorage(){if(typeof window>"u")return null;try{let e=window.sessionStorage.getItem(this.pendingStorageKey);return e?JSON.parse(e):null}catch{return this.clearPendingStorage(),null}}writePendingStorage(e){if(!(typeof window>"u"))try{window.sessionStorage.setItem(this.pendingStorageKey,JSON.stringify(e))}catch{}}clearPendingStorage(){if(!(typeof window>"u"))try{window.sessionStorage.removeItem(this.pendingStorageKey)}catch{}}static \u0275fac=function(n){return new(n||a)(i(o))};static \u0275prov=r({token:a,factory:a.\u0275fac,providedIn:"root"})};export{d as a};
