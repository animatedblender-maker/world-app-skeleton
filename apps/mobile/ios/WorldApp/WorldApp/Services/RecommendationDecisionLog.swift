import Foundation

// MARK: - Recommendation decision / impression log (RecSys Phase 0)
//
// Roadmap directive: log every recommendation decision with enough context to
// reconstruct what the system knew, which sources participated, and position.
// Events flush through EngagementTracker → API → Kafka matterya.engagement.

@MainActor
final class RecommendationDecisionLog {
    static let shared = RecommendationDecisionLog()

    struct ServedItem: Sendable {
        var postID: String
        var authorID: String
        var sources: [String]
        var position: Int
        var score: Double? = nil
    }

    private var lastPageLogAt: [RecommendationSurface: Date] = [:]
    private var viewportLogged = Set<String>()
    private let minInterval: TimeInterval = 2.5

    private init() {}

    /// Log a served page (impression-eligible ranking decision).
    func logServedPage(
        surface: RecommendationSurface,
        requestID: String,
        items: [ServedItem]
    ) {
        guard !items.isEmpty else { return }
        // Rate-limit noisy re-ranks on soft merge.
        if let last = lastPageLogAt[surface], Date().timeIntervalSince(last) < minInterval {
            return
        }
        lastPageLogAt[surface] = Date()

        let policy = surface.policy
        var positions: [String] = []
        // Cap per-item impressions so soft-merge re-ranks do not flood Kafka.
        let impressionCap = min(items.count, 12)
        for (i, item) in items.prefix(impressionCap).enumerated() {
            let pos = item.position > 0 ? item.position : i
            positions.append("\(item.postID)@\(pos)")
            EngagementTracker.shared.enqueueRecommendationEvent(
                type: "impression",
                contentId: item.postID,
                authorId: item.authorID,
                surface: surface.rawValue,
                meta: [
                    "requestId": requestID,
                    "position": "\(pos)",
                    "sources": item.sources.joined(separator: ","),
                    "policyVersion": policy.policyVersion,
                    "surface": surface.rawValue,
                ]
            )
        }
        for (i, item) in items.enumerated() where i >= impressionCap {
            let pos = item.position > 0 ? item.position : i
            positions.append("\(item.postID)@\(pos)")
        }

        // One summary event for the whole ranking decision (reconstructable).
        EngagementTracker.shared.enqueueRecommendationEvent(
            type: "ranked_served",
            contentId: items.first?.postID,
            authorId: items.first?.authorID,
            surface: surface.rawValue,
            meta: [
                "requestId": requestID,
                "count": "\(items.count)",
                "policyVersion": policy.policyVersion,
                "intent": policy.primaryIntent,
                "explorationBudget": String(format: "%.3f", policy.explorationBudget),
                "items": positions.prefix(40).joined(separator: "|"),
            ]
        )
    }

    /// Viewport-visible impression (true exposure, not merely returned by API).
    /// Once per post per app session.
    func logViewportVisible(post: CountryPost, surface: RecommendationSurface, position: Int?) {
        let key = "\(surface.rawValue):\(post.id)"
        guard viewportLogged.insert(key).inserted else { return }
        var meta: [String: String] = [
            "surface": surface.rawValue,
            "policyVersion": surface.policy.policyVersion,
            "exposure": "viewport",
        ]
        if let position { meta["position"] = "\(position)" }
        EngagementTracker.shared.enqueueRecommendationEvent(
            type: "viewport_visible",
            contentId: post.id,
            authorId: post.authorID,
            surface: surface.rawValue,
            meta: meta
        )
    }
}
