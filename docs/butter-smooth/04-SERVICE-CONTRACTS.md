# Service contracts (iOS ↔ API)

## POST /v1/metrics/batch

**Auth:** Bearer preferred; anonymous allowed for cold start shell metrics.  
**Body:**

```json
{
  "sessionId": "string",
  "appVersion": "string",
  "os": "ios",
  "deviceClass": "iphone11|other",
  "events": [
    {
      "name": "app_start_to_feed_visible",
      "t0": 0,
      "t1": 120,
      "durationMs": 120,
      "traceId": "optional",
      "surface": "feed|hubs|sparks|messages|search|profile|composer|app",
      "ok": true,
      "meta": {}
    }
  ]
}
```

**Response:** `{ "ok": true, "accepted": N }`  
**Limits:** max 50 events / request; max 8 KB meta total.

## GET /v1/config

**Auth:** optional  
**Query:** `v` = client known version (if match → `304` or `{ unchanged: true }`)  
**Response:**

```json
{
  "ok": true,
  "version": "2026-08-17.1",
  "ttlSec": 60,
  "flags": {
    "prefetch_depth_high": 3,
    "prefetch_depth_low": 1,
    "player_pool_size": 3,
    "thin_feed_enabled": true,
    "thin_hubs_enabled": true,
    "metrics_sample_rate": 1.0,
    "kill_prefetch": false,
    "kill_server_rank": false
  }
}
```

## Existing (unchanged product)

| Endpoint | Role |
|----------|------|
| `POST /v1/engagement/batch` | Analytics/engagement (async) |
| `POST /v1/recommendation/rank` | Soft re-rank |
| `GET /v1/feed`, `/v1/sparks`, `/v1/hubs/*` | Thin pages |
| GraphQL | Mutations, messages, profiles |
