# iOS Parity Audit

## Goal

Make the native iOS app a true client for the existing web product.
The source of truth is the current web app plus its backend and GraphQL contracts.
The iOS app may change presentation to native iOS patterns, but not core behavior, data rules, routing intent, or feature semantics.

## Source Of Truth

- Web routes: `apps/web/src/app/app.routes.ts`
- Web pages:
  - `apps/web/src/app/pages/globe.page.ts`
  - `apps/web/src/app/pages/post.page.ts`
  - `apps/web/src/app/pages/profile.page.ts`
  - `apps/web/src/app/pages/me.page.ts`
  - `apps/web/src/app/pages/search.page.ts`
  - `apps/web/src/app/pages/messages.page.ts`
  - `apps/web/src/app/pages/news.page.ts`
  - `apps/web/src/app/pages/reels.page.ts`
- Web services:
  - `apps/web/src/app/core/services/posts.service.ts`
  - `apps/web/src/app/core/services/demo-dataset.service.ts`
  - `apps/web/src/app/core/services/profile.service.ts`
  - `apps/web/src/app/core/services/messages.service.ts`
  - `apps/web/src/app/core/services/follow.service.ts`
  - `apps/web/src/app/core/services/notifications.service.ts`
  - `apps/web/src/app/core/services/auth.service.ts`
  - `apps/web/src/app/core/services/gql.service.ts`
- Shared models:
  - `packages/shared/src/models/post.ts`
- GraphQL schema and implementation:
  - `apps/api/src/graphql/typeDefs.ts`
  - `apps/api/src/graphql/resolvers.ts`
  - `apps/api/src/graphql/modules/**`

## Route Model

The web app runtime routes currently are:

- `/auth`
- `/profile-setup`
- `/reset-password`
- `/me`
- `/`
- `/globe`
- `/globe-cesium`
- `/messages`
- `/search`
- `/people`
- `/ads`
- `/reels/:country`
- `/post/:id`
- `/news/:id`
- `/ops-portal-2026`
- `/admin-presence`
- `/user/:slug`

Most app routes are behind auth.
Exceptions in the route table include `/post/:id` and `/user/:slug`.

## Core Contracts

### Auth

- Supabase auth is the session authority.
- GraphQL requests include `Authorization: Bearer <token>` when a token exists.
- The web client tolerates missing tokens and still makes public GraphQL requests.
- Password reset is implemented through Supabase recovery session exchange.

### GraphQL Transport

- Web GraphQL client reads raw text first, then parses JSON.
- It surfaces:
  - network errors
  - non-JSON responses
  - HTTP failures
  - GraphQL `errors`
- iOS must preserve this strict error behavior and not silently collapse failures to empty UI states.

### Shared Post Shape

Source of truth: `packages/shared/src/models/post.ts`

Important fields:

- `media_caption`
- `shared_post_id`
- `shared_post`
- `visibility`
- `like_count`
- `comment_count`
- `view_count`
- `liked_by_me`
- `author`
- external news link fields

The native post model must remain compatible with this shape.

## Feed Contract

### Country Feed

Web source:

- `GlobePageComponent.loadPostsForCountry()`
- `PostsService.listByCountry()`
- `DemoDatasetService.listByCountry()`

Behavior:

- Web globe feed sorts final results descending by `created_at`, then by id.
- `PostsService.listByCountry()` uses `environment.useDemoDataset`.
- In production and dev envs, `useDemoDataset` is enabled.
- Web country feed merges:
  - real GraphQL `postsByCountry`
  - demo dataset posts from `DemoDatasetService`
- Merge rule in web:
  - real posts first, sorted desc
  - demo posts appended after dedupe
  - final slice capped by requested limit

### Demo Dataset Rules

Web source:

- `apps/web/src/app/core/services/demo-dataset.service.ts`

Important behavior:

