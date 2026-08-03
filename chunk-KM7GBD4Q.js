import{a as q}from"./chunk-XKK2OOP6.js";import{a as L}from"./chunk-CLTFIU2N.js";import{a as x}from"./chunk-36NYYCNU.js";import{a as _}from"./chunk-TYADZYHJ.js";import{b as k}from"./chunk-ZPCH672B.js";import{a as g,k as P,n as b}from"./chunk-JPJ3TCZX.js";var w=class d{createdPostSubject=new g;createdPost$=this.createdPostSubject.asObservable();updatedPostSubject=new g;updatedPost$=this.updatedPostSubject.asObservable();insertSubject=new g;insert$=this.insertSubject.asObservable();updateSubject=new g;update$=this.updateSubject.asObservable();deleteSubject=new g;delete$=this.deleteSubject.asObservable();channel=k.channel("public:posts");constructor(){this.channel.on("postgres_changes",{event:"INSERT",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.insertSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.updateSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null,visibility:t.visibility??null})}).on("postgres_changes",{event:"DELETE",schema:"public",table:"posts"},({old:t})=>{t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).subscribe()}emit(t){this.createdPostSubject.next(t)}emitUpdated(t){this.updatedPostSubject.next(t)}emitDeleted(t){t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}ngOnDestroy(){this.channel?.unsubscribe()}static \u0275fac=function(e){return new(e||d)};static \u0275prov=P({token:d,factory:d.\u0275fac,providedIn:"root"})};var O="demo_social_dataset_30k/posts.jsonl",E="demo_social_dataset_30k/comments.jsonl",j="demo_social_dataset_30k/video_captions.jsonl";function S(d){let t=d>>>0;return()=>{t|=0,t=t+1831565813|0;let e=Math.imul(t^t>>>15,1|t);return e=e+Math.imul(e^e>>>7,61|e)^e,((e^e>>>14)>>>0)/4294967296}}function D(d){let t=2166136261;for(let e=0;e<d.length;e++)t^=d.charCodeAt(e),t=Math.imul(t,16777619);return t>>>0}function $(d){let t=[],e=d.split(/\r?\n/);for(let n of e){let s=n.trim();if(s)try{t.push(JSON.parse(s))}catch{}}return t}var I=class d{constructor(t){this.fakeData=t}postsLoaded=!1;postsPromise=null;commentsLoaded=!1;commentsPromise=null;captionsLoaded=!1;captionsPromise=null;posts=[];postsById=new Map;postsByCountry=new Map;postsByAuthor=new Map;postStates=new Map;countryFeedCache=new Map;postSearchCache=new Map;postMediaMeta=new Map;captionsByPost=new Map;commentsByPost=new Map;localCommentsByPost=new Map;commentStates=new Map;commentOrderCache=new Map;profileMap=null;countryOffsets=new Map;pexelsCache=new Map;pexelsInflight=new Map;async isDemoPostId(t){return await this.ensurePostsLoaded(),this.postsById.has(t)}isDemoCommentId(t){return/^cmt_|^local_/.test(t)}async listByCountry(t,e=25,n){n?.skipComments?await this.ensurePostsLoaded():await this.ensureCommentsLoaded();let s=String(t||"").trim().toUpperCase(),i=this.postsByCountry.get(s)??[],a=this.buildBalancedOrder(i,s),r=Math.max(1,e),o=this.sliceWithOffset(s,a,r);return await this.hydrateMedia(o),o}async listForAuthor(t,e=25){await this.ensureCommentsLoaded();let i=[...this.postsByAuthor.get(t)??[]].sort((a,r)=>new Date(r.created_at).getTime()-new Date(a.created_at).getTime()).slice(0,Math.max(1,e));return await this.hydrateMedia(i),i}async getPostById(t){await this.ensureCommentsLoaded();let e=this.postsById.get(t)??null;return e?(await this.hydrateMedia([e]),e):null}async searchPosts(t,e=20){let n=String(t||"").trim().toLowerCase();if(!n)return[];await this.ensurePostsLoaded();let s=this.postSearchCache.get(n);if(s){if(e<=0)return s;let o=s.slice(0,Math.max(1,e));return await this.hydrateMedia(o),o}let a=this.posts.filter(o=>{let u=String(o.title||"").toLowerCase(),l=String(o.body||"").toLowerCase(),y=String(o.media_caption||"").toLowerCase();return u.includes(n)||l.includes(n)||y.includes(n)}).sort((o,u)=>new Date(u.created_at).getTime()-new Date(o.created_at).getTime());if(this.postSearchCache.set(n,a),this.postSearchCache.size>40){let o=this.postSearchCache.keys().next().value;o&&this.postSearchCache.delete(o)}if(e<=0)return a;let r=a.slice(0,Math.max(1,e));return await this.hydrateMedia(r),r}async listComments(t,e=25){await this.ensureCommentsLoaded();let n=this.getOrderedComments(t),s=this.localCommentsByPost.get(t)??[];return[...n,...s].slice(0,Math.max(1,e))}async addComment(t,e,n){await this.ensurePostsLoaded();let i=(await k.auth.getUser()).data.user?.id??"me",a=new Date().toISOString(),r={user_id:i,display_name:"You",username:null,avatar_url:null,country_name:null,country_code:null},o={id:`local_${Date.now()}_${Math.floor(Math.random()*1e4)}`,post_id:t,parent_id:n??null,author_id:i,body:e.trim(),like_count:0,liked_by_me:!1,created_at:a,updated_at:a,author:r},u=this.localCommentsByPost.get(t)??[];u.push(o),this.localCommentsByPost.set(t,u);let l=this.postStates.get(t);if(l){l.comment_count+=1;let y=this.postsById.get(t);y&&(y.comment_count=l.comment_count)}return o}async likePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let n=this.ensurePostState(t);return n.liked_by_me||(n.liked_by_me=!0,n.like_count+=1),this.applyState(e,n),e}async unlikePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let n=this.ensurePostState(t);return n.liked_by_me&&(n.liked_by_me=!1,n.like_count=Math.max(0,n.like_count-1)),this.applyState(e,n),e}async recordView(t){if(!t)return;await this.ensurePostsLoaded();let e=this.ensurePostState(t);e.view_count+=1;let n=this.postsById.get(t);n&&this.applyState(n,e)}async listLikes(t,e=25){await this.ensurePostsLoaded();let n=this.postStates.get(t),s=Math.max(0,Math.min(e,n?.like_count??0));if(!s)return[];let i=await this.fakeData.getProfiles();if(!i.length)return[];let a=S(D(`${t}|likes`)),r=new Set;for(;r.size<s&&r.size<i.length;)r.add(Math.floor(a()*i.length));let o=new Date().toISOString();return[...r].map(u=>{let l=i[u];return{user_id:l.user_id,created_at:o,user:this.profileToAuthor(l)}})}async likeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let n=this.ensureCommentState(t,e);return n.liked_by_me||(n.liked_by_me=!0,n.like_count+=1),e.liked_by_me=n.liked_by_me,e.like_count=n.like_count,e}async unlikeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let n=this.ensureCommentState(t,e);return n.liked_by_me&&(n.liked_by_me=!1,n.like_count=Math.max(0,n.like_count-1)),e.liked_by_me=n.liked_by_me,e.like_count=n.like_count,e}async ensurePostsLoaded(){if(!this.postsLoaded)return this.postsPromise?this.postsPromise:(this.postsPromise=(async()=>{await this.ensureCaptionsLoaded();let t=await this.fetchText(O),e=$(t),n=new Set;for(let s of e){let i=this.normalizeAuthorId(s?.author_id);i&&n.add(i)}await this.ensureProfileMap(n);for(let s of e){let i=this.normalizeAuthorId(s?.author_id);if(!s?.id||!i)continue;let a=this.profileMap?.get(i)??null,r=s.media?.type??"none",o=s.media?.url??null,u=s.media?.thumb_url??null,l=this.captionsByPost.get(s.id)??null,y=a?.country_code??s.country_code??null,p=a?.country_name??s.country_name??null,m=s.created_at||new Date().toISOString(),c={id:s.id,title:s.title??null,body:this.normalizeBody(s.body??"",p||s.country_name||null),media_type:r,media_url:o,thumb_url:u,media_caption:l,visibility:s.visibility||"public",like_count:0,comment_count:0,view_count:0,liked_by_me:!1,created_at:m,updated_at:m,author_id:i,country_name:p,country_code:y,city_name:null,author:a},f=this.seedCount(s.id,8e3),M=this.seedCount(`${s.id}|views`,18e4),v={like_count:f,comment_count:0,view_count:Math.max(M,f*6),liked_by_me:!1};this.postStates.set(s.id,v),this.applyState(c,v),this.posts.push(c),this.postsById.set(s.id,c);let h=String(y||"").trim().toUpperCase();if(h){let B=this.postsByCountry.get(h)??[];B.push(c),this.postsByCountry.set(h,B)}let C=this.postsByAuthor.get(i)??[];C.push(c),this.postsByAuthor.set(i,C),this.postMediaMeta.set(s.id,{type:r,query:s.media?.query??null,url:o,thumb_url:u})}this.postsLoaded=!0})(),this.postsPromise)}async ensureCommentsLoaded(){if(!this.commentsLoaded)return this.commentsPromise?this.commentsPromise:(this.commentsPromise=(async()=>{await this.ensurePostsLoaded();let t=await this.fetchText(E),e=$(t),n=new Set;for(let s of e){let i=this.normalizeAuthorId(s?.author_id);i&&n.add(i)}await this.ensureProfileMap(n);for(let s of e){let i=this.normalizeAuthorId(s?.author_id);if(!s?.id||!s?.post_id||!i)continue;let a=this.profileMap?.get(i)??null,r=s.created_at||new Date().toISOString(),o={id:s.id,post_id:s.post_id,parent_id:s.parent_id??null,author_id:i,body:s.body??"",like_count:this.seedCount(s.id,160),liked_by_me:!1,created_at:r,updated_at:r,author:a},u=this.commentsByPost.get(s.post_id)??[];u.push(o),this.commentsByPost.set(s.post_id,u),this.commentStates.set(s.id,{like_count:o.like_count,liked_by_me:!1});let l=this.postStates.get(s.post_id);l&&(l.comment_count+=1)}for(let[s,i]of this.postStates.entries()){let a=this.postsById.get(s);a&&(a.comment_count=i.comment_count)}this.commentsLoaded=!0})(),this.commentsPromise)}async ensureCaptionsLoaded(){if(!this.captionsLoaded)return this.captionsPromise?this.captionsPromise:(this.captionsPromise=(async()=>{let t=await this.fetchText(j),e=$(t);for(let n of e)!n?.post_id||!n?.caption||this.captionsByPost.set(n.post_id,n.caption);this.captionsLoaded=!0})(),this.captionsPromise)}async ensureProfileMap(t){if(!this.profileMap){let e=await this.fakeData.getProfiles(),n=new Map;for(let s of e)n.set(s.user_id,this.profileToAuthor(s));this.profileMap=n}if(t&&t.size){await this.fakeData.ensureProfilesById(t);for(let e of t){if(this.profileMap?.has(e))continue;let n=await this.fakeData.getProfileById(e);n&&this.profileMap?.set(e,this.profileToAuthor(n))}}}profileToAuthor(t){return{user_id:t.user_id,display_name:t.display_name??null,username:t.username??null,avatar_url:t.avatar_url??null,country_name:t.country_name??null,country_code:t.country_code??null}}applyState(t,e){t.like_count=e.like_count,t.comment_count=e.comment_count,t.view_count=e.view_count,t.liked_by_me=e.liked_by_me}ensurePostState(t){let e=this.postStates.get(t);return e||(e={like_count:0,comment_count:0,view_count:0,liked_by_me:!1},this.postStates.set(t,e)),e}ensureCommentState(t,e){let n=this.commentStates.get(t);return n||(n={like_count:e.like_count,liked_by_me:e.liked_by_me},this.commentStates.set(t,n)),n}findComment(t){for(let e of this.commentsByPost.values()){let n=e.find(s=>s.id===t);if(n)return n}for(let e of this.localCommentsByPost.values()){let n=e.find(s=>s.id===t);if(n)return n}return null}seedCount(t,e){let n=S(D(t));return Math.floor(Math.pow(n(),2)*e)}buildBalancedOrder(t,e){let n=Date.now(),s=Math.floor(n/(1e3*60*15)),i=`${e}:${s}`,a=this.countryFeedCache.get(i);if(a)return a.posts;let r=[...t].sort((m,c)=>new Date(c.created_at).getTime()-new Date(m.created_at).getTime()),o=new Map;for(let m of r){let c=o.get(m.author_id)??[];c.push(m),o.set(m.author_id,c)}let u=Array.from(o.keys()),l=S(D(`${e}|${s}`));for(let m=u.length-1;m>0;m-=1){let c=Math.floor(l()*(m+1)),f=u[m];u[m]=u[c],u[c]=f}let y=[],p=!0;for(;p;){p=!1;for(let m of u){let c=o.get(m);!c||!c.length||(y.push(c.shift()),p=!0)}}return this.countryFeedCache.set(i,{ts:n,posts:y}),y}sliceWithOffset(t,e,n){if(!e.length)return[];if(e.length<=n)return[...e];let i=(this.countryOffsets.get(t)??0)%e.length,a=i+n,r=(i+n)%e.length;if(this.countryOffsets.set(t,r),a<=e.length)return e.slice(i,a);let o=e.slice(i),u=e.slice(0,a-e.length);return[...o,...u]}normalizeBody(t,e){let n=String(t||"").trim();if(!n)return"";let s=n,i=/^in\s+[A-Za-z][^,.:;-]{1,60}[,.:;-]\s*/i;if(s=s.replace(i,"").trim(),!s||!e)return s;let a=e.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),r=new RegExp(`^In\\s+${a}\\b[\\s,.-]*`,"i");return s.replace(r,"").trim()}getOrderedComments(t){let e=this.commentOrderCache.get(t);if(e)return e;let n=this.commentsByPost.get(t)??[];if(!n.length)return this.commentOrderCache.set(t,[]),[];let s=[],i=new Set;for(let r of n){let o=`${r.author_id}|${this.normalizeCommentBody(r.body)}`;i.has(o)||(i.add(o),s.push(r))}let a=S(D(`${t}|comments`));for(let r=s.length-1;r>0;r-=1){let o=Math.floor(a()*(r+1)),u=s[r];s[r]=s[o],s[o]=u}return this.commentOrderCache.set(t,s),s}normalizeCommentBody(t){return String(t||"").trim().toLowerCase().replace(/\s+/g," ")}normalizeAuthorId(t){let e=String(t||"").trim();if(!e)return null;let n=e.match(/^user_(\d+)$/i);if(!n)return e;let s=parseInt(n[1],10);return!Number.isFinite(s)||s<=0?e:`user_${String(s).padStart(6,"0")}`}resolveAssetUrl(t){let e=document.querySelector("base")?.getAttribute("href")??"/",n=new URL(e,window.location.origin).toString();return new URL(t,n).toString()}async fetchText(t){if(typeof window>"u"||typeof document>"u")return"";let e=this.resolveAssetUrl(t),n=await fetch(e);if(!n.ok)throw new Error(`Failed to load ${t}: ${n.status}`);return n.text()}async hydrateMedia(t){if(!_.pexelsApiKey)return;let e=t.map(async n=>{if(!n||n.media_type==="none"||n.media_url)return;let s=this.postMediaMeta.get(n.id);if(!s||!s.query)return;let i=`${s.type}:${s.query}`.toLowerCase(),a=this.pexelsCache.get(i);if(a){n.media_url=a.url,n.thumb_url=a.thumb_url;return}let r=this.pexelsInflight.get(i);if(r){let l=await r;n.media_url=l.url,n.thumb_url=l.thumb_url;return}let o=this.fetchPexels(s.type,s.query);this.pexelsInflight.set(i,o);let u=await o;this.pexelsInflight.delete(i),this.pexelsCache.set(i,u),n.media_url=u.url,n.thumb_url=u.thumb_url});await Promise.all(e)}async fetchPexels(t,e){let n=_.pexelsApiKey||"";if(!n)return{url:null,thumb_url:null};let s={Authorization:n};if(t==="video"){let l=`https://api.pexels.com/videos/search?query=${encodeURIComponent(e)}&per_page=1`,y=await fetch(l,{headers:s});if(!y.ok)return{url:null,thumb_url:null};let m=(await y.json())?.videos?.[0];if(!m)return{url:null,thumb_url:null};let f=(Array.isArray(m.video_files)?m.video_files:[]).filter(h=>String(h?.file_type||"").toLowerCase()==="video/mp4").sort((h,C)=>(h?.width??0)-(C?.width??0)),M=f.find(h=>(h?.width??0)>=720)||f[0],v=m.video_pictures?.[0]?.picture||m.image||null;return{url:M?.link??null,thumb_url:v}}let i=`https://api.pexels.com/v1/search?query=${encodeURIComponent(e)}&per_page=1`,a=await fetch(i,{headers:s});if(!a.ok)return{url:null,thumb_url:null};let u=(await a.json())?.photos?.[0]?.src||{};return{url:u?.large??u?.medium??null,thumb_url:u?.medium??null}}static \u0275fac=function(e){return new(e||d)(b(L))};static \u0275prov=P({token:d,factory:d.\u0275fac,providedIn:"root"})};var T=class d{constructor(t,e,n){this.gql=t;this.postEvents=e;this.demoData=n}async listByCountry(t,e=25,n){let s=Math.max(1,Math.min(80,e||25)),i=`
      query PostsByCountry($code: String!, $limit: Int) {
        postsByCountry(country_code: $code, limit: $limit) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;try{let{postsByCountry:a}=await this.withTimeout(this.gql.request(i,{code:t,limit:s}),8e3,"postsByCountry"),r=(a??[]).map(l=>this.mapPost(l)).filter(l=>!this.isMoment(l));if(!_.useDemoDataset)return r;let o=Math.min(n?.demoLimit??s,40),u=await this.withTimeout(this.demoData.listByCountry(t,o,{skipComments:n?.skipComments??!0}),2500,"demoPostsByCountry").catch(()=>[]);return this.mergePosts(r,u,s)}catch{if(!_.useDemoDataset)return[];try{return await this.withTimeout(this.demoData.listByCountry(t,Math.min(s,20),{skipComments:!0}),2500,"demoPostsByCountryFallback")}catch{return[]}}}async listRecent(t=40,e){let n=`
      query RecentPosts($limit: Int, $before: String) {
        recentPosts(limit: $limit, before: $before) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;try{let{recentPosts:s}=await this.withTimeout(this.gql.request(n,{limit:Math.max(1,Math.min(80,t||40)),before:e??null}),8e3,"recentPosts");return(s??[]).map(i=>this.mapPost(i)).filter(i=>!this.isMoment(i))}catch{return[]}}isMoment(t){if(!t)return!1;let e=String(t.media_type||"").toLowerCase();return e==="story"||e==="moment"?!0:String(t.body||"").includes("__story__|")}isSpark(t){if(!t||this.isMoment(t))return!1;let e=String(t.media_type||"").toLowerCase();if(e==="reel"||e==="spark")return!0;let n=String(t.media_url||"").trim();if(n.startsWith("{")||n.startsWith("["))try{let s=JSON.parse(n),i=s?.reel??s?.spark;return i===!0||i==="true"||i===1||i==="1"}catch{return!1}return!1}isMomentActive(t){if(!this.isMoment(t))return!1;let n=String(t.body||"").match(/__story__\|expires=([^\s|]+)/i);if(!n?.[1])return!0;let s=Date.parse(n[1]);return Number.isFinite(s)?s>Date.now():!0}async listActiveMoments(t=40,e){let n=(e?.followingIds??[]).filter(Boolean).slice(0,8),s=await Promise.all([e?.authorId?this.listForAuthor(e.authorId,24).catch(()=>[]):Promise.resolve([]),...n.map(r=>this.listForAuthor(r,10).catch(()=>[]))]),i=new Set,a=[];for(let r of s)for(let o of r)!o?.id||i.has(o.id)||this.isMomentActive(o)&&(i.add(o.id),a.push(o));return a.sort((r,o)=>{let u=Date.parse(r.created_at||"")||0;return(Date.parse(o.created_at||"")||0)-u}),a.slice(0,Math.max(1,t))}async loadHomeFeed(t){let e=t?.maxPosts??50,n=(t?.followingIds??[]).filter(Boolean).slice(0,6),s=await Promise.all([this.listRecent(40).catch(()=>[]),t?.countryCode?this.listByCountry(t.countryCode,24,{demoLimit:12,skipComments:!0}).catch(()=>[]):Promise.resolve([]),t?.authorId?this.withTimeout(this.listForAuthor(t.authorId,12),5e3,"feedAuthor").catch(()=>[]):Promise.resolve([]),...n.map(r=>this.withTimeout(this.listForAuthor(r,3),4e3,"feedFollowing").catch(()=>[]))]),i=new Set,a=[];for(let r of s)for(let o of r)!o?.id||i.has(o.id)||this.isMoment(o)||this.isSpark(o)||(i.add(o.id),a.push(o));return a.sort((r,o)=>{let u=Date.parse(r.created_at||"")||0;return(Date.parse(o.created_at||"")||0)-u}),a.slice(0,e)}async listForAuthor(t,e=25){if(!t)return[];if(_.useDemoDataset&&/^user_/.test(t))return this.demoData.listForAuthor(t,e);let n=`
      query PostsByAuthor($authorId: ID!, $limit: Int) {
        postsByAuthor(user_id: $authorId, limit: $limit) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;try{let{postsByAuthor:s}=await this.withTimeout(this.gql.request(n,{authorId:t,limit:Math.max(1,Math.min(60,e||25))}),8e3,"postsByAuthor");return(s??[]).map(i=>this.mapPost(i))}catch{return[]}}async searchPosts(t,e=25){let n=String(t||"").trim();if(!n)return[];let s=`
      query SearchPosts($query: String!, $limit: Int) {
        searchPosts(query: $query, limit: $limit) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;try{let{searchPosts:i}=await this.gql.request(s,{query:n,limit:e});return(i??[]).map(a=>this.mapPost(a))}catch{return[]}}async getPostById(t){if(!t)return null;if(_.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.getPostById(t);let e=`
      query PostById($postId: ID!) {
        postById(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{postById:n}=await this.gql.request(e,{postId:t});return n?this.mapPost(n):null}async createPost(t){if(!t.authorId)throw new Error("authorId is required to post.");let e=`
      mutation CreatePost($input: CreatePostInput!) {
        createPost(input: $input) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,n={title:t.title?.trim()||null,body:t.body.trim(),country_name:t.countryName,country_code:t.countryCode,city_name:t.cityName??null,visibility:t.visibility??null,media_type:t.mediaType??null,media_url:t.mediaUrl??null,thumb_url:t.thumbUrl??null,shared_post_id:t.sharedPostId??null},{createPost:s}=await this.gql.request(e,{input:n}),i=this.mapPost(s);return this.postEvents.emit(i),i}async updatePost(t,e){let n=`
      mutation UpdatePost($postId: ID!, $input: UpdatePostInput!) {
        updatePost(post_id: $postId, input: $input) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,s={title:e.title?.trim()??null,body:e.body?.trim()??null,visibility:e.visibility??null},{updatePost:i}=await this.gql.request(n,{postId:t,input:s}),a=this.mapPost(i);return this.postEvents.emitUpdated(a),a}async deletePost(t,e){let n=`
      mutation DeletePost($postId: ID!) {
        deletePost(post_id: $postId)
      }
    `,{deletePost:s}=await this.gql.request(n,{postId:t});return s&&this.postEvents.emitDeleted({id:t,country_code:e?.country_code??null,author_id:e?.author_id??null}),s}async likePost(t){if(_.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.likePost(t);return this.postEvents.emitUpdated(i),i}let e=`
      mutation LikePost($postId: ID!) {
        likePost(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{likePost:n}=await this.gql.request(e,{postId:t}),s=this.mapPost(n);return this.postEvents.emitUpdated(s),s}async unlikePost(t){if(_.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.unlikePost(t);return this.postEvents.emitUpdated(i),i}let e=`
      mutation UnlikePost($postId: ID!) {
        unlikePost(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{unlikePost:n}=await this.gql.request(e,{postId:t}),s=this.mapPost(n);return this.postEvents.emitUpdated(s),s}async recordView(t){if(t?.id){if(_.useDemoDataset&&await this.demoData.isDemoPostId(t.id)){await this.demoData.recordView(t.id);return}t.view_count=Number(t.view_count??0)+1}}async listComments(t,e=25,n){if(_.useDemoDataset&&await this.demoData.isDemoPostId(t)){let a=Math.max(e,1e3);return this.demoData.listComments(t,a)}let s=`
      query CommentsByPost($postId: ID!, $limit: Int, $before: String) {
        commentsByPost(post_id: $postId, limit: $limit, before: $before) {
          id
          post_id
          parent_id
          author_id
          body
          like_count
          liked_by_me
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{commentsByPost:i}=await this.gql.request(s,{postId:t,limit:e,before:n??null});return(i??[]).map(a=>this.mapComment(a))}async listLikes(t,e=25){if(!t)return[];if(_.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.listLikes(t,e);let n=`
      query PostLikes($postId: ID!, $limit: Int) {
        postLikes(post_id: $postId, limit: $limit) {
          user_id
          created_at
          user {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{postLikes:s}=await this.gql.request(n,{postId:t,limit:e});return(s??[]).map(i=>this.mapLike(i))}async addComment(t,e,n){if(_.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.addComment(t,e,n??null);let s=`
      mutation AddComment($postId: ID!, $body: String!, $parentId: ID) {
        addComment(post_id: $postId, body: $body, parent_id: $parentId) {
          id
          post_id
          parent_id
          author_id
          body
          like_count
          liked_by_me
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{addComment:i}=await this.gql.request(s,{postId:t,body:e.trim(),parentId:n??null});return this.mapComment(i)}async likeComment(t){if(_.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.likeComment(t);let e=`
      mutation LikeComment($commentId: ID!) {
        likeComment(comment_id: $commentId) {
          id
          post_id
          parent_id
          author_id
          body
          like_count
          liked_by_me
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{likeComment:n}=await this.gql.request(e,{commentId:t});return this.mapComment(n)}async unlikeComment(t){if(_.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.unlikeComment(t);let e=`
      mutation UnlikeComment($commentId: ID!) {
        unlikeComment(comment_id: $commentId) {
          id
          post_id
          parent_id
          author_id
          body
          like_count
          liked_by_me
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `,{unlikeComment:n}=await this.gql.request(e,{commentId:t});return this.mapComment(n)}async reportPost(t,e){if(_.useDemoDataset&&await this.demoData.isDemoPostId(t))throw new Error("Only live posts can be reported right now.");let n=`
      mutation ReportPost($postId: ID!, $reason: String!) {
        reportPost(post_id: $postId, reason: $reason)
      }
    `,{reportPost:s}=await this.gql.request(n,{postId:t,reason:e.trim()});return!!s}stripMomentMarkers(t){return String(t??"").split(`
`).filter(e=>{let n=e.trim();return n?!(/__story__/i.test(n)||/\bstory\b/i.test(n)&&/\bexpir/i.test(n)):!0}).join(`
`).replace(/\n{3,}/g,`

`).trim()}mapPost(t,e=0){let n=t?.view_count!=null?Number(t.view_count):this.estimateViewCount(t?.id,t?.like_count,t?.comment_count),s=t?.shared_post&&e<1?this.mapPost(t.shared_post,e+1):null;return{id:t.id,title:t.title??null,body:this.stripMomentMarkers(t.body??""),media_type:t.media_type??"none",media_url:t.media_url??null,thumb_url:t.thumb_url??null,media_caption:t.media_caption??null,shared_post_id:t.shared_post_id??null,shared_post:s,visibility:t.visibility??"public",like_count:Number(t.like_count??0),comment_count:Number(t.comment_count??0),view_count:n,liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author_id:t.author_id,country_name:t.country_name??null,country_code:t.country_code??null,city_name:t.city_name??null,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null,external_ref_type:t.external_ref_type??null,external_ref_id:t.external_ref_id??null,link_url:t.link_url??null,link_title:t.link_title??null,link_source_name:t.link_source_name??null,link_published_at:t.link_published_at??null,link_image_url:t.link_image_url??null,link_snippet:t.link_snippet??null}}mapComment(t){return{id:t.id,post_id:t.post_id,parent_id:t.parent_id??null,author_id:t.author_id,body:t.body??"",like_count:Number(t.like_count??0),liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapLike(t){return{user_id:t.user_id,created_at:t.created_at,user:t.user?{user_id:t.user.user_id,display_name:t.user.display_name,username:t.user.username,avatar_url:this.resolveAvatarUrl(t.user.avatar_url,t.user.user_id,t.user.username),country_name:t.user.country_name,country_code:t.user.country_code}:null}}resolveAvatarUrl(t,e,n){return q(t,n||e)}mergePosts(t,e,n){let s=[...t,...e],i=new Set,a=[];for(let r of s)!r?.id||i.has(r.id)||(i.add(r.id),a.push(r));if(t.length){let r=new Set(t.map(l=>l.id)),o=t.filter(l=>r.has(l.id)).sort((l,y)=>new Date(y.created_at).getTime()-new Date(l.created_at).getTime()),u=a.filter(l=>!r.has(l.id));return[...o,...u].slice(0,Math.max(1,n))}return a.sort((r,o)=>new Date(o.created_at).getTime()-new Date(r.created_at).getTime()).slice(0,Math.max(1,n))}estimateViewCount(t,e,n){let s=Number(e??0),i=Number(n??0);if(!s&&!i)return 0;let r=this.hashSeed(String(t||"post"))%1200,o=s*12+i*6+r;return Math.max(o,s+i)}hashSeed(t){let e=2166136261;for(let n=0;n<t.length;n++)e^=t.charCodeAt(n),e=Math.imul(e,16777619);return e>>>0}async withTimeout(t,e,n){let s=null;try{return await Promise.race([t,new Promise((i,a)=>{s=setTimeout(()=>a(new Error(`${n} timeout`)),e)})])}finally{s&&clearTimeout(s)}}static \u0275fac=function(e){return new(e||d)(b(x),b(w),b(I))};static \u0275prov=P({token:d,factory:d.\u0275fac,providedIn:"root"})};export{w as a,T as b};
