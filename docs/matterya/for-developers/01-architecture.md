# Architecture (developer)

## Stack sketch

```
iOS / Web clients
    │  GraphQL + REST shelves + engagement ingest
    ▼
apps/api (Render: matterya-api)
    │  recommendation/*  engagement/*  content-pipeline/*
    ▼
Supabase Postgres (+ pgvector)
    │  posts, feed_video_delivery, entity_engagement_events,
    │  mind_content_features, mind_content_embeddings, …
    ▼
External
    Voyage AI (embeddings)
    Groq (optional STT → transcripts → features)
    R2 (media)
```

## MIND decision path (Public)

1. **Eligibility** — surface namespace (Public vs Masquerade)  
2. **Candidates** — shelves, popularity, affinity, ANN neighbors, …  
3. **Score** — soft boosts (topics, ANN, creator affinity, …)  
4. **Diversify / serve**  
5. **Ledger write** — `feed_video_delivery` (ADR 0001)  

Missing media features or embeddings = **UNKNOWN**, never demote.

## Surfaces
- `home_for_you`
- `hubs_for_you`
- `masquerade_for_you`

Isolation: `mind-isolation.ts` + `eligibility.ts`. Public rank must not join Masquerade inventory or preference tables into Public paths.

## Policy version
`MIND_POLICY_VERSION` in `mind-contracts.ts`  
Production `/health` → `features.mindPolicyVersion` (expect `mind.phase2.v2` after Phase 2b deploy).

## Kill switches
| Env | Effect |
|---|---|
| `MIND_LEDGER_ENABLED` | Off → cursor weave fallback |
| `MIND_MEDIA_FEATURES_ENABLED` | Off → skip topic features |
| `MIND_EMBEDDINGS_ENABLED` | `false`/`0`/`off` → no Voyage / no ANN |

Embeddings also require `VOYAGE_API_KEY`.

## Admin console
- Routes: `/mind`, `/mind/login`, `/mind/api/status`, `/mind/api/stream`, `/mind/api/docs/:slug`
- Auth: shared Ops cookie (`CONTENT_PIPELINE_PASSWORD` / `REPORTS_PAGE_PASSWORD`)
- Status TTL ~20s; UI poll 15s (Disk IO protection)
