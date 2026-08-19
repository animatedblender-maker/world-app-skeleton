import Foundation

// MARK: - Constrained re-ranker (RecSys Phase 0)
//
// Heavy ranker scores items independently; this optimizes the *list*:
// creator diversity, novelty, exploration budget, hard eligibility.
// Greedy constrained re-rank from the recommendation roadmap §10.
//
// **Off-main safe:** pure value transforms + SparkDiscoveryEngine (NSLock).
// Called from `HomeFeedStore.rankForSessionAsync` via `Task.detached`.

enum FeedCompositionEngine {
    /// Assemble a page from ranked candidates under surface policy.
    /// - Parameters:
    ///   - candidates: pre-scored / pre-ordered pool (following first, then discovery, …)
    ///   - policy: surface policy
    ///   - blockedAuthorIDs: hard eligibility (blocks/mutes)
    ///   - alreadyServedIDs: session / page de-dupe
    ///   - followingIDs: relationship boost context
    static func compose(
        candidates: [CountryPost],
        policy: RecommendationSurfacePolicy,
        blockedAuthorIDs: Set<String> = [],
        alreadyServedIDs: Set<String> = [],
        followingIDs: Set<String> = [],
        limit: Int? = nil,
        sessionSeed: UInt64 = 0
    ) -> [CountryPost] {
        let pageLimit = max(1, limit ?? policy.pageSize)
        let scored = scoreCandidates(
            candidates,
            policy: policy,
            blockedAuthorIDs: blockedAuthorIDs,
            alreadyServedIDs: alreadyServedIDs,
            followingIDs: followingIDs,
            sessionSeed: sessionSeed
        )
        return greedyRerank(scored, policy: policy, limit: pageLimit).map(\.post)
    }

    /// Same as `compose` but returns candidates with source attribution for decision logs.
    static func composeDetailed(
        candidates: [CountryPost],
        policy: RecommendationSurfacePolicy,
        blockedAuthorIDs: Set<String> = [],
        alreadyServedIDs: Set<String> = [],
        followingIDs: Set<String> = [],
        limit: Int? = nil,
        sessionSeed: UInt64 = 0
    ) -> [RecommendationCandidate] {
        let pageLimit = max(1, limit ?? policy.pageSize)
        let scored = scoreCandidates(
            candidates,
            policy: policy,
            blockedAuthorIDs: blockedAuthorIDs,
            alreadyServedIDs: alreadyServedIDs,
            followingIDs: followingIDs,
            sessionSeed: sessionSeed
        )
        return greedyRerank(scored, policy: policy, limit: pageLimit)
    }

    // MARK: - Eligibility + base score

    private static func scoreCandidates(
        _ candidates: [CountryPost],
        policy: RecommendationSurfacePolicy,
        blockedAuthorIDs: Set<String>,
        alreadyServedIDs: Set<String>,
        followingIDs: Set<String>,
        sessionSeed: UInt64 = 0
    ) -> [RecommendationCandidate] {
        var out: [RecommendationCandidate] = []
        var seen = Set<String>()
        let now = Date().timeIntervalSince1970

        for (index, post) in candidates.enumerated() {
            guard seen.insert(post.id).inserted else { continue }
            if alreadyServedIDs.contains(post.id) { continue }
            // Hard eligibility: blocked/muted authors (caller supplies set — MainActor-safe).
            if blockedAuthorIDs.contains(post.authorID) { continue }

            // Surface format gates.
            switch policy.surface {
            case .sparks:
                guard ReelsRankingEngine.isSparkEligible(post) || post.hasVideo || post.playableVideoURL != nil
                else { continue }
            case .hubsForYou, .hubsFollowing:
                guard !post.isReel, post.hasVideo || post.playableVideoURL != nil || post.isHubSeedVideo
                else { continue }
            case .homeForYou, .homeFollowing, .explore:
                guard !post.isStory else { continue }
            default:
                break
            }

            let viewed = SparkDiscoveryEngine.isViewed(post)
            if policy.preferUnviewed, viewed, !policy.allowRecycleWhenExhausted {
                continue
            }

            var sources: [RecommendationCandidateSource] = []
            var score = 1.0 - Double(index) * 0.001 // preserve incoming order as weak prior

            if followingIDs.contains(post.authorID) {
                sources.append(.following)
                // Soft boost — hard +2.5 pinned every follow to the same head forever.
                score += 1.35
            }
            // Per-session jitter so the same candidate pool never freezes into one order.
            if sessionSeed != 0 {
                score += sessionJitter(postID: post.id, seed: sessionSeed)
            }
            if let created = post.createdDate {
                let ageHours = max(0, now - created.timeIntervalSince1970) / 3600
                if ageHours < 24 {
                    sources.append(.fresh)
                    score += max(0, 1.2 - ageHours / 24)
                }
            }
            if post.isSparkFeedShare || post.isReel || PlayPlatformBridge.isSparkFeedCard(post) {
                sources.append(.sparksShare)
            }
            // Hubs-badge cards must compete with Sparks density on Home.
            if PlayPlatformBridge.isHubFeedCardVideo(post)
                || PlayPlatformBridge.isHubOriginShare(post)
                || post.isHubOriginFeedShare {
                sources.append(.hubsShare)
                score += 0.95
            }
            if sources.isEmpty {
                sources.append(.explore)
            }
            if policy.preferUnviewed, !viewed {
                score += 1.5
            } else if viewed {
                score -= 3.0
            }

            // Exploration: slight boost for never-seen so cold items can enter.
            if policy.explorationBudget > 0, !viewed,
               !followingIDs.contains(post.authorID) {
                score += policy.explorationBudget * 0.8
                if !sources.contains(.exploration) {
                    sources.append(.exploration)
                }
            }

            out.append(
                RecommendationCandidate(
                    post: post,
                    sources: sources,
                    baseScore: score,
                    retrievalReason: sources.map(\.rawValue).joined(separator: ",")
                )
            )
        }
        // Prefer unviewed, but never starve the head to 1–2 cards (that hung the feed).
        if policy.preferUnviewed {
            let fresh = out.filter { !SparkDiscoveryEngine.isViewed($0.post) }
            let minHead = max(8, policy.pageSize / 3)
            if fresh.count >= minHead {
                out = fresh
            } else if !fresh.isEmpty {
                // Unviewed first, then keep scored viewed fillers so the list stays usable.
                let viewed = out.filter { SparkDiscoveryEngine.isViewed($0.post) }
                out = fresh + viewed
            } else if !policy.allowRecycleWhenExhausted {
                out = []
            }
            // else: library exhausted — keep low-score recycle candidates
        }
        return out.sorted { $0.baseScore > $1.baseScore }
    }

