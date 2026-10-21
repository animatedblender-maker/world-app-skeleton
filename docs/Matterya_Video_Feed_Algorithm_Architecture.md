# Matterya — Personalized Video Feed: Algorithm, Non-Repetition & Lightweight Architecture

**Engineering design specification | Version 1.0 | 21 October 2026**  
**Target stack:** Angular standalone + Capacitor mobile, NestJS GraphQL, PostgreSQL/Supabase, object storage + CDN, Redis (optional).  
**Status:** Proposed architecture and starting heuristics; calibrate thresholds with real measurement.  
**Scope:** Personalized **For You** short-video feed. Following, search, saved videos, creator profiles, shares, and direct links may intentionally replay a video; those surfaces must not silently inherit the For You no-repeat policy.

## 0. Executive decision

**Do not run the recommendation algorithm or transmit the video catalog to the phone.** The app receives only a small ranked batch of video metadata and streaming URLs. All complex candidate generation, filtering, ranking, deduplication, and model updates occur on backend services. The video bytes stream through a CDN, not the GraphQL API. Client-side work is limited to rendering, buffering a few items, collecting playback events, and requesting the next batch.

**Default product guarantee:** A video *successfully delivered as part of a For You batch* is not recommended again to that same account on that surface. This is a strict **at-most-once server delivery** promise, not proof that the person physically saw it. The two concepts cannot be perfectly aligned in the presence of network loss: if the response was lost after the backend committed the delivery, it may be marked delivered but unseen. Design the user experience around this explicit tradeoff. Every item also has a separately measured `impression` (rendered/on-screen) event for recommendation learning.

**Critical rule:** When available unseen videos run out, show an end-of-new-content state, a Following feed, creator profiles, search, or an explicit *Replay watched videos* mode. **Never secretly relax the no-repeat guarantee.**

## 1. Objectives, non-goals and acceptance criteria

### Objectives
1. Different video order for different people, with rapid adaptation to their signals.
2. Never deliver the same canonical video twice in For You to the same registered user, across logins, app restarts, devices, or web/mobile surfaces.
3. Avoid exact duplicate uploads and near-identical reuploads where confidence is sufficiently high.
4. Keep mobile bundle small, playback responsive, and backend costs controllable.
5. Enforce moderation, access policy, blocks, location restrictions, and rights before delivery.
6. Include cold-start creators and exploration, without using popularity as the sole quality metric.
7. Provide transparent controls: Not Interested, mute creator, hide topic, reset interests, delete activity; explain that **resetting interests does not reset delivered history**.

### Non-goals for v1
- A large client-side neural network, continuous location tracking, speech analysis on the phone, or full-catalog downloads.
- A guaranteed inference of the person's actual intentions or emotions.
- Exact predictions calibrated before sufficient logged interaction data exists.
- Claims that engagement metrics alone measure video quality or user satisfaction.

### Initial target SLOs (engineering targets, not proven benchmarks)
- Feed metadata API: p95 <= 300 ms on cache hit; p95 <= 800 ms on normal backend path, excluding client internet time.
- GraphQL response: typically 10–15 cards, target <= 30–60 KB compressed, **no media bytes**.
- First video playback start: target p75 <= 1.5 s on healthy mobile connectivity; measure separately for Wi-Fi/mobile.
- Failed playback start < 1% on supported devices after retry policy; track by network class.
- Duplicate *canonical video ID* delivered for same user in For You: **0** under supported authenticated, server-mediated delivery paths.
- Batch fetch availability >= 99.9% monthly target; graceful fallback to a simpler SQL ranker.
- p95 scroll/render frame performance: target no visible jank, >= 55 FPS on agreed reference devices.

## 2. How big platforms keep apps lightweight

The frontend is a **thin playback and interaction client**. It does NOT contain the recommendation model, video catalog, or multi-year event history. Backend operations are divided by frequency:

| Operation | Where it happens | Frequency | Why it is lightweight on device |
|---|---|---|---|
| Playback/UI and viewability checks | Angular/Capacitor client | During session | Small state machine, limited player pool |
| Candidate retrieval | Backend Postgres, optional search/vector system | Each batch | Only IDs and indexed metadata processed server-side |
| Hard eligibility / delivered-ID filter | Backend SQL | Each batch | Server-owned user state; never download histories |
| Rank 100–1000 candidates | NestJS worker/service or model-serving endpoint | Per batch | Client gets only top 10–15 |
| Aggregate user-topic/creator affinities | Async worker/stream | Continuously or periodically | Server computes compact profile vectors |
| Moderate/transcode/thumbnail/extract tags | Upload worker | Once per upload | Heavy work off the phone during consumption |
| ML retrain (future) | Offline jobs | Daily/weekly | No mobile model updates required |
| Serve HLS segments | CDN/object storage | As playback advances | Adaptive bitrate, cache near viewers |
| Collect interaction events | Ingestion endpoint + queue | Batched on client | Small JSON events, not synchronous model training |

