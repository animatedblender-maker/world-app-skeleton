# Entity · Content · Personality (design)

Matterya treats **users as Entities**. Content and engagement are signals.  
Kafka carries facts. **Personality** is a derived, evolving view of an Entity — not hand-typed labels.

Aligned with existing topics (`matterya.posts`, `matterya.engagement`, outbox pattern).

```
Entity ──produces/engages──► Content
   │                            │
   │                            ▼
   │                     matterya.engagement
   │                     matterya.posts
   │                            │
   │                            ▼
   │                   Personality worker
   │                            │
   └◄──── entity_personality ◄──┘
                    │
                    ▼
              Feed ranking (iOS)
```

---

## 1. Event schema (JSON + topics)

### Envelope (already used)

Same as chat — do not invent a second envelope:

```ts
type DomainEvent<T> = {
  eventId: string;          // uuid
  eventType: string;        // e.g. EngagementLiked
  eventVersion: number;     // start at 1
  occurredAt: string;       // ISO-8601
  producer: string;         // "matterya-api" | "matterya-ios"
  partitionKey: string;     // almost always entityId (the actor)
  correlationId?: string | null;
  payload: T;
};
```

### Topics

| Topic | Purpose | Partition key |
|-------|---------|----------------|
| `matterya.posts` | Content lifecycle (create/update/delete) | `authorId` |
| `matterya.engagement` | All interaction signals | **actor** `entityId` |
| `matterya.entities` *(optional later)* | Profile identity changes | `entityId` |
| `matterya.personality` *(optional later)* | Computed personality snapshots | `entityId` |
| `matterya.dlq` | Failed events | original key |

`matterya.engagement` already exists in `KafkaTopics` — use it.

### Content lifecycle (`matterya.posts`)

| eventType | When |
|-----------|------|
| `ContentDrafted` | User saves draft (optional; privacy-sensitive) |
| `ContentPosted` | Post published |
| `ContentUpdated` | Body/media change |
| `ContentDeleted` | Soft/hard delete |
| `ContentShared` | Share / re-publish into a country feed |

```json
{
  "eventId": "…",
  "eventType": "ContentPosted",
  "eventVersion": 1,
  "occurredAt": "2026-07-31T04:00:00.000Z",
  "producer": "matterya-api",
  "partitionKey": "entity-uuid-author",
  "payload": {
    "entityId": "author-uuid",
    "contentId": "post-uuid",
    "mediaType": "image|video|none|link",
    "visibility": "public|country|followers",
    "countryCode": "DE",
    "cityName": "Berlin",
    "hubSlug": null,
    "isSpark": false,
    "isHubLongForm": false,
    "sharedPostId": null
  }
}
```

### Engagement (`matterya.engagement`)

Every row is: **this Entity did this to that Content**.

| eventType | Strength model |
|-----------|----------------|
| `EngagementLiked` | explicit +1 |
| `EngagementUnliked` | reverse like |
| `EngagementCommented` | high intent |
| `EngagementShared` | amplification |
| `EngagementWatchPartial` | `durationMs` + `progress` 0–1 |
| `EngagementWatchComplete` | watched to end |
| `EngagementScrollDwell` | stopped on post; `durationMs` |
| `EngagementScrollSkip` | scrolled past quickly |
| `EngagementSaved` / `EngagementUnsaved` | bookmark |
| `EngagementOpenedProfile` | soft social signal (optional) |

**Canonical engagement payload:**

```json
{
  "eventId": "…",
  "eventType": "EngagementWatchPartial",
  "eventVersion": 1,
  "occurredAt": "2026-07-31T04:01:12.000Z",
  "producer": "matterya-api",
  "partitionKey": "viewer-entity-uuid",
  "payload": {
    "entityId": "viewer-entity-uuid",
    "contentId": "post-uuid",
    "authorId": "author-entity-uuid",
    "countryCode": "DE",
    "hubSlug": "music",
    "mediaType": "video",
    "isSpark": false,
    "strength": 0.42,
    "durationMs": 8400,
    "progress": 0.35,
    "sessionId": "optional-client-session",
    "surface": "home|hubs|profile|reels|search|country",
    "deviceClass": "phone|mac|tablet"
  }
}
```

**Rules**

- `entityId` = actor (always).
- `authorId` = content owner (for “affinity to this creator”).
- `strength` ∈ `[0, 1]` — server or client-normalized (see §3).
- Prefer **server-side emit** for like/comment/share (trust).  
  Watch/scroll may start as **client → API batch → outbox** (anti-spam, sampling).
