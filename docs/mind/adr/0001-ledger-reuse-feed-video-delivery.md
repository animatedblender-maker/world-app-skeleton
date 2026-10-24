# ADR 0001 — Reuse `feed_video_delivery` as MIND exposure ledger

**Status:** Accepted · 2026-10-25  
**Context:** Handbook §11 proposes `mind_feed_exposure(account_id, canonical_content_id, feed_scope)`.

## Decision

Keep and extend **`public.feed_video_delivery`** (+ `feed_batch` / `feed_batch_item`) as the durable at-most-once ledger.

Mapping:

| Handbook | Matterya |
|---|---|
| `account_id` | `user_id` |
| `canonical_content_id` | `canonical_video_id` (text — R2 pack / share collapse) |
| `feed_scope` | `surface` (`home_for_you`, `hubs_for_you`, `masquerade_for_you`) |
| `delivery_id` | `delivery_id` |
| reservation batch | `feed_batch` + `idempotency_key` |

## Why

- Already live with data and call sites in shelf + anonymous feed.
- Text canonical keys correctly collapse shares of the same R2 object.
- Renaming tables would break production without benefit.

## Consequences

- Admin UI shows both names (“handbook: mind_feed_exposure → Matterya: feed_video_delivery”).
- New surfaces add a `surface` string; no parallel ledger table in Phase 1.
