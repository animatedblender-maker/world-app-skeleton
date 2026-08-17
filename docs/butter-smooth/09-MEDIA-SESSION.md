# Media Session contract (locked)

**Status:** Greenlit 2026-08-18  
**Branch:** `ios-native`  
**UI rule:** No visual redesign. Same cards, mini chrome, expand/minimize look.  
**After this lands:** resume butter-smooth plan at **Grafana step 3** and onward.

---

## Problem this fixes

Home feed freezes when Hubs shares appear because **multiple AV stacks** mount per cell:

- `InFrameVideoPlayer` → `VideoPlayerView` / `MatteryaHubPlayerView` on every card  
- `SparkWarmPool` creating extra `AVPlayer`s on scroll  
- `FeedVideoFocus` + continuous `GlobalHubPlaybackLayer` competing  

Butter-smooth Hubs **list** already does the right thing (`butterWarmHubCatalog` = posters only). Feed must match that model.

---

## Single owner model

```
UI cells (feed / hubs shelves)  →  POSTER only (no AVPlayer)
Focus winner OR open hubs       →  ONE MediaSession host
Hubs mini / expanded            →  GlobalHubPlaybackLayer (same continuous film)
Sparks vertical                 →  Sparks path (windowed warm OK; not feed list)
```

| Mode | Who owns AVPlayer | Feed cells |
|------|-------------------|------------|
| `idle` | none | posters |
| `feedAutoplay` | one `InFrameVideoPlayer` (focus winner only) | others poster |
| `hubsExpanded` | `GlobalHubPlaybackLayer` | no feed AV |
| `hubsMini` | `GlobalHubPlaybackLayer` | no feed AV |
| `sparks` | Sparks pager | feed not live |

**Rule:** At most **one** playing session app-wide. When `hubPlaybackPost != nil`, feed autoplay is off.

---

## Hard rules (ship gates)

1. **Feed list cells never create `AVPlayer` until they are the focus winner** (`playGate == true`).  
2. **Non-winners mount poster only** — no `VideoPlayerView`, no `MatteryaHubPlayerView`, no warm pool claim.  
3. **`SparkWarmPool` is not used on home feed scroll / warmHead / loadMore** (Sparks path may still use it).  
4. **Archive/R2 resolve** only when installing the winner player (or hubs continuous open) — not on every cell appear.  
5. **Hubs open / mini / max** use continuous layer only; frame morph, contentID-only rehost.  
6. **Scroll hot path:** thumbs + window grow; no `recordView` / engagement network mid-fling.  
7. **Look unchanged:** same frames, badges, controls when playing.

---

## Implementation map

| Phase | Code | Done when |
|-------|------|-----------|
| 0 | This doc | Signed (greenlight) |
| 1 | `InFrameVideoPlayer` mounts player **only if** `playGate` | Scroll with many hubs doesn’t hitch |
| 2 | `HomeFeedStore` thumbs-only (no warmSingle / prepareFeedWindow) | No AV storm on head/scroll |
| 3 | `shouldPlay` off when any hubs continuous active | No dual play freeze |
| 4 | Device smoke → then **Grafana step 3** | Metrics resume |

---

## Out of scope (later butter-smooth)

- Grafana dashboards / RUM (resume after media gate)  
- Full `MediaSession` type rename (behavior first; type can follow)  
- Sparks warm-pool redesign  
- Ranking / recsys changes  

---

## Verify checklist

1. Home feed: fling through hub shares → scroll stays fluid.  
2. Stop on a hub card → one autoplay, poster until frames (no black).  
3. Tap open hubs → continuous expand; mini still has chrome.  
4. Mini active → feed does not start a second player.  
5. Sparks vertical still works (separate path).  