**Architecture:**

```text
Angular / Capacitor app
  ├── fetch feed metadata (GraphQL over HTTPS)
  ├── play one video (HLS via CDN)
  ├── prefetch next 1–2 manifests / first segments (bounded)
  └── batch playback events (HTTPS)
        │
        ▼
NestJS API/BFF — session, authorization, per-user rate limits
        ├── Feed Orchestrator
        │     ├── Candidate Sources (followed, topic, fresh, regional, explore)
        │     ├── Hard Policy Filter (moderation, block, visibility, rights)
        │     ├── Ranking + Diversity
        │     └── Atomic Delivery Reservation (PostgreSQL unique key)
        ├── User Profile / Feature Store (Postgres initially; Redis optional)
        ├── Event Ingestion (idempotent)
        └── Video Metadata
              │
              ▼
       Postgres / Supabase

Upload -> Object Storage -> Async transcoding / thumbnails / safety checks
                             -> HLS renditions -> CDN -> client video player

Events -> Queue / Outbox -> Feature aggregation -> updated user affinity vectors
```

**Do not confuse CDN caching and ranked-feed caching.** HLS/video files are globally cacheable via CDN with access-aware URL design; personalized batches are private and short-lived, with durable per-user reservations. A CDN must never cache one user's private recommended feed for another user.

## 3. Content model and canonical identity

Every uploaded asset receives `video_id` (UUID). Separately store:
- `canonical_video_id`: ID of the original/representative item for deduplication; defaults to own `video_id`.
- `content_fingerprint`: high-confidence exact file digest plus perceptual fingerprints, computed asynchronously.
- `creator_id`, `created_at`, duration, language, topic tags, title/caption, visibility, region/copyright limitations, moderation state, age classification, rendition/thumbnail references, engagement counters, quality statistics.
- `video_status`: processing / ready / blocked / deleted.

**Rule:** Normal feed delivery counts by `canonical_video_id`; if a previously seen video is reuploaded as a known duplicate, it remains excluded. Exact SHA-256 equality can auto-link. Perceptual similarities must use conservative thresholds and human review for ambiguous or substantially remixed material. Do not falsely collapse reactions, duets, commentary, or permitted transformative adaptations.

Version the canonical mapping, and implement merge reconciliation: if video B is later proven duplicate of A, future feed requests exclude either if either was delivered. Historic ledger entries are retained for audit, while a canonical family lookup resolves equivalence. A simple unique key on `(user_id, video_id)` alone does **not** solve late duplicate merges.

## 4. Database schema (PostgreSQL)

Core example; adapt to existing user/video tables, use UUIDs and schema names actually present. Keep raw impression/event analytics in time-partitioned tables as volume grows.

```sql
CREATE TABLE feed_video_delivery (
  user_id UUID NOT NULL,
  canonical_video_id UUID NOT NULL,
  first_video_id UUID NOT NULL,
  delivery_id UUID NOT NULL UNIQUE,
  batch_id UUID NOT NULL,
  delivered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, canonical_video_id)
);
CREATE INDEX feed_video_delivery_user_time_idx
  ON feed_video_delivery (user_id, delivered_at DESC);

CREATE TABLE feed_batch (
  batch_id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  idempotency_key TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('building','complete','failed')),
  UNIQUE (user_id, idempotency_key)
);

CREATE TABLE feed_batch_item (
  batch_id UUID NOT NULL REFERENCES feed_batch(batch_id),
  position INT NOT NULL,
  delivery_id UUID NOT NULL REFERENCES feed_video_delivery(delivery_id),
  video_id UUID NOT NULL,
  PRIMARY KEY (batch_id, position),
  UNIQUE (batch_id, delivery_id)
);

CREATE TABLE feed_event (
  event_id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  delivery_id UUID NULL,
  video_id UUID NOT NULL,
  event_type TEXT NOT NULL,
  watch_ms INT,
  visible_ms INT,
  session_id UUID NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  properties JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX feed_event_user_received_idx ON feed_event(user_id, received_at DESC);

CREATE TABLE user_topic_affinity (
  user_id UUID NOT NULL,
  topic_id BIGINT NOT NULL,
  affinity DOUBLE PRECISION NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id, topic_id)
);

CREATE TABLE user_creator_affinity (
  user_id UUID NOT NULL,
  creator_id UUID NOT NULL,
  affinity DOUBLE PRECISION NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id, creator_id)
);
```

