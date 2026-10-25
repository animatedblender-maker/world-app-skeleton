# Phases 3–5 (developer)

Source of truth: `docs/mind/Matterya_MIND_Engineering_Handbook.md` §21.  
Human twin: `docs/matterya/for-humans/08-phases-3-4-5.md`.

## Status
| Phase | Handbook | Matterya now |
|---|---|---|
| 0–1 | Reliable feed | shipped (`mind.phase1.*`) |
| 2 | Content intelligence | 2a+2b shipped (`mind.phase2.v2`) |
| 3 | Adaptive intelligence | **not built** |
| 4 | Other surfaces | **not built** (partial search/Guardian exist outside MIND tickets) |
| 5 | Scale | **not built** — wait for measured need |

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

## Recommended first PR for Phase 3
**MIND-015 light + §18 eval stub:** cold-start candidate blend documented + offline metric script against logged `recommendation_decisions`. No trained model yet.
