# Home Feed butter-smooth audit (web)

**Repo:** `/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton`  
**Gold master:** `docs/butter-smooth/09-MEDIA-SESSION.md`  
**Scope:** `apps/web` Home Feed vs iOS media-session contract  
**Date:** 2026-10-16  
**Deploy:** not done (audit + scoped edits only)

---

## Contract (must match iOS)

| Rule | Web status after this pass |
|------|----------------------------|
| Feed LIST cells = posters only (no AV until focus winner) | **Fixed** — `playGate` mounts `<app-video-player>` only for `focusPostId` |
| At most ONE playing session app-wide | **Wired** — `MediaSessionService` + hubs claim/release |
| Sparks stay on Home as tall reel cards; Moments excluded | **OK** — Moments filtered; Sparks kept |
| Scroll hot path: thumbs/Frame0 only; no network storms mid-fling | **Fixed** — open-path AV freshen removed; Frame0 prefetch; quality HEAD deferred |
| Focus winner may autoplay; non-winners stay poster | **Fixed** — IntersectionObserver focus pick + poster floor |

---

## 1. Current bugs / jank sources (file:line)

### Critical (were shipping jank)

| Issue | Location | Why it hurts |
|-------|----------|--------------|
| ~~Every video card mounted `<video>` with src~~ | Was `matterya-post-card` always mounting player | Multiple HTMLMediaElements + metadata fetches mid-fling |
| Open path awaited `freshenPosts(feed, 12)` before paint | Was `feed.page.ts` refresh | Up to 12 `/v1/playback` calls blocked first paint |
| Open path awaited profile + `listFollowingIds` before thin feed | Was `feed.page.ts` refresh | Extra RTT before `/v1/feed` |
| Poster floor fell back to `mediaSrc` (often mp4/JSON) | Was `matterya-post-card` poster template | `<img src=video>` / broken thumbs |
| Sparks strip used `thumb_url \|\| media_url` | `sparks-strip.component.ts:115–117` (old) | Video/JSON as strip tile → empty/black tiles |
| Quality ladder probed HEAD/Range on every player mount | `video-player.component.ts` `rebuildQualityOptions` | Archive CDN storm when hubs card became focus |
| `MediaSessionService` existed but was unwired from feed cards | `media-session.service.ts` | Dual-play risk vs hubs mini |
| No Frame0 poster path on web | missing service | R2 Sparks without `thumb_url` stayed black until AV |

### Remaining / follow-ups (not fully closed)

| Issue | Location | Notes |
|-------|----------|-------|
| Country / profile feeds still mount players without focus gate | `country-feed.page.ts`, `owner-profile.page.ts`, `public-profile.page.ts` | Same card component defaults `playGate=false` → posters forever unless parent wires focus (safer than AV storm; no autoplay there yet) |
| `video-player` still autoplays any intersecting mount at threshold `0.12` | `video-player.component.ts:1339–1361` | Acceptable once only the winner mounts; raise threshold if dual-mount returns |
| Frame0 `/v1/poster/batch` SQL is `uuid[]` | API `poster-route.ts` | Non-uuid spark ids may 404; singles/fallback still OK |
| Open path still no disk-cache instant paint | `feed.page.ts` | iOS paints cache first; web waits on thin `/v1/feed` |
| Hubs mini bar itself has no continuous `<video>` | `hubs-mini-player.component.ts` | Session claim is wired; continuous film layer parity is separate |

### Already correct / good

- `surface-page.service.ts` — thin `/v1/feed` + `/v1/sparks` mapping matches iOS SurfacePageClient.
- Moments excluded; Sparks kept on Home (`feed.page.ts` filters).
- `HubsPlaybackService.start/stop` claims/releases hubs on `MediaSessionService`.
- Reels page already imports `MediaSessionService`.

---

## 2. Exact code changes (posters-first + IntersectionObserver focus autoplay)

### Architecture

```
feed.page (IO on .feed-card-slot[data-has-video])
  → pick highest intersectionRatio near viewport center
  → MediaSessionService.claimFeed(id, score)
  → [playGate]="focusPostId === post.id"
matterya-post-card
  → playGate false → poster floor (thumb / Frame0) only
  → playGate true  → mount ONE <app-video-player preload=metadata>
  → setFocus freshenPosts([winner], 1) only
```

### Files touched this pass

1. **`apps/web/src/app/core/services/frame0-poster.service.ts`** (new)  
   - Cache + `GET /v1/poster/:id` + `POST /v1/poster/batch`  
   - Image warm after batch  
   - Sync `url(id)` for first paint