**Access control:** All of these tables are server-controlled and not directly writable or broadly readable by the browser's Supabase credentials. Use privileged backend roles narrowly, transactionally, and audit modifications. Never expose per-user delivery history to other users. Evaluate RLS and service-role isolation per deployment.

**Scaling note:** A permanent row per user/video delivery grows approximately as `daily_active_users × daily_delivered_videos × retention_days`; estimate storage including indexes, replicas, and backups before committing to retention. If 'never' means forever, do not TTL or delete the exclusion ledger as a routine optimization. You may partition/compress/encode it, but must preserve a reliable membership check. Account deletion and applicable privacy rights require a defined separate policy and legal review; do not promise both unconditional forever retention and unconditional erasure without resolving the conflict.

## 5. Feed request, atomic reservation, and idempotency

### Delivery definition
A delivery is **committed by the server before returning a successful feed response**. Retrying the *same logical request* must return the exact previously committed ordered batch, not consume additional unseen videos. A new request uses a new idempotency key.

### Transaction rules
1. Authenticate `user_id` from server session; never trust a client-supplied account ID.
2. Validate request input (`limit` 1–20), surface=`FOR_YOU`, idempotency key, device/session identifiers.
3. If `(user_id,idempotency_key)` already exists and is `complete`, fetch exactly its committed items and return them in original order; if processing, wait briefly or return a retryable state. **This replay of the same HTTP operation is not a new recommendation.**
4. Generate/rank candidate IDs outside the database transaction (do not keep a transaction open during external inference calls).
5. Start a short DB transaction. Atomically claim the batch idempotency key and mark it building. Handle concurrent claims via unique-constraint retry/re-read, not `SELECT` then independent `INSERT`.
6. Lock/serialize reservation within this user as needed (transaction-scoped advisory lock on a stable user key or row lock) to avoid duplicate batch races and simplify ordered results. Lock must be bounded in time.
7. For each ranked candidate, insert delivery with `ON CONFLICT DO NOTHING`; only if inserted count=1 add `feed_batch_item` at the next position.
8. Re-run eligibility/visibility constraints before committing, because a candidate may have been removed after ranking.
9. Commit batch + delivery rows together; mark batch `complete`, return committed items.
10. If insufficient candidates due to conflicts, request one additional ranked pool; never insert a duplicate or weaken policy. Return a shorter batch or empty-state if exhausted.
11. Persist `batch_id`, `delivery_id`, and cursor in response; no need to persist entire feed media payload if it can be hydrated from video metadata.

**Cross-surface nuance:** If the same video appears in Following, profile, saved, or shared link, it can be played there. Optionally record non-For You impressions for ranking, but do **not** mark its For You ledger unless product explicitly wants cross-surface suppression. Document and test the choice.

### SQL reservation fragment (inside an already-open transaction)

```sql
INSERT INTO feed_video_delivery
  (user_id, canonical_video_id, first_video_id, delivery_id, batch_id)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (user_id, canonical_video_id) DO NOTHING
RETURNING delivery_id;
```

**Important implementation limitation:** A unique canonical key handles known duplicates only. Resolve dynamically merged canonical families with a canonical-family membership table or equivalence lookup *before* reservation, and recheck on read. The dedup resolver must not rely only on stale cached video metadata.

## 6. Candidate generation (retrieve broadly, then rank narrowly)

Run several indexed queries in parallel, merge by `canonical_video_id`, then hard-filter. Initial budgets are tunable, not fixed laws:

| Source | Initial budget (up to) | Logic |
|---|---:|---|
| Followed creators | 150 | Recent approved content from followed creators |
| Topic affinity | 300 | Topic overlap and similar captions/tags |
| Trending within language/region | 150 | Time-decayed, quality-normalized trends |
| New/underexposed creators | 150 | Eligible low-impression, quality-checked uploads |
| Exploration | 150 | Controlled random sampling from safe eligible pool |
| Similar-to-liked content | 100 | Same topic / creator similarity; embeddings later |

Merge to ~300–900 unique eligible candidates, then rank. Use efficient indexed retrieval and cap candidate counts. If no behavioral history, derive initial preferences from optional onboarding choices, selected language/region, and a balanced exploratory set; do not infer sensitive traits without a valid basis.

