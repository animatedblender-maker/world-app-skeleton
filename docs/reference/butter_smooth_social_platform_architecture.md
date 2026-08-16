# Butter-Smooth Architecture for a Next-Generation Social Platform

**Systems engineering blueprint - production-oriented - version 1.0 - August 2026**

**Audience:** principal architects, backend, frontend, iOS, Android, media, data, platform, security, SRE, DevOps, search, realtime, and developer-productivity teams.

**Mission:** Make the social platform feel instant, continuous, and trustworthy under real-world network conditions and at global scale. The objective is not merely low average latency. The objective is a system that remains responsive during cache misses, packet loss, partial outages, traffic spikes, media processing, background synchronization, retries, deployments, and regional failure.

This document is an execution directive. It defines the architectural defaults, service boundaries, data contracts, caching model, cookie/session policy, URL and slug conventions, media pipeline, realtime model, failure semantics, observability requirements, performance budgets, and rollout sequence that the engineering organization should implement.

---

## 0. Executive directives

1. **Optimize the complete interaction path, not isolated services.** A 20 ms database query does not make a product feel fast if DNS, TLS, JavaScript, image decoding, layout, API waterfalls, or retries add 1.5 seconds.
2. **Treat perceived latency as a product feature.** Optimistic UI, skeletons, prefetching, stale-while-revalidate, local caches, streaming, and graceful fallbacks are part of architecture, not polish.
3. **Put immutable identity beneath human-readable URLs.** Handles and slugs can change. Database identity cannot.
4. **Prefer bounded domain services over a giant monolith or hundreds of tiny microservices.** Split a service when ownership, scaling, failure isolation, data ownership, or deployment independence justifies it.
5. **Use asynchronous work aggressively, but never for operations whose user-visible correctness requires synchronous confirmation.** Upload processing, notifications, analytics, fan-out, moderation enrichment, search indexing, and derived counters belong off the critical path.
6. **Cache by design, not as an emergency patch.** Every high-volume read path must define cacheability, key shape, TTL, invalidation ownership, stale behavior, and stampede protection before launch.
7. **Do not make the browser hold security-critical secrets that JavaScript can read.** Web sessions use secure, HttpOnly cookies; native applications use platform secure storage and short-lived access credentials.
8. **Every write is retryable.** All externally retryable mutations require idempotency semantics.
9. **Use cursor pagination for dynamic social data.** Never build feeds, comments, notifications, or timelines around page-number/offset pagination.
10. **The media path is its own platform.** Original uploads, transcoding, thumbnails, manifests, captions, moderation derivatives, CDN delivery, and lifecycle policy must be decoupled from the transactional API.
11. **Every request is traceable end-to-end.** A user-visible delay must be explainable from client span to gateway to service to database/cache/event publication.
12. **Availability beats feature completeness during incidents.** Design degraded modes for recommendations, search, media, notifications, and realtime.
13. **Do not distribute state casually.** Start with a small number of authoritative data stores and clear ownership. Add replicas, partitions, search indexes, caches, and materialized views as projections, not competing sources of truth.
14. **Performance budgets are release gates.** Regressions in startup, interaction latency, scroll smoothness, memory, API p95/p99, media start time, or error rate can block a release.
15. **Design for deletion, privacy, abuse response, and auditability from the beginning.** Social systems accumulate data faster than teams can retrofit governance.

> **BUILD DECISION:** Adopt a six-plane architecture: (1) client experience plane, (2) edge/delivery plane, (3) API/domain plane, (4) data/event plane, (5) media/realtime/search plane, and (6) reliability/control plane. Each plane has explicit contracts and can evolve independently.

---

## 1. Define what "butter-smooth" means

The engineering organization must operate from measurable user experience objectives rather than subjective descriptions.

### 1.1 Primary experience SLOs

Define separate budgets by device class, region, network quality, and surface. Initial targets should be ambitious but adjustable from measured baselines.

| User action | Target behavior |
|---|---|
| App shell available | render immediately from local/static assets; no dependency on personalized API |
| Tap/navigation acknowledgement | visual acknowledgement in <100 ms |
| Cached screen transition | effectively instant; avoid blank intermediate screens |
| Feed first useful content | target sub-second on good networks; degrade gracefully on slow networks |
| API read p50 / p95 / p99 | define per endpoint class; do not use one platform-wide number |
| Mutation acknowledgement | optimistic where reversible; confirmed result returned asynchronously when safe |
| Image placeholder -> useful image | progressive and viewport-prioritized |
| Short-video startup | minimize manifest + first segment latency; preload next likely items |
| Infinite-scroll page fetch | complete before user reaches buffer threshold |
| Realtime message delivery | near-realtime when connected; durable catch-up after reconnect |
| Crash-free sessions | treated as a first-class SLO |
| Scroll/rendering | sustained frame budget on target devices; no expensive work on main/UI thread |

### 1.2 Measure four forms of latency

- **Network latency:** DNS, connection setup, TLS, request travel, packet loss.
- **Server latency:** gateway, service, cache, database, downstream calls.
- **Client compute latency:** JavaScript/native execution, decoding, layout, rendering, garbage collection.
- **Perceived latency:** what the person experiences after an action.

A smooth architecture minimizes all four and hides unavoidable delay without lying about state.

### 1.3 Golden user journeys

Create synthetic and real-user monitoring for at least:

- cold launch -> authenticated home feed;
- warm launch -> cached feed -> refresh;
- open profile;
- open post and comments;
- like/unlike;
- follow/unfollow;
- create text/image post;
- upload short video;
- upload long video;
- open message thread and send message;
- incoming message while app is foreground/background;
- search query -> suggestions -> results;
- notification -> deep-linked destination;
- reconnect after offline period;
- password/session expiration and refresh;
- delete content/account data flows.

Every release must preserve these journeys.

---

## 2. Top-level reference architecture

```text
Web / iOS / Android
        |
        | DNS + TLS + HTTP/2/HTTP/3
        v
Global CDN / Edge
  |-- static application assets
  |-- image/video delivery
  |-- safe public GET caching
  |-- bot / abuse / WAF controls
  |-- request routing
        |
        v
API Gateway / Edge BFF
  |-- authentication/session resolution
  |-- request IDs / trace context
  |-- rate limits
  |-- experiments / locale / device context
  |-- coarse aggregation
        |
        +-----------------------------+
        |                             |
        v                             v
Domain services                 Realtime gateway
  |-- Identity / Accounts          |-- WebSocket connection registry
  |-- Profiles / Social graph      |-- presence / typing / fan-out
  |-- Posts / Comments             |-- message notifications
  |-- Feed / Recommendation
  |-- Messaging
  |-- Notifications
  |-- Search API
  |-- Moderation / Safety
  |-- Upload coordinator
        |
        +-----------------------------+
        |
        v
Authoritative stores + projections
  |-- relational transactional DB
  |-- cache
  |-- object storage
  |-- event log / stream
  |-- search index
  |-- analytics lake/warehouse
  |-- recommendation feature/index stores
```

> **BUILD DECISION:** Keep the synchronous request graph shallow. The normal interactive request should traverse gateway -> one owning domain service -> its authoritative store/cache, plus at most a small number of deliberate parallel dependencies. Deep synchronous service chains are forbidden without architecture review.

---

## 3. Domain boundaries and service strategy

### 3.1 Start with bounded contexts, not "microservices"

Define these ownership boundaries even if some are initially deployed together:

