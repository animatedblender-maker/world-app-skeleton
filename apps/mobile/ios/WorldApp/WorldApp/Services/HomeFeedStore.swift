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

    private let pageSize = 12
    private let windowPageSize = 8
    private let firstWindow = 8
    /// Prefetch next page when user reaches ~65% of the currently loaded pool.
    private let prefetchRatio = 0.65

    private init() {}

    var displayedPosts: [CountryPost] {
        Array(posts.prefix(windowLimit))
    }

    var showsSkeleton: Bool {
        isBootstrapping && posts.isEmpty
    }

    // MARK: - Lifecycle

    /// Smooth open: cache → tiny first-paint network → done.
    /// Never multi-page GraphQL or hubs catalog on this path.
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
                    PostsService.shared.sessionFreshOrder(
                        BlockService.shared.filterPosts(clean.excludingMoments().excludingSparks())
                    ),
                    replace: true,
                    sessionId: feedSessionId
                )
                isBootstrapping = false
                didPaint = true
                warmHead()
            }
        }

        // 2) One light network round-trip — first paint algorithm only.
        let live = Self.liveOnlyPosts(await PostsService.shared.fetchFirstPaintHomePosts(limit: 40))
        guard gen == generation else { return }

        let existingLive = posts.filter { !$0.isStory }
        // Prefer fresh network; keep on-screen pins so list doesn't jump.
        let pinIDs = Set(posts.prefix(2).map(\.id))
        let realBatch = Self.liveOnlyPosts(live + existingLive)
        let merged = PostsService.shared.sessionFreshOrder(realBatch, pinIDs: pinIDs)
        let capped = Array(merged.prefix(min(merged.count, 48)))

        if !capped.isEmpty {
            applyPosts(capped, replace: true, sessionId: feedSessionId)
            ContentCache.shared.setPosts(posts, for: .homeFeed)
            didPaint = true
            warmHead()
            hasMore = true // always allow scroll-to-load (catalog is huge)
            #if DEBUG
            print("[HomeFeed] firstPaint total=\(capped.count) network=\(live.count)")
            #endif
        } else if posts.isEmpty {
            applyPosts([], replace: true, sessionId: feedSessionId)
            ContentCache.shared.invalidate(.homeFeed)
        }

        isBootstrapping = false
    }

    /// Drop offline Reddit / catalog fakes; keep real UUID-backed posts only
    /// (includes DE Million Post Corpus seeds + their comments).
    private static func liveOnlyPosts(_ posts: [CountryPost]) -> [CountryPost] {
        posts.filter { post in
            if post.authorID.hasPrefix("user_") { return false }
            if post.id.hasPrefix("post_") || post.id.hasPrefix("demo_") { return false }
            if post.id.hasPrefix("ia_") || post.id.hasPrefix("hub_") { return false }
            if post.isStory { return false }
            // Shared / live Sparks with video are OK on main feed (SparkFeedCard).
            // Offline hub catalog fakes only — never drop real UUID backend rows.
            if post.isHubSeedVideo { return false }
            // Archive seed / archive.org media — gated off (see AppConfig.archiveContentEnabled).
            if !AppConfig.archiveContentEnabled {
                if post.isArchiveSparkSource { return false }
                if PlayPlatformBridge.isArchiveCatalogMedia(post) { return false }
            }
            return true
        }
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
            hasMore = windowLimit < posts.count
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
            hasMore = windowLimit < posts.count
            return
        }
        guard hasMore, !isLoadingMore, !isBootstrapping else { return }
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

        // Pull-to-refresh may go a bit deeper than first paint, still capped.
        let live = Self.liveOnlyPosts(await PostsService.shared.fetchNetworkHomePosts(limit: 60))
        guard gen == generation else { return }

        // New session id → full reshuffle every pull-to-refresh.
        let filtered = PostsService.shared.sessionFreshOrder(live)
        applyPosts(filtered, replace: true, sessionId: feedSessionId)
        nextCursor = Self.cursor(from: filtered.last)
        hasMore = filtered.count >= pageSize || windowLimit < posts.count
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
        // Prefer expanding the local window through the already-loaded demo pool.
        if windowLimit < posts.count {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                windowLimit = min(posts.count, windowLimit + windowPageSize)
            }
            hasMore = windowLimit < posts.count
            return
        }

        guard hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let cursor = nextCursor
        let page = await PostsService.shared.loadHomeFeedPage(
            after: cursor,
            limit: pageSize,
            feedSessionId: feedSessionId,
            preferCache: false
        )
        guard gen == generation, !Task.isCancelled else { return }

        if page.items.isEmpty {
            hasMore = windowLimit < posts.count
            return
        }

        var seen = Set(posts.map(\.id))
        var appended: [CountryPost] = []
        for post in page.items where seen.insert(post.id).inserted {
            appended.append(post)
        }
        if appended.isEmpty {
            nextCursor = page.nextCursor
            hasMore = page.hasMore && page.nextCursor != cursor
            return
        }
        // Append shuffled page — never re-order the whole feed chronologically.
        posts.append(contentsOf: appended.shuffled())
        nextCursor = page.nextCursor
        hasMore = page.hasMore || windowLimit < posts.count
        ContentCache.shared.setPosts(posts, for: .homeFeed)
        ImageCache.shared.prefetchFeedMedia(Array(appended.prefix(6)), maxPixelSize: 360)
    }

    private func applyPosts(_ next: [CountryPost], replace: Bool, sessionId: String) {
        feedSessionId = sessionId
        // Already session-shuffled by fetch / hardRefresh; only re-shuffle if still chronological-looking.
        let ordered = next
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
            // Endless while local pool still has rows to reveal.
            hasMore = windowLimit < posts.count || ordered.count >= pageSize
        }
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
    static func cursor(from post: CountryPost?) -> String? {
        guard let post else { return nil }
        // Prefer raw ISO from server; fall back to parsed date.
        if !post.createdAt.isEmpty { return post.createdAt }
        return nil
    }
}
