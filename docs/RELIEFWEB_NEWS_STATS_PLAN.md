# ReliefWeb News Plan For Stats Tab

Prepared on April 1, 2026 for the current `world-app-skeleton` codebase.

## Goal

Add a legal, country-scoped "conflict / crisis updates" module to the existing `stats` tab so users can:

- browse current country updates
- comment on those updates inside World App
- share an update into their country feed as a normal post

The recommended source is the official ReliefWeb API:

- API docs: https://apidoc.reliefweb.int/endpoints
- ReliefWeb content types include `reports` and `disasters`
- The docs describe `reports` as updates and analysis curated from more than 4,000 sources
- The docs also state that, unless otherwise noted, content on the documentation site is CC BY 4.0, but the platform links to ReliefWeb terms and underlying source rights still matter

Important product rule:

- We should treat ReliefWeb as a metadata and outbound-link source
- We should not mirror full article bodies from third-party publishers into our feed
- We should show source attribution and link users out to the original ReliefWeb/source page

## Why This Fits The Existing App

This app already has the right product surfaces:

- the `stats` tab already exists in [`apps/web/src/app/pages/globe.page.ts`](/Users/animated/World_App/world-app-skeleton/apps/web/src/app/pages/globe.page.ts)
- the stats tab already shows global/local info plus `globalMood` and `countryMood`
- the app already supports:
  - post creation
  - comments on posts
  - sharing posts into country feeds
  - notifications
  - admin/daily insights tooling

So the clean extension is:

- keep external news in a dedicated data model
- render it inside the stats tab
- allow users to comment on news items directly
- allow users to share a news item into the social feed as a link-style post

## Recommended Product Behavior

### In the stats tab

Under the existing Global / Local / Mood cards, add:

- `Conflict updates` card when a country is selected
- `Global crisis updates` card when no country is selected

Each update card should show:

- headline/title
- source name
- published date
- country tags
- disaster/conflict tag badges
- button: `Open source`
- button: `Comment`
- button: `Share to country`

### Comment behavior

Comments should belong to the external news item, not to a hidden synthetic post.

Reason:

- comments are clearly about the external article/update
- we avoid polluting the country feed with system-created pseudo-posts
- we keep the feed reserved for user-authored or user-shared content

### Share behavior

When a user taps `Share to country`, create a normal app post that references the news item as a link card.

That post should:

- be authored by the user
- default to `visibility = 'country'`
- optionally allow the user to add a short caption later
- display a compact preview of the linked news item in the feed

This is the best match for the current `sharePostToCountry()` pattern already used for internal post sharing in [`apps/web/src/app/pages/globe.page.ts`](/Users/animated/World_App/world-app-skeleton/apps/web/src/app/pages/globe.page.ts).

## Legal Guardrails

### Safe usage model

Store and display only:

- ReliefWeb item ID
- title
- canonical ReliefWeb URL
- original source name
- published date
- country metadata
- format/type/tags
- optional thumbnail only if clearly provided by ReliefWeb for reuse
- a very short snippet only if we intentionally approve it after reviewing rights implications

Do not ingest or republish by default:

- full article body
- full ReliefWeb body HTML
- original publisher images unless rights are clear
- downloadable attachments

### UI copy

Add a visible note in the news card or details drawer:

- `Source-linked update via ReliefWeb`

And in the outbound link area:

- `Open on ReliefWeb`

### Product-policy rule

Comments and shares are user-generated content about the linked item.
The app is not claiming ownership over the source article itself.

## Recommended Data Model

Use two new external-news tables plus small additions to posts.

### 1. `external_news_items`

Purpose:

- cache normalized ReliefWeb metadata
- dedupe repeated API fetches
- allow comments/shares even after the source item scrolls off the latest API page

Suggested columns:

- `id uuid primary key`
- `provider text not null default 'reliefweb'`
- `provider_item_id text not null`
- `title text not null`
- `url text not null`
- `source_name text`
- `published_at timestamptz`
- `country_codes text[] not null default '{}'`
- `country_names text[] not null default '{}'`
- `disaster_types text[] not null default '{}'`
- `theme_names text[] not null default '{}'`
- `format text`
- `language text`
- `snippet text`
- `image_url text`
- `raw jsonb not null default '{}'::jsonb`
- `last_seen_at timestamptz not null default now()`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Indexes:

- unique `(provider, provider_item_id)`
- gin on `country_codes`
- index on `published_at desc`

### 2. `external_news_comments`

Purpose:

- native in-app discussion on news items

Suggested columns:

