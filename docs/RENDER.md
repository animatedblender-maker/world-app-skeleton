# Render deploy (matterya-api)

## Critical: Dashboard overrides Blueprint

`render.yaml` is **not always applied** to an existing Web Service.  
If logs show:

```text
Running build command 'npm ci && npm run build'
```

…the **Dashboard** still has the old command. Update it manually.

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
npm install --no-workspaces --include=dev && npm run build
```

### Why not `npm ci` at monorepo root?

This repo is an npm **workspace**. If Root Directory is empty or npm walks up to the parent `package.json`, install tries to resolve **mobile Capacitor** packages against a root lockfile that doesn’t list them → build fails.

`--no-workspaces` installs **only** API deps from `apps/api/package.json`.

## Matterya confirmation email (required for signup)

Signup and “Resend confirmation” call Resend.  
Check live status: `GET https://api.matterya.com/auth/status` → `mailConfigured` must be **true**.

| Key | Value |
|-----|--------|
| **RESEND_API_KEY** | From [resend.com](https://resend.com) → API Keys |
| **MAIL_FROM** | `Matterya <noreply@matterya.com>` (domain must be verified in Resend) |
| **PUBLIC_WEB_ORIGIN** | `https://matterya.com` |

Also apply Supabase migration: `supabase/migrations/20260805140000_email_confirmations.sql`.

Without `RESEND_API_KEY`, the API returns **503 MAIL_NOT_CONFIGURED** (it will not pretend an email was sent).

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
