# MIND implementation log — Phase 0+1 (2026-10-25)

What we shipped in this pass, for admins and engineers.

## Documentation

- Vendored handbook → `docs/mind/Matterya_MIND_Engineering_Handbook.md`
- Phase 0 audit → `docs/mind/00-audit.md`
- Gap matrix → `docs/mind/01-gap-matrix.md`
- ADR 0001 ledger reuse · ADR 0002 REST Phase 1
- Admin runbook → `docs/mind/runbooks/admin-mind-console.md`

## Admin console

- **URL:** `/mind` on the API (same Ops password as Pipeline / Reports / Frame 0)
- Live status: `GET /mind/api/status`
- Docs HTML: `GET /mind/api/docs/:slug`
- SSE: `GET /mind/api/stream`
- Pipeline overview links to MIND

Panels: overview, live ledger/seed, architecture wall, gap matrix, Masquerade rooms + isolation, handbook browser, roadmap.

## Code

| File | Role |
|------|------|
| `recommendation/mind-contracts.ts` | Surfaces, policy version, ledger kill switch |
| `recommendation/eligibility.ts` | Hard gates + Public/Masquerade namespace isolation |
| `ops/mind-status.ts` | Read-only aggregator |
| `ops/mind-page.ts` | Illustrated admin HTML |
| `delivery.service.ts` | Honors `MIND_LEDGER_ENABLED` |
| `anonymous/feed.ts` | Returns `mind` meta (`requestId`, `modelVersion`, `deliveryPolicy`) |
| `remote-config.ts` | Exposes `mind_ledger_enabled` |
| `scripts/mind-delivery-concurrency-check.ts` | MIND-008 concurrent reserve test |
| `scripts/mind-offline-eval.ts` | §18 offline metrics over `recommendation_decisions` |

## Verification run locally

```bash
cd apps/api
npx tsx src/recommendation/eligibility.test.ts
npx tsx scripts/mind-delivery-concurrency-check.ts
npx tsc -p tsconfig.json --noEmit
# then open http://127.0.0.1:3000/mind
```

## Follow-ups shipped

- **phase1.v2** — P0 feed reliability (§2/§10/§11 shipped)
- **phase1.v3** — Events hygiene (`sanitizeEngagementMeta`) + `/mind` live event/decision panels (§5/§19 shipped)
- **phase1.v4** — Masquerade isolation proofs + surface namespace asserts (§6 shipped)
- **phase1.v5** — Candidate lanes catalog, feed `candidateMix`, admin inventory (§9 shipped)
- **phase1.v6** — Interest features panel + decision featureHits (§8 shipped)
- **phase1.v7** — Purpose / surface catalog on Overview (§1 shipped; Phase 1 matrix complete)
- **phase2.v1** — §7 Media understanding Phase 2a: `mind_content_features` from `video_transcripts`, soft topic boost, `/mind` media panel
- **phase2.v2** — §7 Phase 2b: Voyage `voyage-4-lite` title/body embeddings → `mind_content_embeddings` (pgvector), soft ANN lane `home_ann_title` / rank `ann` boost
- **phase3.v1** — Phase 3a (MIND-015 light + §18 stub): cold-start prior blend in `rank.service` (`server.v5-cold-start`, eventsCounted &lt; 25 → country/hub/popular/fresh/ANN priors; lane `home_cold_start`); offline eval harness `scripts/mind-offline-eval.ts`; ADR 0004 (Phase 5 scale gate) + ADR 0005 (Phase 4 surfaces scaffold)

## Not in this pass

Trained rankers (MIND-016), session re-rank (017), ads, GraphQL FeedItem, Guardian depth (024), hybrid search (020), full long-form STT catalog. Phase 4–5 scaffolded as ADRs; shown as roadmap on `/mind`.

## Production

Deploy via Render `ios-native` / `apps/api` when authorized. Until then, local `/mind` is the admin surface.