1. Identity & Authentication
2. Accounts & Profiles
3. Social Graph
4. Content/Post Metadata
5. Comments & Reactions
6. Feed & Recommendation
7. Media
8. Messaging
9. Notifications
10. Search & Discovery
11. Safety / Moderation / Trust
12. Ads / Monetization
13. Experimentation / Feature Flags
14. Analytics / Event Collection
15. Platform / Developer Infrastructure

Each domain owns:

- its API contract;
- schema and migrations;
- authoritative write model;
- emitted domain events;
- SLOs;
- caches and projections;
- on-call ownership;
- deletion/privacy behavior.

### 3.2 When to split a deployment

Split only when one or more are true:

- materially different scaling profile;
- independent availability requirement;
- security boundary;
- specialized runtime/language is justified;
- high deployment contention between teams;
- blast-radius reduction is valuable;
- data ownership is already clear;
- independent regionalization is required.

Do not split because a class or module became large.

### 3.3 Service communication policy

- Interactive reads/writes: synchronous HTTP/gRPC only when response requires it.
- Domain propagation: asynchronous events.
- Bulk processing: jobs/stream processing.
- Cross-service reporting: analytics/warehouse or purpose-built projection, not production joins across databases.
- Never allow arbitrary direct database access across service ownership boundaries.

---

## 4. Client architecture: smoothness begins before the API

### 4.1 Web application

Use route-level code splitting and a small application shell. The initial route must not download the entire social platform.

Required rules:

- split by route and major feature;
- tree-shake and enforce bundle budgets;
- lazy-load editors, analytics-heavy screens, media tools, admin features;
- use modern compressed static delivery;
- immutable fingerprinted asset URLs;
- cache static assets for a long lifetime;
- avoid third-party scripts on the critical path;
- preconnect only to origins that will definitely be used;
- prefetch likely next routes conservatively;
- virtualize long lists;
- do image decoding off the interaction-critical path when possible;
- reserve media dimensions to prevent layout shifts;
- never synchronously block rendering on analytics.

### 4.2 Mobile applications

The same architecture principles apply to native apps:

- persistent local data cache;
- image/video disk cache with bounded eviction;
- background sync subject to OS constraints;
- database writes off UI thread;
- list virtualization/recycling;
- prefetch next media based on viewport direction and bandwidth;
- cancel requests when view context disappears;
- lifecycle-aware realtime connections;
- keep startup dependency graph minimal;
- postpone SDK initialization not needed for first interaction.

### 4.3 Local-first read model

For user-visible surfaces, follow:

```text
render cached/local state
        |
        +--> show freshness indicator only when useful
        |
        +--> issue network revalidation
                 |
                 +--> merge authoritative changes
                 +--> preserve scroll position
                 +--> animate only meaningful changes
```

Do not blank a screen merely because a refresh is in progress.

### 4.4 Optimistic UI policy

Use optimistic updates for actions that are reversible and conflict-tolerant:

- like/unlike;
- save/unsave;
- follow/unfollow where policy permits;
- simple reaction changes;
- draft edits saved locally.

Do not pretend success for:

- payments;
- irreversible deletion without undo semantics;
- permission/security changes;
- username/handle reservation until uniqueness is confirmed;
- moderation appeals;
- uploads before server has accepted ownership.

Every optimistic mutation needs rollback or reconciliation logic.

---

## 5. Navigation, URLs, handles, slugs, and immutable IDs

This layer must be designed once and kept boring forever.

### 5.1 Identity rule

**Never use a mutable slug, display name, or handle as the relational identity of an entity.**

Recommended entity model:

```text
internal_id       immutable database identity
public_id         opaque URL-safe identifier
current_slug      optional human-readable presentation
canonical_handle  normalized unique account handle
created_at
updated_at
```

### 5.2 ID strategy

Preferred default for distributed creation:

- immutable 128-bit sortable IDs such as UUIDv7 for internal identity;
- optionally expose a separate compact opaque public identifier encoded URL-safely;
- do not depend on auto-increment IDs for globally distributed creation;
- do not expose identifiers if their ordering or structure leaks information the product considers sensitive.

If a centralized 64-bit Snowflake-style allocator is chosen, document clock behavior, worker allocation, regional failover, and sequence exhaustion.

### 5.3 User handles

Example canonical profile URL:

```text
/@amr
```

Rules:

- store a normalized comparison form separately from display form;
- reserve protected/system words;
- define Unicode/confusable policy;
- enforce uniqueness in the authoritative database, not only cache;
- retain handle history for redirects and abuse investigation;
- define a cooldown/quarantine period before reassignment;
- old handle URLs should redirect to the current canonical handle when safe;
- mentions store target user ID plus display snapshot, not raw handle alone.

### 5.4 Content URLs

Use immutable identity in every content URL. Example:

```text
/@amr/post/01J.../how-we-built-the-feed
```

or compactly:

```text
/p/A8fk2Qx-how-we-built-the-feed
```

The slug is decorative. The router resolves by immutable public ID. If title/caption changes, generate a new canonical slug and 301/308 redirect the old variant where appropriate.

### 5.5 Slug rules

- lowercase canonical representation;
- Unicode normalized consistently;
- transliteration is optional product policy;
- collapse whitespace/separators;
- remove dangerous/control characters;
- cap length;
- do not require uniqueness if immutable ID is present;
- never use slugs in foreign keys;
- store historical aliases only where redirects are valuable;
- cache redirect lookups;
- canonical URL tag/metadata must point to the current canonical route on web.

### 5.6 Deep links

Every externally shareable object has one canonical logical route that maps to:

- web URL;
- iOS universal link;
- Android app link;
- notification deep link;
- internal navigation object.

Do not let each client invent its own URL semantics.

---

## 6. Authentication, sessions, cookies, and device identity

### 6.1 Web session architecture

For the first-party web application, prefer server-recognized sessions with secure cookies rather than storing long-lived bearer tokens in JavaScript-accessible storage.

Cookie defaults:

```text
Secure: true
HttpOnly: true
SameSite: Lax by default
Path: /
Domain: host-only unless cross-subdomain sharing is explicitly required
short/controlled lifetime
rotation after authentication or privilege change
```

Use `SameSite=Strict` where user journeys permit it. Use `SameSite=None; Secure` only when a legitimate cross-site flow requires it.

### 6.2 Session model

Authoritative session record:

```text
session_id
user_id
device_id / installation_id
created_at
last_seen_at
expires_at
credential_version
auth_strength
ip/risk metadata (privacy-governed)
user_agent/device summary
revoked_at
refresh_family_id
```

Requirements:

- rotate session ID after login;
- rotate/upgrade after sensitive authentication;
- revoke individual devices;
- revoke all sessions after high-risk security events;
- enforce idle and absolute lifetimes as product/security policy;
- maintain a server-side credential/session version for global invalidation;
- do not put mutable authorization state permanently inside a long-lived token.

### 6.3 CSRF

Cookie-authenticated mutation endpoints need CSRF protection. Combine appropriate SameSite policy with explicit anti-CSRF validation for browser requests as required by the application model. Do not assume CORS is CSRF protection.

### 6.4 Native credentials

Native clients should keep refresh credentials in platform secure storage and use short-lived access tokens/session credentials for API calls. Never persist secrets in ordinary preferences or application logs.

### 6.5 Anonymous identity

Support an anonymous installation/session identity for:

- pre-login recommendations;
- experiment assignment;
- rate limiting;
- draft preservation;
- abuse prevention;
- later account merge where policy allows.

Anonymous ID must not become an uncontrolled permanent tracking identifier. Apply expiration and privacy policy.

---

## 7. API design and the edge/BFF layer

