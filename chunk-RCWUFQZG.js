import{a as x}from"./chunk-LJDR2ADK.js";import{a as q}from"./chunk-7DJA5TI4.js";import{a as y}from"./chunk-LQQHCQP3.js";import{a as B,b as k}from"./chunk-KO5X6LCN.js";import{a as f,k as b,n as P}from"./chunk-SPQ2JWKS.js";var S=class m{createdPostSubject=new f;createdPost$=this.createdPostSubject.asObservable();updatedPostSubject=new f;updatedPost$=this.updatedPostSubject.asObservable();insertSubject=new f;insert$=this.insertSubject.asObservable();updateSubject=new f;update$=this.updateSubject.asObservable();deleteSubject=new f;delete$=this.deleteSubject.asObservable();channel=k.channel("public:posts");constructor(){this.channel.on("postgres_changes",{event:"INSERT",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.insertSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.updateSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null,visibility:t.visibility??null})}).on("postgres_changes",{event:"DELETE",schema:"public",table:"posts"},({old:t})=>{t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).subscribe()}emit(t){this.createdPostSubject.next(t)}emitUpdated(t){this.updatedPostSubject.next(t)}emitDeleted(t){t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}ngOnDestroy(){this.channel?.unsubscribe()}static \u0275fac=function(e){return new(e||m)};static \u0275prov=b({token:m,factory:m.\u0275fac,providedIn:"root"})};var E="demo_social_dataset_30k/posts.jsonl",j="demo_social_dataset_30k/comments.jsonl",O="demo_social_dataset_30k/video_captions.jsonl";function D(m){let t=m>>>0;return()=>{t|=0,t=t+1831565813|0;let e=Math.imul(t^t>>>15,1|t);return e=e+Math.imul(e^e>>>7,61|e)^e,((e^e>>>14)>>>0)/4294967296}}function w(m){let t=2166136261;for(let e=0;e<m.length;e++)t^=m.charCodeAt(e),t=Math.imul(t,16777619);return t>>>0}function M(m){let t=[],e=m.split(/\r?\n/);for(let n of e){let i=n.trim();if(i)try{t.push(JSON.parse(i))}catch{}}return t}var $=class m{constructor(t){this.fakeData=t}postsLoaded=!1;postsPromise=null;commentsLoaded=!1;commentsPromise=null;captionsLoaded=!1;captionsPromise=null;posts=[];postsById=new Map;postsByCountry=new Map;postsByAuthor=new Map;postStates=new Map;countryFeedCache=new Map;postSearchCache=new Map;postMediaMeta=new Map;captionsByPost=new Map;commentsByPost=new Map;localCommentsByPost=new Map;commentStates=new Map;commentOrderCache=new Map;profileMap=null;countryOffsets=new Map;pexelsCache=new Map;pexelsInflight=new Map;async isDemoPostId(t){return await this.ensurePostsLoaded(),this.postsById.has(t)}isDemoCommentId(t){return/^cmt_|^local_/.test(t)}async listByCountry(t,e=25,n){n?.skipComments?await this.ensurePostsLoaded():await this.ensureCommentsLoaded();let i=String(t||"").trim().toUpperCase(),s=this.postsByCountry.get(i)??[],o=this.buildBalancedOrder(s,i),r=Math.max(1,e),a=this.sliceWithOffset(i,o,r);return await this.hydrateMedia(a),a}async listForAuthor(t,e=25){await this.ensureCommentsLoaded();let s=[...this.postsByAuthor.get(t)??[]].sort((o,r)=>new Date(r.created_at).getTime()-new Date(o.created_at).getTime()).slice(0,Math.max(1,e));return await this.hydrateMedia(s),s}async getPostById(t){await this.ensureCommentsLoaded();let e=this.postsById.get(t)??null;return e?(await this.hydrateMedia([e]),e):null}async searchPosts(t,e=20){let n=String(t||"").trim().toLowerCase();if(!n)return[];await this.ensurePostsLoaded();let i=this.postSearchCache.get(n);if(i){if(e<=0)return i;let a=i.slice(0,Math.max(1,e));return await this.hydrateMedia(a),a}let o=this.posts.filter(a=>{let u=String(a.title||"").toLowerCase(),l=String(a.body||"").toLowerCase(),c=String(a.media_caption||"").toLowerCase();return u.includes(n)||l.includes(n)||c.includes(n)}).sort((a,u)=>new Date(u.created_at).getTime()-new Date(a.created_at).getTime());if(this.postSearchCache.set(n,o),this.postSearchCache.size>40){let a=this.postSearchCache.keys().next().value;a&&this.postSearchCache.delete(a)}if(e<=0)return o;let r=o.slice(0,Math.max(1,e));return await this.hydrateMedia(r),r}async listComments(t,e=25){await this.ensureCommentsLoaded();let n=this.getOrderedComments(t),i=this.localCommentsByPost.get(t)??[];return[...n,...i].slice(0,Math.max(1,e))}async addComment(t,e,n){await this.ensurePostsLoaded();let s=(await k.auth.getUser()).data.user?.id??"me",o=new Date().toISOString(),r={user_id:s,display_name:"You",username:null,avatar_url:null,country_name:null,country_code:null},a={id:`local_${Date.now()}_${Math.floor(Math.random()*1e4)}`,post_id:t,parent_id:n??null,author_id:s,body:e.trim(),like_count:0,liked_by_me:!1,created_at:o,updated_at:o,author:r},u=this.localCommentsByPost.get(t)??[];u.push(a),this.localCommentsByPost.set(t,u);let l=this.postStates.get(t);if(l){l.comment_count+=1;let c=this.postsById.get(t);c&&(c.comment_count=l.comment_count)}return a}async likePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let n=this.ensurePostState(t);return n.liked_by_me||(n.liked_by_me=!0,n.like_count+=1),this.applyState(e,n),e}async unlikePost(t){await this.ensurePostsLoaded();let e=this.postsById.get(t);if(!e)throw new Error("Post not found.");let n=this.ensurePostState(t);return n.liked_by_me&&(n.liked_by_me=!1,n.like_count=Math.max(0,n.like_count-1)),this.applyState(e,n),e}async recordView(t){if(!t)return;await this.ensurePostsLoaded();let e=this.ensurePostState(t);e.view_count+=1;let n=this.postsById.get(t);n&&this.applyState(n,e)}async listLikes(t,e=25){await this.ensurePostsLoaded();let n=this.postStates.get(t),i=Math.max(0,Math.min(e,n?.like_count??0));if(!i)return[];let s=await this.fakeData.getProfiles();if(!s.length)return[];let o=D(w(`${t}|likes`)),r=new Set;for(;r.size<i&&r.size<s.length;)r.add(Math.floor(o()*s.length));let a=new Date().toISOString();return[...r].map(u=>{let l=s[u];return{user_id:l.user_id,created_at:a,user:this.profileToAuthor(l)}})}async likeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let n=this.ensureCommentState(t,e);return n.liked_by_me||(n.liked_by_me=!0,n.like_count+=1),e.liked_by_me=n.liked_by_me,e.like_count=n.like_count,e}async unlikeComment(t){await this.ensureCommentsLoaded();let e=this.findComment(t);if(!e)throw new Error("Comment not found.");let n=this.ensureCommentState(t,e);return n.liked_by_me&&(n.liked_by_me=!1,n.like_count=Math.max(0,n.like_count-1)),e.liked_by_me=n.liked_by_me,e.like_count=n.like_count,e}async ensurePostsLoaded(){if(!this.postsLoaded)return this.postsPromise?this.postsPromise:(this.postsPromise=(async()=>{await this.ensureCaptionsLoaded();let t=await this.fetchText(E),e=M(t),n=new Set;for(let i of e){let s=this.normalizeAuthorId(i?.author_id);s&&n.add(s)}await this.ensureProfileMap(n);for(let i of e){let s=this.normalizeAuthorId(i?.author_id);if(!i?.id||!s)continue;let o=this.profileMap?.get(s)??null,r=i.media?.type??"none",a=i.media?.url??null,u=i.media?.thumb_url??null,l=this.captionsByPost.get(i.id)??null,c=o?.country_code??i.country_code??null,h=o?.country_name??i.country_name??null,d=i.created_at||new Date().toISOString(),_={id:i.id,title:i.title??null,body:this.normalizeBody(i.body??"",h||i.country_name||null),media_type:r,media_url:a,thumb_url:u,media_caption:l,visibility:i.visibility||"public",like_count:0,comment_count:0,view_count:0,liked_by_me:!1,created_at:d,updated_at:d,author_id:s,country_name:h,country_code:c,city_name:null,author:o},g=this.seedCount(i.id,8e3),I=this.seedCount(`${i.id}|views`,18e4),v={like_count:g,comment_count:0,view_count:Math.max(I,g*6),liked_by_me:!1};this.postStates.set(i.id,v),this.applyState(_,v),this.posts.push(_),this.postsById.set(i.id,_);let p=String(c||"").trim().toUpperCase();if(p){let L=this.postsByCountry.get(p)??[];L.push(_),this.postsByCountry.set(p,L)}let C=this.postsByAuthor.get(s)??[];C.push(_),this.postsByAuthor.set(s,C),this.postMediaMeta.set(i.id,{type:r,query:i.media?.query??null,url:a,thumb_url:u})}this.postsLoaded=!0})(),this.postsPromise)}async ensureCommentsLoaded(){if(!this.commentsLoaded)return this.commentsPromise?this.commentsPromise:(this.commentsPromise=(async()=>{await this.ensurePostsLoaded();let t=await this.fetchText(j),e=M(t),n=new Set;for(let i of e){let s=this.normalizeAuthorId(i?.author_id);s&&n.add(s)}await this.ensureProfileMap(n);for(let i of e){let s=this.normalizeAuthorId(i?.author_id);if(!i?.id||!i?.post_id||!s)continue;let o=this.profileMap?.get(s)??null,r=i.created_at||new Date().toISOString(),a={id:i.id,post_id:i.post_id,parent_id:i.parent_id??null,author_id:s,body:i.body??"",like_count:this.seedCount(i.id,160),liked_by_me:!1,created_at:r,updated_at:r,author:o},u=this.commentsByPost.get(i.post_id)??[];u.push(a),this.commentsByPost.set(i.post_id,u),this.commentStates.set(i.id,{like_count:a.like_count,liked_by_me:!1});let l=this.postStates.get(i.post_id);l&&(l.comment_count+=1)}for(let[i,s]of this.postStates.entries()){let o=this.postsById.get(i);o&&(o.comment_count=s.comment_count)}this.commentsLoaded=!0})(),this.commentsPromise)}async ensureCaptionsLoaded(){if(!this.captionsLoaded)return this.captionsPromise?this.captionsPromise:(this.captionsPromise=(async()=>{let t=await this.fetchText(O),e=M(t);for(let n of e)!n?.post_id||!n?.caption||this.captionsByPost.set(n.post_id,n.caption);this.captionsLoaded=!0})(),this.captionsPromise)}async ensureProfileMap(t){if(!this.profileMap){let e=await this.fakeData.getProfiles(),n=new Map;for(let i of e)n.set(i.user_id,this.profileToAuthor(i));this.profileMap=n}if(t&&t.size){await this.fakeData.ensureProfilesById(t);for(let e of t){if(this.profileMap?.has(e))continue;let n=await this.fakeData.getProfileById(e);n&&this.profileMap?.set(e,this.profileToAuthor(n))}}}profileToAuthor(t){return{user_id:t.user_id,display_name:t.display_name??null,username:t.username??null,avatar_url:t.avatar_url??null,country_name:t.country_name??null,country_code:t.country_code??null}}applyState(t,e){t.like_count=e.like_count,t.comment_count=e.comment_count,t.view_count=e.view_count,t.liked_by_me=e.liked_by_me}ensurePostState(t){let e=this.postStates.get(t);return e||(e={like_count:0,comment_count:0,view_count:0,liked_by_me:!1},this.postStates.set(t,e)),e}ensureCommentState(t,e){let n=this.commentStates.get(t);return n||(n={like_count:e.like_count,liked_by_me:e.liked_by_me},this.commentStates.set(t,n)),n}findComment(t){for(let e of this.commentsByPost.values()){let n=e.find(i=>i.id===t);if(n)return n}for(let e of this.localCommentsByPost.values()){let n=e.find(i=>i.id===t);if(n)return n}return null}seedCount(t,e){let n=D(w(t));return Math.floor(Math.pow(n(),2)*e)}buildBalancedOrder(t,e){let n=Date.now(),i=Math.floor(n/(1e3*60*15)),s=`${e}:${i}`,o=this.countryFeedCache.get(s);if(o)return o.posts;let r=[...t].sort((d,_)=>new Date(_.created_at).getTime()-new Date(d.created_at).getTime()),a=new Map;for(let d of r){let _=a.get(d.author_id)??[];_.push(d),a.set(d.author_id,_)}let u=Array.from(a.keys()),l=D(w(`${e}|${i}`));for(let d=u.length-1;d>0;d-=1){let _=Math.floor(l()*(d+1)),g=u[d];u[d]=u[_],u[_]=g}let c=[],h=!0;for(;h;){h=!1;for(let d of u){let _=a.get(d);!_||!_.length||(c.push(_.shift()),h=!0)}}return this.countryFeedCache.set(s,{ts:n,posts:c}),c}sliceWithOffset(t,e,n){if(!e.length)return[];if(e.length<=n)return[...e];let s=(this.countryOffsets.get(t)??0)%e.length,o=s+n,r=(s+n)%e.length;if(this.countryOffsets.set(t,r),o<=e.length)return e.slice(s,o);let a=e.slice(s),u=e.slice(0,o-e.length);return[...a,...u]}normalizeBody(t,e){let n=String(t||"").trim();if(!n)return"";let i=n,s=/^in\s+[A-Za-z][^,.:;-]{1,60}[,.:;-]\s*/i;if(i=i.replace(s,"").trim(),!i||!e)return i;let o=e.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),r=new RegExp(`^In\\s+${o}\\b[\\s,.-]*`,"i");return i.replace(r,"").trim()}getOrderedComments(t){let e=this.commentOrderCache.get(t);if(e)return e;let n=this.commentsByPost.get(t)??[];if(!n.length)return this.commentOrderCache.set(t,[]),[];let i=[],s=new Set;for(let r of n){let a=`${r.author_id}|${this.normalizeCommentBody(r.body)}`;s.has(a)||(s.add(a),i.push(r))}let o=D(w(`${t}|comments`));for(let r=i.length-1;r>0;r-=1){let a=Math.floor(o()*(r+1)),u=i[r];i[r]=i[a],i[a]=u}return this.commentOrderCache.set(t,i),i}normalizeCommentBody(t){return String(t||"").trim().toLowerCase().replace(/\s+/g," ")}normalizeAuthorId(t){let e=String(t||"").trim();if(!e)return null;let n=e.match(/^user_(\d+)$/i);if(!n)return e;let i=parseInt(n[1],10);return!Number.isFinite(i)||i<=0?e:`user_${String(i).padStart(6,"0")}`}resolveAssetUrl(t){let e=document.querySelector("base")?.getAttribute("href")??"/",n=new URL(e,window.location.origin).toString();return new URL(t,n).toString()}async fetchText(t){if(typeof window>"u"||typeof document>"u")return"";let e=this.resolveAssetUrl(t),n=await fetch(e);if(!n.ok)throw new Error(`Failed to load ${t}: ${n.status}`);return n.text()}async hydrateMedia(t){if(!y.pexelsApiKey)return;let e=t.map(async n=>{if(!n||n.media_type==="none"||n.media_url)return;let i=this.postMediaMeta.get(n.id);if(!i||!i.query)return;let s=`${i.type}:${i.query}`.toLowerCase(),o=this.pexelsCache.get(s);if(o){n.media_url=o.url,n.thumb_url=o.thumb_url;return}let r=this.pexelsInflight.get(s);if(r){let l=await r;n.media_url=l.url,n.thumb_url=l.thumb_url;return}let a=this.fetchPexels(i.type,i.query);this.pexelsInflight.set(s,a);let u=await a;this.pexelsInflight.delete(s),this.pexelsCache.set(s,u),n.media_url=u.url,n.thumb_url=u.thumb_url});await Promise.all(e)}async fetchPexels(t,e){let n=y.pexelsApiKey||"";if(!n)return{url:null,thumb_url:null};let i={Authorization:n};if(t==="video"){let l=`https://api.pexels.com/videos/search?query=${encodeURIComponent(e)}&per_page=1`,c=await fetch(l,{headers:i});if(!c.ok)return{url:null,thumb_url:null};let d=(await c.json())?.videos?.[0];if(!d)return{url:null,thumb_url:null};let g=(Array.isArray(d.video_files)?d.video_files:[]).filter(p=>String(p?.file_type||"").toLowerCase()==="video/mp4").sort((p,C)=>(p?.width??0)-(C?.width??0)),I=g.find(p=>(p?.width??0)>=720)||g[0],v=d.video_pictures?.[0]?.picture||d.image||null;return{url:I?.link??null,thumb_url:v}}let s=`https://api.pexels.com/v1/search?query=${encodeURIComponent(e)}&per_page=1`,o=await fetch(s,{headers:i});if(!o.ok)return{url:null,thumb_url:null};let u=(await o.json())?.photos?.[0]?.src||{};return{url:u?.large??u?.medium??null,thumb_url:u?.medium??null}}static \u0275fac=function(e){return new(e||m)(P(x))};static \u0275prov=b({token:m,factory:m.\u0275fac,providedIn:"root"})};var z="https://api.dicebear.com/7.x/identicon/svg?seed=",U=class m{constructor(t,e,n){this.gql=t;this.postEvents=e;this.demoData=n}async listByCountry(t,e=25,n){if(y.useDemoDataset){let o=n?.demoLimit??1e3,r=Math.max(e,o),[a,u]=await Promise.allSettled([this.withTimeout(this.gql.request(`
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
          `,{code:t,limit:r}),1600,"postsByCountry"),this.demoData.listByCountry(t,r,{skipComments:n?.skipComments})]),l=a.status==="fulfilled"?(a.value.postsByCountry??[]).map(h=>this.mapPost(h)):[],c=u.status==="fulfilled"?u.value:[];return this.mergePosts(l,c,r)}let i=`
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
    `,{postsByCountry:s}=await this.gql.request(i,{code:t,limit:e});return(s??[]).map(o=>this.mapPost(o))}async listForAuthor(t,e=25){if(!t)return[];if(y.useDemoDataset&&/^user_/.test(t))return this.demoData.listForAuthor(t,e);let n=`
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
    `,{postsByAuthor:i}=await this.gql.request(n,{authorId:t,limit:e});return(i??[]).map(s=>this.mapPost(s))}async searchPosts(t,e=25){let n=String(t||"").trim();if(!n)return[];let i=`
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
    `;try{let{searchPosts:s}=await this.gql.request(i,{query:n,limit:e});return(s??[]).map(o=>this.mapPost(o))}catch{return[]}}async getPostById(t){if(!t)return null;if(y.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.getPostById(t);let e=`
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
    `,n={title:t.title?.trim()||null,body:t.body.trim(),country_name:t.countryName,country_code:t.countryCode,city_name:t.cityName??null,visibility:t.visibility??null,media_type:t.mediaType??null,media_url:t.mediaUrl??null,thumb_url:t.thumbUrl??null,shared_post_id:t.sharedPostId??null},{createPost:i}=await this.gql.request(e,{input:n}),s=this.mapPost(i);return this.postEvents.emit(s),s}async updatePost(t,e){let n=`
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
    `,i={title:e.title?.trim()??null,body:e.body?.trim()??null,visibility:e.visibility??null},{updatePost:s}=await this.gql.request(n,{postId:t,input:i}),o=this.mapPost(s);return this.postEvents.emitUpdated(o),o}async deletePost(t,e){let n=`
      mutation DeletePost($postId: ID!) {
        deletePost(post_id: $postId)
      }
    `,{deletePost:i}=await this.gql.request(n,{postId:t});return i&&this.postEvents.emitDeleted({id:t,country_code:e?.country_code??null,author_id:e?.author_id??null}),i}async likePost(t){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t)){let s=await this.demoData.likePost(t);return this.postEvents.emitUpdated(s),s}let e=`
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
    `,{likePost:n}=await this.gql.request(e,{postId:t}),i=this.mapPost(n);return this.postEvents.emitUpdated(i),i}async unlikePost(t){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t)){let s=await this.demoData.unlikePost(t);return this.postEvents.emitUpdated(s),s}let e=`
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
    `,{unlikePost:n}=await this.gql.request(e,{postId:t}),i=this.mapPost(n);return this.postEvents.emitUpdated(i),i}async recordView(t){if(t?.id){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t.id)){await this.demoData.recordView(t.id);return}t.view_count=Number(t.view_count??0)+1}}async listComments(t,e=25,n){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t)){let o=Math.max(e,1e3);return this.demoData.listComments(t,o)}let i=`
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
    `,{commentsByPost:s}=await this.gql.request(i,{postId:t,limit:e,before:n??null});return(s??[]).map(o=>this.mapComment(o))}async listLikes(t,e=25){if(!t)return[];if(y.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.listLikes(t,e);let n=`
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
    `,{postLikes:i}=await this.gql.request(n,{postId:t,limit:e});return(i??[]).map(s=>this.mapLike(s))}async addComment(t,e,n){if(y.useDemoDataset&&await this.demoData.isDemoPostId(t))return this.demoData.addComment(t,e,n??null);let i=`
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
    `,{addComment:s}=await this.gql.request(i,{postId:t,body:e.trim(),parentId:n??null});return this.mapComment(s)}async likeComment(t){if(y.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.likeComment(t);let e=`
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
    `,{likeComment:n}=await this.gql.request(e,{commentId:t});return this.mapComment(n)}async unlikeComment(t){if(y.useDemoDataset&&this.demoData.isDemoCommentId(t))return this.demoData.unlikeComment(t);let e=`
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
    `,{unlikeComment:n}=await this.gql.request(e,{commentId:t});return this.mapComment(n)}async reportPost(t,e){let n=`
      mutation ReportPost($postId: ID!, $reason: String!) {
        reportPost(post_id: $postId, reason: $reason)
      }
    `,{reportPost:i}=await this.gql.request(n,{postId:t,reason:e.trim()});return!!i}mapPost(t,e=0){let n=t?.view_count!=null?Number(t.view_count):this.estimateViewCount(t?.id,t?.like_count,t?.comment_count),i=t?.shared_post&&e<1?this.mapPost(t.shared_post,e+1):null;return{id:t.id,title:t.title??null,body:t.body??"",media_type:t.media_type??"none",media_url:t.media_url??null,thumb_url:t.thumb_url??null,media_caption:t.media_caption??null,shared_post_id:t.shared_post_id??null,shared_post:i,visibility:t.visibility??"public",like_count:Number(t.like_count??0),comment_count:Number(t.comment_count??0),view_count:n,liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author_id:t.author_id,country_name:t.country_name??null,country_code:t.country_code??null,city_name:t.city_name??null,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null,external_ref_type:t.external_ref_type??null,external_ref_id:t.external_ref_id??null,link_url:t.link_url??null,link_title:t.link_title??null,link_source_name:t.link_source_name??null,link_published_at:t.link_published_at??null,link_image_url:t.link_image_url??null,link_snippet:t.link_snippet??null}}mapComment(t){return{id:t.id,post_id:t.post_id,parent_id:t.parent_id??null,author_id:t.author_id,body:t.body??"",like_count:Number(t.like_count??0),liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:this.resolveAvatarUrl(t.author.avatar_url,t.author.user_id,t.author.username),country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapLike(t){return{user_id:t.user_id,created_at:t.created_at,user:t.user?{user_id:t.user.user_id,display_name:t.user.display_name,username:t.user.username,avatar_url:this.resolveAvatarUrl(t.user.avatar_url,t.user.user_id,t.user.username),country_name:t.user.country_name,country_code:t.user.country_code}:null}}resolveAvatarUrl(t,e,n){let i=this.normalizeAvatarUrl(t);if(i)return i;let s=String(n||e||"").trim();return s?`${z}${encodeURIComponent(s)}`:""}normalizeAvatarUrl(t){let e=String(t||"").trim();if(!e)return"";if(e.startsWith("data:")||e.startsWith("blob:")||e.startsWith("/"))return e;let n=e.match(/\/storage\/v1\/object\/(?:sign|public)\/avatars\/([^?#]+)/i);if(n?.[1]){let s=decodeURIComponent(n[1]).replace(/^\/+/,"");return`${B}/storage/v1/object/public/avatars/${s}`}if(/^https?:\/\//i.test(e))return e;let i=e.replace(/^\/+/,"");return`${B}/storage/v1/object/public/avatars/${i}`}mergePosts(t,e,n){let i=[...t,...e],s=new Set,o=[];for(let r of i)!r?.id||s.has(r.id)||(s.add(r.id),o.push(r));if(t.length){let r=new Set(t.map(l=>l.id)),a=t.filter(l=>r.has(l.id)).sort((l,c)=>new Date(c.created_at).getTime()-new Date(l.created_at).getTime()),u=o.filter(l=>!r.has(l.id));return[...a,...u].slice(0,Math.max(1,n))}return o.sort((r,a)=>new Date(a.created_at).getTime()-new Date(r.created_at).getTime()).slice(0,Math.max(1,n))}estimateViewCount(t,e,n){let i=Number(e??0),s=Number(n??0);if(!i&&!s)return 0;let r=this.hashSeed(String(t||"post"))%1200,a=i*12+s*6+r;return Math.max(a,i+s)}hashSeed(t){let e=2166136261;for(let n=0;n<t.length;n++)e^=t.charCodeAt(n),e=Math.imul(e,16777619);return e>>>0}async withTimeout(t,e,n){let i=null;try{return await Promise.race([t,new Promise((s,o)=>{i=setTimeout(()=>o(new Error(`${n} timeout`)),e)})])}finally{i&&clearTimeout(i)}}static \u0275fac=function(e){return new(e||m)(P(q),P(S),P($))};static \u0275prov=b({token:m,factory:m.\u0275fac,providedIn:"root"})};export{S as a,U as b};