- Never put PII beyond IDs in Kafka (no display names in payload).

### Client → API batch (watch/scroll)

iOS should not open a Kafka connection. It posts:

```http
POST /v1/engagement/batch
Authorization: Bearer …
```

```json
{
  "sessionId": "…",
  "events": [
    {
      "type": "watch_partial",
      "contentId": "…",
      "durationMs": 8400,
      "progress": 0.35,
      "surface": "home",
      "occurredAt": "…"
    }
  ]
}
```

API validates, rate-limits, writes outbox → `matterya.engagement`.

---

## 2. Database tables

### `entity_engagement_events` (optional durable log)

Outbox is enough for Kafka; this table is for analytics/replay if you want Postgres history.

```sql
create table if not exists public.entity_engagement_events (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null unique,          -- same as Kafka eventId
  event_type      text not null,
  entity_id       uuid not null references auth.users(id) on delete cascade,
  content_id      uuid,                          -- null if not content-bound
  author_id       uuid,
  country_code    text,
  hub_slug        text,
  media_type      text,
  is_spark        boolean not null default false,
  strength        real not null default 0,
  duration_ms     integer,
  progress        real,
  surface         text,
  device_class    text,
  session_id      text,
  occurred_at     timestamptz not null,
  ingested_at     timestamptz not null default now()
);

create index if not exists entity_engagement_entity_time_idx
  on public.entity_engagement_events (entity_id, occurred_at desc);

create index if not exists entity_engagement_content_idx
  on public.entity_engagement_events (content_id, occurred_at desc)
  where content_id is not null;
```

### `entity_personality` (derived state — source of truth for ranking)

```sql
create table if not exists public.entity_personality (
  entity_id           uuid primary key references auth.users(id) on delete cascade,

  -- Scalar traits 0..1 (v0 rules; later model can overwrite)
  traits              jsonb not null default '{}'::jsonb,
  -- e.g. { "curiosity": 0.62, "social": 0.41, "impulsiveness": 0.28, "depth": 0.55 }

  -- Affinities (keys free-form, values 0..1, L2-normalized optional)
  country_affinity    jsonb not null default '{}'::jsonb,  -- { "DE": 0.9, "EG": 0.2 }
  hub_affinity        jsonb not null default '{}'::jsonb,  -- { "music": 0.7 }
  creator_affinity    jsonb not null default '{}'::jsonb,  -- { "author-uuid": 0.5 } top-N only
  media_affinity      jsonb not null default '{}'::jsonb,  -- { "video": 0.6, "image": 0.3, "spark": 0.8 }

  tends_to            text[] not null default '{}',        -- short human tags
  stats               jsonb not null default '{}'::jsonb,  -- counters for debugging

  -- Dense feature vector for similarity (v0: fixed order float array)
  feature_vector      real[] not null default '{}',
  feature_version     int not null default 1,

  events_counted      bigint not null default 0,
  window_start        timestamptz,
  window_end          timestamptz,
  updated_at          timestamptz not null default now(),
  model_version       text not null default 'rules-v0'
);

create index if not exists entity_personality_updated_idx
  on public.entity_personality (updated_at desc);
```

### `entity_neighbors` (optional, for KNN later)

```sql
create table if not exists public.entity_neighbors (
  entity_id     uuid not null references auth.users(id) on delete cascade,
  neighbor_id   uuid not null references auth.users(id) on delete cascade,
  distance      real not null,
  model_version text not null default 'rules-v0',
  updated_at    timestamptz not null default now(),
  primary key (entity_id, neighbor_id)
);
```

### Mapping to existing schema

| Concept | Existing |
|---------|----------|
| Entity ID | `profiles.user_id` / `auth.users.id` |
| Content | `posts` |
| Identity fields | `profiles.*` |
| Kafka durability | `kafka_outbox` (already) |

Do **not** fork a second “users” table. Entity = profile.

---

## 3. v0 Personality rules (no ML)

Worker: consume `matterya.engagement` (+ optionally `matterya.posts`), update `entity_personality` in batches (e.g. every 30–60s or every N events per entity).

### Strength defaults (if client omits)

| Signal | strength |
|--------|----------|
| like | 0.55 |
| unlike | −0.55 (or decay prior like) |
| comment | 0.85 |
| share | 0.75 |
| save | 0.70 |
| watch complete | 0.90 |
| watch partial | `0.15 + 0.75 * progress` (clamp 0–1) |
| scroll dwell | `min(1, durationMs / 8000)` |
| scroll skip | −0.25 if durationMs < 800 |

