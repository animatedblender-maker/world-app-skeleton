import Foundation
import Observation
import SwiftUI
import UIKit

/// Cursor page for home feed — opaque to the UI.
struct HomeFeedPage: Sendable {
    let items: [CountryPost]
    /// Opaque `before` cursor (ISO8601 createdAt of last item) for GraphQL `recentPosts(before:)`.
    let nextCursor: String?
    let hasMore: Bool
    let feedSessionId: String
}

/// Shadow card while a video (or video share) is uploading — pins to the top of the feed.
struct FeedUploadPlaceholder: Identifiable, Equatable {
    let id: String
    var caption: String
    var previewImage: UIImage?
    /// 0…1
    var progress: Double
    var phaseLabel: String
    var isHub: Bool
    var failedMessage: String?

    var progressText: String {
        if let failedMessage { return failedMessage }
        let pct = Int((min(1, max(0, progress)) * 100).rounded())
        return "\(phaseLabel) · \(pct)%"
    }
}

/// Home-feed state machine: cache → first page → prefetch → SWR.
/// Keeps heavy work out of `FeedView` (architecture phase 1–3 for this stage).
@MainActor
@Observable
final class HomeFeedStore {
    static let shared = HomeFeedStore()

    /// Full in-memory pool (not all rendered — `windowLimit` controls LazyVStack).
    private(set) var posts: [CountryPost] = []
    /// How many posts the list may render (window grows on scroll).
    private(set) var windowLimit = 8
    private(set) var isBootstrapping = true
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private(set) var errorMessage: String?
    private(set) var feedSessionId = UUID().uuidString
    /// True once we painted anything (cache/demo/network).
    private(set) var didPaint = false
    /// Uploading / sharing video shadows at the top of the feed.
    private(set) var pendingUploads: [FeedUploadPlaceholder] = []
    /// Single home surface — Phase-0 recsys (following priority + discovery in one stream).
    private let homeSurface: RecommendationSurface = .homeForYou

    private var nextCursor: String?
    /// Bumps cancel obsolete network merges / load-more.
    private var generation = 0
    private var pendingLoadMoreTask: Task<Void, Never>?
    /// True for the whole loadMore body — spinner `isLoadingMore` alone allowed parallel storms.
    private var loadMoreInFlight = false
    /// Architecture: if near-tail while in-flight, run one more page when the flight ends.
    private var loadMoreQueuedNearTail = false
    /// Coalesced delayed drain after fling-queued load-more (cells may not re-fire onAppear).
    private var pendingDrainTask: Task<Void, Never>?
    /// Empty thin/top-up pages (filtered viewed) — forceNetwork follow-ups per generation.
    private var emptyAppendRetriesThisGeneration = 0
    /// Endless Home: never stop retrying empty pages — only back off between attempts.
    private let maxEmptyAppendRetries = 10_000
    /// Bumps on every load-more finish (including empty) so FeedView's sentinel `.task` re-fires
    /// when `windowLimit` did not grow — otherwise the absolute bottom goes quiet forever.
    private(set) var endlessLoadEpoch = 0
    /// Architecture §5 — retry the same key after timeout; clear only on success.
    private var pendingFeedIdempotencyKey: String?
    /// Consecutive `/v1/feed` timeouts/500s on the same thin cursor.
    private var thinFeedFailStreak = 0
    /// After repeated thin failures, skip `/v1/feed` briefly and top up from Sparks/Hubs.
    private var thinFeedCoolUntil: Date?
    /// Soft recycle pass when unique network + catalog slices run dry — feed never ends.
    private var recyclePass = 0
    /// Retains block observer for `.scrollBudgetDidSettle`.
    private var scrollSettleObserver: NSObjectProtocol?
    /// New every app open / pull-to-refresh → different share mix.
    private var sessionRankSeed: UInt64 = UInt64.random(in: 1...UInt64.max)
    private var sessionFollowingIDs: Set<String> = []
    private var sessionMyUserID: String?
    /// True once the user has seen/scrolled a row this session — blocks head-replacing network merges.
    private var userEngagedThisSession = false
    /// Most recent on-screen row — soft-merge must pin through here so the watched card never vanishes.
    private var lastVisiblePostID: String?
    private var lastVisibleIndex: Int = 0
    /// Last open's head IDs — demoted on the next fresh session so Feed isn't identical every launch.
    private static let lastHeadDefaultsKey = "home.feed.lastHeadIDs.v2"
    /// Canonical @matterya welcome post — pin once at top until the user has seen it.
    private static let officialWelcomePostID = "afb52c5b-2218-4b78-afdf-b2b6f4327602"
    private static let officialWelcomeSeenKey = "matterya.home.officialWelcomeSeen.v1"
    private var cachedOfficialWelcome: CountryPost?

    /// Network page size — keep modest so ranking/merge stays off the scroll path.
    private let pageSize = 16
    private let windowPageSize = 10
    /// First paint window — ~1.5 screens; grow on scroll.
    private let firstWindow = 10
    /// Prefetch earlier so the tail never waits on network while scrolling.
    private let prefetchRatio = 0.40
    /// Request next batch when ~8 cards remain (settle lag + fling headroom).
    private let nearTailRemaining = 8
    /// Keep at least this many posts buffered in `posts` (beyond the visible window).
    private let minBufferedPool = 48