### 7.1 One external contract, versioned intentionally

Externally exposed APIs should be stable and backward-compatible for supported clients. Mobile release lag means the backend will see old clients for months.

Contract requirements:

- explicit schema/version policy;
- typed request/response models;
- backward-compatible additive evolution by default;
- deprecation telemetry;
- minimum supported client policy only when necessary;
- generated client types where practical.

### 7.2 REST, GraphQL, and RPC decision

Use the protocol based on boundary, not ideology:

- REST/HTTP: excellent for resource operations, media coordination, web-friendly caching, public APIs.
- GraphQL: useful as an aggregation/query contract for first-party product clients when field governance, persisted operations, query complexity, and caching are controlled.
- gRPC/RPC: good for internal low-latency typed service communication.
- Event schemas: asynchronous cross-domain propagation.

> **BUILD DECISION:** If GraphQL is used for the product API, put it in a controlled BFF/gateway layer. Do not let arbitrary GraphQL queries directly fan out across dozens of production services. Use persisted/approved operations for high-volume app traffic.

### 7.3 Request context

Every request carries:

```text
request_id
trace_id
user/session identity
installation/device class
client version
locale/timezone
surface
experiment assignments or assignment key
network hints where permitted
```

Never trust client-supplied authorization fields merely because they are inside this context.

### 7.4 API response shape

Return enough information for clients to render without immediate follow-up waterfalls. Prefer deliberate screen/view models over forcing the client to perform ten tiny calls.

Bad:

```text
GET post
GET author
GET reaction state
GET media metadata
GET counts
GET viewer permissions
```

Better:

```text
GET post-view
 -> post + author summary + media variants + viewer state + display counts + permissions
```

Keep authoritative ownership internally; aggregation can happen at BFF/read-model level.

---

## 8. Pagination and infinite scroll

### 8.1 Ban offset pagination for dynamic feeds

Do not use:

```text
?page=120&limit=20
OFFSET 2380
```

for feeds, messages, comments, notifications, search streams, or rapidly changing lists.

Use opaque cursors:

```text
GET /feed?after=<opaque_cursor>&limit=20
```

Cursor can encode/sign:

```text
sort_key
entity_id
feed_generation/request_id
policy/model version if needed
snapshot/session state if needed
```

### 8.2 Stable ordering

Every ordering must have a deterministic tiebreaker:

```sql
ORDER BY ranked_at DESC, id DESC
```

or equivalent logical ordering.

### 8.3 Feed cursor semantics

A recommendation feed cursor may represent more than a database key. It can refer to a server-side feed session containing:

- already-served IDs;
- request policy/model version;
- diversity state;
- exploration state;
- expiration;
- next candidate buffer.

Keep cursor payload small and signed/opaque. Never trust mutable client cursor contents.

### 8.4 Prefetch buffer

The client should request the next page before the user reaches the end. Tune by:

- scroll velocity;
- network class;
- item type;
- media buffer state;
- page size;
- memory budget.

Cancel or deprioritize irrelevant prefetches when direction/context changes.

---

## 9. Transactional data architecture

### 9.1 Default source of truth

Use a relational database for core transactional social data unless a workload clearly requires otherwise. Relations, constraints, uniqueness, transactions, and strong queryability are valuable early and remain valuable at scale.

Core examples:

- accounts;
- profiles;
- handles;
- posts metadata;
- comments;
- reactions authoritative state;
- follows/blocks authoritative state;
- permissions;
- session records;
- billing/monetization records;
- moderation decisions.

### 9.2 Schema rules

- every table has immutable primary key;
- all timestamps have explicit timezone semantics;
- soft deletion only where product/legal semantics require it;
- unique constraints enforce true invariants;
- foreign keys where operationally appropriate;
- indexes are workload-driven, not speculative;
- migrations are backward-compatible through rollout windows;
- large migrations use expand -> migrate -> contract;
- application deploy must tolerate mixed schema/application versions.

### 9.3 Read/write separation

Scale reads using:

1. query/index optimization;
2. application/read-model caches;
3. replicas for appropriate stale-tolerant workloads;
4. materialized projections;
5. partitioning/sharding only when required.

Do not jump directly to sharding.

### 9.4 Consistency classes

Define consistency per field/use case:

**Strong/read-your-write preferred**
- authentication;
- permissions;
- blocks;
- handle reservation;
- own profile edits;
- financial state;
- destructive actions.

**Eventual consistency acceptable**
- like count display;
- follower count display;
- search index;
- recommendation features;
- trending aggregates;
- analytics;
- notification badges with reconciliation.

Make this explicit in API contracts so teams do not accidentally depend on a projection being immediately current.

---

## 10. Cache architecture

### 10.1 Cache hierarchy

```text
Client memory cache
    |
Client persistent cache
    |
CDN / edge cache
    |
Gateway/BFF cache
    |
Distributed application cache
    |
Database buffer/cache
    |
Authoritative storage
```

Use the cheapest valid layer closest to the user.

### 10.2 Cache every object by immutable identity

Preferred key pattern:

```text
v3:post:{post_id}
v2:profile:{user_id}
v5:relationship:{viewer_id}:{target_id}
v1:media-manifest:{asset_id}:{variant}
```

Include schema/version in keys for clean migrations.

### 10.3 Cache policy object

Every cached read defines:

```text
owner
key format
TTL
maximum stale age
negative-cache TTL
invalidation events
cache-miss behavior
stampede strategy
privacy scope
regional behavior
```

### 10.4 Stale-while-revalidate

For safe data, serving a slightly stale value immediately is often better than making every user wait for origin recomputation.

Pattern:

```text
fresh cache hit -> return
stale-but-acceptable -> return stale + refresh asynchronously
expired/unsafe -> fetch origin
```

### 10.5 Cache stampede protection

Use one or more:

- request coalescing/single-flight;
- randomized TTL jitter;
- stale serving;
- background refresh;
- admission control;
- distributed locking only where justified.

### 10.6 Negative caching

Cache known absence briefly for hot nonexistent keys such as deleted posts or invalid handles. Keep TTL short enough to avoid hiding newly created data.

### 10.7 Never cache personalized data publicly

Public CDN caching requires correct `Cache-Control`, authorization separation, `Vary` behavior, and cache key design. A single personalized response leaked through a shared cache is a severe security incident.

---

## 11. HTTP delivery, CDN, and edge architecture

### 11.1 Static assets

Fingerprint all immutable assets:

```text
app.4d8f91.js
profile-placeholder.ae120.webp
```

Serve with long-lived immutable caching. HTML/app bootstrap should have a shorter revalidation policy so deployments propagate.

### 11.2 Protocols

Support modern HTTP stacks through the CDN/edge, including HTTP/2 and HTTP/3 where available. The application must remain correct independent of transport version.

### 11.3 Compression

- Brotli/gzip for compressible text assets;
- do not recompress already compressed media;
- generate image/video encodings suitable for target clients;
- monitor compression CPU vs bandwidth tradeoff at origin; precompress static assets.

### 11.4 Edge responsibilities

The edge may perform:

- TLS termination;
- static/media cache;
- safe public API cache;
- WAF and DDoS controls;
- bot/rate controls;
- geo-aware routing;
- lightweight request normalization;
- signed media URL validation where supported.

Do not push authoritative business logic into dozens of ungoverned edge scripts.

---

## 12. Event-driven architecture and asynchronous work

### 12.1 Domain event log

Every important state change emits a durable event after/with the authoritative transaction:

