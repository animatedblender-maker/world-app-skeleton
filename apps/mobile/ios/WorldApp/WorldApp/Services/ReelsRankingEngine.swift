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

    static func isSparkEligible(_ post: CountryPost) -> Bool {
        guard post.hasVideo, !post.isStory else { return false }
        if post.isReel { return true }
        return post.playableVideoURL != nil
    }

    /// Picks the next ranked batch for endless spark scrolling.
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

        var pool = candidates.filter { !existingIDs.contains($0.id) && isSparkEligible($0) }
        if pool.isEmpty, allowRecycle {
            pool = candidates.filter { !existingIDs.contains($0.id) && isSparkEligible($0) }
        }
        if pool.isEmpty, allowRecycle {
            pool = candidates.filter { isSparkEligible($0) }
        }
        guard !pool.isEmpty else { return [] }

        var context = tail
        var picked: [CountryPost] = []
        var remaining = pool
        let viewerCode = viewerCountry?.uppercased()

        while picked.count < limit, !remaining.isEmpty {
            var bestIndex = 0
            var bestScore = -Double.infinity

            let recentAuthors = Set(context.suffix(diversityWindow).map(\.authorID))
            let recentCountries = Set(
                context.suffix(countryDiversityWindow).compactMap { $0.countryCode?.uppercased() }
            )

            for (index, post) in remaining.enumerated() {
                var score = baseScore(
                    for: post,
                    viewerCountry: viewerCode,
                    followingIDs: followingIDs,
                    softenWatchedPenalty: allowRecycle
                )
                if recentAuthors.contains(post.authorID) {
                    score *= diversityPenalty
                }
                if let code = post.countryCode?.uppercased(), recentCountries.contains(code) {
                    score *= countryDiversityPenalty
                }
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            let choice = remaining.remove(at: bestIndex)
            picked.append(choice)
            context.append(choice)
        }

        return picked
    }

    static func rank(
        _ posts: [CountryPost],
        viewerCountry: String?,
        followingIDs: Set<String>,
        softenWatchedPenalty: Bool = false
    ) -> [CountryPost] {
        let viewerCode = viewerCountry?.uppercased()
        let scored = posts.map { post in
            (
                post: post,
                score: baseScore(
                    for: post,
                    viewerCountry: viewerCode,
                    followingIDs: followingIDs,
                    softenWatchedPenalty: softenWatchedPenalty
                )
            )
        }

        var remaining = scored
        var result: [CountryPost] = []

        while !remaining.isEmpty {
            var bestIndex = 0
            var bestAdjusted = -Double.infinity

            let recentAuthors = Set(result.suffix(diversityWindow).map(\.authorID))
            let recentCountries = Set(
                result.suffix(countryDiversityWindow).compactMap { $0.countryCode?.uppercased() }
            )

            for (index, item) in remaining.enumerated() {
                var adjusted = item.score
                if recentAuthors.contains(item.post.authorID) {
                    adjusted *= diversityPenalty
                }
                if let code = item.post.countryCode?.uppercased(), recentCountries.contains(code) {
                    adjusted *= countryDiversityPenalty
                }
                if adjusted > bestAdjusted {
                    bestAdjusted = adjusted
                    bestIndex = index
                }
            }

            let picked = remaining.remove(at: bestIndex)
            result.append(picked.post)
        }

        return result
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

        if sessionWatchedIDs.contains(post.id) {
            score *= softenWatchedPenalty ? recycleWatchedPenalty : watchedPenalty
        }

        return score
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