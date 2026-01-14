import{a as d}from"./chunk-QGWRKH4Y.js";import{Ca as _,e as l,l as s,o as u}from"./chunk-EMTWPIOC.js";var g=`
mutation DetectLocation($lat: Float!, $lng: Float!) {
  detectLocation(lat: $lat, lng: $lng) {
    countryCode
    countryName
    cityName
    source
  }
}
`,y=class r{constructor(t){this.gql=t}async detectViaGpsThenServer(t=8e3){let e=await this.getBrowserCoords(t);return e?(await this.gql.request(g,{lat:e.lat,lng:e.lng})).detectLocation??null:null}getBrowserCoords(t){return new Promise(e=>{if(!("geolocation"in navigator))return e(null);let o=!1,n=a=>{o||(o=!0,e(a))},i=window.setTimeout(()=>n(null),t);navigator.geolocation.getCurrentPosition(a=>{clearTimeout(i),n({lat:a.coords.latitude,lng:a.coords.longitude})},()=>{clearTimeout(i),n(null)},{enableHighAccuracy:!1,timeout:t,maximumAge:6e4})})}static \u0275fac=function(e){return new(e||r)(u(d))};static \u0275prov=s({token:r,factory:r.\u0275fac,providedIn:"root"})};var c=class r{createdPostSubject=new l;createdPost$=this.createdPostSubject.asObservable();updatedPostSubject=new l;updatedPost$=this.updatedPostSubject.asObservable();insertSubject=new l;insert$=this.insertSubject.asObservable();updateSubject=new l;update$=this.updateSubject.asObservable();deleteSubject=new l;delete$=this.deleteSubject.asObservable();channel=_.channel("public:posts");constructor(){this.channel.on("postgres_changes",{event:"INSERT",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.insertSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"posts"},({new:t})=>{t?.id&&this.updateSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null,visibility:t.visibility??null})}).on("postgres_changes",{event:"DELETE",schema:"public",table:"posts"},({old:t})=>{t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}).subscribe()}emit(t){this.createdPostSubject.next(t)}emitUpdated(t){this.updatedPostSubject.next(t)}emitDeleted(t){t?.id&&this.deleteSubject.next({id:t.id,country_code:t.country_code??null,author_id:t.author_id??null})}ngOnDestroy(){this.channel?.unsubscribe()}static \u0275fac=function(e){return new(e||r)};static \u0275prov=s({token:r,factory:r.\u0275fac,providedIn:"root"})};var b=class r{constructor(t,e){this.gql=t;this.postEvents=e}async listByCountry(t,e=25){let o=`
      query PostsByCountry($code: String!, $limit: Int) {
        postsByCountry(country_code: $code, limit: $limit) {
          id
          title
          body
          media_type
          media_url
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
    `,{postsByCountry:n}=await this.gql.request(o,{code:t,limit:e});return(n??[]).map(i=>this.mapPost(i))}async listForAuthor(t,e=25){if(!t)return[];let o=`
      query PostsByAuthor($authorId: ID!, $limit: Int) {
        postsByAuthor(user_id: $authorId, limit: $limit) {
          id
          title
          body
          media_type
          media_url
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
    `,{postsByAuthor:n}=await this.gql.request(o,{authorId:t,limit:e});return(n??[]).map(i=>this.mapPost(i))}async getPostById(t){if(!t)return null;let e=`
      query PostById($postId: ID!) {
        postById(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
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
    `,o={title:t.title?.trim()||null,body:t.body.trim(),country_name:t.countryName,country_code:t.countryCode,city_name:t.cityName??null,visibility:t.visibility??null},{createPost:n}=await this.gql.request(e,{input:o}),i=this.mapPost(n);return this.postEvents.emit(i),i}async updatePost(t,e){let o=`
      mutation UpdatePost($postId: ID!, $input: UpdatePostInput!) {
        updatePost(post_id: $postId, input: $input) {
          id
          title
          body
          media_type
          media_url
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
    `,n={title:e.title?.trim()??null,body:e.body?.trim()??null,visibility:e.visibility??null},{updatePost:i}=await this.gql.request(o,{postId:t,input:n}),a=this.mapPost(i);return this.postEvents.emitUpdated(a),a}async deletePost(t,e){let o=`
      mutation DeletePost($postId: ID!) {
        deletePost(post_id: $postId)
      }
    `,{deletePost:n}=await this.gql.request(o,{postId:t});return n&&this.postEvents.emitDeleted({id:t,country_code:e?.country_code??null,author_id:e?.author_id??null}),n}async likePost(t){let e=`
      mutation LikePost($postId: ID!) {
        likePost(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
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
    `,{likePost:o}=await this.gql.request(e,{postId:t}),n=this.mapPost(o);return this.postEvents.emitUpdated(n),n}async unlikePost(t){let e=`
      mutation UnlikePost($postId: ID!) {
        unlikePost(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
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
    `,{unlikePost:o}=await this.gql.request(e,{postId:t}),n=this.mapPost(o);return this.postEvents.emitUpdated(n),n}async listComments(t,e=25,o){let n=`
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
    `,{commentsByPost:i}=await this.gql.request(n,{postId:t,limit:e,before:o??null});return(i??[]).map(a=>this.mapComment(a))}async listLikes(t,e=25){if(!t)return[];let o=`
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
    `,{postLikes:n}=await this.gql.request(o,{postId:t,limit:e});return(n??[]).map(i=>this.mapLike(i))}async addComment(t,e,o){let n=`
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
    `,{addComment:i}=await this.gql.request(n,{postId:t,body:e.trim(),parentId:o??null});return this.mapComment(i)}async likeComment(t){let e=`
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
    `,{likeComment:o}=await this.gql.request(e,{commentId:t});return this.mapComment(o)}async unlikeComment(t){let e=`
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
    `,{reportPost:n}=await this.gql.request(o,{postId:t,reason:e.trim()});return!!n}mapPost(t){return{id:t.id,title:t.title??null,body:t.body??"",media_type:t.media_type??"none",media_url:t.media_url??null,visibility:t.visibility??"public",like_count:Number(t.like_count??0),comment_count:Number(t.comment_count??0),liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author_id:t.author_id,country_name:t.country_name??null,country_code:t.country_code??null,city_name:t.city_name??null,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:t.author.avatar_url,country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapComment(t){return{id:t.id,post_id:t.post_id,parent_id:t.parent_id??null,author_id:t.author_id,body:t.body??"",like_count:Number(t.like_count??0),liked_by_me:!!t.liked_by_me,created_at:t.created_at,updated_at:t.updated_at??t.created_at,author:t.author?{user_id:t.author.user_id,display_name:t.author.display_name,username:t.author.username,avatar_url:t.author.avatar_url,country_name:t.author.country_name,country_code:t.author.country_code}:null}}mapLike(t){return{user_id:t.user_id,created_at:t.created_at,user:t.user?{user_id:t.user.user_id,display_name:t.user.display_name,username:t.user.username,avatar_url:t.user.avatar_url,country_name:t.user.country_name,country_code:t.user.country_code}:null}}static \u0275fac=function(e){return new(e||r)(u(d),u(c))};static \u0275prov=s({token:r,factory:r.\u0275fac,providedIn:"root"})};var h=class r{constructor(t){this.gql=t}async counts(t){let e=`
      query FollowCounts($userId: ID!) {
        followCounts(user_id: $userId) {
          followers
          following
        }
      }
    `,{followCounts:o}=await this.gql.request(e,{userId:t});return o??{followers:0,following:0}}async isFollowing(t,e){if(t===e)return!1;let o=`
      query IsFollowing($target: ID!) {
        isFollowing(user_id: $target)
      }
    `,{isFollowing:n}=await this.gql.request(o,{target:e});return!!n}async follow(t,e){if(t===e)return;await this.gql.request(`
      mutation FollowUser($target: ID!) {
        followUser(target_id: $target)
      }
    `,{target:e})}async unfollow(t,e){if(t===e)return;await this.gql.request(`
      mutation UnfollowUser($target: ID!) {
        unfollowUser(target_id: $target)
      }
    `,{target:e})}async listFollowingIds(t){let e=`
      query FollowingIds {
        followingIds
      }
    `,{followingIds:o}=await this.gql.request(e);return o??[]}static \u0275fac=function(e){return new(e||r)(u(d))};static \u0275prov=s({token:r,factory:r.\u0275fac,providedIn:"root"})};export{y as a,c as b,b as c,h as d};
