# Kafka backbone (Phase 1)

Matterya uses **Kafka-compatible Redpanda** as an async event bus.  
Postgres stays the source of truth. GraphQL writes domain events through a **transactional outbox**.

## Architecture

```
GraphQL mutation (sendMessage / edit / delete)
        │
        ├─► INSERT messages / UPDATE / DELETE   (same transaction)
        └─► INSERT kafka_outbox                 (same transaction)
                    │
                    ▼
         Outbox publisher (in API process)
                    │
                    ▼
         Redpanda topic: matterya.messages
                    │
                    ▼
         messages consumer → NotificationsService (APNs / web push)
```

### Modes

| Env | Behavior |
|-----|----------|
| `KAFKA_ENABLED` unset/false | Legacy path only (inline `notifyMessage`) |
| `KAFKA_ENABLED=true` | Outbox + Kafka consumer handle push |
| `KAFKA_ENABLED=true` + `KAFKA_SHADOW=true` | **Both** Kafka and inline notify (shadow traffic) |

## Local setup

### 1. Start Redpanda

```bash
docker compose -f infra/docker/docker-compose.yml up -d
```

- Kafka API: `localhost:19092`
- Console UI: http://localhost:8080

### 2. Apply DB migration

```bash
# Supabase CLI (preferred)
supabase db push

# Or run SQL manually against your DATABASE_URL:
# supabase/migrations/20260730120000_kafka_outbox.sql
```

### 3. Configure API (`apps/api/.env`)

```env
KAFKA_ENABLED=true
KAFKA_BROKERS=localhost:19092
KAFKA_CLIENT_ID=matterya-api
KAFKA_CONSUMER_GROUP=matterya-api-workers
# Optional: dual-write while validating
# KAFKA_SHADOW=true
```

### 4. Run API

```bash
npm --workspace apps/api run dev
```

You should see:

```text
✅ Kafka topics ready: ...
✅ Kafka outbox publisher every 500ms
✅ Kafka consumer listening on matterya.messages
✅ Kafka pipeline running
```

## Topics (Phase 1)

| Topic | Events | Consumer |
|-------|--------|----------|
| `matterya.messages` | `MessageSent`, `MessageEdited`, `MessageDeleted` | Push for `MessageSent` |
| `matterya.posts` | `ContentPosted`, … | reports / analytics |
| `matterya.engagement` | likes, watch, … | engagement consumer |
| `matterya.r2.ingest` | `R2IngestRequested`, … | catalog flood (not media) |
| `matterya.media` | `media.upload.completed`, `MediaProcessRequested`, `MediaReady`, `MediaFailed` | **Frame 0** worker (in-process) — see `docs/MEDIA_FRAME0.md` |
| `matterya.follows` | reserved | — |
| `matterya.calls` | reserved | — |
| `matterya.notifications` | reserved | — |
| `matterya.dlq` | reserved | — |

Create `matterya.media` in your Kafka provider UI if auto-create is blocked. Poster rule: **first displayed frame only**.

## Tables

- `public.kafka_outbox` — durable events waiting for / already published to Kafka  
- `public.kafka_processed_events` — consumer idempotency (`consumer_group`, `event_id`)

## Code map

| Path | Role |
|------|------|
| `apps/api/src/kafka/` | Client, outbox, publisher, consumers |
| `apps/api/src/graphql/modules/messages/messages.service.ts` | Enqueues events on send/edit/delete |
| `supabase/migrations/20260730120000_kafka_outbox.sql` | Schema |
| `infra/docker/docker-compose.yml` | Redpanda + console |

## Production on Render (recommended path)

Render already has `DATABASE_URL` + Supabase. You **cannot** use `localhost:19092` there — use a managed Kafka.

### 1. Supabase (you said this is done)
Run migration if not already applied:
`supabase/migrations/20260730120000_kafka_outbox.sql`

### 2. Create managed Kafka (pick one)

**Confluent Cloud** (what you’re using):
1. https://confluent.cloud/ → your cluster → **Cluster settings → Bootstrap server**  
2. **API keys** → Create key (scope: the cluster) → copy **Key** + **Secret** once  
3. **Topics** → create at least `matterya.messages` (partitions 6 is fine)  
   Also useful: `matterya.posts`, `matterya.engagement`, `matterya.follows`, `matterya.calls`, `matterya.notifications`, `matterya.dlq`  
4. Render env (see below) — mechanism is **`plain`**, SSL **on**

**Upstash Kafka** (alternative free tier):
1. https://console.upstash.com/ → Kafka → Create cluster  
2. Copy brokers + SASL user/password (`scram-sha-256`)  

**Alternatives:** Redpanda Cloud, Aiven.

### 3. Render → matterya-api → Environment

| Key | Value |
|-----|--------|
| `KAFKA_ENABLED` | `true` |
| `KAFKA_BROKERS` | from provider (e.g. `xxx.upstash.io:9092`) |
| `KAFKA_CLIENT_ID` | `matterya-api-render` |
| `KAFKA_CONSUMER_GROUP` | `matterya-api-workers` |
| `KAFKA_SSL` | `true` (Upstash / most clouds) |
| `KAFKA_SASL_MECHANISM` | `scram-sha-256` (Upstash default) |
| `KAFKA_SASL_USERNAME` | from provider |
| `KAFKA_SASL_PASSWORD` | from provider |
| `KAFKA_SHADOW` | `true` first week, then `false` |
| `KAFKA_REPLICATION_FACTOR` | `3` if provider requires RF=3 for createTopics |

Leave existing `DATABASE_URL`, `SUPABASE_*`, APNs, LiveKit as they are.

### 4. Deploy
- Push this branch / **Manual Deploy** on Render  
- Logs should show Kafka pipeline start (not “DATABASE_URL is not set”)  
- Send a chat message → push still works  
- With `KAFKA_SHADOW=true`, both paths run; then set `false`

### 5. Rollback (instant)
```
KAFKA_ENABLED=false
```
Redeploy or save env — API falls back to inline notify.

## Next phases

1. **Shadow** (`KAFKA_SHADOW=true`) → compare push volume, then turn shadow off  
2. Move likes/follows notifications to Kafka  
3. Feed ranking / search index consumers  
4. Call metadata (`matterya.calls`) for analytics  
5. Split workers into separate Node processes if API CPU grows  

## Ops notes

- **Never** point mobile clients at Kafka brokers.  
- Partition key for chat is `conversationId` (ordered per chat).  
- Publisher uses `FOR UPDATE SKIP LOCKED` so multiple API replicas can share outbox drain.  
- Idempotent consumers: redelivery must not double-process (ledger table).  
- Local Docker Kafka is optional; production does not depend on your Mac.  
