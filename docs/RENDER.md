# Render deploy (matterya-api)

## Always redeploy after API changes

Render tracks branch **`ios-native`** (not `main`).

After any change under `apps/api/` (or anything the API must serve):

1. Commit on `ios-native`
2. `git push origin ios-native` → Render auto-deploys

Do **not** leave API work only local — the live iOS client hits `api.matterya.com` on this deploy.

## Content pipeline (R2 → owned posts + Kafka)

See **[CONTENT_PIPELINE.md](./CONTENT_PIPELINE.md)**.

| | |
|--|--|
| **Ops UI** | https://api.matterya.com/pipeline (reports password by default) |
| **Cron** | `POST /cron/content-pipeline` + `x-cron-secret: CONTENT_CRON_SECRET` |
| **Kafka** | Topic `matterya.r2.ingest` when `KAFKA_ENABLED=true` |
| **Env** | `CONTENT_CRON_SECRET`, `R2_*` on **matterya-api** web service |

`CONTENT_CRON_SECRET` = any secret you generate (`openssl rand -hex 32`).  
R2 keys = Cloudflare R2 API token (same names as local `.env.r2`).

## Platform reports (password page)

| | |
|--|--|
| **URL** | https://api.matterya.com/reports |
| **Password** | env `REPORTS_PAGE_PASSWORD` (default set in code for this project) |
| **Tabs** | Activity · Uploads |

Optional env:

| Key | Purpose |
|-----|---------|
| `REPORTS_PAGE_PASSWORD` | Login password for `/reports` |
| `REPORTS_COOKIE_SECRET` | Signs the session cookie (defaults to admin key) |

## Critical: Dashboard overrides Blueprint

`render.yaml` is **not always applied** to an existing Web Service.  
If logs show:

```text
Running build command 'npm ci && npm run build'
```

…the **Dashboard** still has the old command. That fails in this monorepo
(`@aws-sdk/*` is only in `apps/api/package-lock.json`). **Update Build Command manually.**

## Required service settings

**Render → matterya-api → Settings**

| Setting | Value |
|---------|--------|
| **Branch** | `ios-native` |
| **Root Directory** | `apps/api` |
| **Build Command** | `npm run render-build` |
| **Start Command** | `npm start` |
| **Health Check Path** | `/health` |

`render-build` runs:

```bash
npm ci --no-workspaces --include=dev && npm run build
```

Clear **Build Cache** once (Clear build cache & deploy) after changing the lockfile or build command.

### Why not `npm ci` at monorepo root?

This repo is an npm **workspace**. If Root Directory is empty or npm walks up to the parent `package.json`, install tries to resolve **mobile Capacitor** packages against a root lockfile that doesn’t list them → build fails.

`--no-workspaces` installs **only** API deps from `apps/api/package.json`.

## Matterya confirmation email from `noreply@matterya.com`

To send **from Matterya** (not Supabase’s generic address), the API uses **Resend**.

Check: `GET https://api.matterya.com/auth/status` → `mailConfigured` must be **true**, and `mailFrom` should be `Matterya <noreply@matterya.com>`.

| Key | Value |
|-----|--------|
| **RESEND_API_KEY** | From [resend.com](https://resend.com) → API Keys (`re_…`) |
| **MAIL_FROM** | `Matterya <noreply@matterya.com>` |
| **PUBLIC_WEB_ORIGIN** | `https://matterya.com` |

### Domain setup (required for that From address)

1. Resend → **Domains** → Add **`matterya.com`**
2. Add the DNS records they show (SPF, DKIM, etc.) at your DNS host
3. Wait until status is **Verified**
4. Then `MAIL_FROM=Matterya <noreply@matterya.com>` will deliver

Without domain verification, Resend rejects sending as `@matterya.com`.

Also apply Supabase migration: `supabase/migrations/20260805140000_email_confirmations.sql`.

**Note:** Supabase-only auth email cannot use `noreply@matterya.com` unless you configure **custom SMTP** in Supabase Auth to the same domain. Resend + this API path is the supported Matterya setup.

Without `RESEND_API_KEY`, the API returns **503 MAIL_NOT_CONFIGURED**.

## Kafka env vars (Confluent Cloud)

| Key | Example |
|-----|---------|
| `KAFKA_ENABLED` | `true` |
| `KAFKA_BROKERS` | `pkc-xxx.region.gcp.confluent.cloud:9092` |
| `KAFKA_SSL` | `true` |
| `KAFKA_SASL_MECHANISM` | `plain` |
| `KAFKA_SASL_USERNAME` | API key |
| `KAFKA_SASL_PASSWORD` | API secret |
| `KAFKA_CLIENT_ID` | `matterya-api-render` |
| `KAFKA_CONSUMER_GROUP` | `matterya-api-workers` |
| `KAFKA_SHADOW` | `true` (first), then `false` |
| `KAFKAJS_NO_PARTITIONER_WARNING` | `1` |

Plus existing `DATABASE_URL`, `SUPABASE_*`, APNs, LiveKit.

## After changing Build Command

1. **Save** Settings  
2. **Manual Deploy** → Clear build cache & deploy (recommended once)  
3. Logs should show `npm run render-build` / `npm install --no-workspaces`, **not** `npm ci`  
