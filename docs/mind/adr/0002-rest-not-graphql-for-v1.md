# ADR 0002 — REST feed contracts for MIND Phase 1

**Status:** Accepted · 2026-10-25  
**Context:** Handbook §15 sketches GraphQL `FeedPage` / `FeedItem`.

## Decision

Phase 1 continues to serve recommendations over **existing Express REST** endpoints:

- `GET /v1/feed`
- `GET /v1/hubs/for-you`, `GET /v1/hubs/shelves/:slug`
- `GET /v1/sparks`
- `GET /v1/anonymous/feed`

Add handbook-aligned metadata fields onto those JSON payloads (`requestId`, `modelVersion`, `deliveryId` / `deliveryPolicy`) rather than introducing GraphQL resolvers now.

## Why

- Clients (iOS native + web) already speak REST.
- GraphQL module exists for other domains; swapping the feed plane is a multi-client migration.
- Vertical slice value is ledger + rank + admin observability, not transport churn.

## Consequences

- Gap matrix marks GraphQL FeedItem as **missing / deferred**.
- Contracts live in TypeScript (`mind-contracts.ts`) shared by REST handlers.