Use exponential time decay on aggregates, half-life **14 days**:

```
weight = strength * 0.5 ** (ageDays / 14)
```

### Trait updates (EMA — exponential moving average)

For each event, update trait `t`:

```
t ← (1 - α) * t + α * signal
α = 0.08   # slow learning; raise for new accounts
```

| Trait | Positive signals | Negative signals |
|-------|------------------|------------------|
| **curiosity** | watch complete, dwell, open hubs, diverse hubs/countries | skip, short dwell |
| **social** | comment, share, like on others’ posts, profile open | only self-posts, no comments |
| **depth** | long-form watch, long dwell, long comments | sparks-only, skips |
| **impulsiveness** | rapid like within 1s of open, many skips + many likes same session | slow deliberate watches |
| **locality** | engage same `countryCode` as entity home | always foreign countries |
| **creator_loyalty** | repeat engage same `authorId` | always new authors |

`tends_to` tags (string list, max ~12): if rolling counters exceed thresholds, e.g.:

- `watches_to_end` if complete_rate > 0.4  
- `comments_often` if comments / sessions > 0.3  
- `spark_native` if spark_engagement > 0.6 of video engagement  
- `hubs_explorer` if unique hubs in 7d ≥ 5  
- `skips_quickly` if skip_rate > 0.5  

### Affinity maps

On positive event (strength > 0):

```
country_affinity[cc]  += weight
hub_affinity[hub]     += weight
creator_affinity[aid] += weight
media_affinity[type]  += weight
if is_spark: media_affinity["spark"] += weight
```

Cap each map to top **20** keys by score; drop the rest.  
Normalize map values to max 1.0 (divide by max) for ranking use.

### Feature vector (fixed order, version 1)

Length 32 (pad zeros). Example layout:

```
[0] curiosity
[1] social
[2] depth
[3] impulsiveness
[4] locality
[5] creator_loyalty
[6..15] top-10 hub affinities (stable hub id hash → slot, or named top hubs)
[16..20] media: image, video, spark, link, none
[21..25] reserved country cluster
[26..31] reserved
```

**KNN later:** cosine distance on `feature_vector` among active entities → `entity_neighbors`.  
**v0 does not require KNN** for feed value.

### Cold start

New entity: traits at **0.5** neutral, empty affinities, `model_version = rules-v0`.  
Until `events_counted < 25`, ranking weight on personality ≤ 0.15 (see §4).

---

## 4. Feed ranking on iOS

### Principle

iOS should **not** run KNN.  
iOS receives an ordered list (or applies a thin client re-rank on a candidate set).

### Preferred path (server-ranked)

```
iOS HomeFeedStore
    → GraphQL homeFeed / recentPosts / personalizedFeed
    → API ranks candidates using entity_personality + post features
    → returns ordered posts
```

Add (when ready) GraphQL:

```graphql
personalizedHomeFeed(limit: Int, before: String): [Post!]!
```

Server score (v0):

```
score =
  0.35 * recencyScore(createdAt)           # hours decay
+ 0.20 * socialProof(likeCount, commentCount)
+ 0.25 * affinityScore(viewer, post)       # from personality
+ 0.10 * sameCountryBoost
+ 0.10 * followingBoost
− 0.15 * alreadySeenPenalty
```

**affinityScore(viewer, post):**

```
a = 0
a += 0.40 * country_affinity[post.countryCode]
a += 0.25 * hub_affinity[post.hubSlug]
a += 0.25 * creator_affinity[post.authorId]
a += 0.10 * media_affinity[post.mediaType or spark]
if personality.depth high && post is long-form: a += 0.05
if personality impulsiveness high && post is spark: a += 0.05
return clamp(a, 0, 1)
```

Cold start: if `events_counted < 25`, replace affinity term with **global popularity** only.

### iOS integration points (current code)

| File | Role |
|------|------|
| `HomeFeedStore.swift` | Holds ordered posts; call personalized query when available |
| `PostsService.loadHome…` | Network merge real + demo |
| `FeedView.swift` | Renders order from store — **do not re-sort randomly** |
| New: `EngagementTracker.swift` | Debounced watch/dwell/skip → batch API |
| `FacebookPostCard` / video player | Call tracker on appear/disappear/progress |
| Like / comment paths | Already server mutations → outbox engagement events |

### Client ranking fallback (until API personalization ships)

If server only returns chronological:

1. Keep demo merge as today.  
2. Optionally apply **local soft boost** using a small cached `PersonalitySnapshot` from:

   ```graphql
   mePersonality { traits countryAffinity hubAffinity … }
   ```