Hard filters **before ranking and before delivery**:
- Video `ready`, public or otherwise entitled, approved for recommendations, age appropriate and rights-valid.
- Creator not blocked/muted; video not reported as hidden by this user; content not removed.
- User/video language and regional restrictions; enforce legal/geographic access where relevant.
- Not in server-side delivery ledger, canonical duplicate family, current uncommitted/committed reservation set.
- Exclude restricted hashtags or hidden topics; allow user preferences to be stronger than trend ranking.
- Respect configurable creator frequency limits and safeguard against repeated near-duplicate scenes.

Example indexed SQL retrieval (simplified):

```sql
SELECT v.id, v.canonical_video_id, v.creator_id, v.created_at,
       v.duration_ms, v.language, v.quality_score
FROM videos v
WHERE v.status = 'ready'
  AND v.recommendation_eligible = TRUE
  AND v.created_at >= now() - interval '30 days'
  AND NOT EXISTS (
    SELECT 1 FROM feed_video_delivery d
    WHERE d.user_id = $1
      AND d.canonical_video_id = v.canonical_video_id
  )
ORDER BY v.created_at DESC
LIMIT 300;
```

This is an illustrative fallback, **not** a full candidate query: `ORDER BY created_at` alone gives a recency-only feed, ignores regional and access restrictions, and can become costly. Build per-source indexed retrieval and explicit hard-filter stages. For very large ledgers or catalogs, benchmark query plans and alternative exact-membership storage; Redis Bloom filters are only a *prefilter* (false positives) and cannot be the sole guarantee.

## 7. V1 per-user ranking algorithm (fully specified)

All features are normalized to `[0,1]`, measured as of request time, and computed on the backend. Start with an understandable heuristic before training a neural ranker.

Definitions:

- `T` topic affinity: weighted average of the user's affinities for this video's topic IDs, mapped into 0–1.
- `C` creator affinity: mapped affinity to creator, 0.5 for unseen creator.
- `W` expected watch completion probability estimated from bucketed behavior for the user's topics, duration bucket, and language; backed off to cohort priors for sparse users.
- `Q` content quality: Bayesian-smoothed completion, hides, reports, and engaged views; restrict inputs to moderation-cleared events; limit spam/bot manipulation.
- `F` freshness: `exp(-age_hours / 120)`; can adjust half-life and use fresh-content buckets.
- `L` language fit: 1.0 preferred language, 0.6 supported second language, else 0.2 if understandable without audio; hard access rules remain separate.
- `N` novelty/exploration: 1.0 for appropriately novel creator/topic in eligible exploration pool; lower for very similar sequences.
- `S` social affinity: creator follow and relevant friend interest, 0–1; avoid leaking private friend activities.
- `H` negative feedback penalty: 0–1 based on Not Interested, frequent immediate skips, topic fatigue, and hides; explicit blocking belongs in hard filters.

**Base score** (starting coefficients; tune through experiments):

```text
score(u,v) =
    0.22*T + 0.12*C + 0.20*W + 0.14*Q
  + 0.08*F + 0.08*L + 0.10*N + 0.06*S
  - 0.25*H
```

Score is *relative* and not a calibrated probability. No raw follower-count boost. Clip/normalize features consistently. Missing values receive documented priors, not accidental zeros. Ensure longer videos are not automatically punished by completion rate alone: combine normalized completion with **satisfied watch seconds** and duration-conditioned baselines.

### Pseudocode

```python
def get_for_you(user_id, request_id, requested_limit=12):
    previous = get_committed_batch(user_id, request_id)
    if previous:
        return hydrate_and_return_same_batch(previous)

    profile = load_user_features(user_id)  # small backend feature row
    pools = retrieve_sources_parallel(profile, budget=900)
    candidates = dedupe_by_canonical_family(pools)
    candidates = hard_filter(candidates, user_id, profile)

    scored = []
    for v in candidates:
        f = normalized_features(user_id, v, profile)
        score = (
            .22*f.topic + .12*f.creator + .20*f.watch
            + .14*f.quality + .08*f.fresh + .08*f.language
            + .10*f.novelty + .06*f.social - .25*f.negative
        )
        scored.append((v, score))

    ranked = diversity_rerank(scored, max_same_creator_in_10=2,
                              max_same_topic_in_10=4,
                              exploration_target=.15)

    # The service MUST enforce the unique delivery constraint atomically.
    batch = reserve_new_batch_transactionally(user_id, request_id,
                                              ranked, requested_limit)
    return hydrate_and_return(batch)
```

### Diversity re-ranking
Greedy choose next video maximizing:

