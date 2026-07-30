# World App — Native iOS

Fresh native SwiftUI iOS client for the World App monorepo, built to match the web app's behavior and contracts.

## Open in Xcode

```bash
open apps/mobile/ios/WorldApp/WorldApp.xcodeproj
# CI/Xcode Cloud may use the symlink:
# open apps/mobile/ios/WorldApp.xcodeproj
```

## Requirements

- Xcode 16+
- iOS 17+
- Apple Developer team for device builds

## Features (web parity)

| Area | Native implementation |
|------|----------------------|
| **Auth** | Supabase login/register + profile setup gate |
| **Globe** | MapKit 3D globe, country search, floating post samples |
| **Globe panels** | Notifications inbox, presence stats |
| **Country feed** | Posts / Following / Media / Stats / News tabs |
| **Composer** | Create posts with optional photo upload |
| **Reels** | Vertical video feed per country |
| **Post detail** | Full post view + threaded comments |
| **News** | ReliefWeb-style items, comments, likes, share to feed |
| **Search** | Countries, people, posts + browse people mode |
| **Follow** | Follow/unfollow on profiles and search results |
| **Messages** | Conversations, text + image media |
| **Profile** | Own profile, edit profile, avatar upload |
| **Public profiles** | View others, follow, start conversation |
| **People** | Browse directory with follow actions |
| **Ads** | View/create ad campaigns |
| **Presence** | Heartbeat loop + online/total stats |
| **Notifications** | Inbox, unread counts, mark read, navigation |
| **Demo data** | Merged into country/search feeds like web |

## Backend

- Supabase Auth: `https://bpdkltgikgbnfjswdbaj.supabase.co`
- GraphQL: `https://api.matterya.com/graphql`
- Storage buckets: `posts`, `avatars`, `messages`

## Project layout

```
WorldApp/
  Config/         Endpoints and flags
  Models/         Shared types
  Services/       Auth, GraphQL, Posts, Profile, Messages, News, Follow, etc.
  ViewModels/     AppState
  Views/          Globe, Search, Messages, Profile, Post, News, Reels, Ads, People
```

## Commands

```bash
npm run mobile:ios          # open native WorldApp.xcodeproj in Xcode
# Android (Kotlin): open apps/mobile/android-app in Android Studio
# npm run mobile:android

python3 apps/mobile/ios/generate_xcode_project.py   # after adding Swift files
```

**No Capacitor.** iOS is pure SwiftUI (`ios/WorldApp`). Do not add `@capacitor/*` packages.

## Local API

Edit `WorldApp/Config/AppConfig.swift` to point `graphqlEndpoint` at your local server.