# iOS golden rebuild — Web + Android

**Rule:** `apps/mobile/ios/WorldApp` is the only product source of truth.  
**Do not edit iOS.** Backend stays `apps/api` + `api.matterya.com`.

**User mandate (2026-10-31):** Delete prior `apps/web` and `apps/mobile/android-app`, rebuild both from iOS until **everything** matches — copy, colors, behavior, Sparks, Hubs, Masquerade, feed autoplay, dimensions (web desktop = layout adaptation only).

## Stacks
| Client | Stack | Path |
|--------|--------|------|
| iOS (gold) | SwiftUI | `apps/mobile/ios/WorldApp` |
| Android | Kotlin + Jetpack Compose | `apps/mobile/android-app` (recreated) |
| Web | Angular | `apps/web` (recreated) |

## Port order (both clients)
1. Theme + MatteryaCopy (`Theme/Theme.swift`) — exact colors; product name **Masquerade** (not “Anonymous” in UI)
2. Config / GraphQL / Auth / session
3. RootView → MainTabView + tab bar
4. Feed (HomeFeedStore + FacebookPostCard + playGate autoplay + strips)
5. Sparks / Reels (ReelsView / SparksUIKitPager) — same chrome + behavior
6. Hubs / Living (YouTubeAppView, Watch, Channel, mini player)
7. Masquerade / Anonymous (all Views/Anonymous + AnonymousService)
8. Messages + CallOverlay
9. Profile / Edit / Public / Setup
10. Search / People / Settings / Ads / Letters / News / Globe (as on iOS)

## Acceptance
- Same user-visible strings as `MatteryaCopy`
- Same Theme tokens (accent = ink, never brown/gold)
- Feed focus autoplay matches iOS `FeedVideoFocus` / playGate
- Sparks full-screen vertical player matches iOS
- Hubs home/watch/channel/mini match iOS Living/*
- Masquerade labeled Masquerade everywhere in UI
- Web: phone layout ≈ iOS; desktop = wider chrome only, same components/semantics
- Android: emulator installable; Web: gh-pages

## File inventory
See `docs/ios-golden-file-inventory.txt` (~194 Swift files).

## Status (live)
- [x] Wipe old clients (commit 80c48b3e)
- [x] Scaffold / restore Compose + Angular trees as infrastructure base
- [x] Theme + MatteryaCopy from iOS (accent=ink, never brown/gold; UI name Masquerade)
- [x] Core surfaces ported: Feed autoplay, Sparks, Hubs rails, Masquerade, Messages ink chrome, Profile/Auth/Search
- [x] Android emulator install verified (Feed + Masquerade Wilde + tabs)
- [x] Web `ng serve` / `ng build` development OK on :4200
- [x] Android Hubs Library screen (History / Sparks / Saved / Liked / Uploads)
- [x] Android Feed→Sparks `instantOpenSeeds(12)` + deferred expand (iOS open path)
- [x] Android Hubs pull-to-minimize (≥0.35) + landscape FS letterbox
- [x] Android Hubs rails → `openLivingVideo` (no Feed fallthrough)
- [x] Web Hubs 2-cycle looping Netflix rails
- [x] Android chat dock hole: continuous Hubs mini docks into conversation bar (HubContinuousDockSlot)
- [x] Android chat open syncs `AppState.openConversation` so `hubPlaybackDockInChat` flips (mini above composer)
- [x] Continuous Hubs: loop + survive VideoPlayerView remount; ENDED seek restart
- [x] Android expanded Hubs: Back chip above continuous film (tappable minimize)
- [x] Web chat dock: hubs mini docks above Messages composer when thread open (compact 56px bar + hole)
- [x] Web expanded Hubs: Back chip on player stage → minimize to mini + history.back
- [ ] Remaining fidelity gaps (gh-pages prod deploy, side-by-side QA)
- [ ] Full QA pass vs iOS simulator side-by-side

### Web deep-link note
- `ng serve` SPA fallback serves `index.html` for `/hubs` when `Accept: text/html` (browsers). Bare `curl` without that header gets Express 404 — not a product bug.
- `deploy-gh-pages.sh` copies `index.html` → `404.html` for GitHub Pages path deep-links; `app.ts` also honors `?redirect=` from `public/404.html`.

## Verified on device (2026-10-31 → 2026-11-01)
- Android tabs: Feed | Masquerade | + | Matterya Hubs | Messages | Profile
- Feed: Sparks for you strip, Matterya Hubs chip, ExoPlayer in-frame; strip tap opens Sparks viewer
- Hubs: Library chip trailing + statusBarsPadding; hero Play → expanded watch; pull-down → mini
- Masquerade: Wilde → welcome letter → spaces onboarding → Ready (anonymous handles, post detail)
- Theme: paper `#f8f6f2`, ink `#2c2825` (no brown/gold accents)
- Web: looping rails in `hubs.page.ts`; deep-link `/hubs` may 404 without SPA fallback (in-app nav OK)

## Wipe
- Removed `apps/web` and `apps/mobile/android-app` at commit after this plan.