```text
selection_score(v | selected) =
    score(u,v)
    - 0.16 * max_similarity(v, selected_last_5)
    - 0.10 * creator_frequency_penalty(v, selected_last_10)
    + 0.04 * underexposed_creator_bonus(v)
```

Initial policy targets: >= ~10–20% exploration slots in a full batch, <= 2 videos per creator per 10, <= 4 from same top-level topic per 10, no direct back-to-back same creator. **These are soft targets, not hard guarantees**: do not block results entirely when supply is small. Remove exploration bonus for policy-ineligible content. Use deterministic seeded tie-breaking keyed to `(user_id, batch_id)` for debugging, never client-side random shuffling after reservation.

### Safe experiment handling
Position bias matters: randomize limited exploration across positions, log rank position and source, and use holdouts when evaluating. Do not train based solely on click/engagement from a fully deterministic exposure policy; logged outcomes are selection-biased. Prioritize satisfaction and 'Not Interested' rates alongside watch time.

## 8. Event collection and updating interests

Events: `batch_received` (diagnostic), `impression` (on-screen threshold), `play_start`, `heartbeat`, `pause`, `resume`, `complete`, `rewatch`, `like`, `unlike`, `save`, `unsave`, `share`, `follow`, `comment`, `not_interested`, `hide_topic`, `block_creator`, `report`, `playback_error`.

Client impression policy (starting hypothesis): >=50% of video visible for >=300 ms with app foregrounded; only once per delivery. Measure actual playback started and milliseconds watched separately. The client batches events every 5–10 seconds and on app background, with bounded retries and disk queue limits. Events carry `event_id` for server idempotency; timestamps are untrusted metadata; server validates ownership of `delivery_id`, valid video IDs, and reasonable durations to suppress fraud.

Example event contribution to topic preference (tune empirically):

| Signal | Increment per mapped topic |
|---|---:|
| Watched >= 90% and >= 3 s | +3 |
| Watched 40–90% | +1 |
| Like | +3 |
| Save / share | +4 |
| Follow creator | +2 to creator affinity |
| Skipped < 2 s and < 10% | -2 |
| Not interested | -6 |
| Hide topic | Strong persistent explicit negative filter |
| Report | Route to safety workflow; do not treat as ordinary preference only |

For signals, avoid double-counting a single event (e.g., `complete` and final heartbeat). Normalize by duration, cap the number of events per item, and only count authenticated, verified client ownership. A user may fully watch content they dislike; explicit negative feedback must override inferred positive completion.

Exponential time decay for each topic/creator accumulator:

```text
new_affinity = clamp(old_affinity * exp(-elapsed_days / 30) + event_delta,
                     -20, +20)
normalized_affinity = sigmoid(new_affinity / 5)
```

Decay is applied lazily/through batch jobs. Store `updated_at`. Explicit blocked creators/topics are never decayed away automatically. Compute user-feature updates asynchronously so event ingestion does not slow scrolling. Can start with a scheduled NestJS job and Postgres outbox, add Redis/queue workers only when needed.

## 9. API contracts (suggested GraphQL)

```graphql
scalar DateTime

type FeedVideo {
  id: ID!
  canonicalVideoId: ID!
  deliveryId: ID!
  creator: PublicCreator!
  caption: String
  durationMs: Int!
  posterUrl: String!
  playback: PlaybackDescriptor!
  recommendationReason: String
}

type PlaybackDescriptor {
  manifestUrl: String! # HLS, signed if necessary
  expiresAt: DateTime
}

type FeedPage {
  batchId: ID!
  items: [FeedVideo!]!
  hasMore: Boolean!
  exhausted: Boolean!
}

input FeedRequest {
  idempotencyKey: ID!
  limit: Int = 12
  surface: String! = "FOR_YOU"
}

input PlaybackEventInput {
  eventId: ID!
  deliveryId: ID
  videoId: ID!
  eventType: String!
  watchMs: Int
  visibleMs: Int
  occurredAt: DateTime!
  sessionId: ID!
}

type Query {
  forYouFeed(input: FeedRequest!): FeedPage!
}

type Mutation {
  recordVideoEvents(events: [PlaybackEventInput!]!): Boolean!
  notInterested(videoId: ID!): Boolean!
  blockCreator(creatorId: ID!): Boolean!
  resetFeedInterests: Boolean!
}
```

For large ingestion volume a REST endpoint `POST /feed/events` can be cheaper and easier than GraphQL; GraphQL is fine initially. Enforce auth, request size, input ranges, rate limits, validation, and service identity on either protocol. Signed media URLs should be short-lived but not expire during normal buffered playback; support refresh.

