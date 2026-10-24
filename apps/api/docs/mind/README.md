# MIND — Matterya Intelligence & Discovery

MIND is Matterya’s shared recommendation and discovery infrastructure: eligible content in, ranked pages out, with a durable **no-repeat delivery ledger**, privacy boundaries (especially **Masquerade**), and admin observability.

This folder is the **source of truth for what we actually ship**, reconciled against the engineering handbook.

## For admins

Open the live console (same Ops password as Pipeline / Reports / Frame 0):

- **Production:** https://api.matterya.com/mind
- **Local API:** http://127.0.0.1:&lt;api-port&gt;/mind

The page illustrates architecture, live ledger/seed health, gap status vs the handbook, and the full handbook text.

## Documents

| Doc | Purpose |
|-----|---------|
| [Matterya_MIND_Engineering_Handbook.md](./Matterya_MIND_Engineering_Handbook.md) | Target specification (v1.0) |
| [00-audit.md](./00-audit.md) | Phase 0: what exists in this repo today |
| [01-gap-matrix.md](./01-gap-matrix.md) | Handbook § → code map + tickets |
| [adr/0001-ledger-reuse-feed-video-delivery.md](./adr/0001-ledger-reuse-feed-video-delivery.md) | Why we reuse `feed_video_delivery` |
| [adr/0002-rest-not-graphql-for-v1.md](./adr/0002-rest-not-graphql-for-v1.md) | Why Phase 1 stays on REST |
| [runbooks/admin-mind-console.md](./runbooks/admin-mind-console.md) | How to read the admin UI |

## Code map (Matterya names)

| Concern | Path |
|---------|------|
| Delivery ledger | `apps/api/src/recommendation/delivery.service.ts` |
| Rank + MMR | `apps/api/src/recommendation/rank.service.ts` |
| Home / Hubs shelves | `apps/api/src/recommendation/shelf.service.ts` |
| Masquerade feed | `apps/api/src/anonymous/feed.ts` |
| MIND contracts | `apps/api/src/recommendation/mind-contracts.ts` |
| Eligibility gates | `apps/api/src/recommendation/eligibility.ts` |
| Admin UI | `apps/api/src/ops/mind-page.ts` |
| Admin status API | `apps/api/src/ops/mind-status.ts` |

## Phases

- **Phase 0+1 (this pass):** audit, admin console, ledger/rank vertical slice.
- **Phase 2+:** media embeddings, trained rankers, Guardian depth — shown on the admin roadmap as not built yet.
