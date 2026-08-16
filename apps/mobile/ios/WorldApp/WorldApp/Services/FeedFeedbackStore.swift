import Foundation

// MARK: - Negative feedback for home ranking (RecSys Phase 0)
//
// Hide = remove this post from my feed (this device / account local + signal).
// Not interested = down-rank this post + author affinity penalty.

@MainActor
final class FeedFeedbackStore {
    static let shared = FeedFeedbackStore()

    private let hideKey = "feed.feedback.hidden.v1"
    private let notInterestedKey = "feed.feedback.not_interested.v1"
    private let authorPenaltyKey = "feed.feedback.author_penalty.v1"

    private(set) var hiddenPostIDs: Set<String> = []
    private(set) var notInterestedPostIDs: Set<String> = []
    /// authorID → penalty strength 0…1 (higher = more suppressed)
    private(set) var authorPenalties: [String: Double] = [:]

    private init() {
        hiddenPostIDs = Set(UserDefaults.standard.stringArray(forKey: hideKey) ?? [])
        notInterestedPostIDs = Set(UserDefaults.standard.stringArray(forKey: notInterestedKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: authorPenaltyKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            authorPenalties = decoded
        }
    }

    func isHidden(_ postID: String) -> Bool {
        hiddenPostIDs.contains(postID) || notInterestedPostIDs.contains(postID)
    }

    func authorPenalty(for authorID: String) -> Double {
        authorPenalties[authorID] ?? 0
    }

    /// Hide this post from the feed (local + engagement signal).
    func hide(post: CountryPost) {
        guard !post.id.isEmpty else { return }
        hiddenPostIDs.insert(post.id)
        persist()
        EngagementTracker.shared.enqueueRecommendationEvent(
            type: "hide",
            contentId: post.id,
            authorId: post.authorID,
            surface: RecommendationSurface.homeForYou.rawValue,
            meta: ["action": "hide"]
        )
        SparkDiscoveryEngine.markImpressed(post.id)
    }

    /// Not interested — hide post and mildly suppress the creator.
    func notInterested(post: CountryPost) {
        guard !post.id.isEmpty else { return }
        notInterestedPostIDs.insert(post.id)
        hiddenPostIDs.insert(post.id)
        let prior = authorPenalties[post.authorID] ?? 0
        authorPenalties[post.authorID] = min(1, prior + 0.35)
        persist()
        EngagementTracker.shared.enqueueRecommendationEvent(
            type: "not_interested",
            contentId: post.id,
            authorId: post.authorID,
            surface: RecommendationSurface.homeForYou.rawValue,
            meta: [
                "action": "not_interested",
                "authorPenalty": String(format: "%.2f", authorPenalties[post.authorID] ?? 0),
            ]
        )
        SparkDiscoveryEngine.markImpressed(post.id)
    }

    func filterOutFeedback(_ posts: [CountryPost]) -> [CountryPost] {
        posts.filter { !isHidden($0.id) }
    }

    private func persist() {
        UserDefaults.standard.set(Array(hiddenPostIDs.prefix(2_000)), forKey: hideKey)
        UserDefaults.standard.set(Array(notInterestedPostIDs.prefix(2_000)), forKey: notInterestedKey)
        if let data = try? JSONEncoder().encode(authorPenalties) {
            UserDefaults.standard.set(data, forKey: authorPenaltyKey)
        }
    }
}

// MARK: - Home feed mode (legacy)

/// Dual chips removed — home is one Phase-0 recsys stream (`homeForYou` policy:
/// following priority + discovery). Kept as a thin alias for any residual call sites.
enum HomeFeedMode: String, CaseIterable, Identifiable, Sendable {
    case forYou

    var id: String { rawValue }
    var title: String { "Home" }
    var surface: RecommendationSurface { .homeForYou }
}
