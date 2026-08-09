# Content pipeline (R2 + Kafka + ops page)

Brings new R2 Sparks into Supabase as **owned** posts + home-feed **shares**, then announces via **Kafka outbox**.

## Architecture

```
R2 bucket (new packs)
        │
        ▼
 Discover (cron /ops page / Kafka job)
        │
        ├─ insert original Spark  (__spark__|)     → Sparks player
        ├─ insert spark share     (__spark_share__|) → home feed
        └─ emitContentPosted → kafka_outbox
                │
                ▼
         matterya.posts / matterya.engagement
                │
                ▼
         reports, stats, future consumers

Optional (KAFKA_ENABLED=true):
  Cron → outbox event R2IngestRequested on matterya.r2.ingest
       → r2-ingest consumer runs the same pipeline
```

## Ops page (no curl required)

| | |
|--|--|
| **URL** | https://api.matterya.com/pipeline |
| **Password** | Same as Reports by default (`REPORTS_PAGE_PASSWORD`, currently `54isamr!` unless you change env) |
| **Override** | `CONTENT_PIPELINE_PASSWORD` |

Buttons:

- **Run now** — execute pipeline in the API process  
- **Dry run** — discover only / no writes  
- **Re-sign URLs only** — refresh 7‑day R2 presigns  
- **Queue via Kafka** — enqueue job (needs `KAFKA_ENABLED`)

## CONTENT_CRON_SECRET — what is it?

**You invent it.** It is not from Cloudflare.

Example:

```bash
openssl rand -hex 32
```

Put that value in Render as `CONTENT_CRON_SECRET`.  
Use the same value in cron:

```bash
curl -X POST 'https://api.matterya.com/cron/content-pipeline' \
  -H "x-cron-secret: PASTE_THE_SAME_SECRET_HERE"
```

If unset, falls back to `INSIGHTS_CRON_SECRET`.

## R2 secrets — where to get them

From **Cloudflare Dashboard → R2 → Manage R2 API Tokens** (or your existing local file):

| Env | Source |
|-----|--------|
| `R2_ACCOUNT_ID` | Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | R2 API token access key |
| `R2_SECRET_ACCESS_KEY` | R2 API token secret |
| `R2_BUCKET` | e.g. `matterya-sparks` |
| `R2_ENDPOINT` | optional; default `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |

Local seed scripts already used:

`TikTokDashboard/.env.r2` with the same key names — copy those values into Render (never commit them).

## Render env (matterya-api)

```
CONTENT_CRON_SECRET=<openssl rand -hex 32>
R2_ACCOUNT_ID=...
R2_ACCESS_KEY_ID=...
R2_SECRET_ACCESS_KEY=...
R2_BUCKET=matterya-sparks
# optional
CONTENT_PIPELINE_PASSWORD=...   # else reports password
KAFKA_ENABLED=true              # optional; queue jobs on matterya.r2.ingest
```

Redeploy after setting env. Confirm:

```bash
curl -s https://api.matterya.com/health | jq .contentPipeline
```

Expect `"r2Configured": true` when R2 env is set.

## Cron (every 6h)

Blueprint service `matterya-content-pipeline` or Render Cron Job:

```
POST https://api.matterya.com/cron/content-pipeline
Header: x-cron-secret: <CONTENT_CRON_SECRET>
```

- With Kafka on → **202** + enqueued event  
- With Kafka off → **200** + inline stats  
- Force inline: `?inline=1`

## Local CLI

```bash
cd apps/api
npm run content-pipeline:dry
npm run content-pipeline
```

## Product rules

| Rule | Behavior |
|------|----------|
| Every post has an owner | Real `profiles.user_id` in US/DE/EG/AL |
| No profiles in country | Pack skipped (`skipped_no_owner`) |
| User uploads | Untouched (`media_path` not `r2:`) |
| Feed | Spark **shares** only + other non-spark posts; newest `created_at` first |
| Sparks player | Originals |

## After a successful run

1. Open Matterya → home feed → pull to refresh  
2. Newest spark **shares** should be at the top  
3. Open Sparks player → originals in the catalog  
4. Reports → Uploads tab shows ContentPosted lines when Kafka/DB path works  
