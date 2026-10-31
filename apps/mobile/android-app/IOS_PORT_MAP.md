# iOS → Android 1:1 Port Status

**Source:** `apps/mobile/ios/WorldApp/WorldApp/` (148 Swift files)  
**Target:** `apps/mobile/android-app/`  
**Package:** `com.matterya.matterya`  
**Build:** green · Masquerade/Anonymous ported

## Architecture rule
iOS is source of truth. Every screen/service is ported page-by-page. **No Flutter.**

## Platform renames (intentional)
| iOS | Android |
|-----|---------|
| CallKitManager | `data/calls/TelecomCallManager.kt` |
| AppleMusicNowPlayingService | `data/media/NowPlayingService.kt` |
| VoIPPushService | FCM high-priority channel surface |

## Major surfaces

| Area | Status |
|------|--------|
| Config / Theme / Models / Markers / GraphQL | ✅ |
| Auth + PasswordPolicy + session | ✅ |
| PostsService (full ops) + MediaService + uploads | ✅ |
| AppState (~100+ methods) | ✅ |
| Feed (section order, strips, cards) | ✅ structure |
| FacebookPostCard (Spark 9:16 / Hubs 16:9 / share / follow) | ✅ structure |
| Sparks full-screen player + comments overlay | ✅ chrome |
| Hubs filters + watch 16:9 + mini player | ✅ chrome |
| Stories strip + mark viewed | ✅ |
| Notifications + Presence panels | ✅ |
| Search / People / Profile 4 tabs / Public / Edit save | ✅ |
| Settings + blocked list + push status | ✅ |
| Messages list + conversation deep chrome | ✅ |
| Country feed network tabs + composer sheet | ✅ |
| **Masquerade / Anonymous** | ✅ models + REST + store + Compose screens; AppMenu → `NavRoutes.masquerade` |
| Globe (hand-drawn disc, not MapKit/SceneKit) | ⚠️ intentional simplification |
| LiveKit video in calls | ⚠️ signaling chrome; media stub |
| Full FCM host / google-services | ⚠️ no Firebase BOM; `MatteryaFirebaseMessagingHost` + Service/Receiver no-op (reflection token probe) |

### Masquerade port map (iOS → Android)
| iOS | Android |
|-----|---------|
| `Models/AnonymousModels.swift` | `model/AnonymousModels.kt` |
| `Services/AnonymousService.swift` | `data/anonymous/AnonymousService.kt` |
| `ViewModels/AnonymousStore.swift` | `viewmodel/AnonymousStore.kt` |
| `Views/Anonymous/*` | `ui/anonymous/*` |
| Tab `.anonymous` | AppMenu → full-screen `AnonymousRootView` (Android keeps Globe tab) |

## Run
```bash
cd apps/mobile/android-app
./gradlew :app:installDebug
adb shell am start -n com.matterya.matterya/.MainActivity
```