```text
PostCreated
PostDeleted
ReactionChanged
UserFollowed
UserBlocked
ProfileUpdated
MediaReady
CommentCreated
MessageAccepted
ModerationDecisionChanged
```

### 12.2 Transactional outbox

Avoid the dual-write bug:

```text
DB commit succeeds
Kafka/event publish fails
```

Use a transactional outbox or equivalent atomic change-capture pattern so domain state and event intent are committed together.

### 12.3 Event envelope

```text
event_id
schema_version
event_type
aggregate_type
aggregate_id
occurred_at
producer
trace_id
causation_id
correlation_id
payload
```

### 12.4 Idempotent consumers

Assume events can be redelivered. Consumers must deduplicate or make processing naturally idempotent.

Never build correctness on "this message will only appear once."

### 12.5 What belongs asynchronously

- search indexing;
- recommendation feature updates;
- analytics;
- notification generation;
- email/push delivery;
- media transcode;
- thumbnail/caption generation;
- content classification;
- derived counters;
- fan-out caches;
- abuse heuristics;
- data exports;
- deletion propagation;
- expensive link previews;
- feed precomputation where used.

### 12.6 Queue backpressure

Every consumer defines:

- maximum acceptable lag;
- concurrency controls;
- retry policy;
- dead-letter/quarantine policy;
- poison-event handling;
- replay procedure;
- load shedding behavior;
- downstream dependency limits.

---

## 13. Idempotency, retries, timeouts, and duplicate prevention

### 13.1 Idempotency keys

All retryable externally visible writes should accept an idempotency key:

```text
POST /posts
Idempotency-Key: <client-generated-key>
```

Server persists enough state to return the original result for retries within the defined window.

Use for:

- post creation;
- message send;
- media initiation/finalization;
- purchases;
- account actions;
- any mobile request likely to be retried after an ambiguous network failure.

### 13.2 Timeouts

Every network call has an explicit timeout derived from the caller's total deadline. Never rely on library defaults.

Example budget:

```text
Client deadline: 2,000 ms
Edge/gateway:    1,500 ms
Service work:    1,000 ms
DB/cache calls:    300 ms each with bounded retries
```

Do not permit a downstream service to consume more time than its caller has left.

### 13.3 Retries

Retry only transient, safe/idempotent operations. Use:

- exponential backoff;
- jitter;
- small bounded retry count;
- deadline awareness;
- retry budgets to prevent storms.

Never instantly retry an overloaded dependency from every replica.

### 13.4 Circuit breaking and load shedding

When dependency health deteriorates:

- stop sending work it cannot process;
- serve stale cache where safe;
- disable optional enrichments;
- reject low-priority work before critical work;
- use bounded queues.

---

## 14. Feed-serving architecture for smooth scrolling

The recommendation roadmap decides *what* to show. This architecture decides *how to deliver it without pauses*.

### 14.1 Feed response contract

Each feed item should be sufficiently hydrated to render immediately:

```text
item identity
creator summary
text/caption summary
media presentation variants
aspect ratio / dimensions
viewer reaction state
relationship summary
safe display counts
accessibility metadata
ranking/impression token
tracking token
navigation/deep-link data
```

Avoid per-card follow-up requests.

### 14.2 Feed session buffer

For expensive ranking, compute a buffer larger than one page and retain a short-lived server-side feed session. Subsequent cursor calls consume/refill the buffer.

Benefits:

- lower repeated ranking cost;
- more stable pagination;
- easier deduplication;
- diversity constraints across pages;
- smoother prefetch.

### 14.3 Impression semantics

Do not log an impression merely because an item was returned by API. Distinguish:

- generated candidate;
- returned to client;
- entered viewport;
- met viewability threshold;
- media actually started.

This distinction matters for analytics and recommendation training.

### 14.4 Client list rules

- stable item keys;
- virtualized/recycled cells;
- no unbounded DOM/view hierarchy;
- pre-sized media containers;
- defer offscreen expensive components;
- decode/preload only a bounded forward window;
- cancel previous video aggressively when required;
- preserve scroll anchor on refresh/insertions.

---

## 15. Media architecture: images, short video, long video, audio

### 15.1 Never upload large media through the normal API server

Flow:

```text
Client
  |
  | 1. request upload session
  v
Upload Coordinator
  |
  | 2. signed multipart/direct-upload credentials
  v
Object Storage
  |
  | 3. upload completed event
  v
Media Pipeline
  |-- validate/container inspect
  |-- malware/security checks where applicable
  |-- transcode ladder
  |-- thumbnails/poster frames
  |-- waveform/audio derivatives
  |-- captions/transcript
  |-- moderation/safety features
  |-- metadata extraction
  v
Media Catalog -> CDN
```

### 15.2 Upload protocol

Support resumable/multipart upload for large files. Store upload state and permit retry without restarting the entire file.

### 15.3 Media IDs and states

```text
CREATED
UPLOADING
UPLOADED
VALIDATING
PROCESSING
READY
FAILED
QUARANTINED
DELETED
```

Content posts can reference media only according to an explicit state policy.

### 15.4 Image pipeline

Create server-generated variants based on actual UI breakpoints/device density, not arbitrary dozens of sizes.

Store:

- original (subject to policy);
- canonical normalized asset;
- thumbnail/small/medium/large variants;
- modern formats where client support warrants;
- width/height/aspect ratio;
- blur/preview representation if used.

Use `srcset`/equivalent responsive selection on web.

### 15.5 Video delivery

Use adaptive bitrate streaming for long/important video surfaces. Create a transcode ladder based on source quality, content class, and target devices.

Deliver:

- manifest;
- short media segments;
- multiple resolutions/bitrates;
- audio tracks;
- captions/subtitles;
- poster frame.

For short-form feeds, optimize the first playable bytes and next-item preload aggressively while respecting bandwidth/data saver.

### 15.6 CDN media URLs

Media URLs should be cacheable and immutable by asset/version. Authorization for private media can use short-lived signed URLs/cookies or authenticated edge delivery. Avoid routing every byte through application servers.

### 15.7 Media deletion

Deletion must propagate to:

- media catalog;
- object storage lifecycle;
- CDN invalidation/expiry strategy;
- search index;
- recommendation indexes;
- derived thumbnails/transcodes;
- moderation derivatives according to legal retention policy;
- backups according to documented retention/deletion semantics.

---

## 16. Realtime architecture

### 16.1 Separate realtime transport from durable state

WebSockets are a delivery optimization, not the source of truth.

For messaging:

```text
Client -> Messaging API -> durable message commit -> event
                                      |
                                      +-> realtime delivery
                                      +-> push notification if needed
```

A recipient who was disconnected catches up from durable message history.

### 16.2 Connection gateway

Realtime gateway owns:

- authenticated connection establishment;
- connection/session registry;
- subscription authorization;
- heartbeat/liveness;
- backpressure;
- fan-out to connected devices;
- protocol versioning.

It does not own permanent message history.

### 16.3 Presence

Presence is ephemeral and approximate. Do not write a relational database row every few seconds for millions of clients.

Use short-lived distributed state/heartbeats and product-defined buckets such as:

```text
online
recently active
offline/unknown
```

Avoid false precision.

### 16.4 Reconnection

Client reconnection uses:

- exponential backoff + jitter;
- session resumption where supported;
- last known durable sequence/cursor;
- catch-up API after reconnect;
- deduplication by immutable message/event ID.

### 16.5 Typing indicators and transient events

Typing indicators are lossy by design. Do not persist them. Apply TTL and rate limits.

---

## 17. Messaging specifics

### 17.1 Message identity