**Pagination:** request the next batch *before* the current list empties (e.g., 3 videos remaining). Use a fresh idempotency key for each genuine batch; retry the previous key for timeouts. Cursor/page numbers are not sufficient to guarantee uniqueness because the ranking and candidate pool evolve. The database ledger is the authority.

## 10. Mobile client — implementation contract

- Angular page renders **one active video player**, optionally 1 prebuffered next player; release decoded video resources for distant cards.
- Fetch ~10–15 metadata records; maintain at most ~20–30 cards in local list, virtualize/drop old DOM nodes.
- HLS through native or platform-supported player; adaptive bitrate renditions (e.g., 240p/360p/540p/720p as appropriate); cap on cellular/data-saver mode.
- Download poster images with efficient image sizing. Prefetch at most next 1–2 videos with strict bandwidth/device-memory and power constraints; avoid preloading all videos.
- `IntersectionObserver`/native viewability triggers visibility signals; app lifecycle pauses media and batching.
- Debounce rapid swipes, cancel obsolete requests, protect against duplicate event emissions, and prevent multiple players playing audio.
- Include data-saver, mute, autoplay controls, captions, and accessibility features.
- No recommendation weights/model/code shipped as secrets; client UI ranking should preserve server order.
- Cache non-sensitive metadata temporarily and media segments according to signed URL policy. Do not use a pre-cached feed across accounts or claim cached data is newly delivered without prior server reservation.
- Offline: permit **explicitly downloaded/saved** replay outside For You; don't invent new For You deliveries offline. On reconnection, sync events idempotently.
- Device switch: same authenticated account -> same backend ledger, so global suppression applies.

### Suggested Angular service outline

```ts
interface FeedVideo { id: string; deliveryId: string; /* other metadata */ }

class VideoFeedService {
  private videos: FeedVideo[] = [];
  private inFlight = false;
  private retryKey: string | null = null;

  async fetchMore() {
    if (this.inFlight) return;
    this.inFlight = true;
    const key = this.retryKey ?? crypto.randomUUID();
    this.retryKey = key;
    try {
      const page = await this.graphql.fetchForYou({ idempotencyKey: key, limit: 12 });
      // Keep this.retryKey during a failed/ambiguous request; a successful response completes it.
      this.videos.push(...page.items.filter(v => !this.videos.some(x => x.id === v.id)));
      this.retryKey = null;
    } finally {
      this.inFlight = false;
    }
  }
}
```

This is illustrative only; integrate service dependencies, persistence of pending request keys across app suspension, max-length trimming, and a per-video player state machine. The client-side filter is for defensive rendering only: **it is not the no-repeat guarantee**.

## 11. Streaming, storage and CDN

1. Upload raw video directly to object storage using scoped signed upload URLs, not through the NestJS process.
2. Send upload event; async queue transcodes to several HLS renditions and generates thumbnails, normalized audio, captions (where available), metadata/tags, and fingerprints.
3. Run copyright/policy checks as required; only set `ready` and `recommendation_eligible` after required checks.
4. Serve HLS manifest/segments via a CDN. Keep segment URLs cacheable, handle access controls securely, and never ship storage admin credentials.
5. Set bitrate ladders based on actual mobile network measurements; HLS manifest is tiny, segments streamed on demand.
6. Support deletion/takedown and prompt CDN invalidation/revocation workflows, recognizing cached content limitations.
7. Scale separate resources independently: API CPU, DB throughput, transcoding workers, storage/egress, and CDN bandwidth.

**Supabase warning:** If egress is a concern, measure playback traffic separately from metadata traffic. Video delivery dominates bytes; switching the ranking algorithm will not solve streaming-egress costs. Use an appropriate media hosting/transcoding/CDN stack and calculate per-view costs with an assumed average viewed duration and bitrate.

## 12. Caching and scalability roadmap

**At launch (simplest reliable stack):** NestJS monolith modules (`feed`, `video`, `events`, `recommendation`), Supabase Postgres, object storage, external transcoder/CDN. Postgres indexed queries, local bounded in-memory feature cache (optional), background aggregation via jobs/outbox. Keep atomic delivery transactions entirely in Postgres.

**At growth:** Redis for cached user features/trending pools/ranking artifacts (short TTL, never as sole record of watched IDs); dedicated queue for events/transcoding; separate recommendation worker process; cache popular candidate pools, not committed per-user delivery decisions. Use Postgres read replicas for retrieval if appropriate while writes and strict no-repeat reads remain consistent with the primary; replicas lag and must not govern dedup claims.

