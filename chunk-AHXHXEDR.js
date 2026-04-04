import{a as L,b as W,e as G,o as H,p as Y}from"./chunk-ODV6P57G.js";import{b as J}from"./chunk-USDJHKJZ.js";import"./chunk-EKSI37KS.js";import{a as A}from"./chunk-L63J6I6F.js";import"./chunk-LQQHCQP3.js";import"./chunk-6RHINBXE.js";import{C,D as o,Da as V,Fa as z,G as x,H as T,Ia as R,Ka as j,L as _,P as l,Q as a,R as r,S as h,Y as I,Z as f,_ as c,ca as D,ea as q,fa as m,ga as d,ha as w,ia as N,ja as k,k as O,ka as E,la as P,n as $,p as u,q as g,qa as S,ra as M,ta as B,ya as F,za as U}from"./chunk-5NOU33V4.js";import{a as v,b}from"./chunk-2NFLSA4Y.js";var y=class n{constructor(t){this.gql=t}async countryConflictUpdates(t,e=10,i=0){let s=`
      query CountryConflictUpdates($country_code: String!, $limit: Int, $offset: Int) {
        countryConflictUpdates(country_code: $country_code, limit: $limit, offset: $offset) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{countryConflictUpdates:p}=await this.gql.request(s,{country_code:t,limit:e,offset:i});return p??[]}async globalConflictUpdates(t=10,e=0){let i=`
      query GlobalConflictUpdates($limit: Int, $offset: Int) {
        globalConflictUpdates(limit: $limit, offset: $offset) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{globalConflictUpdates:s}=await this.gql.request(i,{limit:t,offset:e});return s??[]}async item(t){let e=`
      query ExternalNewsItem($news_item_id: ID!) {
        externalNewsItem(news_item_id: $news_item_id) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{externalNewsItem:i}=await this.gql.request(e,{news_item_id:t});return i??null}async comments(t,e=25,i){let s=`
      query ExternalNewsComments($news_item_id: ID!, $limit: Int, $before: String) {
        externalNewsComments(news_item_id: $news_item_id, limit: $limit, before: $before) {
          id
          news_item_id
          parent_id
          author_id
          body
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
    `,{externalNewsComments:p}=await this.gql.request(s,{news_item_id:t,limit:e,before:i??null});return p??[]}async addComment(t,e,i){let s=`
      mutation AddExternalNewsComment($news_item_id: ID!, $body: String!, $parent_id: ID) {
        addExternalNewsComment(news_item_id: $news_item_id, body: $body, parent_id: $parent_id) {
          id
          news_item_id
          parent_id
          author_id
          body
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
    `,{addExternalNewsComment:p}=await this.gql.request(s,{news_item_id:t,body:String(e??"").trim(),parent_id:i??null});return p}async shareToCountry(t,e){let i=`
      mutation ShareExternalNewsToCountry($news_item_id: ID!, $body: String, $visibility: String) {
        shareExternalNewsToCountry(news_item_id: $news_item_id, body: $body, visibility: $visibility) {
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
    `,{shareExternalNewsToCountry:s}=await this.gql.request(i,{news_item_id:t,body:e??null,visibility:"country"});return s}async like(t){let e=`
      mutation LikeExternalNews($news_item_id: ID!) {
        likeExternalNews(news_item_id: $news_item_id) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{likeExternalNews:i}=await this.gql.request(e,{news_item_id:t});return i}async unlike(t){let e=`
      mutation UnlikeExternalNews($news_item_id: ID!) {
        unlikeExternalNews(news_item_id: $news_item_id) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          like_count
          liked_by_me
          comment_count
          shared_post_count
        }
      }
    `,{unlikeExternalNews:i}=await this.gql.request(e,{news_item_id:t});return i}static \u0275fac=function(e){return new(e||n)($(A))};static \u0275prov=O({token:n,factory:n.\u0275fac,providedIn:"root"})};function Z(n,t){n&1&&(a(0,"div",6),m(1,"Loading news..."),r())}function ee(n,t){if(n&1&&(a(0,"div",7),m(1),r()),n&2){let e=c();o(),d(e.error)}}function te(n,t){if(n&1&&(a(0,"span",28),m(1),r()),n&2){let e=t.$implicit;o(),d(e)}}function ne(n,t){if(n&1&&(a(0,"span",28),m(1),r()),n&2){let e=t.$implicit;o(),d(e)}}function ie(n,t){if(n&1&&(a(0,"div",26),_(1,te,2,1,"span",27)(2,ne,2,1,"span",27),r()),n&2){let e=c().ngIf;o(),l("ngForOf",e.theme_names.slice(0,3)),o(),l("ngForOf",e.disaster_types.slice(0,3))}}function oe(n,t){if(n&1&&(a(0,"div",29),h(1,"img",30),r()),n&2){let e=c().ngIf;o(),l("src",e.image_url,C)("alt",e.title)}}function re(n,t){if(n&1&&(a(0,"div",31),m(1),r()),n&2){let e=c().ngIf;o(),d(e.snippet)}}function ae(n,t){if(n&1&&(a(0,"div",32),m(1),r()),n&2){let e=c().ngIf;o(),w(" ",e.country_names.join(" \u2022 ")," ")}}function se(n,t){if(n&1&&(a(0,"div",33),m(1),r()),n&2){let e=c(2);o(),d(e.shareFeedback)}}function me(n,t){if(n&1&&(a(0,"article",40)(1,"div",41)(2,"span",42),m(3),r(),a(4,"span",43),m(5),S(6,"date"),r()(),a(7,"div",44),m(8),r()()),n&2){let e=t.$implicit;o(3),d((e.author==null?null:e.author.display_name)||(e.author==null?null:e.author.username)||"Member"),o(2),d(M(6,3,e.created_at,"mediumDate")),o(3),d(e.body)}}function le(n,t){if(n&1&&(a(0,"div",38),_(1,me,9,6,"article",39),r()),n&2){let e=c(3);o(),l("ngForOf",e.comments)}}function ce(n,t){n&1&&(a(0,"div",45),m(1,"No comments yet."),r())}function de(n,t){if(n&1&&(a(0,"div",46),m(1),r()),n&2){let e=c(3);o(),d(e.commentError)}}function pe(n,t){if(n&1){let e=I();a(0,"div",34)(1,"div",21),m(2,"Comments"),r(),_(3,le,2,1,"div",35)(4,ce,2,0,"ng-template",null,0,B),a(6,"textarea",36),P("ngModelChange",function(s){u(e);let p=c(2);return E(p.commentDraft,s)||(p.commentDraft=s),g(s)}),r(),a(7,"button",23),f("click",function(){u(e);let s=c(2);return g(s.submitComment())}),m(8),r(),_(9,de,2,1,"div",37),r()}if(n&2){let e=D(5),i=c(2);o(3),l("ngIf",i.comments.length)("ngIfElse",e),o(3),k("ngModel",i.commentDraft),o(),l("disabled",i.commentBusy),o(),w(" ",i.commentBusy?"Posting...":"Post comment"," "),o(),l("ngIf",i.commentError)}}function _e(n,t){if(n&1){let e=I();a(0,"div",6)(1,"div",8)(2,"span",9),m(3),r(),a(4,"span",10),m(5),S(6,"date"),r()(),a(7,"div",11),m(8),r(),_(9,ie,3,2,"div",12)(10,oe,2,2,"div",13)(11,re,2,1,"div",14)(12,ae,2,1,"div",15),a(13,"div",16)(14,"button",17),f("click",function(){u(e);let s=c();return g(s.toggleLike())}),m(15),r(),a(16,"button",18),f("click",function(){u(e);let s=c();return g(s.toggleComments())}),m(17),r(),a(18,"a",19),m(19,"Go to source"),r()(),a(20,"div",20)(21,"div",21),m(22,"Share This News To Your Feed"),r(),a(23,"textarea",22),P("ngModelChange",function(s){u(e);let p=c();return E(p.shareDraft,s)||(p.shareDraft=s),g(s)}),r(),a(24,"button",23),f("click",function(){u(e);let s=c();return g(s.shareToFeed())}),m(25),r(),_(26,se,2,1,"div",24),r(),_(27,pe,10,6,"div",25),r()}if(n&2){let e=t.ngIf,i=c();o(3),d(e.source_name||"ReliefWeb"),o(2),d(e.published_at?M(6,20,e.published_at,"medium"):""),o(3),d(e.title),o(),l("ngIf",e.theme_names.length||e.disaster_types.length),o(),l("ngIf",e.image_url),o(),l("ngIf",e.snippet),o(),l("ngIf",e.country_names.length),o(2),q("active",e.liked_by_me),l("disabled",i.likeBusy),o(),N(" ",e.liked_by_me?"Unlike":"Like"," \xB7 ",e.like_count," "),o(2),N(" ",i.commentsOpen?"Hide comments":"Comments"," \xB7 ",e.comment_count," "),o(),l("href",i.sourceUrl(e),C),o(5),k("ngModel",i.shareDraft),o(),l("disabled",i.shareBusy),o(),w(" ",i.shareBusy?"Sharing...":"Share to country feed"," "),o(),l("ngIf",i.shareFeedback),o(),l("ngIf",i.commentsOpen)}}var K=class n{constructor(t,e,i){this.route=t;this.router=e;this.newsService=i}item=null;comments=[];loading=!0;error="";commentsOpen=!0;commentDraft="";commentBusy=!1;commentError="";shareDraft="";shareBusy=!1;shareFeedback="";likeBusy=!1;routeSub;ngOnInit(){this.routeSub=this.route.paramMap.subscribe(t=>{let e=String(t.get("id")??"").trim();this.loadArticle(e)})}ngOnDestroy(){this.routeSub?.unsubscribe()}goHome(){this.router.navigateByUrl("/globe")}async loadComments(){this.item&&(this.comments=await this.newsService.comments(this.item.id))}getRouteStateItem(t){let e=history.state?.newsItem;return e?.id===t?e:null}async loadArticle(t){if(this.error="",this.comments=[],this.commentDraft="",this.commentError="",this.shareFeedback="",!t){this.item=null,this.loading=!1,this.error="News item not found.";return}let e=this.getRouteStateItem(t);e?(this.item=e,this.loading=!1,this.loadComments().catch(()=>{})):(this.item=null,this.loading=!0);try{let i=await this.newsService.item(t);if(!i){this.item=null,this.error="News item not found.";return}this.item=i,await this.loadComments()}catch(i){this.item||(this.error=i?.message??"Failed to load this news item.")}finally{this.loading=!1}}toggleComments(){this.commentsOpen=!this.commentsOpen}async submitComment(){if(!this.item||this.commentBusy)return;let t=this.commentDraft.trim();if(t){this.commentBusy=!0,this.commentError="";try{let e=await this.newsService.addComment(this.item.id,t);this.comments=[...this.comments,e],this.commentDraft="",this.item=b(v({},this.item),{comment_count:(this.item.comment_count??0)+1})}catch(e){this.commentError=e?.message??"Failed to post comment."}finally{this.commentBusy=!1}}}async toggleLike(){if(!(!this.item||this.likeBusy)){this.likeBusy=!0;try{this.item=this.item.liked_by_me?await this.newsService.unlike(this.item.id):await this.newsService.like(this.item.id)}catch(t){this.error=t?.message??"Failed to update like."}finally{this.likeBusy=!1}}}async shareToFeed(){if(!(!this.item||this.shareBusy)){this.shareBusy=!0,this.shareFeedback="";try{await this.newsService.shareToCountry(this.item.id,this.shareDraft.trim()||null),this.shareDraft="",this.item=b(v({},this.item),{shared_post_count:(this.item.shared_post_count??0)+1}),this.shareFeedback="Shared to your country feed."}catch(t){this.shareFeedback=t?.message??"Failed to share."}finally{this.shareBusy=!1}}}sourceUrl(t){let e=String(t?.url??"").trim();return/^https?:\/\/api\.reliefweb\.int\/v2\/reports\b/i.test(e)&&t?.provider_item_id?`https://reliefweb.int/node/${encodeURIComponent(t.provider_item_id)}`:e||(t?.provider==="reliefweb"&&t?.provider_item_id?`https://reliefweb.int/node/${encodeURIComponent(t.provider_item_id)}`:"#")}static \u0275fac=function(e){return new(e||n)(x(R),x(j),x(y))};static \u0275cmp=T({type:n,selectors:[["app-news-page"]],decls:7,vars:3,consts:[["noComments",""],[1,"news-shell"],["type","button",1,"logo-btn",3,"click"],["src","/logo.png","alt","Matterya"],["class","news-card",4,"ngIf"],["class","news-card error",4,"ngIf"],[1,"news-card"],[1,"news-card","error"],[1,"news-kicker-row"],[1,"news-kicker"],[1,"news-date"],[1,"news-title"],["class","news-tags",4,"ngIf"],["class","news-media",4,"ngIf"],["class","news-summary",4,"ngIf"],["class","news-country-line",4,"ngIf"],[1,"news-actions"],["type","button",1,"action",3,"click","disabled"],["type","button",1,"action",3,"click"],["target","_blank","rel","noreferrer",1,"action","source",3,"href"],[1,"share-panel"],[1,"panel-title"],["rows","3","maxlength","5000","placeholder","Add your caption before sharing...",1,"panel-input",3,"ngModelChange","ngModel"],["type","button",1,"panel-button",3,"click","disabled"],["class","panel-message",4,"ngIf"],["class","comment-panel",4,"ngIf"],[1,"news-tags"],["class","tag",4,"ngFor","ngForOf"],[1,"tag"],[1,"news-media"],[3,"src","alt"],[1,"news-summary"],[1,"news-country-line"],[1,"panel-message"],[1,"comment-panel"],["class","comment-list",4,"ngIf","ngIfElse"],["rows","3","maxlength","5000","placeholder","Add a comment...",1,"panel-input",3,"ngModelChange","ngModel"],["class","panel-message error",4,"ngIf"],[1,"comment-list"],["class","comment",4,"ngFor","ngForOf"],[1,"comment"],[1,"comment-head"],[1,"comment-author"],[1,"comment-date"],[1,"comment-body"],[1,"comment-empty"],[1,"panel-message","error"]],template:function(e,i){e&1&&(a(0,"div",1)(1,"button",2),f("click",function(){return i.goHome()}),h(2,"img",3),r(),_(3,Z,2,0,"div",4)(4,ee,2,1,"div",5)(5,_e,28,23,"div",4),r(),h(6,"app-bottom-tabs")),e&2&&(o(3),l("ngIf",i.loading),o(),l("ngIf",!i.loading&&i.error),o(),l("ngIf",!i.loading&&i.item))},dependencies:[z,F,U,Y,L,W,H,G,J,V],styles:["[_nghost-%COMP%]{display:block;min-height:100dvh;background:#eef2f5;color:#16191f}.news-shell[_ngcontent-%COMP%]{height:100dvh;overflow-y:auto;overflow-x:hidden;min-height:100dvh;padding:92px 18px calc(24px + var(--tabs-safe, 64px));display:flex;flex-direction:column;align-items:center;gap:18px}.logo-btn[_ngcontent-%COMP%]{position:fixed;top:18px;left:18px;width:48px;height:48px;border:0;border-radius:50%;background:#ffffffe6;box-shadow:0 12px 30px #1018281f;display:grid;place-items:center;cursor:pointer;z-index:10}.logo-btn[_ngcontent-%COMP%]   img[_ngcontent-%COMP%]{width:40px;height:40px;object-fit:contain}.news-card[_ngcontent-%COMP%]{width:min(780px,100%);background:#fff;border-radius:28px;padding:22px;box-shadow:0 20px 55px #11182714}.news-card.error[_ngcontent-%COMP%], .panel-message.error[_ngcontent-%COMP%]{color:#b42318}.news-kicker-row[_ngcontent-%COMP%]{display:flex;justify-content:space-between;gap:12px;font-size:12px;color:#667085;margin-bottom:10px}.news-kicker[_ngcontent-%COMP%]{font-weight:800;letter-spacing:.08em;text-transform:uppercase}.news-title[_ngcontent-%COMP%]{font-size:clamp(28px,3vw,42px);line-height:1.05;font-weight:900;letter-spacing:-.04em;margin-bottom:14px}.news-tags[_ngcontent-%COMP%]{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px}.tag[_ngcontent-%COMP%]{padding:6px 10px;border-radius:999px;background:#eef2f6;color:#344054;font-size:12px;font-weight:700}.news-media[_ngcontent-%COMP%]{border-radius:22px;overflow:hidden;margin-bottom:16px;background:#d9dde3}.news-media[_ngcontent-%COMP%]   img[_ngcontent-%COMP%]{width:100%;display:block;object-fit:cover}.news-summary[_ngcontent-%COMP%]{font-size:16px;line-height:1.7;color:#344054;margin-bottom:14px}.news-country-line[_ngcontent-%COMP%]{color:#475467;font-size:13px;margin-bottom:18px}.news-actions[_ngcontent-%COMP%]{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:20px}.action[_ngcontent-%COMP%]{border:1px solid #d0d5dd;background:#fff;color:#101828;border-radius:999px;padding:10px 14px;font-weight:700;cursor:pointer;text-decoration:none}.action.active[_ngcontent-%COMP%]{background:#101828;color:#fff}.share-panel[_ngcontent-%COMP%], .comment-panel[_ngcontent-%COMP%]{border-top:1px solid #eaecf0;padding-top:18px;margin-top:18px}.panel-title[_ngcontent-%COMP%]{font-size:13px;font-weight:900;letter-spacing:.08em;text-transform:uppercase;margin-bottom:10px;color:#475467}.panel-input[_ngcontent-%COMP%]{width:100%;border:1px solid #d0d5dd;border-radius:18px;padding:14px 16px;resize:vertical;font:inherit;box-sizing:border-box;background:#fff}.panel-button[_ngcontent-%COMP%]{margin-top:10px;border:0;border-radius:999px;background:#101828;color:#fff;padding:12px 18px;font-weight:800;cursor:pointer}.panel-message[_ngcontent-%COMP%]{margin-top:10px;font-size:13px;color:#475467}.comment-list[_ngcontent-%COMP%]{display:grid;gap:12px;margin-bottom:14px}.comment[_ngcontent-%COMP%]{padding:14px 16px;border-radius:18px;background:#f8fafc}.comment-head[_ngcontent-%COMP%]{display:flex;justify-content:space-between;gap:10px;margin-bottom:6px;font-size:12px;color:#667085}.comment-author[_ngcontent-%COMP%]{font-weight:800;color:#101828}.comment-body[_ngcontent-%COMP%]{color:#344054;line-height:1.6}.comment-empty[_ngcontent-%COMP%]{color:#667085;margin-bottom:14px}"]})};export{K as NewsPageComponent};
