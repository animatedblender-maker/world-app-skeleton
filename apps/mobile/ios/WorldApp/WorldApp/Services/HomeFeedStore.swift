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

    /// Must happen now: paint cache. Later: soft revalidate.
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

        // 1) Instant paint from cache if any (may be demo-only — network still runs below).
        if posts.isEmpty, let cached = ContentCache.shared.posts(for: .homeFeed), !cached.isEmpty {
            applyPosts(
                BlockService.shared.filterPosts(cached.forProfileFeedGrid()),
                replace: true,
                sessionId: feedSessionId
            )
            isBootstrapping = false
            didPaint = true
            warmHead()
        }

        // 2) Network live posts + demo filler in parallel.
        //    Critical: never skip network because a fat demo cache is "fresh".
        async let liveTask = PostsService.shared.fetchNetworkHomePosts(limit: 80)
        async let demoTask: [CountryPost] = {
            guard AppConfig.useDemoDataset else { return [] }
            return await PostsService.shared.sampleGlobalPosts(limit: AppConfig.demoDatasetMaxPosts)
        }()

        let live = await liveTask
        let demoRaw = await demoTask
        guard gen == generation else { return }

        let demo = BlockService.shared.filterPosts(demoRaw.forProfileFeedGrid())
        // Keep any live rows already in memory (e.g. just-created post) + fresh network.
        let existingLive = posts.filter { !$0.isSeededOrSynthetic && !$0.isStory && !$0.isSpark }
        let realBatch = live + existingLive
        let merged = PostsService.shared.mergePosts(
            real: realBatch,
            demo: demo,
            limit: max(demo.count + realBatch.count, 50)
        )

        if !merged.isEmpty {
            applyPosts(merged, replace: true, sessionId: feedSessionId)
            ContentCache.shared.setPosts(merged, for: .homeFeed)
            didPaint = true
            warmHead()
            hasMore = windowLimit < posts.count
            #if DEBUG
            let liveN = merged.filter(\.isRealPersonFeedPost).count
            print("[HomeFeed] bootstrap live=\(liveN) total=\(merged.count) networkRaw=\(live.count)")
            #endif
        }

        isBootstrapping = false
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
        let ahead = fling ? 2 : 5
        let end = min(displayedPosts.count, index + ahead)
        if index < end {
            ImageCache.shared.prefetchFeedMedia(Array(displayedPosts[index..<end]), maxPixelSize: fling ? 280 : 360)
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
        guard !post.isSpark, !post.isStory else { return }
        if posts.contains(where: { $0.id == post.id }) {
            applyLocalUpdate(post)
            return
        }
        // New live posts always pin to the top of the feed (above demo seed).
        if post.isSeededOrSynthetic {
            if let firstSeed = posts.firstIndex(where: \.isSeededOrSynthetic) {
                posts.insert(post, at: firstSeed)
            } else {
                posts.append(post)
            }
        } else {
            posts.insert(post, at: 0)
        }
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

        async let liveTask = PostsService.shared.fetchNetworkHomePosts(limit: 80)
        async let demoTask: [CountryPost] = {
            guard AppConfig.useDemoDataset else { return [] }
            return await PostsService.shared.sampleGlobalPosts(limit: AppConfig.demoDatasetMaxPosts)
        }()

        let live = await liveTask
        let demoRaw = await demoTask
        guard gen == generation else { return }

        let demo = BlockService.shared.filterPosts(demoRaw.forProfileFeedGrid())
        let filtered = PostsService.shared.mergePosts(
            real: live,
            demo: demo,
            limit: max(demo.count + live.count, 50)
        )
        applyPosts(filtered, replace: true, sessionId: feedSessionId)
        nextCursor = Self.cursor(from: filtered.last)
        hasMore = filtered.count >= pageSize || windowLimit < posts.count
        didPaint = !posts.isEmpty
        warmHead()
        if !filtered.isEmpty {
            ContentCache.shared.setPosts(posts, for: .homeFeed)
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
        // Real people from the new page slot into the people tier; seed stays below.
        let people = appended.filter(\.isRealPersonFeedPost)
        let filler = appended.filter { !$0.isRealPersonFeedPost }
        if people.isEmpty {
            posts.append(contentsOf: filler)
        } else if let firstSeed = posts.firstIndex(where: { !$0.isRealPersonFeedPost }) {
            posts.insert(contentsOf: people, at: firstSeed)
            posts.append(contentsOf: filler)
        } else {
            posts.append(contentsOf: people + filler)
        }
        nextCursor = page.nextCursor
        hasMore = page.hasMore || windowLimit < posts.count
        ContentCache.shared.setPosts(posts, for: .homeFeed)
        ImageCache.shared.prefetchFeedMedia(Array(appended.prefix(6)), maxPixelSize: 360)
    }

    private func applyPosts(_ next: [CountryPost], replace: Bool, sessionId: String) {
        feedSessionId = sessionId
        // Trust caller order (`mergePosts` already puts network live above demo).
        // Do NOT re-run prioritizeRealPeopleFeed here — it can bury edge-case live rows.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            if replace {
                posts = next
                windowLimit = min(firstWindow, max(next.count, 0))
            } else {
                posts = next
            }
        }
        if !next.isEmpty {
            nextCursor = Self.cursor(from: next.last)
            // Endless while local pool still has rows to reveal.
            hasMore = windowLimit < posts.count || next.count >= pageSize
        }
    }

    private func warmHead() {
        ImageCache.shared.prefetchFeedMedia(Array(posts.prefix(firstWindow + 2)), maxPixelSize: 360)
    }

    /// Opaque cursor for GraphQL `before` (created_at timestamptz).
    static func cursor(from post: CountryPost?) -> String? {
        guard let post else { return nil }
        // Prefer raw ISO from server; fall back to parsed date.
        if !post.createdAt.isEmpty { return post.createdAt }
        return nil
    }
}
