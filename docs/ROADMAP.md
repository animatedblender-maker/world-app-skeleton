# Matterya roadmap (from butter-smooth + recsys blueprints)

Detailed blueprints: `docs/reference/`. Apply status: `docs/APPLY_BUTTER_AND_RECSYS.md`.

---

## Now — Phase 0 (instrumentation + deterministic feeds)

- [x] Canonical engagement batch path (client → API → Kafka)
- [x] Recommendation surface policy objects (iOS)
- [x] Constrained re-ranker (creator diversity, exploration, eligibility)
- [x] Decision logs: impression, ranked_served, viewport_visible
- [ ] Prod Kafka enabled + Console verification
- [ ] Warehouse sink for engagement
- [ ] Hide / Not interested product actions
- [ ] Explicit Home Following chip (optional)

**Exit:** >99% core events captured; feed reconstructable from logs; latency budgets defined.

---

## Next — Butter Phase 1 (core social smoothness)

- [x] Local-first feed cache / soft-merge
- [x] Cursor pagination (home/sparks)
- [x] Image/video warm pools
- [ ] Bulk post-view hydration API
- [ ] RUM (Sentry/Firebase) on golden journeys
- [ ] CDN cache policies for static + media

---

## Recsys Phase 1 (weeks 6–12)

- Hand-engineered user/item features  
- Co-visitation candidate source  
- GBDT or small MLP ranker  
- A/B vs deterministic baseline  
- Shadow + canary model deploy  

---

## Butter Phase 2–3 / Recsys Phase 2

- Resumable uploads end-to-end  
- Adaptive video delivery metrics  
- Feature registry + online store  
- Two-tower retrieval + ANN  

---

## Later (only when measured)

- Multi-task sequence ranker  
- Exploration / causal learning  
- Multi-region DR  
- Extreme-scale sharding  

---

## Golden journeys (must not regress)

1. Cold launch → home feed  
2. Warm launch → cached feed  
3. Open Spark / endless scroll  
4. Open Hubs video → mini → maximize  
5. Like / follow optimistic  
6. Upload Spark / long video  
7. Message send + reconnect  
8. Notification deep link  
