# ADR 0005 — Phase 4 product surfaces scaffold

**Status:** Accepted (scaffold; implementation deferred per slice)  
**Date:** 2026-10-25

## Context

Handbook Phase 4 (MIND-020–025) extends MIND beyond Home/Hubs/Sparks ranking into search, people discovery, world/country feed, Masquerade room rank, Guardian depth, and creator insights. Partial search and report queues already exist outside MIND tickets.

## Decision

1. Implement Phase 4 as **thin vertical slices**, not a big-bang rewrite.
2. **First slices when Phase 3a is live:**
   - **MIND-020** — hybrid search: existing keyword + Voyage query embed (reuse `mind_content_embeddings`).
   - **MIND-024** — Guardian depth: wire report queues → policy signals visible on `/mind` (no new identity model).
3. Later: MIND-021 people discovery (privacy review), MIND-022 world feed (geoprivacy), MIND-023 Masquerade room deepen, MIND-025 creator insights / ads audit hooks.
4. Ads/economy (§14) remains product-gated; REST FeedItem stays (ADR 0002).

## Consequences

- Gap matrix §12 / §13 stay **partial** until 020/024 land.
- Phase 4 work must not block Phase 3 cold-start eval traffic or trained-ranker prep (MIND-016).
- Privacy review is mandatory before people-discovery or geoprivacy feeds ship.
