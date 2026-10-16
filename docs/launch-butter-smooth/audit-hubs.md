# Web Hubs butter-smooth audit (home + watch + mini)

**Date:** 2026-10-16  
**Repo:** `/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton`  
**Gold:** iOS `YouTubeAppView` / `GlobalHubPlaybackLayer` + `docs/butter-smooth/09-MEDIA-SESSION.md` + `08-HUBS-A-Z-AUDIT.md`  
**Scope:** web Hubs home, watch, mini player — continuity / exclusivity only. **No deploy.**

---

## Goals vs status

| Goal | Status | Notes |
|------|--------|-------|
| Shelves: posters only while scrolling | **Pass (fixed)** | Rows / continue / channel / related no longer fall back to playable `media_url` as `<img>`. |
| Watch open: instant poster then frames; resume mid-clip | **Pass** | Watch paints poster + `startTime` from catalog; video mounts after first paint. |
| Expand ↔ mini continuous (same content, position preserved) | **Pass (fixed)** | Mini now hosts a live `<video>`; playhead persisted via catalog; expand remounts watch from saved position. |
| Only one playing session; mute Sparks/feed when hubs plays | **Pass (fixed)** | `MediaSessionService.claimHubs` on start/minimize/expand; Sparks pauses hubs; Sparks destroy reclaims hubs. |
| Compact 16:9 stage, no letterbox bars | **Pass (fixed)** | Cover fill kept; desktop ≥1280px max-height regression restored to ~42vh compact stage. |

---

## Architecture (web vs iOS gold)

```
iOS: GlobalHubPlaybackLayer owns ONE AVPlayer; frame morphs expand↔mini (contentID-only rehost).

Web (after fix):
  HubsPlaybackService + MediaSessionService  →  single session owner
  Watch route                                →  VideoPlayerComponent (expanded)
  App-shell mini (hidden on /hubs/watch)     →  live <video> while docked
  Position bridge                            →  HubsCatalogService playback positions
```

Web cannot morph the same DOM video across Angular route destroy/create without a full global layer rewrite. Scoped continuity = **same content + preserved playhead** across expand/mini remounts (not identical HTMLVideoElement).

---

## Findings

### P0 — Mini was chrome-only (no film) — **fixed**

`hubs-mini-player.component.ts` showed a static thumb and toggled `playing`/`muted` state with **no AV**. Leaving watch → mini stopped audio/video cold.

**Fix:** Mini hosts a continuous `<video>` (poster floor until frames), syncs play/mute from `HubsPlaybackService`, writes `notePlaybackPosition` / `savePlaybackPosition`, resumes from catalog on mount, expands after forcing a position save.

### P1 — Shelves used video URLs as posters — **fixed**

`hubs-video-row`, hubs home continue cards, channel thumbs, watch related rail fell back to `catalog.mediaUrl(post)` inside `<img>`. That can fetch mp4s on scroll (violates 09 “posters only”).

**Fix:** `HubsCatalogService.posterUrl()` returns `thumb_url` only (rejects video extensions / JSON payloads). Call sites updated.

### P1 — Sparks exit dropped hubs exclusivity — **fixed**

Sparks `claimSparks()` overwrote media-session mode. On Sparks destroy, `releaseSparks()` → `idle` even when hubs mini still had a post → feed could autoplay beside a “live” hubs session.

**Fix:** `HubsPlaybackService.reclaimSession()`; reels `ngOnDestroy` reclaims when `hubsPlayback.isActive`. Minimize/expand also re-`claimHubs`.

### P1 — Desktop watch stage ballooned — **fixed**

`hubs-watch.page.ts` @1280px / @1600px set `--watch-player-max-h` to ~96–98vh (half+ screen), undoing the compact 16:9 prior fix. Cover fill was already correct via `object-fit: cover`.

**Fix:** Cap restored to `min(42vh, 560px)` / `min(42vh, 600px)`.

### Already good

- Home shelves / `HubsVideoRow`: image thumbs only (no in-list AV).
- Watch: early first paint, poster attr, `startTime` resume, minimize on destroy.
- Feed: `playGate` + hubs-active blocks focus autoplay (`feed.page.ts`).
- Sparks open: `hubsPlayback.setPlaying(false)` before `claimSparks()`.
- Mini hidden on `/hubs/watch` (no dual chrome).

### Residual / out of scope

- True single-element morph (iOS GlobalHubPlaybackLayer) — needs app-shell film host always mounted; not done.
- `MediaSessionService` still broadcasts `video-player-content-focus` with **post ids** while `VideoPlayerComponent` compares **player instance ids** (fragile; works via mount-after-claim ordering).
- Missing `thumb_url` → empty dark poster (server/YT synthesize is API-side; web does not invent hqdefault).
- R2 signed URL freshness on web hubs open — covered by 08 audit / playback resolver paths; not re-verified here.
- No deploy performed.

---

## Files touched

| File | Change |
|------|--------|
| `apps/web/src/app/hubs/components/hubs-mini-player.component.ts` | Live continuous mini film + position/mute sync |
| `apps/web/src/app/hubs/hubs-playback.service.ts` | Re-claim on minimize/expand; `reclaimSession()` |
| `apps/web/src/app/hubs/hubs-catalog.service.ts` | `posterUrl()` helper |
| `apps/web/src/app/components/hubs-video-row.component.ts` | Poster-only thumbs |
| `apps/web/src/app/pages/hubs.page.ts` | Poster-only thumbs |
| `apps/web/src/app/pages/hubs-channel.page.ts` | Poster-only thumbs |
| `apps/web/src/app/pages/hubs-watch.page.ts` | Poster-only related; compact stage max-h |
| `apps/web/src/app/pages/reels.page.ts` | Reclaim hubs session on Sparks destroy |

---

## Verify checklist (manual)

1. Hubs home: fling shelves → only posters, no video network thrash for thumbs.
2. Open long-form → poster then frames; scrub mid-clip.
3. Navigate away (or minimize path) → mini shows **moving** film at same playhead; play/pause/mute work.
4. Expand mini → watch resumes near same second (not 0:00).
5. With hubs mini playing, open Home feed → no second autoplay.
6. Open Sparks with hubs mini → hubs pauses; leave Sparks → hubs still owns session (paused until play).
7. Desktop ≥1280: watch stage stays compact (~42vh), cover-filled, no letterbox bars.

**Build:** `npx ng build --configuration development` succeeded after changes.  
**Deploy:** not run (per request).
