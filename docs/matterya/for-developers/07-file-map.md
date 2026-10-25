# File map (developer)

## API — MIND / Voyage
| Path | Role |
|---|---|
| `apps/api/src/recommendation/mind-contracts.ts` | Policy version, surfaces |
| `apps/api/src/recommendation/mind-embeddings.ts` | Voyage client, schema, schedule, backfill, ANN |
| `apps/api/src/recommendation/mind-media.ts` | Phase 2a features |
| `apps/api/src/recommendation/mind-candidates.ts` | Candidate lanes incl. ANN |
| `apps/api/src/recommendation/mind-isolation.ts` | Public ↔ Masquerade |
| `apps/api/src/recommendation/rank.service.ts` | Scoring + ANN merge |
| `apps/api/src/ops/mind-page.ts` | `/mind` HTML |
| `apps/api/src/ops/mind-status.ts` | Status aggregator |
| `apps/api/src/main.ts` | Routes incl. `/cron/mind-embeddings` |
| `apps/api/src/graphql/modules/posts/posts.service.ts` | create/update → schedule embed |
| `apps/api/src/content-pipeline/run.ts` | Seed inserts → schedule embed |
| `apps/api/src/media/transcribe.ts` | Transcript ready → features |
| `apps/api/scripts/run-mind-embeddings-cron.mjs` | Optional Render cron caller |
| `render.yaml` | Web + content-pipeline cron + mind-embeddings cron stub |

## iOS — attribution
| Path | Role |
|---|---|
| `…/Services/HubVideoSeedService.swift` | Archive channel + `isHubSeedVideo` |
| `…/Services/PlayPlatformBridge.swift` | `displayCreator`, catalog helpers |
| `…/Views/Components/FacebookPostCard.swift` | Feed card names / Shared from |
| `…/Services/YouTubeCatalogService.swift` | Channel grouping |
| `…/Services/HubCategoryClassifier.swift` | Slug display fallback |

## Web
| Path | Role |
|---|---|
| `apps/web/src/app/hubs/hubs-seed.service.ts` | `isHubSeedVideo` parity |

## Docs
| Path | Role |
|---|---|
| `docs/matterya/` | **This pack** (humans + developers) |
| `docs/mind/` | Handbook, gap matrix, ADRs, `MIND_FOR_HUMANS.md` |
| `docs/CONTENT_PIPELINE.md` | Pipeline + embed catch-up note |
| `docs/RENDER.md` | Render build quirks |

## Mac runtime (not in git)
| Path | Role |
|---|---|
| `/Volumes/MatteryaSSD/Development/tmp/mind-embed/` | Backfill + progress :8789 |
| `/Volumes/MatteryaSSD/Development/keep_progress_servers_alive.sh` | Keeps :8789 among others |
| `/Volumes/MatteryaSSD/Development/docs/matterya/` | Mirror of this pack |
