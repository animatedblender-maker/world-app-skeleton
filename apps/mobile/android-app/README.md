# Matterya — Native Android

**Pure Kotlin + Jetpack Compose.** iOS (`apps/mobile/ios/WorldApp`) is the source of truth for behavior and UI.

**Not Flutter. Not Capacitor.**

## Open

```bash
# Android Studio
open -a "Android Studio" apps/mobile/android-app

# or CLI install to emulator
cd apps/mobile/android-app
./gradlew :app:installDebug
adb shell am start -n com.matterya.matterya/.MainActivity
```

## Package

- `applicationId`: `com.matterya.matterya`
- GraphQL: `https://api.matterya.com/graphql`
- Supabase auth: same as iOS `AppConfig.swift`

## Layout (mirrors iOS)

```
app/src/main/java/com/matterya/matterya/
  config/       AppConfig
  theme/        Matterya colors / copy
  model/        CountryPost, Profile, comments…
  data/
    auth/       AuthService (Supabase)
    graphql/    GraphQlClient + GqlOps
    media/      MediaUrlResolver, VideoFrameCache
    posts/      PostsService, ProfileService
  ui/
    components/ AvatarView (hand-drawn frame), PostCard, VideoPoster
    feed/       FeedScreen + strips
    auth/       Login + profile setup
    shell/      MainShell + tab bar
  viewmodel/    AppViewModel
```

## Ported so far (parity with iOS feed path)

- Auth login / signup / session persistence
- Profile setup gate
- Home feed (`recentPosts`) with spark + hubs strips
- Hand-drawn scrapbook avatars + media frames
- Video posters via `MediaMetadataRetriever` when `thumb_url` is null
- Origin like/comment counts on spark shares
- Inline comments (merge origin thread)
- Post like toggle

## Next (same modules as iOS Views/)

Globe, Hubs continuous player, Sparks full-screen, Messages, Search, People, Create composers, Notifications.
