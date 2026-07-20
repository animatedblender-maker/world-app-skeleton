import{a as U}from"./chunk-7QOEYGCO.js";import{a as S}from"./chunk-O6EOGRYE.js";import{k as _,n as C}from"./chunk-KO2AEFNE.js";var L="https://api.dicebear.com/7.x/identicon/svg?seed=",E="fake_users_60k_real_names/fake_users_60k.jsonl",F="names-by-country.json";function g(c){let t=c>>>0;return()=>{t|=0,t=t+1831565813|0;let e=Math.imul(t^t>>>15,1|t);return e=e+Math.imul(e^e>>>7,61|e)^e,((e^e>>>14)>>>0)/4294967296}}function y(c){let t=2166136261;for(let e=0;e<c.length;e++)t^=c.charCodeAt(e),t=Math.imul(t,16777619);return t>>>0}function h(c){return String(c||"").toLowerCase().replace(/[^a-z0-9._]/g,"").replace(/^@+/,"").slice(0,24)}function I(c,t,e){return Math.max(t,Math.min(e,c))}function A(c,t){let e=[],n=c.split(/\r?\n/);for(let r of n){let i=r.trim();if(i){try{e.push(JSON.parse(i))}catch{}if(t&&e.length>=t)break}}return e}var w=class c{constructor(t){this.countriesService=t}COUNT=3e4;initialized=!1;initPromise=null;profiles=[];profilesById=new Map;profilesByUsername=new Map;searchIndex=[];countries=[];fakeUsersLoaded=!1;fakeUsersPromise=null;fakeUsers=[];fakeUsersById=new Map;cityPoolByCountry=new Map;fallbackCityPoolByCountry=new Map;cityPrimaryCountry=new Map;generatedCityPoolByCountry=new Map;countryGeoByCode=new Map;namesLoaded=!1;namesPromise=null;namesByCountry={};async ensureInitialized(t){if(!this.initialized)return this.initPromise?this.initPromise:(this.initPromise=(async()=>{let e=(t||[]).filter(s=>!!s.code);if(e.length)this.countries=e;else{let s=await this.countriesService.loadCountries();this.countries=(s.countries||[]).filter(l=>!!l.code)}this.countries.length||(this.countries=[{id:0,name:"World",norm:"world",center:{lat:0,lng:0},labelSize:.6,flyAltitude:1,code:"WW",pointPool:[{lat:0,lng:0}]}]),this.buildCountryGeoIndex(),await this.loadFakeUsers(),await this.loadNamesByCountry(),this.buildCityPools();let n=Date.now(),r=1e3*60*60*24*365*2,i=new Set;this.profiles=[],this.profilesById.clear(),this.profilesByUsername.clear(),this.searchIndex=[];let o=this.fakeUsers.length?this.fakeUsers:[],a=I(this.COUNT,1,o.length||1);for(let s=0;s<a;s++){let l=o[s]||{user_id:`user_${String(s+1).padStart(6,"0")}`},u=String(l.user_id||"").trim()||`user_${String(s+1).padStart(6,"0")}`,d=g(y(u)),f=new Date(n-Math.floor(d()*r)).toISOString(),m=this.resolveCountryCode(l.country_code,l.country),p=this.buildUsername(l,u,m),b=this.buildDisplayName(l,u,p,m,i),$=this.resolveCountryName(l.country,m),v=this.pickCityName(l,m,u),R=this.normalizeBio(l.bio,l.city,v),B=g(y(`${u}|follow`)),z=Math.floor(Math.pow(B(),2)*2e4),x=Math.floor(Math.pow(B(),2)*3200),P={user_id:u,email:null,display_name:b,username:p,avatar_url:`${L}${encodeURIComponent(p||u)}`,country_name:$||"Unknown",country_code:m,city_name:v,bio:R,followers_count:z,following_count:x,created_at:f,updated_at:f};this.profiles.push(P),this.profilesById.set(u,P),p&&this.profilesByUsername.set(p.toLowerCase(),P);let k=h(l.handle||"");k&&this.profilesByUsername.set(k.toLowerCase(),P),this.searchIndex.push({profile:P,username:(p||"").toLowerCase(),display:(b||"").toLowerCase()})}this.initialized=!0})(),this.initPromise)}buildUsername(t,e,n){let r=h(t.username||t.handle||"");if(r)return r;let i=this.pickNamePart(t.first_name,n,"first",y(`${e}|first`)),o=this.pickNamePart(t.last_name,n,"last",y(`${e}|last`));return h(`${i}.${o}`)||h(e)||h(e)}buildDisplayName(t,e,n,r,i){let o=this.pickNamePart(t.first_name,r,"first",y(`${e}|first`)),a=this.pickNamePart(t.last_name,r,"last",y(`${e}|last`)),s=`${o} ${a}`.trim();s||(s=n||e);let l=0;for(;i.has(s)&&l<4;)s=`${s} ${String(l+1)}`.trim(),l+=1;return i.add(s),s}normalizeCountryCode(t){return String(t||"").trim().toUpperCase()||null}normalizeCountryName(t){return String(t||"").trim().toLowerCase().replace(/\s+/g," ")}buildCountryGeoIndex(){this.countryGeoByCode.clear();for(let t of this.countries){let e=String(t.code||"").trim().toUpperCase();if(!e)continue;let n=Array.isArray(t.pointPool)?t.pointPool:[];if(!n.length)continue;let r=1/0,i=-1/0,o=1/0,a=-1/0;for(let s of n)s&&(r=Math.min(r,s.lat),i=Math.max(i,s.lat),o=Math.min(o,s.lng),a=Math.max(a,s.lng));!Number.isFinite(r)||!Number.isFinite(o)||this.countryGeoByCode.set(e,{center:t.center,points:n,minLat:r,maxLat:i,minLng:o,maxLng:a})}}resolveCountryCode(t,e){let n=this.normalizeCountryCode(t);if(n)return n;let r=this.normalizeCountryName(e);return r?this.countries.find(o=>this.normalizeCountryName(o.name)===r)?.code??null:null}resolveCountryName(t,e){let n=(t||"").trim(),r=this.normalizeCountryName(n),i=String(e||"").trim().toUpperCase();if(i){let o=this.countries.find(a=>String(a.code||"").toUpperCase()===i);return o?r&&this.normalizeCountryName(o.name)===r?n:o.name||n||null:n||null}return n||null}pickNamePart(t,e,n,r){let i=this.getNameList(e,n);if(i.length){if(Number.isFinite(r)){let a=g(r);return i[Math.floor(a()*i.length)]}return i[0]}let o=(t||"").trim();return o||""}getNameList(t,e){let n=String(t??"").trim().toUpperCase(),r=n&&this.namesByCountry[n]?.[e]||[];if(r&&r.length)return r;let i=this.namesByCountry.GLOBAL?.[e]||[];return i&&i.length?i:[]}buildCityPools(){let t=new Map,e=new Map;for(let i of this.fakeUsers){let o=this.resolveCountryCode(i.country_code,i.country),a=this.normalizeCityName(i.city);if(!o||!a||!this.isSaneCityName(a))continue;let s=t.get(o)??new Map;s.set(a,(s.get(a)??0)+1),t.set(o,s);let l=e.get(a)??new Map;l.set(o,(l.get(o)??0)+1),e.set(a,l)}this.cityPoolByCountry.clear(),this.fallbackCityPoolByCountry.clear(),this.cityPrimaryCountry.clear(),this.generatedCityPoolByCountry.clear();let n=new Map;for(let[i,o]of e.entries()){let a=Array.from(o.entries()).sort((f,m)=>m[1]-f[1]),[s,l]=a[0],u=a.reduce((f,m)=>f+m[1],0),d=u?l/u:0;if(this.cityPrimaryCountry.set(i,s),u>=3&&d>=.7){let f=n.get(s)??[];f.push({city:i,count:l}),n.set(s,f)}}let r=240;for(let[i,o]of n.entries()){let a=o.sort((s,l)=>l.count-s.count).slice(0,r).map(s=>s.city);this.cityPoolByCountry.set(i,a)}for(let[i,o]of t.entries()){let a=Array.from(o.entries()).sort((s,l)=>l[1]-s[1]).slice(0,r).map(([s])=>s);this.fallbackCityPoolByCountry.set(i,a)}for(let i of this.countries){let o=String(i.code||"").trim().toUpperCase();if(!o)continue;let a=this.generateMapCityPool(o);a.length&&this.generatedCityPoolByCountry.set(o,a)}}pickCityName(t,e,n){let r=String(e||"").trim().toUpperCase(),i=this.normalizeCityName(t.city),o=r?this.generatedCityPoolByCountry.get(r)??[]:[],a=r?o.length?o:this.cityPoolByCountry.get(r)??this.fallbackCityPoolByCountry.get(r)??[]:[];if(!a.length)return null;let s=g(y(`${n}|city`));return a[Math.floor(s()*a.length)]??null}normalizeCityName(t){return String(t||"").trim().replace(/\s+/g," ")}isSaneCityName(t){if(!t)return!1;let e=t.trim();return!e||e.length>48?!1:(e.match(/[A-Za-z0-9 .,'-]/g)?.length??0)/e.length>=.7}generateMapCityPool(t){let e=this.countryGeoByCode.get(t);if(!e||!e.points.length)return[];let n=g(y(`${t}|geo`)),r=new Set,i=Math.min(e.points.length*2,480);for(let o=0;o<i;o+=1){let a=Math.floor(n()*e.points.length),s=e.points[a];if(s&&(r.add(this.pickRegionLabel(e,s)),r.size>=12))break}return Array.from(r)}pickRegionLabel(t,e){let n=Math.max(.1,t.maxLat-t.minLat),r=Math.max(.1,t.maxLng-t.minLng),i=(e.lat-t.center.lat)/n,o=(e.lng-t.center.lng)/r,a=.18,s="",l="";if(i>a?s="North":i<-a&&(s="South"),o>a?l="East":o<-a&&(l="West"),!s&&!l)return"Central";if(s&&l){let u=`${s}-${l}`;return{"North-East":"Northeast","North-West":"Northwest","South-East":"Southeast","South-West":"Southwest"}[u]??`${s}${l}`}return s||l}normalizeBio(t,e,n){let r=String(t||"").trim();if(!r)return null;let i=r,o=this.normalizeCityName(e),a=this.normalizeCityName(n);if(o){let s=o.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),l=new RegExp(s,"gi");l.test(i)&&(i=i.replace(l,a||"").replace(/\s{2,}/g," ").trim())}return i=i.replace(/\s*(?:\u2022|\u00b7|[|.-])\s*$/g,"").trim(),i||null}async loadFakeUsers(){if(!this.fakeUsersLoaded)return this.fakeUsersPromise?this.fakeUsersPromise:(this.fakeUsersPromise=(async()=>{if(typeof window>"u"||typeof document>"u"){this.fakeUsers=[],this.fakeUsersLoaded=!0;return}try{let t=document.querySelector("base")?.getAttribute("href")??"/",e=new URL(t,window.location.origin).toString(),n=new URL(E,e).toString(),r=await fetch(n);if(!r.ok)throw new Error(`Failed to load fake users: ${r.status}`);let i=await r.text();this.fakeUsers=A(i,this.COUNT),this.fakeUsersById.clear();for(let o of this.fakeUsers)o?.user_id&&this.fakeUsersById.set(o.user_id,o);this.buildCityPools()}catch{this.fakeUsers=[],this.fakeUsersById.clear(),this.cityPoolByCountry.clear(),this.fallbackCityPoolByCountry.clear(),this.cityPrimaryCountry.clear(),this.generatedCityPoolByCountry.clear()}finally{this.fakeUsersLoaded=!0}})(),this.fakeUsersPromise)}async loadNamesByCountry(){if(!this.namesLoaded)return this.namesPromise?this.namesPromise:(this.namesPromise=(async()=>{if(typeof window>"u"||typeof document>"u"){this.namesByCountry={},this.namesLoaded=!0;return}try{let t=document.querySelector("base")?.getAttribute("href")??"/",e=new URL(t,window.location.origin).toString(),n=new URL(F,e).toString(),r=await fetch(n);if(!r.ok)throw new Error(`Failed to load names data: ${r.status}`);let i=await r.json();this.namesByCountry=i&&typeof i=="object"?i:{}}catch{this.namesByCountry={}}finally{this.namesLoaded=!0}})(),this.namesPromise)}async getProfiles(t){return await this.ensureInitialized(t),this.profiles}async getProfileById(t){await this.ensureInitialized();let e=this.profilesById.get(t);if(e)return e;let n=this.fakeUsersById.get(t);if(!n)return null;let r=this.resolveCountryCode(n.country_code,n.country),i=this.buildUsername(n,t,r),o=this.buildDisplayName(n,t,i,r,new Set),a=this.resolveCountryName(n.country,r),s=this.pickCityName(n,r,t),l=new Date().toISOString(),u=this.normalizeBio(n.bio,n.city,s),d=g(y(`${t}|follow`)),f={user_id:t,email:null,display_name:o,username:i,avatar_url:`${L}${encodeURIComponent(i||t)}`,country_name:a||"Unknown",country_code:r,city_name:s,bio:u,followers_count:Math.floor(Math.pow(d(),2)*2e4),following_count:Math.floor(Math.pow(d(),2)*3200),created_at:l,updated_at:l};return this.profilesById.set(t,f),i&&this.profilesByUsername.set(i.toLowerCase(),f),this.searchIndex.push({profile:f,username:(i||"").toLowerCase(),display:(o||"").toLowerCase()}),this.profiles.push(f),f}async ensureProfilesById(t){await this.ensureInitialized();for(let e of t)!e||this.profilesById.has(e)||!this.fakeUsersById.get(e)||await this.getProfileById(e)}async getProfileByUsername(t){await this.ensureInitialized();let e=h(t);return e?this.profilesByUsername.get(e)??null:null}async getFollowCounts(t){await this.ensureInitialized();let e=this.profilesById.get(t);return e?{followers:e.followers_count??0,following:e.following_count??0}:null}async searchProfiles(t,e=6){await this.ensureInitialized();let n=String(t||"").trim().toLowerCase(),r=h(t);if(!n&&!r)return[];let i=[];for(let a of this.searchIndex){let s=-1;r&&a.username.startsWith(r)?s=0:n&&a.display.startsWith(n)?s=1:(r&&a.username.includes(r)||n&&a.display.includes(n))&&(s=2),s!==-1&&i.push({score:s,profile:a.profile,username:a.username})}i.sort((a,s)=>a.score-s.score||a.username.localeCompare(s.username));let o=[];for(let a of i)if(o.push(a.profile),o.length>=I(e,1,50))break;return o}static \u0275fac=function(e){return new(e||c)(C(S))};static \u0275prov=_({token:c,factory:c.\u0275fac,providedIn:"root"})};var O=`
query Countries {
  countries {
    countries {
      id
      name
      iso
      continent
      center { lat lng }
    }
  }
}
`,G=`
query MeProfile {
  meProfile {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,j=`
mutation UpdateProfile($input: UpdateProfileInput!) {
  updateProfile(input: $input) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,T=`
query ProfileByUsername($username: String!) {
  profileByUsername(username: $username) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,W=`
query ProfileById($user_id: ID!) {
  profileById(user_id: $user_id) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,M=`
query SearchProfiles($query: String!, $limit: Int) {
  searchProfiles(query: $query, limit: $limit) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,H=`
query BrowseProfiles($limit: Int, $offset: Int) {
  browseProfiles(limit: $limit, offset: $offset) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`,N=class c{constructor(t,e){this.gql=t;this.fakeData=e}async countries(){return this.gql.request(O)}async meProfile(){return this.gql.request(G)}async updateProfile(t){return this.gql.request(j,{input:t})}async profileByUsername(t){let e=String(t||"").trim().replace(/^@/,"");if(!e)return{profileByUsername:null};try{let r=await this.gql.request(T,{username:e});if(r?.profileByUsername)return r}catch{}let n=await this.fakeData.getProfileByUsername(e);return n?{profileByUsername:n}:{profileByUsername:null}}async profileById(t){let e=String(t||"").trim();if(!e)return{profileById:null};try{let r=await this.gql.request(W,{user_id:e});if(r?.profileById)return r}catch{}let n=await this.fakeData.getProfileById(e);return n?{profileById:n}:{profileById:null}}isComplete(t){return t?!!t.display_name&&!!t.country_name&&t.country_name!=="Unknown":!1}async searchProfiles(t,e=6){let n=String(t||"").trim();if(!n)return{searchProfiles:[]};let r=e<=0?void 0:e,i=e<=0?5e3:e,[o,a]=await Promise.allSettled([this.gql.request(M,{query:n,limit:r}),this.fakeData.searchProfiles(n,i)]),s=o.status==="fulfilled"?o.value.searchProfiles??[]:[],l=a.status==="fulfilled"?a.value:[];return{searchProfiles:this.mergeProfiles(s,l,e)}}async searchProfilesReal(t,e=6){let n=String(t||"").trim();if(!n)return{searchProfiles:[]};let r=e<=0?void 0:e;try{return await this.gql.request(M,{query:n,limit:r})}catch{return{searchProfiles:[]}}}async browseProfilesReal(t=80,e=0){try{return await this.gql.request(H,{limit:t<=0?void 0:t,offset:Math.max(0,e)})}catch{return{browseProfiles:[]}}}mergeProfiles(t,e,n){let r=[],i=new Set,o=a=>{let s=a.user_id||a.username||"";!s||i.has(s)||(i.add(s),r.push(a))};return t.forEach(o),e.forEach(o),n<=0?r:r.slice(0,Math.max(1,n))}static \u0275fac=function(e){return new(e||c)(C(U),C(w))};static \u0275prov=_({token:c,factory:c.\u0275fac,providedIn:"root"})};export{w as a,N as b};
