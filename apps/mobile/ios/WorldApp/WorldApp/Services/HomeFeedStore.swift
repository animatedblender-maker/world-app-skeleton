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
    /// Soft recycle pass when unique network + catalog slices run dry — feed never ends.
    private var recyclePass = 0
    /// New every app open / pull-to-refresh → different share mix.
    private var sessionRankSeed: UInt64 = UInt64.random(in: 1...UInt64.max)
    private var sessionFollowingIDs: Set<String> = []
    private var sessionMyUserID: String?
    /// True once the user has seen/scrolled a row this session — blocks head-replacing network merges.
    private var userEngagedThisSession = false

    /// Network page size — fat pages so the tail never feels "loading more".
    private let pageSize = 40
    private let windowPageSize = 18
    /// First paint window — enough for 2+ screens without load-more spinner.
    private let firstWindow = 20
    /// Prefetch next page early (Facebook-style always-ahead pool).
    private let prefetchRatio = 0.32
    /// Keep at least this many posts buffered in `posts` (beyond the visible window).
    private let minBufferedPool = 56

    private init() {}

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
    func applyServerRankIfPossible() async {
        let snapshot = posts
        guard snapshot.count >= 4 else { return }
        let surface = homeSurface
        let ranked = await RecommendationClient.rankPosts(
            snapshot,
            surface: surface,
            sessionId: feedSessionId,
            followingIDs: sessionFollowingIDs,
            limit: min(snapshot.count, 100)
        )
        guard ranked.map(\.id) != snapshot.map(\.id) else { return }
        // Soft blend only — never wipe the session-shuffled head (that made every open identical).
        let headCount = min(userEngagedThisSession ? 4 : 6, snapshot.count)
        let head = Array(snapshot.prefix(headCount))
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

    private func runFreshSession(forceReplace: Bool) async {
        generation += 1
        let gen = generation
        errorMessage = nil
        nextCursor = nil
        hasMore = true
        isRefreshing = true
        defer { isRefreshing = false }

        if forceReplace {
            userEngagedThisSession = false
            feedSessionId = UUID().uuidString
            recyclePass = 0
            // Remount list from top with a brand-new order (no sticky window tail).
            windowLimit = firstWindow
            await refreshSessionRankingContext()
        } else if posts.isEmpty {
            feedSessionId = UUID().uuidString
            await refreshSessionRankingContext()
        } else {
            // Already showing rows — keep session seed so the head order stays stable.
            await refreshFollowingContextOnly()
        }

        // 1) Instant paint from cache only when empty or forced reshape.
        let paintedBefore = didPaint && !posts.isEmpty
        if forceReplace || posts.isEmpty {
            // Force reshape: pool = previous posts + disk cache, then **re-rank with new seed**.
            var pool: [CountryPost] = forceReplace ? posts : []
            if let cached = ContentCache.shared.posts(for: .homeFeed) {
                pool.append(contentsOf: Self.liveOnlyPosts(cached))
            }
            if pool.isEmpty {
                pool = posts
            }
            pool = Self.liveOnlyPosts(
                BlockService.shared.filterPosts(pool.excludingMoments().forHomeFeed())
            )
            if !pool.isEmpty {
                let rankedPool = await rankForSessionAsync(pool)
                applyPosts(Array(rankedPool.prefix(80)), replace: true, sessionId: feedSessionId, alreadyRanked: true)
                isBootstrapping = false
                didPaint = true
                // Never block first paint on AV warm — warm in parallel.
                Task { await warmHead() }
            } else {
                isBootstrapping = true
            }
        }

        // 2) Network — thin /v1/feed first, GraphQL fallback. Never hard-replace while watching.
        // Pull a wider first page so viewed-filter still leaves a usable head.
        let liveRaw: [CountryPost]
        if let thin = await SurfacePageClient.fetchHomeFeed(limit: 48, cursor: nil), !thin.items.isEmpty {
            nextCursor = thin.nextCursor
            liveRaw = thin.items
        } else {
            liveRaw = await PostsService.shared.fetchFirstPaintHomePosts(limit: 64)
        }
        let live = Self.liveOnlyPosts(liveRaw)
        guard gen == generation else { return }

        let preserveHead = !forceReplace
            && (paintedBefore || userEngagedThisSession || (didPaint && !posts.isEmpty))

        if preserveHead {
            await softMergePreservingHead(live)
            isBootstrapping = false
            didPaint = true
            hasMore = true
            recyclePass = 0
            #if DEBUG
            print("[HomeFeed] freshSession soft-merge live=\(live.count) pool=\(posts.count) window=\(windowLimit) engaged=\(userEngagedThisSession)")
            #endif
        } else {
            // Rank the full raw+pool first (session order tops up thin unviewed), then liveOnly.
            let realBatch = Self.liveOnlyPosts(liveRaw + posts)
            var capped = Array((await rankForSessionAsync(realBatch)).prefix(min(max(realBatch.count, 1), 90)))
            // Safety net: if rank still starved, fall back to liveOnlyPosts of the raw page.
            if capped.count < 8, liveRaw.count > capped.count {
                let fallback = Self.liveOnlyPosts(liveRaw + posts + capped)
                if fallback.count > capped.count {
                    capped = Array((await rankForSessionAsync(fallback)).prefix(90))
                }
                if capped.count < 8 {
                    capped = Array(fallback.prefix(90))
                }
            }

            if !capped.isEmpty {
                applyPosts(capped, replace: true, sessionId: feedSessionId, alreadyRanked: true)
                ContentCache.shared.setPosts(posts, for: .homeFeed)
                didPaint = true
                Task { await warmHead() }
                hasMore = true
                recyclePass = 0
                #if DEBUG
                print("[HomeFeed] freshSession replace total=\(capped.count) raw=\(liveRaw.count) live=\(live.count) following=\(sessionFollowingIDs.count) seed=\(sessionRankSeed)")
                #endif
            } else if posts.isEmpty {
                applyPosts([], replace: true, sessionId: feedSessionId)
                ContentCache.shared.invalidate(.homeFeed)
                hasMore = true
            }
        }

        isBootstrapping = false
        // Thin head after viewed-filter → immediately page for more (don’t spin on 1 card).
        if posts.count < 12 {
            hasMore = true
            requestLoadMore()
        }
        // Facebook-style: never leave the user waiting at the tail — fill the pool in background.
        Task(priority: .utility) { [weak self] in
            await self?.ensureBufferedPool()
        }
    }

    /// Keep a deep post pool so scroll rarely hits "loading more".
    private func ensureBufferedPool() async {
        var guardPasses = 0
        while posts.count < minBufferedPool, hasMore, guardPasses < 5 {
            guardPasses += 1
            let gen = generation
            // Force network — don't only expand the local window.
            await loadMore(generation: gen, forceNetwork: true)
            guard gen == generation else { return }
        }
    }

    /// Append / weave network rows **under** the visible head — never remounts what the user is watching.
    private func softMergePreservingHead(_ incoming: [CountryPost]) async {
        let clean = Self.liveOnlyPosts(
            BlockService.shared.filterPosts(incoming.excludingMoments().forHomeFeed())
        )
        guard !clean.isEmpty else { return }

        // Pin everything already on screen (and a little buffer) in its current order.
        let pinCount = max(windowLimit, firstWindow, min(posts.count, 16))
        let head = Array(posts.prefix(pinCount))
        var seen = Set(head.map(\.id))
        var contentKeys = Set(head.map(\.homeFeedContentKey))

        // Rank the rest of the library for the tail only.
        let ranked = await rankForSessionAsync(clean + posts)
        var tail: [CountryPost] = []
        tail.reserveCapacity(ranked.count)
        for post in ranked {
            guard seen.insert(post.id).inserted else { continue }
            guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
            tail.append(post)
        }

        guard !tail.isEmpty || head.count != posts.count else {
            // Still refresh disk cache with current pool.
            if !posts.isEmpty {
                ContentCache.shared.setPosts(
                    Array(posts.prefix(ContentCache.maxCachedPosts)),
                    for: .homeFeed
                )
            }
            return
        }

        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts = head + tail
            // Critical: do NOT reset windowLimit — that was the “feed refreshed” jump.
        }
        nextCursor = Self.cursor(from: posts.last)
        hasMore = true
        ContentCache.shared.setPosts(
            Array(posts.prefix(ContentCache.maxCachedPosts)),
            for: .homeFeed
        )
    }

    /// Smooth open: cache → tiny first-paint network → done.
    /// Never multi-page GraphQL or hubs catalog on this path.
    /// Prefer `beginFreshSession()` when the user should see a **new** mix.
    func bootstrap(forceRefresh: Bool = false) async {
        generation += 1
        let gen = generation
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
                Task { await warmHead() }
            }
        }

        // 2) Thin surface page first (slug/light path) — fall back to GraphQL first-paint.
        let live: [CountryPost]
        if let thin = await SurfacePageClient.fetchHomeFeed(limit: 28, cursor: nil), !thin.items.isEmpty {
            nextCursor = thin.nextCursor
            live = Self.liveOnlyPosts(thin.items)
            #if DEBUG
            print("[HomeFeed] thin /v1/feed firstPaint=\(live.count)")
            #endif
        } else {
            live = Self.liveOnlyPosts(await PostsService.shared.fetchFirstPaintHomePosts(limit: 48))
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
            let capped = Array((await rankForSessionAsync(realBatch)).prefix(min(realBatch.count, 90)))

            if !capped.isEmpty {
                applyPosts(capped, replace: true, sessionId: feedSessionId, alreadyRanked: true)
                ContentCache.shared.setPosts(posts, for: .homeFeed)
                didPaint = true
                Task { await warmHead() }
                hasMore = true
                recyclePass = 0
                #if DEBUG
                print("[HomeFeed] firstPaint total=\(capped.count) network=\(live.count)")
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
    /// Unviewed first via rankForDiscovery — but NEVER drop viewed posts from the pool
    /// (that starved Home to a handful of old cards after Sparks browsing).
    private static func liveOnlyPosts(_ posts: [CountryPost]) -> [CountryPost] {
        let base = posts.excludingDeletedPosts().forHomeFeed()
        guard !base.isEmpty else { return [] }
        return SparkDiscoveryEngine.rankForDiscovery(base)
    }

    // MARK: - Scroll / prefetch

    /// Call from row `onAppear`. Prefetches media and next page at 65%.
    /// Fast fling: grow the local window aggressively, skip heavy network work until scroll settles.
    func onRowAppear(post: CountryPost) {
        ScrollBudget.noteCellAppear()
        // Any row appear counts as engagement — late network must not remount the head.
        userEngagedThisSession = true
        guard let index = displayedPosts.firstIndex(where: { $0.id == post.id }) else { return }

        // True exposure (viewport) — stronger label than "returned by ranking".
        // Dwell/skip still come from FeedView appear/disappear.
        RecommendationDecisionLog.shared.logViewportVisible(
            post: post,
            surface: .homeForYou,
            position: index
        )

        let fling = ScrollBudget.isFlinging
        // During a fling, jump the window ahead so LazyVStack always has cells ready.
        let growBy = fling ? windowPageSize * 3 : windowPageSize
        let growWhenWithin = fling ? 8 : 3

        if index >= displayedPosts.count - growWhenWithin, windowLimit < posts.count {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                windowLimit = min(posts.count, windowLimit + growBy)
            }
            // Local pool may still grow via network / R2 — never mark exhausted here.
            hasMore = true
        }

        // Thumbs for nearby rows; Sparks-style 5-ahead AV sliding window on shared hubs/sparks.
        let ahead = fling ? 3 : 5
        let end = min(displayedPosts.count, index + ahead)
        if index < end {
            let window = Array(displayedPosts[index..<end])
            ImageCache.shared.prefetchFeedMedia(window, maxPixelSize: fling ? 280 : 360)
            if !fling {
                let videos = Self.feedWarmVideoQueue(from: displayedPosts)
                if let videoIndex = Self.feedWarmIndex(for: post, in: videos, feedIndex: index, feed: displayedPosts) {
                    SparkWarmPool.shared.prepareFeedWindow(posts: videos, around: videoIndex)
                    let hi = min(videos.count, videoIndex + SparkWarmPool.MediaBudget.playerAheadFeed + 1)
                    let warmIDs = Array(videos[videoIndex..<hi].map(\.id))
                    if !warmIDs.isEmpty {
                        Task(priority: .utility) {
                            await RecommendationClient.warmPlaybackURLs(warmIDs)
                        }
                    }
                }
            }
        }

        // Don't kick network load-more mid-fling (causes hitch + image storms).
        guard !fling else { return }

        // Top up pool early — never wait until the last few cells.
        let threshold = max(0, Int(Double(max(posts.count, 1)) * prefetchRatio) - 1)
        if index >= threshold || posts.count < minBufferedPool {
            requestLoadMore()
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
        guard !isLoadingMore, !isBootstrapping else { return }
        hasMore = true
        let gen = generation
        pendingLoadMoreTask?.cancel()
        pendingLoadMoreTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.loadMore(generation: gen)
        }
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
        hasMore = true
        recyclePass = 0
        await refreshSessionRankingContext()

        // Pull-to-refresh: new session seed + following-first ranking.
        let live = Self.liveOnlyPosts(await PostsService.shared.fetchNetworkHomePosts(limit: 100))
        guard gen == generation else { return }

        let filtered = await rankForSessionAsync(live)
        applyPosts(filtered, replace: true, sessionId: feedSessionId, alreadyRanked: true)
        nextCursor = Self.cursor(from: filtered.last)
        // Always more — R2 library + network continue after this head.
        hasMore = true
        didPaint = !posts.isEmpty
        Task { await warmHead() }
        if !filtered.isEmpty {
            ContentCache.shared.setPosts(posts, for: .homeFeed)
        } else {
            ContentCache.shared.invalidate(.homeFeed)
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

        // Never permanently stop — R2 Sparks keep the tail alive.
        // Background buffer top-ups stay silent (no spinner) when the list already has rows.
        let showSpinner = displayedPosts.count < 8
        if showSpinner { isLoadingMore = true }
        defer { if showSpinner { isLoadingMore = false } }

        let cursor = nextCursor
        let existingIDs = Set(posts.map(\.id))
        let seenContent = Set(posts.map(\.homeFeedContentKey))

        // Prefer thin /v1/feed page (light); GraphQL only if thin fails.
        let pageItems: [CountryPost]
        let pageNextCursor: String?
        if let thin = await SurfacePageClient.fetchHomeFeed(limit: pageSize, cursor: cursor),
           !thin.items.isEmpty {
            pageNextCursor = thin.nextCursor
            nextCursor = thin.nextCursor
            // Endless feed: thin cursor may end, but R2/Spark top-up must keep going.
            hasMore = true
            pageItems = thin.items
        } else {
            let page = await PostsService.shared.loadHomeFeedPage(
                after: cursor,
                limit: pageSize,
                feedSessionId: feedSessionId,
                preferCache: false,
                excludingIDs: existingIDs
            )
            pageNextCursor = page.nextCursor
            nextCursor = page.nextCursor
            hasMore = true
            pageItems = page.items
        }
        guard gen == generation, !Task.isCancelled else { return }

        var appended: [CountryPost] = []
        var seen = existingIDs
        var contentKeys = seenContent
        let pageDeduped = pageItems.dedupeHomeFeedContent()
        // Append everything new from the page (unviewed first via rank) — do not hard-skip viewed.
        for post in SparkDiscoveryEngine.rankForDiscovery(pageDeduped) {
            guard seen.insert(post.id).inserted else { continue }
            guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
            appended.append(post)
            if appended.count >= pageSize { break }
        }

        // Empty / all-dupes: unique R2 top-up (Sparks + Hubs).
        if appended.isEmpty {
            recyclePass += 1
            let forceDeep = recyclePass == 1 || recyclePass % 4 == 0
            if forceDeep {
                _ = await PostsService.shared.loadSparksDiscoveryCatalog(
                    forceRefresh: recyclePass == 1,
                    deep: recyclePass >= 1
                )
            }
            let exclude = seen
            // Mix Sparks + Hubs-badge cards (~2:1) so Home isn't spark-only.
            let hubLimit = max(2, pageSize / 3)
            let sparkLimit = max(1, pageSize - hubLimit)
            async let sparkTop = PostsService.shared.homeFeedSparkTopUp(
                excluding: exclude,
                limit: sparkLimit,
                forceRefresh: recyclePass > 2
            )
            async let hubTop = PostsService.shared.homeFeedHubTopUp(
                excluding: exclude,
                limit: hubLimit,
                forceRefresh: recyclePass > 2
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
                }
            }
            for post in mixed {
                guard seen.insert(post.id).inserted else { continue }
                guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
                appended.append(post)
            }
        }

        if appended.isEmpty {
            // Keep trying on next scroll — never set hasMore false permanently.
            hasMore = true
            // Advance cursor from network even when items filtered as dups.
            if let next = pageNextCursor, next != cursor {
                nextCursor = next
            }
            return
        }

        // Rank new batch (unviewed only; follows first), then append without reordering the live head.
        let orderedAppend = await rankForSessionAsync(appended)
        // Never allow duplicate ids (uniqueKeysWithValues fatal + ForEach identity bugs).
        var poolIDs = Set(posts.map(\.id))
        let dedupedAppend = orderedAppend.filter { poolIDs.insert($0.id).inserted }
        posts.append(contentsOf: dedupedAppend)
        // Grow window so new rows appear without waiting for another appear cycle.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            windowLimit = min(posts.count, max(windowLimit + appended.count, windowLimit + windowPageSize))
        }
        // Prefer network cursor (not spark top-up dates) so we don't re-walk the head.
        nextCursor = pageNextCursor ?? Self.cursor(from: posts.last)
        hasMore = true
        ContentCache.shared.setPosts(Array(posts.prefix(ContentCache.maxCachedPosts)), for: .homeFeed)
        // Media session 09: page append = thumbs only (no AV pool).
        ImageCache.shared.prefetchFeedMedia(Array(appended.prefix(8)), maxPixelSize: 360)
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
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts = ordered
            if replace {
                // Only shrink/reset the window when the user has not started watching yet.
                // Resetting windowLimit mid-watch felt like a full feed refresh.
                if !userEngagedThisSession {
                    windowLimit = min(firstWindow, max(ordered.count, 0))
                } else {
                    windowLimit = min(max(windowLimit, firstWindow), max(ordered.count, 0))
                }
            }
        }
        if !ordered.isEmpty {
            nextCursor = Self.cursor(from: ordered.last)
        }
        hasMore = true
    }

    /// Deep-preroll the first feed videos, then wait briefly so autoplay can claim
    /// a decoded frame (Instagram-style — no black/thumb blink on the winner).
    private func warmHead() async {
        // Posters first (cheap). Sliding 5-ahead window fills under the concurrent warm cap
        // (same policy as Sparks — no parallel MP4 storm).
        let head = Array(posts.prefix(max(firstWindow + 2, 12)))
        ImageCache.shared.prefetchFeedMedia(head, maxPixelSize: 360)
        let videos = Self.feedWarmVideoQueue(from: posts)
        guard !videos.isEmpty else { return }
        SparkWarmPool.shared.prepareFeedWindow(posts: videos, around: 0)
        for post in videos.prefix(SparkWarmPool.MediaBudget.playerAheadFeed + 1) {
            if let url = post.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) {
                ArchiveVideoPlayback.warmResolve(url)
            }
        }
        let readyIDs = Array(videos.prefix(2).map(\.id))
        Task(priority: .utility) {
            await RecommendationClient.warmPlaybackURLs(readyIDs)
        }
        await SparkWarmPool.shared.awaitReady(postIDs: Array(readyIDs.prefix(1)), timeout: 0.35)
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
