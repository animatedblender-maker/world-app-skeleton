# Days 1–30 inventory (living doc)

## Synchronous dependency chains (known)

| Path | Chain | Notes |
|------|-------|-------|
| Feed first paint | cache → optional GraphQL/thin feed → rank off-main | Soft-merge preserves head |
| Hubs open | slug shelf API → fallback loadPlayCatalog | Thin path preferred |
| Sparks open | SurfacePageClient / loadReelsFeedPage | Warm pool |
| Messages open | cache TTL → hydrate | — |
| Rank | POST /v1/recommendation/rank | Soft; timeout 4s client |

## OFFSET pagination

- Avoid for large feeds; prefer keyset / opaque cursor (HomeFeedStore nextCursor, thin `/v1/feed`).  
- Audit remaining GraphQL `offset` if any → ticket BS-013.

## N+1 risks

- Profile avatars in lists: batch or cache.  
- Feed hydration must stay batch (posts:batch / DataLoader).  
- Playback: use `/v1/playback/batch` not per-id on head.

## Main-thread hotspots (iOS)

| Risk | Mitigation |
|------|------------|
| Large JSON decode | ContentCache background; rank async |
| Image decode | ImageCache off main |
| Rank 200+ posts sync | `rankForSessionAsync` |
| Continuous player layout | pass-through hit test; no full-window GeometryReader steal |

## Caches without invalidation (watch)

| Cache | Invalidation |
|-------|----------------|
| ContentCache homeFeed | generation / force refresh / logout |
| hubsSessionCatalog | remember / delete / logout |
| ImageCache | memory pressure / URL key |
| Feature config | version + ttlSec |

Update this file as code lands.