Client generates a temporary/local ID and idempotency key. Server returns immutable message ID and server ordering metadata.

### 17.2 Ordering

Do not claim a global total order across the entire system. Define ordering per conversation using server-assigned sequence/order semantics.

### 17.3 Delivery/read state

Separate:

- accepted by server;
- delivered to device/account;
- read by user.

Treat each as a state transition/event, not a synchronous chain that blocks message send.

### 17.4 Attachments

Messaging attachments use the media upload system, not base64 blobs inside message JSON.

---

## 18. Search architecture

### 18.1 Search is a projection, not the source of truth

Account/content writes commit to authoritative stores, emit events, and update the search index asynchronously.

### 18.2 Separate search concerns

- exact handle lookup;
- prefix/autocomplete;
- lexical search;
- semantic/vector retrieval;
- personalized ranking;
- trending query suggestions;
- safety filtering.

Do not force every search use case through one index/query.

### 18.3 Autocomplete latency

Keep suggestions extremely fast:

- edge/client debounce;
- cancellation of stale requests;
- prefix index optimized for short queries;
- cache popular anonymous prefixes;
- personalize only when latency budget permits;
- never display results from an older request after a newer query has completed.

### 18.4 Index consistency

UI must tolerate index delay after profile/post changes. For the current user, merge authoritative recent writes into search/display where read-your-write matters.

---

## 19. Social graph and counters

### 19.1 Relationship truth

Follow/block/mute state is authoritative transactional state. Recommendation graph projections may be asynchronous copies.

### 19.2 Counts

Do not update a single hot `followers_count` row transactionally for every follow at enormous scale.

Possible progression:

1. transactional count while small;
2. striped/sharded counters;
3. event-driven aggregation;
4. cached approximate display count with periodic reconciliation.

Permission decisions must never depend on an approximate count.

### 19.3 Celebrity/hot-key problem

Design for extremely skewed accounts. One creator can receive orders of magnitude more reads/writes than average.

Mitigations:

- cache hot profiles/content;
- partition fan-out work;
- async counters;
- avoid single-key locks;
- bounded fan-out-on-write;
- use hybrid feed fan-out for high-fanout accounts.

---

## 20. Notification architecture

### 20.1 Notification is a product pipeline

```text
Domain event
   -> eligibility
   -> dedupe/coalescing
   -> user preferences
   -> ranking/priority
   -> channel decision
   -> in-app inbox
   -> push/email when appropriate
```

### 20.2 Coalescing

Avoid 100 notifications saying individual users liked the same post. Coalesce where product semantics allow.

### 20.3 Push is a hint

Push payload should be small and deep-link by immutable object identity. The application fetches authoritative state after opening. Do not treat mobile push delivery as guaranteed.

### 20.4 Badge counts

Badge counts are projections. Reconcile periodically and design for missed/reordered events.

---

## 21. Safety, privacy, authorization, and abuse resistance

### 21.1 Authorization occurs at the owning service

Gateway authentication is not sufficient. Each domain service enforces authorization on the requested object/action.

### 21.2 Blocks and privacy are hard constraints

A block/mute/privacy rule must propagate to:

- feed;
- search;
- profile visibility;
- comments;
- messaging;
- notifications;
- recommendations;
- realtime subscriptions.

Centralize policy primitives or distribute a versioned policy library/service so semantics cannot drift.

### 21.3 Rate limits

Layer limits:

- IP/network abuse controls;
- anonymous installation;
- account;
- endpoint/action;
- recipient/target based;
- expensive resource quotas.

Use token bucket/leaky bucket or equivalent with burst tolerance. Return structured retry information.

### 21.4 Secrets and PII

- secrets only in managed secret storage;
- no access tokens/session cookies in logs;
- redact sensitive query/body fields;
- encrypt in transit and at rest;
- maintain data classification;
- restrict production data access;
- audit privileged access;
- minimize PII copied into events and caches.

### 21.5 Data deletion map

Maintain a machine-readable inventory of where user data can exist:

```text
primary DB
replicas
cache
search index
event log
warehouse/lake
feature store
recommendation index
object storage
backups
observability/logs
support systems
```

Define deletion/retention behavior for each.

---

## 22. Database query performance

### 22.1 Index from access patterns

For every hot query, document:

- predicate;
- ordering;
- expected cardinality;
- index used;
- p50/p95/p99;
- rows scanned vs returned;
- cache hit behavior.

### 22.2 N+1 prevention

N+1 database/API behavior is a release blocker on high-volume surfaces. Use batching, joins within the owning database, or precomputed read models.

### 22.3 Connection pools

Each application replica must not independently open an unbounded number of database connections. Size pools from database capacity and replica counts. Use a pooler/proxy when warranted.

### 22.4 Query deadlines

Slow queries should fail within a controlled budget rather than consume connections indefinitely. Track lock waits separately from execution.

### 22.5 Partitioning

Partition large tables only with a concrete operational/query reason, such as:

- time-based retention;
- very large event/history tables;
- geographic/tenant locality;
- maintenance boundaries.

Do not partition every table by default.

---

## 23. Multi-region strategy

Do not begin by making every database active-active everywhere. Global writes create major consistency complexity.

### 23.1 Recommended progression

**Stage 1:** single primary region, global CDN, multi-AZ database, regional edge.

**Stage 2:** read replicas / caches in additional regions, disaster-recovery region.

**Stage 3:** regionalized stateless services and read paths.

**Stage 4:** selectively regionalize write ownership for domains that need it.

**Stage 5:** only use multi-writer/global-consensus designs where business requirements justify their cost and semantics.

### 23.2 Data locality

Plan for legal/residency requirements by attaching data-class and home-region metadata to domains. Do not hard-code one global storage assumption into every service.

### 23.3 Failure policy

Document per domain:

- RPO;
- RTO;
- failover authority;
- DNS/traffic switch procedure;
- session behavior;
- data reconciliation;
- whether writes pause or continue in degraded mode.

---

## 24. Observability: no black boxes

Use a common telemetry standard and propagate trace context through synchronous calls and asynchronous events.

### 24.1 Required signals

- distributed traces;
- metrics;
- structured logs;
- profiles where useful;
- client real-user monitoring;
- crash reports;
- business/experience metrics.

### 24.2 Every request span should identify

```text
service
operation/route
request_id
trace_id
region/zone
release/version
client type/version bucket
status/error class
latency
cache hit/miss where relevant
downstream dependency spans
```

Do not put raw PII into high-cardinality telemetry attributes.

### 24.3 RED + USE

For request-driven services monitor:

- Rate;
- Errors;
- Duration.

For resources monitor:

- Utilization;
- Saturation;
- Errors.

### 24.4 Tail latency

p99 matters. Averages hide the exact users who perceive the product as randomly slow.

Slice latency by:

- region;
- ISP/network class;
- device;
- client version;
- endpoint;
- cache state;
- experiment;
- dependency;
- database shard/partition;
- media codec/variant.

---

## 25. Performance budgets and release gates

Every critical client and service has budgets checked in CI/CD and production canaries.

### 25.1 Web budgets

Track at minimum:

- JS/CSS transferred bytes by route;
- startup parse/execute time;
- main-thread long tasks;
- layout stability;
- image bytes above the fold;
- route transition time;
- API waterfall count;
- memory growth on long sessions.

### 25.2 Native budgets

- cold/warm startup;
- frame drops/jank;
- memory;
- battery/network use;
- app binary growth;
- background work;
- video start/rebuffer;
- crash/ANR/hang rate.