    private init() {
        scrollSettleObserver = NotificationCenter.default.addObserver(
            forName: .scrollBudgetDidSettle,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.drainQueuedLoadMoreIfNeeded()
            }
        }
    }

    private func refreshSessionRankingContext() async {
        sessionRankSeed = UInt64.random(in: 1...UInt64.max)
            ^ UInt64(Date().timeIntervalSince1970 * 1_000_000)
        sessionFollowingIDs = await FollowService.shared.followingIDs()
        sessionMyUserID = ContentCache.shared.cachedProfile()?.userID
            ?? AuthService.shared.currentUser?.id
    }

    /// Refresh follow/me ids without reshuffling session seed (stable head while watching).
    private func refreshFollowingContextOnly() async {
        sessionFollowingIDs = await FollowService.shared.followingIDs()
        sessionMyUserID = ContentCache.shared.cachedProfile()?.userID
            ?? AuthService.shared.currentUser?.id
    }

    /// Hide / not interested — remove from list + persist feedback.
    func applyNegativeFeedback(postID: String, kind: FeedNegativeKind) {
        guard let post = posts.first(where: { $0.id == postID }) else {
            // Still remove if already gone from pool but UI holds id.
            posts.removeAll { $0.id == postID }
            return
        }
        switch kind {
        case .hide:
            FeedFeedbackStore.shared.hide(post: post)
        case .notInterested:
            FeedFeedbackStore.shared.notInterested(post: post)
        }
        withAnimation(MatteryaMotion.insert) {
            posts.removeAll { $0.id == postID }
        }
    }

    enum FeedNegativeKind {
        case hide
        case notInterested
    }

    /// Session order + hard hide of already-viewed posts (open / reload / app open / load-more).
    /// Phase-0 recsys: unviewed → following first → discovery, then constrained re-rank.
    /// Heavy compose runs **off MainActor** when the pool is large (IG-class: never block scroll).
    private func rankForSession(_ posts: [CountryPost]) -> [CountryPost] {
        // Tiny pools stay sync (first paint / empty). Large pools should use `rankForSessionAsync`.
        if posts.count > 48 {
            // Fallback sync path if caller forgot async — still correct, just heavier.
            // Prefer `rankForSessionAsync` from load paths.
        }
        return rankForSessionSync(posts)
    }

    /// Off-main compose for network / load-more paths (never freezes UI on 80–200 candidates).
    private func rankForSessionAsync(_ posts: [CountryPost]) async -> [CountryPost] {
        let cleaned = FeedFeedbackStore.shared.filterOutFeedback(posts.dedupeHomeFeedContent())
        let surface = homeSurface
        let policy = surface.policy
        let following = sessionFollowingIDs
        let myUser = sessionMyUserID
        let seed = sessionRankSeed
        let blocked = Set(BlockService.shared.blocked.map(\.userID))
        let penalizedAuthors = Set(
            FeedFeedbackStore.shared.authorPenalties
                .filter { $0.value >= 0.85 }
                .map(\.key)
        )
        let blockedUnion = blocked.union(penalizedAuthors)
        let sessionId = feedSessionId
        let pageSize = policy.pageSize

        let local: [CountryPost] = await Task.detached(priority: .userInitiated) {
            let baseline = SparkDiscoveryEngine.sessionHomeFeedOrder(
                cleaned,
                followingIDs: following,
                myUserID: myUser,
                sessionSeed: seed
            )
            let composed = FeedCompositionEngine.compose(
                candidates: baseline,
                policy: policy,
                blockedAuthorIDs: blockedUnion,
                alreadyServedIDs: [],
                followingIDs: following,
                limit: max(baseline.count, pageSize),
                sessionSeed: seed
            )
            return composed.isEmpty ? baseline : composed
        }.value

        if !local.isEmpty {
            RecommendationDecisionLog.shared.logServedPage(
                surface: surface,
                requestID: sessionId,
                items: local.prefix(pageSize).enumerated().map { i, post in
                    RecommendationDecisionLog.ServedItem(
                        postID: post.id,
                        authorID: post.authorID,
                        sources: following.contains(post.authorID) ? ["following"] : ["explore"],
                        position: i
                    )
                }
            )
        }
        return local
    }

    private func rankForSessionSync(_ posts: [CountryPost]) -> [CountryPost] {
        let cleaned = FeedFeedbackStore.shared.filterOutFeedback(posts.dedupeHomeFeedContent())
        let surface = homeSurface
        let policy = surface.policy

        let baseline = SparkDiscoveryEngine.sessionHomeFeedOrder(
            cleaned,
            followingIDs: sessionFollowingIDs,
            myUserID: sessionMyUserID,
            sessionSeed: sessionRankSeed
        )

        let blocked = Set(BlockService.shared.blocked.map(\.userID))
        let penalizedAuthors = Set(
            FeedFeedbackStore.shared.authorPenalties
                .filter { $0.value >= 0.85 }
                .map(\.key)
        )
        let composed = FeedCompositionEngine.compose(
            candidates: baseline,
            policy: policy,
            blockedAuthorIDs: blocked.union(penalizedAuthors),
            alreadyServedIDs: [],
            followingIDs: sessionFollowingIDs,
            limit: max(baseline.count, policy.pageSize),
            sessionSeed: sessionRankSeed
        )
        let local = composed.isEmpty ? baseline : composed
        if !local.isEmpty {
            RecommendationDecisionLog.shared.logServedPage(
                surface: surface,
                requestID: feedSessionId,
                items: local.prefix(policy.pageSize).enumerated().map { i, post in
                    RecommendationDecisionLog.ServedItem(
                        postID: post.id,
                        authorID: post.authorID,
                        sources: sessionFollowingIDs.contains(post.authorID) ? ["following"] : ["explore"],
                        position: i
                    )
                }
            )
        }
        return local
    }

    /// After a network page lands, ask the server ranker to personalize order (scale path).
    /// Never blocks first paint — call from load paths in the background.
    /// While the user is watching, only reorders **below** the on-screen window.
    func applyServerRankIfPossible() async {
        let snapshot = posts
        guard snapshot.count >= 4 else { return }
        // Four-lane /v1/feed (v3 cursor, base64 "v3|" → "djN8") already mixes
        // spark/hub/image/text — server recsys re-rank would clump kinds again.
        if let cur = nextCursor, cur.hasPrefix("djN8") || cur.hasPrefix("djJ8") {
            return
        }
        // Engaged: never reshuffle anything the user can see (or just watched).
        let pinCount: Int
        if userEngagedThisSession {
            pinCount = pinnedPrefixCount(poolCount: snapshot.count)
            // Nothing useful to re-rank below a deep pin — skip the round-trip.
            if pinCount >= snapshot.count - 2 { return }
        } else {
            pinCount = min(6, snapshot.count)
        }
        let surface = homeSurface
        let ranked = await RecommendationClient.rankPosts(
            snapshot,
            surface: surface,
            sessionId: feedSessionId,
            followingIDs: sessionFollowingIDs,
            limit: min(snapshot.count, 100)
        )
        guard ranked.map(\.id) != snapshot.map(\.id) else { return }
        let head = Array(snapshot.prefix(pinCount))
        let headIDs = Set(head.map(\.id))
        let tail = ranked.filter { !headIDs.contains($0.id) }
        // Keep any local-only ids (non-UUID seeds) that server dropped.
        var used = headIDs.union(tail.map(\.id))
        let orphans = snapshot.filter { used.insert($0.id).inserted }
        let merged = head + tail + orphans
        guard merged.map(\.id) != snapshot.map(\.id) else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { posts = merged }
    }

    /// How many leading posts must stay frozen in place while the user is mid-watch.
    private func pinnedPrefixCount(poolCount: Int) -> Int {
        guard poolCount > 0 else { return 0 }
        // Freeze the full painted window + a couple ahead of the focused row.
        let byWindow = windowLimit
        let byFocus = lastVisibleIndex + 3
        return min(poolCount, max(byWindow, byFocus, firstWindow))
    }

    private func persistedLastHeadIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.lastHeadDefaultsKey) ?? []
    }

    /// Remember what the user just saw at the top so the next cold open can demote it.
    private func rememberDisplayedHead() {
        let ids = Array(displayedPosts.prefix(28).map(\.id))
        guard !ids.isEmpty else { return }
        var merged = ids
        for old in persistedLastHeadIDs() where !merged.contains(old) {
            merged.append(old)
            if merged.count >= 120 { break }
        }
        UserDefaults.standard.set(Array(merged.prefix(120)), forKey: Self.lastHeadDefaultsKey)
    }

    /// Put last-open head at the tail — API `/v1/feed` is newest-first and otherwise repeats.
    /// Image cards are hard-dropped (not demoted): they never get video `onViewed`, so without
    /// this the same Reddit photos resurface every refresh while videos rotate.
    private func demoteRecentHead(_ posts: [CountryPost]) -> [CountryPost] {
        let recent = Set(persistedLastHeadIDs())
        guard !recent.isEmpty else { return posts }
        var fresh: [CountryPost] = []
        var stale: [CountryPost] = []
        fresh.reserveCapacity(posts.count)
        for post in posts {
            if recent.contains(post.id) {
                if Self.isHomeImageCard(post) { continue }
                stale.append(post)
            } else {
                fresh.append(post)
            }
        }
        guard !fresh.isEmpty else { return posts }
        return fresh + stale
    }

    private static func isHomeImageCard(_ post: CountryPost) -> Bool {
        PlayPlatformBridge.isHomeImageCard(post)
    }

    /// On reshape: if page-1 is mostly last session's head, walk the cursor for new IDs.
    private func expandFreshHead(
        initial: [CountryPost],
        startingCursor: String?
    ) async -> (items: [CountryPost], cursor: String?) {
        var pooled = initial
        var cursor = startingCursor
        let recent = Set(persistedLastHeadIDs())
        let freshCount = pooled.filter { !recent.contains($0.id) }.count
        // Already enough new material — skip extra round-trips.
        if freshCount >= 20 || cursor == nil { return (pooled, cursor) }

        var seen = Set(pooled.map(\.id))
        for _ in 0..<8 {
            guard let cur = cursor, !cur.isEmpty else { break }
            guard let page = await SurfacePageClient.fetchHomeFeed(
                limit: 48,
                cursor: cur,
                session: feedSessionId
            ) else { break }
            cursor = page.nextCursor
            // Delivery ledger can return items=0 with next=true — keep walking.
            if page.items.isEmpty {
                if page.nextCursor == nil { break }
                continue
            }
            for post in page.items where seen.insert(post.id).inserted {
                pooled.append(post)
            }
            let fresh = pooled.filter { !recent.contains($0.id) }.count
            if fresh >= 20 { break }
            if page.nextCursor == nil { break }
        }
        return (pooled, cursor)
    }

    var displayedPosts: [CountryPost] {
        Array(posts.prefix(windowLimit))
    }

    var showsSkeleton: Bool {
        isBootstrapping && posts.isEmpty
    }

    // MARK: - Lifecycle

    /// New browsing session (app open / 5+ min away / pull).
    /// - Parameter forceReplace: pull-to-refresh / explicit reshuffle — rebuilds the whole list.
    ///   Default **false**: after the first paint, network only soft-merges so a late
    ///   first-paint response never rips out the row the user is already watching.
    ///
    /// Runs **detached** so SwiftUI `.task(id:)` cancellation (launch generation bump)
    /// cannot abort `/v1/feed` mid-flight and leave an empty feed.
    func beginFreshSession(forceReplace: Bool = false) async {
        let work = Task.detached(priority: .userInitiated) { @MainActor in
            await HomeFeedStore.shared.runFreshSession(forceReplace: forceReplace)
        }
        // If the caller is cancelled, still let work finish applying posts.
        _ = await work.result
    }

    /// App Store / Simulator capture seed — bypasses network wipe.
    func applyScreenshotSeed(_ seed: [CountryPost]) {
        guard ScreenshotMode.isActive, !seed.isEmpty else { return }
        feedSessionId = UUID().uuidString
        applyPosts(Array(seed.prefix(28)), replace: true, sessionId: feedSessionId, alreadyRanked: true)
        isBootstrapping = false
        didPaint = true
        isRefreshing = false
        hasMore = false
        errorMessage = nil
    }

    private func runFreshSession(forceReplace: Bool) async {
        generation += 1
        let gen = generation
        emptyAppendRetriesThisGeneration = 0
        endlessLoadEpoch = 0
        errorMessage = nil
        nextCursor = nil
        thinFeedFailStreak = 0
        thinFeedCoolUntil = nil
        hasMore = true
        let paintedBefore = didPaint && !posts.isEmpty
        // Only show refresh chrome when the list was already on screen (pull / reshape).
        isRefreshing = forceReplace && paintedBefore

        // Screenshot Mode: keep seeded posts; never replace with empty /v1/feed.
        if ScreenshotMode.isActive {
            if posts.isEmpty, let cached = ContentCache.shared.posts(for: .homeFeed), !cached.isEmpty {
                applyScreenshotSeed(cached)
            }
            isBootstrapping = false
            isRefreshing = false
            return
        }

        if forceReplace {
            // Snapshot on-screen head before wipe so Reddit image cards (no video
            // onViewed) are hard-excluded from the reshuffled pool.
            rememberDisplayedHead()
            for post in displayedPosts where Self.isHomeImageCard(post) {
                SparkDiscoveryEngine.markWatched(post)
            }
            userEngagedThisSession = false
            lastVisiblePostID = nil
            lastVisibleIndex = 0
            feedSessionId = UUID().uuidString
            recyclePass = 0
            windowLimit = firstWindow
            PostsService.shared.resetHomeFeedSparkPager()
            // Keep disk cache for instant paint — overwrite after thin succeeds.
            SparkDiscoveryEngine.beginNewBrowseSession()
            sessionRankSeed = UInt64.random(in: 1...UInt64.max)
                ^ UInt64(Date().timeIntervalSince1970 * 1_000_000)
        } else if posts.isEmpty {
            feedSessionId = UUID().uuidString
            sessionRankSeed = UInt64.random(in: 1...UInt64.max)
                ^ UInt64(Date().timeIntervalSince1970 * 1_000_000)
        }

        // 1) Instant disk paint — never wait on GraphQL / Frame0 / strip discover.
        if posts.isEmpty || forceReplace {
            if let cached = ContentCache.shared.posts(for: .homeFeed) {
                let pool = Self.liveOnlyPosts(
                    BlockService.shared.filterPosts(cached.excludingMoments().forHomeFeed())
                )
                if !pool.isEmpty {
                    // Demote last open's head so cache paint isn't a carbon copy every launch.
                    let ranked = Self.weaveWrittenAmongMedia(
                        demoteRecentHead(rankForSessionSync(pool))
                    )
                    applyPosts(
                        Array(ranked.prefix(24)),
                        replace: true,
                        sessionId: feedSessionId,
                        alreadyRanked: true
                    )
                    isBootstrapping = false
                    didPaint = true
                    isRefreshing = false
                    Task { await warmHead(lite: true) }
                } else if posts.isEmpty {
                    isBootstrapping = true
                }
            } else if posts.isEmpty {
                isBootstrapping = true
            }
        }

        // 2) Thin feed only on the critical path (following refresh off-path).
        Task(priority: .utility) { await self.refreshFollowingContextOnly() }
        // Fresh session: wider first page + session id so server rotates the mix.
        let thinLimit = forceReplace ? 48 : 24
        let thin = await SurfacePageClient.fetchHomeFeed(
            limit: thinLimit,
            cursor: nil,
            session: feedSessionId
        )
        guard gen == generation else {
            isRefreshing = false
            return
        }

        if let thin {
            nextCursor = thin.nextCursor
            var livePool = thin.items
            // items=0 + nextCursor = delivery-ledger exhausted window — walk before GraphQL.
            if livePool.isEmpty, thin.nextCursor != nil {
                let expanded = await expandFreshHead(initial: [], startingCursor: thin.nextCursor)
                livePool = expanded.items
                if let cur = expanded.cursor { nextCursor = cur }
            } else if forceReplace, !livePool.isEmpty {
                let expanded = await expandFreshHead(initial: livePool, startingCursor: thin.nextCursor)
                livePool = expanded.items
                if let cur = expanded.cursor { nextCursor = cur }
            }
            if !livePool.isEmpty {
                var rankedFast = Self.liveOnlyPosts(livePool)
                if rankedFast.isEmpty { rankedFast = livePool }
                // Always session-rank on a fresh open so the head isn't identical every launch.
                if forceReplace || !paintedBefore {
                    rankedFast = demoteRecentHead(rankForSessionSync(rankedFast))
                }
                let head = Array(rankedFast.prefix(forceReplace ? 36 : 24))
                if !head.isEmpty {
                    // Never yank the list under a mid-scroll finger — cache may have
                    // painted, user scrolled, then thin network returned with forceReplace.
                    let scrolling =
                        userEngagedThisSession || ScrollBudget.isFlinging
                    if scrolling {
                        await softMergePreservingHead(head)
                    } else if forceReplace || !paintedBefore {
                        applyPosts(head, replace: true, sessionId: feedSessionId, alreadyRanked: true)
                        ContentCache.shared.setPosts(posts, for: .homeFeed)
                        rememberDisplayedHead()
                    } else {
                        await softMergePreservingHead(head)
                    }
                    isBootstrapping = false
                    didPaint = true
                    hasMore = true
                    Task { await warmHead(lite: true) }
                }
            }
        }
        if posts.isEmpty {
            // Surface Sparks only — never GraphQL discover stampede on cold open (-1001 storm).
            let sparkPage = await SurfacePageClient.fetchSparks(limit: 40)
            let liveRaw = sparkPage?.items ?? []
            if let cur = sparkPage?.nextCursor { nextCursor = cur }
            guard gen == generation else {
                isRefreshing = false
                return
            }
            let ranked = Self.weaveWrittenAmongMedia(
                demoteRecentHead(rankForSessionSync(Self.liveOnlyPosts(liveRaw)))
            )
            if !ranked.isEmpty {
                applyPosts(Array(ranked.prefix(36)), replace: true, sessionId: feedSessionId, alreadyRanked: true)
                ContentCache.shared.setPosts(posts, for: .homeFeed)
                rememberDisplayedHead()
                didPaint = true
                hasMore = true
                Task { await warmHead(lite: true) }
            }
        }

        isBootstrapping = false
        isRefreshing = false
        recyclePass = 0

        // 3) Heavy work AFTER first paint + autoplay unlock — never AV under splash.
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            // Wait until cold-open gate opens (or give up after ~4s).
            for _ in 0..<40 {
                if FeedVideoFocus.shared.allowsFeedAVWarm { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard FeedVideoFocus.shared.allowsFeedAVWarm else { return }
            guard gen == self.generation else { return }
            await self.warmHead(lite: false)
            let exclude = Set(self.posts.map(\.id))
            async let sparkTop = PostsService.shared.homeFeedSparkTopUp(
                excluding: exclude,
                limit: 16,
                forceRefresh: false
            )
            async let hubTop = PostsService.shared.homeFeedHubTopUp(
                excluding: exclude,
                limit: 6,
                forceRefresh: false
            )
            // No text top-up on the hot path — Home stays Sparks/Hubs-smooth; rare text comes from thin feed.
            let extra = (await sparkTop) + (await hubTop)
            guard gen == self.generation else { return }
            if !extra.isEmpty {
                await self.softMergePreservingHead(extra)
            }
            if self.posts.count < 16 {
                self.requestLoadMore()
            }
            await self.ensureBufferedPool()
        }
    }

    /// Keep a deep post pool so scroll rarely hits "loading more".
    func ensureBufferedPool() async {
        var guardPasses = 0
        var stagnant = 0
        var lastCount = posts.count
        // Endless Home: keep walking until the buffer is deep or generation changes.
        while posts.count < minBufferedPool, hasMore, guardPasses < 12 {
            guardPasses += 1
            let gen = generation
            // Force network — don't only expand the local window.
            await loadMore(generation: gen, forceNetwork: true)
            guard gen == generation else { return }
            if posts.count <= lastCount {
                stagnant += 1
                // Brief pause then keep going — empty thin/viewed pages are transient.
                if stagnant >= 2 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                if stagnant >= 8 { break }
            } else {
                stagnant = 0
                lastCount = posts.count
            }
        }
    }

    /// Weave network rows under the live on-screen window.
    /// Mid-watch: never reorder or drop pinned posts (marking watched used to send the
    /// focused card to the viewed tail and replace it with strangers).
    private func softMergePreservingHead(_ incoming: [CountryPost]) async {
        let clean = Self.liveOnlyPosts(
            BlockService.shared.filterPosts(incoming.excludingMoments().forHomeFeed())
        )
        guard !clean.isEmpty else { return }

        // Already painted: never full-replace (re-rank stacked every written card on top).
        // Pin the live list; weave newcomers into the tail (~1 written / 3–4 media).
        if !posts.isEmpty {
            let pinCount = userEngagedThisSession
                ? pinnedPrefixCount(poolCount: posts.count)
                : posts.count
            let head = Array(posts.prefix(pinCount))
            let below = Array(posts.dropFirst(pinCount))
            var seen = Set(head.map(\.id))
            var contentKeys = Set(head.map(\.homeFeedContentKey))

            var preservedBelow: [CountryPost] = []
            for post in below where seen.insert(post.id).inserted {
                contentKeys.insert(post.homeFeedContentKey)
                preservedBelow.append(post)
            }

            var newcomers: [CountryPost] = []
            for post in clean {
                guard seen.insert(post.id).inserted else { continue }
                guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
                // Never append watched videos — written/text stay eligible.
                if SparkDiscoveryEngine.isViewed(post),
                   !(PlayPlatformBridge.isWrittenHomePost(post) && !Self.isHomeImageCard(post)) {
                    continue
                }
                newcomers.append(post)
            }
            let cleanedBelow = preservedBelow.filter {
                (PlayPlatformBridge.isWrittenHomePost($0) && !Self.isHomeImageCard($0))
                    || !SparkDiscoveryEngine.isViewed($0)
            }
            let wovenNew = Self.weaveWrittenAmongMedia(newcomers)

            let merged = head + cleanedBelow + wovenNew
            guard merged.map(\.id) != posts.map(\.id) else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { posts = merged }
            hasMore = true
            ContentCache.shared.setPosts(
                Array(posts.prefix(ContentCache.maxCachedPosts)),
                for: .homeFeed
            )
            return
        }

        // Truly empty: first paint from this merge — weave, don't score-stack written.
        let ranked = await rankForSessionAsync(clean)
        let woven = Self.weaveWrittenAmongMedia(ranked.filter {
            (PlayPlatformBridge.isWrittenHomePost($0) && !Self.isHomeImageCard($0))
                || !SparkDiscoveryEngine.isViewed($0)
        })
        guard !woven.isEmpty else { return }

        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts = woven
            windowLimit = min(windowLimit, max(firstWindow, min(posts.count, firstWindow)))
        }
        hasMore = true
        ContentCache.shared.setPosts(
            Array(posts.prefix(ContentCache.maxCachedPosts)),
            for: .homeFeed
        )
    }

    /// Home mix family — ShortForm Sparks vs TikTok vs Hubs vs image (variety weave).
    private enum HomeFeedKind: Equatable {
        case shortform, tiktok, hub, image, text

        static func classify(_ post: CountryPost) -> HomeFeedKind {
            if PlayPlatformBridge.isWrittenHomePost(post) {
                let mt = (post.mediaType ?? "").lowercased()
                if mt == "image" || mt == "photo" || mt == "gif" || post.feedImageURL != nil {
                    return .image
                }
                return .text
            }
            if PlayPlatformBridge.isHubFeedCardVideo(post)
                || PlayPlatformBridge.isHubCatalogContent(post)
                || post.externalRefType?.lowercased() == "hub" {
                return .hub
            }
            let mt = (post.mediaType ?? "").lowercased()
            if mt == "image" || mt == "photo" || mt == "gif" || (post.hasImage && !post.hasVideo) {
                return .image
            }
            let blob = [
                post.mediaURL ?? "",
                post.mediaPayload?.r2Key ?? "",
                post.thumbURL ?? "",
            ]
            .joined(separator: " ")
            .lowercased()
            if blob.contains("/shortform/") { return .shortform }
            if blob.contains("/longform/") { return .hub }
            if blob.contains("/posts/") { return .image }
            // TikTok country-root packs: Country/<digits>/…
            if blob.range(of: #"(united_states|germany|albania|egypt|kosovo)/\d{8,}"#, options: .regularExpression) != nil {
                return .tiktok
            }
            return .tiktok
        }
    }

    /// Variety weave: ShortForm Sparks appear often between hubs/images/TikTok —
    /// never stack the same family back-to-back when alternatives exist.
    private static func weaveWrittenAmongMedia(_ posts: [CountryPost]) -> [CountryPost] {
        guard posts.count > 1 else { return posts }
        var shortform: [CountryPost] = []
        var tiktok: [CountryPost] = []
        var hub: [CountryPost] = []
        var image: [CountryPost] = []
        var text: [CountryPost] = []
        for p in posts {
            switch HomeFeedKind.classify(p) {
            case .shortform: shortform.append(p)
            case .tiktok: tiktok.append(p)
            case .hub: hub.append(p)
            case .image: image.append(p)
            case .text: text.append(p)
            }
        }

        // Prefer ShortForm twice as often as TikTok in the rotation.
        let rotation: [HomeFeedKind] = [
            .shortform, .hub, .image, .shortform, .tiktok, .hub, .image,
        ]
        var queues: [HomeFeedKind: [CountryPost]] = [
            .shortform: shortform,
            .tiktok: tiktok,
            .hub: hub,
            .image: image,
            .text: text,
        ]
        var out: [CountryPost] = []
        out.reserveCapacity(posts.count)
        var rot = 0
        var guardCount = 0
        var prev: HomeFeedKind?

        func take(_ kind: HomeFeedKind) -> CountryPost? {
            guard var q = queues[kind], !q.isEmpty else { return nil }
            let post = q.removeFirst()
            queues[kind] = q
            return post
        }

        while out.count < posts.count, guardCount < posts.count * 8 {
            guardCount += 1
            let prefer = rotation[rot % rotation.count]
            rot += 1
            var picked: CountryPost?
            if prefer != prev {
                picked = take(prefer)
            }
            if picked == nil {
                for kind in [HomeFeedKind.shortform, .hub, .image, .tiktok, .text] where kind != prev {
                    if let p = take(kind) {
                        picked = p
                        prev = kind
                        break
                    }
                }
            }
            if picked == nil {
                for kind in [HomeFeedKind.shortform, .hub, .image, .tiktok, .text] {
                    if let p = take(kind) {
                        picked = p
                        prev = kind
                        break
                    }
                }
            }
            guard let post = picked else { break }
            prev = HomeFeedKind.classify(post)
            out.append(post)
        }
        return out.isEmpty ? posts : out
    }

    /// Smooth open: cache → tiny first-paint network → done.
    /// Never multi-page GraphQL or hubs catalog on this path.
    /// Prefer `beginFreshSession()` when the user should see a **new** mix.
    func bootstrap(forceRefresh: Bool = false) async {
        generation += 1
        let gen = generation
        emptyAppendRetriesThisGeneration = 0
        errorMessage = nil

        if forceRefresh {
            isRefreshing = true
            defer { isRefreshing = false }
            await hardRefresh(generation: gen)
            return
        }

        await refreshSessionRankingContext()

        // 1) Instant paint from cache (sign-in / relaunch must not wait on network).
        if posts.isEmpty, let cached = ContentCache.shared.posts(for: .homeFeed), !cached.isEmpty {
            let clean = Self.liveOnlyPosts(cached)
            if clean.isEmpty {
                ContentCache.shared.invalidate(.homeFeed)
            } else {
                // Off-main rank — sync compose on MainActor was first-paint hitch.
                let filtered = BlockService.shared.filterPosts(
                    clean.excludingMoments().forHomeFeed()
                )
                let ranked = await rankForSessionAsync(filtered)
                applyPosts(ranked, replace: true, sessionId: feedSessionId, alreadyRanked: true)
                isBootstrapping = false
                didPaint = true
                // Thumbs only until autoplay unlock — AV/Frame0 under splash freezes + ghost audio.
                Task { await warmHead(lite: true) }
            }
        }

        // 2) Thin surface page first — walk empty ledger pages; Sparks surface if still empty.
        // Never GraphQL discover on this path (cold-open -1001 stampede).
        let live: [CountryPost]
        let fromThin: Bool
        if let thin = await SurfacePageClient.fetchHomeFeed(limit: 28, cursor: nil, session: feedSessionId) {
            nextCursor = thin.nextCursor
            var pool = thin.items
            if pool.isEmpty, let cur = thin.nextCursor {
                let expanded = await expandFreshHead(initial: [], startingCursor: cur)
                pool = expanded.items
                if let c = expanded.cursor { nextCursor = c }
            }
            if !pool.isEmpty {
                live = Self.liveOnlyPosts(pool)
                fromThin = true
                #if DEBUG
                print("[HomeFeed] thin /v1/feed firstPaint=\(live.count)")
                #endif
            } else {
                let sparks = await SurfacePageClient.fetchSparks(limit: 40)
                live = Self.liveOnlyPosts(sparks?.items ?? [])
                if let c = sparks?.nextCursor { nextCursor = c }
                fromThin = false
                #if DEBUG
                print("[HomeFeed] sparks surface fallback firstPaint=\(live.count)")
                #endif
            }
        } else {
            let sparks = await SurfacePageClient.fetchSparks(limit: 40)
            live = Self.liveOnlyPosts(sparks?.items ?? [])
            if let c = sparks?.nextCursor { nextCursor = c }
            fromThin = false
        }
        guard gen == generation else { return }

        // If cache already painted (or user started watching), soft-merge only.
        if didPaint && !posts.isEmpty {
            await softMergePreservingHead(live)
            isBootstrapping = false
            hasMore = true
            recyclePass = 0
            #if DEBUG
            print("[HomeFeed] bootstrap soft-merge live=\(live.count) pool=\(posts.count)")
            #endif
        } else {
            let existingLive = posts.filter { !$0.isStory }
            let realBatch = Self.liveOnlyPosts(live + existingLive)
            // Variety weave: ShortForm Sparks between hubs/images/TikTok (no same-family stacks).
            let mixed = Self.weaveWrittenAmongMedia(realBatch)
            let capped: [CountryPost]
            if fromThin {
                capped = Array(mixed.prefix(min(mixed.count, 90)))
            } else {
                capped = Array((await rankForSessionAsync(mixed)).prefix(min(mixed.count, 90)))
            }

            if !capped.isEmpty {
                applyPosts(capped, replace: true, sessionId: feedSessionId, alreadyRanked: true)
                ContentCache.shared.setPosts(posts, for: .homeFeed)
                didPaint = true
                Task { await warmHead(lite: true) }
                hasMore = true
                recyclePass = 0
                #if DEBUG
                print("[HomeFeed] firstPaint total=\(capped.count) network=\(live.count) thin=\(fromThin)")
                #endif
            } else if posts.isEmpty {
                applyPosts([], replace: true, sessionId: feedSessionId)
                ContentCache.shared.invalidate(.homeFeed)
                hasMore = true
            }
        }

        isBootstrapping = false

        // Server recsys rank (personalization) after first paint — never blocks open.
        Task { await applyServerRankIfPossible() }

        // 3) Warm a light Sparks catalog off the critical path so scroll has R2 fuel.
        // Deep (thousands) expands on demand in load-more — never block first paint.
        Task(priority: .utility) {
            _ = await PostsService.shared.loadSparksDiscoveryCatalog(forceRefresh: false, deep: false)
        }
    }

    /// Drop offline Reddit / catalog fakes; keep real UUID-backed posts only
    /// (includes DE Million Post Corpus seeds + their comments).
    /// **Keeps R2 Sparks** — they render as SparkFeedCard on the main feed.
    /// Hard-exclude watched **videos** — written/text posts are not “watched clips”.
    private static func liveOnlyPosts(_ posts: [CountryPost]) -> [CountryPost] {
        // NSFW never on Home — R2 adult packs route to Masquerade secrets.
        let base = posts
            .excludingDeletedPosts()
            .forHomeFeed()
            .filter { !$0.isAdultContent }
            // Home: drop pure text/written cards (forum corpus freezes scroll). Keep images + video.
            .filter { post in
                let mt = (post.mediaType ?? "").lowercased()
                if mt == "none" || mt == "text" { return false }
                let hasMedia =
                    post.hasVideo
                    || post.hasImage
                    || post.feedImageURL != nil
                    || post.playableVideoURL != nil
                    || mt == "image" || mt == "photo" || mt == "gif"
                    || mt == "video" || mt == "reel" || mt == "spark"
                if hasMedia { return true }
                // Body-only written post with no attachment.
                return !PlayPlatformBridge.isWrittenHomePost(post)
            }
        guard !base.isEmpty else { return [] }
        return base.filter { post in
            // Pure text/written can resurface; Home image cards (Reddit stills) follow
            // the same once-seen rule as videos once EngagementTracker marks them.
            if PlayPlatformBridge.isWrittenHomePost(post), !isHomeImageCard(post) {
                return true
            }
            return !SparkDiscoveryEngine.isViewed(post)
        }
    }

    /// After a meaningful watch: drop this clip from upcoming Home rows (keep on-screen pin).
    func noteClipWatched(_ post: CountryPost) {
        let keys = Set(SparkDiscoveryEngine.discoveryKeys(for: post))
        guard !keys.isEmpty, !posts.isEmpty else { return }
        let pin = pinnedPrefixCount(poolCount: posts.count)
        let head = Array(posts.prefix(pin))
        var seen = Set(head.map(\.id))
        var rest: [CountryPost] = []
        for p in posts.dropFirst(pin) {
            guard seen.insert(p.id).inserted else { continue }
            if keys.contains(p.id) || SparkDiscoveryEngine.isViewed(p) { continue }
            rest.append(p)
        }
        let next = head + rest
        guard next.map(\.id) != posts.map(\.id) else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { posts = next }
    }

    // MARK: - Scroll / prefetch

    /// Call from row `onAppear`. Prefetches media and next page at 65%.
    /// Fast fling: grow the local window aggressively, skip heavy network work until scroll settles.
    /// Call when leaving the Feed tab / backgrounding — locks this open's head for next demote.
    func noteSessionPaused() {
        rememberDisplayedHead()
    }

    func onRowAppear(post: CountryPost) {
        ScrollBudget.noteCellAppear()
        // Any row appear counts as engagement — late network must not remount the head.
        userEngagedThisSession = true
        guard let index = displayedPosts.firstIndex(where: { $0.id == post.id }) else { return }
        lastVisiblePostID = post.id
        lastVisibleIndex = index
        // Once they scroll past the @matterya welcome, stop pinning it on later opens.
        if index > 0 {
            markOfficialWelcomeSeenIfNeeded(visiblePostID: post.id)
        }

        // True exposure (viewport) — stronger label than "returned by ranking".
        // Dwell/skip still come from FeedView appear/disappear.
        RecommendationDecisionLog.shared.logViewportVisible(
            post: post,
            surface: .homeForYou,
            position: index
        )

        let fling = ScrollBudget.isFlinging
        // During a fling, jump the window ahead so LazyVStack always has cells ready.
        let growBy = fling ? windowPageSize * 2 : windowPageSize
        let growWhenWithin = fling ? 8 : nearTailRemaining
        let remainingDisplayed = max(0, displayedPosts.count - index - 1)
        let nearTail = remainingDisplayed <= growWhenWithin

        if nearTail, windowLimit < posts.count {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                windowLimit = min(posts.count, windowLimit + growBy)
            }
            // Local pool may still grow via network / R2 — never mark exhausted here.
            hasMore = true
        }

        // Thumbs + Frame0; AV warm on video queue so autoplay is instant.
        let thumbAhead = fling ? 2 : 5
        let end = min(displayedPosts.count, index + thumbAhead)
        if index < end {
            let window = Array(displayedPosts[index..<end])
            // Photos warm at ≥540 inside prefetchFeedMedia; this size is video posters only.
            ImageCache.shared.prefetchFeedMedia(window, maxPixelSize: fling ? 320 : 720)
            if !fling {
                Task(priority: .utility) {
                    await Frame0PosterResolver.shared.prefetch(
                        postIDs: Array(window.prefix(4).map(\.id))
                    )
                }
            }
        }

        // Warm focused video + ahead (video queue only). Runs mid-fling too (pool flingProtect).
        let videos = Self.feedWarmVideoQueue(from: displayedPosts)
        if let warmIdx = Self.feedWarmIndex(
            for: post,
            in: videos,
            feedIndex: index,
            feed: displayedPosts
        ) {
            SparkWarmPool.shared.prepareFeedWindow(posts: videos, around: warmIdx)
        }

        // Don't kick network load-more mid-fling (causes hitch + image storms).
        guard !fling else {
            if nearTail || posts.count < minBufferedPool {
                loadMoreQueuedNearTail = true
                scheduleDrainQueuedLoadMore(afterMs: 400, forceNearTailRetry: true)
            }
            return
        }

        // Architecture: next batch when ~3 remain — also keep min buffer and mid-pool top-up.
        let ratioThreshold = max(0, Int(Double(max(posts.count, 1)) * prefetchRatio) - 1)
        let poolNearExhaust = windowLimit >= max(0, posts.count - nearTailRemaining)
        if nearTail || poolNearExhaust || index >= ratioThreshold || posts.count < minBufferedPool {
            requestLoadMore()
        }
    }

    /// Drain load-more that was queued mid-fling / mid-flight after settle.
    /// Without this, LazyVStack may not re-fire onAppear at the stuck tail.
    func drainQueuedLoadMoreIfNeeded() {
        guard loadMoreQueuedNearTail, !loadMoreInFlight, !isBootstrapping else { return }
        loadMoreQueuedNearTail = false
        requestLoadMore()
    }

    /// Coalesced delayed drain — fling settle + empty sentinel don't always re-fire onAppear.
    private func scheduleDrainQueuedLoadMore(afterMs: UInt64, forceNearTailRetry: Bool = false) {
        pendingDrainTask?.cancel()
        let gen = generation
        let force = forceNearTailRetry
        pendingDrainTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: afterMs * 1_000_000)
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            self.drainQueuedLoadMoreIfNeeded()
            // Absolute pool tail after fling/in-flight queue — one forced network retry.
            if force, self.hasMore, !self.loadMoreInFlight, !self.isBootstrapping,
               self.windowLimit >= self.posts.count {
                let followGen = self.generation
                await self.loadMore(generation: followGen, forceNetwork: true)
            }
        }
    }

    func requestLoadMore() {
        // Local window still has room — just expand (handled in onRowAppear).
        if windowLimit < posts.count {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                windowLimit = min(posts.count, windowLimit + windowPageSize)
            }
            hasMore = true
            // If window is catching the pool tail, also kick network/R2 in parallel.
            if windowLimit >= posts.count - windowPageSize {
                // fall through to network
            } else {
                return
            }
        }
        // Single-flight: UncancellableHTTP ignores Task.cancel, so parallel loadMores
        // storm the same /v1/feed cursor until -1001.
        if loadMoreInFlight || isLoadingMore || isBootstrapping {
            loadMoreQueuedNearTail = true
            scheduleDrainQueuedLoadMore(afterMs: 400, forceNearTailRetry: true)
            return
        }
        hasMore = true
        let gen = generation
        pendingLoadMoreTask?.cancel()
        pendingLoadMoreTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.loadMore(generation: gen)
        }
        // Settle lag: drain any race-queued flag once (no forced double-fetch).
        scheduleDrainQueuedLoadMore(afterMs: 400, forceNearTailRetry: false)
    }

    // MARK: - Mutations from UI

    func applyLocalUpdate(_ post: CountryPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        }
    }

    func insertNewPost(_ post: CountryPost) {
        // Sparks allowed (shared sparks show as SparkFeedCard). Moments stay off the main feed.
        guard !post.isStory else { return }
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts.remove(at: index)
        }
        // Brand-new posts always pin to top; do not re-chronological-sort the whole feed.
        posts.insert(post, at: 0)
        windowLimit = max(windowLimit, firstWindow)
        ContentCache.shared.setPosts(posts, for: .homeFeed)
    }

    // MARK: - Upload shadow cards

    @discardableResult
    func beginVideoUpload(
        caption: String,
        previewImage: UIImage?,
        isHub: Bool
    ) -> String {
        let id = "upload-\(UUID().uuidString)"
        let placeholder = FeedUploadPlaceholder(
            id: id,
            caption: caption,
            previewImage: previewImage,
            progress: 0.02,
            phaseLabel: "Preparing",
            isHub: isHub,
            failedMessage: nil
        )
        pendingUploads.insert(placeholder, at: 0)
        windowLimit = max(windowLimit, firstWindow)
        return id
    }

    func updateVideoUpload(id: String, progress: Double, phaseLabel: String) {
        guard let index = pendingUploads.firstIndex(where: { $0.id == id }) else { return }
        pendingUploads[index].progress = min(1, max(0, progress))
        pendingUploads[index].phaseLabel = phaseLabel
        pendingUploads[index].failedMessage = nil
    }

    func completeVideoUpload(id: String, post: CountryPost) {
        pendingUploads.removeAll { $0.id == id }
        insertNewPost(post)
    }

    func failVideoUpload(id: String, message: String) {
        guard let index = pendingUploads.firstIndex(where: { $0.id == id }) else { return }
        pendingUploads[index].failedMessage = message
        pendingUploads[index].phaseLabel = "Failed"
        // Auto-dismiss failed shadow after a moment.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            pendingUploads.removeAll { $0.id == id }
        }
    }

    func dismissUpload(id: String) {
        pendingUploads.removeAll { $0.id == id }
    }

    func removePost(id: String, post: CountryPost? = nil) {
        if let post {
            DeletedPostsStore.shared.markDeleted(post: post)
        } else {
            DeletedPostsStore.shared.markDeleted(id)
        }
        let store = DeletedPostsStore.shared
        posts.removeAll {
            store.isDeleted(post: $0) || $0.id == id || $0.sharedPostID == id
        }
        // Keep disk cache in sync so relaunch does not resurrect the card.
        if var cached = ContentCache.shared.posts(for: .homeFeed) {
            cached.removeAll {
                store.isDeleted(post: $0) || $0.id == id || $0.sharedPostID == id
            }
            ContentCache.shared.setPosts(cached, for: .homeFeed)
        }
    }

    // MARK: - Private

    private func hardRefresh(generation gen: Int) async {
        feedSessionId = UUID().uuidString
        nextCursor = nil
        thinFeedFailStreak = 0
        thinFeedCoolUntil = nil
        hasMore = true
        recyclePass = 0
        PostsService.shared.resetHomeFeedSparkPager()
        await refreshSessionRankingContext()

        // Same fast path as fresh session — thin first, discovery in background.
        ContentCache.shared.invalidate(.homeFeed)
        SparkDiscoveryEngine.beginNewBrowseSession()
        let thin = await SurfacePageClient.fetchHomeFeed(limit: 48, cursor: nil)
        guard gen == generation else { return }
        var liveRaw = thin?.items ?? []
        if let thin { nextCursor = thin.nextCursor }
        if liveRaw.isEmpty {
            liveRaw = await PostsService.shared.fetchFirstPaintHomePosts(limit: 48)
        }
        let live = Self.liveOnlyPosts(liveRaw)
        let filtered = rankForSessionSync(live.isEmpty ? liveRaw : live)
        applyPosts(Array(filtered.prefix(36)), replace: true, sessionId: feedSessionId, alreadyRanked: true)
        hasMore = true
        didPaint = !posts.isEmpty
        Task { await warmHead(lite: true) }
        if !filtered.isEmpty {
            ContentCache.shared.setPosts(posts, for: .homeFeed)
        } else {
            ContentCache.shared.invalidate(.homeFeed)
        }
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let exclude = Set(self.posts.map(\.id))
            async let sparkTop = PostsService.shared.homeFeedSparkTopUp(
                excluding: exclude, limit: 28, forceRefresh: false
            )
            async let hubTop = PostsService.shared.homeFeedHubTopUp(
                excluding: exclude, limit: 10, forceRefresh: false
            )
            let extra = (await sparkTop) + (await hubTop)
            guard gen == self.generation, !extra.isEmpty else {
                await self.ensureBufferedPool()
                return
            }
            await self.softMergePreservingHead(extra)
            await self.ensureBufferedPool()
        }
        #if DEBUG
        print("[HomeFeed] hardRefresh live=\(live.count) total=\(filtered.count)")
        #endif
    }

    private func loadMore(generation gen: Int, forceNetwork: Bool = false) async {
        // Prefer expanding the local window through the already-loaded pool.
        if !forceNetwork, windowLimit < posts.count {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                windowLimit = min(posts.count, windowLimit + windowPageSize)
            }
            // Still more once the local window catches up to the pool.
            hasMore = true
            return
        }

        if loadMoreInFlight {
            loadMoreQueuedNearTail = true
            return
        }
        loadMoreInFlight = true
        defer {
            loadMoreInFlight = false
            // Near-tail requests during flight must not die — one queued follow-up.
            if loadMoreQueuedNearTail, gen == generation {
                loadMoreQueuedNearTail = false
                let followGen = generation
                Task(priority: .utility) { [weak self] in
                    await self?.loadMore(generation: followGen, forceNetwork: true)
                }
            }
        }

        // Background buffer top-ups stay silent when the list already has rows.
        let showSpinner = displayedPosts.count < 8
        if showSpinner { isLoadingMore = true }
        defer { if showSpinner { isLoadingMore = false } }

        let cursor = nextCursor
        let existingIDs = Set(posts.map(\.id))
        let seenContent = Set(posts.map(\.homeFeedContentKey))
        let thinCooling = thinFeedCoolUntil.map { Date() < $0 } ?? false

        // Prefer thin /v1/feed. On timeout/500: do NOT GraphQL with a v2 cursor (that
        // storms /graphql too) — clear stuck cursor and fall through to Sparks/Hubs.
        var pageItems: [CountryPost] = []
        var pageNextCursor: String? = cursor
        if !thinCooling {
            let idem = pendingFeedIdempotencyKey ?? UUID().uuidString
            pendingFeedIdempotencyKey = idem
            if let thin = await SurfacePageClient.fetchHomeFeed(
                limit: pageSize,
                cursor: cursor,
                idempotencyKey: idem,
                session: feedSessionId
            ) {
                thinFeedFailStreak = 0
                thinFeedCoolUntil = nil
                pendingFeedIdempotencyKey = nil
                if !thin.items.isEmpty {
                    pageItems = thin.items
                    pageNextCursor = thin.nextCursor
                    nextCursor = thin.nextCursor
                    hasMore = true
                } else if let next = thin.nextCursor, next != cursor {
                    pageNextCursor = next
                    nextCursor = next
                } else {
                    // Thin exhausted — Sparks/Hubs keep the feed endless.
                    pageNextCursor = nil
                    nextCursor = nil
                }
            } else {
                // Keep idem key so the next attempt replays the same reserved batch.
                thinFeedFailStreak += 1
                #if DEBUG
                print("[HomeFeed] thin /v1/feed fail streak=\(thinFeedFailStreak) cursor=\(cursor?.prefix(24) ?? "nil")")
                #endif
                if thinFeedFailStreak >= 2 {
                    // Drop the stuck cursor so the next thin attempt starts fresh.
                    nextCursor = nil
                    pageNextCursor = nil
                    thinFeedCoolUntil = Date().addingTimeInterval(20)
                    thinFeedFailStreak = 0
                    pendingFeedIdempotencyKey = nil
                }
            }
        }
        guard gen == generation else { return }

        var appended: [CountryPost] = []
        var seen = existingIDs
        var contentKeys = seenContent
        if !pageItems.isEmpty {
            // Preserve API four-lane weave order — do not re-rank thin pages.
            let pageDeduped = pageItems.dedupeHomeFeedContent()
            for post in pageDeduped {
                guard seen.insert(post.id).inserted else { continue }
                guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
                if SparkDiscoveryEngine.isViewed(post),
                   !(PlayPlatformBridge.isWrittenHomePost(post) && !Self.isHomeImageCard(post)) {
                    continue
                }
                appended.append(post)
                if appended.count >= pageSize { break }
            }
        }

        // Empty / failed thin → Sparks + Hubs top-up only (video-smooth). Rare text stays on thin feed.
        if appended.isEmpty {
            recyclePass += 1
            let exclude = seen
            let hubLimit = max(2, pageSize / 3)
            let sparkLimit = max(1, pageSize - hubLimit)
            // Never forceRefresh mid-scroll — that reset the Sparks cursor and stalled the tail.
            async let sparkTop = PostsService.shared.homeFeedSparkTopUp(
                excluding: exclude,
                limit: sparkLimit,
                forceRefresh: false
            )
            async let hubTop = PostsService.shared.homeFeedHubTopUp(
                excluding: exclude,
                limit: hubLimit,
                forceRefresh: false
            )
            let sparks = await sparkTop
            let hubs = await hubTop
            var mixed: [CountryPost] = []
            var si = 0
            var hi = 0
            while mixed.count < pageSize, si < sparks.count || hi < hubs.count {
                if hi < hubs.count, mixed.count % 3 == 2 || si >= sparks.count {
                    mixed.append(hubs[hi]); hi += 1
                } else if si < sparks.count {
                    mixed.append(sparks[si]); si += 1
                } else if hi < hubs.count {
                    mixed.append(hubs[hi]); hi += 1
                } else {
                    break
                }
            }
            for post in mixed {
                guard seen.insert(post.id).inserted else { continue }
                guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
                appended.append(post)
            }
        }

        if appended.isEmpty {
            // Keep trying forever — never set hasMore false permanently.
            hasMore = true
            if let next = pageNextCursor, next != cursor {
                nextCursor = next
            }
            emptyAppendRetriesThisGeneration += 1
            // Pulse sentinel even when windowLimit did not grow.
            endlessLoadEpoch &+= 1
            // After several empty top-ups, nudge Sparks pager so the next pass walks fresh R2.
            if emptyAppendRetriesThisGeneration % 3 == 0 {
                PostsService.shared.nudgeHomeFeedSparkPagerForEndless()
            }
            // Back off a bit so we don't storm /v1/feed — but never stop.
            let attempt = emptyAppendRetriesThisGeneration
            let delayMs: UInt64 = min(8_000, 350 + UInt64(attempt) * 250)
            if attempt <= maxEmptyAppendRetries {
                let followGen = gen
                Task(priority: .utility) { [weak self] in
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                    guard let self, followGen == self.generation else { return }
                    await self.loadMore(generation: followGen, forceNetwork: true)
                }
            }
            #if DEBUG
            print("[HomeFeed] loadMore empty retry=\(attempt) pool=\(posts.count) window=\(windowLimit) epoch=\(endlessLoadEpoch)")
            #endif
            return
        }

        emptyAppendRetriesThisGeneration = 0

        // Thin pages keep server weave order; spark/hub top-up still session-ranks.
        let orderedAppend = pageItems.isEmpty ? await rankForSessionAsync(appended) : appended
        var poolIDs = Set(posts.map(\.id))
        let dedupedAppend = orderedAppend.filter { poolIDs.insert($0.id).inserted }
        posts.append(contentsOf: dedupedAppend)
        // Grow window so new rows appear without waiting for another appear cycle.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            windowLimit = min(posts.count, max(windowLimit + appended.count, windowLimit + windowPageSize))
        }
        // Prefer thin network cursor only when we actually used thin items.
        if !pageItems.isEmpty, let pageNextCursor {
            nextCursor = pageNextCursor
        }
        hasMore = true
        endlessLoadEpoch &+= 1
        ContentCache.shared.setPosts(Array(posts.prefix(ContentCache.maxCachedPosts)), for: .homeFeed)
        // Media session 09: page append = thumbs only (no AV pool).
        ImageCache.shared.prefetchFeedMedia(
            Array(appended.prefix(SparkWarmPool.MediaBudget.thumbAhead)),
            maxPixelSize: 720
        )
        Task {
            await Frame0PosterResolver.shared.prefetch(
                postIDs: Array(appended.prefix(SparkWarmPool.MediaBudget.thumbAhead).map(\.id))
            )
        }
        #if DEBUG
        print("[HomeFeed] loadMore +\(appended.count) pool=\(posts.count) window=\(windowLimit) recycle=\(recyclePass)")
        #endif
        // Re-personalize after pool growth (head stays stable if user engaged).
        Task { await applyServerRankIfPossible() }
        // Keep pool deep so the next scroll never waits on network.
        if posts.count < minBufferedPool {
            Task(priority: .utility) { [weak self] in
                await self?.ensureBufferedPool()
            }
        }
    }

    private func applyPosts(_ next: [CountryPost], replace: Bool, sessionId: String, alreadyRanked: Bool = false) {
        feedSessionId = sessionId
        // Prefer caller-provided rank (off-main). Sync re-rank only for small/legacy paths.
        let ranked = alreadyRanked ? next : rankForSessionSync(next)
        // Stable unique by id — duplicate keys crash Dictionary(uniqueKeysWithValues) on rank/open.
        var seen = Set<String>()
        let ordered = ranked.filter { seen.insert($0.id).inserted }
        let pinned = withOfficialWelcomePinned(ordered)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts = pinned
            if replace {
                // Only shrink/reset the window when the user has not started watching yet.
                // Resetting windowLimit mid-watch felt like a full feed refresh.
                if !userEngagedThisSession {
                    windowLimit = min(firstWindow, max(pinned.count, 0))
                } else {
                    windowLimit = min(max(windowLimit, firstWindow), max(pinned.count, 0))
                }
            }
        }
        // Preserve existing nextCursor from Surface/GraphQL — don't clobber with ISO.
        hasMore = true
        Task { await ensureOfficialWelcomeCached() }
    }

    private var hasSeenOfficialWelcome: Bool {
        UserDefaults.standard.bool(forKey: Self.officialWelcomeSeenKey)
    }

    /// Pin the Matterya welcome post at index 0 until the user has scrolled past it once.
    private func withOfficialWelcomePinned(_ posts: [CountryPost]) -> [CountryPost] {
        guard !hasSeenOfficialWelcome else { return posts }
        let welcome =
            posts.first(where: { $0.id == Self.officialWelcomePostID })
            ?? cachedOfficialWelcome
            ?? posts.first(where: {
                let handle = $0.author?.username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let body = ($0.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return handle == "matterya" && body.hasPrefix("**Well, hello there. Welcome to Matterya!**")
            })
        guard let welcome else { return posts }
        cachedOfficialWelcome = welcome
        var rest = posts.filter { $0.id != welcome.id }
        return [welcome] + rest
    }

    private func ensureOfficialWelcomeCached() async {
        guard !hasSeenOfficialWelcome else { return }
        if cachedOfficialWelcome != nil { return }
        if let hit = posts.first(where: { $0.id == Self.officialWelcomePostID }) {
            cachedOfficialWelcome = hit
            return
        }
        if let remote = try? await PostsService.shared.getPostByID(Self.officialWelcomePostID) {
            cachedOfficialWelcome = remote
            // Re-pin without a full network reload if the pool already painted.
            if !posts.isEmpty, posts.first?.id != remote.id {
                let rest = posts.filter { $0.id != remote.id }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { posts = [remote] + rest }
            }
        }
    }

    /// Call when the welcome card leaves the first visible slot (scrolled past / opened elsewhere).
    func markOfficialWelcomeSeenIfNeeded(visiblePostID: String?) {
        guard !hasSeenOfficialWelcome else { return }
        guard let visiblePostID, !visiblePostID.isEmpty else { return }
        if visiblePostID == Self.officialWelcomePostID { return }
        // Any other card in focus means the welcome is no longer the first thing they see.
        if posts.contains(where: { $0.id == Self.officialWelcomePostID })
            || cachedOfficialWelcome != nil
            || posts.first?.author?.username?.lowercased() == "matterya"
        {
            UserDefaults.standard.set(true, forKey: Self.officialWelcomeSeenKey)
        }
    }

    /// Called the instant autoplay unlocks — warm the on-screen video queue so the first
    /// Feed Spark/video claims a ready buffer instead of cold-starting after splash.
    func warmVideosAfterAutoplayUnlock() {
        guard FeedVideoFocus.shared.allowsFeedAVWarm else { return }
        let videos = Self.feedWarmVideoQueue(
            from: Array(displayedPosts.prefix(max(windowLimit, firstWindow)))
        )
        guard !videos.isEmpty else { return }
        let around: Int
        if let id = lastVisiblePostID,
           let idx = Self.feedWarmIndex(
            for: displayedPosts.first(where: { $0.id == id }) ?? videos[0],
            in: videos,
            feedIndex: lastVisibleIndex,
            feed: displayedPosts
           ) {
            around = idx
        } else {
            around = 0
        }
        SparkWarmPool.shared.prepareFeedWindow(posts: videos, around: around)
    }

    /// Open / after-paint: thumbs (+ Frame0 after settle). Lite skips Frame0 + AV entirely.
    /// Cold open Frame0×N + AV under splash froze the main thread while audio kept playing.
    private func warmHead(lite: Bool = false) async {
        let thumbN = lite ? 3 : min(max(windowLimit, firstWindow), 8)
        let thumbBand = Array(posts.prefix(thumbN))
        ImageCache.shared.prefetchFeedMedia(thumbBand, maxPixelSize: lite ? 320 : 540)
        ImageCache.shared.prefetchPostThumbnails(thumbBand, maxPixelSize: lite ? 280 : 420, aggressive: false)
        // Open path: tiny thumbs only. Frame0 + AV only after autoplay unlock.
        guard !lite else { return }
        guard FeedVideoFocus.shared.allowsFeedAVWarm else { return }
        Task(priority: .utility) {
            // Cap Frame0 stampede on open — 2 posters max.
            await Frame0PosterResolver.shared.prefetch(postIDs: Array(thumbBand.prefix(2).map(\.id)))
        }
        let videos = Self.feedWarmVideoQueue(
            from: Array(displayedPosts.prefix(max(windowLimit, firstWindow)))
        )
        if !videos.isEmpty {
            SparkWarmPool.shared.prepareFeedWindow(posts: videos, around: 0)
        }
    }

    /// Shared Sparks / Hubs (and any playable video) cards — feed warm queue skips text/image rows.
    static func isFeedWarmVideo(_ post: CountryPost) -> Bool {
        guard post.playableVideoURL != nil || post.hasVideo else { return false }
        if post.isSpark || post.isReel || PlayPlatformBridge.isSparkFeedCard(post) { return true }
        if PlayPlatformBridge.isHubFeedCardVideo(post) || PlayPlatformBridge.isHubOriginShare(post) {
            return true
        }
        return post.hasVideo && post.playableVideoURL != nil
    }

    static func feedWarmVideoQueue(from posts: [CountryPost]) -> [CountryPost] {
        posts.filter(isFeedWarmVideo)
    }

    /// Index in the video-only queue for sliding-window warm. If the visible row is not a
    /// video, warm from the next upcoming shared Sparks/Hubs card.
    static func feedWarmIndex(
        for post: CountryPost,
        in videos: [CountryPost],
        feedIndex: Int,
        feed: [CountryPost]
    ) -> Int? {
        guard !videos.isEmpty else { return nil }
        if let hit = videos.firstIndex(where: { $0.id == post.id }) {
            return hit
        }
        guard feedIndex < feed.count else { return 0 }
        for row in feed[feedIndex...] {
            if let hit = videos.firstIndex(where: { $0.id == row.id }) {
                return hit
            }
        }
        return videos.indices.last
    }

    /// Opaque cursor for GraphQL `before` (created_at timestamptz).
    /// Always ISO-8601 — never epoch ms (PG rejects `1786664811920` as timestamptz).
    static func cursor(from post: CountryPost?) -> String? {
        guard let post else { return nil }
        if let date = post.createdDate {
            return ISO8601DateFormatter().string(from: date)
        }
        let raw = post.createdAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        // Already ISO-ish
        if raw.contains("-") || raw.contains("T") { return raw }
        // Epoch ms / s → ISO
        if let n = Double(raw) {
            let seconds = n > 1_000_000_000_000 ? n / 1000.0 : n
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
        }
        return raw
    }
}
