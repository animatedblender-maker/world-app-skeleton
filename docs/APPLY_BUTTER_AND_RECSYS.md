# Applying butter-smooth + recommendation roadmaps to Matterya

**Sources (canonical copies in-repo):**

- `docs/reference/butter_smooth_social_platform_architecture.md`
- `docs/reference/social_recommendation_engineering_roadmap.md`

**Date applied:** 2026-08-16  
**Scope:** Phase 0 foundations only — product stays shippable while instrumentation and policies land.

---

## Already present in Matterya (mapped)

| Roadmap concept | Matterya today |
|---|---|
| Six-plane / domain services | GraphQL API + Supabase + R2 media + Kafka/Redpanda outbox |
| Client local-first feed | `HomeFeedStore` + `ContentCache` + soft-merge |
| Cursor pagination | Home / Sparks / Hubs load-more cursors |
| Optimistic like/follow | iOS engagement + FollowService |
| Media platform (partial) | R2 public playback, archive warm, SparkWarmPool |
| Realtime messaging | Messages + presence + CallKit/LiveKit |
| Event bus | `matterya.engagement`, posts, messages, follows, R2 ingest |
| Client engagement SDK | `EngagementTracker` → `/v1/engagement/batch` |
| Short-video discovery | `SparkDiscoveryEngine` + `ReelsRankingEngine` |
| Long-form hubs | `YouTubeCatalogService` + continuous player |
| Butter-smooth UX work | continuous hubs player, feed prefetch, warm pools |

---

## Applied in this pass (code)

### Butter-smooth (client experience plane)

- Continues existing local-first feed / miniplayer / warm-pool work (prior commits).
- Performance budgets remain release gates for iOS feed, Sparks open, Hubs expand (see iOS motion + prefetch).

### Recommendation Phase 0

1. **`RecommendationSurface` + policy object**  
   Explicit surfaces: home For you / Following, Sparks, Hubs For you / Following, Explore, …  
   Each has page size, exploration budget, creator diversity, latency budget, candidate sources.

2. **`FeedCompositionEngine`**  
   Greedy constrained re-ranker: eligibility, creator window, near-dupe penalty, exploration slots, unviewed preference.

3. **`RecommendationDecisionLog`**  
   Logs `impression`, `ranked_served`, `viewport_visible` through EngagementTracker with `requestId`, position, sources, `policyVersion`.

4. **Home feed wiring**  
   `HomeFeedStore.rankForSession` → baseline discovery order → composition engine → decision log.  
   Viewport exposure on row appear.

5. **API / Kafka**  
   New engagement event types: Impression, RankedServed, ViewportVisible, Hide, NotInterested.

---

## Not applied yet (needs infra / product / you)

These are **not** implementable as pure app code without decisions and services from you (or a backend/ML team).

### You need to provide / decide

| Item | Why | What we need from you |
|---|---|---|
| **Kafka / Redpanda in prod** | Decision logs only help if they land in a stream/warehouse | Confirm `KAFKA_ENABLED=true` on API deploy; Redpanda/Kafka brokers; access to Console |
| **Warehouse / lakehouse** | Phase 0 exit: reconstruct feeds offline | Snowflake / BigQuery / ClickHouse / S3+Iceberg choice + credentials |
| **Experiment assignment** | A/B for ranker vs baseline | Randomization unit (user_id), holdout %, who owns experiment config |
| **Feature store** | Dual online/offline features | Redis/KV + offline tables — vendor or self-host |
| **ANN / embeddings** | Two-tower retrieval (Phase 2) | GPU budget, embedding model choice, vector DB (pgvector / Pinecone / …) |
| **Safety eligibility service** | Hard gates outside ranker | Moderation API or rules owner; age/region policy |
| **Following vs For you UI** | Roadmap: two distinct home policies | Product call: ship dual tabs/chips on home now? |
| **Hide / Not interested UI** | Negative labels | Product design for long-press / menu actions |
| **CDN / edge policy** | Butter doc Phase 1 | Cloudflare (or other) zone + cache rules for media/static |
| **Performance RUM** | Golden journeys SLOs | Prefer Firebase Perf / Sentry / custom? API keys |
| **Privacy / retention** | Event TTL, deletion lineage | Legal retention days for engagement events |
| **Team ownership** | RecSys platform vs ranking vs features | Who on-calls which plane (even if one person today) |

### Server work still open (we can do next when you green-light)

- Server-side feed session cursor with already-served IDs + policy version  
- Bulk post-view hydration endpoint (stop client waterfalls)  
- Idempotency keys on all mutations  
- Feature-flag service (or LaunchDarkly key)  
- Eligibility microservice (blocks + moderation state)  
- Parquet export job from Kafka engagement → warehouse  

### Explicitly deferred (Phase 1–5 recsys)

- GBDT / multi-task neural ranker  
- Two-tower + ANN  
- Sequence/session encoder service  
- Causal exploration / bandits  
- Creator ecosystem optimizer  

---

## Phase map (Matterya-specific)

| Weeks | Focus | Owner |
|---|---|---|
| 0–2 | Event quality >99%; decision logs in Kafka; dual home policies if product OK | Eng + you (Kafka/prod) |
| 2–6 | Warehouse tables; metric registry; Following/For you split; hide/not-interested | Eng + data |
| 6–12 | Hand features + GBDT baseline vs deterministic; A/B | ML + eng |
| 3–6 mo | Feature platform + two-tower | ML + infra |
| 6–12 mo | Multi-task + sequence; exploration budget online | ML |

---

## How to verify this pass

1. Run iOS app → open home feed → scroll.  
2. API logs / Redpanda Console → `matterya.engagement` should show `EngagementImpression`, `EngagementRankedServed`, `EngagementViewportVisible`.  
3. Feed should still soft-merge and not blank on refresh.  
4. Creator diversity: fewer back-to-back same-author cards on For you.

---

## File index

| Path | Role |
|---|---|
| `docs/reference/*.md` | Full original blueprints |
| `docs/APPLY_BUTTER_AND_RECSYS.md` | This apply map |
| `docs/DECISIONS.md` | ADR stubs filled |
| `docs/ROADMAP.md` | Phased Matterya roadmap |
| `…/RecommendationSurface.swift` | Surface policies |
| `…/FeedCompositionEngine.swift` | Constrained re-ranker |
| `…/RecommendationDecisionLog.swift` | Decision telemetry |
| `…/HomeFeedStore.swift` | Wired composition + viewport |
| `…/EngagementTracker.swift` | Recsys event enqueue |
| `apps/api/src/engagement/*` + `kafka/types.ts` | Server accept new types |
