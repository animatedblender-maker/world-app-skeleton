import Foundation

enum ReelsRankingEngine {
    private static let recencyHalfLifeHours: Double = 48
    private static let diversityPenalty: Double = 0.45
    private static let diversityWindow = 3
    private static let watchedPenalty: Double = 0.15
    private static var sessionWatchedIDs: Set<String> = []

    static func markWatched(_ postID: String) {
        sessionWatchedIDs.insert(postID)
    }

    static func resetSession() {
        sessionWatchedIDs.removeAll()
    }

    static func rank(
        _ posts: [CountryPost],
        viewerCountry: String?,
        followingIDs: Set<String>
    ) -> [CountryPost] {
        let viewerCode = viewerCountry?.uppercased()
        let scored = posts.map { post in
            (post: post, score: baseScore(for: post, viewerCountry: viewerCode, followingIDs: followingIDs))
        }

        var remaining = scored
        var result: [CountryPost] = []

        while !remaining.isEmpty {
            var bestIndex = 0
            var bestAdjusted = -Double.infinity

            let recentAuthors = Set(result.suffix(diversityWindow).map(\.authorID))

            for (index, item) in remaining.enumerated() {
                var adjusted = item.score
                if recentAuthors.contains(item.post.authorID) {
                    adjusted *= diversityPenalty
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
        followingIDs: Set<String>
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

        if (post.mediaType ?? "").lowercased() == "reel" {
            score *= 1.2
        }

        if sessionWatchedIDs.contains(post.id) {
            score *= watchedPenalty
        }

        return score
    }

    private static func hoursSince(_ iso: String) -> Double {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return 72 }
        return max(0, Date().timeIntervalSince(date) / 3600)
    }
}