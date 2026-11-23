# Ads (Sparks + Hubs)

Teammate map for Matterya video ads. Phase 1 organized modules; Phase 2 hardened security (shipped).

## Surfaces

| Surface | Placement | UI | Behavior |
|---------|-----------|-----|----------|
| Sparks pager | `reel` (fallback `video`) | `SparkAdStandaloneCard` | Own swipe page; **append-only** into the pager (never mid-list insert — fling hitch). |
| Hubs / long-form | `video` | `AdPrerollView` | Full-screen pre-roll before the title; Skip bottom-right; Learn more = Matterya matte/ink CTA. |

Premium (`SubscriptionService.isPremium`) skips ads on both surfaces via `AdDeliveryPolicy.adsEnabled`.

### Budget model (client-set)
- Advertisers set **total** and **daily** budget in EUR. Campaign **create is free** (no App Store create-IAP).
- Delivery pacing in `ads.serve.ts` uses **€0.10 per impression** (`budget_cents / 10`). iOS `AdsBudgetEstimate` mirrors that for estimated impressions / views (~85% view rate).
- Real money collection (Stripe / invoicing) can plug in later; do not resurrect fixed create SKUs for ad spend.

## iOS module map

```
Services/AdsModels.swift     AdDeliveryPolicy, AdCreative/Campaign/Slot,
                             CountryPost.sponsoredAd, SparkAdRegistry,
                             AdServeCache, AdURL
Services/AdsService.swift    GraphQL client (serve / impression / click / CRUD)
Services/AdCampaignBilling.swift  StoreKit purchase → redeem with JWS
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

### URL open (iOS)

Always use `AdURL.normalized(_:)` / `AdURL.media(_:)`. Bare hosts become `https://…`. Rejects non-http(s), `javascript:` / `data:` / `file:`, credentials-in-URL, empty host, length &gt; 2048.

## API module map

```
apps/api/src/graphql/modules/ads/
  ads.resolver.ts       GraphQL entry (keep thin)
  ads.service.ts        Facade + campaign/creative CRUD
  ads.serve.ts          serveVideoAd, pacing, budget
  ads.attribution.ts    logImpression, logClick (TTL + unique click)
  ads.billing.ts        IAP create-credit redeem (requires verified JWS)
  ads.apple-jws.ts      StoreKit 2 JWS verify (x5c → Apple Root CA G3)
  ads.urls.ts           normalizeClickUrl / normalizeMediaUrl / country codes
```

Resolver keeps importing `AdsService` from `ads.service.ts`.

## Security (Phase 2 — shipped)

| ID | Control | Where |
|----|---------|--------|
| T3 | Redeem requires StoreKit JWS; signature + Apple Root CA G3 chain; product/bundle/tx match verified payload | `ads.apple-jws.ts`, `ads.billing.ts` |
| T2 | Click/media URLs http(s) only; no credentials; block localhost/private hosts; re-normalize on serve | `ads.urls.ts`, createCreative, serve map, iOS `AdURL` |
| T1 | Impression/click tokens must be UUID shape; 2h TTL from `served_at`; one `ad_clicks` row per impression | `ads.attribution.ts`, migration `20261123120000_ad_clicks_impression_unique.sql` |
| T4+ | `debugServeVideoAd` disabled in production unless `ADS_DEBUG_SERVE=1`; server budget/pacing remains source of truth in `ads.serve.ts` | resolver + serve |

### Ops notes

- Free create emails: default owner + `ADS_FREE_CREATE_EMAILS` env (comma-separated).
- Apply migration `20261123120000_ad_clicks_impression_unique.sql` on every environment (prod applied with Phase 2 ship).
- Do **not** restore decode-only JWS redeem paths.

## Product rules (do not break)

1. Sparks ads are **standalone pages**, never overlays on organic clips.
2. Sparks insert is **append-only** after scroll settle (`ScrollBudget` / fling gate).
3. Hubs pre-roll uses `AdServeCache` so the creative can start before GraphQL returns.
4. Player is **aspect fill** (`AdFillPlayerView`), not stock `VideoPlayer` letterbox.
5. Skip control is **bottom-right**; Learn more is Matterya matte capsule on ink text.

## Quick change recipes

**Change Sparks ad density** → edit ranges in `AdDeliveryPolicy` only.

**New ad UI chrome** → `SparkAdCard` or `AdPrerollView`; shared player stays in `AdPlayerSurface`.

**New serve rule (geo, budget, pacing)** → `ads.serve.ts`; keep resolver thin.

**Learn more broken** → check DB `click_url`, API `normalizeClickUrl`, iOS `AdURL.normalized`.

**Purchase redeem fails** → client must send StoreKit `jwsRepresentation`; server verifies chain to Apple Root CA G3.
