# MIND Phases 3 → 4 → 5 (handbook plan)

**Where we are:** Phase 0–1, Phase 2a/2b, **Phase 3a**, **Phase 3b (thin)**, and **Phase 4 (thin)** are built.  
**Next:** deepen world/Guardian appeals as product needs them; train the ranker only after offline lift proves it.  
**Rule:** finish each phase’s **gate** before jumping ahead. **Phase 5 only after measured need** (`mind-scale-benchmark` + separate ADR).

---

## Phase 3 — Adaptive intelligence

**Plain meaning:** the feed stops being “smart rules + Voyage neighbors” and starts **learning** what each person likes — with cold-start backup, experiments, and user-visible interest controls.

| Ticket | What | Why it matters | Status |
|---|---|---|---|
| **MIND-015** | Collaborative candidates + **cold-start fallback** | New users still get a good feed | shipped (3a) |
| **MIND-016** | **Trained ranker** + model registry | Better ordering than hand-tuned scores | thin — flag off + fit stub |
| **MIND-017** | Session features + monitored re-rank | Feed adapts within a session | shipped thin |
| **MIND-018** | Creator opportunity / diversification | Fairer discovery for creators | shipped thin |
| **MIND-019** | Explainability + **user interest controls** | “Why am I seeing this?” + People-dossier → user-facing | shipped thin |

**Gate (handbook):** generalization, fairness, satisfaction, and cost proven — not just “model exists.”

**Phase 3a done:** cold-start priors + offline eval script.  
**Phase 3b done (thin):** interest controls, session, opportunity, logistic behind a flag + `mind-fit-ranker` co-occurrence stub.

---

## Phase 4 — Other product surfaces

**Plain meaning:** MIND powers more of the product than Home/Hubs/Sparks ranking.

| Ticket | What | Status |
|---|---|---|
| **MIND-020** | Search: semantic + keyword hybrid | shipped thin |
| **MIND-021** | People / creator discovery (privacy review) | shipped thin |
| **MIND-022** | World / country feed (geoprivacy) | shipped thin (world still light) |
| **MIND-023** | Masquerade-only identity + room rank + isolation tests | shipped thin (CI script) |
| **MIND-024** | **Guardian** depth — signals, policy, appeals | panel shipped; appeals deepen later |
| **MIND-025** | Creator insights + payment/ad audit hooks | organic insights only |

**Also on roadmap here:** ads/economy (§14) when product is ready.

---

## Phase 5 — Scaling (only after observed need)

**Plain meaning:** infrastructure when traffic forces it — not “build Kubernetes because it sounds cool.”

- Feature store, event broker hardening, warehouse  
- ANN cluster / dedicated search service  
- Model-serving autoscaling, multi-region  
- Each piece needs an ADR + cost projection  

**Gate:** benchmark proves current stack is the bottleneck.

```bash
cd apps/api && npx tsx scripts/mind-scale-benchmark.ts
```

Reports `scaleNeeded` from decision latency p95 and 24h volume placeholders. Do not start Phase 5 infra from this script alone.

---

## Suggested order to “finish it all”

```
Close Phase 2b live checks (Voyage ANN ON + iOS rebuild)
        ↓
Phase 3a — cold start + eval          ✅
        ↓
Phase 3b — controls / session / logistic flag (thin)  ✅
        ↓
Phase 4 — search / Guardian panel / world / isolation  ✅ thin
        ↓
Deepen world · Guardian appeals · offline lift → real train
        ↓
Phase 5 — only if mind-scale-benchmark + ADR say we must
```

Then: **fun** (product experiments, multimodal pilots, delightful UI — unconstrained by the handbook gate).

---

## What we already have that Phase 3–4 build on
- Voyage embeddings + ANN soft boost  
- Creator affinity + personality bubbles  
- `/mind` People dossiers + Guardian panel (Ops)  
- Delivery ledger + decisions with `featureHits` / `annHits`  
- Kafka engagement path  
- Interest controls table + hybrid search  

Phase 5 is **not** next by default — measure first.
