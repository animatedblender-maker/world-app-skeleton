# Voyage & embeddings (developer)

## Why Voyage
SpaceXAI Explore (`GET /v1/embedding-models`) returned empty for the team key.  
Voyage `voyage-4-lite` is the production embedder for Phase 2b.

## Schema
```sql
-- created by ensureEmbeddingSchema()
public.mind_content_embeddings (
  post_id uuid PK → posts(id) ON DELETE CASCADE,
  model_version text,          -- 'voyage:voyage-4-lite'
  dims int,                    -- 1024
  embedding vector(1024),
  source text,                 -- 'title_body'
  text_fingerprint text,
  updated_at timestamptz
);
-- HNSW: mind_content_embeddings_hnsw (vector_cosine_ops)
```

Requires `CREATE EXTENSION vector` (pgvector 0.8.x on Supabase).

## Online path (incremental) — prefer this
`scheduleEmbeddingForPost(postId)` — fire-and-forget queue in `mind-embeddings.ts`.

**Call sites:**
- `posts.service.ts` → `createPost` (public, non-moment)
- `posts.service.ts` → `updatePost` when title/body change
- `content-pipeline/run.ts` → originals + hub/spark shares

Pacing: ~400ms between queue items to avoid Voyage stampedes.

## Catch-up HTTP
```
POST /cron/mind-embeddings?limit=400
Header: x-cron-secret: <CONTENT_CRON_SECRET or INSIGHTS_CRON_SECRET>
→ backfillEmbeddings({ limit, batchSize })
```

Script for Render Cron (optional; **not required** — paid Cron Job needs a card):  
`apps/api/scripts/run-mind-embeddings-cron.mjs`  
Declared in `render.yaml` as `matterya-mind-embeddings` (`15 * * * *`).

**Decision (2026-10-25):** skip creating the paid Render Cron Job. Inline queue + optional manual curl is enough.

## Offline historical backfill (Mac)
```
/Volumes/MatteryaSSD/Development/tmp/mind-embed/
  backfill_voyage.py      # adaptive fast/throttled
  backfill.log
  backfill.pid
  embed_progress_server.py
  STATUS.json
```
Progress UI: `http://127.0.0.1:8789/`  
Watchdog hook: `keep_progress_servers_alive.sh` → `start_8789`.

Skips rows that already have `model_version = voyage:voyage-4-lite`.

## Rank integration
`rank.service.ts` imports `annCandidates` / `mindEmbeddingsEnabled`.  
Soft merge into score pool; missing vector never demotes.

## Env
| Var | Where |
|---|---|
| `VOYAGE_API_KEY` | `apps/api/.env` + Render `matterya-api` |
| `MIND_EMBEDDINGS_ENABLED` | optional kill switch (`false` disables) |

## Rate limits
Without payment method: ~3 RPM / 10K TPM → multi-hour backfill.  
With payment method: standard RPM; script uses `mode=fast` (batch 64, ~0.35s sleep).

## Do not
- Use `XAI_API_KEY` for embeddings  
- Embed Masquerade inventory into Public ANN  
- Re-run full Mac backfill for routine growth  
- Paste API keys into chat / git  