3. Soft boost only (stable sort key): never shuffle aggressively (hurts LazyVStack identity).

```swift
// Pseudocode
func localBoost(_ post: CountryPost, p: PersonalitySnapshot) -> Double {
  var s = 0.0
  if let c = post.countryCode { s += 0.4 * (p.countryAffinity[c] ?? 0) }
  // hub / media similar…
  return s
}
// sort: (-boost, -createdAt)  // secondary key = time
```

### What NOT to do on iOS

- Full KNN in-app  
- Per-scroll network personality recompute  
- Different personality logic on Mac vs phone (same API)

### Instrumentation checklist (iOS)

1. **Like / unlike / comment / share / save** — server emits `Engagement*` (outbox).  
2. **Video** — on stop: `watch_partial` or `watch_complete` with `progress`.  
3. **Feed cell** — visible > 1.2s → dwell; flick < 0.5s → skip (sampled 1/N to save cost).  
4. **Hubs** — same tracker with `surface: hubs`.

---

## Implementation order (ship sequence)

| Step | Work | Outcome |
|------|------|---------|
| 1 | Migration: `entity_personality` (+ optional engagement log) | Schema ready |
| 2 | TypeScript types + outbox on like/comment/createPost | Real events on `matterya.engagement` / `posts` |
| 3 | `POST /v1/engagement/batch` + iOS tracker | Watch/scroll signals |
| 4 | Personality worker (rules-v0) | Rows in `entity_personality` |
| 5 | `personalizedHomeFeed` or rank inside existing feed loader | Users feel relevance |
| 6 | Neighbors / KNN (optional) | “People like you”, advanced ranking |

---

## Privacy & product notes

- Personality is **inferred**, not a public shame field.  
- UI language: “You tend to watch long videos” not “Impulsive type.”  
- Respect private profiles / blocks when using creator_affinity.  
- Allow “Reset personalization” → wipe affinities, keep identity.  
- GDPR: personality is user data; include in export/delete.

---

## Summary

| Layer | Decision |
|-------|----------|
| Entity | = existing profile user |
| Content | = posts + lifecycle events |
| Signals | Kafka `matterya.engagement` + `matterya.posts` |
| Personality | `entity_personality`, rules-v0 first |
| KNN | Later consumer on `feature_vector` |
| iOS | Emit signals; consume ranked feed; thin local boost only |

---

## Live signals in Kafka + reports (implemented)

### Pipeline

```
App / GraphQL
   → POST /v1/engagement/batch   (dwell, skip, watch, …)
   → like / comment mutations
        │
        ├─ entity_engagement_events   (Postgres report store)
        └─ kafka_outbox
                │
                ▼ (~500ms publisher)
         topic: matterya.engagement
                │
        ┌───────┴────────┐
        ▼                ▼
 Redpanda Console    API log: [kafka-live] …
 (http://localhost:8080)
```

### Watch live

1. `docker compose -f infra/docker/docker-compose.yml up -d`
2. API: `KAFKA_ENABLED=true` + brokers + `DATABASE_URL`
3. Open **http://localhost:8080** → Topics → **`matterya.engagement`** → Messages
4. Or watch API stdout: `[kafka-live] matterya.engagement  EngagementScrollDwell …`

### Report API

```http
GET /v1/engagement/report?hours=24
Authorization: Bearer <supabase-jwt>
# or header x-admin-key: <ADMIN_PORTAL_KEY>
```

Returns totals by event type, top entities/content, dwell stats, last 50 events.

### Ingest API (iOS / tools)

```http
POST /v1/engagement/batch
Authorization: Bearer <jwt>
Content-Type: application/json

{
  "sessionId": "optional",
  "events": [
    {
      "type": "scroll_dwell",
      "contentId": "post-uuid",
      "authorId": "author-uuid",
      "durationMs": 3200,
      "surface": "home",
      "deviceClass": "phone"
    },
    { "type": "scroll_skip", "contentId": "…", "durationMs": 200, "surface": "home" },
    { "type": "watch_partial", "contentId": "…", "progress": 0.4, "durationMs": 8000 }
  ]
}
```

Allowed `type` values: `like`, `unlike`, `comment`, `share`, `save`, `unsave`,
`watch_partial`, `watch_complete`, `scroll_dwell`, `scroll_skip`, `profile_open`.

### Migrations

- `supabase/migrations/20260731120000_entity_engagement_personality.sql`
- Run on Supabase before expecting Postgres reports (Kafka can still receive events if table is missing for insert, outbox still publishes).