2. **`apps/web/src/app/core/services/media-session.service.ts`**  
   - Added `feedScore` + score-aware `claimFeed(postId, score)` so fling prefers the more-visible card

3. **`apps/web/src/app/pages/feed.page.ts`**  
   - Focus IO: `rootMargin: '-28% 0px -28% 0px'`, thresholds `[0,0.15,0.35,0.55,0.75,1]`  
   - Mount AV only for `focusPostId`  
   - Clear focus when hubs owns session  
   - **Paint thin feed before any playback freshen**  
   - `warmPostersAfterPaint()` → Frame0 prefetch (rail + first 24 videos)  
   - Winner-only `freshenPosts([post], 1)` in `setFocus`  
   - Profile/following off critical path  
   - Secondary sparks top-up: posters only (no batch playback freshen)

4. **`apps/web/src/app/components/matterya-post-card.component.ts`**  
   - `@Input() playGate` + poster floor template  
   - Poster = image `thumb_url` → Frame0 cache/resolve (never video URL)  
   - Winner player uses `preload='metadata'` (not `auto`)  
   - `requestPlay` for tap-to-claim when not auto-focused

5. **`apps/web/src/app/components/sparks-strip.component.ts`**  
   - Image thumb only; Frame0 fallback; prefetch on posts change

6. **`apps/web/src/app/components/video-player.component.ts`**  
   - Defer `pruneUnreachableQualities()` until quality menu opens

7. **`apps/web/src/app/hubs/hubs-playback.service.ts`** (already)  
   - `claimHubs` / `releaseHubs` on start/stop

### Recommended follow-up edits (not done)

- Port the same focus IO wrapper to `country-feed.page.ts` if country Home should autoplay.
- Optional: localStorage / IndexedDB disk paint for Home (iOS cache-first).
- Optional: raise in-player IO threshold to `~0.55` when used under feed playGate.

---

## 3. Prefetch strategy (posters/playback — no AV storm)

| Phase | What | Cap | Must not |
|-------|------|-----|----------|
| Open critical path | `GET /v1/feed?limit≈36` | 1 request | await following, Frame0, playback, GraphQL |
| After first paint | `POST /v1/poster/batch` for rail + first ~24 video ids | chunks of 24 | create `<video>`, call `/v1/playback` for all |
| Scroll / focus | Frame0 already cached; winner gets `freshenPosts([id],1)` | 1 playback resolve | warm all visible cells |
| Secondary | country posts + `/v1/sparks` for rail | best-effort | block spinner; batch-freshen 12 play URLs |
| Sparks vertical (out of Home list) | existing reels windowed path | separate | use feed list warm |

**Hard rule:** Home list scroll = thumbs + Frame0 only. Archive/R2 play URL resolve only when installing the focus winner (or hubs/sparks open).

---

## 4. Acceptance checks

### Device / browser smoke (Home)

1. **Fling through many Sparks/Hubs cards** — scroll stays fluid; DevTools Network shows no cascade of `.mp4` Range GETs while flinging.  
2. **Stop on a video/Spark card** — exactly one `<video>` in DOM for feed; poster visible until frames; autoplay muted/policy-ok.  
3. **Leave the winner** — previous player unmounts (poster returns); no dual audio.  
4. **Sparks for you strip** — tiles show Frame0/thumb images, not black boxes from mp4 `src`.  
5. **Tap poster play on a hubs long-form card** — either claims feed focus or navigates watch; if hubs mini/expanded active, feed does not start a second player.  
6. **Open Hubs watch / mini** — feed focus clears; cards stay posters.  
7. **Moments** — never appear on Home.  
8. **Open path timing** — first content (posters) after thin `/v1/feed` without waiting for 12× `/v1/playback`.

### DevTools checks

- While flinging: filter `playback` / `.mp4` — should be quiet.  
- On settle: at most one feed `video` element with `src` set.  
- After paint: `/v1/poster/batch` (or singles) OK; not required for paint.

### Build

- `npx ng build --configuration development` — **passed** after these edits.

---

## Edits summary (this session)

Implemented / tightened the focus-gate and poster-first path:

- New `Frame0PosterService` for `/v1/poster` (+ batch).
- Score-aware `MediaSessionService.claimFeed`.
- Home feed: IntersectionObserver focus winner, playGate mount, deferred AV freshen, Frame0 warm after paint, profile/following off critical path.
- Post card: poster floor without video URL fallback; Frame0 resolve; `preload=metadata`.
- Sparks strip: image/Frame0 only.
- Video player: lazy quality URL probing.

**Not deployed.**