- `id uuid primary key`
- `news_item_id uuid not null references external_news_items(id) on delete cascade`
- `parent_id uuid null references external_news_comments(id) on delete cascade`
- `author_id uuid not null references auth.users(id)`
- `body text not null`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`
- `deleted_at timestamptz`

Optional follow-up table if we want parity with post comments:

- `external_news_comment_likes`

### 3. Extend `posts`

The app already has `shared_post_id` for internal reposts. For external news shares, add link-card fields.

Suggested new nullable columns on `posts`:

- `external_ref_type text`
- `external_ref_id uuid`
- `link_url text`
- `link_title text`
- `link_source_name text`
- `link_published_at timestamptz`
- `link_image_url text`
- `link_snippet text`

Recommended constraints:

- `external_ref_type in ('news')` for now
- if `external_ref_type = 'news'`, then `external_ref_id` references `external_news_items(id)`

### Why not reuse `shared_post_id`?

Because `shared_post_id` points to another post. News items are a separate entity with separate comments and legal rules.

## Recommended GraphQL Additions

Add a new `news` module in `apps/api/src/graphql/modules/news`.

### New types

```graphql
type ExternalNewsItem {
  id: ID!
  provider: String!
  provider_item_id: String!
  title: String!
  url: String!
  source_name: String
  published_at: String
  country_codes: [String!]!
  country_names: [String!]!
  disaster_types: [String!]!
  theme_names: [String!]!
  format: String
  language: String
  snippet: String
  image_url: String
  comment_count: Int!
  shared_post_count: Int!
}

