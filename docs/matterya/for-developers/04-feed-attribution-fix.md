# Feed attribution fix — “The Archive” disaster (developer)

## Symptom
All Sparks/Hubs feed cards showed author **The Archive**.

## Root cause
```swift
// BROKEN (old)
var isHubSeedVideo: Bool { externalRefType == "hub" }
```

`SurfacePageClient` and GraphQL stamp live hub_slug posts as `externalRefType = "hub"`.  
`PlayPlatformBridge.displayCreator` / `isArchiveCatalogMedia` then forced:

`HubVideoSeedService.archiveChannelDisplayName` → **"The Archive"**.

DB profiles/channels were fine (Dokumentar AL, people, etc.).

## Product rules
1. Sparks → uploading user as primary name  
2. Hubs-on-feed shares → sharing person + “Shared from {channel}”  
3. True IA seeds only → The Archive channel  

`FacebookPostCard` already had re-share UI (`isFeedReshareCard` + `originSource`); seed detection was poisoning `displayCreator`.

## Fix (ios-native / world-app-skeleton)
Narrow seed detection:

```swift
var isHubSeedVideo: Bool {
  if HubVideoSeedService.isArchiveChannelAuthor(authorID) { return true }
  // ia_* / hub_spark_* ids only — NOT externalRefType == "hub" alone
  …
}
```

`displayCreator` forces The Archive **only** for `isArchiveChannelAuthor`.  
`YouTubeCatalogService` grouping and `FacebookPostCard` hubSlug fallbacks updated similarly.  
Web: `hubs-seed.service.ts` `isHubSeedVideo` mirrored.

## Files touched
- `HubVideoSeedService.swift`
- `PlayPlatformBridge.swift`
- `FacebookPostCard.swift`
- `YouTubeCatalogService.swift`
- `HubCategoryClassifier.swift`
- `apps/web/src/app/hubs/hubs-seed.service.ts`

## Verify
1. Rebuild iOS from `ios-native`  
2. Home feed: live channel names + person sharers  
3. Hubs watch: channel identity for live R2 longform  
4. Archive seeds (if `archiveContentEnabled`) still show The Archive  

## Note
These Swift changes may still be **uncommitted** in a dirty worktree alongside other WIP. Stage carefully; do not bundle unrelated iOS churn into API-only deploys.
