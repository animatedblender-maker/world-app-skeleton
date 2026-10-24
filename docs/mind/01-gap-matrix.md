# Handbook → code gap matrix

Status legend: **shipped** · **partial** · **missing** (roadmap)

| Handbook § | Topic | Status | Matterya location / ticket |
|---|---|---|---|
| 1 | Purpose / surfaces | partial | Surfaces exist; admin docs explain |
| 2 | Invariants (no-repeat, fail closed) | partial | Ledger PK enforces no-repeat; ML fail → cursor |
| 3 | Architecture diagram | shipped | Admin `/mind` architecture wall |
| 4 | Repo layout `intelligence/` | partial | Kept under `recommendation/` + `ops/` |
| 5 | Event envelope | partial | `entity_engagement_events` + Kafka; MIND-001/002 |
| 6 | Masquerade isolation | partial | Separate schemas/routes; admin check panel |
| 7 | Media understanding | missing | Phase 2 |
| 8 | Interest memory / features | partial | `entity_personality`, affinity tables |
| 9 | Candidate generation | partial | Shelf multi-lane |
| 10 | Rank + diversity | partial | `rank.service` + MMR; MIND-005 |
| 11 | Exposure ledger | partial | `feed_video_delivery`; MIND-004 |
| 12 | Search / world / rooms | partial | Search exists; world map later |
| 13 | Guardian | partial | Reports / moderation queues |
| 14 | Ads / economy | missing | Phase 4+ |
| 15 | GraphQL FeedItem | missing | REST instead (ADR 0002); MIND-006 metadata |
| 16 | Schema | partial | Delivery migration applied |
| 17 | Workers | partial | Pipeline + frame0; not full MIND workers |
| 18 | ML eval | missing | Phase 2–3 |
| 19 | Observability | partial | `/mind` live + metrics ingest |
| 20 | Tests | partial | MIND-008 concurrency |
| 21 | Roadmap | shipped | Documented on admin page |

## Phase 1 tickets

| ID | Title | Status |
|----|-------|--------|
| MIND-001 | Shared contracts / surfaces | this pass |
| MIND-002 | Event allowlist alignment | this pass |
| MIND-003 | Central eligibility helper | this pass |
| MIND-004 | Ledger + Masquerade reserve | this pass |
| MIND-005 | Diversity / family gaps | this pass |
| MIND-006 | `deliveryId` / `modelVersion` / `requestId` on feeds | this pass |
| MIND-007 | Hide / not-interested exclusions | stub / wire if tables allow |
| MIND-008 | Concurrent reservation test | this pass |
| MIND-009 | `MIND_LEDGER_ENABLED` + admin | this pass |
