# Overnight Android + Web parity progress

**Started:** 2026-10-31 (session)  
**Rules:** Do not touch iOS. One backend (`api.matterya.com`). Match iOS behavior/API; adapt layouts for web desktop. Kotlin Compose Android. Deploy web → `gh-pages`. Android buildable for simulator tomorrow.

**User check-in:** say `continue` or `how far are we now?`

## Locked decisions
- Full feature parity Android + Web (no “thin slice”)
- Ambiguity → match iOS; layout-only differences on web/desktop
- Mature Masquerade policy / separate mod queue = parked (moderation ops), not blocking client UIs
- No Play Store submit tonight

## Current baseline (pre-work)
| Surface | Android | Web |
|---------|---------|-----|
| Auth / profile setup / feed | present | present |
| Hubs / Sparks / Messages / Globe / Search / People / Profile | present (chrome+) | present (Hubs strong) |
| Masquerade / Anonymous | **ported** (Compose; AppMenu entry; assembleDebug green) | page exists |
| Desktop Hubs/Sparks layouts | n/a | partial / needs Facebook-desktop treatment |
| LiveKit calls | signaling stub | livekit-client present |
| gh-pages | — | last deploy ~2026-10-16 |

## Work log
- 03:13Z First agent wave died on CLI network stream after partial work.
- Web partial landed in workspace: feed desktop rail + Sparks desktop phone-stage CSS.
- Feed rail TS/CSS completed in main session (`feed.page.ts`).
- 03:20Z+ Restarted agents (shared workspace): Android Masquerade port; Web messages/hubs + gh-pages deploy.
- Android `android-app/` was untracked — Masquerade port + `.gitignore` landing in this commit (no `build/`).
- **Android Masquerade port:** `AnonymousModels` / `AnonymousService` (`api.matterya.com/v1/anonymous`) / `AnonymousStore` / `ui/anonymous/*` (Root, AgeGate, UsernameClaim, WelcomeLetter, Onboarding, Feed, Spaces, SpaceDetail, PostDetail, Composer, Search, Inbox, Me, PublicProfile, CreateSpace). Entry: AppMenu → `NavRoutes.masquerade`. `./gradlew :app:assembleDebug` **BUILD SUCCESSFUL**.
- **03:31Z Web wave (this session):**
  - **Feed** desktop right rail (≥1280px): Sparks / People / Explore companion column.
  - **Sparks** desktop phone-stage (≥900px): centered 9:16 stage + side comments pane.
  - **Messages** desktop list+thread side-by-side (≥900px); mobile stays stacked. Added iOS Primary/Requests inbox + accept/decline mutations.
  - **Hubs watch** related column hardened (sticky solid rail, dedupe, prefetch pages).
  - **/anonymous** age gate verified: `unauthenticated` → sign-in; `under_18` / `missing_birthdate` / `need_attest` / `need_username` phases; API smoke returns 401 unauthenticated without JWT.
  - Production `ng build` clean. Deploy via `npm run deploy:gh-pages` (gh-pages only).
  - **Deploy SUCCESS:** gh-pages `953cb72` → https://matterya.com (CDN may lag). Source commit `aed6b14f` on `ios-native`.
- Say `how far are we now?` or `continue` anytime.

## Web desktop parity shipped tonight
| Surface | Breakpoint | Behavior |
|---------|------------|----------|
| Home feed | ≥1280px | Center column + right rail |
| Sparks | ≥900px | Phone-sized stage; comments as side pane |
| Messages | ≥900px | List \| thread; &lt;900 stacked like iOS |
| Hubs watch | ≥900px | Player + sticky “More on Hubs” related |


- **13:27Z:** Web Home feed **Continue watching** strip (iOS FeedView parity) — Hubs history/in-progress via HubsCatalogService; 16:9 rail + progress; opens `/hubs/watch/:id`.


- **13:40Z:** Messages archive/delete + Hubs watch autoplay-next already in `5f79fe57`. Android Masquerade media zoom `f5798cf3`. Redeployed gh-pages after continue-watching.

## Remaining gaps (web)
- Messages: CallKit-grade call UX polish
- Hubs: remount-free continuous mini player (watch up-next shipped)
- Anonymous: Search profile deep-link / in-shell chat thread (Inbox now lists DMs + alerts)
- Feed: continue-watching strip — **shipped 13:27Z**
- Android Masquerade: mod panel polish (media zoom/video + DM threads wired)

- **13:24Z Wave (scheduler):**
  - No Android/web worktrees to merge (only iOS wt: feed-home-butter, freeze-cold-open, names-r2 — left alone).
  - **Android Masquerade DMs:** `MessagesService.listConversations(inbox=masquerade)` + surface filter; Inbox tab = official Matterya threads; `ConversationRouteView` opens inside Masquerade; `refreshMasqueradeMessageUnread` for badge. `./gradlew :app:assembleDebug` **BUILD SUCCESSFUL**. APK: `apps/mobile/android-app/app/build/outputs/apk/debug/app-debug.apk` (~25MB).
  - **Web Anonymous:** Search + Inbox shell tabs (people/spaces/posts search; Masquerade DMs + alerts split ≥900px). People page desktop 2/3-col grid. `ng build` clean.
  - **Deploy SUCCESS:** gh-pages `30e7daf` → https://matterya.com (CDN may lag).

- **Overnight wave — Android Masquerade media polish (no iOS edits):**
  - Images: `FeedPinchZoomPhoto` (in-card pinch, resets on release) + tap → `MatteryaPhotoLightbox` (fullscreen pinch/pan, double-tap, drag-down dismiss).
  - Videos: feed/space/profile → `MasqueradeVideoPoster` → fullscreen `MasqueradeVideoPlayerCover` (ExoPlayer/`VideoPlayerView`); post detail `AnonymousPostCardStyle.Thread` → `MasqueradeInFrameVideo` (in-frame controls + fullscreen).
  - Wired in `AnonymousComponents` media block; `AnonymousPostDetailView` uses Thread style.
  - `./gradlew :app:assembleDebug` **BUILD SUCCESSFUL**. APK: `apps/mobile/android-app/app/build/outputs/apk/debug/app-debug.apk`.

- **13:30Z Wave (web parity):**
  - **Messages archive/delete:** GraphQL `archiveConversation` / `deleteConversation` on web `MessagesService` (same iOS mutations). Primary inbox: explicit Archive + Delete buttons (desktop + mobile); mobile swipe-left reveals Archive/Delete. Optimistic remove + local hidden-id fallback (iOS `ConversationInboxStore`). Requests keep Accept/Delete.
  - **Hubs watch up-next:** `video-player` emits `ended`; watch page autoplays first `related[]` item via same-route navigate (component reused; player `src` updates in place). Near-end timeupdate fallback for flaky R2/HLS end events.
  - `ng build --configuration production` clean. Deploy via `npm run deploy:gh-pages`.