**At large scale:** Dedicated feature store; approximate nearest-neighbor embeddings for candidate retrieval; trained multi-task ranker; streaming data pipeline; event warehouse; sharded/partitioned delivery history with exact membership semantics; multi-region routing carefully designed to preserve one authoritative reservation path per user.

**Avoid premature dependencies:** Kafka, Kubernetes, a vector DB, and multiple microservices are not prerequisites for the first correct version.

## 13. Fallback behavior

| Situation | Required behavior |
|---|---|
| Reopen app | New request gets unseen videos; completed old batch may be rehydrated only on retry or explicit Resume Session, not counted as a fresh recommendation |
| Same network request times out | Retry same idempotency key; never generate a second batch accidentally |
| Two devices simultaneously | DB unique constraint and per-user reservation serialization prevent duplicate delivery |
| Video removed after delivery | Skip on frontend or return `unavailable`, do not resurrect it |
| Video fails to play | Log error; by default keep delivered in ledger; offer explicit retry/replay of same item outside new recommendations |
| App crashes after response sent | Delivered items stay excluded; this sacrifices unseen items to preserve strict no-repeat |
| User scrolls past instantly | Still delivered and excluded; log skip/impression separately |
| Not enough unseen videos | Return partial batch/empty state; never recycle without explicit user action |
| User presses refresh | Request new batch, not previous watched videos |
| User resets interests | Reset affinity model, **not** non-repeat ledger |
| Creator reuploads exact same file | Fingerprint and canonical mapping exclude confidently matching duplicate |
| Late canonical merge | Check alias-family historical exposure at request time and reconcile affected mappings |
| Offline | No new personalized delivery; saved items can be replayed via another explicitly labeled surface |
| Anonymous tab | Keep entirely separate access and identity policies; **do not link anonymous community actions to normal feed features** without express privacy design and consent |

## 14. Security, privacy, fairness, wellbeing

- Check account age classification, sensitive content thresholds, blocks, geographic rights, and safety status **before sending recommendations**.
- Moderate both uploads and community reports; emergency takedown must supersede cached rankings.
- Restrict access to raw watch history and inferred interests; encrypt data at rest/in transit and use least-privilege roles. Document retention, consent/legitimate basis, deletion and portability requirements with counsel, including EU GDPR/DSA and applicable laws.
- Avoid profiling sensitive traits without a justified legal basis and appropriate protections. Offer meaningful feed preference controls and an accessible alternative where required.
- Bot-resistant signals: clamp repeated self-generated play counts, verify event delivery ownership, detect unnatural patterns, rate-limit bulk reactions.
- Explanations can say 'Because you watch science videos' or 'New creator', but never disclose another user's private actions.
- Track creator exposure fairness: distribution by creator size, new creator opportunity, undue amplification, and policy/report rates.
- Optimize for viewer satisfaction in addition to engagement; add session breaks and controls that do not force infinite scrolling.

## 15. Quality assurance and test cases

**Unit tests:** feature normalization; duration conditioned metrics; smoothing/decay; duplicate resolution; diversity ranking; feedback overrides; eligibility gating; deterministic tie breaks; cold-start priors.

**DB integration tests:** unique `(user_id,canonical_video_id)` under concurrent requests; identical idempotency-key returns same order; transaction rollback on error; only returned items are reserved; blocked content cannot be committed; duplicate family mappings; privacy isolation of server-only tables.

**End-to-end tests:** app restart, login/logout, second device, background/resume, slow network, lost HTTP response, rapid swiping, short batches, exhausted library, signed URL expiration, post-delivery takedown, preference reset, event queue duplicates, offline playback, high contention.

**Load tests:** 100/1,000/10,000 concurrent users under synthetic profiles. Capture DB query plans, unique-conflict rates, API p50/p95/p99, event ingestion throughput, CPU/memory, DB connections and locks, CDN hit rate, stream start time, and real cost/1,000 views.

**Launch gate:** Demonstrate 0 duplicate committed For You deliveries in the acceptance test suite, confirm observable on-screen duplicate rate, meet agreed API/player SLOs, verify takedown, privacy and incident runbooks, and establish an A/B guardrail dashboard.

## 16. Analytics and experiment metrics

- Delivery-to-impression ratio (important: strict at-most-once delivery may waste videos on lost responses).
- First frame time, buffering ratio, failed playback, video abandonment, crash rate, API request latency.
- Watch time per delivered and per impression, completion by duration bucket, long-session vs satisfaction proxy.
- `not_interested` and hide/report rates per 1,000 impressions.
- D1/D7 retention, meaningful positive actions, session frequency, creator diversity and low-exposure creator reach.
- Recommendation duplicate rate from durable ledger = 0, separate from near-duplicate perceptual error rate.
- Query cost, object-storage / transcoding / CDN egress cost per 1,000 delivered watches.