### 25.3 Backend budgets

- p50/p95/p99 latency;
- request and dependency error rate;
- CPU/memory per request;
- database queries/request;
- cache hit ratio;
- event publish latency;
- queue lag;
- saturation;
- cost per 1,000 requests / per active user for major surfaces.

---

## 26. Deployment architecture

### 26.1 Immutable builds

Build once. Promote the same artifact through environments. Configuration and secrets are externalized.

### 26.2 Progressive delivery

Use:

```text
unit/integration tests
 -> staging
 -> shadow where applicable
 -> internal users
 -> 1% canary
 -> small region/cohort
 -> 10%
 -> 50%
 -> 100%
```

Automated rollback triggers should include both infrastructure metrics and product experience metrics.

### 26.3 Database migrations

Use expand-contract:

1. deploy additive schema;
2. deploy code that can read/write both if needed;
3. backfill asynchronously;
4. switch reads;
5. stop old writes;
6. verify;
7. remove old schema later.

Never require every service instance to switch schemas at exactly the same millisecond.

### 26.4 Feature flags

Flags must have:

- owner;
- creation date;
- intended expiration;
- type (release/experiment/ops/permission);
- default behavior;
- kill-switch semantics;
- audit history.

Stale flags are technical debt and must be removed.

---

## 27. Reliability and degraded modes

### 27.1 Bulkheads

Isolate pools/resources for critical vs optional workloads. Search outage must not exhaust the connection pool needed for login.

### 27.2 Fallback table

| Failure | Required fallback |
|---|---|
| recommender unavailable | cached feed / following / trending safe fallback |
| search index unavailable | exact handle lookup + graceful error for broad search |
| realtime unavailable | durable polling/catch-up; message send can still commit |
| notification provider down | queue and retry; in-app notification remains |
| analytics unavailable | buffer/drop by policy; never block product requests |
| media transcode delayed | show processing state; text/post metadata remains usable |
| cache unavailable | protect DB with load shedding; do not unleash full traffic blindly |
| replica stale/unavailable | route critical reads to primary within capacity |
| moderation enrichment delayed | apply conservative eligibility policy for unclassified content |

### 27.3 Chaos and game days

Test:

- cache cluster loss;
- one AZ failure;
- database failover;
- queue consumer lag;
- object-storage latency;
- CDN origin pressure;
- bad deployment;
- malformed event storm;
- third-party push/email outage;
- credential rotation;
- regional isolation.

---

## 28. Background jobs and schedulers

Do not build critical jobs as random cron scripts on application instances.

Job platform requirements:

- durable scheduling;
- ownership;
- idempotency;
- concurrency control;
- retries/backoff;
- timeout;
- run history;
- observability;
- dead-letter/quarantine;
- manual replay;
- partitioning for large jobs.

Examples:

- account deletion workflows;
- media cleanup;
- stale session expiration;
- recomputation/backfills;
- notification digests;
- search reconciliation;
- counter repair;
- cache warming;
- model/index publication.

---

## 29. Configuration and feature ownership

Separate:

- build-time constants;
- runtime configuration;
- secrets;
- experiment configuration;
- product policy;
- emergency kill switches.

Configuration changes need versioning, validation, auditability, and rollback. A malformed configuration should not be able to globally take down the feed.

---

## 30. Data contracts and schema governance

### 30.1 APIs

Use machine-readable schemas and compatibility checks in CI.

### 30.2 Events

Version event schemas. Consumers must tolerate additive evolution and reject/alert on incompatible versions deliberately.

### 30.3 Database ownership

Schema changes require owning-team review. No service silently depends on another team's private table layout.

### 30.4 Timestamps

Use server timestamps for authoritative ordering. Client timestamps are metadata and may be wrong.

---

## 31. Time, clocks, and ordering

Distributed systems do not have one perfect clock.

Rules:

- use UTC server timestamps internally;
- store user timezone separately for presentation/scheduling;
- do not rely on client clock for authorization or durable ordering;
- sequence critical per-aggregate operations explicitly;
- account for clock skew in expiry/lease logic;
- use monotonic clocks for measuring durations inside a process.

---

## 32. Content creation pipeline

### 32.1 Draft model

Client maintains a local draft ID. Server may create a draft/upload session before final publish.

### 32.2 Publish transaction

A post should become publicly discoverable only after its required dependencies meet publish policy.

Possible flow:

```text
create draft
upload media
media reaches allowed state
submit publish mutation (idempotent)
transaction commits post metadata
emit PostPublished
enqueue downstream indexing/recommendation/notifications
return canonical post object
```

### 32.3 Link previews

Fetch link previews asynchronously with SSRF protections, DNS/IP validation, content limits, timeouts, and caching. Never let arbitrary user URLs make unrestricted requests from trusted internal networks.

---

## 33. Deletion, undo, and tombstones

### 33.1 User experience

Where safe, provide a short undo window for destructive actions. Internally distinguish:

- hidden from user/product immediately;
- tombstoned in authoritative state;
- asynchronously removed from projections/media;
- legally retained where required.

### 33.2 Referential behavior

Deleted objects need explicit rendering policy:

```text
comment on deleted post -> inaccessible
message attachment deleted -> tombstone
reply parent deleted -> preserve thread placeholder or remove by policy
user deleted -> anonymized/tombstoned reference by policy
```

Do not let every client invent behavior.

---

## 34. Client/server state reconciliation

Every mutable object should support conflict handling.

Useful fields:

```text
version / etag
updated_at
server state
client mutation id
```

For edits, use optimistic concurrency where lost updates matter. A stale editor should not silently overwrite a newer version.

---

## 35. Offline and unreliable-network behavior

Assume users move between Wi-Fi, LTE/5G, tunnels, trains, elevators, and offline state.

### 35.1 Read behavior

- render cached content;
- mark stale only when useful;
- queue refresh until connectivity;
- preserve drafts;
- keep navigation usable for cached routes.

### 35.2 Mutation behavior

Classify actions:

**Queueable:** likes, saves, drafts, some follows, messages if product supports offline outbox.

**Requires online confirmation:** handle changes, sensitive account changes, payments, authorization-critical actions.

### 35.3 Outbox

Client-side offline outbox stores:

```text
mutation_id
operation
payload/reference
created_at
retry_count
status
```

Replay with idempotency keys. Reconcile server result to local state.

---

## 36. Cost architecture

Performance and cost are coupled.

Measure unit economics:

```text
cost / 1,000 feed requests
cost / uploaded GB
cost / streamed GB
cost / 1,000 search queries
cost / 1,000 messages
cost / monthly active user
cache savings
transcode cost / video minute
```

Do not optimize cloud bill by making UX visibly worse. Instead eliminate waste:

- oversized media variants;
- cache misses;
- duplicate API calls;
- overfetching;
- unbounded logs;
- unnecessary cross-region traffic;
- wasteful model inference;
- idle overprovisioning;
- runaway retries.

---

## 37. Technology selection principles

Technology choices should minimize operational entropy.

### 37.1 Default stack categories

Choose one strong default for each category and allow exceptions through architecture review:

- relational OLTP database;
- distributed cache;
- durable event log/stream;
- object storage;
- CDN;
- search engine;
- observability standard/backends;
- container/runtime platform;
- schema/IDL system;
- secrets manager;
- CI/CD;
- feature flag/experiment system.

### 37.2 Polyglot rule

Use multiple languages only for real benefits. A social platform can use a productive product-service language for most APIs, then specialized languages/runtimes for media, high-throughput realtime, ML, or performance-critical components.

