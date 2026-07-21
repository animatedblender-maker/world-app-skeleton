import{a as T}from"./chunk-CUVPT7L7.js";import{a as A}from"./chunk-G4AEBNEO.js";import{a as q}from"./chunk-NQC6INBE.js";import{a as d}from"./chunk-LQQHCQP3.js";import{b as w}from"./chunk-O6RSSF7I.js";import{a as f,k as P,n as b}from"./chunk-X6NOM4Z7.js";var S=class h{createdPostSubject=new f;createdPost$=this.createdPostSubject.asObservable();updatedPostSubject=new f;updatedPost$=this.updatedPostSubject.asObservable();insertSubject=new f;insert$=this.insertSubject.asObservable();updateSubject=new f;update$=this.updateSubject.asObservable();deleteSubject=new f;delete$=this.deleteSubject.asObservable();channel=w.channel("public:posts");constructor(){this.channel.on("postgres_changes",{event:"INSERT",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.insertSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.updateSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null,visibility:t.visibility??null})}).on("postgres_changes",{event:"DELETE",schema:"public",table:"posts"},({old:t})=>{t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).subscribe()}emit(t){this.createdPostSubject.next(t)}emitUpdated(t){this.updatedPostSubject.next(t)}emitDeleted(t){t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}ngOnDestroy(){this.channel?.unsubscribe()}static \u0275fac=function(e){return new(e||h)};static \u0275prov=P({token:h,factory:h.\u0275fac,providedIn:"root"})};var j="demo_social_dataset_30k/posts.jsonl",F="demo_social_dataset_30k/comments.jsonl",R="demo_social_dataset_30k/video_captions.jsonl";function M(h){let t=h>>>0;return()=>{t|=0,t=t+1831565813|0;let e=Math.imul(t^t>>>15,1|t);return e=e+Math.imul(e^e>>>7,61|e)^e,((e^e>>>14)>>>0)/4294967296}}function v(h){let t=2166136261;for(let e=0;e<h.length;e++)t^=h.charCodeAt(e),t=Math.imul(t,16777619);return t>>>0}function B(h){let t=[],e=h.split(/\r?\n/);for(let s of e){let n=s.trim();if(n)try{t.push(JSON.parse(n))}catch{}}return t}var I=class h{constructor(t){this.fakeData=t}postsLoaded=!1;postsPromise=null;commentsLoaded=!1;commentsPromise=null;captionsLoaded=!1;captionsPromise=null;posts=[];postsById=new Map;postsByCountry=new Map;postsByAuthor=new Map;postStates=new Map;countryFeedCache=new Map;postSearchCache=new Map;postMediaMeta=new Map;captionsByPost=new Map;commentsByPost=new Map;localCommentsByPost=new Map;commentStates=new Map;commentOrderCache=new Map;profileMap=null;countryOffsets=new Map;pexelsCache=new Map;pexelsInflight=new Map;async isDemoPostId(t){return await this.ensurePostsLoaded(),this.postsById.has(t)}isDemoCommentId(t){return/^cmt_|^local_/.test(t)}async listByCountry(t,e=25,s){s?.skipComments?await this.ensurePostsLoaded():await this.ensureCommentsLoaded();let n=String(t||"").trim().toUpperCase(),i=this.postsByCountry.get(n)??[],a=this.buildBalancedOrder(i,n),r=Math.max(1,e),o=this.sliceWithOffset(n,a,r);return await this.hydrateMedia(o),o}async listForAuthor(t,e=25){await this.ensureCommentsLoaded();let i=[...this.postsByAuthor.get(t)??[]].sort((a,r)=>new Date(r.created_at).getTime()-new Date(a.created_at).getTime()).slice(0,Math.max(1,e));return await this.hydrateMedia(i),i}async listRecent(t=40){await this.ensurePostsLoaded();let s=[...this.posts].sort((n,i)=>new Date(i.created_at).getTime()-new Date(n.created_at).getTime()).slice(0,Math.max(1,t));return await this.hydrateMedia(s),s}async getPostById(t){await this.ensureCommentsLoaded();let e=this.postsById.get(t)??null;return e?(await this.hydrateMedia([e]),e):null}async searchPosts(t,e=20){let s=String(t||"").trim().toLowerCase();if(!s)return[];await this.ensurePostsLoaded();let n=this.postSearchCache.get(s);if(n){if(e<=0)return n;let o=n.slice(0,Math.max(1,e));return await this.hydrateMedia(o),o}let a=this.posts.filter(o=>{let u=String(o.title||"").toLowerCase(),l=String(o.body||"").toLowerCase(),m=String(o.media_caption||"").toLowerCase();return u.includes(s)||l.includes(s)||m.includes(s)}).sort((o,u)=>new Date(u.created_at).getTime()-new Date(o.created_at).getTime());if(this.postSearchCache.set(s,a),this.postSearchCache.size>40){let o=this.postSearchCache.keys().next().value;o&&this.postSearchCache.delete(o)}if(e<=0)return a;let r=a.slice(0,Math.max(1,e));return await this.hydrateMedia(r),r}async listComments(t,e=25){await this.ensureCommentsLoaded();let s=this.getOrderedComments(t),n=this.localCommentsByPost.get(t)??[];return[...s,...n].slice(0,Math.max(1,e))}async addComment(t,e,s){await this.ensurePostsLoaded();let i=(await w.auth.getUser()).data.user?.id??"me",a=new Date().toISOString(),r={user_id:i,display_name:"You",username:null,avatar_url:null,country_name:null,country_code:null},o={id:`local_${Date.now()}_${Math.floor(Math.random()*1e4)}`,post_id:t,parent_id:s??null,author_id:i,body:e.trim(),like_count:0,liked_by_me:!1,created_at:a,updated_at:a,author:r},u=this.localCommentsByPost.get(t)??[];u.push(o),this.localCommentsByPost.set(t,u);let l=this.postStates.get(t);if(l){l.comment_count+=1;let m=this.postsById.get(t);m&&(m.comment_count=l.comment_count)}return o}async likePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.liked_by_me||(s.liked_by_me=!0,s.like_count+=1),this.applyState(e,s),e}async unlikePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.liked_by_me&&(s.liked_by_me=!1,s.like_count=Math.max(0,s.like_count-1)),this.applyState(e,s),e}async savePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.saved_by_me=!0,this.applyState(e,s),e}async unsavePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.saved_by_me=!1,this.applyState(e,s),e}async recordView(t){if(!t)return;await this.ensurePostsLoaded();let e=this.ensurePostState(t);e.view_count+=1;let s=this.postsById.get(t);s&&this.applyState(s,e)}async listLikes(t,e=25){await this.ensurePostsLoaded();let s=this.postStates.get(t),n=Math.max(0,Math.min(e,s?.like_count??0));if(!n)return[];let i=await this.fakeData.getProfiles();if(!i.length)return[];let a=M(v(`${t}|likes`)),r=new Set;for(;r.size<n&&r.size<i.length;)r.add(Math.floor(a()*i.length));let o=new Date().toISOString();return[...r].map(u=>{let l=i[u];return{user_id:l.user_id,created_at:o,user:this.profileToAuthor(l)}})}async likeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let s=this.ensureCommentState(t,e);return s.liked_by_me||(s.liked_by_me=!0,s.like_count+=1),e.liked_by_me=s.liked_by_me,e.like_count=s.like_count,e}async unlikeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let s=this.ensureCommentState(t,e);return s.liked_by_me&&(s.liked_by_me=!1,s.like_count=Math.max(0,s.like_count-1)),e.liked_by_me=s.liked_by_me,e.like_count=s.like_count,e}async ensurePostsLoaded(){if(!this.postsLoaded)return this.postsPromise?this.postsPromise:(this.postsPromise=(async()=>{await this.ensureCaptionsLoaded();let t=await this.fetchText(j),e=B(t),s=new Set;for(let n of e){let i=this.normalizeAuthorId(n?.author_id);i&&s.add(i)}await this.ensureProfileMap(s);for(let n of e){let i=this.normalizeAuthorId(n?.author_id);if(!n?.id||!i)continue;let a=this.profileMap?.get(i)??null,r=this.synthesizeMedia(n),o=r.type,u=r.url,l=r.thumb_url,m=String(n.title||n.body||"").trim().slice(0,180),y=this.captionsByPost.get(n.id)??(m||null),c=a?.country_code??n.country_code??null,_=a?.country_name??n.country_name??null,C=n.created_at||new Date().toISOString(),p={id:n.id,title:n.title??null,body:this.normalizeBody(n.body??"",_||n.country_name||null),media_type:o,media_url:u,thumb_url:l,media_caption:y,visibility:n.visibility||"public",like_count:0,comment_count:0,view_count:0,liked_by_me:!1,saved_by_me:!1,created_at:C,updated_at:C,author_id:i,country_name:_,country_code:c,city_name:null,author:a},D=this.seedCount(n.id,8e3),$=this.seedCount(`${n.id}|views`,18e4),g={like_count:D,comment_count:0,view_count:Math.max($,D*6),liked_by_me:!1,saved_by_me:!1};this.postStates.set(n.id,g),this.applyState(p,g),this.posts.push(p),this.postsById.set(n.id,p);let k=String(c||"").trim().toUpperCase();if(k){let L=this.postsByCountry.get(k)??[];L.push(p),this.postsByCountry.set(k,L)}let x=this.postsByAuthor.get(i)??[];x.push(p),this.postsByAuthor.set(i,x),this.postMediaMeta.set(n.id,{type:o==="spark"||o==="reel"?"video":o,query:r.query,url:u,thumb_url:l})}this.postsLoaded=!0})(),this.postsPromise)}async ensureCommentsLoaded(){if(!this.commentsLoaded)return this.commentsPromise?this.commentsPromise:(this.commentsPromise=(async()=>{await this.ensurePostsLoaded();let t=await this.fetchText(F),e=B(t),s=new Set;for(let n of e){let i=this.normalizeAuthorId(n?.author_id);i&&s.add(i)}await this.ensureProfileMap(s);for(let n of e){let i=this.normalizeAuthorId(n?.author_id);if(!n?.id||!n?.post_id||!i)continue;let a=this.profileMap?.get(i)??null,r=n.created_at||new Date().toISOString(),o={id:n.id,post_id:n.post_id,parent_id:n.parent_id??null,author_id:i,body:n.body??"",like_count:this.seedCount(n.id,160),liked_by_me:!1,created_at:r,updated_at:r,author:a},u=this.commentsByPost.get(n.post_id)??[];u.push(o),this.commentsByPost.set(n.post_id,u),this.commentStates.set(n.id,{like_count:o.like_count,liked_by_me:!1});let l=this.postStates.get(n.post_id);l&&(l.comment_count+=1)}for(let[n,i]of this.postStates.entries()){let a=this.postsById.get(n);a&&(a.comment_count=i.comment_count)}this.commentsLoaded=!0})(),this.commentsPromise)}async ensureCaptionsLoaded(){if(!this.captionsLoaded)return this.captionsPromise?this.captionsPromise:(this.captionsPromise=(async()=>{let t=await this.fetchText(R),e=B(t);for(let s of e)!s?.post_id||!s?.caption||this.captionsByPost.set(s.post_id,s.caption);this.captionsLoaded=!0})(),this.captionsPromise)}async ensureProfileMap(t){if(!this.profileMap){let e=await this.fakeData.getProfiles(),s=new Map;for(let n of e)s.set(n.user_id,this.profileToAuthor(n));this.profileMap=s}if(t&&t.size){await this.fakeData.ensureProfilesById(t);for(let e of t){if(this.profileMap?.has(e))continue;let s=await this.fakeData.getProfileById(e);s&&this.profileMap?.set(e,this.profileToAuthor(s))}}}profileToAuthor(t){return{user_id:t.user_id,display_name:t.display_name??null,username:t.username??null,avatar_url:t.avatar_url??null,country_name:t.country_name??null,country_code:t.country_code??null}}applyState(t,e){t.like_count=e.like_count,t.comment_count=e.comment_count,t.view_count=e.view_count,t.liked_by_me=e.liked_by_me,t.saved_by_me=e.saved_by_me}ensurePostState(t){let e=this.postStates.get(t);return e||(e={like_count:0,comment_count:0,view_count:0,liked_by_me:!1,saved_by_me:!1},this.postStates.set(t,e)),e}synthesizeMedia(t){if(t.media?.url)return{type:t.media?.type||"image",query:t.media?.query??null,url:t.media.url,thumb_url:t.media?.thumb_url??null};if(t.media?.type&&t.media?.query)return{type:t.media.type,query:t.media.query,url:null,thumb_url:t.media?.thumb_url??null};let s=v(String(t.id||t.title||"post"))%100,n=String(t.category_slug||"travel").replace(/[_-]+/g," ").trim(),i=String(t.country_name||t.country_code||"world").trim(),a=`${n} ${i}`.trim()||"city life";return s<35?{type:"spark",query:a,url:null,thumb_url:null}:s<85?{type:"image",query:a,url:null,thumb_url:null}:{type:"none",query:null,url:null,thumb_url:null}}ensureCommentState(t,e){let s=this.commentStates.get(t);return s||(s={like_count:e.like_count,liked_by_me:e.liked_by_me},this.commentStates.set(t,s)),s}findComment(t){for(let e of this.commentsByPost.values()){let s=e.find(n=>n.id===t);if(s)return s}for(let e of this.localCommentsByPost.values()){let s=e.find(n=>n.id===t);if(s)return s}return null}seedCount(t,e){let s=M(v(t));return Math.floor(Math.pow(s(),2)*e)}buildBalancedOrder(t,e){let s=Date.now(),n=Math.floor(s/(1e3*60*15)),i=`${e}:${n}`,a=this.countryFeedCache.get(i);if(a)return a.posts;let r=[...t].sort((c,_)=>new Date(_.created_at).getTime()-new Date(c.created_at).getTime()),o=new Map;for(let c of r){let _=o.get(c.author_id)??[];_.push(c),o.set(c.author_id,_)}let u=Array.from(o.keys()),l=M(v(`${e}|${n}`));for(let c=u.length-1;c>0;c-=1){let _=Math.floor(l()*(c+1)),C=u[c];u[c]=u[_],u[_]=C}let m=[],y=!0;for(;y;){y=!1;for(let c of u){let _=o.get(c);!_||!_.length||(m.push(_.shift()),y=!0)}}return this.countryFeedCache.set(i,{ts:s,posts:m}),m}sliceWithOffset(t,e,s){if(!e.length)return[];if(e.length<=s)return[...e];let i=(this.countryOffsets.get(t)??0)%e.length,a=i+s,r=(i+s)%e.length;if(this.countryOffsets.set(t,r),a<=e.length)return e.slice(i,a);let o=e.slice(i),u=e.slice(0,a-e.length);return[...o,...u]}normalizeBody(t,e){let s=String(t||"").trim();if(!s)return"";let n=s,i=/^in\s+[A-Za-z][^,.:;-]{1,60}[,.:;-]\s*/i;if(n=n.replace(i,"").trim(),!n||!e)return n;let a=e.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),r=new RegExp(`^In\\s+${a}\\b[\\s,.-]*`,"i");return n.replace(r,"").trim()}getOrderedComments(t){let e=this.commentOrderCache.get(t);if(e)return e;let s=this.commentsByPost.get(t)??[];if(!s.length)return this.commentOrderCache.set(t,[]),[];let n=[],i=new Set;for(let r of s){let o=`${r.author_id}|${this.normalizeCommentBody(r.body)}`;i.has(o)||(i.add(o),n.push(r))}let a=M(v(`${t}|comments`));for(let r=n.length-1;r>0;r-=1){let o=Math.floor(a()*(r+1)),u=n[r];n[r]=n[o],n[o]=u}return this.commentOrderCache.set(t,n),n}normalizeCommentBody(t){return String(t||"").trim().toLowerCase().replace(/\s+/g," ")}normalizeAuthorId(t){let e=String(t||"").trim();if(!e)return null;let s=e.match(/^user_(\d+)$/i);if(!s)return e;let n=parseInt(s[1],10);return!Number.isFinite(n)||n<=0?e:`user_${String(n).padStart(6,"0")}`}resolveAssetUrl(t){let e=document.querySelector("base")?.getAttribute("href")??"/",s=new URL(e,window.location.origin).toString();return new URL(t,s).toString()}async fetchText(t){if(typeof window>"u"||typeof document>"u")return"";let e=this.resolveAssetUrl(t),s=await fetch(e);if(!s.ok)throw new Error(`Failed to load ${t}: ${s.status}`);return s.text()}async hydrateMedia(t){if(!d.pexelsApiKey)return;let e=t.map(async s=>{if(!s)return;let n=String(s.media_type||"").toLowerCase();if(!n||n==="none"||s.media_url)return;let i=this.postMediaMeta.get(s.id),a=i?.query||String(s.country_name||s.title||"travel"),r=n==="video"||n==="reel"||n==="spark"||i?.type==="video"?"video":"image";if(!a)return;let o=`${r}:${a}`.toLowerCase(),u=this.pexelsCache.get(o);if(u){s.media_url=u.url,s.thumb_url=u.thumb_url;return}let l=this.pexelsInflight.get(o);if(l){let c=await l;s.media_url=c.url,s.thumb_url=c.thumb_url;return}let m=this.fetchPexels(r,a);this.pexelsInflight.set(o,m);let y=await m;this.pexelsInflight.delete(o),this.pexelsCache.set(o,y),s.media_url=y.url,s.thumb_url=y.thumb_url});await Promise.all(e)}async fetchPexels(t,e){let s=d.pexelsApiKey||"",n=t==="video"||t==="spark"||t==="reel";if(!s)return this.fallbackMedia(e,n);try{let i={Authorization:s};if(n){let m=`https://api.pexels.com/videos/search?query=${encodeURIComponent(e)}&per_page=1`,y=await fetch(m,{headers:i});if(!y.ok)return this.fallbackMedia(e,!0);let _=(await y.json())?.videos?.[0];if(!_)return this.fallbackMedia(e,!0);let p=(Array.isArray(_.video_files)?_.video_files:[]).filter(g=>String(g?.file_type||"").toLowerCase()==="video/mp4").sort((g,k)=>(g?.width??0)-(k?.width??0)),D=p.find(g=>(g?.width??0)>=720)||p[0],$=_.video_pictures?.[0]?.picture||_.image||null;return{url:D?.link??null,thumb_url:$}}let a=`https://api.pexels.com/v1/search?query=${encodeURIComponent(e)}&per_page=1`,r=await fetch(a,{headers:i});if(!r.ok)return this.fallbackMedia(e,!1);let l=(await r.json())?.photos?.[0]?.src||{};return{url:l?.large??l?.medium??null,thumb_url:l?.medium??null}}catch{return this.fallbackMedia(e,n)}}fallbackMedia(t,e){let s=v(String(t||"demo"));if(e){let i=["https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4","https://storage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4"];return{url:i[s%i.length],thumb_url:null}}return{url:`https://picsum.photos/seed/${s}/1080/1350`,thumb_url:`https://picsum.photos/seed/${s}/400/500`}}static \u0275fac=function(e){return new(e||h)(b(A))};static \u0275prov=P({token:h,factory:h.\u0275fac,providedIn:"root"})};var E=class h{constructor(t,e,s){this.gql=t;this.postEvents=e;this.demoData=s}async listByCountry(t,e=25,s){let n=Math.max(1,Math.min(80,e||25)),i=`
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
    `;try{let{postsByCountry:a}=await this.withTimeout(this.gql.request(i,{code:t,limit:n}),8e3,"postsByCountry"),r=(a??[]).map(l=>this.mapPost(l)).filter(l=>!this.isMoment(l));if(!d.useDemoDataset)return r;let o=Math.min(s?.demoLimit??n,40),u=await this.withTimeout(this.demoData.listByCountry(t,o,{skipComments:s?.skipComments??!0}),2500,"demoPostsByCountry").catch(()=>[]);return this.mergePosts(r,u,n)}catch{if(!d.useDemoDataset)return[];try{return await this.withTimeout(this.demoData.listByCountry(t,Math.min(n,20),{skipComments:!0}),2500,"demoPostsByCountryFallback")}catch{return[]}}}async listRecent(t=40,e){let s=`
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
    `;try{let{recentPosts:n}=await this.withTimeout(this.gql.request(s,{limit:Math.max(1,Math.min(80,t||40)),before:e??null}),8e3,"recentPosts"),i=(n??[]).map(r=>this.mapPost(r)).filter(r=>!this.isMoment(r));if(!d.useDemoDataset)return i;let a=await this.withTimeout(this.demoData.listRecent(Math.min(t||40,30)),2500,"demoRecentPosts").catch(()=>[]);return this.mergePosts(i,a,Math.max(1,Math.min(80,t||40)))}catch{if(!d.useDemoDataset)return[];try{return await this.withTimeout(this.demoData.listRecent(Math.min(t||40,20)),2500,"demoRecentPostsFallback")}catch{return[]}}}isMoment(t){if(!t)return!1;let e=String(t.media_type||"").toLowerCase();return e==="story"||e==="moment"?!0:String(t.body||"").includes("__story__|")}isSpark(t){if(!t||this.isMoment(t))return!1;let e=String(t.media_type||"").toLowerCase();if(e==="reel"||e==="spark")return!0;let s=String(t.media_url||"").trim();if(s.startsWith("{")||s.startsWith("["))try{let n=JSON.parse(s),i=n?.reel??n?.spark;return i===!0||i==="true"||i===1||i==="1"}catch{return!1}return!1}isMomentActive(t){if(!this.isMoment(t))return!1;let s=String(t.body||"").match(/__story__\|expires=([^\s|]+)/i);if(!s?.[1])return!0;let n=Date.parse(s[1]);return Number.isFinite(n)?n>Date.now():!0}async listActiveMoments(t=40,e){let s=(e?.followingIds??[]).filter(Boolean).slice(0,8),n=await Promise.all([e?.authorId?this.listForAuthor(e.authorId,24).catch(()=>[]):Promise.resolve([]),...s.map(r=>this.listForAuthor(r,10).catch(()=>[]))]),i=new Set,a=[];for(let r of n)for(let o of r)!o?.id||i.has(o.id)||this.isMomentActive(o)&&(i.add(o.id),a.push(o));return a.sort((r,o)=>{let u=Date.parse(r.created_at||"")||0;return(Date.parse(o.created_at||"")||0)-u}),a.slice(0,Math.max(1,t))}async loadHomeFeed(t){let e=t?.maxPosts??50,s=(t?.followingIds??[]).filter(Boolean).slice(0,6),n=await Promise.all([this.listRecent(40).catch(()=>[]),t?.countryCode?this.listByCountry(t.countryCode,24,{demoLimit:12,skipComments:!0}).catch(()=>[]):Promise.resolve([]),t?.authorId?this.withTimeout(this.listForAuthor(t.authorId,12),5e3,"feedAuthor").catch(()=>[]):Promise.resolve([]),...s.map(r=>this.withTimeout(this.listForAuthor(r,3),4e3,"feedFollowing").catch(()=>[]))]),i=new Set,a=[];for(let r of n)for(let o of r)!o?.id||i.has(o.id)||this.isMoment(o)||this.isSpark(o)||(i.add(o.id),a.push(o));return a.sort((r,o)=>{let u=Date.parse(r.created_at||"")||0;return(Date.parse(o.created_at||"")||0)-u}),a.slice(0,e)}async listForAuthor(t,e=25){if(!t)return[];if(d.useDemoDataset&&/^user_/.test(t))return this.demoData.listForAuthor(t,e);let s=`
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
    `;try{let{postsByAuthor:n}=await this.withTimeout(this.gql.request(s,{authorId:t,limit:Math.max(1,Math.min(60,e||25))}),8e3,"postsByAuthor");return(n??[]).map(i=>this.mapPost(i))}catch{return[]}}async searchPosts(t,e=25){let s=String(t||"").trim();if(!s)return[];let n=`
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
    `;try{let{searchPosts:i}=await this.gql.request(n,{query:s,limit:e});return(i??[]).map(a=>this.mapPost(a))}catch{return[]}}async getPostById(t){if(!t)return null;if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.getPostById(t);let e=`
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
    `,s={title:t.title?.trim()||null,body:t.body.trim(),country_name:t.countryName,country_code:t.countryCode,city_name:t.cityName??null,visibility:t.visibility??null,media_type:t.mediaType??null,media_url:t.mediaUrl??null,thumb_url:t.thumbUrl??null,shared_post_id:t.sharedPostId??null},{createPost:n}=await this.gql.request(e,{input:s}),i=this.mapPost(n);return this.postEvents.emit(i),i}async updatePost(t,e){let s=`
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
    `,n={title:e.title?.trim()??null,body:e.body?.trim()??null,visibility:e.visibility??null},{updatePost:i}=await this.gql.request(s,{postId:t,input:n}),a=this.mapPost(i);return this.postEvents.emitUpdated(a),a}async deletePost(t,e){let s=`
      mutation DeletePost($postId: ID!) {
        deletePost(post_id: $postId)
      }
    `,{deletePost:n}=await this.gql.request(s,{postId:t});return n&&this.postEvents.emitDeleted({id:t,country_code:e?.country_code??null,author_id:e?.author_id??null}),n}async likePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.likePost(t);return this.postEvents.emitUpdated(i),i}let e=`
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
    `,{likePost:s}=await this.gql.request(e,{postId:t}),n=this.mapPost(s);return this.postEvents.emitUpdated(n),n}async unlikePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.unlikePost(t);return this.postEvents.emitUpdated(i),i}let e=`
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
    `,{unlikePost:s}=await this.gql.request(e,{postId:t}),n=this.mapPost(s);return this.postEvents.emitUpdated(n),n}async recordView(t){if(t?.id){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t.id)){await this.demoData.recordView(t.id);return}t.view_count=Number(t.view_count??0)+1}}async savePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.savePost(t);return this.postEvents.emitUpdated(i),i}let e=`
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
    `,{savePost:s}=await this.gql.request(e,{postId:t}),n=this.mapPost(s);return this.postEvents.emitUpdated(n),n}async unsavePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.unsavePost(t);return this.postEvents.emitUpdated(i),i}let e=`
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
    `,{unsavePost:s}=await this.gql.request(e,{postId:t}),n=this.mapPost(s);return this.postEvents.emitUpdated(n),n}async listComments(t,e=25,s){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let a=Math.max(e,1e3);return this.demoData.listComments(t,a)}let n=`
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
    `,{commentsByPost:i}=await this.gql.request(n,{postId:t,limit:e,before:s??null});return(i??[]).map(a=>this.mapComment(a))}async listLikes(t,e=25){if(!t)return[];if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.listLikes(t,e);let s=`
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
    `,{postLikes:n}=await this.gql.request(s,{postId:t,limit:e});return(n??[]).map(i=>this.mapLike(i))}async addComment(t,e,s){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.addComment(t,e,s??null);let n=`
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
    `,{addComment:i}=await this.gql.request(n,{postId:t,body:e.trim(),parentId:s??null});return this.mapComment(i)}async likeComment(t){if(d.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.likeComment(t);let e=`
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
    `,{reportPost:n}=await this.gql.request(s,{postId:t,reason:e.trim()});return!!n}stripMomentMarkers(t){return String(t??"").split(`
`).filter(e=>{let s=e.trim();return s?!(/__story__/i.test(s)||/\bstory\b/i.test(s)&&/\bexpir/i.test(s)):!0}).join(`
`).replace(/\n{3,}/g,`

`).trim()}mapPost(t,e=0){let s=t?.view_count!=null?Number(t.view_count):this.estimateViewCount(t?.id,t?.like_count,t?.comment_count),n=t?.shared_post&&e<1?this.mapPost(t.shared_post,e+1):null;return{id:t.id,title:t.title??null,body:this.stripMomentMarkers(t.body??""),media_type:t.media_type??"none",media_url:t.media_url??null,thumb_url:t.thumb_url??null,media_caption:t.media_caption??null,shared_post_id:t.shared_post_id??null,shared_post:n,visibility:t.visibility??"public",like_count:Number(t.like_count??0),comment_count:Number(t.comment_count??0),view_count:s,liked_by_me:!!t.liked_by_me,saved_by_me:!!t.saved_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author_id:t.author_id,country_name:t.country_name??null,country_code:t.country_code??null,city_name:t.city_name??null,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null,external_ref_type:t.external_ref_type??null,external_ref_id:t.external_ref_id??null,link_url:t.link_url??null,link_title:t.link_title??null,link_source_name:t.link_source_name??null,link_published_at:t.link_published_at??null,link_image_url:t.link_image_url??null,link_snippet:t.link_snippet??null}}mapComment(t){return{id:t.id,post_id:t.post_id,parent_id:t.parent_id??null,author_id:t.author_id,body:t.body??"",like_count:Number(t.like_count??0),liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapLike(t){return{user_id:t.user_id,created_at:t.created_at,user:t.user?{user_id:t.user.user_id,display_name:t.user.display_name,username:t.user.username,avatar_url:this.resolveAvatarUrl(t.user.avatar_url,t.user.user_id,t.user.username),country_name:t.user.country_name,country_code:t.user.country_code}:null}}resolveAvatarUrl(t,e,s){return T(t,s||e)}mergePosts(t,e,s){let n=Math.max(1,s),i=[...t].filter(m=>!!m?.id).sort((m,y)=>new Date(y.created_at).getTime()-new Date(m.created_at).getTime()),a=new Set(i.map(m=>m.id)),r=[...e].filter(m=>m?.id&&!a.has(m.id)).sort((m,y)=>new Date(y.created_at).getTime()-new Date(m.created_at).getTime()),o=[],u=0,l=0;for(;o.length<n&&(u<i.length||l<r.length);){for(let m=0;m<2&&u<i.length&&o.length<n;m+=1)o.push(i[u++]);if(l<r.length&&o.length<n&&o.push(r[l++]),u>=i.length)for(;l<r.length&&o.length<n;)o.push(r[l++]);if(l>=r.length)for(;u<i.length&&o.length<n;)o.push(i[u++])}return o}estimateViewCount(t,e,s){let n=Number(e??0),i=Number(s??0);if(!n&&!i)return 0;let r=this.hashSeed(String(t||"post"))%1200,o=n*12+i*6+r;return Math.max(o,n+i)}hashSeed(t){let e=2166136261;for(let s=0;s<t.length;s++)e^=t.charCodeAt(s),e=Math.imul(e,16777619);return e>>>0}async withTimeout(t,e,s){let n=null;try{return await Promise.race([t,new Promise((i,a)=>{n=setTimeout(()=>a(new Error(`${s} timeout`)),e)})])}finally{n&&clearTimeout(n)}}static \u0275fac=function(e){return new(e||h)(b(q),b(S),b(I))};static \u0275prov=P({token:h,factory:h.\u0275fac,providedIn:"root"})};export{S as a,E as b};