- Demo posts are indexed by author profile country when available, not just raw dataset country.
- Author ids like `user_1` are normalized to padded ids like `user_000001`.
- Demo post bodies are normalized by stripping duplicated country prefixes.
- `video_captions.jsonl` is loaded and used as `media_caption`.
- Missing media URLs are hydrated from Pexels using stored `media.query`.
- Country feed ordering is balanced by author, seeded by country and a 15 minute bucket.
- Country feed uses rotating offsets so slices are not static.
- Demo likes, views, and comments are seeded with deterministic pseudo-random counts.

### Following Feed

Web source:

- `GlobePageComponent.loadFollowingFeed()`

Behavior:

- Requires auth.
- Loads `followingIds`.
- Loads posts per followed author with `limitPer = 6`.
- Merges all author lists.
- Sorts merged result descending by `created_at`.
- This feed is not tied to the current country.

## Search Contract

Web source:

- `SearchPageComponent.runSearch()`
- `PostsService.searchPosts()`
- `ProfileService.searchProfilesReal()`

Behavior:

- Country results are local name/code matches from loaded country data.
- Post search is backend-first via GraphQL `searchPosts`.
- People search is backend-first via GraphQL `searchProfiles`.
- People browse mode merges real profiles and fake profiles.
- Follow actions are available in search results.

## Profile Contract

Web source:

- `ProfilePageComponent`
- `ProfileService`
- `FollowService`
- `MessagesService.startConversation()`

Behavior:

- Profile route resolves by:
  - username
  - then current user aliases
  - then direct user id fallback
- Owner detection uses:
  - user id
  - email
  - slug aliases
- Profile page loads:
  - profile
  - follow counts
  - viewer follow status
  - profile posts
- Owner profile can auto-refresh location and update profile country/city if GPS indicates movement.
- Public profile can:
  - follow/unfollow
  - start direct conversation

## Post Detail Contract

Web source:

- `PostPageComponent`
- `PostsService.getPostById()`

Behavior:

- Supports both real and demo posts.
- Shared posts can deep-link back into the globe feed or another post context.
- Author profile navigation is available from the post screen.

## Messages Contract

Web source:

- `MessagesService`
- `MessagesPageComponent`
- backend `messages.service.ts`

Behavior:

- Conversations are auth-only.
- Messages are auth-only.
- Opening a conversation marks it read when loading without `before`.
- `startConversation` reuses an existing direct conversation if one already exists.
- Messages support:
  - text
  - optional media metadata
  - edit
  - delete
- Message notifications are generated for other members.

## Follow Contract

Web source:

- `FollowService`
- backend `follows.service.ts`

Behavior:

- Fake/demo users are not followable in the web client.
- Real users support:
  - counts
  - following ids
  - isFollowing
  - follow
  - unfollow

## Notifications Contract

Web source:

- `GlobePageComponent`
- `NotificationsService`
- `NotificationEventsService`
- backend `notifications.service.ts`

Behavior:

- Notification inbox is rendered as a globe panel, not a separate route.
- Message notifications are filtered out of the globe notification list in some flows.
- Notification unread counts are polled and updated via realtime event channels.
- Notification types include:
  - `follow`
  - `like`
  - `comment`
  - `comment_like`
  - `comment_reply`
  - `message`

## Presence Contract

Web source:

- `PresenceService`
- backend `presence.service.ts`

Behavior:

- Presence TTL defaults to 70 seconds.
- Online means `is_online=true` and `last_seen_at` within TTL.
- Heartbeat writes country/city presence from profile location, with optional ISO override.

## Current iOS Rule

No new native behavior should be added unless it is mapped to the audited web/backend contract first.
The iOS app should keep native presentation, but match:

- data source
- auth requirement
- load order
- fallback behavior
- sort order
- dedupe logic
- mutation semantics
- navigation intent

## Current iOS Gap List

Comparison target:

- `apps/mobile/ios/App/App/NativeRootView.swift`

### 1. App Route / Navigation Parity

Current iOS app has four root areas:

- home
- search
- messages
- profile

Missing or incomplete compared with web routes:

- dedicated auth route flow parity
- profile setup flow
- reset password flow
- `/me` route semantics
- people directory route
- ads route
- reels route
- post route parity as a first-class navigation surface
- news route
- admin route
- notification panel route behavior within globe

### 2. Globe / Home Experience Parity

