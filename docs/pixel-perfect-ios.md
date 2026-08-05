# Pixel-perfect iOS → Web contract

**Gold master:** `apps/mobile/ios/WorldApp` (SwiftUI).  
**Web target:** `apps/web` must match spacing, type, color, and IA from iOS `Theme.swift` + screens.

## Design tokens (locked)

From `Theme.swift` → CSS variables in `apps/web/src/styles.css`:

| Token | iOS | Web CSS |
|-------|-----|---------|
| paper/canvas | 0.973/0.965/0.949 | `--m-paper` `#f8f6f2` |
| surface | 0.996/0.992/0.984 | `--m-surface` `#fefdfb` |
| ink | 0.173/0.157/0.145 | `--m-ink` `#2c2825` |
| inkMuted | 0.580/0.545/0.510 | `--m-ink-muted` `#948b82` |
| accentBright | 0.482/0.388/0.278 | `--m-accent-bright` `#7b6347` |
| tabBarHeight | 49 | `--m-tab-bar-height` |
| pagePadding | 16 | `--m-page-padding` |
| feedGutter | 14 | `--m-feed-gutter` |
| cardRadius | 12 | `--m-card-radius` |

## Screen checklist

| Surface | iOS source | Web status |
|---------|------------|------------|
| Design tokens | Theme.swift | ✅ locked |
| Top bar | MatteryaTopBar / YouTubeAppHeader | ✅ rebuilt |
| Bottom tabs + create | BottomTabBar | ✅ 49pt height, icon sizes |
| Feed home | FeedView + FacebookPostCard | ✅ Sparks + continue + post card |
| Hubs home | YouTubeAppView | ✅ chips underline, full-width rows, seed |
| Hubs watch | YouTubeWatchView | 🟡 structure; polish ongoing |
| Mini player | YouTubeMiniPlayerBar | ✅ light surface 196×110 |
| Globe map | GlobeView | 🟡 map shell; country opens dedicated feed |
| Country feed | CountryFeedView | ✅ `/country/:code` (tabs, cards, news, sparks) |
| Messages / calls | ConversationView | ⬜ not pixel-matched |
| Profile (owner) | ProfileView | ✅ `/profile` |
| Profile (public) | PublicProfileView | ✅ `/user/:slug` |
| Messages inbox | MessagesView | ✅ paper chrome + top bar |
| Search / people | SearchView | ✅ rewritten search; people paper list |
| Sparks full-screen | ReelsVerticalFeed | 🟡 full-screen + warm progress (not full passport) |
| Create composers | Post/Reel/Story composers | ⬜ still globe-based |

## Rule

When changing web UI for a shared surface, open the matching iOS Swift file and match:

1. Vertical spacing (padding/margins)  
2. Font family (serif headlines vs system body)  
3. Icon size / weight  
4. Corner radius and 0.5px borders  
5. Interaction (what tap does)

Do not invent web-only layout for gold-master surfaces.