type ExternalNewsComment {
  id: ID!
  news_item_id: ID!
  parent_id: ID
  author_id: ID!
  body: String!
  created_at: String!
  updated_at: String!
  author: PostAuthor
}
```

### New queries

```graphql
type Query {
  countryConflictUpdates(country_code: String!, limit: Int, offset: Int): [ExternalNewsItem!]!
  globalConflictUpdates(limit: Int, offset: Int): [ExternalNewsItem!]!
  externalNewsComments(news_item_id: ID!, limit: Int, before: String): [ExternalNewsComment!]!
}
```

### New mutations

```graphql
type Mutation {
  addExternalNewsComment(news_item_id: ID!, body: String!, parent_id: ID): ExternalNewsComment!
  shareExternalNewsToCountry(news_item_id: ID!, body: String, visibility: String): Post!
  refreshCountryConflictUpdates(country_code: String!): [ExternalNewsItem!]!
}
```

### Notes

- `shareExternalNewsToCountry` should create a normal `Post`
- this mutation should internally pull the referenced `external_news_items` row and map it into the new link-card fields on `posts`
- `refreshCountryConflictUpdates` can be auth-gated or admin-gated, but the regular query can use cached rows first

## API Ingestion Strategy

### Fetch mode

Use a hybrid approach:

- fetch live from ReliefWeb when cache is stale
- upsert normalized items into `external_news_items`
- return cached rows to the frontend

### Cache rules

Recommended:

- selected-country stats query TTL: 15 minutes
- global crisis query TTL: 15 minutes
- background refresh on demand plus optional cron

### ReliefWeb endpoints to use first

Use:

- `reports` for the main updates stream
- optionally `disasters` later for grouped crisis metadata

Recommended initial filter strategy:

- latest reports
- filtered by country code or country name mapping
- filtered to crisis-relevant themes if available

Normalize these fields from ReliefWeb:

- item ID
- title
- source
- date
- URL
- country list
- themes
- disaster types
- language
- format

### Ingestion rule

Do not save full raw text into feed-facing columns.
Keep the full provider payload only in `raw jsonb` for debugging and future field extraction.

## Frontend Integration Plan

### 1. Add a web service

Create:

- [`apps/web/src/app/core/services/news.service.ts`](/Users/animated/World_App/world-app-skeleton/apps/web/src/app/core/services/news.service.ts)

Methods:

- `countryConflictUpdates(countryCode: string, limit = 10, offset = 0)`
- `globalConflictUpdates(limit = 10, offset = 0)`
- `comments(newsItemId: string, limit = 25, before?: string | null)`
- `addComment(newsItemId: string, body: string, parentId?: string | null)`
- `shareToCountry(newsItemId: string, body?: string | null)`

### 2. Extend the stats tab state in `globe.page.ts`

Add state for:

- `countryNews: ExternalNewsItem[]`
- `globalNews: ExternalNewsItem[]`
- `newsLoading`
- `newsError`
- `newsCommentOpenById`
- `newsCommentItemsById`
- `newsCommentDraftById`
- `newsShareFeedbackById`
- `newsShareBusyById`

### 3. Load data alongside mood stats

Today `globe.page.ts` already does:

- `loadMoodStats()`

Add:

- `loadStatsNews()`

Trigger it when:

- the selected country changes
- the tab changes to `stats`
- the stats view opens after country selection

### 4. Add UI block below the existing Local mood card

Suggested order inside the existing `*ngSwitchCase="'stats'"` pane:

1. Global users
2. Global mood
3. Local users
4. Local mood
5. `Conflict updates`
6. Status/debug card

### 5. Card actions

For each news item:

- `Open on ReliefWeb`
- `Comment`
- `Share to country`

The share action should call the new news service mutation, not the existing `sharePostToCountry()` helper, because this is not an internal post repost.

## Feed Rendering Plan For Shared News

### Reuse the existing post feed

Do not build a separate "shared news feed" type.
Instead, extend the current `CountryPost` model.

Add these optional fields to [`packages/shared/src/models/post.ts`](/Users/animated/World_App/world-app-skeleton/packages/shared/src/models/post.ts):

- `external_ref_type?: 'news' | null`
- `external_ref_id?: string | null`
- `link_url?: string | null`
- `link_title?: string | null`
- `link_source_name?: string | null`
- `link_published_at?: string | null`
- `link_image_url?: string | null`
- `link_snippet?: string | null`

### Feed-card rendering rule

When `post.external_ref_type === 'news'`, show:

- user caption/body if present
- a news preview card beneath it
- source name + published date
- outbound-link button

This is a better UX than stuffing external metadata into `body`.

### Why this fits current code

The post feed already supports:

- standard body rendering
- media-aware layouts
- shared internal posts
- post detail pages

Adding a link-card branch is a small, understandable extension.

## Notifications

Recommended first version:

- no automatic notifications for external-news publication
- only notify on user-generated engagement if we later add:
  - replies to news comments
  - likes on news comments

That keeps launch scope smaller.

## Moderation

Add the same moderation posture used for posts/comments:

- report abusive comments on news items in a later phase
- soft-delete comments
- keep no publisher-body text in user-editable fields

The riskiest moderation surface is the user comment thread, not the linked metadata.

## Admin / Ops

Add one small admin capability later:

- "refresh country news cache" button in the admin presence page

This is optional for v1 because cache refresh can happen automatically on query.

## Suggested File Changes

### Database

- `supabase/migrations/<timestamp>_add_external_news.sql`

### API

- `apps/api/src/graphql/typeDefs.ts`
- `apps/api/src/graphql/resolvers.ts`
- `apps/api/src/graphql/modules/news/news.resolver.ts`
- `apps/api/src/graphql/modules/news/news.service.ts`
- optionally `apps/api/src/external/reliefweb.client.ts`

### Web

- `apps/web/src/app/core/services/news.service.ts`
- `apps/web/src/app/pages/globe.page.ts`
- `packages/shared/src/models/post.ts`
- `apps/web/src/app/core/services/posts.service.ts`
- `apps/web/src/app/pages/post.page.ts`
- `apps/web/src/app/pages/search.page.ts`
- `apps/web/src/app/pages/profile.page.ts`

Reason for those last files:

- they already render posts and shared content
- they will need to understand the new news-link fields for shared news posts

## Exact V1 Scope I Recommend

Ship only this first:

1. ReliefWeb-backed cached country updates in the stats tab
2. open-source/outbound link action
3. in-app comments on news items
4. share-to-country creating a normal post with a news link card

Do not ship in v1:

- full article body rendering
- auto-generated summaries from source text
- likes on news comments
- push notifications for new external updates
- multi-provider news aggregation
- per-user personalized news ranking

## Concrete Query Shape To Aim For

Frontend stats query flow:

```ts
if (selectedCountry?.code) {
  await Promise.all([
    loadMoodStats(),
    loadCountryConflictUpdates(selectedCountry.code),
  ]);
} else {
  await Promise.all([
    loadMoodStats(),
    loadGlobalConflictUpdates(),
  ]);
}
```

Share flow:

```ts
await newsService.shareToCountry(newsItemId);
```

Server-side effect:

- fetch `external_news_items` row
- create `posts` row with:
  - `body = userCaption || ''`
  - `visibility = 'country'`
  - `media_type = 'link'`
  - `external_ref_type = 'news'`
  - `external_ref_id = news_item.id`
  - `link_url = news_item.url`
  - `link_title = news_item.title`
  - `link_source_name = news_item.source_name`
  - `link_published_at = news_item.published_at`
  - `link_image_url = news_item.image_url`
  - `link_snippet = news_item.snippet`

## Bottom Line

The best implementation for this codebase is not "turn ReliefWeb articles into regular posts."

The best implementation is:

- keep ReliefWeb items as external linked records
- render them inside the existing stats tab
- let users comment on those linked records
- let users share those records into the feed as normal user-authored link posts

That matches the app's existing architecture, keeps the legal surface safer, and gives the product a useful country-specific updates layer without making World App feel like a scraped-news reader.
