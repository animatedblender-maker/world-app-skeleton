import{a as U}from"./chunk-CUVPT7L7.js";import{a as O}from"./chunk-G4AEBNEO.js";import{a as T}from"./chunk-NQC6INBE.js";import{a as d}from"./chunk-LQQHCQP3.js";import{b as w}from"./chunk-O6RSSF7I.js";import{a as P,k as b,n as v}from"./chunk-X6NOM4Z7.js";import{a as A,b as q}from"./chunk-2NFLSA4Y.js";var S=class y{createdPostSubject=new P;createdPost$=this.createdPostSubject.asObservable();updatedPostSubject=new P;updatedPost$=this.updatedPostSubject.asObservable();insertSubject=new P;insert$=this.insertSubject.asObservable();updateSubject=new P;update$=this.updateSubject.asObservable();deleteSubject=new P;delete$=this.deleteSubject.asObservable();channel=w.channel("public:posts");constructor(){this.channel.on("postgres_changes",{event:"INSERT",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.insertSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.updateSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null,visibility:t.visibility??null})}).on("postgres_changes",{event:"DELETE",schema:"public",table:"posts"},({old:t})=>{t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).subscribe()}emit(t){this.createdPostSubject.next(t)}emitUpdated(t){this.updatedPostSubject.next(t)}emitDeleted(t){t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}ngOnDestroy(){this.channel?.unsubscribe()}static \u0275fac=function(e){return new(e||y)};static \u0275prov=b({token:y,factory:y.\u0275fac,providedIn:"root"})};var R="demo_social_dataset_30k/posts.jsonl",N="demo_social_dataset_30k/comments.jsonl",z="demo_social_dataset_30k/video_captions.jsonl";function M(y){let t=y>>>0;return()=>{t|=0,t=t+1831565813|0;let e=Math.imul(t^t>>>15,1|t);return e=e+Math.imul(e^e>>>7,61|e)^e,((e^e>>>14)>>>0)/4294967296}}function f(y){let t=2166136261;for(let e=0;e<y.length;e++)t^=y.charCodeAt(e),t=Math.imul(t,16777619);return t>>>0}function B(y){let t=[],e=y.split(/\r?\n/);for(let s of e){let o=s.trim();if(o)try{t.push(JSON.parse(o))}catch{}}return t}var $=class y{constructor(t){this.fakeData=t}postsLoaded=!1;postsPromise=null;commentsLoaded=!1;commentsPromise=null;captionsLoaded=!1;captionsPromise=null;posts=[];postsById=new Map;postsByCountry=new Map;postsByAuthor=new Map;postStates=new Map;countryFeedCache=new Map;postSearchCache=new Map;postMediaMeta=new Map;captionsByPost=new Map;commentsByPost=new Map;localCommentsByPost=new Map;commentStates=new Map;commentOrderCache=new Map;profileMap=null;countryOffsets=new Map;pexelsCache=new Map;pexelsInflight=new Map;async isDemoPostId(t){return await this.ensurePostsLoaded(),this.postsById.has(t)}isDemoCommentId(t){return/^cmt_|^local_/.test(t)}async listByCountry(t,e=25,s){s?.skipComments?await this.ensurePostsLoaded():await this.ensureCommentsLoaded();let o=String(t||"").trim().toUpperCase(),i=this.postsByCountry.get(o)??[],a=this.buildBalancedOrder(i,o),r=Math.max(1,e),n=this.sliceWithOffset(o,a,r);return await this.hydrateMedia(n),n}async listForAuthor(t,e=25){await this.ensureCommentsLoaded();let i=[...this.postsByAuthor.get(t)??[]].sort((a,r)=>new Date(r.created_at).getTime()-new Date(a.created_at).getTime()).slice(0,Math.max(1,e));return await this.hydrateMedia(i),i}async listRecent(t=40){await this.ensurePostsLoaded();let e=this.buildBalancedOrder(this.posts,"WW"),s=Math.max(1,Math.min(t,this.posts.length||1)),o=this.sliceWithOffset("WW_GLOBAL",e,s);return await this.hydrateMedia(o),o}async getPostById(t){await this.ensureCommentsLoaded();let e=this.postsById.get(t)??null;return e?(await this.hydrateMedia([e]),e):null}async searchPosts(t,e=20){let s=String(t||"").trim().toLowerCase();if(!s)return[];await this.ensurePostsLoaded();let o=this.postSearchCache.get(s);if(o){if(e<=0)return o;let n=o.slice(0,Math.max(1,e));return await this.hydrateMedia(n),n}let a=this.posts.filter(n=>{let u=String(n.title||"").toLowerCase(),l=String(n.body||"").toLowerCase(),_=String(n.media_caption||"").toLowerCase();return u.includes(s)||l.includes(s)||_.includes(s)}).sort((n,u)=>new Date(u.created_at).getTime()-new Date(n.created_at).getTime());if(this.postSearchCache.set(s,a),this.postSearchCache.size>40){let n=this.postSearchCache.keys().next().value;n&&this.postSearchCache.delete(n)}if(e<=0)return a;let r=a.slice(0,Math.max(1,e));return await this.hydrateMedia(r),r}async listComments(t,e=25){await this.ensureCommentsLoaded();let s=this.getOrderedComments(t),o=this.localCommentsByPost.get(t)??[];return[...s,...o].slice(0,Math.max(1,e))}async addComment(t,e,s){await this.ensurePostsLoaded();let i=(await w.auth.getUser()).data.user?.id??"me",a=new Date().toISOString(),r={user_id:i,display_name:"You",username:null,avatar_url:null,country_name:null,country_code:null},n={id:`local_${Date.now()}_${Math.floor(Math.random()*1e4)}`,post_id:t,parent_id:s??null,author_id:i,body:e.trim(),like_count:0,liked_by_me:!1,created_at:a,updated_at:a,author:r},u=this.localCommentsByPost.get(t)??[];u.push(n),this.localCommentsByPost.set(t,u);let l=this.postStates.get(t);if(l){l.comment_count+=1;let _=this.postsById.get(t);_&&(_.comment_count=l.comment_count)}return n}async likePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.liked_by_me||(s.liked_by_me=!0,s.like_count+=1),this.applyState(e,s),e}async unlikePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.liked_by_me&&(s.liked_by_me=!1,s.like_count=Math.max(0,s.like_count-1)),this.applyState(e,s),e}async savePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.saved_by_me=!0,this.applyState(e,s),e}async unsavePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.saved_by_me=!1,this.applyState(e,s),e}async recordView(t){if(!t)return;await this.ensurePostsLoaded();let e=this.ensurePostState(t);e.view_count+=1;let s=this.postsById.get(t);s&&this.applyState(s,e)}async listLikes(t,e=25){await this.ensurePostsLoaded();let s=this.postStates.get(t),o=Math.max(0,Math.min(e,s?.like_count??0));if(!o)return[];let i=await this.fakeData.getProfiles();if(!i.length)return[];let a=M(f(`${t}|likes`)),r=new Set;for(;r.size<o&&r.size<i.length;)r.add(Math.floor(a()*i.length));let n=new Date().toISOString();return[...r].map(u=>{let l=i[u];return{user_id:l.user_id,created_at:n,user:this.profileToAuthor(l)}})}async likeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let s=this.ensureCommentState(t,e);return s.liked_by_me||(s.liked_by_me=!0,s.like_count+=1),e.liked_by_me=s.liked_by_me,e.like_count=s.like_count,e}async unlikeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let s=this.ensureCommentState(t,e);return s.liked_by_me&&(s.liked_by_me=!1,s.like_count=Math.max(0,s.like_count-1)),e.liked_by_me=s.liked_by_me,e.like_count=s.like_count,e}async ensurePostsLoaded(){if(!this.postsLoaded)return this.postsPromise?this.postsPromise:(this.postsPromise=(async()=>{await this.ensureCaptionsLoaded();let t=await this.fetchText(R),e=B(t),s=new Set;for(let o of e){let i=this.normalizeAuthorId(o?.author_id);i&&s.add(i)}await this.ensureProfileMap(s);for(let o of e){let i=this.normalizeAuthorId(o?.author_id);if(!o?.id||!i)continue;let a=String(o.country_code||this.profileMap?.get(i)?.country_code||"").trim().toUpperCase()||null,r=o.country_name||this.profileMap?.get(i)?.country_name||null,n=this.resolveAuthor(i,a,r),u=this.synthesizeMedia(o),l=u.type,_=u.url,m=u.thumb_url,c=this.normalizeBody(o.body??"",r||o.country_name||null);!c.trim()&&o.title&&(c=this.normalizeBody(String(o.title),r));let h=this.captionsByPost.get(o.id)??(c.trim()?c.trim().slice(0,180):null),k=o.created_at||new Date().toISOString(),p={id:o.id,title:null,body:c,media_type:l,media_url:_,thumb_url:m,media_caption:h,visibility:o.visibility||"public",like_count:0,comment_count:0,view_count:0,liked_by_me:!1,saved_by_me:!1,created_at:k,updated_at:k,author_id:i,country_name:r,country_code:a,city_name:null,author:n},D=this.seedCount(o.id,8e3),I=this.seedCount(`${o.id}|views`,18e4),g={like_count:D,comment_count:0,view_count:Math.max(I,D*6),liked_by_me:!1,saved_by_me:!1};this.postStates.set(o.id,g),this.applyState(p,g),this.posts.push(p),this.postsById.set(o.id,p);let C=String(a||"").trim().toUpperCase();if(C){let x=this.postsByCountry.get(C)??[];x.push(p),this.postsByCountry.set(C,x)}let L=this.postsByAuthor.get(i)??[];L.push(p),this.postsByAuthor.set(i,L),this.postMediaMeta.set(o.id,{type:l==="spark"||l==="reel"?"video":l,query:u.query,url:_,thumb_url:m})}this.postsLoaded=!0})(),this.postsPromise)}async ensureCommentsLoaded(){if(!this.commentsLoaded)return this.commentsPromise?this.commentsPromise:(this.commentsPromise=(async()=>{await this.ensurePostsLoaded();let t=await this.fetchText(N),e=B(t),s=new Set;for(let o of e){let i=this.normalizeAuthorId(o?.author_id);i&&s.add(i)}await this.ensureProfileMap(s);for(let o of e){let i=this.normalizeAuthorId(o?.author_id);if(!o?.id||!o?.post_id||!i)continue;let a=this.profileMap?.get(i)??null,r=o.created_at||new Date().toISOString(),n={id:o.id,post_id:o.post_id,parent_id:o.parent_id??null,author_id:i,body:o.body??"",like_count:this.seedCount(o.id,160),liked_by_me:!1,created_at:r,updated_at:r,author:a},u=this.commentsByPost.get(o.post_id)??[];u.push(n),this.commentsByPost.set(o.post_id,u),this.commentStates.set(o.id,{like_count:n.like_count,liked_by_me:!1});let l=this.postStates.get(o.post_id);l&&(l.comment_count+=1)}for(let[o,i]of this.postStates.entries()){let a=this.postsById.get(o);a&&(a.comment_count=i.comment_count)}this.commentsLoaded=!0})(),this.commentsPromise)}async ensureCaptionsLoaded(){if(!this.captionsLoaded)return this.captionsPromise?this.captionsPromise:(this.captionsPromise=(async()=>{let t=await this.fetchText(z),e=B(t);for(let s of e)!s?.post_id||!s?.caption||this.captionsByPost.set(s.post_id,s.caption);this.captionsLoaded=!0})(),this.captionsPromise)}async ensureProfileMap(t){if(!this.profileMap){let e=await this.fakeData.getProfiles(),s=new Map;for(let o of e)s.set(o.user_id,this.profileToAuthor(o));this.profileMap=s}if(t&&t.size){await this.fakeData.ensureProfilesById(t);for(let e of t){if(this.profileMap?.has(e))continue;let s=await this.fakeData.getProfileById(e);s&&this.profileMap?.set(e,this.profileToAuthor(s))}}}profileToAuthor(t){return{user_id:t.user_id,display_name:t.display_name??null,username:t.username??null,avatar_url:t.avatar_url??null,country_name:t.country_name??null,country_code:t.country_code??null}}applyState(t,e){t.like_count=e.like_count,t.comment_count=e.comment_count,t.view_count=e.view_count,t.liked_by_me=e.liked_by_me,t.saved_by_me=e.saved_by_me}ensurePostState(t){let e=this.postStates.get(t);return e||(e={like_count:0,comment_count:0,view_count:0,liked_by_me:!1,saved_by_me:!1},this.postStates.set(t,e)),e}resolveAuthor(t,e,s){let o=this.profileMap?.get(t)??null;if(o){let m=String(o.display_name||o.username||"").trim();if(m&&!this.looksLikeGenericAuthor(m,t))return q(A({},o),{country_code:o.country_code||e,country_name:o.country_name||s})}let i=f(t),a=["Amina","Sofia","Yuki","Mateo","Priya","Noah","Fatima","Luca","Mei","Omar","Elena","Kenji","Aisha","Hugo","Ingrid","Diego","Zara","Theo","Lina","Ravi"],r=["Nguyen","Silva","Kim","Rossi","Patel","Costa","Hassan","M\xFCller","Chen","Garc\xEDa","Okafor","Ivanov","Berg","Santos","Ali","Kowalski","Dubois","Yamamoto","Lopez","Singh"],n=a[i%a.length],u=r[(i>>>8)%r.length],l=`${n} ${u}`,_=`${n.toLowerCase()}_${u.toLowerCase()}${i%90+10}`;return{user_id:t,display_name:l,username:_,avatar_url:`https://api.dicebear.com/7.x/identicon/svg?seed=${encodeURIComponent(t)}`,country_name:s,country_code:e}}looksLikeGenericAuthor(t,e){let s=t.trim().toLowerCase();return!!(!s||s==="user"||s==="member"||s==="someone"||/^user[_\s]?\d+$/i.test(s)||s===e.toLowerCase()||/^user\s+[0-9a-f]{4,}$/i.test(s))}synthesizeMedia(t){if(t.media?.url)return{type:t.media?.type||"image",query:t.media?.query??null,url:t.media.url,thumb_url:t.media?.thumb_url??null};let e=f(String(t.id||t.title||"post")),s=e%100,o=String(t.category_slug||"travel").replace(/[_-]+/g," ").trim(),i=String(t.country_name||t.country_code||"world").trim(),a=`${o} ${i}`.trim()||"city life",r=["https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4"];return s<12?{type:"video",query:a,url:r[e%r.length],thumb_url:null}:s<78?{type:"image",query:a,url:`https://picsum.photos/seed/${e}/1080/1350`,thumb_url:`https://picsum.photos/seed/${e}/400/500`}:{type:"none",query:null,url:null,thumb_url:null}}ensureCommentState(t,e){let s=this.commentStates.get(t);return s||(s={like_count:e.like_count,liked_by_me:e.liked_by_me},this.commentStates.set(t,s)),s}findComment(t){for(let e of this.commentsByPost.values()){let s=e.find(o=>o.id===t);if(s)return s}for(let e of this.localCommentsByPost.values()){let s=e.find(o=>o.id===t);if(s)return s}return null}seedCount(t,e){let s=M(f(t));return Math.floor(Math.pow(s(),2)*e)}buildBalancedOrder(t,e){let s=Date.now(),o=Math.floor(s/(1e3*60*15)),i=`${e}:${o}`,a=this.countryFeedCache.get(i);if(a)return a.posts;let r=[...t].sort((c,h)=>new Date(h.created_at).getTime()-new Date(c.created_at).getTime()),n=new Map;for(let c of r){let h=n.get(c.author_id)??[];h.push(c),n.set(c.author_id,h)}let u=Array.from(n.keys()),l=M(f(`${e}|${o}`));for(let c=u.length-1;c>0;c-=1){let h=Math.floor(l()*(c+1)),k=u[c];u[c]=u[h],u[h]=k}let _=[],m=!0;for(;m;){m=!1;for(let c of u){let h=n.get(c);!h||!h.length||(_.push(h.shift()),m=!0)}}return this.countryFeedCache.set(i,{ts:s,posts:_}),_}sliceWithOffset(t,e,s){if(!e.length)return[];if(e.length<=s)return[...e];let i=(this.countryOffsets.get(t)??0)%e.length,a=i+s,r=(i+s)%e.length;if(this.countryOffsets.set(t,r),a<=e.length)return e.slice(i,a);let n=e.slice(i),u=e.slice(0,a-e.length);return[...n,...u]}normalizeBody(t,e){let s=String(t||"").trim();if(!s)return"";let o=s,i=/^in\s+[A-Za-z][^,.:;-]{1,60}[,.:;-]\s*/i;if(o=o.replace(i,"").trim(),!o||!e)return o;let a=e.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),r=new RegExp(`^In\\s+${a}\\b[\\s,.-]*`,"i");return o.replace(r,"").trim()}getOrderedComments(t){let e=this.commentOrderCache.get(t);if(e)return e;let s=this.commentsByPost.get(t)??[];if(!s.length)return this.commentOrderCache.set(t,[]),[];let o=[],i=new Set;for(let r of s){let n=`${r.author_id}|${this.normalizeCommentBody(r.body)}`;i.has(n)||(i.add(n),o.push(r))}let a=M(f(`${t}|comments`));for(let r=o.length-1;r>0;r-=1){let n=Math.floor(a()*(r+1)),u=o[r];o[r]=o[n],o[n]=u}return this.commentOrderCache.set(t,o),o}normalizeCommentBody(t){return String(t||"").trim().toLowerCase().replace(/\s+/g," ")}normalizeAuthorId(t){let e=String(t||"").trim();if(!e)return null;let s=e.match(/^user_(\d+)$/i);if(!s)return e;let o=parseInt(s[1],10);return!Number.isFinite(o)||o<=0?e:`user_${String(o).padStart(6,"0")}`}resolveAssetUrl(t){let e=document.querySelector("base")?.getAttribute("href")??"/",s=new URL(e,window.location.origin).toString();return new URL(t,s).toString()}async fetchText(t){if(typeof window>"u"||typeof document>"u")return"";let e=this.resolveAssetUrl(t),s=await fetch(e);if(!s.ok)throw new Error(`Failed to load ${t}: ${s.status}`);return s.text()}async hydrateMedia(t){if(!d.pexelsApiKey)return;let e=t.map(async s=>{if(!s)return;let o=String(s.media_type||"").toLowerCase();if(!o||o==="none"||s.media_url)return;let i=this.postMediaMeta.get(s.id),a=i?.query||String(s.country_name||s.title||"travel"),r=o==="video"||o==="reel"||o==="spark"||i?.type==="video"?"video":"image";if(!a)return;let n=`${r}:${a}`.toLowerCase(),u=this.pexelsCache.get(n);if(u){s.media_url=u.url,s.thumb_url=u.thumb_url;return}let l=this.pexelsInflight.get(n);if(l){let c=await l;s.media_url=c.url,s.thumb_url=c.thumb_url;return}let _=this.fetchPexels(r,a);this.pexelsInflight.set(n,_);let m=await _;this.pexelsInflight.delete(n),this.pexelsCache.set(n,m),s.media_url=m.url,s.thumb_url=m.thumb_url});await Promise.all(e)}async fetchPexels(t,e){let s=d.pexelsApiKey||"",o=t==="video"||t==="spark"||t==="reel";if(!s)return this.fallbackMedia(e,o);try{let i={Authorization:s};if(o){let _=`https://api.pexels.com/videos/search?query=${encodeURIComponent(e)}&per_page=1`,m=await fetch(_,{headers:i});if(!m.ok)return this.fallbackMedia(e,!0);let h=(await m.json())?.videos?.[0];if(!h)return this.fallbackMedia(e,!0);let p=(Array.isArray(h.video_files)?h.video_files:[]).filter(g=>String(g?.file_type||"").toLowerCase()==="video/mp4").sort((g,C)=>(g?.width??0)-(C?.width??0)),D=p.find(g=>(g?.width??0)>=720)||p[0],I=h.video_pictures?.[0]?.picture||h.image||null;return{url:D?.link??null,thumb_url:I}}let a=`https://api.pexels.com/v1/search?query=${encodeURIComponent(e)}&per_page=1`,r=await fetch(a,{headers:i});if(!r.ok)return this.fallbackMedia(e,!1);let l=(await r.json())?.photos?.[0]?.src||{};return{url:l?.large??l?.medium??null,thumb_url:l?.medium??null}}catch{return this.fallbackMedia(e,o)}}fallbackMedia(t,e){let s=f(String(t||"demo"));if(e){let i=["https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4"];return{url:i[s%i.length],thumb_url:null}}return{url:`https://picsum.photos/seed/${s}/1080/1350`,thumb_url:`https://picsum.photos/seed/${s}/400/500`}}static \u0275fac=function(e){return new(e||y)(v(O))};static \u0275prov=b({token:y,factory:y.\u0275fac,providedIn:"root"})};var F=class y{constructor(t,e,s){this.gql=t;this.postEvents=e;this.demoData=s}async listByCountry(t,e=25,s){let o=d.useDemoDataset?500:80,i=Math.max(1,Math.min(o,e||25)),a=`
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
    `;try{let{postsByCountry:r}=await this.withTimeout(this.gql.request(a,{code:t,limit:i}),8e3,"postsByCountry"),n=(r??[]).map(_=>this.mapPost(_)).filter(_=>!this.isMoment(_));if(!d.useDemoDataset)return n;let u=Math.min(s?.demoLimit??i,d.useDemoDataset?400:40),l=await this.withTimeout(this.demoData.listByCountry(t,u,{skipComments:s?.skipComments??!0}),8e3,"demoPostsByCountry").catch(()=>[]);return this.mergePosts(n,l,i)}catch{if(!d.useDemoDataset)return[];try{return await this.withTimeout(this.demoData.listByCountry(t,Math.min(i,200),{skipComments:!0}),8e3,"demoPostsByCountryFallback")}catch{return[]}}}async listRecent(t=40,e){let s=`
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
    `;try{let o=d.useDemoDataset?500:80,i=Math.max(1,Math.min(o,t||40)),{recentPosts:a}=await this.withTimeout(this.gql.request(s,{limit:Math.min(80,i),before:e??null}),8e3,"recentPosts"),r=(a??[]).map(l=>this.mapPost(l)).filter(l=>!this.isMoment(l));if(!d.useDemoDataset)return r;let n=Math.max(i,Math.min(800,i*4)),u=await this.withTimeout(this.demoData.listRecent(n),12e3,"demoRecentPosts").catch(()=>[]);return this.mergePosts(r,u,i)}catch{if(!d.useDemoDataset)return[];try{return await this.withTimeout(this.demoData.listRecent(Math.min(t||40,500)),12e3,"demoRecentPostsFallback")}catch{return[]}}}isMoment(t){if(!t)return!1;let e=String(t.media_type||"").toLowerCase();return e==="story"||e==="moment"?!0:String(t.body||"").includes("__story__|")}isSpark(t){if(!t||this.isMoment(t))return!1;let e=String(t.media_type||"").toLowerCase();if(e==="reel"||e==="spark")return!0;let s=String(t.media_url||"").trim();if(s.startsWith("{")||s.startsWith("["))try{let o=JSON.parse(s),i=o?.reel??o?.spark;return i===!0||i==="true"||i===1||i==="1"}catch{return!1}return!1}isMomentActive(t){if(!this.isMoment(t))return!1;let s=String(t.body||"").match(/__story__\|expires=([^\s|]+)/i);if(!s?.[1])return!0;let o=Date.parse(s[1]);return Number.isFinite(o)?o>Date.now():!0}async listActiveMoments(t=40,e){let s=(e?.followingIds??[]).filter(Boolean).slice(0,8),o=await Promise.all([e?.authorId?this.listForAuthor(e.authorId,24).catch(()=>[]):Promise.resolve([]),...s.map(r=>this.listForAuthor(r,10).catch(()=>[]))]),i=new Set,a=[];for(let r of o)for(let n of r)!n?.id||i.has(n.id)||this.isMomentActive(n)&&(i.add(n.id),a.push(n));return a.sort((r,n)=>{let u=Date.parse(r.created_at||"")||0;return(Date.parse(n.created_at||"")||0)-u}),a.slice(0,Math.max(1,t))}async loadHomeFeed(t){let e=t?.maxPosts??(d.useDemoDataset?600:50),s=(t?.followingIds??[]).filter(Boolean).slice(0,6),o=d.useDemoDataset?Math.min(e,500):40,i=d.useDemoDataset?200:24,a=await Promise.all([this.listRecent(o).catch(()=>[]),t?.countryCode?this.listByCountry(t.countryCode,i,{demoLimit:i,skipComments:!0}).catch(()=>[]):Promise.resolve([]),t?.authorId?this.withTimeout(this.listForAuthor(t.authorId,12),5e3,"feedAuthor").catch(()=>[]):Promise.resolve([]),...s.map(u=>this.withTimeout(this.listForAuthor(u,3),4e3,"feedFollowing").catch(()=>[]))]),r=new Set,n=[];for(let u of a)for(let l of u)!l?.id||r.has(l.id)||this.isMoment(l)||(r.add(l.id),n.push(l));return n.sort((u,l)=>{let _=Date.parse(u.created_at||"")||0;return(Date.parse(l.created_at||"")||0)-_}),n.slice(0,e)}async listForAuthor(t,e=25){if(!t)return[];if(d.useDemoDataset&&/^user_/.test(t))return this.demoData.listForAuthor(t,e);let s=`
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
    `;try{let{postsByAuthor:o}=await this.withTimeout(this.gql.request(s,{authorId:t,limit:Math.max(1,Math.min(60,e||25))}),8e3,"postsByAuthor");return(o??[]).map(i=>this.mapPost(i))}catch{return[]}}async searchPosts(t,e=25){let s=String(t||"").trim();if(!s)return[];let o=`
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
    `;try{let{searchPosts:i}=await this.gql.request(o,{query:s,limit:e});return(i??[]).map(a=>this.mapPost(a))}catch{return[]}}async getPostById(t){if(!t)return null;if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.getPostById(t);let e=`
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
    `,{postById:s}=await this.gql.request(e,{postId:t});return s?this.mapPost(s):null}async createPost(t){if(!t.authorId)throw new Error("authorId is required to post.");let e=`
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
    `,s={title:t.title?.trim()||null,body:t.body.trim(),country_name:t.countryName,country_code:t.countryCode,city_name:t.cityName??null,visibility:t.visibility??null,media_type:t.mediaType??null,media_url:t.mediaUrl??null,thumb_url:t.thumbUrl??null,shared_post_id:t.sharedPostId??null},{createPost:o}=await this.gql.request(e,{input:s}),i=this.mapPost(o);return this.postEvents.emit(i),i}async updatePost(t,e){let s=`
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
    `,o={title:e.title?.trim()??null,body:e.body?.trim()??null,visibility:e.visibility??null},{updatePost:i}=await this.gql.request(s,{postId:t,input:o}),a=this.mapPost(i);return this.postEvents.emitUpdated(a),a}async deletePost(t,e){let s=`
      mutation DeletePost($postId: ID!) {
        deletePost(post_id: $postId)
      }
    `,{deletePost:o}=await this.gql.request(s,{postId:t});return o&&this.postEvents.emitDeleted({id:t,country_code:e?.country_code??null,author_id:e?.author_id??null}),o}async likePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.likePost(t);return this.postEvents.emitUpdated(i),i}let e=`
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
    `,{likePost:s}=await this.gql.request(e,{postId:t}),o=this.mapPost(s);return this.postEvents.emitUpdated(o),o}async unlikePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.unlikePost(t);return this.postEvents.emitUpdated(i),i}let e=`
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
    `,{unlikePost:s}=await this.gql.request(e,{postId:t}),o=this.mapPost(s);return this.postEvents.emitUpdated(o),o}async recordView(t){if(t?.id){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t.id)){await this.demoData.recordView(t.id);return}t.view_count=Number(t.view_count??0)+1}}async savePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.savePost(t);return this.postEvents.emitUpdated(i),i}let e=`
      mutation SavePost($postId: ID!) {
        savePost(post_id: $postId) {
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
          saved_by_me
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
    `,{savePost:s}=await this.gql.request(e,{postId:t}),o=this.mapPost(s);return this.postEvents.emitUpdated(o),o}async unsavePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.unsavePost(t);return this.postEvents.emitUpdated(i),i}let e=`
      mutation UnsavePost($postId: ID!) {
        unsavePost(post_id: $postId) {
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
          saved_by_me
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
    `,{unsavePost:s}=await this.gql.request(e,{postId:t}),o=this.mapPost(s);return this.postEvents.emitUpdated(o),o}async listComments(t,e=25,s){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let a=Math.max(e,1e3);return this.demoData.listComments(t,a)}let o=`
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
    `,{commentsByPost:i}=await this.gql.request(o,{postId:t,limit:e,before:s??null});return(i??[]).map(a=>this.mapComment(a))}async listLikes(t,e=25){if(!t)return[];if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.listLikes(t,e);let s=`
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
    `,{postLikes:o}=await this.gql.request(s,{postId:t,limit:e});return(o??[]).map(i=>this.mapLike(i))}async addComment(t,e,s){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.addComment(t,e,s??null);let o=`
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
    `,{addComment:i}=await this.gql.request(o,{postId:t,body:e.trim(),parentId:s??null});return this.mapComment(i)}async likeComment(t){if(d.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.likeComment(t);let e=`
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
    `,{likeComment:s}=await this.gql.request(e,{commentId:t});return this.mapComment(s)}async unlikeComment(t){if(d.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.unlikeComment(t);let e=`
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
    `,{unlikeComment:s}=await this.gql.request(e,{commentId:t});return this.mapComment(s)}async reportPost(t,e){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))throw new Error("Only live posts can be reported right now.");let s=`
      mutation ReportPost($postId: ID!, $reason: String!) {
        reportPost(post_id: $postId, reason: $reason)
      }
    `,{reportPost:o}=await this.gql.request(s,{postId:t,reason:e.trim()});return!!o}stripMomentMarkers(t){return String(t??"").split(`
`).filter(e=>{let s=e.trim();return s?!(/__story__/i.test(s)||/\bstory\b/i.test(s)&&/\bexpir/i.test(s)):!0}).join(`
`).replace(/\n{3,}/g,`

`).trim()}mapPost(t,e=0){let s=t?.view_count!=null?Number(t.view_count):this.estimateViewCount(t?.id,t?.like_count,t?.comment_count),o=t?.shared_post&&e<1?this.mapPost(t.shared_post,e+1):null;return{id:t.id,title:t.title??null,body:this.stripMomentMarkers(t.body??""),media_type:t.media_type??"none",media_url:t.media_url??null,thumb_url:t.thumb_url??null,media_caption:t.media_caption??null,shared_post_id:t.shared_post_id??null,shared_post:o,visibility:t.visibility??"public",like_count:Number(t.like_count??0),comment_count:Number(t.comment_count??0),view_count:s,liked_by_me:!!t.liked_by_me,saved_by_me:!!t.saved_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author_id:t.author_id,country_name:t.country_name??null,country_code:t.country_code??null,city_name:t.city_name??null,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null,external_ref_type:t.external_ref_type??null,external_ref_id:t.external_ref_id??null,link_url:t.link_url??null,link_title:t.link_title??null,link_source_name:t.link_source_name??null,link_published_at:t.link_published_at??null,link_image_url:t.link_image_url??null,link_snippet:t.link_snippet??null}}mapComment(t){return{id:t.id,post_id:t.post_id,parent_id:t.parent_id??null,author_id:t.author_id,body:t.body??"",like_count:Number(t.like_count??0),liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapLike(t){return{user_id:t.user_id,created_at:t.created_at,user:t.user?{user_id:t.user.user_id,display_name:t.user.display_name,username:t.user.username,avatar_url:this.resolveAvatarUrl(t.user.avatar_url,t.user.user_id,t.user.username),country_name:t.user.country_name,country_code:t.user.country_code}:null}}resolveAvatarUrl(t,e,s){return U(t,s||e)}mergePosts(t,e,s){let o=Math.max(1,s),i=[...t].filter(m=>!!m?.id).sort((m,c)=>new Date(c.created_at).getTime()-new Date(m.created_at).getTime()),a=new Set(i.map(m=>m.id)),r=[...e].filter(m=>m?.id&&!a.has(m.id)).sort((m,c)=>new Date(c.created_at).getTime()-new Date(m.created_at).getTime()),n=[],u=0,l=0,_=r.length>i.length*2?4:2;for(;n.length<o&&(u<i.length||l<r.length);){u<i.length&&n.length<o&&n.push(i[u++]);for(let m=0;m<_&&l<r.length&&n.length<o;m+=1)n.push(r[l++]);if(u>=i.length)for(;l<r.length&&n.length<o;)n.push(r[l++]);if(l>=r.length)for(;u<i.length&&n.length<o;)n.push(i[u++])}return n}estimateViewCount(t,e,s){let o=Number(e??0),i=Number(s??0);if(!o&&!i)return 0;let r=this.hashSeed(String(t||"post"))%1200,n=o*12+i*6+r;return Math.max(n,o+i)}hashSeed(t){let e=2166136261;for(let s=0;s<t.length;s++)e^=t.charCodeAt(s),e=Math.imul(e,16777619);return e>>>0}async withTimeout(t,e,s){let o=null;try{return await Promise.race([t,new Promise((i,a)=>{o=setTimeout(()=>a(new Error(`${s} timeout`)),e)})])}finally{o&&clearTimeout(o)}}static \u0275fac=function(e){return new(e||y)(v(T),v(S),v($))};static \u0275prov=b({token:y,factory:y.\u0275fac,providedIn:"root"})};export{S as a,F as b};