Current iOS home is still a simplified native shell, not the full web globe behavior.

Missing or incomplete:

- left/right panel structure from web globe
- notification panel inside globe
- presence panel behavior
- search overlay behavior on globe
- floating words / sampled global firework posts behavior
- route/query-param driven globe state
- country intelligence and pulse side panels
- composer parity inside the country feed

### 3. Country Feed Parity

Partially implemented, but still not fully equivalent.

Known gaps:

- web feed uses `PostsService.listByCountry()` and then page-level sort; iOS still has its own feed repository layer and feed model
- iOS does not yet implement the full web composer flow for new posts
- iOS does not yet support the same full media selection modes from the web composer
- iOS feed cards are still custom approximations, not a full behavioral port of the web feed surface
- comment thread behavior is simpler than web threaded comments
- route/query-param focus behavior for a specific post in the country feed is missing

### 4. Search Parity

Current iOS search is a simplified merge of countries, profiles, and posts.

Missing or incomplete:

- browse people mode
- follow/unfollow actions in search results
- same result limits and mixed-mode UX behavior as web
- route-driven search state (`q`, `browse=people`)
- same empty/error/loading semantics

### 5. Profile Parity

Current iOS profile support loads profile data and posts, but does not match web profile behavior.

Missing or incomplete:

- owner/public profile route resolution semantics
- follow/unfollow UI and mutation flow
- start conversation from public profile
- owner edit profile flow
- avatar upload/edit flow
- live location refresh and profile auto-update
- profile composer/create-post flow
- profile share behavior
- profile presence/online handling

### 6. Messages Parity

Current iOS messages are closer than before, but still behind the web app.

Missing or incomplete:

- pending conversation handoff behavior from profile/news/notifications
- conversation-by-id query path
- unread count behavior
- media upload in messages
- message edit
- message delete
- notification-driven conversation open
- full member model and last-read state

### 7. Notifications Parity

Major gap.

Web behavior includes:

- notification list
- unread count
- mark read
- mark all read
- realtime insert/update events via Supabase channel
- filtering of message notifications from the globe panel
- navigation from notification to user/post/messages

Current iOS state:

- no audited notification inbox equivalent
- no unread counter
- no realtime notification event handling
- no mark-read behavior

### 8. Presence Parity

Major gap.

Web behavior includes:

- realtime presence subscription
- periodic backend heartbeat
- per-country online counts
- fake/demo online population overlay
- presence overrides
- viewing-country updates

Current iOS state:

- no equivalent presence service layer in the native app
- no heartbeat loop
- no presence overlay parity
- no online snapshot parity

### 9. Media / Upload Parity

Major gap.

Web behavior includes:

- post media upload
- ad media upload
- message media upload
- avatar upload
- signed/public avatar URL handling

Current iOS state:

- no equivalent native upload flow mapped to Supabase storage for posts/messages/avatars

### 10. News Parity

Major gap.

Web behavior includes:

- country and global conflict update feeds
- external news item detail
- comments on news items
- like/unlike on news items
- share external news into country feed

Current iOS state:

- no equivalent audited news feature flow

### 11. Reels Parity

Major gap.

Web behavior includes:

- country reels route
- country video filtering from posts
- comment interactions on reels
- scroll to pending post
- media-type inference from serialized post media

Current iOS state:

- no equivalent reels route or reel player flow

### 12. Follow Graph Parity

Partially implemented in data helpers only.

Missing or incomplete:

- follow/unfollow actions on profile
- follow/unfollow actions on search results
- follow/unfollow actions on feed cards
- follow-driven UI state synchronization across screens

### 13. Post Detail Parity

Partially implemented.

Missing or incomplete:

- full threaded comment UX parity
- notification/open-post route behavior parity
- same navigation affordances as web from post detail to search/messages/notifications/home
- shared post deep-link behavior parity

### 14. Auth Flow Parity

Current iOS app has a login sheet, but not the full web auth workflow.

Missing or incomplete:

- register flow parity
- reset password flow parity
- recovery session exchange parity
- profile-setup gating parity
- auth-route based navigation parity