Do not make every team choose its own framework.

### 37.3 Build vs buy

Prefer managed/commodity infrastructure for undifferentiated capabilities early. Build custom systems where the product's scale, latency, economics, or unique behavior materially requires it.

Recommendation quality, creator distribution, media experience, social graph, and product surfaces may become differentiators. Running your own generic certificate authority or reinventing object storage usually is not.

---

## 38. Security architecture checklist

Every service must answer:

- Who can call it?
- How is identity authenticated?
- What authorization check occurs?
- What data classification is handled?
- What secrets are required?
- What is logged?
- What is rate limited?
- What is the abuse model?
- What happens if the request is replayed?
- Can input trigger SSRF/path traversal/injection/deserialization issues?
- What is the maximum request/body size?
- What is the timeout?
- What data leaves the region/provider?
- How is deletion propagated?

Security review is part of architecture design, not a launch-week penetration-test ticket.

---

## 39. Testing strategy

### 39.1 Pyramid

- unit tests for deterministic logic;
- contract tests for APIs/events;
- integration tests with real dependencies where valuable;
- end-to-end tests for golden journeys;
- load/performance tests;
- fault injection;
- security tests;
- migration tests;
- client backward-compatibility tests.

### 39.2 Production-safe validation

Use shadow traffic, replay of sanitized traffic, canaries, and synthetic accounts. Never assume staging reproduces global production skew.

### 39.3 Load models

Test skew, not just average RPS:

- celebrity post;
- breaking-news spike;
- viral video;
- bot burst;
- login storm after outage;
- notification fan-out;
- massive livestream/event if supported;
- cache cold start.

---

## 40. SRE ownership and incident response

### 40.1 SLOs and error budgets

Every critical service/surface has:

- availability SLO;
- latency SLO;
- correctness/data freshness SLO where relevant;
- owner;
- dashboard;
- alerts tied to user impact.

### 40.2 Alerting

Alert on actionable symptoms, not every metric twitch. Page for imminent/user-impacting failures. Ticket low-urgency capacity and quality issues.

### 40.3 Runbooks

Required for:

- database failover;
- cache failure;
- queue lag;
- high error rate;
- media pipeline backlog;
- search outage;
- realtime disconnect storm;
- credential/key rotation;
- rollback;
- regional evacuation;
- abuse attack.

### 40.4 Postmortems

Blameless, technically specific, with corrective actions addressing systemic causes. Track action completion.

---

## 41. Team topology

Recommended ownership groups once scale justifies them:

### Client Platform
Owns web/iOS/Android foundations, networking, local cache, navigation, design-system performance, release tooling.

### Edge & API Platform
Owns CDN integration, gateway/BFF foundation, auth context, rate limiting, API standards, request tracing.

### Core Social
Owns accounts, profiles, follows/blocks, posts metadata, reactions/comments.

### Media Platform
Owns uploads, storage, transcode, media catalog, delivery, players/SDK foundations.

### Realtime & Messaging
Owns WebSocket infrastructure, durable messaging, presence, conversation sync.

### Search & Discovery
Owns indexing/search service and query stack.

### Recommendation Platform
Owns retrieval/ranking/feature infrastructure and feed orchestration in conjunction with product teams.

### Data Platform
Owns events, stream processing, lake/warehouse, governance, data quality.

### Trust & Safety Platform
Owns policy enforcement primitives, moderation infrastructure, abuse signals.

### SRE / Production Engineering
Owns reliability framework, capacity, incident management, disaster recovery, observability foundations.

### Developer Platform
Owns CI/CD, local development, service templates, schema tooling, secrets/configuration, paved roads.

---

## 42. The paved road: make the correct thing the easy thing

Create a standard service template including:

```text
health/readiness endpoints
structured logging
OpenTelemetry instrumentation
request/trace IDs
auth middleware
timeout/deadline propagation
standard retry client
rate-limit hooks
metrics
config + secrets
schema validation
CI pipeline
container definition
deployment policy
SLO dashboard skeleton
```

Create equivalent client modules for:

```text
networking
session refresh
request cancellation
retry policy
local cache
image loading
analytics events
feature flags
crash reporting
navigation/deep links
```

Teams should not reimplement these independently.

---

## 43. Architecture decision records (ADRs)

Major decisions require an ADR with:

```text
Context
Decision
Alternatives considered
Why rejected
Data ownership impact
Consistency model
Failure modes
Security/privacy impact
Latency/cost impact
Migration/rollback plan
Review date
Owner
```

Required ADRs early:

1. ID/public-ID scheme.
2. Handle/slug/canonical URL policy.
3. Authentication/session/cookie model.
4. External API style.
5. OLTP database strategy.
6. Event bus and outbox pattern.
7. Cache strategy.
8. Media upload/delivery model.
9. Realtime connection architecture.
10. Search projection architecture.
11. Experiment assignment architecture.
12. Multi-region strategy.
13. Data deletion/retention architecture.

---

## 44. Concrete platform conventions

### 44.1 Headers

Standardize:

```text
X-Request-Id or equivalent trace-aware request correlation
Idempotency-Key for supported mutations
client version/build identifiers
Content-Language / locale semantics where needed
ETag / If-None-Match where cache validation is useful
```

Do not expose internal topology through arbitrary headers.

### 44.2 Error envelope

```json
{
  "error": {
    "code": "HANDLE_TAKEN",
    "message": "This handle is unavailable.",
    "request_id": "...",
    "retryable": false,
    "details": {}
  }
}
```

Clients branch on stable machine codes, never English message text.

### 44.3 Date/time

API timestamps use an unambiguous ISO 8601 representation or typed serialization. Client localizes for display.

### 44.4 Money

Store integer minor units or exact decimal type with explicit currency. Never binary floating point.

### 44.5 Text

Define maximum lengths and Unicode normalization. Preserve original user text where required; derive normalized forms for search/uniqueness separately.

---

## 45. Feed + architecture integration contract

The recommendation system and delivery system need an explicit boundary.

Recommendation returns a ranked logical list:

```text
user/session
surface
item IDs
ranking/impression tokens
score metadata for internal logging
next-cursor/feed-session token
```

Hydration/read-model layer resolves display data in bulk. It must not call the ranker once per card.

The API response logs:

```text
recommendation_request_id
feed_session_id
item IDs/order
hydration version
client response time
```

Client logs viewability separately.

This separation lets ranking change independently from content rendering/caching.

---

## 46. Experimentation architecture

Experiment assignment should be stable and available near the edge/gateway without repeated database calls.

### 46.1 Assignment

Deterministically assign by a stable key:

```text
hash(experiment_id, user_or_installation_id) -> bucket
```

subject to eligibility, mutual exclusion, ramp percentage, and geography.

### 46.2 Exposure

Do not count a user as exposed just because they were assigned. Log exposure when the changed behavior was actually executed/rendered.

### 46.3 Configuration

Experiment configuration must be versioned and auditable. Clients receive only the flags/parameters they require.

---

## 47. Practical staged implementation roadmap

### Phase 0 - Architecture foundations

Build before feature explosion:

- immutable ID/public-ID convention;
- handles/slugs/deep-link convention;
- session/cookie/auth architecture;
- API schema conventions;
- relational primary datastore;
- migrations and connection pooling;
- CDN/static delivery;
- distributed cache;
- object storage;
- event bus + outbox;
- structured logs/traces/metrics;
- CI/CD + progressive rollout;
- feature flags;
- idempotency framework;
- rate limiting;
- service/client templates.

