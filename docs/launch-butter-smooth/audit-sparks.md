# Sparks full-screen player audit (web)

**Repo:** `/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton`  
**Gold:** iOS `ReelsVerticalFeed` + `SparksUIKitPager` + `docs/butter-smooth/09-MEDIA-SESSION.md` + `SparkWarmPool.MediaBudget`  
**Web:** `apps/web/src/app/pages/reels.page.ts`, `components/video-player.component.ts`, `core/services/r2-playback.service.ts`, `surface-page.service.ts`, `media-session.service.ts`  
**Date:** 2026-10-16 · **Deploy:** not in scope

---

## Target checklist (launch butter-smooth)

| Target | Gold (iOS) | Web before fixes | Gap |
|--------|------------|------------------|-----|
| Vertical snap paging | UICollectionView paging / snappy settle | `scroll-snap-type: y mandatory` + `scroll-snap-stop: always` | Mostly OK; no settle debounce / early focus commit |
| Warm window: active + next ~5 (deep 2) | `preparePlayerWindow` ahead=5, deepPreroll=2 | URL `ensurePlayable` for next 5; **every** reel mounts `<video preload=auto>` | Critical: AV storm / decode thrash |
| Infinite discovery `/v1/sparks` + `discoverSparks` | Surface page + discover append | `SurfacePageService.fetchSparks` + `PostsService.discoverSparks` + load-more at −6 | OK |
| Fresh R2 via `/v1/playback` | R2PlaybackResolver | `R2PlaybackService.playURL` / `freshenPosts` | OK for open path |
| Progress rail `#7b6347` | `Theme.reelsAccent` | `var(--m-accent-bright, #7b6347)` | OK |
| Mute global consistency | App-wide mute | `VideoPlayerComponent.globalMuted` + `__videoMuted` + event | Plumbing OK; Sparks chrome hides mute (`showMute=false`) |
| Recover 403 by re-resolve | Invalidate + re-sign | Player `onError` only quality/ad fallback — **no R2 re-resolve** | High |
| Pause when leaving page | silence / drain warm on disappear | `releaseSparks()` only — videos may keep decoding until GC | High |
| Exclusivity vs Hubs mini | MediaSession + silence hubs | `claimSparks` + `hubsPlayback.setPlaying(false)` | Partial (mini has no real AV yet; session claim OK) |

---

## What already matches gold

1. **Discovery path** — thin `GET /v1/sparks` then GraphQL `discoverSparks`, country merge when slug ≠ WORLD, shuffle open, seed handoff from feed/hubs state.
2. **Playback freshen** — `freshenPosts` + per-id `playURL`; preserves spark JSON payload identity so `isSpark()` stays true.
3. **Media session** — `MediaSessionService` modes `idle|feedAutoplay|hubs|sparks`; Sparks claims on enter / releases on destroy; feed checks `sparksOwns`.
4. **Snap CSS** — full-viewport `.reel` + mandatory Y snap + overscroll contain.
5. **Accent** — progress active + chip-dot use `#7b6347`.
6. **Near-end paging** — `loadMoreReels` at `length - 6`, cursor then discover fallback.

---

## Findings (severity)

### P0 — Mount-all players (butter killer)
`*ngFor` mounts an `<app-video-player>` (HTMLVideoElement, IntersectionObserver, ads decision) for **every** spark. iOS keeps ≤ ~7 AV slots (5 ahead + 1 behind + spare) with deep preroll only for next 2.

**Effect:** memory pressure, decode contention, janky snap, battery drain; `preload="auto"` amplifies.

**Fix:** windowed mount — players for `[active−1 … active+5]`; `preload=auto` for active+deep2; `metadata` for outer warm; poster-only beyond.

### P0 — No 403 / expired R2 recovery
`video-player.onError` recovers quality ladder / ads only. Expired Cloudflare R2 presigns (403) leave a dead reel until remount.

**Fix:** emit `mediaError`; page `invalidate(id)` + force `playURL`; Angular `[src]` change reloads via existing `ngOnChanges`.

### P1 — Leave path does not pause media
`ngOnDestroy` releases session but does not pause in-DOM videos. Tab hide (`visibilitychange`) also ignored. Competing audio if destroy is delayed.

**Fix:** `pauseAllReelVideos()` on `visibilitychange` (hidden) + destroy; keep `releaseSparks`.

### P1 — Mute affordance missing on Sparks chrome
Global mute works if set elsewhere, but Sparks UI forces `[showMute]="false"` and CSS-hides `.mute-toggle`. Users cannot toggle mute in-player.

**Fix:** chrome mute button that flips `__videoMuted` + `video-player-mute` event (same bus as player).

### P2 — Warm depth vs deep preload undifferentiated
URL resolve for next 5 exists; no distinction between deep (first-frame ready) and light warm. All mounted players used `preload=auto`.

**Fix:** couple windowed mount with `preloadFor(i)`.

### P2 — Intersection threshold 0.12
With mount-all, multiple reels could claim play briefly during fling. Windowed mount reduces blast radius; optional later: reel-specific threshold ~0.55.

### P3 — Hubs mini exclusivity incomplete
Mini chrome has no continuous `<video>` yet (poster bar only). `setPlaying(false)` + `claimSparks` is correct scaffolding; real dual-audio risk returns when continuous layer ships.

### P3 — Snap polish
No early focus commit / velocity settle like `SparksUIKitPager` early snap. CSS snap is adequate for launch; optional `scrollend` warm is nice-to-have.

---

## File map

| File | Role |
|------|------|
| `apps/web/src/app/pages/reels.page.ts` | Sparks pager UI + discovery + warm + session |
| `apps/web/src/app/components/video-player.component.ts` | HTML5 player, global mute, solo focus, ads |
| `apps/web/src/app/core/services/r2-playback.service.ts` | `/v1/playback/:id` cache + freshen |
| `apps/web/src/app/core/services/surface-page.service.ts` | `/v1/sparks` thin cards |
| `apps/web/src/app/core/services/media-session.service.ts` | Single-owner mode (09 contract) |
| `apps/mobile/.../SparkWarmPool.swift` | Gold budgets: ahead 5, deep 2, behind 1 |
| `docs/butter-smooth/09-MEDIA-SESSION.md` | One playing session app-wide |

---

## Implemented in this pass (no deploy)

1. Windowed player mount + differentiated preload (deep 2 / warm 5 / poster beyond).
2. `mediaError` → invalidate + re-resolve playback (403 recovery).
3. Pause all reel videos on tab hide + page destroy.
4. Chrome mute toggle wired to global mute bus.
5. Central `warmPlaybackWindow(index)` aligned to iOS 5-ahead.

## Deferred (not safe / out of scope)

- Full virtualized list (recycle DOM cells) — larger rewrite.
- Raising IntersectionObserver threshold via new `@Input` — optional follow-up.
- Continuous Hubs mini AV layer exclusivity — blocked on hubs continuous player.
- Deploy / gh-pages.