    // MARK: - Greedy list re-rank

    private static func greedyRerank(
        _ candidates: [RecommendationCandidate],
        policy: RecommendationSurfacePolicy,
        limit: Int
    ) -> [RecommendationCandidate] {
        guard !candidates.isEmpty else { return [] }
        var remaining = candidates
        var selected: [RecommendationCandidate] = []
        var selectedIDs = Set<String>()
        let exploreSlots = max(0, Int((Double(limit) * policy.explorationBudget).rounded()))
        var exploreUsed = 0

        while selected.count < limit, !remaining.isEmpty {
            var bestIndex: Int?
            var bestMarginal = -Double.infinity

            for (i, c) in remaining.enumerated() {
                if selectedIDs.contains(c.id) { continue }
                let marginal = marginalScore(
                    c,
                    selected: selected,
                    policy: policy,
                    exploreSlots: exploreSlots,
                    exploreUsed: exploreUsed
                )
                if marginal > bestMarginal {
                    bestMarginal = marginal
                    bestIndex = i
                }
            }

            guard let idx = bestIndex else { break }
            let pick = remaining.remove(at: idx)
            selected.append(pick)
            selectedIDs.insert(pick.id)
            let isExplore = !pick.sources.contains(.following)
                && pick.sources.contains(.exploration)
            if isExplore { exploreUsed += 1 }
        }

        return selected
    }

    private static func marginalScore(
        _ c: RecommendationCandidate,
        selected: [RecommendationCandidate],
        policy: RecommendationSurfacePolicy,
        exploreSlots: Int,
        exploreUsed: Int
    ) -> Double {
        var s = c.baseScore

        // Creator repetition penalty (soft constraint).
        let window = selected.suffix(max(1, policy.creatorWindow))
        let sameCreator = window.filter { $0.post.authorID == c.post.authorID }.count
        if sameCreator >= policy.maxSameCreatorInWindow {
            s -= 8.0
        } else if sameCreator > 0 {
            s -= Double(sameCreator) * 1.8
        }

        // Consecutive same author — hard soft-block.
        if let last = selected.last, last.post.authorID == c.post.authorID {
            s -= 5.0
        }

        // Near-duplicate body / media key.
        if let last = selected.last {
            if last.post.homeFeedContentKey == c.post.homeFeedContentKey {
                s -= 12.0
            }
        }

        // Exploration budget: prefer explore candidates while slots remain.
        let isExplore = !c.sources.contains(.following) && c.sources.contains(.exploration)
        if exploreSlots > 0 {
            if isExplore, exploreUsed < exploreSlots {
                s += 1.4
            } else if !isExplore, exploreUsed < exploreSlots, selected.count >= limitHint(policy) {
                // Leave room for exploration near page end.
                s -= 0.3
            }
        }

        // Novelty vs recently viewed (session / origin key).
        if SparkDiscoveryEngine.isViewed(c.post) {
            s -= 2.5
        }

        // Format diversity: after a Spark streak, prefer a Hubs-badge card (and vice versa).
        if policy.surface == .homeForYou {
            let recent = selected.suffix(4)
            let sparkStreak = recent.filter {
                PlayPlatformBridge.isSparkFeedCard($0.post) || $0.post.isReel
            }.count
            let hubStreak = recent.filter {
                PlayPlatformBridge.isHubFeedCardVideo($0.post)
                    || PlayPlatformBridge.isHubOriginShare($0.post)
            }.count
            let isHub = PlayPlatformBridge.isHubFeedCardVideo(c.post)
                || PlayPlatformBridge.isHubOriginShare(c.post)
            let isSpark = PlayPlatformBridge.isSparkFeedCard(c.post) || c.post.isReel
            if isHub, sparkStreak >= 3 { s += 2.8 }
            if isSpark, hubStreak >= 2 { s += 1.2 }
            if isSpark, sparkStreak >= 3 { s -= 1.4 }
        }

        return s
    }

    private static func limitHint(_ policy: RecommendationSurfacePolicy) -> Int {
        max(1, policy.pageSize - max(1, Int(Double(policy.pageSize) * policy.explorationBudget)))
    }

    /// Deterministic 0…~1.8 noise from post id + session seed (stable within open, new each open).
    private static func sessionJitter(postID: String, seed: UInt64) -> Double {
        var h: UInt64 = seed ^ 0x9E3779B97F4A7C15
        for b in postID.utf8 {
            h = h &* 1_099_511_628_211 &+ UInt64(b)
        }
        h ^= h >> 33
        h &*= 0xFF51AFD7ED558CCD
        h ^= h >> 33
        return Double(h % 1_800) / 1_000.0
    }
}
