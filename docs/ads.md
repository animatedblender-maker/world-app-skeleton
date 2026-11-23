# Ads (Sparks + Hubs)

Teammate map for Matterya video ads. **Phase 1** = organize modules. **Phase 2** = security hardening (see below). Behavior must stay the same when you move code.

## Surfaces

| Surface | Placement | UI | Behavior |
|---------|-----------|-----|----------|
| Sparks pager | `reel` (fallback `video`) | `SparkAdStandaloneCard` | Own swipe page; **append-only** into the pager (never mid-list insert — fling hitch). |
| Hubs / long-form | `video` | `AdPrerollView` | Full-screen pre-roll before the title; Skip bottom-right; Learn more = Matterya matte/ink CTA. |

Premium (`SubscriptionService.isPremium`) skips ads on both surfaces via `AdDeliveryPolicy.adsEnabled`.

## iOS module map

```
Services/AdsModels.swift     AdDeliveryPolicy, AdCreative/Campaign/Slot,
                             CountryPost.sponsoredAd, SparkAdRegistry,
                             AdServeCache, AdURL
Services/AdsService.swift    GraphQL client (serve / impression / click / CRUD)
Views/Ads/AdPrerollView.swift     Hubs pre-roll only
Views/Ads/SparkAdCard.swift       Sparks standalone page
Views/Ads/AdPlayerSurface.swift   AdFillPlayerView (aspectFill — no black letterbox)
Views/Reels/ReelsVerticalFeed.swift   density insert using AdDeliveryPolicy
```

**Do not** re-declare ad types in `Models.swift`. Density / skip / cache TTL live in `AdDeliveryPolicy` only.

### Density knobs (`AdDeliveryPolicy`)

| Constant | Role |
|----------|------|
| `firstOrganicGap` | Organic Sparks before first ad |
| `laterOrganicGap` | Gap after an ad was shown |
| `emptyServeFirstGap` / `emptyServeLaterGap` | Retry when serve returns nil |
| `upcomingAdAvoidWindow` | Lookahead to avoid stacking ads |
| `serveCacheMaxAge` | Hubs instant start from last serve |
| `skipAfterSecondsClamp` | Client clamp of server skip delay |
| `serveTimeoutSeconds` | Cold GraphQL serve timeout |

### URL open

Always use `AdURL.normalized(_:)` / `AdURL.media(_:)`. Bare hosts (`matterya.com`) become `https://…`. Non-http(s) schemes are rejected on iOS.

## API module map

```
apps/api/src/graphql/modules/ads/
  ads.resolver.ts       GraphQL entry (keep thin)
  ads.service.ts        Facade + campaign/creative CRUD
  ads.serve.ts          serveVideoAd, pacing, budget
  ads.attribution.ts    logImpression, logClick
  ads.billing.ts        IAP create-credit, free-email entitlement
  ads.urls.ts           normalizeClickUrl, country codes
```

Resolver keeps importing `AdsService` from `ads.service.ts`. New serve/attribution logic goes in the focused modules; the facade re-exports for callers.

## Product rules (do not break)

1. Sparks ads are **standalone pages**, never overlays on organic clips.
2. Sparks insert is **append-only** after scroll settle (`ScrollBudget` / fling gate).
3. Hubs pre-roll uses `AdServeCache` so the creative can start before GraphQL returns.
4. Player is **aspect fill** (`AdFillPlayerView`), not stock `VideoPlayer` letterbox.
5. Skip control is **bottom-right**; Learn more is Matterya matte capsule on ink text.

## Phase 2 security backlog (do not ship as “done” in Phase 1)

Discussed threat model for future PRs (order of attack):

| ID | Risk | Direction |
|----|------|-----------|
| T3 | IAP / create-credit: client-trusted JWS decode | Verify with App Store Server API; never trust decoded payload alone |
| T2 | Click URL open / stored `click_url` | Allowlist schemes + hosts; reject `javascript:` / data / intent; server + client |
| T1 | Impression / click mutation without auth or TTL | Require viewer JWT where product allows; short-lived impression tokens; rate limits |
| T4 | Serve budget bypass | Server-side remaining budget + pacing as source of truth |
| T5–T8 | Token replay, free-email abuse, debug serve in prod, studio earn double-credit | Harden as follow-ups |

When you touch billing or attribution, read `ads.billing.ts` / `ads.attribution.ts` first and add tests for the threat you are closing.

## Quick change recipes

**Change Sparks ad density** → edit ranges in `AdDeliveryPolicy` only; do not hardcode `12...28` in the feed again.

**New ad UI chrome** → `SparkAdCard` or `AdPrerollView`; shared player stays in `AdPlayerSurface`.

**New serve rule (geo, budget, pacing)** → `ads.serve.ts`; keep resolver thin.

**Learn more broken** → check DB `click_url`, API `normalizeClickUrl`, iOS `AdURL.normalized`.
