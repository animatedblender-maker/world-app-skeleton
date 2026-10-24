# Phase 0 — Repository audit (2026-10-25)

Handbook rule: inspect the real repo before implementing. This document is that inventory.

## Product stack (actual)

| Handbook assumption | Matterya today |
|---|---|
| Angular + Capacitor | iOS native (`apps/mobile/ios`) + web; Capacitor remnants elsewhere |
| NestJS GraphQL | **Express** REST under `apps/api` |
| PostgreSQL / Supabase | Yes — pooler via `DATABASE_URL` |
| Render + GitHub Pages | API on Render (`ios-native`, root `apps/api`); web separately |
| Brand / anon | Matterya; **Masquerade** = `/v1/anonymous/*` |

## Auth

- Public feeds: JWT via Supabase JWKS (`requireUser` / optional anonymous paths).
- Ops admin pages (`/pipeline`, `/frame0`, `/reports`, `/mind`): shared password cookie (`CONTENT_PIPELINE_PASSWORD` / `REPORTS_PAGE_PASSWORD`).
- Admin JSON APIs: Bearer JWT **or** `x-admin-key`.

## Recommendation surfaces

| Surface | HTTP | Ledger surface key | Ranker |
|---|---|---|---|
| Home For You | `GET /v1/feed` | `home_for_you` | `rank.service` + shelf weave |
| Hubs For You | `GET /v1/hubs/for-you` | `hubs_for_you` | shelf + ledger |
| Sparks | `GET /v1/sparks` | (cursor / shares) | shelf |
| Masquerade | `GET /v1/anonymous/feed` | `masquerade_for_you` | SQL + MMR + async reserve |

## Storage (live counts at audit time)

| Object | Status |
|---|---|
| `public.feed_video_delivery` | **Exists** — exposure ledger (~2k rows at audit) |
| `public.feed_batch` / `feed_batch_item` | **Exists** — idempotent batches |
| `public.entity_engagement_events` | **Exists** (~69k rows) |
| `public.recommendation_decisions` | Missing / unused at audit |
| `public.mind_feed_exposure` | **Does not exist** (handbook name only) |
| `anonymous.spaces` / `anonymous.posts` | Live Masquerade catalog |

## Code owners

- Delivery: `recommendation/delivery.service.ts` (`reserveDeliveryBatch`, `canonicalVideoKey`)
- Rank: `recommendation/rank.service.ts` (`POLICY_VERSION = server.v4-social-mmr`)
- Shelves: `recommendation/shelf.service.ts`
- Engagement ingest: `engagement/engagement.service.ts` + Kafka consumer
- Ops UI: `ops/ops-page.ts`, `ops/mind-page.ts`

## Deploy constraints

- Branch `ios-native`; Render Root Directory `apps/api`; `npm run render-build`.
- Do not assume SSD paths (`/Volumes/MatteryaSSD/...`) exist on Render — seed live panels degrade gracefully.

## Cost / ops baseline

- Rank cache TTL ~20s in-process.
- Ledger fail-open → cursor weave when schema/reserve fails (anonymous / missing tables).
- Heavy ML training is **not** in the API process (handbook-aligned).

## Product decisions locked for Phase 1

1. Reuse `feed_video_delivery` as the MIND exposure ledger (ADR 0001).
2. Keep REST feed contracts (ADR 0002).
3. Masquerade stays a separate namespace; Public MIND must not read anon preference state.
4. Admin illustration lives at `/mind` with the Ops password.
