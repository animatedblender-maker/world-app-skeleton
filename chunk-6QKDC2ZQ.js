import{a as x}from"./chunk-LJDR2ADK.js";import{a as L}from"./chunk-7DJA5TI4.js";import{a as y}from"./chunk-LQQHCQP3.js";import{b as w}from"./chunk-KO5X6LCN.js";import{a as b,k as P,n as v}from"./chunk-SPQ2JWKS.js";var S=class d{createdPostSubject=new b;createdPost$=this.createdPostSubject.asObservable();updatedPostSubject=new b;updatedPost$=this.updatedPostSubject.asObservable();insertSubject=new b;insert$=this.insertSubject.asObservable();updateSubject=new b;update$=this.updateSubject.asObservable();deleteSubject=new b;delete$=this.deleteSubject.asObservable();channel=w.channel("public:posts");constructor(){this.channel.on("postgres_changes",{event:"INSERT",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.insertSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.updateSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null,visibility:t.visibility??null})}).on("postgres_changes",{event:"DELETE",schema:"public",table:"posts"},({old:t})=>{t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).subscribe()}emit(t){this.createdPostSubject.next(t)}emitUpdated(t){this.updatedPostSubject.next(t)}emitDeleted(t){t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}ngOnDestroy(){this.channel?.unsubscribe()}static \u0275fac=function(e){return new(e||d)};static \u0275prov=P({token:d,factory:d.\u0275fac,providedIn:"root"})};var E="demo_social_dataset_30k/posts.jsonl",U="demo_social_dataset_30k/comments.jsonl",O="demo_social_dataset_30k/video_captions.jsonl",j="https://hacker-news.firebaseio.com/v0/topstories.json",N=d=>`https://hacker-news.firebaseio.com/v0/item/${d}.json`,R="https://api.pushshift.io/reddit/comment/search/?q=ai&size=1000";function D(d){let t=d>>>0;return()=>{t|=0,t=t+1831565813|0;let e=Math.imul(t^t>>>15,1|t);return e=e+Math.imul(e^e>>>7,61|e)^e,((e^e>>>14)>>>0)/4294967296}}function g(d){let t=2166136261;for(let e=0;e<d.length;e++)t^=d.charCodeAt(e),t=Math.imul(t,16777619);return t>>>0}function B(d){let t=[],e=d.split(/\r?\n/);for(let s of e){let n=s.trim();if(n)try{t.push(JSON.parse(n))}catch{}}return t}var I=class d{constructor(t){this.fakeData=t}postsLoaded=!1;postsPromise=null;commentsLoaded=!1;commentsPromise=null;captionsLoaded=!1;captionsPromise=null;posts=[];postsById=new Map;postsByCountry=new Map;postsByAuthor=new Map;postStates=new Map;countryFeedCache=new Map;postSearchCache=new Map;postMediaMeta=new Map;captionsByPost=new Map;commentsByPost=new Map;localCommentsByPost=new Map;commentStates=new Map;commentOrderCache=new Map;profileMap=null;countryOffsets=new Map;pexelsCache=new Map;pexelsInflight=new Map;usingHackerNews=!1;async isDemoPostId(t){return await this.ensurePostsLoaded(),this.postsById.has(t)}isDemoCommentId(t){return/^cmt_|^local_/.test(t)}async listByCountry(t,e=25,s){s?.skipComments?await this.ensurePostsLoaded():await this.ensureCommentsLoaded();let n=String(t||"").trim().toUpperCase(),i=this.postsByCountry.get(n)??[],o=this.buildBalancedOrder(i,n),r=Math.max(1,e),a=this.sliceWithOffset(n,o,r);return await this.hydrateMedia(a),a}async listForAuthor(t,e=25){await this.ensureCommentsLoaded();let i=[...this.postsByAuthor.get(t)??[]].sort((o,r)=>new Date(r.created_at).getTime()-new Date(o.created_at).getTime()).slice(0,Math.max(1,e));return await this.hydrateMedia(i),i}async getPostById(t){await this.ensureCommentsLoaded();let e=this.postsById.get(t)??null;return e?(await this.hydrateMedia([e]),e):null}async searchPosts(t,e=20){let s=String(t||"").trim().toLowerCase();if(!s)return[];await this.ensurePostsLoaded();let n=this.postSearchCache.get(s);if(n){if(e<=0)return n;let a=n.slice(0,Math.max(1,e));return await this.hydrateMedia(a),a}let o=this.posts.filter(a=>{let u=String(a.title||"").toLowerCase(),l=String(a.body||"").toLowerCase(),m=String(a.media_caption||"").toLowerCase();return u.includes(s)||l.includes(s)||m.includes(s)}).sort((a,u)=>new Date(u.created_at).getTime()-new Date(a.created_at).getTime());if(this.postSearchCache.set(s,o),this.postSearchCache.size>40){let a=this.postSearchCache.keys().next().value;a&&this.postSearchCache.delete(a)}if(e<=0)return o;let r=o.slice(0,Math.max(1,e));return await this.hydrateMedia(r),r}async listComments(t,e=25){await this.ensureCommentsLoaded();let s=this.getOrderedComments(t),n=this.localCommentsByPost.get(t)??[];return[...s,...n].slice(0,Math.max(1,e))}async addComment(t,e,s){await this.ensurePostsLoaded();let i=(await w.auth.getUser()).data.user?.id??"me",o=new Date().toISOString(),r={user_id:i,display_name:"You",username:null,avatar_url:null,country_name:null,country_code:null},a={id:`local_${Date.now()}_${Math.floor(Math.random()*1e4)}`,post_id:t,parent_id:s??null,author_id:i,body:e.trim(),like_count:0,liked_by_me:!1,created_at:o,updated_at:o,author:r},u=this.localCommentsByPost.get(t)??[];u.push(a),this.localCommentsByPost.set(t,u);let l=this.postStates.get(t);if(l){l.comment_count+=1;let m=this.postsById.get(t);m&&(m.comment_count=l.comment_count)}return a}async likePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.liked_by_me||(s.liked_by_me=!0,s.like_count+=1),this.applyState(e,s),e}async unlikePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let s=this.ensurePostState(t);return s.liked_by_me&&(s.liked_by_me=!1,s.like_count=Math.max(0,s.like_count-1)),this.applyState(e,s),e}async recordView(t){if(!t)return;await this.ensurePostsLoaded();let e=this.ensurePostState(t);e.view_count+=1;let s=this.postsById.get(t);s&&this.applyState(s,e)}async listLikes(t,e=25){await this.ensurePostsLoaded();let s=this.postStates.get(t),n=Math.max(0,Math.min(e,s?.like_count??0));if(!n)return[];let i=await this.fakeData.getProfiles();if(!i.length)return[];let o=D(g(`${t}|likes`)),r=new Set;for(;r.size<n&&r.size<i.length;)r.add(Math.floor(o()*i.length));let a=new Date().toISOString();return[...r].map(u=>{let l=i[u];return{user_id:l.user_id,created_at:a,user:this.profileToAuthor(l)}})}async likeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let s=this.ensureCommentState(t,e);return s.liked_by_me||(s.liked_by_me=!0,s.like_count+=1),e.liked_by_me=s.liked_by_me,e.like_count=s.like_count,e}async unlikeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let s=this.ensureCommentState(t,e);return s.liked_by_me&&(s.liked_by_me=!1,s.like_count=Math.max(0,s.like_count-1)),e.liked_by_me=s.liked_by_me,e.like_count=s.like_count,e}async ensurePostsLoaded(){if(!this.postsLoaded)return this.postsPromise?this.postsPromise:(this.postsPromise=(async()=>{if(await this.tryLoadHackerNewsPosts()){this.postsLoaded=!0;return}await this.ensureCaptionsLoaded();let t=await this.fetchText(E),e=B(t),s=new Set;for(let n of e){let i=this.normalizeAuthorId(n?.author_id);i&&s.add(i)}await this.ensureProfileMap(s);for(let n of e){let i=this.normalizeAuthorId(n?.author_id);if(!n?.id||!i)continue;let o=this.profileMap?.get(i)??null,r=n.media?.type??"none",a=n.media?.url??null,u=n.media?.thumb_url??null,l=this.captionsByPost.get(n.id)??null,m=o?.country_code??n.country_code??null,h=o?.country_name??n.country_name??null,c=n.created_at||new Date().toISOString(),_={id:n.id,title:n.title??null,body:this.normalizeBody(n.body??"",h||n.country_name||null),media_type:r,media_url:a,thumb_url:u,media_caption:l,visibility:n.visibility||"public",like_count:0,comment_count:0,view_count:0,liked_by_me:!1,created_at:c,updated_at:c,author_id:i,country_name:h,country_code:m,city_name:null,author:o},f=this.seedCount(n.id,8e3),$=this.seedCount(`${n.id}|views`,18e4),C={like_count:f,comment_count:0,view_count:Math.max($,f*6),liked_by_me:!1};this.postStates.set(n.id,C),this.applyState(_,C),this.posts.push(_),this.postsById.set(n.id,_);let p=String(m||"").trim().toUpperCase();if(p){let M=this.postsByCountry.get(p)??[];M.push(_),this.postsByCountry.set(p,M)}let k=this.postsByAuthor.get(i)??[];k.push(_),this.postsByAuthor.set(i,k),this.postMediaMeta.set(n.id,{type:r,query:n.media?.query??null,url:a,thumb_url:u})}this.postsLoaded=!0})(),this.postsPromise)}async ensureCommentsLoaded(){if(!this.commentsLoaded)return this.commentsPromise?this.commentsPromise:(this.commentsPromise=(async()=>{if(await this.ensurePostsLoaded(),this.usingHackerNews){for(let[n,i]of this.postStates.entries()){let o=this.postsById.get(n);o&&(o.comment_count=i.comment_count)}this.commentsLoaded=!0;return}let t=await this.fetchText(U),e=B(t),s=new Set;for(let n of e){let i=this.normalizeAuthorId(n?.author_id);i&&s.add(i)}await this.ensureProfileMap(s);for(let n of e){let i=this.normalizeAuthorId(n?.author_id);if(!n?.id||!n?.post_id||!i)continue;let o=this.profileMap?.get(i)??null,r=n.created_at||new Date().toISOString(),a={id:n.id,post_id:n.post_id,parent_id:n.parent_id??null,author_id:i,body:n.body??"",like_count:this.seedCount(n.id,160),liked_by_me:!1,created_at:r,updated_at:r,author:o},u=this.commentsByPost.get(n.post_id)??[];u.push(a),this.commentsByPost.set(n.post_id,u),this.commentStates.set(n.id,{like_count:a.like_count,liked_by_me:!1});let l=this.postStates.get(n.post_id);l&&(l.comment_count+=1)}for(let[n,i]of this.postStates.entries()){let o=this.postsById.get(n);o&&(o.comment_count=i.comment_count)}this.commentsLoaded=!0})(),this.commentsPromise)}async ensureCaptionsLoaded(){if(!this.captionsLoaded)return this.captionsPromise?this.captionsPromise:(this.captionsPromise=(async()=>{let t=await this.fetchText(O),e=B(t);for(let s of e)!s?.post_id||!s?.caption||this.captionsByPost.set(s.post_id,s.caption);this.captionsLoaded=!0})(),this.captionsPromise)}async tryLoadHackerNewsPosts(){this.usingHackerNews=!1,this.resetFeedCaches();try{let t=await this.fakeData.getProfiles();return t.length?(await this.appendHackerNewsStories(t),await this.appendPushshiftComments(t),this.usingHackerNews=this.posts.length>0,this.usingHackerNews):!1}catch{return this.usingHackerNews=!1,!1}}async appendHackerNewsStories(t){try{let e=await this.fetchJson(j,5e3);if(!Array.isArray(e)||!e.length)return;let s=e.slice(0,260),i=(await this.fetchHnItems(s,14)).filter(o=>o&&o.type==="story"&&!o.deleted&&!o.dead&&!!o.title).sort((o,r)=>Number(r.time??0)-Number(o.time??0)).slice(0,210);for(let o of i){let r=t[g(`hn|${o.id}`)%t.length];this.addExternalPost({source:"hn",sourceId:String(o.id),title:String(o.title||"").trim()||null,body:this.buildHnBody(o),createdAt:this.hnTimeToIso(o.time),likeCount:Math.max(0,Number(o.score??0)),commentCount:Math.max(0,Number(o.descendants??0)),viewBoost:g(String(o.id))%1200,media:this.detectHnMedia(o.url),caption:this.extractHost(o.url),profile:r})}}catch{}}async appendPushshiftComments(t){try{let e=await this.fetchJson(R,7e3),s=Array.isArray(e?.data)?e.data:[];if(!s.length)return;let n=0;for(let i of s){if(n>=220)break;let o=String(i?.id||"").trim();if(!o)continue;let r=this.normalizePushshiftBody(i?.body);if(!r)continue;let a=t[g(`ps|${o}`)%t.length],u=String(i?.subreddit||"").trim(),l=String(i?.link_title||"").trim()||(u?`Reddit r/${u}`:"Reddit discussion"),m=this.hnTimeToIso(i?.created_utc),h=Math.max(0,Number(i?.score??0));this.addExternalPost({source:"ps",sourceId:o,title:l,body:r,createdAt:m,likeCount:h,commentCount:0,viewBoost:g(`ps|${o}`)%900,media:{type:"none",url:null},caption:u?`r/${u}`:"reddit",profile:a}),n+=1}}catch{}}addExternalPost(t){let s=`${t.source==="hn"?"hn_":"ps_"}${t.sourceId}`;if(this.postsById.has(s))return;let n=this.profileToAuthor(t.profile||{user_id:`ext_${t.sourceId}`}),i=String(n.country_code||"").trim().toUpperCase();if(!i)return;let o={id:s,title:t.title,body:t.body,media_type:t.media.type,media_url:t.media.url,thumb_url:null,media_caption:t.caption,visibility:"public",like_count:0,comment_count:0,view_count:0,liked_by_me:!1,created_at:t.createdAt,updated_at:t.createdAt,author_id:n.user_id,country_name:n.country_name??null,country_code:i,city_name:null,author:n},r={like_count:t.likeCount,comment_count:t.commentCount,view_count:Math.max(t.likeCount*34+t.commentCount*9,60+t.viewBoost),liked_by_me:!1};this.postStates.set(o.id,r),this.applyState(o,r),this.posts.push(o),this.postsById.set(o.id,o);let a=this.postsByCountry.get(i)??[];a.push(o),this.postsByCountry.set(i,a);let u=this.postsByAuthor.get(o.author_id)??[];u.push(o),this.postsByAuthor.set(o.author_id,u),this.postMediaMeta.set(o.id,{type:o.media_type??"none",query:null,url:o.media_url,thumb_url:o.thumb_url??null})}resetFeedCaches(){this.posts=[],this.postsById.clear(),this.postsByCountry.clear(),this.postsByAuthor.clear(),this.postStates.clear(),this.countryFeedCache.clear(),this.postSearchCache.clear(),this.postMediaMeta.clear(),this.commentsByPost.clear(),this.localCommentsByPost.clear(),this.commentStates.clear(),this.commentOrderCache.clear()}async fetchHnItems(t,e){let s=[],n=0,i=new Array(Math.max(1,e)).fill(null).map(async()=>{for(;n<t.length;){let o=n;n+=1;let r=t[o];try{let a=await this.fetchJson(N(r),3500);a&&s.push(a)}catch{}}});return await Promise.all(i),s}async fetchJson(t,e=4e3){let s=new AbortController,n=setTimeout(()=>s.abort(),e);try{let i=await fetch(t,{signal:s.signal,cache:"no-store"});if(!i.ok)throw new Error(`HTTP ${i.status}`);return await i.json()}finally{clearTimeout(n)}}hnTimeToIso(t){let e=Number(t??0);return!Number.isFinite(e)||e<=0?new Date().toISOString():new Date(e*1e3).toISOString()}extractHost(t){let e=String(t||"").trim();if(!e)return null;try{return new URL(e).hostname.replace(/^www\./i,"")}catch{return null}}stripHtml(t){let e=String(t||"").trim();if(!e)return"";try{let s=document.createElement("div");return s.innerHTML=e,(s.textContent||s.innerText||"").trim()}catch{return e.replace(/<[^>]*>/g," ").replace(/\s+/g," ").trim()}}buildHnBody(t){let e=this.stripHtml(String(t?.text||""));if(e)return e.slice(0,1800);let s=String(t?.url||"").trim();return s?`External link: ${s}`:""}normalizePushshiftBody(t){let e=this.stripHtml(String(t||""));if(!e)return"";let s=e.toLowerCase();return s==="[deleted]"||s==="[removed]"?"":e.slice(0,1600)}detectHnMedia(t){let e=String(t||"").trim();if(!e)return{type:"none",url:null};let s=e.split("?")[0].toLowerCase();return/\.(png|jpg|jpeg|webp|gif)$/i.test(s)?{type:"image",url:e}:/\.(mp4|webm|mov|m3u8)$/i.test(s)?{type:"video",url:e}:{type:"none",url:null}}async ensureProfileMap(t){if(!this.profileMap){let e=await this.fakeData.getProfiles(),s=new Map;for(let n of e)s.set(n.user_id,this.profileToAuthor(n));this.profileMap=s}if(t&&t.size){await this.fakeData.ensureProfilesById(t);for(let e of t){if(this.profileMap?.has(e))continue;let s=await this.fakeData.getProfileById(e);s&&this.profileMap?.set(e,this.profileToAuthor(s))}}}profileToAuthor(t){return{user_id:t.user_id,display_name:t.display_name??null,username:t.username??null,avatar_url:t.avatar_url??null,country_name:t.country_name??null,country_code:t.country_code??null}}applyState(t,e){t.like_count=e.like_count,t.comment_count=e.comment_count,t.view_count=e.view_count,t.liked_by_me=e.liked_by_me}ensurePostState(t){let e=this.postStates.get(t);return e||(e={like_count:0,comment_count:0,view_count:0,liked_by_me:!1},this.postStates.set(t,e)),e}ensureCommentState(t,e){let s=this.commentStates.get(t);return s||(s={like_count:e.like_count,liked_by_me:e.liked_by_me},this.commentStates.set(t,s)),s}findComment(t){for(let e of this.commentsByPost.values()){let s=e.find(n=>n.id===t);if(s)return s}for(let e of this.localCommentsByPost.values()){let s=e.find(n=>n.id===t);if(s)return s}return null}seedCount(t,e){let s=D(g(t));return Math.floor(Math.pow(s(),2)*e)}buildBalancedOrder(t,e){let s=Date.now(),n=Math.floor(s/(1e3*60*15)),i=`${e}:${n}`,o=this.countryFeedCache.get(i);if(o)return o.posts;let r=[...t].sort((c,_)=>new Date(_.created_at).getTime()-new Date(c.created_at).getTime()),a=new Map;for(let c of r){let _=a.get(c.author_id)??[];_.push(c),a.set(c.author_id,_)}let u=Array.from(a.keys()),l=D(g(`${e}|${n}`));for(let c=u.length-1;c>0;c-=1){let _=Math.floor(l()*(c+1)),f=u[c];u[c]=u[_],u[_]=f}let m=[],h=!0;for(;h;){h=!1;for(let c of u){let _=a.get(c);!_||!_.length||(m.push(_.shift()),h=!0)}}return this.countryFeedCache.set(i,{ts:s,posts:m}),m}sliceWithOffset(t,e,s){if(!e.length)return[];if(e.length<=s)return[...e];let i=(this.countryOffsets.get(t)??0)%e.length,o=i+s,r=(i+s)%e.length;if(this.countryOffsets.set(t,r),o<=e.length)return e.slice(i,o);let a=e.slice(i),u=e.slice(0,o-e.length);return[...a,...u]}normalizeBody(t,e){let s=String(t||"").trim();if(!s)return"";let n=s,i=/^in\s+[A-Za-z][^,.:;-]{1,60}[,.:;-]\s*/i;if(n=n.replace(i,"").trim(),!n||!e)return n;let o=e.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),r=new RegExp(`^In\\s+${o}\\b[\\s,.-]*`,"i");return n.replace(r,"").trim()}getOrderedComments(t){let e=this.commentOrderCache.get(t);if(e)return e;let s=this.commentsByPost.get(t)??[];if(!s.length)return this.commentOrderCache.set(t,[]),[];let n=[],i=new Set;for(let r of s){let a=`${r.author_id}|${this.normalizeCommentBody(r.body)}`;i.has(a)||(i.add(a),n.push(r))}let o=D(g(`${t}|comments`));for(let r=n.length-1;r>0;r-=1){let a=Math.floor(o()*(r+1)),u=n[r];n[r]=n[a],n[a]=u}return this.commentOrderCache.set(t,n),n}normalizeCommentBody(t){return String(t||"").trim().toLowerCase().replace(/\s+/g," ")}normalizeAuthorId(t){let e=String(t||"").trim();if(!e)return null;let s=e.match(/^user_(\d+)$/i);if(!s)return e;let n=parseInt(s[1],10);return!Number.isFinite(n)||n<=0?e:`user_${String(n).padStart(6,"0")}`}resolveAssetUrl(t){let e=document.querySelector("base")?.getAttribute("href")??"/",s=new URL(e,window.location.origin).toString();return new URL(t,s).toString()}async fetchText(t){if(typeof window>"u"||typeof document>"u")return"";let e=this.resolveAssetUrl(t),s=await fetch(e);if(!s.ok)throw new Error(`Failed to load ${t}: ${s.status}`);return s.text()}async hydrateMedia(t){if(!y.pexelsApiKey)return;let e=t.map(async s=>{if(!s||s.media_type==="none"||s.media_url)return;let n=this.postMediaMeta.get(s.id);if(!n||!n.query)return;let i=`${n.type}:${n.query}`.toLowerCase(),o=this.pexelsCache.get(i);if(o){s.media_url=o.url,s.thumb_url=o.thumb_url;return}let r=this.pexelsInflight.get(i);if(r){let l=await r;s.media_url=l.url,s.thumb_url=l.thumb_url;return}let a=this.fetchPexels(n.type,n.query);this.pexelsInflight.set(i,a);let u=await a;this.pexelsInflight.delete(i),this.pexelsCache.set(i,u),s.media_url=u.url,s.thumb_url=u.thumb_url});await Promise.all(e)}async fetchPexels(t,e){let s=y.pexelsApiKey||"";if(!s)return{url:null,thumb_url:null};let n={Authorization:s};if(t==="video"){let l=`https://api.pexels.com/videos/search?query=${encodeURIComponent(e)}&per_page=1`,m=await fetch(l,{headers:n});if(!m.ok)return{url:null,thumb_url:null};let c=(await m.json())?.videos?.[0];if(!c)return{url:null,thumb_url:null};let f=(Array.isArray(c.video_files)?c.video_files:[]).filter(p=>String(p?.file_type||"").toLowerCase()==="video/mp4").sort((p,k)=>(p?.width??0)-(k?.width??0)),$=f.find(p=>(p?.width??0)>=720)||f[0],C=c.video_pictures?.[0]?.picture||c.image||null;return{url:$?.link??null,thumb_url:C}}let i=`https://api.pexels.com/v1/search?query=${encodeURIComponent(e)}&per_page=1`,o=await fetch(i,{headers:n});if(!o.ok)return{url:null,thumb_url:null};let u=(await o.json())?.photos?.[0]?.src||{};return{url:u?.large??u?.medium??null,thumb_url:u?.medium??null}}static \u0275fac=function(e){return new(e||d)(v(x))};static \u0275prov=P({token:d,factory:d.\u0275fac,providedIn:"root"})};var q=class d{constructor(t,e,s){this.gql=t;this.postEvents=e;this.demoData=s}async listByCountry(t,e=25,s){if(y.useDemoDataset){let o=s?.demoLimit??1e3,r=Math.max(e,o),[a,u]=await Promise.allSettled([this.withTimeout(this.gql.request(`
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
          `,{code:t,limit:r}),1600,"postsByCountry"),this.demoData.listByCountry(t,r,{skipComments:s?.skipComments})]),l=a.status==="fulfilled"?(a.value.postsByCountry??[]).map(h=>this.mapPost(h)):[],m=u.status==="fulfilled"?u.value:[];return this.mergePosts(l,m,r)}let n=`
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
    `,{postsByCountry:i}=await this.gql.request(n,{code:t,limit:e});return(i??[]).map(o=>this.mapPost(o))}async listForAuthor(t,e=25){if(!t)return[];if(y.useDemoDataset&&/^user_/.test(t))return this.demoData.listForAuthor(t,e);let s=`
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
    `,{postsByAuthor:n}=await this.gql.request(s,{authorId:t,limit:e});return(n??[]).map(i=>this.mapPost(i))}async searchPosts(t,e=25){let s=String(t||"").trim();if(!s)return[];let n=`
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
    `;try{let{searchPosts:i}=await this.gql.request(n,{query:s,limit:e});return(i??[]).map(o=>this.mapPost(o))}catch{return[]}}async getPostById(t){if(!t)return null;if(y.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.getPostById(t);let e=`
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
    `,n={title:e.title?.trim()??null,body:e.body?.trim()??null,visibility:e.visibility??null},{updatePost:i}=await this.gql.request(s,{postId:t,input:n}),o=this.mapPost(i);return this.postEvents.emitUpdated(o),o}async deletePost(t,e){let s=`
      mutation DeletePost($postId: ID!) {
        deletePost(post_id: $postId)
      }
    `,{deletePost:n}=await this.gql.request(s,{postId:t});return n&&this.postEvents.emitDeleted({id:t,country_code:e?.country_code??null,author_id:e?.author_id??null}),n}async likePost(t){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.likePost(t);return this.postEvents.emitUpdated(i),i}let e=`
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
    `,{likePost:s}=await this.gql.request(e,{postId:t}),n=this.mapPost(s);return this.postEvents.emitUpdated(n),n}async unlikePost(t){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=await this.demoData.unlikePost(t);return this.postEvents.emitUpdated(i),i}let e=`
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
    `,{unlikePost:s}=await this.gql.request(e,{postId:t}),n=this.mapPost(s);return this.postEvents.emitUpdated(n),n}async recordView(t){if(t?.id){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t.id)){await this.demoData.recordView(t.id);return}t.view_count=Number(t.view_count??0)+1}}async listComments(t,e=25,s){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t)){let o=Math.max(e,1e3);return this.demoData.listComments(t,o)}let n=`
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
    `,{commentsByPost:i}=await this.gql.request(n,{postId:t,limit:e,before:s??null});return(i??[]).map(o=>this.mapComment(o))}async listLikes(t,e=25){if(!t)return[];if(y.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.listLikes(t,e);let s=`
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
    `,{postLikes:n}=await this.gql.request(s,{postId:t,limit:e});return(n??[]).map(i=>this.mapLike(i))}async addComment(t,e,s){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.addComment(t,e,s??null);let n=`
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
    `,{addComment:i}=await this.gql.request(n,{postId:t,body:e.trim(),parentId:s??null});return this.mapComment(i)}async likeComment(t){if(y.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.likeComment(t);let e=`
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
    `,{likeComment:s}=await this.gql.request(e,{commentId:t});return this.mapComment(s)}async unlikeComment(t){if(y.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.unlikeComment(t);let e=`
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
    `,{unlikeComment:s}=await this.gql.request(e,{commentId:t});return this.mapComment(s)}async reportPost(t,e){let s=`
      mutation ReportPost($postId: ID!, $reason: String!) {
        reportPost(post_id: $postId, reason: $reason)
      }
    `,{reportPost:n}=await this.gql.request(s,{postId:t,reason:e.trim()});return!!n}mapPost(t,e=0){let s=t?.view_count!=null?Number(t.view_count):this.estimateViewCount(t?.id,t?.like_count,t?.comment_count),n=t?.shared_post&&e<1?this.mapPost(t.shared_post,e+1):null;return{id:t.id,title:t.title??null,body:t.body??"",media_type:t.media_type??"none",media_url:t.media_url??null,thumb_url:t.thumb_url??null,media_caption:t.media_caption??null,shared_post_id:t.shared_post_id??null,shared_post:n,visibility:t.visibility??"public",like_count:Number(t.like_count??0),comment_count:Number(t.comment_count??0),view_count:s,liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author_id:t.author_id,country_name:t.country_name??null,country_code:t.country_code??null,city_name:t.city_name??null,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.normalizeAvatarUrl(t.author.avatar_url),country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapComment(t){return{id:t.id,post_id:t.post_id,parent_id:t.parent_id??null,author_id:t.author_id,body:t.body??"",like_count:Number(t.like_count??0),liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.normalizeAvatarUrl(t.author.avatar_url),country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapLike(t){return{user_id:t.user_id,created_at:t.created_at,user:t.user?{user_id:t.user.user_id,display_name:t.user.display_name,username:t.user.username,avatar_url:this.normalizeAvatarUrl(t.user.avatar_url),country_name:t.user.country_name,country_code:t.user.country_code}:null}}mergePosts(t,e,s){let n=[...t,...e],i=new Set,o=[];for(let r of n)!r?.id||i.has(r.id)||(i.add(r.id),o.push(r));if(t.length){let r=new Set(t.map(l=>l.id)),a=t.filter(l=>r.has(l.id)).sort((l,m)=>new Date(m.created_at).getTime()-new Date(l.created_at).getTime()),u=o.filter(l=>!r.has(l.id));return[...a,...u].slice(0,Math.max(1,s))}return o.sort((r,a)=>new Date(a.created_at).getTime()-new Date(r.created_at).getTime()).slice(0,Math.max(1,s))}estimateViewCount(t,e,s){let n=Number(e??0),i=Number(s??0);if(!n&&!i)return 0;let r=this.hashSeed(String(t||"post"))%1200,a=n*12+i*6+r;return Math.max(a,n+i)}hashSeed(t){let e=2166136261;for(let s=0;s<t.length;s++)e^=t.charCodeAt(s),e=Math.imul(e,16777619);return e>>>0}normalizeAvatarUrl(t){let e=String(t??"").trim();if(!e)return null;if(e.startsWith("data:")||e.startsWith("blob:"))return e;let s=i=>{let o=i.replace(/^\/+/,"").replace(/^storage\/v1\/object\/(?:public|sign)\/avatars\/+/i,"").replace(/^avatars\/+/i,"");return o?`${y.supabaseUrl}/storage/v1/object/public/avatars/${o}`:null};if(/^https?:\/\//i.test(e)){try{let i=new URL(e);if(/\/storage\/v1\/object\/(?:public|sign)\/avatars\//i.test(i.pathname))return s(decodeURIComponent(i.pathname))}catch{return e}return e}let n=s(e);return n||null}async withTimeout(t,e,s){let n=null;try{return await Promise.race([t,new Promise((i,o)=>{n=setTimeout(()=>o(new Error(`${s} timeout`)),e)})])}finally{n&&clearTimeout(n)}}static \u0275fac=function(e){return new(e||d)(v(L),v(S),v(I))};static \u0275prov=P({token:d,factory:d.\u0275fac,providedIn:"root"})};export{S as a,q as b};
