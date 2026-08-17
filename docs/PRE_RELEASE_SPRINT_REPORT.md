# Matterya iOS — Pre-Release Sprint Report

**Branch:** `ios-native`  
**Date:** 2026-08-17 (perf/recsys pass same day)  
**Audience:** Founder / release gate  
**Scope:** Butter-smooth functionality, messaging mastery, recsys integrity, no layout redesign  
**Commits (this sprint window):** `68bd53c` → `f895260` → `acf8532` (plus earlier feed/FS work `8e5118f`, `bf260b7`, `a23a499`, …)

---

## 1. Executive summary

This sprint treated Matterya as **one product surface** (feed, Sparks, Hubs, messages, calls, push, comments) and closed the gaps that make an app feel “almost ready” but not shippable:

| Theme | Outcome |
|--------|---------|
| **Smoothness** | Deeper feed pool, earlier prefetch, stickier autoplay, less random pause |
| **Sparks integrity** | Watched clips no longer reappear via share/original ID mismatch |
| **Hubs polish** | Mini black screen, FS edge black, FS exit direction, scroll vs FS pull |
| **Copy hygiene** | `sid=uuid…` control stamps stripped from feed/profile/chat |
| **Messaging** | Cleaner long-press menu; call UI themed + **speaker** control |
| **Push** | Message alerts keep sound; foreground chime; time-sensitive APNs |
| **Comments** | Hub/seed threads load & save on-device (were silently empty) |
| **Recsys** | Related / “More on Matterya” hard-prefer unviewed |

**Layout was not redesigned** — only behavior, routing, sanitization, audio, and engagement correctness.

---

## 2. What we shipped (by product area)

### 2.1 Home feed & performance

**Problems**
- Hubs cards cold-started (long black wait).
- Videos paused without leaving frame (focus glitch + hard silence).
- Feed hit “loading more” too early (tiny window / late prefetch).
- Watched Sparks reappeared (identity + soft recycle).

**Fixes**
- **Pool:** first window ~20, page size 40, background fill to **56+** posts.
- **Prefetch:** load-more at ~32% of pool; silent background top-up (spinner only if almost empty).
- **Warm:** head + upcoming Sparks/Hubs resolve + `SparkWarmPool`.
- **Hubs feed cards:** `loops: true`, start at 0, re-warm on focus win.
- **Focus:** longer debounce; no instant `silenceAll` when winner is briefly nil; stickier keep-visible thresholds.
- **Unviewed:** discovery keys (post + share + origin); hard drop viewed while unviewed remain; softer recycle only deep in session.

**Instagram-class approach (what we aligned to)**
| Layer | Industry pattern | Matterya now |
|--------|------------------|--------------|
| Client | Always-ahead cursor + local window | `HomeFeedStore` buffer + window grow |
| Media | Warm N ahead AVPlayers | `SparkWarmPool` + archive resolve |
| Solo audio | One audible player | `MediaPlaybackCoordinator` + continuous protect |
| Ranking | Unviewed / relationship first | Phase-0 `sessionHomeFeedOrder` + `FeedCompositionEngine` |
| Backend (later) | Rank service + feature store | `RecommendationClient` + warehouse tables exist; not blocking ship |

**Still heavier than IG** if we over-warm (32 deep players). Next optimization (post-ship OK): feed deep-preroll 2–4 only; keep Sparks player at 8–14.

---

### 2.2 Hubs continuous player

| Issue | Fix |
|--------|-----|
| FS double-enter / rebuffer | In-place `fsProgress` morph — same AVPlayer |
| White notch / bottom in FS | Edge-to-edge black + hide tab bar |
| FS exit felt wrong | **Swipe up** exits (not down) |
| Meta pull blocked comments scroll | FS pull only when scroll is **at top** |
| **Mini black screen** | Higher mini z-index (65), **fill** mini frame, reassert play/audio; **dock film to measured mini hole** (`adb9c1d` — floating bar was ignored → black ink bed) |

---

### 2.3 Copy / “sid blabla” stamps

**Cause:** `__hub_origin__|sid=…|aid=…` stripped prefix but left control payload; some UI used raw `post.body`.

**Fix**
- Stronger `ContentSanitizer` (control lines, `sid=` regex, multi-key stamps).
- `displayBody` / `displayExcerpt` / `displayHeadline` gates.
- `PostCardView`, `ProfilePostCard`, chat share headlines use sanitized fields.

---

### 2.4 Messaging (chat)