Feature flags: `ranking_version`, `candidate_weights`, `diversity_limits`, `exploration_rate`, `event_sampling`, `prefetch_count`, `delivery_policy`. Log model version on batch, preserve experimental allocation per user, and provide safe rollback to heuristic ranking. The no-repeat constraint remains immutable across experiments.

## 17. Implementation phases / team tickets

**Phase A — foundations:** Add canonical IDs, status/eligibility fields, HLS assets, DB constraints; migration and monitoring; implement authenticated GraphQL feed endpoint; exact per-account reservation + idempotency + concurrency tests.

**Phase B — v1 ranking:** Implement indexed candidate sources, hard filters, feature tables, heuristic scorer, diversity re-ranker, and controlled no-content fallback.

**Phase C — client:** Implement video player pool, virtualized scrolling, bounded prefetch, lifecycle handling, server-ordered batches, impression/playback events and retries.

**Phase D — signals:** Add secure event ingestion, Postgres outbox/queue, decayed topic/creator affinities, controls (Not Interested, hide topic, blocked creator), analytics dashboards.

**Phase E — robustness:** Duplicate fingerprinting, late canonical merges, download/network error handling, app restart/multi-device test matrix, takedowns and safety audit.

**Phase F — optimization:** Load tests, SLO alerting, CDN bitrate tuning, cost monitoring, A/B testing. Only introduce advanced retrieval/ML when enough data shows better performance.

### Suggested team ownership
- Backend: feed orchestrator, Postgres transactions, events, APIs, safety filtering.
- Mobile/frontend: player lifecycle, pagination, prefetch, telemetry, user controls.
- Media infrastructure: uploads, transcodes, manifests, CDN, retention and deletion.
- Data/ML: metrics, feature extraction, scorer, experimentation, fairness evaluation.
- Trust/privacy: age/policy gates, abuse, account deletion and audit.

## 18. Decisions to confirm before implementation

1. **Primary promise:** Strict 'never delivered twice' (recommended), or 'never actually seen twice' (requires a different acknowledgment-based state and cannot guarantee both no repeats and no skipped unseen items under network failures).
2. Does watching a video in a profile, search or Following prevent subsequent For You delivery? Recommended **no** initially; keep explicit definitions by surface.
3. Is a **voluntary replay mode** allowed? Recommended yes, clearly separated from For You and excluded from delivery uniqueness claims.
4. Are feed impressions and interests used across the normal and Anonymous tab? Recommended **no cross-context linking** without a reviewed privacy architecture.
5. How will deletion/legal privacy requests interact with the 'forever' exposure ledger? Needs legal/product decision, not a silent engineering shortcut.
6. Which media provider/transcoder and CDN meet Germany/EU legal, operational and cost requirements? Benchmark with real view data.

## 19. Quick answer for stakeholders

**Why doesn't the app become heavy?** Because the phone never executes the huge recommendation pipeline. It simply asks the API for 12 already-ranked videos, receives compact metadata, plays CDN-streamed adaptive video, and sends tiny interaction events. Background workers update user interests and media files. The exact no-repeat guarantee lives in a small, indexed server-side constraint, not in local device history.

**Why does it not repeat?** The feed's database transaction can reserve each canonical video for a user only once. A new app session filters out all reserved deliveries. Concurrent devices cannot defeat the unique constraint. Repeated HTTP retries reuse the original batch. Unknown duplicate reuploads remain an imperfect detection problem and should not be represented as an absolute guarantee.

## References (background architecture)

- Covington, Adams & Sargin, *Deep Neural Networks for YouTube Recommendations* (2016), https://research.google/pubs/deep-neural-networks-for-youtube-recommendations/ — established candidate generation → ranking architecture.
- TikTok, *How content is recommended*, https://support.tiktok.com/en/using-tiktok/exploring-videos/how-tiktok-recommends-content — public disclosure of interaction, content and user-context signals.
- TikTok 2024 annual online safety report, https://www.imda.gov.sg/-/media/imda/files/regulations-and-licensing/regulations/online-safety/tiktok-2024-annual-online-safety-report.pdf — described ranking, diversity and safety gates.

*The ranking weights, SLOs, table definitions and algorithmic policies in this document are Matterya-specific proposals, not proprietary specifications of YouTube or TikTok.*
