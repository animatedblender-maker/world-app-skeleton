import Foundation

enum ReelsRankingEngine {
    private static var sessionWatchedIDs: Set<String> = []

    static func markWatched(_ postID: String) {
        sessionWatchedIDs.insert(postID)
    }

    static func resetSession() {
        sessionWatchedIDs.removeAll()
    }

    /// Original Sparks for the **unified vertical player** only.
    /// Feed spark shares stay on the feed card — never this pool (open resolves to the original).
    static func isSparkEligible(_ post: CountryPost) -> Bool {
        guard !post.isStory else { return false }
        guard post.playableVideoURL != nil else { return false }

        // Explicit feed re-shares — never swipe-pool “new” Sparks.
        if SparkShareMarker.isMarked(post.body) { return false }
        if post.isSparkFeedShare { return false }
        if PlayPlatformBridge.isHubOriginShare(post) { return false }

        // Archive seed gated off.
        if !AppConfig.archiveContentEnabled,
           post.isArchiveSparkSource || PlayPlatformBridge.isArchiveCatalogMedia(post) {
            return false
        }

        // First-class Sparks: reel type / JSON reel / __spark__| body.
        if post.isReel { return true }

        // R2 catalog originals often land as media_type=video + reel JSON / r2 path.
        // Accept short-form R2 video that is not a hub long-form path.
        if post.isR2HostedMedia, post.hasVideo {
            let path = (post.mediaURL ?? "").lowercased() + (post.thumbURL ?? "").lowercased()
            if path.contains("longform") { return false }
            if HubChannelPostMarker.isMarked(post.body) { return false }
            return true
        }

        return false
    }

    /// Prefer the playable original when the user opened a feed/chat share shell.
    static func resolvePlayerStart(_ post: CountryPost) -> CountryPost {
        if let embed = post.sharedPost?.asCountryPost,
           embed.playableVideoURL != nil,
           isSparkEligible(embed) || embed.isReel {
            return embed
        }
        return post
    }

    /// Picks the next batch for endless spark scrolling.
    /// Temporary stand-in: **SparkDiscoveryEngine** (novelty + diversity) until official recommender.
    static func nextBatch(
        from candidates: [CountryPost],
        excluding existingIDs: Set<String>,
        limit: Int,
        viewerCountry: String?,
        followingIDs: Set<String>,
        tail: [CountryPost] = [],
        allowRecycle: Bool = false
    ) -> [CountryPost] {
        _ = viewerCountry
        _ = followingIDs
        return SparkDiscoveryEngine.nextBatch(
            from: candidates,
            excluding: existingIDs,
            limit: limit,
            tail: tail,
            allowRecycle: allowRecycle
        )
    }

    /// Full reshuffle for Sparks player / rails — discovery order (unseen first).
    static func sessionFreshOrder(_ posts: [CountryPost]) -> [CountryPost] {
        SparkDiscoveryEngine.rankForDiscovery(posts.filter(isSparkEligible))
    }

    static func rank(
        _ posts: [CountryPost],
        viewerCountry: String?,
        followingIDs: Set<String>,
        softenWatchedPenalty: Bool = false
    ) -> [CountryPost] {
        _ = viewerCountry
        _ = followingIDs
        _ = softenWatchedPenalty
        return sessionFreshOrder(posts)
    }

    /// Prefer R2 originals, then live network sparks, Archive last (when enabled).
    static func prioritizeR2First(_ posts: [CountryPost]) -> [CountryPost] {
        let r2 = posts.filter(\.isR2HostedMedia).shuffled()
        let live = posts.filter { !$0.isR2HostedMedia && !$0.isArchiveSparkSource }.shuffled()
        guard AppConfig.archiveContentEnabled else {
            return r2 + live
        }
        let archive = posts.filter(\.isArchiveSparkSource).shuffled()
        return r2 + live + archive
    }
}

struct ReelsFeedPage: Sendable {
    let posts: [CountryPost]
    let nextCursor: String?
    let hasMore: Bool
}