| Area | Status after sprint |
|------|---------------------|
| Bubbles | Theme paper / `accentBright` mine / surface peer |
| Swipe reply | Unchanged (works) |
| **Long-press menu** | **Reply, Like, React, Copy, Unsend, Remove** (was react-only + destructive) |
| Share cards in chat | Sanitized headlines (no sid stamps) |
| Read label | Last-read “Read · time” (not double-check ticks — acceptable v1) |

**Not in this sprint (documented for next):** forward, multi-select delete, edit message, delivery ticks.

---

### 2.5 Calls

| Control | Before | After |
|---------|--------|--------|
| Accept / Decline / End | ✅ | ✅ |
| Mute | ✅ | ✅ |
| Camera on/off (video) | ✅ | ✅ |
| **Speaker / earpiece** | ❌ | ✅ `toggleSpeaker` + UI button |
| Theme | Hardcoded blue-black | Matterya **ink / canvasDeep / accent** gradient |
| CallKit ring | `MatteryaCall.caf` | unchanged |
| In-app ring | `MatteryaCallRing.mp3` | unchanged |

**Not yet:** flip camera, hold/merge, multi-party.

---

### 2.6 Push notifications

| Type | Sound | Behavior |
|------|--------|----------|
| **Message** (background) | APNs `sound: default` + time-sensitive | Banner when not in that chat |
| **Message** (foreground) | System chime `1003` + banner/sound | Suppressed if chat open |
| **Call** (VoIP / CallKit) | Custom `MatteryaCall.caf` | Full ring path |
| **Call** (in-app) | `MatteryaCallRing.mp3` | Foreground |

**WhatsApp parity note:** custom message `.caf` not bundled yet; system default + foreground chime is shippable. Optional next: `MatteryaMessage.caf` in bundle + APNs `sound` name.

---

### 2.7 Comments

**Critical bug fixed:** Hub/seed posts (`ia_*`, non-UUID, etc.) always hit GraphQL → empty success → comments vanished after leave.

**Now**
- `listComments` / `addComment` / `likeComment` short-circuit **`HubEngagementStore`** for local-engagement IDs.
- Origin + share merge still works for hybrid cases.
- GraphQL failure falls back to local so Hubs never “silent fail.”

Feed expand + Hubs watch use the same `PostsService` path → both benefit.

---

### 2.8 Recsys / “will users see new content?”

| Surface | Unviewed-first? | Notes |
|---------|-----------------|--------|
| **Home feed** | ✅ Hard | Discovery keys; composition drops viewed while unviewed remain |
| **Sparks player** | ✅ Hard | mark watched on page; queue excludes viewed |
| **Hubs For you shelves** | ✅ Prefer (per slug) | Viewed demoted; deep endless can recycle (by design when exhausted) |
| **More on Matterya (related)** | ✅ Harder now | Pass 1 unviewed-only across tiers; seen only if shelf empty |

**Answer for release:** Yes — users should consistently get **new Sparks/feed items** until the unviewed library is exhausted; related shelf prefers unwatched long-form first.

---

## 3. Tab-by-tab readiness (functionality)

| Tab | Expectation | Gate |
|-----|-------------|------|
| **Feed** | Endless, following-priority mix, hubs/sparks autoplay sticky, no sid text, delete sticks | Ready to QA |
| **Hubs** | Continuous watch → mini (video visible) → FS black edges; related unviewed; comments local | Ready to QA |
| **Messages** | Chat menu complete enough; push sound; calls mute/speaker/camera/end | Ready to QA |
| **Profile** | Delete sync via tombstone; excerpts sanitized | Ready to QA |
| **Globe** | Untouched this sprint (no layout change) | Smoke only |
| **Sparks** | Unviewed queue + mark all identities | Ready to QA |

---

## 4. Architecture notes — **shipped performance sprint** (IG-class)

| Layer | Was | Now (this pass) |
|--------|-----|-----------------|
| **Native list virtualization** | LazyVStack + over-warm 8–32 AVPlayers | LazyVStack + **device-tier warm**: feed deep preroll **2–4**, max slots 8/14/18, light outer ring |
| **Server rank** | Optional soft re-order | **Required soft path**: home + Sparks call `POST /v1/recommendation/rank` (`server.v2` + 20s cache) |
| **CDN edge** | Client warm pool only | **`POST /v1/playback/batch`** freshen + ranged GET edge warm for feed head |
| **MainActor ranking** | Full compose on main | **`rankForSessionAsync`** → `Task.detached` compose; applyPosts skips double-rank |

### 4.1 Device media budget (`SparkWarmPool.MediaBudget`)

