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

    private let pageSize = 24
    private let windowPageSize = 12
    private let firstWindow = 10
    /// Prefetch next page when user reaches ~55% of the currently loaded pool.
    private let prefetchRatio = 0.55

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

    /// Session order + hard hide of already-viewed posts (open / reload / app open / load-more).
    private func rankForSession(_ posts: [CountryPost]) -> [CountryPost] {
        SparkDiscoveryEngine.sessionHomeFeedOrder(
            posts.dedupeHomeFeedContent(),
            followingIDs: sessionFollowingIDs,
            myUserID: sessionMyUserID,
            sessionSeed: sessionRankSeed
        )
    }

    var displayedPosts: [CountryPost] {
        Array(posts.prefix(windowLimit))
    }

    var showsSkeleton: Bool {
        isBootstrapping && posts.isEmpty
    }

    // MARK: - Lifecycle

    /// New browsing session (app open / 3+ min away / pull).
    /// - Parameter forceReplace: pull-to-refresh / explicit reshuffle — rebuilds the whole list.
    ///   Default **false**: after the first paint, network only soft-merges so a late
    ///   first-paint response never rips out the row the user is already watching.
    func beginFreshSession(forceReplace: Bool = false) async {
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
            var pool: [CountryPost] = posts
            if pool.isEmpty, let cached = ContentCache.shared.posts(for: .homeFeed) {
                pool = Self.liveOnlyPosts(cached)
            }
            pool = Self.liveOnlyPosts(
                BlockService.shared.filterPosts(pool.excludingMoments().forHomeFeed())
            )
            if !pool.isEmpty {
                applyPosts(Array(rankForSession(pool).prefix(80)), replace: true, sessionId: feedSessionId)
                isBootstrapping = false
                didPaint = true
                warmHead()
            } else {
                isBootstrapping = true
            }
        }

        // 2) Network — never hard-replace a feed the user is already watching.
        let live = Self.liveOnlyPosts(await PostsService.shared.fetchFirstPaintHomePosts(limit: 72))
        guard gen == generation else { return }

        let preserveHead = !forceReplace
            && (paintedBefore || userEngagedThisSession || (didPaint && !posts.isEmpty))

        if preserveHead {
            softMergePreservingHead(live)
            isBootstrapping = false
            didPaint = true
            hasMore = true
            recyclePass = 0
            #if DEBUG
            print("[HomeFeed] freshSession soft-merge live=\(live.count) pool=\(posts.count) window=\(windowLimit) engaged=\(userEngagedThisSession)")
            #endif
        } else {
            let realBatch = Self.liveOnlyPosts(live + posts)
            let capped = Array(rankForSession(realBatch).prefix(min(realBatch.count, 90)))

            if !capped.isEmpty {
                applyPosts(capped, replace: true, sessionId: feedSessionId)
                ContentCache.shared.setPosts(posts, for: .homeFeed)
                didPaint = true
                warmHead()
                hasMore = true
                recyclePass = 0
                #if DEBUG
                print("[HomeFeed] freshSession replace total=\(capped.count) following=\(sessionFollowingIDs.count) seed=\(sessionRankSeed)")
                #endif
            } else if posts.isEmpty {
                applyPosts([], replace: true, sessionId: feedSessionId)
                ContentCache.shared.invalidate(.homeFeed)
                hasMore = true
            }
        }

        isBootstrapping = false
    }

    /// Append / weave network rows **under** the visible head — never remounts what the user is watching.
    private func softMergePreservingHead(_ incoming: [CountryPost]) {
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
        let ranked = rankForSession(clean + posts)
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
                applyPosts(
                    BlockService.shared.filterPosts(
                        clean.excludingMoments().forHomeFeed()
                    ),
                    replace: true,
                    sessionId: feedSessionId
                )
                isBootstrapping = false
                didPaint = true
                warmHead()
            }
        }

        // 2) Light network first paint ONLY — never await full Sparks catalog here
        // (that blocked @MainActor for minutes and froze the feed).
        let live = Self.liveOnlyPosts(await PostsService.shared.fetchFirstPaintHomePosts(limit: 72))
        guard gen == generation else { return }

        // If cache already painted (or user started watching), soft-merge only.
        if didPaint && !posts.isEmpty {
            softMergePreservingHead(live)
            isBootstrapping = false
            hasMore = true
            recyclePass = 0
            #if DEBUG
            print("[HomeFeed] bootstrap soft-merge live=\(live.count) pool=\(posts.count)")
            #endif
        } else {
            let existingLive = posts.filter { !$0.isStory }
            let realBatch = Self.liveOnlyPosts(live + existingLive)
            let capped = Array(rankForSession(realBatch).prefix(min(realBatch.count, 90)))

            if !capped.isEmpty {
                applyPosts(capped, replace: true, sessionId: feedSessionId)
                ContentCache.shared.setPosts(posts, for: .homeFeed)
                didPaint = true
                warmHead()
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

        // 3) Warm a light Sparks catalog off the critical path so scroll has R2 fuel.
        // Deep (thousands) expands on demand in load-more — never block first paint.
        Task(priority: .utility) {
            _ = await PostsService.shared.loadSparksDiscoveryCatalog(forceRefresh: false, deep: false)
        }
    }

    /// Drop offline Reddit / catalog fakes; keep real UUID-backed posts only
    /// (includes DE Million Post Corpus seeds + their comments).
    /// **Keeps R2 Sparks** — they render as SparkFeedCard on the main feed.
    private static func liveOnlyPosts(_ posts: [CountryPost]) -> [CountryPost] {
        posts.forHomeFeed()
    }

    // MARK: - Scroll / prefetch

    /// Call from row `onAppear`. Prefetches media and next page at 65%.
    /// Fast fling: grow the local window aggressively, skip heavy network work until scroll settles.
    func onRowAppear(post: CountryPost) {
        ScrollBudget.noteCellAppear()
        // Any row appear counts as engagement — late network must not remount the head.
        userEngagedThisSession = true
        guard let index = displayedPosts.firstIndex(where: { $0.id == post.id }) else { return }

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

        // Media: fling = small ahead buffer; settled = deeper prefetch so sparks/videos land on time.
        let ahead = fling ? 4 : 10
        let end = min(displayedPosts.count, index + ahead)
        if index < end {
            let window = Array(displayedPosts[index..<end])
            ImageCache.shared.prefetchFeedMedia(window, maxPixelSize: fling ? 280 : 360)
            // Pre-buffer upcoming feed Sparks + playable clips so first frame is almost instant.
            let sparkPosts = window.filter {
                $0.isSparkFeedShare || $0.isReel || PlayPlatformBridge.isSparkFeedCard($0)
                    || $0.hasVideo || $0.playableVideoURL != nil
            }
            if !sparkPosts.isEmpty {
                SparkWarmPool.shared.prepare(
                    posts: sparkPosts,
                    around: 0,
                    ahead: max(0, sparkPosts.count - 1),
                    behind: 0
                )
            }
            if !fling {
                for p in window.prefix(4) {
                    guard let url = p.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) else { continue }
                    ArchiveVideoPlayback.warmResolve(url)
                }
            }
        }

        // Don't kick network load-more mid-fling (causes hitch + image storms).
        guard !fling else { return }

        let threshold = max(0, Int(Double(max(posts.count, 1)) * prefetchRatio) - 1)
        if index >= threshold, windowLimit >= posts.count - windowPageSize {
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

    func removePost(id: String) {
        posts.removeAll { $0.id == id }
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

        let filtered = rankForSession(live)
        applyPosts(filtered, replace: true, sessionId: feedSessionId)
        nextCursor = Self.cursor(from: filtered.last)
        // Always more — R2 library + network continue after this head.
        hasMore = true
        didPaint = !posts.isEmpty
        warmHead()
        if !filtered.isEmpty {
            ContentCache.shared.setPosts(posts, for: .homeFeed)
        } else {
            ContentCache.shared.invalidate(.homeFeed)
        }
        #if DEBUG
        print("[HomeFeed] hardRefresh live=\(live.count) total=\(filtered.count)")
        #endif
    }

    private func loadMore(generation gen: Int) async {
        // Prefer expanding the local window through the already-loaded pool.
        if windowLimit < posts.count {
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
        isLoadingMore = true
        defer { isLoadingMore = false }

        let cursor = nextCursor
        let seenIDs = Set(posts.map(\.id))
        let seenContent = Set(posts.map(\.homeFeedContentKey))
        let page = await PostsService.shared.loadHomeFeedPage(
            after: cursor,
            limit: pageSize,
            feedSessionId: feedSessionId,
            preferCache: false,
            excludingIDs: seenIDs
        )
        guard gen == generation, !Task.isCancelled else { return }

        var appended: [CountryPost] = []
        var seen = seenIDs
        var contentKeys = seenContent
        for post in page.items.dedupeHomeFeedContent() {
            // Already watched → never re-inject on scroll-more (same rule as open/reload).
            guard !SparkDiscoveryEngine.isViewed(post.id) else { continue }
            guard seen.insert(post.id).inserted else { continue }
            guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
            appended.append(post)
        }

        // Empty / all-dupes / all-viewed: unique R2 top-up only (never re-insert the whole head).
        if appended.isEmpty {
            recyclePass += 1
            let forceDeep = recyclePass == 1 || recyclePass % 4 == 0
            if forceDeep {
                _ = await PostsService.shared.loadSparksDiscoveryCatalog(
                    forceRefresh: recyclePass == 1,
                    deep: recyclePass >= 1
                )
            }
            let viewedExclude = Set(SparkDiscoveryEngine.viewedIDList(limit: 800))
            let topUp = await PostsService.shared.homeFeedSparkTopUp(
                excluding: seen.union(viewedExclude),
                limit: pageSize,
                forceRefresh: recyclePass > 2
            )
            for post in topUp {
                guard !SparkDiscoveryEngine.isViewed(post.id) else { continue }
                guard seen.insert(post.id).inserted else { continue }
                guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
                appended.append(post)
            }
            // Soft recycle ONLY when unviewed library is exhausted (deep session).
            // sessionHomeFeedOrder will still prefer least-recently-viewed first.
            if appended.isEmpty, posts.count >= 60, recyclePass >= 3 {
                let tailIDs = Set(posts.suffix(24).map(\.id))
                let tailKeys = Set(posts.suffix(24).map(\.homeFeedContentKey))
                let recycled = await PostsService.shared.homeFeedSparkTopUp(
                    excluding: tailIDs,
                    limit: pageSize,
                    forceRefresh: true
                )
                for post in recycled {
                    if tailIDs.contains(post.id) { continue }
                    if tailKeys.contains(post.homeFeedContentKey) { continue }
                    guard seen.insert(post.id).inserted else { continue }
                    appended.append(post)
                }
            }
        }

        if appended.isEmpty {
            // Keep trying on next scroll — never set hasMore false permanently.
            hasMore = true
            // Advance cursor from network even when items filtered as dups.
            if let next = page.nextCursor, next != cursor {
                nextCursor = next
            }
            return
        }

        // Rank new batch (unviewed only; follows first), then append without reordering the live head.
        let orderedAppend = rankForSession(appended)
        posts.append(contentsOf: orderedAppend)
        // Grow window so new rows appear without waiting for another appear cycle.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            windowLimit = min(posts.count, max(windowLimit + appended.count, windowLimit + windowPageSize))
        }
        // Prefer network cursor (not spark top-up dates) so we don't re-walk the head.
        nextCursor = page.nextCursor ?? Self.cursor(from: posts.last)
        hasMore = true
        ContentCache.shared.setPosts(Array(posts.prefix(ContentCache.maxCachedPosts)), for: .homeFeed)
        ImageCache.shared.prefetchFeedMedia(Array(appended.prefix(8)), maxPixelSize: 360)
        let sparkPosts = appended.filter {
            $0.isSparkFeedShare || $0.isReel || PlayPlatformBridge.isSparkFeedCard($0)
        }
        if !sparkPosts.isEmpty {
            SparkWarmPool.shared.prepare(
                posts: sparkPosts,
                around: 0,
                ahead: max(0, sparkPosts.count - 1),
                behind: 0
            )
        }
        #if DEBUG
        print("[HomeFeed] loadMore +\(appended.count) pool=\(posts.count) window=\(windowLimit) recycle=\(recyclePass)")
        #endif
    }

    private func applyPosts(_ next: [CountryPost], replace: Bool, sessionId: String) {
        feedSessionId = sessionId
        // Dedupe + session rank: unviewed only (following first). Seen posts never re-enter.
        let ordered = rankForSession(next)
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

    private func warmHead() {
        // First screen + next rows so sparks/videos paint on time (not after scroll).
        let head = Array(posts.prefix(max(firstWindow, 14)))
        ImageCache.shared.prefetchFeedMedia(head, maxPixelSize: 360)
        let sparks = head.filter {
            $0.isSparkFeedShare || $0.isReel || PlayPlatformBridge.isSparkFeedCard($0)
                || $0.hasVideo || $0.playableVideoURL != nil
        }
        if !sparks.isEmpty {
            SparkWarmPool.shared.prepare(
                posts: Array(sparks.prefix(8)),
                around: 0,
                ahead: min(6, max(0, sparks.count - 1)),
                behind: 0
            )
        }
        // Archive long-form hubs on the feed head.
        for post in head.prefix(6) {
            guard let url = post.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) else { continue }
            ArchiveVideoPlayback.warmResolve(url)
        }
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
