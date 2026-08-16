# Matterya iOS — Pre-Release Sprint Report

**Branch:** `ios-native`  
**Date:** 2026-08-17  
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
| **Mini black screen** | Higher mini z-index (65), **fill** mini frame, reassert play/audio on minimize |

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

## 4. Architecture notes for “why IG still feels lighter”

1. **Native list virtualization** — we use SwiftUI `LazyVStack` (good) but still over-warm AVPlayers on feed.  
2. **Server rank** — IG does heavy ranking server-side; we do Phase-0 client + optional rank API.  
3. **CDN edge** — media latency dominates “hubs load time”; warm pool is the right client countermeasure.  
4. **MainActor ranking** — still ranks large pools on main; post-ship: off-main compose.

None of these block a tester build; they define the next performance sprint.

---

## 5. Remaining risks (honest)

| Risk | Severity | Mitigation / next |
|------|----------|-------------------|
| No custom message `.caf` | Low | System default + chime; add branded sound later |
| Hubs endless recycle can re-show watched deep in session | Low | Expected after exhaustion |
| Feed warm may still spike memory on low devices | Med | Cap deep preroll to 2–4 after beta metrics |
| Flip camera / forward message | Low | Backlog |
| Full automated UI tests | Med | Manual QA checklist below |

---

## 6. Manual QA checklist (pre-distribute)

### Feed
- [ ] Scroll 50+ cards without long spinner
- [ ] Hubs card starts without multi-second black
- [ ] No random pause while card fully on screen
- [ ] No `sid=` text under any video
- [ ] Watched Spark does not reappear as share
- [ ] Delete post → gone on profile + after force quit

### Hubs
- [ ] Minimize → **video visible** in mini (not black)
- [ ] FS black at notch + bottom
- [ ] Swipe **up** exits FS
- [ ] Scroll comments freely; pull FS only at top
- [ ] Comment on archive/seed video → persists after leave/reopen
- [ ] Related shelf mostly unwatched first

### Messages
- [ ] Long-press: Reply, Like, React, Copy, Unsend, Remove
- [ ] Message push while background → banner + sound
- [ ] Open chat → no banner for that thread
- [ ] Audio call: mute, **speaker**, end
- [ ] Video call: mute, speaker, camera off, end
- [ ] CallKit ring uses Matterya tone

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

This is the right “last run before distribute”: correctness of engagement, unviewed discovery, messaging parity, and continuous playback are in place. The remaining items are **polish and scale** (custom message sound, camera flip, feed warm budget), not core product holes.

---

*Report generated as part of the pre-release engineering sprint. Team: Grok coding agent + parallel explore audits.*
