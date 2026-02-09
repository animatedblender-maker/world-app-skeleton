import{a as L}from"./chunk-LJDR2ADK.js";import{a as q}from"./chunk-7DJA5TI4.js";import{a as y}from"./chunk-LQQHCQP3.js";import{b as k}from"./chunk-KO5X6LCN.js";import{a as P,k as b,n as f}from"./chunk-SPQ2JWKS.js";var w=class l{createdPostSubject=new P;createdPost$=this.createdPostSubject.asObservable();updatedPostSubject=new P;updatedPost$=this.updatedPostSubject.asObservable();insertSubject=new P;insert$=this.insertSubject.asObservable();updateSubject=new P;update$=this.updateSubject.asObservable();deleteSubject=new P;delete$=this.deleteSubject.asObservable();channel=k.channel("public:posts");constructor(){this.channel.on("postgres_changes",{event:"INSERT",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.insertSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.updateSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null,visibility:t.visibility??null})}).on("postgres_changes",{event:"DELETE",schema:"public",table:"posts"},({old:t})=>{t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).subscribe()}emit(t){this.createdPostSubject.next(t)}emitUpdated(t){this.updatedPostSubject.next(t)}emitDeleted(t){t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}ngOnDestroy(){this.channel?.unsubscribe()}static \u0275fac=function(e){return new(e||l)};static \u0275prov=b({token:l,factory:l.\u0275fac,providedIn:"root"})};var O="demo_social_dataset_30k/posts.jsonl",j="demo_social_dataset_30k/comments.jsonl",E="demo_social_dataset_30k/video_captions.jsonl";function D(l){let t=l>>>0;return()=>{t|=0,t=t+1831565813|0;let e=Math.imul(t^t>>>15,1|t);return e=e+Math.imul(e^e>>>7,61|e)^e,((e^e>>>14)>>>0)/4294967296}}function S(l){let t=2166136261;for(let e=0;e<l.length;e++)t^=l.charCodeAt(e),t=Math.imul(t,16777619);return t>>>0}function M(l){let t=[],e=l.split(/\r?\n/);for(let o of e){let n=o.trim();if(n)try{t.push(JSON.parse(n))}catch{}}return t}var $=class l{constructor(t){this.fakeData=t}postsLoaded=!1;postsPromise=null;commentsLoaded=!1;commentsPromise=null;captionsLoaded=!1;captionsPromise=null;posts=[];postsById=new Map;postsByCountry=new Map;postsByAuthor=new Map;postStates=new Map;countryFeedCache=new Map;postSearchCache=new Map;postMediaMeta=new Map;captionsByPost=new Map;commentsByPost=new Map;localCommentsByPost=new Map;commentStates=new Map;commentOrderCache=new Map;profileMap=null;countryOffsets=new Map;pexelsCache=new Map;pexelsInflight=new Map;async isDemoPostId(t){return await this.ensurePostsLoaded(),this.postsById.has(t)}isDemoCommentId(t){return/^cmt_|^local_/.test(t)}async listByCountry(t,e=25,o){o?.skipComments?await this.ensurePostsLoaded():await this.ensureCommentsLoaded();let n=String(t||"").trim().toUpperCase(),s=this.postsByCountry.get(n)??[],i=this.buildBalancedOrder(s,n),r=Math.max(1,e),a=this.sliceWithOffset(n,i,r);return await this.hydrateMedia(a),a}async listForAuthor(t,e=25){await this.ensureCommentsLoaded();let s=[...this.postsByAuthor.get(t)??[]].sort((i,r)=>new Date(r.created_at).getTime()-new Date(i.created_at).getTime()).slice(0,Math.max(1,e));return await this.hydrateMedia(s),s}async getPostById(t){await this.ensureCommentsLoaded();let e=this.postsById.get(t)??null;return e?(await this.hydrateMedia([e]),e):null}async searchPosts(t,e=20){let o=String(t||"").trim().toLowerCase();if(!o)return[];await this.ensurePostsLoaded();let n=this.postSearchCache.get(o);if(n){if(e<=0)return n;let a=n.slice(0,Math.max(1,e));return await this.hydrateMedia(a),a}let i=this.posts.filter(a=>{let u=String(a.title||"").toLowerCase(),d=String(a.body||"").toLowerCase(),c=String(a.media_caption||"").toLowerCase();return u.includes(o)||d.includes(o)||c.includes(o)}).sort((a,u)=>new Date(u.created_at).getTime()-new Date(a.created_at).getTime());if(this.postSearchCache.set(o,i),this.postSearchCache.size>40){let a=this.postSearchCache.keys().next().value;a&&this.postSearchCache.delete(a)}if(e<=0)return i;let r=i.slice(0,Math.max(1,e));return await this.hydrateMedia(r),r}async listComments(t,e=25){await this.ensureCommentsLoaded();let o=this.getOrderedComments(t),n=this.localCommentsByPost.get(t)??[];return[...o,...n].slice(0,Math.max(1,e))}async addComment(t,e,o){await this.ensurePostsLoaded();let s=(await k.auth.getUser()).data.user?.id??"me",i=new Date().toISOString(),r={user_id:s,display_name:"You",username:null,avatar_url:null,country_name:null,country_code:null},a={id:`local_${Date.now()}_${Math.floor(Math.random()*1e4)}`,post_id:t,parent_id:o??null,author_id:s,body:e.trim(),like_count:0,liked_by_me:!1,created_at:i,updated_at:i,author:r},u=this.localCommentsByPost.get(t)??[];u.push(a),this.localCommentsByPost.set(t,u);let d=this.postStates.get(t);if(d){d.comment_count+=1;let c=this.postsById.get(t);c&&(c.comment_count=d.comment_count)}return a}async likePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let o=this.ensurePostState(t);return o.liked_by_me||(o.liked_by_me=!0,o.like_count+=1),this.applyState(e,o),e}async unlikePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let o=this.ensurePostState(t);return o.liked_by_me&&(o.liked_by_me=!1,o.like_count=Math.max(0,o.like_count-1)),this.applyState(e,o),e}async recordView(t){if(!t)return;await this.ensurePostsLoaded();let e=this.ensurePostState(t);e.view_count+=1;let o=this.postsById.get(t);o&&this.applyState(o,e)}async listLikes(t,e=25){await this.ensurePostsLoaded();let o=this.postStates.get(t),n=Math.max(0,Math.min(e,o?.like_count??0));if(!n)return[];let s=await this.fakeData.getProfiles();if(!s.length)return[];let i=D(S(`${t}|likes`)),r=new Set;for(;r.size<n&&r.size<s.length;)r.add(Math.floor(i()*s.length));let a=new Date().toISOString();return[...r].map(u=>{let d=s[u];return{user_id:d.user_id,created_at:a,user:this.profileToAuthor(d)}})}async likeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let o=this.ensureCommentState(t,e);return o.liked_by_me||(o.liked_by_me=!0,o.like_count+=1),e.liked_by_me=o.liked_by_me,e.like_count=o.like_count,e}async unlikeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let o=this.ensureCommentState(t,e);return o.liked_by_me&&(o.liked_by_me=!1,o.like_count=Math.max(0,o.like_count-1)),e.liked_by_me=o.liked_by_me,e.like_count=o.like_count,e}async ensurePostsLoaded(){if(!this.postsLoaded)return this.postsPromise?this.postsPromise:(this.postsPromise=(async()=>{await this.ensureCaptionsLoaded();let t=await this.fetchText(O),e=M(t),o=new Set;for(let n of e){let s=this.normalizeAuthorId(n?.author_id);s&&o.add(s)}await this.ensureProfileMap(o);for(let n of e){let s=this.normalizeAuthorId(n?.author_id);if(!n?.id||!s)continue;let i=this.profileMap?.get(s)??null,r=n.media?.type??"none",a=n.media?.url??null,u=n.media?.thumb_url??null,d=this.captionsByPost.get(n.id)??null,c=i?.country_code??n.country_code??null,h=i?.country_name??n.country_name??null,m=n.created_at||new Date().toISOString(),_={id:n.id,title:n.title??null,body:this.normalizeBody(n.body??"",h||n.country_name||null),media_type:r,media_url:a,thumb_url:u,media_caption:d,visibility:n.visibility||"public",like_count:0,comment_count:0,view_count:0,liked_by_me:!1,created_at:m,updated_at:m,author_id:s,country_name:h,country_code:c,city_name:null,author:i},g=this.seedCount(n.id,8e3),I=this.seedCount(`${n.id}|views`,18e4),v={like_count:g,comment_count:0,view_count:Math.max(I,g*6),liked_by_me:!1};this.postStates.set(n.id,v),this.applyState(_,v),this.posts.push(_),this.postsById.set(n.id,_);let p=String(c||"").trim().toUpperCase();if(p){let B=this.postsByCountry.get(p)??[];B.push(_),this.postsByCountry.set(p,B)}let C=this.postsByAuthor.get(s)??[];C.push(_),this.postsByAuthor.set(s,C),this.postMediaMeta.set(n.id,{type:r,query:n.media?.query??null,url:a,thumb_url:u})}this.postsLoaded=!0})(),this.postsPromise)}async ensureCommentsLoaded(){if(!this.commentsLoaded)return this.commentsPromise?this.commentsPromise:(this.commentsPromise=(async()=>{await this.ensurePostsLoaded();let t=await this.fetchText(j),e=M(t),o=new Set;for(let n of e){let s=this.normalizeAuthorId(n?.author_id);s&&o.add(s)}await this.ensureProfileMap(o);for(let n of e){let s=this.normalizeAuthorId(n?.author_id);if(!n?.id||!n?.post_id||!s)continue;let i=this.profileMap?.get(s)??null,r=n.created_at||new Date().toISOString(),a={id:n.id,post_id:n.post_id,parent_id:n.parent_id??null,author_id:s,body:n.body??"",like_count:this.seedCount(n.id,160),liked_by_me:!1,created_at:r,updated_at:r,author:i},u=this.commentsByPost.get(n.post_id)??[];u.push(a),this.commentsByPost.set(n.post_id,u),this.commentStates.set(n.id,{like_count:a.like_count,liked_by_me:!1});let d=this.postStates.get(n.post_id);d&&(d.comment_count+=1)}for(let[n,s]of this.postStates.entries()){let i=this.postsById.get(n);i&&(i.comment_count=s.comment_count)}this.commentsLoaded=!0})(),this.commentsPromise)}async ensureCaptionsLoaded(){if(!this.captionsLoaded)return this.captionsPromise?this.captionsPromise:(this.captionsPromise=(async()=>{let t=await this.fetchText(E),e=M(t);for(let o of e)!o?.post_id||!o?.caption||this.captionsByPost.set(o.post_id,o.caption);this.captionsLoaded=!0})(),this.captionsPromise)}async ensureProfileMap(t){if(!this.profileMap){let e=await this.fakeData.getProfiles(),o=new Map;for(let n of e)o.set(n.user_id,this.profileToAuthor(n));this.profileMap=o}if(t&&t.size){await this.fakeData.ensureProfilesById(t);for(let e of t){if(this.profileMap?.has(e))continue;let o=await this.fakeData.getProfileById(e);o&&this.profileMap?.set(e,this.profileToAuthor(o))}}}profileToAuthor(t){return{user_id:t.user_id,display_name:t.display_name??null,username:t.username??null,avatar_url:t.avatar_url??null,country_name:t.country_name??null,country_code:t.country_code??null}}applyState(t,e){t.like_count=e.like_count,t.comment_count=e.comment_count,t.view_count=e.view_count,t.liked_by_me=e.liked_by_me}ensurePostState(t){let e=this.postStates.get(t);return e||(e={like_count:0,comment_count:0,view_count:0,liked_by_me:!1},this.postStates.set(t,e)),e}ensureCommentState(t,e){let o=this.commentStates.get(t);return o||(o={like_count:e.like_count,liked_by_me:e.liked_by_me},this.commentStates.set(t,o)),o}findComment(t){for(let e of this.commentsByPost.values()){let o=e.find(n=>n.id===t);if(o)return o}for(let e of this.localCommentsByPost.values()){let o=e.find(n=>n.id===t);if(o)return o}return null}seedCount(t,e){let o=D(S(t));return Math.floor(Math.pow(o(),2)*e)}buildBalancedOrder(t,e){let o=Date.now(),n=Math.floor(o/(1e3*60*15)),s=`${e}:${n}`,i=this.countryFeedCache.get(s);if(i)return i.posts;let r=[...t].sort((m,_)=>new Date(_.created_at).getTime()-new Date(m.created_at).getTime()),a=new Map;for(let m of r){let _=a.get(m.author_id)??[];_.push(m),a.set(m.author_id,_)}let u=Array.from(a.keys()),d=D(S(`${e}|${n}`));for(let m=u.length-1;m>0;m-=1){let _=Math.floor(d()*(m+1)),g=u[m];u[m]=u[_],u[_]=g}let c=[],h=!0;for(;h;){h=!1;for(let m of u){let _=a.get(m);!_||!_.length||(c.push(_.shift()),h=!0)}}return this.countryFeedCache.set(s,{ts:o,posts:c}),c}sliceWithOffset(t,e,o){if(!e.length)return[];if(e.length<=o)return[...e];let s=(this.countryOffsets.get(t)??0)%e.length,i=s+o,r=(s+o)%e.length;if(this.countryOffsets.set(t,r),i<=e.length)return e.slice(s,i);let a=e.slice(s),u=e.slice(0,i-e.length);return[...a,...u]}normalizeBody(t,e){let o=String(t||"").trim();if(!o)return"";let n=o,s=/^in\s+[A-Za-z][^,.:;-]{1,60}[,.:;-]\s*/i;if(n=n.replace(s,"").trim(),!n||!e)return n;let i=e.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),r=new RegExp(`^In\\s+${i}\\b[\\s,.-]*`,"i");return n.replace(r,"").trim()}getOrderedComments(t){let e=this.commentOrderCache.get(t);if(e)return e;let o=this.commentsByPost.get(t)??[];if(!o.length)return this.commentOrderCache.set(t,[]),[];let n=[],s=new Set;for(let r of o){let a=`${r.author_id}|${this.normalizeCommentBody(r.body)}`;s.has(a)||(s.add(a),n.push(r))}let i=D(S(`${t}|comments`));for(let r=n.length-1;r>0;r-=1){let a=Math.floor(i()*(r+1)),u=n[r];n[r]=n[a],n[a]=u}return this.commentOrderCache.set(t,n),n}normalizeCommentBody(t){return String(t||"").trim().toLowerCase().replace(/\s+/g," ")}normalizeAuthorId(t){let e=String(t||"").trim();if(!e)return null;let o=e.match(/^user_(\d+)$/i);if(!o)return e;let n=parseInt(o[1],10);return!Number.isFinite(n)||n<=0?e:`user_${String(n).padStart(6,"0")}`}resolveAssetUrl(t){let e=document.querySelector("base")?.getAttribute("href")??"/",o=new URL(e,window.location.origin).toString();return new URL(t,o).toString()}async fetchText(t){if(typeof window>"u"||typeof document>"u")return"";let e=this.resolveAssetUrl(t),o=await fetch(e);if(!o.ok)throw new Error(`Failed to load ${t}: ${o.status}`);return o.text()}async hydrateMedia(t){if(!y.pexelsApiKey)return;let e=t.map(async o=>{if(!o||o.media_type==="none"||o.media_url)return;let n=this.postMediaMeta.get(o.id);if(!n||!n.query)return;let s=`${n.type}:${n.query}`.toLowerCase(),i=this.pexelsCache.get(s);if(i){o.media_url=i.url,o.thumb_url=i.thumb_url;return}let r=this.pexelsInflight.get(s);if(r){let d=await r;o.media_url=d.url,o.thumb_url=d.thumb_url;return}let a=this.fetchPexels(n.type,n.query);this.pexelsInflight.set(s,a);let u=await a;this.pexelsInflight.delete(s),this.pexelsCache.set(s,u),o.media_url=u.url,o.thumb_url=u.thumb_url});await Promise.all(e)}async fetchPexels(t,e){let o=y.pexelsApiKey||"";if(!o)return{url:null,thumb_url:null};let n={Authorization:o};if(t==="video"){let d=`https://api.pexels.com/videos/search?query=${encodeURIComponent(e)}&per_page=1`,c=await fetch(d,{headers:n});if(!c.ok)return{url:null,thumb_url:null};let m=(await c.json())?.videos?.[0];if(!m)return{url:null,thumb_url:null};let g=(Array.isArray(m.video_files)?m.video_files:[]).filter(p=>String(p?.file_type||"").toLowerCase()==="video/mp4").sort((p,C)=>(p?.width??0)-(C?.width??0)),I=g.find(p=>(p?.width??0)>=720)||g[0],v=m.video_pictures?.[0]?.picture||m.image||null;return{url:I?.link??null,thumb_url:v}}let s=`https://api.pexels.com/v1/search?query=${encodeURIComponent(e)}&per_page=1`,i=await fetch(s,{headers:n});if(!i.ok)return{url:null,thumb_url:null};let u=(await i.json())?.photos?.[0]?.src||{};return{url:u?.large??u?.medium??null,thumb_url:u?.medium??null}}static \u0275fac=function(e){return new(e||l)(f(L))};static \u0275prov=b({token:l,factory:l.\u0275fac,providedIn:"root"})};var A=class l{constructor(t,e,o){this.gql=t;this.postEvents=e;this.demoData=o}async listByCountry(t,e=25,o){if(y.useDemoDataset){let i=o?.demoLimit??1e3,r=Math.max(e,i),[a,u]=await Promise.allSettled([this.withTimeout(this.gql.request(`
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
          `,{code:t,limit:r}),1600,"postsByCountry"),this.demoData.listByCountry(t,r,{skipComments:o?.skipComments})]),d=a.status==="fulfilled"?(a.value.postsByCountry??[]).map(h=>this.mapPost(h)):[],c=u.status==="fulfilled"?u.value:[];return this.mergePosts(d,c,r)}let n=`
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
    `,{postsByCountry:s}=await this.gql.request(n,{code:t,limit:e});return(s??[]).map(i=>this.mapPost(i))}async listForAuthor(t,e=25){if(!t)return[];if(y.useDemoDataset&&/^user_/.test(t))return this.demoData.listForAuthor(t,e);let o=`
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
    `,{postsByAuthor:n}=await this.gql.request(o,{authorId:t,limit:e});return(n??[]).map(s=>this.mapPost(s))}async searchPosts(t,e=25){let o=String(t||"").trim();if(!o)return[];let n=`
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
    `;try{let{searchPosts:s}=await this.gql.request(n,{query:o,limit:e});return(s??[]).map(i=>this.mapPost(i))}catch{return[]}}async getPostById(t){if(!t)return null;if(y.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.getPostById(t);let e=`
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
    `,{postById:o}=await this.gql.request(e,{postId:t});return o?this.mapPost(o):null}async createPost(t){if(!t.authorId)throw new Error("authorId is required to post.");let e=`
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
    `,o={title:t.title?.trim()||null,body:t.body.trim(),country_name:t.countryName,country_code:t.countryCode,city_name:t.cityName??null,visibility:t.visibility??null,media_type:t.mediaType??null,media_url:t.mediaUrl??null,thumb_url:t.thumbUrl??null,shared_post_id:t.sharedPostId??null},{createPost:n}=await this.gql.request(e,{input:o}),s=this.mapPost(n);return this.postEvents.emit(s),s}async updatePost(t,e){let o=`
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
    `,n={title:e.title?.trim()??null,body:e.body?.trim()??null,visibility:e.visibility??null},{updatePost:s}=await this.gql.request(o,{postId:t,input:n}),i=this.mapPost(s);return this.postEvents.emitUpdated(i),i}async deletePost(t,e){let o=`
      mutation DeletePost($postId: ID!) {
        deletePost(post_id: $postId)
      }
    `,{deletePost:n}=await this.gql.request(o,{postId:t});return n&&this.postEvents.emitDeleted({id:t,country_code:e?.country_code??null,author_id:e?.author_id??null}),n}async likePost(t){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t)){let s=await this.demoData.likePost(t);return this.postEvents.emitUpdated(s),s}let e=`
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
    `,{likePost:o}=await this.gql.request(e,{postId:t}),n=this.mapPost(o);return this.postEvents.emitUpdated(n),n}async unlikePost(t){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t)){let s=await this.demoData.unlikePost(t);return this.postEvents.emitUpdated(s),s}let e=`
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
    `,{unlikePost:o}=await this.gql.request(e,{postId:t}),n=this.mapPost(o);return this.postEvents.emitUpdated(n),n}async recordView(t){if(t?.id){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t.id)){await this.demoData.recordView(t.id);return}t.view_count=Number(t.view_count??0)+1}}async listComments(t,e=25,o){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t)){let i=Math.max(e,1e3);return this.demoData.listComments(t,i)}let n=`
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
    `,{commentsByPost:s}=await this.gql.request(n,{postId:t,limit:e,before:o??null});return(s??[]).map(i=>this.mapComment(i))}async listLikes(t,e=25){if(!t)return[];if(y.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.listLikes(t,e);let o=`
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
    `,{postLikes:n}=await this.gql.request(o,{postId:t,limit:e});return(n??[]).map(s=>this.mapLike(s))}async addComment(t,e,o){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.addComment(t,e,o??null);let n=`
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
    `,{addComment:s}=await this.gql.request(n,{postId:t,body:e.trim(),parentId:o??null});return this.mapComment(s)}async likeComment(t){if(y.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.likeComment(t);let e=`
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
    `,{likeComment:o}=await this.gql.request(e,{commentId:t});return this.mapComment(o)}async unlikeComment(t){if(y.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.unlikeComment(t);let e=`
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
    `,{unlikeComment:o}=await this.gql.request(e,{commentId:t});return this.mapComment(o)}async reportPost(t,e){let o=`
      mutation ReportPost($postId: ID!, $reason: String!) {
        reportPost(post_id: $postId, reason: $reason)
      }
    `,{reportPost:n}=await this.gql.request(o,{postId:t,reason:e.trim()});return!!n}mapPost(t,e=0){let o=t?.view_count!=null?Number(t.view_count):this.estimateViewCount(t?.id,t?.like_count,t?.comment_count),n=t?.shared_post&&e<1?this.mapPost(t.shared_post,e+1):null;return{id:t.id,title:t.title??null,body:t.body??"",media_type:t.media_type??"none",media_url:t.media_url??null,thumb_url:t.thumb_url??null,media_caption:t.media_caption??null,shared_post_id:t.shared_post_id??null,shared_post:n,visibility:t.visibility??"public",like_count:Number(t.like_count??0),comment_count:Number(t.comment_count??0),view_count:o,liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author_id:t.author_id,country_name:t.country_name??null,country_code:t.country_code??null,city_name:t.city_name??null,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:t.author.avatar_url,country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapComment(t){return{id:t.id,post_id:t.post_id,parent_id:t.parent_id??null,author_id:t.author_id,body:t.body??"",like_count:Number(t.like_count??0),liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:t.author.avatar_url,country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapLike(t){return{user_id:t.user_id,created_at:t.created_at,user:t.user?{user_id:t.user.user_id,display_name:t.user.display_name,username:t.user.username,avatar_url:t.user.avatar_url,country_name:t.user.country_name,country_code:t.user.country_code}:null}}mergePosts(t,e,o){let n=[...t,...e],s=new Set,i=[];for(let r of n)!r?.id||s.has(r.id)||(s.add(r.id),i.push(r));if(t.length){let r=new Set(t.map(d=>d.id)),a=t.filter(d=>r.has(d.id)).sort((d,c)=>new Date(c.created_at).getTime()-new Date(d.created_at).getTime()),u=i.filter(d=>!r.has(d.id));return[...a,...u].slice(0,Math.max(1,o))}return i.sort((r,a)=>new Date(a.created_at).getTime()-new Date(r.created_at).getTime()).slice(0,Math.max(1,o))}estimateViewCount(t,e,o){let n=Number(e??0),s=Number(o??0);if(!n&&!s)return 0;let r=this.hashSeed(String(t||"post"))%1200,a=n*12+s*6+r;return Math.max(a,n+s)}hashSeed(t){let e=2166136261;for(let o=0;o<t.length;o++)e^=t.charCodeAt(o),e=Math.imul(e,16777619);return e>>>0}async withTimeout(t,e,o){let n=null;try{return await Promise.race([t,new Promise((s,i)=>{n=setTimeout(()=>i(new Error(`${o} timeout`)),e)})])}finally{n&&clearTimeout(n)}}static \u0275fac=function(e){return new(e||l)(f(q),f(w),f($))};static \u0275prov=b({token:l,factory:l.\u0275fac,providedIn:"root"})};export{w as a,A as b};
