# Hubs A→Z audit (2026-08-17)

## Executive summary

**P0 root cause of “Hubs videos take years / never play”:**  
Shelf + playback APIs returned **public `pub-*.r2.dev` URLs that HTTP 403**.  
The stack treated those as “always valid” and **never re-presigned**, so AVPlayer hung on dead links.

Secondary issues (P1): missing `thumb_url` on thin cards (empty list posters until YT extract),  
token refresh on hot paths, continuous player rehost during morph (fixed earlier).

---

## Flow (end-to-end)

```
Hubs tab open
  → paintInstantHubsIfPossible (cache)
  → SlugShelfStore.loadForYou / loadShelf
       GET /v1/hubs/for-you | /v1/hubs/shelves/:slug   (~200–450ms API — OK)
  → mapThinCard → CountryPost (media_url JSON, thumb often null)
  → list thumbs (posterURL → YT hqdefault from LongForm path)
  → open video
       startHubPlayback → GlobalHubPlaybackLayer (continuous AV)
       Archive / VideoPlayer → play URL
            ❌ was: public r2.dev (403)
            ✅ now: freshened signed GET from API / R2PlaybackResolver
  → minimize/maximize → frame morph, no rehost (contentID only)
```

---

## What works

| Area | Status |
|------|--------|
| Slug shelf API latency | Good (~0.2–0.4s unauthenticated probe) |
| Thin card shape (id, media JSON, author) | Good |
| iOS slug-first load (no fat GraphQL first paint) | Good |
| Continuous single player identity | Good (post-ce86ade) |
| Mini chrome on film | Good (post-088480a) |
| NaN Int crash guards | Good (post-413bf5c) |
| YouTube poster derivation from LongForm path | Works on client; server now also fills thumb_url |

---

## P0 — Empty chip shelves when `hub_slug` column empty (fixed this commit)

If migration applied but nothing writes `posts.hub_slug`, SQL filter
`hub_slug = :slug` returns **zero rows** for every chip. iOS shows empty shelves.

**Fix:** shelf page falls back to unfiltered + classify when SQL path is empty.
Also hubs SQL prefers `media_type = video` (not reel/spark).

---

## P0 — Broken play URLs (fixed this commit)

### Evidence
```
GET for-you item media_url → https://pub-….r2.dev/LongForm/.../video.mp4
HEAD/RANGE that URL → HTTP 403 Forbidden
GET /v1/playback/:id → same 403 public URL (no re-presign)
```

### Why
1. `R2_PUBLIC_BASE_URL` set to public r2.dev host that is **not world-readable**.
2. `presignGet()` short-circuited to public base (never signed).
3. `existingPlayUrlStillFresh()` treated unsigned r2.dev as “always fine”.
4. Shelf cards served raw DB `media_url` without freshen.
5. iOS `playbackConfiguration` played plain r2.dev without calling `/v1/playback`.

### Fix (this commit)
| Layer | Change |
|-------|--------|
| API `r2.ts` | `presignGet` **always** mints real signed GET |
| API `r2-playback.ts` | Prefer real presign; unsigned r2.dev is **not** fresh |
| API `shelf.service.ts` | Freshen each card’s media_url; synthesize YT thumbs |
| iOS `MediaURLResolver` | R2 + postID → live resolve before play |
| iOS `ArchiveVideoPlayback` | R2 → `R2PlaybackResolver` before install |
| iOS `R2PlaybackResolver` | Cached token only (no ensureValidToken stall) |

### Ops note
- After deploy, verify:  
  `curl -sS https://api.matterya.com/v1/playback/<uuid> | jq .url`  
  URL should contain `X-Amz-Signature` (or a working custom CDN), **not** a 403 r2.dev.
- Optional: set `R2_FORCE_PUBLIC=1` only if public base is proven 200.
- Optional long-term: fix bucket public ACL or point `R2_PUBLIC_BASE_URL` at a working custom domain.

---

## P1 — Slow / fragile (partially fixed)

| Issue | Severity | Status |
|-------|----------|--------|
| Null `thumb_url` on shelves | P1 | Fixed server-side synthesize + client YT path |
| `ensureValidToken` on shelf/surface fetch | P1 | SlugShelf uses cached token; SurfacePageClient still refreshes |
| Continuous morph rehost | P1 | Fixed earlier (contentID-only rehost) |
| Mini below tab bar (safe area) | P1 | Fixed earlier (safe bottom in miniFrame) |
| Feed shared hubs open lag | P1 | Fixed earlier (instant startHubPlayback + edge warm) |
| playback/batch requires auth | P2 | Warm fails silently when logged out |
| Shelf over-fetch when no hub_slug column | P2 | SQL scan up to 8 batches — monitor |

---

## P2 — Follow-ups

1. **SurfacePageClient** — same cached-token pattern as SlugShelfStore.
2. **playback/batch** — allow public posts without auth for edge warm.
3. **Hub_slug migration** — ensure column + backfill so shelf SQL filters (no classify scan).
4. **Grafana** — still Step 3 dashboard when app stable.
5. **Metrics** — `hubs_open_to_first_frame`, `shelf_page_ms` once play works.

---

## Verify checklist (device)

1. Hubs For you: posters visible (not empty film wall).
2. Open video: first frame &lt; ~1–2s on good network (not infinite spinner).
3. Mini: sits above tab bar; play continues through minimize/maximize.
4. Feed shared Hubs: autoplay + tap open continuous player.
5. API: playback URL is signed and Range-GET returns 206.

---

## Commits related

- `ce86ade` — slug speed, mini dock, morph
- `05c09f2` — feed shared hubs warm/open
- **this** — R2 403 root cause + thumbs + live shelf media
