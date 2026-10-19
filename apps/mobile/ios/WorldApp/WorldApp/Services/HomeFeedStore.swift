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
    /// Most recent on-screen row — soft-merge must pin through here so the watched card never vanishes.
    private var lastVisiblePostID: String?
    private var lastVisibleIndex: Int = 0
    /// Last open's head IDs — demoted on the next fresh session so Feed isn't identical every launch.
    private static let lastHeadDefaultsKey = "home.feed.lastHeadIDs.v2"

    /// Network page size — keep modest so ranking/merge stays off the scroll path.
    private let pageSize = 24
    private let windowPageSize = 12
    /// First paint window — ~1.5 screens; grow on scroll.
    private let firstWindow = 12
    /// Prefetch next page early (Facebook-style always-ahead pool).
    private let prefetchRatio = 0.28
    /// Keep at least this many posts buffered in `posts` (beyond the visible window).
    private let minBufferedPool = 36

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
    /// While the user is watching, only reorders **below** the on-screen window.
    func applyServerRankIfPossible() async {
        let snapshot = posts
        guard snapshot.count >= 4 else { return }
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
            if merged.count >= 80 { break }
        }
        UserDefaults.standard.set(Array(merged.prefix(80)), forKey: Self.lastHeadDefaultsKey)
    }

    /// Put last-open head at the tail — API `/v1/feed` is newest-first and otherwise repeats.
    private func demoteRecentHead(_ posts: [CountryPost]) -> [CountryPost] {
        let recent = Set(persistedLastHeadIDs())
        guard !recent.isEmpty else { return posts }
        var fresh: [CountryPost] = []
        var stale: [CountryPost] = []
        fresh.reserveCapacity(posts.count)
        for post in posts {
            if recent.contains(post.id) {
                stale.append(post)
            } else {
                fresh.append(post)
            }
        }
        guard !fresh.isEmpty else { return posts }
        return fresh + stale
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
        if freshCount >= 14 || cursor == nil { return (pooled, cursor) }

        var seen = Set(pooled.map(\.id))
        for _ in 0..<3 {
            guard let cur = cursor, !cur.isEmpty else { break }
            guard let page = await SurfacePageClient.fetchHomeFeed(limit: 48, cursor: cur) else { break }
            cursor = page.nextCursor
            if page.items.isEmpty { break }
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
        errorMessage = nil
        nextCursor = nil
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
            userEngagedThisSession = false
            lastVisiblePostID = nil
            lastVisibleIndex = 0
            feedSessionId = UUID().uuidString
            recyclePass = 0
            windowLimit = firstWindow
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
                    let ranked = demoteRecentHead(rankForSessionSync(pool))
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
        // Fresh session: wider first page so demote+shuffle has room to differ.
        let thinLimit = forceReplace ? 48 : 24
        let thin = await SurfacePageClient.fetchHomeFeed(limit: thinLimit, cursor: nil)
        guard gen == generation else {
            isRefreshing = false
            return
        }

        if let thin, !thin.items.isEmpty {
            nextCursor = thin.nextCursor
            var livePool = thin.items
            if forceReplace {
                let expanded = await expandFreshHead(initial: livePool, startingCursor: thin.nextCursor)
                livePool = expanded.items
                if let cur = expanded.cursor { nextCursor = cur }
            }
            let fast = Self.liveOnlyPosts(livePool)
            var rankedFast = rankForSessionSync(fast.isEmpty ? livePool : fast)
            if forceReplace {
                rankedFast = demoteRecentHead(rankedFast)
            }
            let head = Array(rankedFast.prefix(forceReplace ? 36 : 24))
            if !head.isEmpty {
                let preserveHead = !forceReplace
                    && (paintedBefore || userEngagedThisSession)
                if preserveHead {
                    await softMergePreservingHead(head)
                } else {
                    applyPosts(head, replace: true, sessionId: feedSessionId, alreadyRanked: true)
                    ContentCache.shared.setPosts(posts, for: .homeFeed)
                    rememberDisplayedHead()
                }
                isBootstrapping = false
                didPaint = true
                hasMore = true
                Task { await warmHead(lite: true) }
            }
        } else if posts.isEmpty {
            let liveRaw = await PostsService.shared.fetchFirstPaintHomePosts(limit: 48)
            guard gen == generation else {
                isRefreshing = false
                return
            }
            let ranked = demoteRecentHead(rankForSessionSync(Self.liveOnlyPosts(liveRaw)))
            if !ranked.isEmpty {
                applyPosts(Array(ranked.prefix(36)), replace: true, sessionId: feedSessionId, alreadyRanked: true)
                ContentCache.shared.setPosts(posts, for: .homeFeed)
                rememberDisplayedHead()
                didPaint = true
                Task { await warmHead(lite: true) }
            }
        }

        isBootstrapping = false
        isRefreshing = false
        recyclePass = 0

        // 3) Heavy work AFTER first paint — never compete with thin feed.
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard gen == self.generation else { return }
            await self.warmHead(lite: false)
            let exclude = Set(self.posts.map(\.id))
            async let sparkTop = PostsService.shared.homeFeedSparkTopUp(
                excluding: exclude,
                limit: 20,
                forceRefresh: false
            )
            async let hubTop = PostsService.shared.homeFeedHubTopUp(
                excluding: exclude,
                limit: 8,
                forceRefresh: false
            )
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
    private func ensureBufferedPool() async {
        var guardPasses = 0
        var stagnant = 0
        var lastCount = posts.count
        while posts.count < minBufferedPool, hasMore, guardPasses < 12 {
            guardPasses += 1
            let gen = generation
            // Force network — don't only expand the local window.
            await loadMore(generation: gen, forceNetwork: true)
            guard gen == generation else { return }
            if posts.count <= lastCount {
                stagnant += 1
                if stagnant >= 3 { break }
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

        // Engaged: freeze the on-screen window in place. Append new rows only below it.
        // Never re-rank / move a post the user is watching to the viewed tail.
        if userEngagedThisSession, !posts.isEmpty {
            let pinCount = pinnedPrefixCount(poolCount: posts.count)
            let head = Array(posts.prefix(pinCount))
            let below = Array(posts.dropFirst(pinCount))
            var seen = Set(head.map(\.id))
            var contentKeys = Set(head.map(\.homeFeedContentKey))

            var preservedBelow: [CountryPost] = []
            for post in below where seen.insert(post.id).inserted {
                contentKeys.insert(post.homeFeedContentKey)
                preservedBelow.append(post)
            }

            var newUnviewed: [CountryPost] = []
            var newViewed: [CountryPost] = []
            for post in clean {
                guard seen.insert(post.id).inserted else { continue }
                guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
                if SparkDiscoveryEngine.isViewed(post) {
                    newViewed.append(post)
                } else {
                    newUnviewed.append(post)
                }
            }

            let merged = head + preservedBelow + newUnviewed + newViewed
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

        // Cold open (not engaged): full rank is fine — nothing on screen yet to protect.
        let ranked = await rankForSessionAsync(clean + posts)
        let head: [CountryPost] = []
        var seen = Set(head.map(\.id))
        var contentKeys = Set(head.map(\.homeFeedContentKey))

        var freshTail: [CountryPost] = []
        var viewedTail: [CountryPost] = []
        freshTail.reserveCapacity(ranked.count)
        for post in ranked {
            guard seen.insert(post.id).inserted else { continue }
            guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
            if SparkDiscoveryEngine.isViewed(post) {
                viewedTail.append(post)
            } else {
                freshTail.append(post)
            }
        }
        let tail = freshTail + viewedTail
        guard !tail.isEmpty else { return }

        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts = head + tail
            windowLimit = min(windowLimit, max(firstWindow, min(posts.count, firstWindow)))
        }
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
    /// Unviewed only while any remain in this batch; recycle only when the batch is all-viewed.
    private static func liveOnlyPosts(_ posts: [CountryPost]) -> [CountryPost] {
        let base = posts.excludingDeletedPosts().forHomeFeed()
        guard !base.isEmpty else { return [] }
        // Unviewed first, watched at end — keep full pool so home feed stays endless.
        return SparkDiscoveryEngine.rankForDiscovery(base)
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

        // Media session 09: feed list = posters only. NO SparkWarmPool / AV on scroll.
        let thumbAhead = fling ? 4 : 8
        let end = min(displayedPosts.count, index + thumbAhead)
        if index < end {
            let window = Array(displayedPosts[index..<end])
            ImageCache.shared.prefetchFeedMedia(window, maxPixelSize: fling ? 280 : 360)
            if !fling {
                Task(priority: .utility) {
                    await Frame0PosterResolver.shared.prefetch(postIDs: window.map(\.id))
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
        Task { await warmHead() }
        if !filtered.isEmpty {
            ContentCache.shared.setPosts(posts, for: .homeFeed)
        } else {
            ContentCache.shared.invalidate(.homeFeed)
        }
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let exclude = Set(self.posts.map(\.id))
            async let sparkTop = PostsService.shared.homeFeedSparkTopUp(
                excluding: exclude, limit: 36, forceRefresh: false
            )
            async let hubTop = PostsService.shared.homeFeedHubTopUp(
                excluding: exclude, limit: 14, forceRefresh: false
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
        // Infinite scroll: take unviewed first from the page; watched only as tail fillers.
        let rankedPage = SparkDiscoveryEngine.rankForDiscovery(pageDeduped)
        var pageViewed: [CountryPost] = []
        for post in rankedPage {
            guard seen.insert(post.id).inserted else { continue }
            guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
            if SparkDiscoveryEngine.isViewed(post) {
                pageViewed.append(post)
                continue
            }
            appended.append(post)
            if appended.count >= pageSize { break }
        }
        if appended.count < pageSize {
            for post in pageViewed {
                appended.append(post)
                if appended.count >= pageSize { break }
            }
        }

        // Empty page → R2 discovery top-up (unviewed first, watched at end).
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
        // Prefer network cursor only — never invent ISO from last post (re-walks thin page 1).
        if let pageNextCursor {
            nextCursor = pageNextCursor
        }
        hasMore = true
        ContentCache.shared.setPosts(Array(posts.prefix(ContentCache.maxCachedPosts)), for: .homeFeed)
        // Media session 09: page append = thumbs only (no AV pool).
        ImageCache.shared.prefetchFeedMedia(
            Array(appended.prefix(SparkWarmPool.MediaBudget.thumbAhead)),
            maxPixelSize: 360
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
        // Preserve existing nextCursor from Surface/GraphQL — don't clobber with ISO.
        hasMore = true
    }

    /// Media session 09: feed head = thumbs + Frame0 only. Never prepareFeedWindow here.
    /// `lite` = open path (tiny band); full = after paint (visible + a few ahead).
    private func warmHead(lite: Bool = false) async {
        let thumbN = lite ? 6 : min(max(windowLimit, firstWindow) + 4, 14)
        let thumbBand = Array(posts.prefix(thumbN))
        ImageCache.shared.prefetchFeedMedia(thumbBand, maxPixelSize: lite ? 240 : 320)
        ImageCache.shared.prefetchPostThumbnails(thumbBand, maxPixelSize: 320, aggressive: false)
        Task(priority: .utility) {
            await Frame0PosterResolver.shared.prefetch(postIDs: Array(thumbBand.prefix(8).map(\.id)))
        }
        // Slug neighbor only after paint — never on the open path.
        if !lite, let hub = posts.prefix(8).first(where: {
            PlayPlatformBridge.isHubFeedCardVideo($0) || PlayPlatformBridge.isHubOriginShare($0)
        }) {
            let slug = hub.hubSlug ?? YouTubeCatalogService.parentHubSlug(for: hub)
            SlugShelfStore.shared.warmNeighbor(of: slug)
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
