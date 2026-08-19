import Foundation

// MARK: - Recommendation surface policy (RecSys Phase 0)
//
// From `social_recommendation_engineering_roadmap.md`:
// each feed surface is an explicit policy over shared primitives —
// not a pile of scattered if-statements.

/// Product surfaces that own their own candidate mix, objectives, and constraints.
enum RecommendationSurface: String, Codable, CaseIterable, Sendable {
    case homeForYou = "home_for_you"
    case homeFollowing = "home_following"
    case sparks = "sparks"
    case hubsForYou = "hubs_for_you"
    case hubsFollowing = "hubs_following"
    case explore = "explore"
    case search = "search"
    case notifications = "notifications"
    case creatorSuggestions = "creator_suggestions"

    /// Human label for debug / logs.
    var displayName: String {
        switch self {
        case .homeForYou: return "Home · For you"
        case .homeFollowing: return "Home · Following"
        case .sparks: return MatteryaCopy.sparks
        case .hubsForYou: return "Hubs · For you"
        case .hubsFollowing: return "Hubs · Following"
        case .explore: return "Explore"
        case .search: return "Search"
        case .notifications: return "Notifications"
        case .creatorSuggestions: return "Creator suggestions"
        }
    }

    /// Policy configuration for this surface (deterministic Phase-0 baseline).
    var policy: RecommendationSurfacePolicy {
        switch self {
        case .homeForYou:
            return RecommendationSurfacePolicy(
                surface: self,
                primaryIntent: "relationship + discovery",
                candidateSources: [.following, .fresh, .explore, .sparksShare, .hubsShare, .exploration],
                pageSize: 24,
                prefetchThreshold: 0.65,
                explorationBudget: 0.06,
                maxSameCreatorInWindow: 2,
                creatorWindow: 8,
                preferUnviewed: true,
                allowRecycleWhenExhausted: true,
                latencyBudgetMs: 450
            )
        case .homeFollowing:
            return RecommendationSurfacePolicy(
                surface: self,
                primaryIntent: "recency + relationships",
                candidateSources: [.following],
                pageSize: 24,
                prefetchThreshold: 0.70,
                explorationBudget: 0,
                maxSameCreatorInWindow: 4,
                creatorWindow: 6,
                preferUnviewed: true,
                allowRecycleWhenExhausted: false,
                latencyBudgetMs: 350
            )
        case .sparks:
            return RecommendationSurfacePolicy(
                surface: self,
                primaryIntent: "high-throughput short-video discovery",
                candidateSources: [.explore, .fresh, .following, .exploration],
                pageSize: 80,
                prefetchThreshold: 0.75,
                explorationBudget: 0.08,
                maxSameCreatorInWindow: 1,
                creatorWindow: 6,
                preferUnviewed: true,
                allowRecycleWhenExhausted: true,
                latencyBudgetMs: 280
            )
        case .hubsForYou:
            return RecommendationSurfacePolicy(
                surface: self,
                primaryIntent: "long-form intent + commitment",
                candidateSources: [.explore, .fresh, .following, .exploration],
                pageSize: 32,
                prefetchThreshold: 0.70,
                explorationBudget: 0.05,
                maxSameCreatorInWindow: 2,
                creatorWindow: 10,
                preferUnviewed: true,
                allowRecycleWhenExhausted: true,
                latencyBudgetMs: 400
            )
        case .hubsFollowing:
            return RecommendationSurfacePolicy(
                surface: self,
                primaryIntent: "followed channels, newest first",
                candidateSources: [.following],
                pageSize: 24,
                prefetchThreshold: 0.70,
                explorationBudget: 0,
                maxSameCreatorInWindow: 3,
                creatorWindow: 8,
                preferUnviewed: true,
                allowRecycleWhenExhausted: false,
                latencyBudgetMs: 350
            )
        case .explore:
            return RecommendationSurfacePolicy(
                surface: self,
                primaryIntent: "breadth / novel discovery",
                candidateSources: [.explore, .fresh, .trending, .exploration],
                pageSize: 30,
                prefetchThreshold: 0.65,
                explorationBudget: 0.12,
                maxSameCreatorInWindow: 1,
                creatorWindow: 10,
                preferUnviewed: true,
                allowRecycleWhenExhausted: true,
                latencyBudgetMs: 500
            )
        case .search, .notifications, .creatorSuggestions:
            return RecommendationSurfacePolicy(
                surface: self,
                primaryIntent: "high-precision intent",
                candidateSources: [.explore],
                pageSize: 20,
                prefetchThreshold: 0.80,
                explorationBudget: 0.02,
                maxSameCreatorInWindow: 3,
                creatorWindow: 8,
                preferUnviewed: false,
                allowRecycleWhenExhausted: false,
                latencyBudgetMs: 300
            )
        }
    }
}

/// Candidate generators that may contribute to a surface (Phase 0 names).
enum RecommendationCandidateSource: String, Codable, Sendable {
    case following
    case fresh
    case explore
    case trending
    case sparksShare
    /// Home feed Hubs long-form / `__hub_origin__|` shares (16:9 + Hubs badge).
    case hubsShare
    case exploration
    case socialProof
    case editorial
}

/// Explicit policy object — one place for page size, diversity, exploration, latency.
struct RecommendationSurfacePolicy: Sendable {
    var surface: RecommendationSurface
    var primaryIntent: String
    var candidateSources: [RecommendationCandidateSource]
    var pageSize: Int
    /// Fraction of list height at which client should prefetch next page.
    var prefetchThreshold: Double
    /// Fraction of slots reserved for exploration / new-item cold start (0…1).
    var explorationBudget: Double
    /// Soft constraint: max times one creator may appear in a sliding window.
    var maxSameCreatorInWindow: Int
    var creatorWindow: Int
    var preferUnviewed: Bool
    var allowRecycleWhenExhausted: Bool
    /// Soft client budget for ranking assembly (ms). Logged for observability.
    var latencyBudgetMs: Int

    var policyVersion: String { "phase0.v1" }
}

// MARK: - Scored candidate (retrieval → rank → re-rank)

struct RecommendationCandidate: Identifiable, Sendable {
    var id: String { post.id }
    var post: CountryPost
    var sources: [RecommendationCandidateSource]
    /// Higher is better (pre-policy).
    var baseScore: Double
    var retrievalReason: String

    init(
        post: CountryPost,
        sources: [RecommendationCandidateSource],
        baseScore: Double = 0,
        retrievalReason: String = ""
    ) {
        self.post = post
        self.sources = sources
        self.baseScore = baseScore
        self.retrievalReason = retrievalReason
    }
}
