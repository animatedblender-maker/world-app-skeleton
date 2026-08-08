import Foundation

enum ReelsRankingEngine {
    private static let recencyHalfLifeHours: Double = 48
    private static let diversityPenalty: Double = 0.45
    private static let countryDiversityPenalty: Double = 0.62
    private static let diversityWindow = 3
    private static let countryDiversityWindow = 2
    private static let watchedPenalty: Double = 0.15
    private static let recycleWatchedPenalty: Double = 0.55
    private static var sessionWatchedIDs: Set<String> = []

    static func markWatched(_ postID: String) {
        sessionWatchedIDs.insert(postID)
    }

    static func resetSession() {
        sessionWatchedIDs.removeAll()
    }

    /// Only **original** Sparks (Archive seeds when enabled, channel sparks, user-published sparks).
    /// Feed re-shares of Sparks stay on the home feed card only — never this pool.
    static func isSparkEligible(_ post: CountryPost) -> Bool {
        guard post.hasVideo, !post.isStory else { return false }
        guard post.isReel, post.playableVideoURL != nil else { return false }
        // Archive seed / archive.org media gated off until re-enabled in AppConfig.
        if !AppConfig.archiveContentEnabled,
           post.isArchiveSparkSource || PlayPlatformBridge.isArchiveCatalogMedia(post) {
            return false
        }
        // Explicit feed re-share stamps — never enter Sparks-for-you / swipe pool as “new” Sparks.
        if SparkShareMarker.isMarked(post.body) { return false }
        if post.isSparkFeedShare { return false }
        if PlayPlatformBridge.isHubOriginShare(post) { return false }
        // Pointer re-post of someone else’s Spark.
        if let shared = post.sharedPostID, !shared.isEmpty,
           !HubChannelPostMarker.isMarked(post.body) {
            return false
        }
        // Live user + Archive media + no channel marker = re-hosted catalog clip, not original.
        if PlayPlatformBridge.isArchiveCatalogMedia(post),
           PlayPlatformBridge.isLikelyLiveUserAuthor(post.authorID),
           !post.isHubSeedVideo,
           !HubChannelPostMarker.isMarked(post.body) {
            return false
        }
        return true
    }

    /// Picks the next batch for endless spark scrolling.
    /// Until a real recommender exists: **always random** so every open/scroll feels new.
    /// Light author/country diversity is applied on top of the shuffle (no engagement ranking).
    static func nextBatch(
        from candidates: [CountryPost],
        excluding existingIDs: Set<String>,
        limit: Int,
        viewerCountry: String?,
        followingIDs: Set<String>,
        tail: [CountryPost] = [],
        allowRecycle: Bool = false
    ) -> [CountryPost] {
        guard limit > 0 else { return [] }
        _ = viewerCountry
        _ = followingIDs

        var pool = candidates.filter { !existingIDs.contains($0.id) && isSparkEligible($0) }
        if pool.isEmpty, allowRecycle {
            pool = candidates.filter { !existingIDs.contains($0.id) && isSparkEligible($0) }
        }
        if pool.isEmpty, allowRecycle {
            pool = candidates.filter { isSparkEligible($0) }
        }
        guard !pool.isEmpty else { return [] }

        // Fresh random order every call — not chronological, not engagement-ranked.
        var remaining = prioritizeR2First(pool)
        var context = tail
        var picked: [CountryPost] = []

        while picked.count < limit, !remaining.isEmpty {
            // Soft diversity: prefer not repeating author/country from recent tail when options exist.
            let recentAuthors = Set(context.suffix(diversityWindow).map(\.authorID))
            let recentCountries = Set(
                context.suffix(countryDiversityWindow).compactMap { $0.countryCode?.uppercased() }
            )
            let diverse = remaining.enumerated().filter { _, post in
                if recentAuthors.contains(post.authorID) { return false }
                if let code = post.countryCode?.uppercased(), recentCountries.contains(code) {
                    return false
                }
                return true
            }
            let choiceIndex: Int
            if let pick = diverse.randomElement() {
                choiceIndex = pick.offset
            } else {
                choiceIndex = remaining.indices.randomElement() ?? 0
            }
            let choice = remaining.remove(at: choiceIndex)
            picked.append(choice)
            context.append(choice)
        }

        return picked
    }

    /// Full reshuffle for Sparks player / rails (R2 ahead of Archive, all random within).
    static func sessionFreshOrder(_ posts: [CountryPost]) -> [CountryPost] {
        prioritizeR2First(posts.filter(isSparkEligible))
    }

    static func rank(
        _ posts: [CountryPost],
        viewerCountry: String?,
        followingIDs: Set<String>,
        softenWatchedPenalty: Bool = false
    ) -> [CountryPost] {
        // Stand-in for recommender: always random (still R2-first buckets).
        _ = viewerCountry
        _ = followingIDs
        _ = softenWatchedPenalty
        return sessionFreshOrder(posts)
    }

    private static func baseScore(
        for post: CountryPost,
        viewerCountry: String?,
        followingIDs: Set<String>,
        softenWatchedPenalty: Bool = false
    ) -> Double {
        let ageHours = hoursSince(post.createdAt)
        let recency = pow(0.5, ageHours / recencyHalfLifeHours)
        let engagement = Double(post.likeCount) * 2
            + Double(post.commentCount) * 3
            + Double(post.viewCount) * 0.1
        let velocity = engagement / (ageHours + 1)

        var score = recency * (1 + engagement + velocity * 0.35)

        if let viewerCountry,
           post.countryCode?.uppercased() == viewerCountry {
            score *= 1.3
        }

        if followingIDs.contains(post.authorID) {
            score *= 1.5
        }

        if post.isReel {
            score *= 1.2
        }

        // R2 focus catalog dominates Sparks swipe; Archive is last resort fill.
        if post.isR2HostedMedia {
            score *= 4.5
        } else if post.isArchiveSparkSource {
            score *= 0.08
        }

        if sessionWatchedIDs.contains(post.id) {
            score *= softenWatchedPenalty ? recycleWatchedPenalty : watchedPenalty
        }

        return score
    }

    /// Prefer R2 originals, then live network sparks, Archive last (when enabled).
    static func prioritizeR2First(_ posts: [CountryPost]) -> [CountryPost] {
        let r2 = posts.filter(\.isR2HostedMedia)
        let live = posts.filter { !$0.isR2HostedMedia && !$0.isArchiveSparkSource }
        guard AppConfig.archiveContentEnabled else {
            return r2.shuffled() + live.shuffled()
        }
        let archive = posts.filter(\.isArchiveSparkSource)
        return r2.shuffled() + live.shuffled() + archive.shuffled()
    }

    private static func hoursSince(_ iso: String) -> Double {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return 72 }
        return max(0, Date().timeIntervalSince(date) / 3600)
    }
}

struct ReelsFeedPage: Sendable {
    let posts: [CountryPost]
    let nextCursor: String?
    let hasMore: Bool
}