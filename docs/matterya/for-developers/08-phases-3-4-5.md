# Phases 3–5 (developer)

Source of truth: `docs/mind/Matterya_MIND_Engineering_Handbook.md` §21.  
Human twin: `docs/matterya/for-humans/08-phases-3-4-5.md`.

## Status
| Phase | Handbook | Matterya now |
|---|---|---|
| 0–1 | Reliable feed | shipped (`mind.phase1.*`) |
| 2 | Content intelligence | 2a+2b shipped (`mind.phase2.v2`) |
| 3a | Cold-start + eval | **shipped** (`mind.phase3.v1` / `server.v5-cold-start`) |
| 3b | Trained ranker · session · controls | **shipped thin** (`mind.phase3.v2`) — logistic flag default off |
| 4 | Other surfaces | **shipped thin** (`mind.phase4.v1`) — search/Guardian/world/people; world still thin |
| 5 | Scale | **gated** (ADR 0004) — `scripts/mind-scale-benchmark.ts`; wait for measured need + separate ADR |

## Phase 3 tickets → code touchpoints
| ID | Likely modules |
|---|---|
| MIND-015 | `knn.service` / `mind-candidates` cold-start lanes; shelf priors |
| MIND-016 | `mind-trained-ranker.ts` + `scripts/mind-fit-ranker.ts` → `data/mind-ranker-weights.json`; flag in `rank.service.ts` |
| MIND-017 | `mind-session.ts` short-TTL features; re-rank path |
| MIND-018 | diversity / creator opportunity constraints in MMR |
| MIND-019 | `mind-interest-controls.ts` + migration `mind_user_interest_controls`; explain `sources` on cards |

## Phase 4
| ID | Notes |
|---|---|
| MIND-020 | Search hybrid — `mind-search.ts` / `GET /v1/search` (Voyage + keyword) |
| MIND-021 | People discovery — reuse People dossier signals carefully |
| MIND-022 | World/country shelf — `mind-world.ts` (thin) |
| MIND-023 | Masquerade isolation deepen — `scripts/mind-isolation-tests.ts` |
| MIND-024 | Guardian panel on `/mind` + report queues (appeals deepen later) |
| MIND-025 | Creator dashboard + ads audit (organic insights only for now) |

## Phase 5
ADR-required: feature store, ANN cluster, serving autoscaling. Do not start without p95/QPS evidence.

```bash
cd apps/api && npx tsx scripts/mind-scale-benchmark.ts
```

`scaleNeeded` stays false unless decision p95 latency_ms &gt; 3000 or decisions/24h &gt; 500000 (placeholders). Each Phase 5 piece still needs its own ADR + cost projection.

## Phase 3a shipped
**MIND-015 light + §18 eval stub**
- Rank: `apps/api/src/recommendation/rank.service.ts` — cold-start priors when `eventsCounted < 25` (country/hub/popular/fresh/ANN); `featureHits.coldStart` / `coldStartHits` logged on decisions.
- Lane catalog: `home_cold_start` in `mind-candidates.ts`.
- Eval: `cd apps/api && npx tsx scripts/mind-offline-eval.ts` (optional `LOOKBACK_HOURS`, `SURFACE`).
- Policy: `MIND_POLICY_VERSION=mind.phase3.v1`, rank `server.v5-cold-start`.
- ADRs: `docs/mind/adr/0004-phase5-scale-after-measured-need.md`, `0005-phase4-surfaces-scaffold.md`.

## Phase 3b + 4 shipped thin (this pass)
- Interest controls schema + API; session features; opportunity; logistic behind `MIND_TRAINED_RANKER_ENABLED`.
- Fit stub: `npx tsx scripts/mind-fit-ranker.ts`.
- Isolation CI: `npx tsx scripts/mind-isolation-tests.ts`.
- Scale probe: `npx tsx scripts/mind-scale-benchmark.ts`.

Next: deepen world/Guardian appeals when product asks; train ranker only after offline lift; Phase 5 only if benchmark says so.
