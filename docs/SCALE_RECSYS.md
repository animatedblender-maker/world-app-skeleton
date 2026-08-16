# Scale path: warehouse + recommender (Matterya)

You are scaling fast. We are **not** waiting for a Big Tech data org.

## Plain English

| Buzzword | What it is for us **today** | What it becomes later |
|---|---|---|
| **Warehouse** | Postgres fact tables that store every signal forever-enough to train on | Optional export to BigQuery/Snowflake when volume needs it |
| **Event bus** | Kafka / Redpanda `matterya.engagement` (already ON in prod) | Same — more consumers |
| **Feature store** | `recsys_user_creator_affinity`, `entity_personality`, `recsys_item_stats` | Redis + offline tables if needed |
| **Ranker** | `POST /v1/recommendation/rank` (server multi-source + diversity) | GBDT → neural multi-task |
| **Decision log** | `recommendation_decisions` + client impressions | Offline training labels |

**You already have a warehouse of record:**  
`entity_engagement_events` + Kafka. That *is* the analytical spine startups use for the first 1–50M events. A separate cloud warehouse is a **copy**, not a prerequisite to being big.

## Architecture (live)

```
iOS / web
  │  engagement batch + rank request
  ▼
API (api.matterya.com)
  ├─ entity_engagement_events     ← facts (warehouse)
  ├─ recsys_user_creator_affinity ← online features
  ├─ recsys_item_stats            ← item quality
  ├─ recommendation_decisions     ← every ranked page
  ├─ kafka_outbox → matterya.engagement
  └─ POST /v1/recommendation/rank ← serving ranker
```

## APIs

| Endpoint | Purpose |
|---|---|
| `POST /v1/engagement/batch` | Ingest signals; refreshes user features |
| `POST /v1/recommendation/rank` | Order candidate IDs for a surface |
| `POST /v1/recommendation/refresh-features` | Force user affinity rebuild |
| `POST /v1/recommendation/refresh-item-stats` | Cron: global item quality |

## Migration

`supabase/migrations/20260816120000_recsys_warehouse_and_rank.sql`

Apply to production Supabase (`supabase db push` or SQL editor).

## Why this is “already big”

1. **Every impression / hide / dwell is durable** (Postgres + Kafka).  
2. **Server ranks with personalization**, not only client shuffle.  
3. **Decision logs reconstruct feeds** for debugging and future training.  
4. **Export path is open**: dump `entity_engagement_events` / `recommendation_decisions` to any lake later **without changing the app**.  
5. **Surfaces are policy objects** (Following vs For you) so growth does not become if-statement spaghetti.

## What we do **not** need before public launch

- BigQuery contract  
- Two-tower GPU cluster  
- Separate “ML platform” hire  

Those come when measurement shows the baseline ranker is the bottleneck — not before.

## Next scale steps (I own)

1. Apply migration + confirm rank endpoint on prod health (`recsysRank: true`).  
2. Nightly item-stats cron.  
3. Sparks / Hubs call the same rank API.  
4. When events > ~10M rows: partition engagement by month + optional warehouse export job.
