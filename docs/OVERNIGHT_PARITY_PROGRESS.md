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
| Masquerade / Anonymous | **missing** | page exists |
| Desktop Hubs/Sparks layouts | n/a | partial / needs Facebook-desktop treatment |
| LiveKit calls | signaling stub | livekit-client present |
| gh-pages | — | last deploy ~2026-10-16 |

## Work log
- 03:13Z First agent wave died on CLI network stream after partial work.
- Web partial landed in workspace: feed desktop rail + Sparks desktop phone-stage CSS.
- Feed rail TS/CSS completed in main session (`feed.page.ts`).
- 03:20Z+ Restarted agents (shared workspace): Android Masquerade port; Web messages/hubs + gh-pages deploy.
- Android `android-app/` is currently **untracked** in git (~225MB sources) — will commit with proper `.gitignore` (no `build/`).
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

## Remaining gaps (web)
- Messages: archive/delete swipe actions; CallKit-grade call UX polish
- Hubs: remount-free continuous player; autoplay-next related
- Anonymous: Search / Inbox shell tabs still thinner than iOS
- Feed: continue-watching strip parity with iOS HomeFeedStore
- Android Masquerade / Anonymous port still in progress (untracked `android-app/`)
