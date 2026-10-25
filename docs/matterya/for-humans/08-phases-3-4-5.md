# MIND Phases 3 → 4 → 5 (handbook plan)

**Where we are:** Phase 0–1 and Phase 2a/2b are built.  
**Next:** Phase 3 → 4 → 5 from the Matterya MIND Engineering Handbook (§21).  
**Rule:** finish each phase’s **gate** before jumping ahead. Phase 5 only after measured need.

---

## Phase 3 — Adaptive intelligence

**Plain meaning:** the feed stops being “smart rules + Voyage neighbors” and starts **learning** what each person likes — with cold-start backup, experiments, and user-visible interest controls.

| Ticket | What | Why it matters |
|---|---|---|
| **MIND-015** | Collaborative candidates + **cold-start fallback** | New users still get a good feed |
| **MIND-016** | **Trained ranker** + model registry | Better ordering than hand-tuned scores |
| **MIND-017** | Session features + monitored re-rank | Feed adapts within a session |
| **MIND-018** | Creator opportunity / diversification | Fairer discovery for creators |
| **MIND-019** | Explainability + **user interest controls** | “Why am I seeing this?” + People-dossier → user-facing |

**Gate (handbook):** generalization, fairness, satisfaction, and cost proven — not just “model exists.”

**Practical first slice (recommended start):**
1. Cold-start policy using country/hub priors + Voyage ANN (MIND-015 light)  
2. Offline eval harness (§18) so we can measure wins (MIND-014 leftover → 3)  
3. Expand People dossier → interest controls / explainability hooks (MIND-019 light)  
4. Only then a trained ranker (MIND-016) behind a flag  

---

## Phase 4 — Other product surfaces

**Plain meaning:** MIND powers more of the product than Home/Hubs/Sparks ranking.

| Ticket | What |
|---|---|
| **MIND-020** | Search: semantic + keyword hybrid |
| **MIND-021** | People / creator discovery (privacy review) |
| **MIND-022** | World / country feed (geoprivacy) |
| **MIND-023** | Masquerade-only identity + room rank + isolation tests |
| **MIND-024** | **Guardian** depth — signals, policy, appeals |
| **MIND-025** | Creator insights + payment/ad audit hooks |

**Also on roadmap here:** ads/economy (§14) when product is ready.

**Practical first slice:** hybrid search (020) + Guardian depth on existing report queues (024) — biggest user-visible wins.

---

## Phase 5 — Scaling (only after observed need)

**Plain meaning:** infrastructure when traffic forces it — not “build Kubernetes because it sounds cool.”

- Feature store, event broker hardening, warehouse  
- ANN cluster / dedicated search service  
- Model-serving autoscaling, multi-region  
- Each piece needs an ADR + cost projection  

**Gate:** benchmark proves current stack is the bottleneck.

---

## Suggested order to “finish it all”

```
Close Phase 2b live checks (Voyage ANN ON + iOS rebuild)
        ↓
Phase 3a — cold start + eval + interest controls
        ↓
Phase 3b — trained ranker behind flag
        ↓
Phase 4a — search hybrid + Guardian depth
        ↓
Phase 4b — discovery / world / creator insights / ads when ready
        ↓
Phase 5 — only if metrics say we must
```

Then: **fun** (product experiments, multimodal pilots, delightful UI — unconstrained by the handbook gate).

---

## What we already have that Phase 3 builds on
- Voyage embeddings + ANN soft boost  
- Creator affinity + personality bubbles  
- `/mind` People dossiers (Ops)  
- Delivery ledger + decisions with `featureHits` / `annHits`  
- Kafka engagement path  

Phase 3 is **not** starting from zero — it’s teaching the system to adapt with proof.
