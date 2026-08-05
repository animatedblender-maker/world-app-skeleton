# iOS ↔ Web product parity

**Source of truth:** native iOS app (`apps/mobile/ios/WorldApp`).  
**Goal:** the Angular web app (`apps/web`) matches iOS product behavior and information architecture. Shared backend remains GraphQL + Supabase.

## Strategy

| Decision | Choice |
|----------|--------|
| Gold master | **iOS** |
| Client stacks | Keep SwiftUI + Angular (no Capacitor rewrite) |
| Shared contracts | GraphQL, Supabase auth/storage, seed assets where needed |
| First parity surface | **Matterya Hubs** (watch experience) |

## Shared seed / data (critical)

| Flag / source | iOS | Web |
|---------------|-----|-----|
| `useDemoDataset` | `true` (`AppConfig`) | **`true`** (dev + prod env) |
| Social posts seed | `demo_social_dataset_30k` / bundled `demo_social_seed` | `public/demo_social_dataset_30k` (capped 4k like iOS) |
| Fake people | names + fake users | `fake_users_60k_real_names` + `FakeDataService` |
| Hub videos | `hub_videos.jsonl` | `public/hub_video_seed/hub_videos.jsonl` |
| Home feed merge | live first, demo filler | `listRecent` + `loadHomeFeed` same rule |
| Search posts | demo + real | `searchPosts` merges demo when enabled |
| Country feed | demo merge | already via `listByCountry` when flag on |

## Hubs parity status (2026-07-31)

### Shipped on web (aligned with iOS)

| Capability | iOS | Web |
|------------|-----|-----|
| Hubs home IA | YouTubeAppView shelves | `/hubs` — Sparks strip, Continue watching, Following, Discover |
| Category chips | YouTubeHomeFilter | Same filter set (For you, categories, Trending, Latest) |
| Seed catalog | `hub_videos.jsonl` / HubVideoSeedService | `public/hub_video_seed/hub_videos.jsonl` + `HubsSeedService` |
| Long-form watch | YouTubeWatchView | `/hubs/watch/:id` (+ `/play/watch/:id` alias) |
| Channel page | YouTubeChannelView | `/hubs/channel/:id` |
| Library | History / Sparks / Saved / Liked / Uploads | In-Hubs Library mode |
| In-Hubs search | YouTubeSearchSheet | Search panel on Hubs |
| Mini player | GlobalHubPlaybackLayer | `HubsPlaybackService` + `app-hubs-mini-player` |
| Watch history + resume | UserDefaults | localStorage keys `matterya.play.*` |
| Local seed engagement | HubEngagementStore | `HubsEngagementService` |
| Sparks handoff | Reels viewer | `/sparks/:country` with `history.state.seedPosts` |
| Share deep links | matterya.com/play/… | `/hubs/watch/:id`, `/play/watch/:id` |

### Still behind iOS (next)

- Continuous **single `<video>` element** remount-free between full stage and mini (web remounts player; resume position mitigates)
- Archive CDN progressive resolve (`ArchiveVideoPlayback`) beyond direct IA URLs
- Full `HubCategoryClassifier` multi-persona channels
- Channel setup + hub-publish composer parity inside Hubs
- Reels ranking engine fidelity + passport world-hop
- Engagement analytics events (`hub_open`, `hub_video_open`, …)
- Autoplay-next related (neither client has true up-next yet)

## Web file map (Hubs)

```
apps/web/src/app/hubs/
  hubs-seed.service.ts
  hubs-catalog.service.ts
  hubs-engagement.service.ts
  hubs-playback.service.ts
  components/hubs-mini-player.component.ts
apps/web/src/app/pages/
  hubs.page.ts
  hubs-watch.page.ts
  hubs-channel.page.ts
apps/web/public/hub_video_seed/hub_videos.jsonl
```

## Remaining product surfaces (ordered)

1. **Home feed** — Sparks strip, continue watching, post cards, paging (`HomeFeedStore`)
2. **Messages / calls** — edit/delete media, CallKit-grade UX where web allows
3. **Globe** — presence, notifications panel, moments composer parity
4. **Profile** — channel setup, hub uploads, owner/public flows
5. **Search / people / ads** — close remaining contract gaps

## Rule

Do not invent web-only product behavior for shared features. Port iOS contracts first (data source, sort, dedupe, navigation intent). Presentation may use web patterns; semantics should match.