**Exit criteria:** one golden vertical slice can be traced from tap through API/database/event and back, with repeatable deployment and rollback.

### Phase 1 - Core social smoothness

Implement:

- profile/read model caching;
- cursor pagination;
- optimistic reactions/follows;
- post/comment hydration APIs;
- local client cache;
- route/code splitting;
- image pipeline and responsive variants;
- feed prefetch buffer;
- real-user performance monitoring.

**Exit criteria:** scrolling and navigation remain smooth under normal network variance; no N+1/API waterfalls on core surfaces.

### Phase 2 - Media platform

Implement:

- resumable direct upload;
- media state machine;
- transcode workers;
- adaptive video delivery;
- thumbnails/posters/captions;
- CDN signed/private delivery;
- background processing dashboards;
- deletion lifecycle.

**Exit criteria:** application API never proxies large video bytes; upload resumes after failure; video start/rebuffer metrics are visible.

### Phase 3 - Realtime and messaging

Implement:

- durable message service;
- realtime connection gateway;
- reconnect/catch-up protocol;
- presence;
- push fallback;
- offline outbox;
- message deduplication/idempotency.

**Exit criteria:** disconnecting/reconnecting cannot lose or duplicate a logical message.

### Phase 4 - Search/discovery projections

Implement:

- event-driven search indexing;
- exact handle lookup;
- autocomplete;
- content search;
- cache/cancellation/debounce;
- projection repair/reindex tools.

**Exit criteria:** search can be fully rebuilt from authoritative sources/events without product downtime.

### Phase 5 - Global reliability

Implement:

- multi-region read/edge footprint;
- DR environment;
- failover game days;
- workload isolation/bulkheads;
- mature autoscaling/capacity models;
- chaos testing;
- cost per user/surface dashboards.

**Exit criteria:** documented regional/dependency failures have tested degraded modes and recovery procedures.

### Phase 6 - Extreme-scale optimization

Only after measurements justify it:

- specialized sharding;
- regional write ownership;
- custom high-performance services;
- hybrid feed fan-out;
- specialized media edge logic;
- advanced cache hierarchy;
- storage tiering;
- tailored transport/protocol optimizations.

**Rule:** complexity enters after a measured bottleneck, not before.

---

## 48. First 90 days for a large architecture team

### Days 1-30: standards and measurement

- approve ID, URL/slug, auth/session, API, event, and observability ADRs;
- inventory existing request paths and data stores;
- define golden journeys and performance budgets;
- instrument client + backend traces;
- remove obvious API waterfalls/N+1s;
- create paved-road service/client templates;
- establish cache and idempotency libraries.

### Days 31-60: critical-path redesign

- implement local-first feed/profile cache;
- deploy CDN/static/media cache policies;
- move uploads to direct object storage;
- add cursor pagination everywhere dynamic;
- introduce outbox/event pipeline;
- build bulk hydration APIs;
- enforce timeouts/deadlines/retry budgets;
- ship performance dashboards by region/device/version.

### Days 61-90: resilience and scale

- canary/progressive delivery gates;
- cache stampede and hot-key tests;
- DB failover exercise;
- queue backlog exercise;
- realtime reconnect test at scale;
- synthetic slow-network suite;
- establish cost-per-surface metrics;
- complete first disaster-recovery runbook.

---

## 49. Engineering review checklist for every new feature

Before approving architecture, answer all of the following:

### Product path
- What is the user interaction?
- What is the perceived-latency budget?
- What is rendered from local/cache state first?

### API
- How many network round trips?
- Can they be parallelized or combined?
- Is the response overfetching or underfetching?
- What is the deadline?

### Identity/URLs
- What is the immutable ID?
- Does the feature expose a slug/handle?
- What happens after rename?
- What is the canonical deep link?

### Data
- Which service/store is authoritative?
- What constraints enforce correctness?
- What is eventual vs strong consistency?
- Which indexes support the query?

### Cache
- Is it cacheable?
- At which layer?
- TTL?
- Invalidation?
- Stale behavior?
- Stampede behavior?

### Events
- Which domain events are emitted?
- Are consumers idempotent?
- What happens if they lag for hours?

### Failure
- What if cache is down?
- What if DB is slow?
- What if event bus is delayed?
- What if the client retries?
- What is the degraded behavior?

### Security/privacy
- Authorization?
- Rate limits?
- Sensitive data?
- Logging redaction?
- Deletion/retention?

### Observability
- Which traces/metrics/logs?
- Which user-facing SLO?
- Which alert?
- How is rollout measured?

No feature is architecturally complete until these answers exist.

---

## 50. Anti-patterns prohibited by default

1. Slug or username as database primary/foreign key.
2. Long-lived auth token in browser `localStorage` as the default first-party session design.
3. Offset pagination for infinite social feeds.
4. Uploading/streaming large video through ordinary application servers.
5. Synchronous analytics calls in user request path.
6. A service calling five other services sequentially to render one card.
7. Cache without owner/invalidation/TTL definition.
8. Infinite retry loops.
9. Retryable writes without idempotency.
10. Shared database tables modified by unrelated services.
11. Search index used as authoritative account/content state.
12. WebSocket delivery treated as durable message storage.
13. Client timestamp used as authoritative ordering.
14. Global cache flush as normal invalidation strategy.
15. Unbounded list rendering.
16. Loading full-resolution images in thumbnail slots.
17. Blocking app startup on analytics, ads, recommendation personalization, or other optional SDKs.
18. Logging secrets, cookies, authorization headers, raw passwords, or full sensitive request bodies.
19. Database migration requiring synchronized deployment of every instance.
20. Introducing multi-region active-active writes before the product has a measured need and conflict model.

---

## 51. Reference standards and engineering anchors

The implementation should stay aligned with current primary standards/documentation rather than copying framework folklore. Relevant anchors include:

- IETF HTTP specifications and caching semantics.
- IETF cookie specifications and browser security behavior.
- QUIC / HTTP/3 specifications for modern transport.
- PostgreSQL current documentation for indexing, replication, partitioning, monitoring, and transactional semantics.
- Apache Kafka current documentation for durable event streaming, idempotent producers, transactions, and processing semantics.
- OpenTelemetry specifications and semantic conventions for traces, metrics, logs, resources, and context propagation.
- Platform-specific Apple and Android guidance for secure credential storage, background execution, universal/app links, media playback, and network behavior.
- W3C/Web Performance and browser performance APIs for real-user measurement.

**Important:** standards define primitives. Product architecture still owns the policy: cache lifetimes, session expiration, retry budgets, consistency classes, SLOs, and degraded behavior.

---

# Final directive

The platform should feel simple to the user precisely because the engineering organization is disciplined about complexity underneath it.

The governing architecture is:

```text
IMMUTABLE IDENTITY
       +
LOCAL-FIRST CLIENT STATE
       +
GLOBAL EDGE DELIVERY
       +
SHALLOW SYNCHRONOUS REQUESTS
       +
AUTHORITATIVE DOMAIN OWNERSHIP
       +
INTENTIONAL CACHE HIERARCHY
       +
DURABLE ASYNCHRONOUS EVENTS
       +
SPECIALIZED MEDIA / REALTIME / SEARCH PLANES
       +
IDEMPOTENCY + DEADLINES + DEGRADATION
       +
END-TO-END OBSERVABILITY
       =
A PLATFORM THAT FEELS INSTANT EVEN WHEN THE SYSTEM IS NOT
```

Do not optimize for architectural fashion. Optimize for predictable latency, correct state, graceful failure, developer velocity, and the ability to understand what happened when any one of those properties degrades.
