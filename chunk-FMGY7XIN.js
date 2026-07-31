import{a as A}from"./chunk-6D62BGA5.js";import{a as q}from"./chunk-FQNXSWEQ.js";import{a as L}from"./chunk-SDLIAUTV.js";import{a as d}from"./chunk-LQQHCQP3.js";import{b as k}from"./chunk-GNESUA2A.js";import{a as g,k as P,n as b}from"./chunk-JF5FM6ZL.js";var w=class y{createdPostSubject=new g;createdPost$=this.createdPostSubject.asObservable();updatedPostSubject=new g;updatedPost$=this.updatedPostSubject.asObservable();insertSubject=new g;insert$=this.insertSubject.asObservable();updateSubject=new g;update$=this.updateSubject.asObservable();deleteSubject=new g;delete$=this.deleteSubject.asObservable();channel=k.channel("public:posts");constructor(){this.channel.on("postgres_changes",{event:"INSERT",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.insertSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.updateSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null,visibility:t.visibility??null})}).on("postgres_changes",{event:"DELETE",schema:"public",table:"posts"},({old:t})=>{t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).subscribe()}emit(t){this.createdPostSubject.next(t)}emitUpdated(t){this.updatedPostSubject.next(t)}emitDeleted(t){t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}ngOnDestroy(){this.channel?.unsubscribe()}static \u0275fac=function(e){return new(e||y)};static \u0275prov=P({token:y,factory:y.\u0275fac,providedIn:"root"})};var E="demo_social_dataset_30k/posts.jsonl",j="demo_social_dataset_30k/comments.jsonl",R="demo_social_dataset_30k/video_captions.jsonl";function D(y){let t=y>>>0;return()=>{t|=0,t=t+1831565813|0;let e=Math.imul(t^t>>>15,1|t);return e=e+Math.imul(e^e>>>7,61|e)^e,((e^e>>>14)>>>0)/4294967296}}function S(y){let t=2166136261;for(let e=0;e<y.length;e++)t^=y.charCodeAt(e),t=Math.imul(t,16777619);return t>>>0}function $(y){let t=[],e=y.split(/\r?\n/);for(let s of e){let n=s.trim();if(n)try{t.push(JSON.parse(n))}catch{}}return t}var M=class y{constructor(t){this.fakeData=t}postsLoaded=!1;postsPromise=null;commentsLoaded=!1;commentsPromise=null;captionsLoaded=!1;captionsPromise=null;posts=[];postsById=new Map;postsByCountry=new Map;postsByAuthor=new Map;postStates=new Map;countryFeedCache=new Map;postSearchCache=new Map;postMediaMeta=new Map;captionsByPost=new Map;commentsByPost=new Map;localCommentsByPost=new Map;commentStates=new Map;commentOrderCache=new Map;profileMap=null;countryOffsets=new Map;pexelsCache=new Map;pexelsInflight=new Map;async isDemoPostId(t){return await this.ensurePostsLoaded(),this.postsById.has(t)}isDemoCommentId(t){return/^cmt_|^local_/.test(t)}async listByCountry(t,e=25,s){s?.skipComments?await this.ensurePostsLoaded():await this.ensureCommentsLoaded();let n=String(t||"").trim().toUpperCase(),o=this.postsByCountry.get(n)??[],i=this.buildBalancedOrder(o,n),r=Math.max(1,e),a=this.sliceWithOffset(n,i,r);return await this.hydrateMedia(a),a}async listForAuthor(t,e=25){await this.ensureCommentsLoaded();let o=[...this.postsByAuthor.get(t)??[]].sort((i,r)=>new Date(r.created_at).getTime()-new Date(i.created_at).getTime()).slice(0,Math.max(1,e));return await this.hydrateMedia(o),o}async sampleGlobalPosts(t=4e3){await this.ensurePostsLoaded();let e=Math.max(1,Math.min(t,this.posts.length||t)),s=this.posts.slice(0,e);return await this.hydrateMedia(s.slice(0,Math.min(40,s.length))),s}async getPostById(t){await this.ensureCommentsLoaded();let e=this.postsById.get(t)??null;return e?(await this.hydrateMedia([e]),e):null}async searchPosts(t,e=20){let s=String(t||"").trim().toLowerCase();if(!s)return[];await this.ensurePostsLoaded();let n=this.postSearchCache.get(s);if(n){if(e<=0)return n;let a=n.slice(0,Math.max(1,e));return await this.hydrateMedia(a),a}let i=this.posts.filter(a=>{let u=String(a.title||"").toLowerCase(),l=String(a.body||"").toLowerCase(),_=String(a.media_caption||"").toLowerCase();return u.includes(s)||l.includes(s)||_.includes(s)}).sort((a,u)=>new Date(u.created_at).getTime()-new Date(a.created_at).getTime());if(this.postSearchCache.set(s,i),this.postSearchCache.size>40){let a=this.postSearchCache.keys().next().value;a&&this.postSearchCache.delete(a)}if(e<=0)return i;let r=i.slice(0,Math.max(1,e));return await this.hydrateMedia(r),r}async listComments(t,e=25){await this.ensureCommentsLoaded();let s=this.getOrderedComments(t),n=this.localCommentsByPost.get(t)??[];return[...s,...n].slice(0,Math.max(1,e))}async addComment(t,e,s){await this.ensurePostsLoaded();let o=(await k.auth.getUser()).data.user?.id??"me",i=new Date().toISOString(),r={user_id:o,display_name:"You",username:null,avatar_url:null,country_name:null,country_code:null},a={id:`local_${Date.now()}_${Math.floor(Math.random()*1e4)}`,post_id:t,parent_id:s??null,author_id:o,body:e.trim(),like_count:0,liked_by_me:!1,created_at:i,updated_at:i,author:r},u=this.localCommentsByPost.get(t)??[];u.push(a),this.localCommentsByPost.set(t,u);let l=this.postStates.get(t);if(l){l.comment_count+=1;let _=this.postsById.get(t);_&&(_.comment_count=l.comment_count)}return a}async likePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.liked_by_me||(s.liked_by_me=!0,s.like_count+=1),this.applyState(e,s),e}async unlikePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.liked_by_me&&(s.liked_by_me=!1,s.like_count=Math.max(0,s.like_count-1)),this.applyState(e,s),e}async recordView(t){if(!t)return;await this.ensurePostsLoaded();let e=this.ensurePostState(t);e.view_count+=1;let s=this.postsById.get(t);s&&this.applyState(s,e)}async listLikes(t,e=25){await this.ensurePostsLoaded();let s=this.postStates.get(t),n=Math.max(0,Math.min(e,s?.like_count??0));if(!n)return[];let o=await this.fakeData.getProfiles();if(!o.length)return[];let i=D(S(`${t}|likes`)),r=new Set;for(;r.size<n&&r.size<o.length;)r.add(Math.floor(i()*o.length));let a=new Date().toISOString();return[...r].map(u=>{let l=o[u];return{user_id:l.user_id,created_at:a,user:this.profileToAuthor(l)}})}async likeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let s=this.ensureCommentState(t,e);return s.liked_by_me||(s.liked_by_me=!0,s.like_count+=1),e.liked_by_me=s.liked_by_me,e.like_count=s.like_count,e}async unlikeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let s=this.ensureCommentState(t,e);return s.liked_by_me&&(s.liked_by_me=!1,s.like_count=Math.max(0,s.like_count-1)),e.liked_by_me=s.liked_by_me,e.like_count=s.like_count,e}async ensurePostsLoaded(){if(!this.postsLoaded)return this.postsPromise?this.postsPromise:(this.postsPromise=(async()=>{await this.ensureCaptionsLoaded();let t=await this.fetchText(E),s=$(t).slice(0,4e3),n=new Set;for(let o of s){let i=this.normalizeAuthorId(o?.author_id);i&&n.add(i)}await this.ensureProfileMap(n);for(let o of s){let i=this.normalizeAuthorId(o?.author_id);if(!o?.id||!i)continue;let r=this.profileMap?.get(i)??null,a=o.media?.type??"none",u=o.media?.url??null,l=o.media?.thumb_url??null,_=this.captionsByPost.get(o.id)??null,p=r?.country_code??o.country_code??null,m=r?.country_name??o.country_name??null,h=o.created_at||new Date().toISOString(),c={id:o.id,title:o.title??null,body:this.normalizeBody(o.body??"",m||o.country_name||null),media_type:a,media_url:u,thumb_url:l,media_caption:_,visibility:o.visibility||"public",like_count:0,comment_count:0,view_count:0,liked_by_me:!1,created_at:h,updated_at:h,author_id:i,country_name:m,country_code:p,city_name:null,author:r},v=this.seedCount(o.id,8e3),I=this.seedCount(`${o.id}|views`,18e4),f={like_count:v,comment_count:0,view_count:Math.max(I,v*6),liked_by_me:!1};this.postStates.set(o.id,f),this.applyState(c,f),this.posts.push(c),this.postsById.set(o.id,c);let C=String(p||"").trim().toUpperCase();if(C){let B=this.postsByCountry.get(C)??[];B.push(c),this.postsByCountry.set(C,B)}let x=this.postsByAuthor.get(i)??[];x.push(c),this.postsByAuthor.set(i,x),this.postMediaMeta.set(o.id,{type:a,query:o.media?.query??null,url:u,thumb_url:l})}this.postsLoaded=!0})(),this.postsPromise)}async ensureCommentsLoaded(){if(!this.commentsLoaded)return this.commentsPromise?this.commentsPromise:(this.commentsPromise=(async()=>{await this.ensurePostsLoaded();let t=await this.fetchText(j),e=$(t),s=new Set;for(let n of e){let o=this.normalizeAuthorId(n?.author_id);o&&s.add(o)}await this.ensureProfileMap(s);for(let n of e){let o=this.normalizeAuthorId(n?.author_id);if(!n?.id||!n?.post_id||!o)continue;let i=this.profileMap?.get(o)??null,r=n.created_at||new Date().toISOString(),a={id:n.id,post_id:n.post_id,parent_id:n.parent_id??null,author_id:o,body:n.body??"",like_count:this.seedCount(n.id,160),liked_by_me:!1,created_at:r,updated_at:r,author:i},u=this.commentsByPost.get(n.post_id)??[];u.push(a),this.commentsByPost.set(n.post_id,u),this.commentStates.set(n.id,{like_count:a.like_count,liked_by_me:!1});let l=this.postStates.get(n.post_id);l&&(l.comment_count+=1)}for(let[n,o]of this.postStates.entries()){let i=this.postsById.get(n);i&&(i.comment_count=o.comment_count)}this.commentsLoaded=!0})(),this.commentsPromise)}async ensureCaptionsLoaded(){if(!this.captionsLoaded)return this.captionsPromise?this.captionsPromise:(this.captionsPromise=(async()=>{let t=await this.fetchText(R),e=$(t);for(let s of e)!s?.post_id||!s?.caption||this.captionsByPost.set(s.post_id,s.caption);this.captionsLoaded=!0})(),this.captionsPromise)}async ensureProfileMap(t){if(!this.profileMap){let e=await this.fakeData.getProfiles(),s=new Map;for(let n of e)s.set(n.user_id,this.profileToAuthor(n));this.profileMap=s}if(t&&t.size){await this.fakeData.ensureProfilesById(t);for(let e of t){if(this.profileMap?.has(e))continue;let s=await this.fakeData.getProfileById(e);s&&this.profileMap?.set(e,this.profileToAuthor(s))}}}profileToAuthor(t){return{user_id:t.user_id,display_name:t.display_name??null,username:t.username??null,avatar_url:t.avatar_url??null,country_name:t.country_name??null,country_code:t.country_code??null}}applyState(t,e){t.like_count=e.like_count,t.comment_count=e.comment_count,t.view_count=e.view_count,t.liked_by_me=e.liked_by_me}ensurePostState(t){let e=this.postStates.get(t);return e||(e={like_count:0,comment_count:0,view_count:0,liked_by_me:!1},this.postStates.set(t,e)),e}ensureCommentState(t,e){let s=this.commentStates.get(t);return s||(s={like_count:e.like_count,liked_by_me:e.liked_by_me},this.commentStates.set(t,s)),s}findComment(t){for(let e of this.commentsByPost.values()){let s=e.find(n=>n.id===t);if(s)return s}for(let e of this.localCommentsByPost.values()){let s=e.find(n=>n.id===t);if(s)return s}return null}seedCount(t,e){let s=D(S(t));return Math.floor(Math.pow(s(),2)*e)}buildBalancedOrder(t,e){let s=Date.now(),n=Math.floor(s/(1e3*60*15)),o=`${e}:${n}`,i=this.countryFeedCache.get(o);if(i)return i.posts;let r=[...t].sort((m,h)=>new Date(h.created_at).getTime()-new Date(m.created_at).getTime()),a=new Map;for(let m of r){let h=a.get(m.author_id)??[];h.push(m),a.set(m.author_id,h)}let u=Array.from(a.keys()),l=D(S(`${e}|${n}`));for(let m=u.length-1;m>0;m-=1){let h=Math.floor(l()*(m+1)),c=u[m];u[m]=u[h],u[h]=c}let _=[],p=!0;for(;p;){p=!1;for(let m of u){let h=a.get(m);!h||!h.length||(_.push(h.shift()),p=!0)}}return this.countryFeedCache.set(o,{ts:s,posts:_}),_}sliceWithOffset(t,e,s){if(!e.length)return[];if(e.length<=s)return[...e];let o=(this.countryOffsets.get(t)??0)%e.length,i=o+s,r=(o+s)%e.length;if(this.countryOffsets.set(t,r),i<=e.length)return e.slice(o,i);let a=e.slice(o),u=e.slice(0,i-e.length);return[...a,...u]}normalizeBody(t,e){let s=String(t||"").trim();if(!s)return"";let n=s,o=/^in\s+[A-Za-z][^,.:;-]{1,60}[,.:;-]\s*/i;if(n=n.replace(o,"").trim(),!n||!e)return n;let i=e.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),r=new RegExp(`^In\\s+${i}\\b[\\s,.-]*`,"i");return n.replace(r,"").trim()}getOrderedComments(t){let e=this.commentOrderCache.get(t);if(e)return e;let s=this.commentsByPost.get(t)??[];if(!s.length)return this.commentOrderCache.set(t,[]),[];let n=[],o=new Set;for(let r of s){let a=`${r.author_id}|${this.normalizeCommentBody(r.body)}`;o.has(a)||(o.add(a),n.push(r))}let i=D(S(`${t}|comments`));for(let r=n.length-1;r>0;r-=1){let a=Math.floor(i()*(r+1)),u=n[r];n[r]=n[a],n[a]=u}return this.commentOrderCache.set(t,n),n}normalizeCommentBody(t){return String(t||"").trim().toLowerCase().replace(/\s+/g," ")}normalizeAuthorId(t){let e=String(t||"").trim();if(!e)return null;let s=e.match(/^user_(\d+)$/i);if(!s)return e;let n=parseInt(s[1],10);return!Number.isFinite(n)||n<=0?e:`user_${String(n).padStart(6,"0")}`}resolveAssetUrl(t){let e=document.querySelector("base")?.getAttribute("href")??"/",s=new URL(e,window.location.origin).toString();return new URL(t,s).toString()}async fetchText(t){if(typeof window>"u"||typeof document>"u")return"";let e=this.resolveAssetUrl(t),s=await fetch(e);if(!s.ok)throw new Error(`Failed to load ${t}: ${s.status}`);return s.text()}async hydrateMedia(t){if(!d.pexelsApiKey)return;let e=t.map(async s=>{if(!s||s.media_type==="none"||s.media_url)return;let n=this.postMediaMeta.get(s.id);if(!n||!n.query)return;let o=`${n.type}:${n.query}`.toLowerCase(),i=this.pexelsCache.get(o);if(i){s.media_url=i.url,s.thumb_url=i.thumb_url;return}let r=this.pexelsInflight.get(o);if(r){let l=await r;s.media_url=l.url,s.thumb_url=l.thumb_url;return}let a=this.fetchPexels(n.type,n.query);this.pexelsInflight.set(o,a);let u=await a;this.pexelsInflight.delete(o),this.pexelsCache.set(o,u),s.media_url=u.url,s.thumb_url=u.thumb_url});await Promise.all(e)}async fetchPexels(t,e){let s=d.pexelsApiKey||"";if(!s)return{url:null,thumb_url:null};let n={Authorization:s};if(t==="video"){let l=`https://api.pexels.com/videos/search?query=${encodeURIComponent(e)}&per_page=1`,_=await fetch(l,{headers:n});if(!_.ok)return{url:null,thumb_url:null};let m=(await _.json())?.videos?.[0];if(!m)return{url:null,thumb_url:null};let c=(Array.isArray(m.video_files)?m.video_files:[]).filter(f=>String(f?.file_type||"").toLowerCase()==="video/mp4").sort((f,C)=>(f?.width??0)-(C?.width??0)),v=c.find(f=>(f?.width??0)>=720)||c[0],I=m.video_pictures?.[0]?.picture||m.image||null;return{url:v?.link??null,thumb_url:I}}let o=`https://api.pexels.com/v1/search?query=${encodeURIComponent(e)}&per_page=1`,i=await fetch(o,{headers:n});if(!i.ok)return{url:null,thumb_url:null};let u=(await i.json())?.photos?.[0]?.src||{};return{url:u?.large??u?.medium??null,thumb_url:u?.medium??null}}static \u0275fac=function(e){return new(e||y)(b(q))};static \u0275prov=P({token:y,factory:y.\u0275fac,providedIn:"root"})};var O=class y{constructor(t,e,s){this.gql=t;this.postEvents=e;this.demoData=s}async listByCountry(t,e=25,s){let n=Math.max(1,Math.min(80,e||25)),o=`
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
    `;try{let{postsByCountry:i}=await this.withTimeout(this.gql.request(o,{code:t,limit:n}),8e3,"postsByCountry"),r=(i??[]).map(l=>this.mapPost(l)).filter(l=>!this.isMoment(l));if(!d.useDemoDataset)return r;let a=Math.min(s?.demoLimit??n,40),u=await this.withTimeout(this.demoData.listByCountry(t,a,{skipComments:s?.skipComments??!0}),2500,"demoPostsByCountry").catch(()=>[]);return this.mergePosts(r,u,n)}catch{if(!d.useDemoDataset)return[];try{return await this.withTimeout(this.demoData.listByCountry(t,Math.min(n,20),{skipComments:!0}),2500,"demoPostsByCountryFallback")}catch{return[]}}}async listRecentNetworkOnly(t=40,e){let s=`
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
    `,n=Math.max(1,Math.min(80,t||40));try{let{recentPosts:o}=await this.withTimeout(this.gql.request(s,{limit:n,before:e??null}),8e3,"recentPosts");return(o??[]).map(i=>this.mapPost(i)).filter(i=>!this.isMoment(i))}catch{return[]}}async listRecent(t=40,e){let s=Math.max(1,Math.min(80,t||40)),n=(await this.listRecentNetworkOnly(s,e)).filter(o=>!this.isSpark(o));if(!d.useDemoDataset||e)return n;try{let i=(await this.withTimeout(this.demoData.sampleGlobalPosts(Math.max(s*4,80)),12e3,"demoRecent").catch(()=>[])||[]).filter(r=>!this.isMoment(r)&&!this.isSpark(r));return this.mergePosts(n,i,Math.max(s,50))}catch{return n}}isMoment(t){if(!t)return!1;let e=String(t.media_type||"").toLowerCase();return e==="story"||e==="moment"?!0:String(t.body||"").includes("__story__|")}isSpark(t){if(!t||this.isMoment(t))return!1;let e=String(t.media_type||"").toLowerCase();if(e==="reel"||e==="spark")return!0;let s=String(t.media_url||"").trim();if(s.startsWith("{")||s.startsWith("["))try{let n=JSON.parse(s),o=n?.reel??n?.spark;return o===!0||o==="true"||o===1||o==="1"}catch{return!1}return!1}isMomentActive(t){if(!this.isMoment(t))return!1;let s=String(t.body||"").match(/__story__\|expires=([^\s|]+)/i);if(!s?.[1])return!0;let n=Date.parse(s[1]);return Number.isFinite(n)?n>Date.now():!0}async listActiveMoments(t=40,e){let s=(e?.followingIds??[]).filter(Boolean).slice(0,8),n=await Promise.all([e?.authorId?this.listForAuthor(e.authorId,24).catch(()=>[]):Promise.resolve([]),...s.map(r=>this.listForAuthor(r,10).catch(()=>[]))]),o=new Set,i=[];for(let r of n)for(let a of r)!a?.id||o.has(a.id)||this.isMomentActive(a)&&(o.add(a.id),i.push(a));return i.sort((r,a)=>{let u=Date.parse(r.created_at||"")||0;return(Date.parse(a.created_at||"")||0)-u}),i.slice(0,Math.max(1,t))}async loadHomeFeed(t){let e=t?.maxPosts??(d.useDemoDataset?200:50),s=(t?.followingIds??[]).filter(Boolean).slice(0,6),[n,o,i,...r]=await Promise.all([this.listRecent(40).catch(()=>[]),t?.countryCode?this.listByCountry(t.countryCode,40,{demoLimit:40,skipComments:!0}).catch(()=>[]):Promise.resolve([]),t?.authorId?this.withTimeout(this.listForAuthor(t.authorId,12),5e3,"feedAuthor").catch(()=>[]):Promise.resolve([]),...s.map(m=>this.withTimeout(this.listForAuthor(m,3),4e3,"feedFollowing").catch(()=>[]))]),a=m=>String(m.id||"").startsWith("post_")||String(m.id||"").startsWith("demo_")||String(m.author_id||"").startsWith("user_"),u=new Set,l=[],_=[],p=(m,h=!1)=>{for(let c of m||[])!c?.id||u.has(c.id)||this.isMoment(c)||this.isSpark(c)||(u.add(c.id),h||a(c)?_.push(c):l.push(c))};p(n),p(o),p(i);for(let m of r)p(m);if(d.useDemoDataset&&_.length+l.length<e){let m=await this.demoData.sampleGlobalPosts(Math.min(4e3,e)).catch(()=>[]);p(m,!0)}return l.sort((m,h)=>{let c=Date.parse(m.created_at||"")||0;return(Date.parse(h.created_at||"")||0)-c}),[...l,..._].slice(0,e)}async listForAuthor(t,e=25){if(!t)return[];if(d.useDemoDataset&&/^user_/.test(t))return this.demoData.listForAuthor(t,e);let s=`
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
    `;try{let{postsByAuthor:n}=await this.withTimeout(this.gql.request(s,{authorId:t,limit:Math.max(1,Math.min(60,e||25))}),8e3,"postsByAuthor");return(n??[]).map(o=>this.mapPost(o))}catch{return[]}}async searchPosts(t,e=25){let s=String(t||"").trim();if(!s)return[];let n=`
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
    `,o=[];try{let{searchPosts:i}=await this.gql.request(n,{query:s,limit:e});o=(i??[]).map(r=>this.mapPost(r))}catch{o=[]}if(!d.useDemoDataset)return o;try{let i=await this.demoData.searchPosts(s,e);return this.mergePosts(o,i,Math.max(1,e))}catch{return o}}async getPostById(t){if(!t)return null;if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.getPostById(t);let e=`
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
    `,s={title:t.title?.trim()||null,body:t.body.trim(),country_name:t.countryName,country_code:t.countryCode,city_name:t.cityName??null,visibility:t.visibility??null,media_type:t.mediaType??null,media_url:t.mediaUrl??null,thumb_url:t.thumbUrl??null,shared_post_id:t.sharedPostId??null},{createPost:n}=await this.gql.request(e,{input:s}),o=this.mapPost(n);return this.postEvents.emit(o),o}async updatePost(t,e){let s=`
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
    `,n={title:e.title?.trim()??null,body:e.body?.trim()??null,visibility:e.visibility??null},{updatePost:o}=await this.gql.request(s,{postId:t,input:n}),i=this.mapPost(o);return this.postEvents.emitUpdated(i),i}async deletePost(t,e){let s=`
      mutation DeletePost($postId: ID!) {
        deletePost(post_id: $postId)
      }
    `,{deletePost:n}=await this.gql.request(s,{postId:t});return n&&this.postEvents.emitDeleted({id:t,country_code:e?.country_code??null,author_id:e?.author_id??null}),n}async likePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let o=await this.demoData.likePost(t);return this.postEvents.emitUpdated(o),o}let e=`
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
    `,{likePost:s}=await this.gql.request(e,{postId:t}),n=this.mapPost(s);return this.postEvents.emitUpdated(n),n}async unlikePost(t){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let o=await this.demoData.unlikePost(t);return this.postEvents.emitUpdated(o),o}let e=`
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
    `,{unlikePost:s}=await this.gql.request(e,{postId:t}),n=this.mapPost(s);return this.postEvents.emitUpdated(n),n}async recordView(t){if(t?.id){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t.id)){await this.demoData.recordView(t.id);return}t.view_count=Number(t.view_count??0)+1}}async listComments(t,e=25,s){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=Math.max(e,1e3);return this.demoData.listComments(t,i)}let n=`
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
    `,{commentsByPost:o}=await this.gql.request(n,{postId:t,limit:e,before:s??null});return(o??[]).map(i=>this.mapComment(i))}async listLikes(t,e=25){if(!t)return[];if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.listLikes(t,e);let s=`
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
    `,{postLikes:n}=await this.gql.request(s,{postId:t,limit:e});return(n??[]).map(o=>this.mapLike(o))}async addComment(t,e,s){if(d.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.addComment(t,e,s??null);let n=`
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
    `,{addComment:o}=await this.gql.request(n,{postId:t,body:e.trim(),parentId:s??null});return this.mapComment(o)}async likeComment(t){if(d.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.likeComment(t);let e=`
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

`).trim()}mapPost(t,e=0){let s=t?.view_count!=null?Number(t.view_count):this.estimateViewCount(t?.id,t?.like_count,t?.comment_count),n=t?.shared_post&&e<1?this.mapPost(t.shared_post,e+1):null;return{id:t.id,title:t.title??null,body:this.stripMomentMarkers(t.body??""),media_type:t.media_type??"none",media_url:t.media_url??null,thumb_url:t.thumb_url??null,media_caption:t.media_caption??null,shared_post_id:t.shared_post_id??null,shared_post:n,visibility:t.visibility??"public",like_count:Number(t.like_count??0),comment_count:Number(t.comment_count??0),view_count:s,liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author_id:t.author_id,country_name:t.country_name??null,country_code:t.country_code??null,city_name:t.city_name??null,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null,external_ref_type:t.external_ref_type??null,external_ref_id:t.external_ref_id??null,link_url:t.link_url??null,link_title:t.link_title??null,link_source_name:t.link_source_name??null,link_published_at:t.link_published_at??null,link_image_url:t.link_image_url??null,link_snippet:t.link_snippet??null}}mapComment(t){return{id:t.id,post_id:t.post_id,parent_id:t.parent_id??null,author_id:t.author_id,body:t.body??"",like_count:Number(t.like_count??0),liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapLike(t){return{user_id:t.user_id,created_at:t.created_at,user:t.user?{user_id:t.user.user_id,display_name:t.user.display_name,username:t.user.username,avatar_url:this.resolveAvatarUrl(t.user.avatar_url,t.user.user_id,t.user.username),country_name:t.user.country_name,country_code:t.user.country_code}:null}}resolveAvatarUrl(t,e,s){return A(t,s||e)}mergePosts(t,e,s){let n=[...t,...e],o=new Set,i=[];for(let r of n)!r?.id||o.has(r.id)||(o.add(r.id),i.push(r));if(t.length){let r=new Set(t.map(l=>l.id)),a=t.filter(l=>r.has(l.id)).sort((l,_)=>new Date(_.created_at).getTime()-new Date(l.created_at).getTime()),u=i.filter(l=>!r.has(l.id));return[...a,...u].slice(0,Math.max(1,s))}return i.sort((r,a)=>new Date(a.created_at).getTime()-new Date(r.created_at).getTime()).slice(0,Math.max(1,s))}estimateViewCount(t,e,s){let n=Number(e??0),o=Number(s??0);if(!n&&!o)return 0;let r=this.hashSeed(String(t||"post"))%1200,a=n*12+o*6+r;return Math.max(a,n+o)}hashSeed(t){let e=2166136261;for(let s=0;s<t.length;s++)e^=t.charCodeAt(s),e=Math.imul(e,16777619);return e>>>0}async withTimeout(t,e,s){let n=null;try{return await Promise.race([t,new Promise((o,i)=>{n=setTimeout(()=>i(new Error(`${s} timeout`)),e)})])}finally{n&&clearTimeout(n)}}static \u0275fac=function(e){return new(e||y)(b(L),b(w),b(M))};static \u0275prov=P({token:y,factory:y.\u0275fac,providedIn:"root"})};export{w as a,O as b};
