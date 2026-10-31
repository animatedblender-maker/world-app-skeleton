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

## Status
- [ ] Wipe old clients
- [ ] Scaffold empty Angular + Compose shells
- [ ] Theme + Copy
- [ ] Surfaces (checklist above)
- [ ] QA vs iOS

## Wipe
- Removed `apps/web` and `apps/mobile/android-app` at commit after this plan.
