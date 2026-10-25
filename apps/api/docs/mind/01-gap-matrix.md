# Handbook → code gap matrix

Status legend: **shipped** · **partial** · **missing** (roadmap)

| Handbook § | Topic | Status | Matterya location / ticket |
|---|---|---|---|
| 1 | Purpose / surfaces | shipped | Surface catalog + endpoints + ledger keys on `/mind` |
| 2 | Invariants (no-repeat, fail closed) | shipped | Ledger PK; soft-recycle penalty; fail → cursor |
| 3 | Architecture diagram | shipped | Admin `/mind` architecture wall |
| 4 | Repo layout `intelligence/` | partial | Kept under `recommendation/` + `ops/` |
| 5 | Event envelope | shipped | Allowlist ingest + meta scrub + Kafka/PG |
| 6 | Masquerade isolation | shipped | Live proofs + surface namespace guards |
| 7 | Media understanding | shipped | Phase 2a: `video_transcripts` → `mind_content_features`; pgvector = 2b |
| 8 | Interest memory / features | shipped | Personality + creator affinity + featureHits on decisions |
| 9 | Candidate generation | shipped | Multi-lane retrieval + mix meta + inventory |
| 10 | Rank + diversity | shipped | MMR + family caps on Home/Hubs/Masquerade |
| 11 | Exposure ledger | shipped | `feed_video_delivery` on all For You surfaces |
| 12 | Search / world / rooms | partial | Search exists; world map later |
| 13 | Guardian | partial | Reports / moderation queues |
| 14 | Ads / economy | missing | Phase 4+ |
| 15 | GraphQL FeedItem | missing | REST instead (ADR 0002); MIND-006 metadata |
| 16 | Schema | partial | Delivery migration applied |
| 17 | Workers | partial | Pipeline + frame0; not full MIND workers |
| 18 | ML eval | missing | Phase 2–3 |
| 19 | Observability | shipped | `/mind` events, decisions, ledger, seed |
| 20 | Tests | partial | MIND-008 concurrency |
| 21 | Roadmap | shipped | Documented on admin page |

## Phase 1 tickets

| ID | Title | Status |
|----|-------|--------|
| MIND-001 | Shared contracts / surfaces | this pass |
| MIND-002 | Event allowlist alignment | this pass |
| MIND-003 | Central eligibility helper | this pass |
| MIND-004 | Ledger + Masquerade reserve | shipped (phase1.v2 await + soft recycle) |
| MIND-005 | Diversity / family gaps | shipped |
| MIND-006 | `deliveryId` / `modelVersion` / `requestId` on feeds | shipped |
| MIND-007 | Hide / not-interested exclusions | stub / wire if tables allow |
| MIND-008 | Concurrent reservation test | this pass |
| MIND-009 | `MIND_LEDGER_ENABLED` + admin | this pass |
