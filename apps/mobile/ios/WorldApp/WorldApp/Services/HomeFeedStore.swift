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

    private let pageSize = 24
    private let windowPageSize = 12
    private let firstWindow = 10
    /// Prefetch next page when user reaches ~55% of the currently loaded pool.
    private let prefetchRatio = 0.55

    private init() {}

    var displayedPosts: [CountryPost] {
        Array(posts.prefix(windowLimit))
    }

    var showsSkeleton: Bool {
        isBootstrapping && posts.isEmpty
    }

    // MARK: - Lifecycle

    /// New browsing session (app open / 3+ min away / pull): **newest upload on top**.
    /// Network recency wins so R2 / backend pipeline posts always surface first.
    func beginFreshSession() async {
        generation += 1
        let gen = generation
        errorMessage = nil
        feedSessionId = UUID().uuidString
        nextCursor = nil
        hasMore = true
        isRefreshing = true
        defer { isRefreshing = false }

        // 1) Instant paint from memory / disk — still newest-first (not shuffled).
        var pool: [CountryPost] = posts
        if pool.isEmpty, let cached = ContentCache.shared.posts(for: .homeFeed) {
            pool = Self.liveOnlyPosts(cached)
        }
        pool = Self.liveOnlyPosts(
            BlockService.shared.filterPosts(pool.excludingMoments().forHomeFeed())
        )
        if !pool.isEmpty {
            let fresh = PostsService.shared.chronologicalNewestFirst(pool.dedupeHomeFeedContent())
            applyPosts(Array(fresh.prefix(80)), replace: true, sessionId: feedSessionId)
            isBootstrapping = false
            didPaint = true
            warmHead()
        } else {
            isBootstrapping = true
        }

        // 2) Network page — last uploaded always at top (includes R2 Sparks).
        let live = Self.liveOnlyPosts(await PostsService.shared.fetchFirstPaintHomePosts(limit: 64))
        guard gen == generation else { return }

        let realBatch = Self.liveOnlyPosts(live + posts).dedupeHomeFeedContent()
        let merged = PostsService.shared.chronologicalNewestFirst(realBatch)
        // First paint head only — load-more pulls the rest of the 28k+ library.
        let capped = Array(merged.prefix(min(merged.count, 80)))

        if !capped.isEmpty {
            applyPosts(capped, replace: true, sessionId: feedSessionId)
            ContentCache.shared.setPosts(posts, for: .homeFeed)
            didPaint = true
            warmHead()
            hasMore = true // endless — R2 + network continue on scroll
            recyclePass = 0
            #if DEBUG
            print("[HomeFeed] freshSession total=\(capped.count) network=\(live.count) newest=\(capped.first?.id.prefix(8) ?? "-")")
            #endif
        } else if posts.isEmpty {
            applyPosts([], replace: true, sessionId: feedSessionId)
            ContentCache.shared.invalidate(.homeFeed)
            hasMore = true
        }

        isBootstrapping = false
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

        // 1) Instant paint from cache (sign-in / relaunch must not wait on network).
        if posts.isEmpty, let cached = ContentCache.shared.posts(for: .homeFeed), !cached.isEmpty {
            let clean = Self.liveOnlyPosts(cached)
            if clean.isEmpty {
                ContentCache.shared.invalidate(.homeFeed)
            } else {
                applyPosts(
                    PostsService.shared.chronologicalNewestFirst(
                        BlockService.shared.filterPosts(
                            clean.excludingMoments().forHomeFeed().dedupeHomeFeedContent()
                        )
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
        let live = Self.liveOnlyPosts(await PostsService.shared.fetchFirstPaintHomePosts(limit: 64))
        guard gen == generation else { return }

        let existingLive = posts.filter { !$0.isStory }
        let realBatch = Self.liveOnlyPosts(live + existingLive).dedupeHomeFeedContent()
        let merged = PostsService.shared.chronologicalNewestFirst(realBatch)
        let capped = Array(merged.prefix(min(merged.count, 80)))

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

        // Media: fling = small ahead buffer; settled = normal prefetch.
        let ahead = fling ? 3 : 6
        let end = min(displayedPosts.count, index + ahead)
        if index < end {
            let window = Array(displayedPosts[index..<end])
            ImageCache.shared.prefetchFeedMedia(window, maxPixelSize: fling ? 280 : 360)
            // Pre-buffer upcoming feed Sparks so first frame is almost instant.
            let sparkPosts = window.filter {
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

        // Pull-to-refresh may go a bit deeper than first paint, still capped for smoothness.
        let live = Self.liveOnlyPosts(await PostsService.shared.fetchNetworkHomePosts(limit: 100))
        guard gen == generation else { return }

        // Newest upload first — pull-to-refresh must surface brand-new R2/backend posts.
        let filtered = PostsService.shared.chronologicalNewestFirst(live)
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
            guard seen.insert(post.id).inserted else { continue }
            guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
            appended.append(post)
        }

        // Empty / all-dupes: unique R2 top-up only (never re-insert the whole head).
        if appended.isEmpty {
            recyclePass += 1
            let forceDeep = recyclePass == 1 || recyclePass % 4 == 0
            if forceDeep {
                _ = await PostsService.shared.loadSparksDiscoveryCatalog(
                    forceRefresh: recyclePass == 1,
                    deep: recyclePass >= 1
                )
            }
            let topUp = await PostsService.shared.homeFeedSparkTopUp(
                excluding: seen,
                limit: pageSize,
                forceRefresh: recyclePass > 2
            )
            for post in topUp {
                guard seen.insert(post.id).inserted else { continue }
                guard contentKeys.insert(post.homeFeedContentKey).inserted else { continue }
                appended.append(post)
            }
            // Soft recycle ONLY after a deep session — never on first empty page
            // (that was doubling every post: network dups → re-inject same sparks).
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

        // Append unique content only.
        posts.append(contentsOf: appended)
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
        // Always collapse original+share pairs and id dups.
        let ordered = next.dedupeHomeFeedContent()
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts = ordered
            if replace {
                windowLimit = min(firstWindow, max(ordered.count, 0))
            }
        }
        if !ordered.isEmpty {
            nextCursor = Self.cursor(from: ordered.last)
        }
        hasMore = true
    }

    private func warmHead() {
        // Only what the first screen can show — never warm the whole pool.
        let head = Array(posts.prefix(firstWindow))
        ImageCache.shared.prefetchFeedMedia(head, maxPixelSize: 320)
        let sparks = head.prefix(2).filter {
            $0.isSparkFeedShare || $0.isReel || PlayPlatformBridge.isSparkFeedCard($0)
        }
        if !sparks.isEmpty {
            SparkWarmPool.shared.prepare(posts: Array(sparks), around: 0, ahead: 1, behind: 0)
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
