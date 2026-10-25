# Phases 3–5 (developer)

Source of truth: `docs/mind/Matterya_MIND_Engineering_Handbook.md` §21.  
Human twin: `docs/matterya/for-humans/08-phases-3-4-5.md`.

## Status
| Phase | Handbook | Matterya now |
|---|---|---|
| 0–1 | Reliable feed | shipped (`mind.phase1.*`) |
| 2 | Content intelligence | 2a+2b shipped (`mind.phase2.v2`) |
| 3a | Cold-start + eval | **shipped** (`mind.phase3.v1` / `server.v5-cold-start`) |
| 3b | Trained ranker · session · controls | **not built** (MIND-016–019) |
| 4 | Other surfaces | **scaffold** (ADR 0005); search/Guardian partial outside tickets |
| 5 | Scale | **gated** (ADR 0004) — wait for measured need |

## Phase 3 tickets → code touchpoints
| ID | Likely modules |
|---|---|
| MIND-015 | `knn.service` / `mind-candidates` cold-start lanes; shelf priors |
| MIND-016 | new `rank` model service + registry; flag in `rank.service.ts` |
| MIND-017 | session store / short-TTL features; re-rank path |
| MIND-018 | diversity / creator opportunity constraints in MMR |
| MIND-019 | extend `/mind/api/people` → user-facing interest API; explain `sources` on cards |

## Phase 4
| ID | Notes |
|---|---|
| MIND-020 | Search service + Voyage query embed + keyword |
| MIND-021 | People discovery — reuse People dossier signals carefully |
| MIND-022 | World/country shelf |
| MIND-023 | Masquerade isolation already partial — deepen tests |
| MIND-024 | Wire reports → Guardian policy |
| MIND-025 | Creator dashboard + ads audit |

## Phase 5
ADR-required: feature store, ANN cluster, serving autoscaling. Do not start without p95/QPS evidence.

## Phase 3a shipped (this pass)
**MIND-015 light + §18 eval stub**
- Rank: `apps/api/src/recommendation/rank.service.ts` — cold-start priors when `eventsCounted < 25` (country/hub/popular/fresh/ANN); `featureHits.coldStart` / `coldStartHits` logged on decisions.
- Lane catalog: `home_cold_start` in `mind-candidates.ts`.
- Eval: `cd apps/api && npx tsx scripts/mind-offline-eval.ts` (optional `LOOKBACK_HOURS`, `SURFACE`).
- Policy: `MIND_POLICY_VERSION=mind.phase3.v1`, rank `server.v5-cold-start`.
- ADRs: `docs/mind/adr/0004-phase5-scale-after-measured-need.md`, `0005-phase4-surfaces-scaffold.md`.

Next Phase 3 work: MIND-019 interest-control hooks → MIND-016 trained ranker behind a flag (after offline lift).