| RAM | Deep preroll (feed) | Deep (Sparks) | Max parked slots | Player ahead (feed) |
|-----|---------------------|---------------|------------------|---------------------|
| &lt; ~3.5 GB | 2 | 3 | 8 | 3 |
| &lt; ~5.5 GB | 3 | 5 | 14 | 5 |
| Higher | 4 | 6 | 18 | 6 |

Fling: thumbs only (no deep AV warm). Focus win: deep-preroll **that card only**.

### 4.2 Backend contracts

| Endpoint | Role |
|----------|------|
| `POST /v1/recommendation/rank` | Multi-source score + diversity; **v2** weights + short TTL cache |
| `POST /v1/playback/batch` | Up to 12 post IDs → live play URLs for CDN edge warm |
| `POST /v1/recommendation/refresh-item-stats` | Cron item quality (unchanged) |

Client still paints **first** from Phase-0 local order; server re-order never blocks open.

---

## 5. Remaining risks (honest) — status after performance pass

| Risk | Severity | Status / mitigation |
|------|----------|---------------------|
| No custom message `.caf` | Low | **Accepted for ship** — APNs `default` + foreground chime `1003`. Backlog: `MatteryaMessage.caf` |
| Hubs endless recycle can re-show watched deep in session | Low | **By design** after unviewed exhaustion; discovery still demotes viewed first |
| Feed warm memory on low devices | Med → **Low** | **Mitigated**: deep preroll capped 2–4 by RAM tier; max slots 8 on constrained |
| Flip camera / forward message | Low | **Backlog** — not release-blocking |
| Full automated UI tests | Med | **Manual QA checklist below** remains gate; XCUITest suite still backlog |

---

## 6. Manual QA checklist (pre-distribute)

### Feed
- [ ] Scroll 50+ cards without long spinner
- [ ] Hubs card starts without multi-second black (poster while buffering)
- [ ] Hubs **controls only after tap** (not while scrolling)
- [ ] No random pause while card fully on screen
- [ ] No `sid=` text under any video
- [ ] Watched Spark does not reappear as share
- [ ] Delete post → gone on profile + after force quit
- [ ] Low-memory device (or sim): no jetsam after 2 min aggressive scroll
- [ ] Memory: deep warm only next 2–4 videos (Instruments optional)

### Hubs
- [ ] Minimize → **video visible** in mini (not black)
- [ ] FS black at notch + bottom
- [ ] Swipe **up** exits FS
- [ ] Scroll comments freely; pull FS only at top
- [ ] Comment on archive/seed video → persists after leave/reopen
- [ ] Related shelf mostly unwatched first

### Messages
- [ ] Conversations list paints **instantly** (cache) then soft-refreshes
- [ ] Long-press: Reply, Like, React, Copy, Unsend, Remove
- [ ] Message push while background → banner + sound (system default OK)
- [ ] Open chat → no banner for that thread
- [ ] Audio call: mute, **speaker**, end
- [ ] Video call: mute, speaker, camera off, end
- [ ] Hangup / no-answer → **call log appears immediately** in thread + inbox preview
- [ ] CallKit ring uses Matterya tone
- [ ] Spark share open → endless swipe queue (not single clip)

### Sparks
- [ ] Swipe past 20 → no recent watched repeats
- [ ] Open from feed share → marks both identities

---

## 7. Commits reference

| Commit | Focus |
|--------|--------|
| `8e5118f` | Feed ahead-buffer + stickier hubs autoplay |
| `68bd53c` | Hard unviewed Sparks (origin+share keys) |
| `a23a499` / `bf260b7` / `c1eabe1` | FS scroll gate, swipe-up exit, black edges |
| `f895260` | Sid kill, mini paint, chat/call/push polish |
| `acf8532` | Hubs comments local path |
| `9590479` | This sprint report |
| *(follow-up)* | Mini docks to floating hole; API/model strip hub `sid=`; chat title sanitized |

---

## 8. Recommendation

**Ship a TestFlight / internal distribute build from `ios-native` HEAD after the QA checklist.**  

Correctness (engagement, unviewed, messaging, continuous playback) plus **IG-class performance controls** (memory-capped warm, off-main compose, server rank v2, CDN batch warm) are in place.

**Still backlog (not blocking):** branded message `.caf`, flip camera, forward message, XCUITest suite.

### Deploy notes (API)
1. Deploy `apps/api` with `server.v2` rank + `POST /v1/playback/batch`.
2. Confirm `POST /v1/recommendation/rank` returns `policyVersion: "server.v2"`.
3. Optional: cron `POST /v1/recommendation/refresh-item-stats` for quality scores.

---

*Report generated as part of the pre-release engineering sprint. Team: Grok coding agent + performance / recsys pass.*
