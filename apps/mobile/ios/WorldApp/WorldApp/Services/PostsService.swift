import Foundation
import UIKit

@MainActor
final class PostsService {
    static let shared = PostsService()

    private let gql = GraphQLService.shared
    private let demo = DemoDatasetService.shared
    private let follow = FollowService.shared

    private init() {}

    private let postFields = """
    id title body media_type media_url thumb_url shared_post_id
    shared_post {
      id title body media_type media_url thumb_url author_id
      like_count comment_count
      author { user_id display_name username avatar_url country_name country_code }
    }
    visibility like_count comment_count liked_by_me
    created_at updated_at author_id country_name country_code city_name
    author { user_id display_name username avatar_url country_name country_code }
    """

    private let postFieldsWithBookmarks = """
    id title body media_type media_url thumb_url shared_post_id
    shared_post {
      id title body media_type media_url thumb_url author_id
      like_count comment_count
      author { user_id display_name username avatar_url country_name country_code }
    }
    visibility like_count comment_count liked_by_me saved_by_me
    created_at updated_at author_id country_name country_code city_name
    author { user_id display_name username avatar_url country_name country_code }
    """

    func listByCountry(_ countryCode: String, limit: Int = 25) async throws -> [CountryPost] {
        let code = countryCode.uppercased()
        if AppConfig.useDemoDataset {
            async let realTask = fetchRealPostsByCountry(code, limit: max(limit, 40))
            async let demoTask = demo.listByCountry(code, limit: max(limit, 40))
            let real = (try? await realTask) ?? []
            let demoPosts = await demoTask
            return mergePosts(real: real, demo: demoPosts, limit: limit)
        }
        return try await fetchRealPostsByCountry(code, limit: limit)
    }

    func listForAuthor(_ authorID: String, limit: Int = 25) async throws -> [CountryPost] {
        if ScreenshotMode.isActive, authorID == ScreenshotMode.demoProfile.userID {
            if let cached = ContentCache.shared.posts(for: .profilePosts) {
                return Array(cached.prefix(limit))
            }
            return Array(await demo.sampleGlobalPosts(limit: limit).prefix(limit))
        }
        if AppConfig.useDemoDataset, authorID.hasPrefix("user_") {
            return await demo.listForAuthor(authorID, limit: limit)
        }
        struct Response: Decodable { let postsByAuthor: [GraphQLPost] }
        let query = """
        query PostsByAuthor($authorId: ID!, $limit: Int) {
          postsByAuthor(user_id: $authorId, limit: $limit) { \(postFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["authorId": authorID, "limit": limit])
        return result.postsByAuthor.map(\.toModel)
    }

    func loadFollowingFeed(limitPerAuthor: Int = 4, maxAuthors: Int = 12) async -> [CountryPost] {
        let followingIDs = Array(await follow.followingIDs().prefix(maxAuthors))
        guard !followingIDs.isEmpty else { return [] }

        var merged: [CountryPost] = []
        await withTaskGroup(of: [CountryPost].self) { group in
            for authorID in followingIDs {
                group.addTask {
                    (try? await self.listForAuthor(authorID, limit: limitPerAuthor)) ?? []
                }
            }
            for await batch in group { merged.append(contentsOf: batch) }
        }
        return merged.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
    }

    /// Country feed posts: local country posts plus followed creators posting from abroad.
    func loadCountryFeedPosts(
        countryISO: String,
        localLimit: Int = 30,
        followingLimitPerAuthor: Int = 5,
        maxAuthors: Int = 24
    ) async throws -> [CountryPost] {
        let iso = countryISO.uppercased()
        async let localTask = listByCountry(iso, limit: localLimit)
        async let followingTask = loadFollowingFeed(
            limitPerAuthor: followingLimitPerAuthor,
            maxAuthors: maxAuthors
        )

        let local = try await localTask
        let following = await followingTask
        let localIDs = Set(local.map(\.id))
        let abroadFollowing = following.filter { post in
            guard !localIDs.contains(post.id) else { return false }
            let postISO = post.countryCode?.uppercased() ?? ""
            return !postISO.isEmpty && postISO != iso
        }

        return mergeFeedSources([local, abroadFollowing], limit: localLimit + abroadFollowing.count)
            .excludingMoments()
            .excludingSparks()
    }

    func loadHomeFeed(
        followingLimitPerAuthor: Int = 4,
        globalLimit: Int = 40,
        maxPosts: Int = 50,
        forceRefresh: Bool = false
    ) async -> [CountryPost] {
        if !forceRefresh,
           ContentCache.shared.isFresh(.homeFeed),
           let cached = ContentCache.shared.posts(for: .homeFeed) {
            return cached
        }

        let live = await fetchNetworkHomePosts(limit: max(globalLimit, maxPosts))
        var demo: [CountryPost] = []
        if AppConfig.useDemoDataset {
            demo = await sampleGlobalPosts(limit: min(AppConfig.demoDatasetMaxPosts, max(maxPosts * 4, 80)))
        }
        var merged = mergePosts(real: live, demo: demo, limit: max(maxPosts, live.count + min(demo.count, 40)))
            .excludingMoments()
            .excludingSparks()
        if merged.isEmpty {
            merged = await fallbackFeedPosts(limit: maxPosts).excludingSparks()
        }
        if !merged.isEmpty {
            ContentCache.shared.setPosts(merged, for: .homeFeed)
        } else {
            ContentCache.shared.invalidate(.homeFeed)
        }
        return merged
    }

    /// Launch markets — feed must surface all four, not only the viewer's home country.
    private static let focusMarketCodes = ["US", "DE", "EG", "AL"]

    /// **Smooth first paint** after sign-in / cold open.
    /// Newest upload first so backend / R2 pipeline posts surface immediately at the top.
    func fetchFirstPaintHomePosts(limit: Int = 40) async -> [CountryPost] {
        await prepareFeedContext()
        let pageLimit = min(max(limit, 24), 48)
        // Dense spark-share walk, then sort by created_at (newest first).
        async let recentTask = fetchRecentFeedPosts(limit: pageLimit, preferSparkShares: true)
        async let ownTask = fetchOwnPosts(limit: 8)
        let recent = await recentTask
        let own = await ownTask

        var combined = own + recent
        combined = combined
            .excludingMoments()
            .excludingSparks()
            .excludingArchiveContent()
            .filter { post in
                if post.authorID.hasPrefix("user_") || post.id.hasPrefix("post_") { return false }
                if post.id.hasPrefix("demo_") { return false }
                if post.isHubSeedVideo { return false }
                return true
            }
        // Last uploaded always on top — no shuffle.
        var merged = chronologicalNewestFirst(combined)
        if merged.count > pageLimit {
            merged = Array(merged.prefix(pageLimit))
        }
        return merged
    }

    /// Live network posts for pull-to-refresh / deeper revalidate (still bounded for smoothness).
    func fetchNetworkHomePosts(limit: Int = 80) async -> [CountryPost] {
        await prepareFeedContext()
        let cap = min(max(limit, 40), 100)
        async let ownTask = fetchOwnPosts(limit: 12)
        async let recentTask = fetchRecentPosts(limit: min(cap, 60))
        async let focusTask = fetchFocusMarketPosts(limit: min(48, cap))

        let own = await ownTask
        let recent = await recentTask
        let focus = await focusTask

        var combined: [CountryPost] = []
        combined.append(contentsOf: own)
        combined.append(contentsOf: focus)
        combined.append(contentsOf: recent)

        var merged = chronologicalNewestFirst(combined)
            .excludingMoments()
            .excludingSparks() // originals stay in Sparks player; spark *shares* pass through
            .excludingArchiveContent()
            .filter { post in
                if post.authorID.hasPrefix("user_") || post.id.hasPrefix("post_") { return false }
                if post.id.hasPrefix("demo_") { return false }
                if post.isHubSeedVideo { return false }
                return true
            }
        // Pure recency — last uploaded always at top (no density reshuffle).
        if merged.count > cap {
            merged = Array(merged.prefix(cap))
        }
        if merged.isEmpty {
            merged = chronologicalNewestFirst(
                await fallbackFeedPosts(limit: cap).excludingSparks()
                    .filter { !$0.authorID.hasPrefix("user_") && !$0.id.hasPrefix("post_") }
            )
        }
        return merged
    }

    /// Prefer Spark shares and video rows near the head without fully breaking recency.
    private func rankFeedForSparkDensity(_ posts: [CountryPost]) -> [CountryPost] {
        guard posts.count > 8 else { return posts }
        // Soft interleave: take windows of ~12 newest, put spark shares / video first inside each window.
        var out: [CountryPost] = []
        out.reserveCapacity(posts.count)
        let window = 12
        var i = 0
        while i < posts.count {
            let end = min(posts.count, i + window)
            var slice = Array(posts[i..<end])
            slice.sort { a, b in
                let aspark = a.isSparkFeedShare || a.isHubOriginFeedShare || (a.hasVideo && !a.isSpark)
                let bspark = b.isSparkFeedShare || b.isHubOriginFeedShare || (b.hasVideo && !b.isSpark)
                if aspark != bspark { return aspark && !bspark }
                return a.createdAt > b.createdAt
            }
            out.append(contentsOf: slice)
            i = end
        }
        return out
    }

    /// Round-robin US / DE / EG / AL so the home feed isn't one-country heavy.
    private func balanceFocusMarkets(_ posts: [CountryPost], limit: Int) -> [CountryPost] {
        guard posts.count > 12 else { return posts }
        var buckets: [String: [CountryPost]] = Dictionary(
            uniqueKeysWithValues: Self.focusMarketCodes.map { ($0, []) }
        )
        var other: [CountryPost] = []
        for post in posts {
            let code = (post.countryCode ?? "").uppercased()
            if buckets[code] != nil {
                buckets[code, default: []].append(post)
            } else {
                other.append(post)
            }
        }
        var out: [CountryPost] = []
        out.reserveCapacity(min(limit, posts.count))
        var indices = Dictionary(uniqueKeysWithValues: Self.focusMarketCodes.map { ($0, 0) })
        while out.count < limit {
            var added = false
            for code in Self.focusMarketCodes {
                let list = buckets[code] ?? []
                let i = indices[code] ?? 0
                guard i < list.count else { continue }
                out.append(list[i])
                indices[code] = i + 1
                added = true
                if out.count >= limit { break }
            }
            if !added { break }
        }
        // Append remaining non-focus after a balanced core.
        if out.count < limit {
            var seen = Set(out.map(\.id))
            for post in other where seen.insert(post.id).inserted {
                out.append(post)
                if out.count >= limit { break }
            }
        }
        // Fill any leftover slots from unused focus items.
        if out.count < limit {
            var seen = Set(out.map(\.id))
            for code in Self.focusMarketCodes {
                for post in buckets[code] ?? [] where seen.insert(post.id).inserted {
                    out.append(post)
                    if out.count >= limit { break }
                }
                if out.count >= limit { break }
            }
        }
        return out
    }

    /// Explicit pull from each launch market (GraphQL postsByCountry).
    private func fetchFocusMarketPosts(limit: Int) async -> [CountryPost] {
        let per = max(10, min(20, limit / max(Self.focusMarketCodes.count, 1)))
        var combined: [CountryPost] = []
        await withTaskGroup(of: [CountryPost].self) { group in
            for code in Self.focusMarketCodes {
                group.addTask {
                    ((try? await self.listByCountry(code, limit: per)) ?? [])
                        .excludingMoments()
                        .excludingSparks()
                }
            }
            for await batch in group {
                combined.append(contentsOf: batch)
            }
        }
        return chronologicalNewestFirst(combined)
    }

    /// Deep pull of R2 Spark *originals* from all four focus countries for the Sparks player.
    private func fetchFocusMarketSparks(limitPerCountry: Int = 100) async -> [CountryPost] {
        let per = min(max(limitPerCountry, 40), 500)
        var combined: [CountryPost] = []
        await withTaskGroup(of: [CountryPost].self) { group in
            for code in Self.focusMarketCodes {
                group.addTask {
                    let batch = (try? await self.listByCountry(code, limit: per)) ?? []
                    return batch.filter { ReelsRankingEngine.isSparkEligible($0) }
                }
            }
            for await batch in group {
                combined.append(contentsOf: batch)
            }
        }
        return combined
    }

    /// Whether a usable Sparks pool is already in memory (no network).
    var sparksCatalogIsWarm: Bool {
        sparksSessionCatalog.count >= 40
    }

    /// Snapshot of the in-memory Sparks pool (may be empty).
    func sparksCatalogSnapshot() -> [CountryPost] {
        sparksSessionCatalog
    }

    /// Session Sparks pool.
    /// - `deep: false`: medium fill for feed rails / first swipe (safe on feed open).
    /// - `deep: true`: large R2 channel + country sample for the Sparks player.
    /// Always re-ranks on return so order is never frozen for 20 minutes.
    func loadSparksDiscoveryCatalog(forceRefresh: Bool = false, deep: Bool = false) async -> [CountryPost] {
        let minWarm = deep ? 120 : 40
        let cacheTTL: TimeInterval = deep ? 8 * 60 : 3 * 60
        let cacheOK = !forceRefresh
            && sparksSessionCatalog.count >= minWarm
            && !(deep && sparksSessionCatalog.count < 120)
            && sparksSessionLoadedAt.map { Date().timeIntervalSince($0) < cacheTTL } == true

        if cacheOK {
            // Same pool, **pure shuffle** every call — discovery rank was sticky across opens.
            let snapshot = sparksSessionCatalog
            return await Task.detached(priority: .utility) {
                snapshot.shuffled()
            }.value
        }

        await prepareFeedContext()
        await Task.yield()

        if !deep {
            // Wider light pull so rails aren't stuck on ~8–16 IDs.
            async let country = fetchFocusMarketSparks(limitPerCountry: 100)
            async let hubSparks = fetchFocusMarketHubSparks(limitPerAuthor: 200)
            async let recent = fetchRecentPosts(limit: 80)
            let countryBatch = await country
            let hubBatch = await hubSparks
            let recentBatch = await recent
            await Task.yield()

            var merged: [CountryPost] = []
            var seen = Set<String>()
            // Prefer existing catalog so we grow, not thrash.
            for post in sparksSessionCatalog + hubBatch + countryBatch + recentBatch {
                guard seen.insert(post.id).inserted else { continue }
                guard ReelsRankingEngine.isSparkEligible(post) else { continue }
                merged.append(post)
            }
            let shuffled = await Task.detached(priority: .utility) {
                merged.shuffled()
            }.value
            if shuffled.count >= sparksSessionCatalog.count || sparksSessionCatalog.isEmpty {
                sparksSessionCatalog = shuffled
                sparksSessionLoadedAt = Date()
            }
            #if DEBUG
            print("[Sparks] light catalog size=\(sparksSessionCatalog.count)")
            #endif
            if sparksSessionCatalog.isEmpty { return shuffled }
            let snapshot = sparksSessionCatalog
            return await Task.detached(priority: .utility) {
                snapshot.shuffled()
            }.value
        }

        // Deep: max channel lists (API cap 500/author) + multi-country + recent pages.
        // Goal: entire R2 Spark library available in-session (thousands when seeded).
        async let hubSparks = fetchFocusMarketHubSparks(limitPerAuthor: 500)
        async let countrySparks = fetchFocusMarketSparks(limitPerCountry: 500)
        async let recent = fetchRecentPosts(limit: 120)
        let hubBatch = await hubSparks
        await Task.yield()
        let countryBatch = await countrySparks
        await Task.yield()
        let recentBatch = await recent
        await Task.yield()

        var merged: [CountryPost] = []
        var seen = Set<String>()
        for post in hubBatch + countryBatch + recentBatch + sparksSessionCatalog {
            guard seen.insert(post.id).inserted else { continue }
            guard ReelsRankingEngine.isSparkEligible(post) else { continue }
            merged.append(post)
        }

        // Page further recent posts for more Sparks (new R2 uploads land here first).
        var before: String? = recentBatch.last?.createdAt
        for _ in 0..<6 {
            let page = await fetchRecentPosts(limit: 100, before: before)
            if page.isEmpty { break }
            var added = 0
            for post in page {
                guard seen.insert(post.id).inserted else { continue }
                guard ReelsRankingEngine.isSparkEligible(post) else { continue }
                merged.append(post)
                added += 1
            }
            before = page.last?.createdAt
            if page.count < 40 || added == 0 { break }
            await Task.yield()
        }

        // Optional Archive seed top-up (when enabled).
        if AppConfig.archiveContentEnabled {
            let seed = UInt64.random(in: 1...UInt64.max) ^ UInt64(Date().timeIntervalSince1970 * 1_000)
            let archive = await HubVideoSeedService.shared.sparkSeedVideos(limit: nil, shuffleSeed: seed)
            for post in archive {
                guard seen.insert(post.id).inserted else { continue }
                guard ReelsRankingEngine.isSparkEligible(post) else { continue }
                merged.append(post)
            }
        }

        // Store unsorted pool; callers that need a fresh order use beginFreshSparksSession / shuffle.
        sparksSessionCatalog = merged
        sparksSessionLoadedAt = Date()
        #if DEBUG
        print("[Sparks] deep catalog size=\(merged.count)")
        #endif
        // Return a shuffled view so even cache-less deep loads feel random.
        let seed = UInt64.random(in: 1...UInt64.max) ^ UInt64(merged.count)
        var rng = SeededRNG(seed: seed)
        var shuffled = merged
        shuffled.shuffle(using: &rng)
        return shuffled
    }

    /// Thread-safe snapshot for detached ranking (avoid capturing mutable actor state oddly).
    private func sparksSessionCatalogSnapshot() -> [CountryPost] {
        sparksSessionCatalog
    }

    /// Drop session pool so next open must re-fetch + re-rank (call when leaving Sparks / feed long enough).
    func invalidateSparksDiscoveryCatalog() {
        sparksSessionLoadedAt = nil
    }

    /// **Every Sparks player open** (feed / chat / Hubs / strip / menu): full catalog + pure shuffle.
    /// Returns only **eligible originals** so the queue is thousands of distinct Sparks, not recycled shares.
    func beginFreshSparksSession(preferStart: CountryPost? = nil) async -> [CountryPost] {
        SparkDiscoveryEngine.resetSession()
        ReelsRankingEngine.resetSession()
        invalidateSparksDiscoveryCatalog()

        // Always deep + force — max R2 channel lists + multi-country sparks.
        var catalog = await loadSparksDiscoveryCatalog(forceRefresh: true, deep: true)

        // Extra recent pages so brand-new uploads join the pool this session.
        var seen = Set(catalog.map(\.id))
        var before: String? = nil
        for _ in 0..<8 {
            let page = await fetchRecentPosts(limit: 100, before: before)
            if page.isEmpty { break }
            for post in page where seen.insert(post.id).inserted {
                guard ReelsRankingEngine.isSparkEligible(post) else { continue }
                catalog.append(post)
            }
            before = page.last?.createdAt
            if page.count < 40 { break }
        }

        // Hard filter — drop any share shells / long-form that slipped in.
        catalog = catalog.filter { ReelsRankingEngine.isSparkEligible($0) && $0.playableVideoURL != nil }
        seen = Set(catalog.map(\.id))

        // Pure random order every open (not sticky “rank” order).
        let seed = UInt64.random(in: 1...UInt64.max)
            ^ UInt64(Date().timeIntervalSince1970 * 1_000_000)
            ^ UInt64(catalog.count &<< 12)
        var rng = SeededRNG(seed: seed)
        catalog.shuffle(using: &rng)

        if let rawStart = preferStart {
            let start = ReelsRankingEngine.resolvePlayerStart(rawStart)
            if start.playableVideoURL != nil {
                catalog.removeAll { $0.id == start.id }
                catalog.insert(start, at: 0)
                seen.insert(start.id)
            }
        }

        sparksSessionCatalog = catalog
        sparksSessionLoadedAt = Date()
        #if DEBUG
        print("[Sparks] fresh session size=\(catalog.count) seed=\(seed)")
        #endif
        return catalog
    }

    /// Deterministic PRNG for session shuffles (Swift RandomNumberGenerator).
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// Walk `recentPosts` pages until we have enough feed items (spark shares + text + long video).
    /// Always returns **newest upload first** so R2/backend posts land at the top of the feed.
    private func fetchRecentFeedPosts(limit: Int, preferSparkShares: Bool) async -> [CountryPost] {
        _ = preferSparkShares // density is product preference; recency is the hard rule
        var collected: [CountryPost] = []
        var seen = Set<String>()
        var before: String? = nil
        // Max 2 pages — smoothness first; scroll load-more covers the long tail.
        let maxPages = 2
        let stopAt = max(limit, 80)
        for _ in 0..<maxPages {
            let batch = await fetchRecentPosts(limit: min(60, stopAt), before: before)
                .filter { post in
                    !post.isSpark && !post.isStory
                        && !post.authorID.hasPrefix("user_")
                        && !post.id.hasPrefix("post_")
                }
            if batch.isEmpty { break }
            for post in batch {
                guard seen.insert(post.id).inserted else { continue }
                collected.append(post)
            }
            before = batch.last?.createdAt
            if batch.count < 30 { break }
            if collected.count >= stopAt { break }
        }
        var merged = chronologicalNewestFirst(collected)
        if merged.count > limit { merged = Array(merged.prefix(limit)) }
        return merged
    }

    /// Walk `recentPosts` pages until we have enough non-spark text/feed items.
    private func fetchRecentTextPosts(limit: Int) async -> [CountryPost] {
        await fetchRecentFeedPosts(limit: limit, preferSparkShares: false)
    }

    /// Paginated home page for infinite scroll (cursor = createdAt of last item).
    func loadHomeFeedPage(
        after cursor: String?,
        limit: Int,
        feedSessionId: String,
        preferCache: Bool
    ) async -> HomeFeedPage {
        _ = feedSessionId
        if preferCache,
           cursor == nil,
           let cached = ContentCache.shared.posts(for: .homeFeed),
           !cached.isEmpty {
            let slice = Array(cached.prefix(limit))
            return HomeFeedPage(
                items: slice,
                nextCursor: HomeFeedStore.cursor(from: slice.last),
                hasMore: cached.count > limit,
                feedSessionId: feedSessionId
            )
        }

        let network = await fetchRecentPosts(limit: max(limit, 20), before: cursor)
            .excludingMoments()
            .excludingSparks()
        // Newest first (cursor pages are already recent → older).
        let items = Array(chronologicalNewestFirst(network).prefix(limit))
        let next = HomeFeedStore.cursor(from: items.last)
        return HomeFeedPage(
            items: items,
            nextCursor: next,
            hasMore: items.count >= limit && next != nil && next != cursor,
            feedSessionId: feedSessionId
        )
    }

    func loadReelsFeed(
        followingLimitPerAuthor: Int = 10,
        globalLimit: Int = 40,
        viewerCountry: String? = nil,
        followingIDs: Set<String> = []
    ) async -> [CountryPost] {
        let page = await loadReelsFeedPage(
            excludingIDs: [],
            cursor: nil,
            batchSize: globalLimit,
            fetchLimit: max(globalLimit, 40),
            followingLimitPerAuthor: followingLimitPerAuthor,
            viewerCountry: viewerCountry,
            followingIDs: followingIDs,
            tail: [],
            allowRecycle: false
        )
        return page.posts
    }

    /// Paginated endless spark feed — discovery ranking; never blocks UI on a full-catalog pull.
    func loadReelsFeedPage(
        excludingIDs: Set<String>,
        cursor: String? = nil,
        batchSize: Int = 12,
        fetchLimit: Int = 48,
        followingLimitPerAuthor: Int = 10,
        viewerCountry: String? = nil,
        followingIDs: Set<String> = [],
        tail: [CountryPost] = [],
        allowRecycle: Bool = false
    ) async -> ReelsFeedPage {
        await prepareFeedContext()

        // Prefer in-memory catalog; otherwise light fill (deep catalog warms in background).
        var candidates: [CountryPost]
        if sparksCatalogIsWarm {
            candidates = sparksSessionCatalog
        } else {
            candidates = await loadSparksDiscoveryCatalog(forceRefresh: false, deep: false)
        }

        // Top up with a cursor page of recent so brand-new uploads appear quickly.
        let recent = await fetchRecentPosts(limit: min(max(fetchLimit, 24), 60), before: cursor)
        candidates.append(contentsOf: recent.filter { ReelsRankingEngine.isSparkEligible($0) })

        if cursor == nil, followingLimitPerAuthor > 0 {
            // Light own/following only — do not re-run full country walks.
            let own = await fetchOwnPosts(limit: 12)
            candidates.append(contentsOf: own.filter { ReelsRankingEngine.isSparkEligible($0) })
        }

        var seenCandidateIDs = Set<String>()
        candidates = candidates.filter { post in
            guard seenCandidateIDs.insert(post.id).inserted else { return false }
            return ReelsRankingEngine.isSparkEligible(post)
        }

        let batch = ReelsRankingEngine.nextBatch(
            from: candidates,
            excluding: excludingIDs,
            limit: batchSize,
            viewerCountry: viewerCountry,
            followingIDs: followingIDs,
            tail: tail,
            allowRecycle: allowRecycle
        )

        let remainingUnseen = candidates.contains {
            !excludingIDs.contains($0.id)
                && !batch.map(\.id).contains($0.id)
                && ReelsRankingEngine.isSparkEligible($0)
        }
        let nextCursor = recent.last?.createdAt
        let hasMore = remainingUnseen || recent.count >= max(8, fetchLimit / 4) || !batch.isEmpty

        return ReelsFeedPage(posts: batch, nextCursor: nextCursor, hasMore: hasMore)
    }

    /// Fresher sparks to prepend when scrolling back up.
    func loadReelsNewerBatch(
        than createdAfter: String,
        excludingIDs: Set<String>,
        batchSize: Int = 8,
        viewerCountry: String? = nil,
        followingIDs: Set<String> = [],
        head: [CountryPost] = []
    ) async -> [CountryPost] {
        let recent = await fetchRecentPosts(limit: 60)
        let newer = recent.filter { $0.createdAt > createdAfter }
        let pool = await loadReelsPool(followingLimitPerAuthor: 8, globalLimit: 40)
        var candidates = newer + pool
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.id).inserted }

        return ReelsRankingEngine.nextBatch(
            from: candidates,
            excluding: excludingIDs,
            limit: batchSize,
            viewerCountry: viewerCountry,
            followingIDs: followingIDs,
            tail: head,
            allowRecycle: false
        )
    }

    func loadReelsPool(followingLimitPerAuthor: Int = 10, globalLimit: Int = 40) async -> [CountryPost] {
        await prepareFeedContext()

        let followingIDs = await follow.followingIDs()
        let currentUserID = currentAuthorID()

        var videos: [CountryPost] = []
        var seen = Set<String>()

        func appendVideos(_ batch: [CountryPost]) {
            for post in batch where post.hasVideo && !post.isStory && !seen.contains(post.id) {
                videos.append(post)
                seen.insert(post.id)
            }
        }

        // Prefer the big discovery catalog when warm.
        appendVideos(sparksSessionCatalog)
        appendVideos(await fetchOwnPosts(limit: min(globalLimit, 16)))
        appendVideos(await fetchRecentPosts(limit: min(max(globalLimit, 40), 80)))
        // Deep multi-country sample so we never recycle ~12 IDs.
        appendVideos(await fetchFocusMarketSparks(limitPerCountry: min(200, max(80, globalLimit * 4))))

        if !followingIDs.isEmpty {
            await withTaskGroup(of: [CountryPost].self) { group in
                for authorID in followingIDs where authorID != currentUserID {
                    group.addTask {
                        (try? await self.listForAuthor(authorID, limit: followingLimitPerAuthor)) ?? []
                    }
                }
                for await batch in group {
                    appendVideos(batch)
                }
            }
        }

        if AppConfig.useDemoDataset {
            appendVideos(await sampleGlobalPosts(limit: globalLimit))
        }
        return videos.filter { ReelsRankingEngine.isSparkEligible($0) || $0.hasVideo }
    }

    /// Country longform channel handles (R2 LongForm seed). Prefer *1 variants.
    private static let focusLongformChannelHandles: [(code: String, handles: [String])] = [
        ("US", ["stateside_stories1", "stateside_stories"]),
        ("DE", ["doku_deutschland1", "doku_deutschland"]),
        ("EG", ["egypt_docs1", "egypt_docs"]),
        ("AL", ["dokumentar_al1", "dokumentar_al"]),
    ]

    /// Cached channel owner UUIDs (handle → userID) so Hubs never re-resolves usernames every open.
    private var hubOwnerIDByHandle: [String: String] = [:]

    /// In-process Hubs catalog — survives tab switches without disk/network.
    private(set) var hubsSessionCatalog: [CountryPost] = []
    private var hubsSessionLoadedAt: Date?

    /// Large Sparks catalog for the four focus countries (session cache).
    /// Avoids re-fetching thousands of rows every swipe while still rotating novelty.
    private var sparksSessionCatalog: [CountryPost] = []
    private var sparksSessionLoadedAt: Date?

    func rememberHubsSessionCatalog(_ posts: [CountryPost]) {
        guard !posts.isEmpty else { return }
        hubsSessionCatalog = posts
        hubsSessionLoadedAt = Date()
    }

    /// True when session memory is good enough for an instant Hubs re-open.
    func hubsSessionIsWarm(minLongForm: Int = 8) -> Bool {
        hubsSessionCatalog.filter { !$0.isReel }.count >= minLongForm
    }

    private func resolveHubOwnerID(handles: [String]) async -> String? {
        for handle in handles {
            let key = handle.lowercased()
            if let cached = hubOwnerIDByHandle[key], !cached.isEmpty {
                return cached
            }
        }
        for handle in handles {
            let key = handle.lowercased()
            if let profile = try? await ProfileService.shared.profileByUsername(handle),
               !profile.userID.isEmpty {
                hubOwnerIDByHandle[key] = profile.userID
                // Alias sibling handles to the same owner so next open is free.
                for h in handles {
                    hubOwnerIDByHandle[h.lowercased()] = profile.userID
                }
                return profile.userID
            }
        }
        return nil
    }

    /// Resolve all focus longform channel owner UUIDs (cached).
    func focusHubOwnerIDs() async -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        for entry in Self.focusLongformChannelHandles {
            if let ownerID = await resolveHubOwnerID(handles: entry.handles),
               seen.insert(ownerID).inserted {
                ids.append(ownerID)
            }
        }
        return ids
    }

    /// True for R2 longform media paths (matterya-sparks / longform/).
    private static func isR2LongformMedia(_ post: CountryPost) -> Bool {
        let media = (post.mediaURL ?? post.playableVideoURL?.absoluteString ?? "").lowercased()
        guard !media.isEmpty else { return false }
        return media.contains("longform/")
            || media.contains("/longform")
            || media.contains("r2:matterya-sparks")
            || media.contains("matterya-sparks")
    }

    /// R2 long-form **and** Sparks from the official country channels — **every** upload.
    /// - Parameters:
    ///   - limitPerAuthor: posts per channel owner (server allows up to 500).
    ///   - includeSparks: when true, keep reels for the Hubs Sparks rail.
    ///   - topUpRecent: multi-page recent scan for extra hub / R2 longform.
    func fetchFocusMarketHubCatalog(
        limitPerAuthor: Int = 500,
        includeSparks: Bool = true,
        topUpRecent: Bool = true
    ) async -> [CountryPost] {
        if topUpRecent {
            await prepareFeedContext()
        }
        // Pull the full channel catalog (API cap ~500 per author).
        let per = min(max(limitPerAuthor, 100), 500)
        var combined: [CountryPost] = []

        await withTaskGroup(of: [CountryPost].self) { group in
            for entry in Self.focusLongformChannelHandles {
                group.addTask {
                    guard let ownerID = await self.resolveHubOwnerID(handles: entry.handles) else {
                        return []
                    }
                    // Entire channel upload list for this R2 owner.
                    let batch = (try? await self.listForAuthor(ownerID, limit: per)) ?? []
                    return batch.filter { post in
                        guard post.hasVideo, !post.isStory else { return false }
                        if post.isReel {
                            return includeSparks
                        }
                        // Keep every long-form video from these channels (all R2 longform).
                        return true
                    }
                }
            }
            for await batch in group {
                combined.append(contentsOf: batch)
            }
        }

        if topUpRecent {
            var before: String? = nil
            var seen = Set(combined.map(\.id))
            // Bounded scan — 12×100 recent pages froze Hubs open on MainActor.
            for _ in 0..<3 {
                let recent = await fetchRecentPosts(limit: 60, before: before)
                if recent.isEmpty { break }
                for post in recent {
                    guard seen.insert(post.id).inserted else { continue }
                    guard post.hasVideo, !post.isStory else { continue }
                    if post.isReel {
                        guard includeSparks else { continue }
                        if PlayPlatformBridge.belongsInHubsCatalog(post)
                            || PlayPlatformBridge.isHubChannelUpload(post) {
                            combined.append(post)
                        }
                        continue
                    }
                    // Long-form: channel upload, hub catalog, or R2 longform path.
                    if PlayPlatformBridge.isHubOriginShare(post)
                        || PlayPlatformBridge.isHubChannelUpload(post)
                        || PlayPlatformBridge.belongsInHubsCatalog(post)
                        || Self.isR2LongformMedia(post) {
                        combined.append(post)
                    }
                }
                before = recent.last?.createdAt
                if recent.count < 40 { break }
            }
        }

        var dedup = Set<String>()
        return combined.filter { dedup.insert($0.id).inserted }
    }

    /// Long-form only (For you list) — every R2 longform we can reach.
    func fetchFocusMarketHubLongform(
        limitPerCountry: Int = 500,
        topUpRecent: Bool = true
    ) async -> [CountryPost] {
        let all = await fetchFocusMarketHubCatalog(
            limitPerAuthor: limitPerCountry,
            includeSparks: false,
            topUpRecent: topUpRecent
        )
        return all.filter { !$0.isReel }
    }

    /// Sparks from the same R2 country channels (not feed re-shares).
    func fetchFocusMarketHubSparks(limitPerAuthor: Int = 500) async -> [CountryPost] {
        let all = await fetchFocusMarketHubCatalog(
            limitPerAuthor: limitPerAuthor,
            includeSparks: true,
            topUpRecent: false
        )
        return all.filter { $0.isReel && ReelsRankingEngine.isSparkEligible($0) }
    }

    func loadLivingVideos(
        followingLimitPerAuthor: Int = 10,
        globalLimit: Int = 40,
        forceRefresh: Bool = false,
        /// Fast first paint: smaller per-channel pull, no recent top-up.
        fast: Bool = false
    ) async -> [CountryPost] {
        if !forceRefresh {
            let sessionLong = hubsSessionCatalog.filter { !$0.isReel }
            // Fast path may reuse a warm session; full path only if already large.
            // Full path only reuses session when it already looks complete (hundreds of longform).
            let enough = fast ? sessionLong.count >= 8 : sessionLong.count >= 200
            if enough {
                return sessionLong.filter { !$0.isReel && $0.hasVideo }
            }
            if fast, let cached = ContentCache.shared.posts(for: .livingVideos) {
                let filtered = cached.filter { !$0.isReel && $0.hasVideo }
                if filtered.count >= 6 { return filtered }
            }
        }

        var videos = await fetchFocusMarketHubLongform(
            // Fast: first screen only. Full: every longform per channel (up to API 500).
            limitPerCountry: fast ? min(32, max(20, globalLimit)) : 500,
            topUpRecent: !fast
        )
        if !fast {
            let own = await fetchOwnPosts(limit: max(globalLimit, 40))
            for post in own where post.hasVideo && !post.isReel && !post.isStory
                && PlayPlatformBridge.isHubChannelUpload(post) {
                if !videos.contains(where: { $0.id == post.id }) {
                    videos.append(post)
                }
            }
        }
        videos = videos.filter { !$0.isReel && !$0.isStory }
            .excludingArchiveContent()

        if !videos.isEmpty {
            ContentCache.shared.setPosts(Array(videos.prefix(ContentCache.maxCachedPosts)), for: .livingVideos)
            // Merge into session without dropping existing sparks.
            var merged = hubsSessionCatalog.filter(\.isReel) + videos
            var seen = Set<String>()
            merged = merged.filter { seen.insert($0.id).inserted }
            rememberHubsSessionCatalog(merged)
        } else if forceRefresh {
            ContentCache.shared.invalidate(.livingVideos)
        }
        #if DEBUG
        print("[Hubs] loadLivingVideos longForm=\(videos.count) fast=\(fast) force=\(forceRefresh)")
        #endif
        return videos
    }

    /// Unified Matterya Hubs catalog: R2 channel longform + channel Sparks (+ Archive if enabled).
    /// - Parameter fast: first paint — longform only; full loads **all** channel sparks + videos.
    func loadPlayCatalog(
        followingLimitPerAuthor: Int = 10,
        globalLimit: Int = 40,
        forceRefresh: Bool = false,
        viewerCountry: String? = nil,
        followingIDs: Set<String> = [],
        fast: Bool = false
    ) async -> [CountryPost] {
        let sessionLong = hubsSessionCatalog.filter { !$0.isReel }.count
        let sessionSparks = hubsSessionCatalog.filter(\.isReel).count

        // Session only short-circuits FAST paint or a useful FULL catalog.
        if !forceRefresh {
            if fast, sessionLong >= 8 {
                #if DEBUG
                print("[Hubs] loadPlayCatalog SESSION fast hit long=\(sessionLong)")
                #endif
                return hubsSessionCatalog
            }
            // 40 longform is enough for Hubs UI — don't re-pull thousands of rows every open.
            if !fast, sessionLong >= 40 {
                #if DEBUG
                print("[Hubs] loadPlayCatalog SESSION full hit long=\(sessionLong) sparks=\(sessionSparks)")
                #endif
                return hubsSessionCatalog
            }
        }

        if fast {
            let longForm = await loadLivingVideos(
                followingLimitPerAuthor: followingLimitPerAuthor,
                globalLimit: min(globalLimit, 28),
                forceRefresh: forceRefresh,
                fast: true
            )
            var merged = longForm
            var seen = Set(merged.map(\.id))
            for post in hubsSessionCatalog.filter(\.isReel).prefix(12) where seen.insert(post.id).inserted {
                merged.append(post)
            }
            if !merged.isEmpty {
                ContentCache.shared.setPosts(Array(merged.prefix(ContentCache.maxCachedPosts)), for: .livingVideos)
                rememberHubsSessionCatalog(merged)
            }
            #if DEBUG
            print("[Hubs] loadPlayCatalog FAST longForm=\(longForm.count)")
            #endif
            return merged
        }

        // FULL: deeper channel sample. Cap well below API 500 — that froze Hubs for seconds.
        // Pull-to-refresh still goes deeper; background warm stays modest.
        let perAuthor = forceRefresh ? 120 : 48
        async let channelCatalogTask = fetchFocusMarketHubCatalog(
            limitPerAuthor: perAuthor,
            includeSparks: true,
            topUpRecent: forceRefresh
        )
        async let feedSparksTask = loadReelsFeed(
            followingLimitPerAuthor: followingLimitPerAuthor,
            globalLimit: min(max(globalLimit, 24), 48),
            viewerCountry: viewerCountry,
            followingIDs: followingIDs
        )
        async let ownTask = fetchOwnPosts(limit: forceRefresh ? 40 : 16)

        let channelCatalog = await channelCatalogTask
        let feedSparks = (await feedSparksTask).filter {
            $0.isReel
                && (PlayPlatformBridge.belongsInHubsCatalog($0)
                    || PlayPlatformBridge.isHubChannelUpload($0)
                    || ReelsRankingEngine.isSparkEligible($0))
        }
        let own = await ownTask

        // Optional Archive seed.
        let seedAll: [CountryPost]
        if AppConfig.archiveContentEnabled {
            if forceRefresh {
                seedAll = await HubVideoSeedService.shared.allVideos()
            } else {
                let slugLong = await HubVideoSeedService.shared.catalogLongFormVideos(perHub: 10)
                let sparks = await HubVideoSeedService.shared.sparkSeedVideos(limit: 40)
                seedAll = slugLong + sparks
            }
        } else {
            seedAll = []
        }

        var merged: [CountryPost] = []
        var seen = Set<String>()
        for post in channelCatalog + feedSparks + own + seedAll where seen.insert(post.id).inserted {
            guard post.hasVideo || post.playableVideoURL != nil else { continue }
            if post.isStory { continue }
            if post.isReel {
                guard ReelsRankingEngine.isSparkEligible(post)
                    || PlayPlatformBridge.belongsInHubsCatalog(post)
                    || PlayPlatformBridge.isHubChannelUpload(post) else { continue }
            }
            merged.append(post)
        }
        if !AppConfig.archiveContentEnabled {
            merged = merged.excludingArchiveContent()
        }

        #if DEBUG
        let lf = merged.filter { !$0.isReel }.count
        let sp = merged.filter(\.isReel).count
        print("[Hubs] loadPlayCatalog FULL longForm=\(lf) sparks=\(sp) total=\(merged.count) channel=\(channelCatalog.count)")
        #endif
        if !merged.isEmpty {
            // Disk stays capped; session holds the full catalog for this launch.
            ContentCache.shared.setPosts(Array(merged.prefix(ContentCache.maxCachedPosts)), for: .livingVideos)
            rememberHubsSessionCatalog(merged)
        } else if forceRefresh {
            ContentCache.shared.invalidate(.livingVideos)
        }
        return merged
    }

    func searchPosts(_ query: String, limit: Int = 20) async throws -> [CountryPost] {
        struct Response: Decodable { let searchPosts: [GraphQLPost] }
        let gqlQuery = """
        query SearchPosts($query: String!, $limit: Int) {
          searchPosts(query: $query, limit: $limit) { \(postFields) }
        }
        """
        let real: [CountryPost]
        do {
            let result: Response = try await gql.authenticatedRequest(query: gqlQuery, variables: ["query": query, "limit": limit])
            real = result.searchPosts.map(\.toModel)
        } catch { real = [] }

        if AppConfig.useDemoDataset {
            let demoPosts = await demo.searchPosts(query, limit: limit)
            let merged = mergePosts(real: real, demo: demoPosts, limit: limit)
            return MatteryaSearchEngine.rankContent(merged, query: query, limit: limit)
                .excludingSparks()
        }
        return MatteryaSearchEngine.rankContent(real, query: query, limit: limit)
            .excludingSparks()
    }

    func getPostByID(_ postID: String) async throws -> CountryPost? {
        if AppConfig.useDemoDataset, let demoPost = await demo.getPostByID(postID) { return demoPost }
        struct Response: Decodable { let postById: GraphQLPost? }
        let query = "query($postId: ID!) { postById(post_id: $postId) { \(postFields) } }"
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["postId": postID])
        return result.postById?.toModel
    }

    /// Whether likes/comments must stay on-device (seed/hub/missing server rows).
    func shouldEngageLocally(postID: String) async -> Bool {
        if HubEngagementStore.usesLocalEngagement(postID: postID) { return true }
        if let cached = cachedPost(id: postID) {
            if cached.isHubSeedVideo { return true }
            let author = cached.authorID.lowercased()
            if author.hasPrefix("hub_") || author.hasPrefix("hub_spark_") { return true }
            if let url = cached.mediaURL?.lowercased(), url.contains("archive.org") { return true }
            if let url = cached.thumbURL?.lowercased(), url.contains("archive.org") { return true }
        }
        return false
    }

    private func cachedPost(id: String) -> CountryPost? {
        for key in [ContentCacheKey.livingVideos, .homeFeed, .savedPosts, .profilePosts] {
            if let match = ContentCache.shared.posts(for: key)?.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    /// Synchronous cache lookup for deep-links / Hubs open-by-id (no network).
    @MainActor
    func cachedPostForDetail(id: String) -> CountryPost? {
        cachedPost(id: id)
    }

    func listComments(_ postID: String, limit: Int = 2000) async throws -> [PostComment] {
        if AppConfig.useDemoDataset, await demo.isDemoPostID(postID) {
            return await demo.listComments(postID, limit: limit)
        }
        var comments = try await fetchCommentsByPost(postID, limit: limit)

        // Spark feed shares may have a partial seed thread — prefer the fuller R2 origin thread.
        if let post = try? await getPostByID(postID) {
            let originID = SparkShareMarker.originID(from: post.body)
                ?? post.sharedPostID
                ?? post.sharedPost?.id
            if let originID, originID != postID {
                let originComments = (try? await fetchCommentsByPost(originID, limit: limit)) ?? []
                if originComments.count > comments.count {
                    // Prefer origin (R2) comments; keep any real replies on the share after.
                    var seen = Set(originComments.map(\.id))
                    var merged = originComments
                    for c in comments where seen.insert(c.id).inserted {
                        merged.append(c)
                    }
                    comments = Array(merged.prefix(limit))
                }
            }
        }
        return comments
    }

    private func fetchCommentsByPost(_ postID: String, limit: Int) async throws -> [PostComment] {
        struct Response: Decodable { let commentsByPost: [GraphQLComment] }
        let query = """
        query($post_id: ID!, $limit: Int) {
          commentsByPost(post_id: $post_id, limit: $limit) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["post_id": postID, "limit": limit]
        )
        return result.commentsByPost.map(\.toModel)
    }

    func addComment(_ postID: String, body: String, parentID: String? = nil) async throws -> PostComment {
        if AppConfig.useDemoDataset, await demo.isDemoPostID(postID) {
            return await demo.addComment(postID, body: body, parentID: parentID)
        }
        struct Response: Decodable { let addComment: GraphQLComment }
        let mutation = """
        mutation($post_id: ID!, $body: String!, $parent_id: ID) {
          addComment(post_id: $post_id, body: $body, parent_id: $parent_id) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        var vars: [String: Any] = [
            "post_id": postID,
            "body": body,
        ]
        if let parentID, !parentID.isEmpty {
            vars["parent_id"] = parentID
        }
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: vars)
        return result.addComment.toModel
    }

    func createReel(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        videoFileURL: URL,
        mimeType: String = "video/mp4",
        fileExtension: String = "mp4",
        thumbnailImage: UIImage? = nil,
        onUploadProgress: (@Sendable (UploadProgress) -> Void)? = nil,
        onPublishing: (@Sendable () -> Void)? = nil
    ) async throws -> CountryPost {
        let upload = try await MediaService.shared.uploadPostMedia(
            fileURL: videoFileURL,
            fileExtension: fileExtension,
            mimeType: mimeType,
            onProgress: onUploadProgress
        )
        let thumbURL = try await uploadVideoThumbnail(
            from: videoFileURL,
            prefetchedImage: thumbnailImage
        )
        onPublishing?()
        let mediaURL = PostMediaPayload.encode(
            urls: [upload.publicURL],
            types: ["video"],
            reel: true
        )
        // Explicit spark marker so isReel stays true even if media JSON is stripped.
        let cleaned = body
            .replacingOccurrences(of: "__spark__|", with: "")
            .replacingOccurrences(of: "__reel__|", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyOut = "__spark__|\(cleaned.isEmpty ? "Spark" : cleaned)"
        return try await createPost(
            authorID: authorID,
            body: bodyOut,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            mediaType: "video",
            mediaURL: mediaURL,
            thumbURL: thumbURL
        )
    }

    /// Long-form video for the **home feed** (default). Not shown as a Hubs channel item.
    func createFeedVideo(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        title: String? = nil,
        videoFileURL: URL,
        mimeType: String = "video/mp4",
        fileExtension: String = "mp4",
        thumbnailImage: UIImage? = nil,
        onUploadProgress: (@Sendable (UploadProgress) -> Void)? = nil,
        onPublishing: (@Sendable () -> Void)? = nil
    ) async throws -> CountryPost {
        try await createLongFormVideo(
            authorID: authorID,
            body: body,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            title: title,
            videoFileURL: videoFileURL,
            mimeType: mimeType,
            fileExtension: fileExtension,
            thumbnailImage: thumbnailImage,
            publishToHubChannel: false,
            onUploadProgress: onUploadProgress,
            onPublishing: onPublishing
        )
    }

    /// Long-form video for the user’s **Hubs channel** (marked for Hubs shelves + simple feed card).
    func createLivingVideo(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        title: String? = nil,
        videoFileURL: URL,
        mimeType: String = "video/mp4",
        fileExtension: String = "mp4",
        thumbnailImage: UIImage? = nil,
        publishToHubChannel: Bool = true,
        onUploadProgress: (@Sendable (UploadProgress) -> Void)? = nil,
        onPublishing: (@Sendable () -> Void)? = nil
    ) async throws -> CountryPost {
        try await createLongFormVideo(
            authorID: authorID,
            body: body,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            title: title,
            videoFileURL: videoFileURL,
            mimeType: mimeType,
            fileExtension: fileExtension,
            thumbnailImage: thumbnailImage,
            publishToHubChannel: publishToHubChannel,
            onUploadProgress: onUploadProgress,
            onPublishing: onPublishing
        )
    }

    private func createLongFormVideo(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String?,
        title: String?,
        videoFileURL: URL,
        mimeType: String,
        fileExtension: String,
        thumbnailImage: UIImage?,
        publishToHubChannel: Bool,
        onUploadProgress: (@Sendable (UploadProgress) -> Void)?,
        onPublishing: (@Sendable () -> Void)?
    ) async throws -> CountryPost {
        let upload = try await MediaService.shared.uploadPostMedia(
            fileURL: videoFileURL,
            fileExtension: fileExtension,
            mimeType: mimeType,
            onProgress: onUploadProgress
        )
        let thumbURL = try await uploadVideoThumbnail(
            from: videoFileURL,
            prefetchedImage: thumbnailImage
        )
        onPublishing?()
        let mediaURL = PostMediaPayload.encode(
            urls: [upload.publicURL],
            types: ["video"],
            reel: false
        )
        let bodyOut = publishToHubChannel ? HubChannelPostMarker.markBody(body) : body
        return try await createPost(
            authorID: authorID,
            body: bodyOut,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            title: title,
            mediaType: "video",
            mediaURL: mediaURL,
            thumbURL: thumbURL
        )
    }

    func createStory(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        mediaData: Data? = nil,
        mediaFileURL: URL? = nil,
        mimeType: String,
        fileExtension: String,
        onUploadProgress: (@Sendable (UploadProgress) -> Void)? = nil,
        onPublishing: (@Sendable () -> Void)? = nil
    ) async throws -> CountryPost {
        let upload: (path: String, publicURL: String)
        if let mediaFileURL {
            upload = try await MediaService.shared.uploadPostMedia(
                fileURL: mediaFileURL,
                fileExtension: fileExtension,
                mimeType: mimeType,
                onProgress: onUploadProgress
            )
        } else if let mediaData {
            upload = try await MediaService.shared.uploadPostMedia(
                data: mediaData,
                fileExtension: fileExtension,
                mimeType: mimeType
            )
        } else {
            throw MediaError.uploadFailed("Missing story media.")
        }
        onPublishing?()
        let expiresAt = Date().addingTimeInterval(86_400)
        let storyBody = PostStoryMarker.buildBody(caption: body, expiresAt: expiresAt)
        return try await createPost(
            authorID: authorID,
            body: storyBody,
            countryName: countryName,
            countryCode: countryCode,
            cityName: cityName,
            visibility: .country,
            mediaType: "story",
            mediaURL: upload.publicURL
        )
    }

    func loadActiveStoryGroups(
        countryCode: String?,
        followingIDs: Set<String>,
        viewedStoryIDs: Set<String>,
        currentUserID: String?
    ) async -> [StoryGroup] {
        var pool: [CountryPost] = []
        var seen = Set<String>()

        func append(_ batch: [CountryPost]) {
            for post in batch where post.isStory && post.isStoryActive && !seen.contains(post.id) {
                pool.append(post)
                seen.insert(post.id)
            }
        }

        if let countryCode {
            append((try? await listByCountry(countryCode, limit: 80)) ?? [])
        }

        if !followingIDs.isEmpty {
            await withTaskGroup(of: [CountryPost].self) { group in
                for authorID in followingIDs {
                    group.addTask { (try? await self.listForAuthor(authorID, limit: 20)) ?? [] }
                }
                for await batch in group { append(batch) }
            }
        }

        if let currentUserID {
            append((try? await listForAuthor(currentUserID, limit: 20)) ?? [])
        }

        let grouped = Dictionary(grouping: pool, by: \.authorID)
        return grouped.map { authorID, stories in
            let sorted = stories.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            let author = sorted.first?.author
            let hasUnviewed = sorted.contains { !viewedStoryIDs.contains($0.id) }
            return StoryGroup(authorID: authorID, author: author, stories: sorted, hasUnviewed: hasUnviewed)
        }
        .sorted { lhs, rhs in
            if lhs.authorID == currentUserID { return true }
            if rhs.authorID == currentUserID { return false }
            if lhs.hasUnviewed != rhs.hasUnviewed { return lhs.hasUnviewed }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func sharePostToCountryFeed(
        post: CountryPost,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        caption: String? = nil
    ) async throws -> CountryPost {
        guard !post.isStory else {
            throw PostsServiceError.momentCannotBeSharedAsPost
        }
        if let shared = post.sharedPost, shared.asCountryPost.isStory {
            throw PostsServiceError.momentCannotBeSharedAsPost
        }
        let originalID = post.sharedPostID ?? post.id
        let captionBody = (caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        struct Response: Decodable { let createPost: GraphQLPost }

        // Server posts (UUID) → normal share pointer (except Sparks — always self-contained card).
        // Hubs catalog / Archive seeds are client-only ids (ia_*, hub_*, …) → stamp media.
        let isServerPost = UUID(uuidString: originalID) != nil
        let isHubCatalog = PlayPlatformBridge.isHubCatalogContent(post) || post.isHubSeedVideo
        // Sparks: original reel, spark-share re-post, or embedded spark — never hub long-form.
        let isSpark = post.isReel
            || PlayPlatformBridge.isReelVideo(post)
            || post.isSparkFeedShare
            || SparkShareMarker.isMarked(post.body)
            || (post.sharedPost?.asCountryPost.isReel == true)
            || (post.sharedPost.map { PlayPlatformBridge.isReelVideo($0.asCountryPost) } == true)
        // Hub long-form only when this is clearly not a Spark.
        let isHubLongFormShare = isHubCatalog && !isSpark

        // Stamp media when: non-UUID id, hub catalog, or any Spark share.
        // Sparks always get media + SparkShareMarker so the feed shows SparkFeedCard.
        // NEVER stamp __spark__ on a share (that put re-shares into Sparks-for-you rail).
        let shouldStampMedia = !isServerPost || isHubCatalog || isSpark

        var input: [String: Any] = [
            "country_name": countryName,
            "country_code": countryCode.uppercased(),
            // Everything posts to the main feed only (not country-scoped feeds).
            "visibility": "public",
        ]
        if let cityName { input["city_name"] = cityName }

        if shouldStampMedia {
            // Self-contained Hubs / Sparks share (media lives on this post).
            var mediaURL = post.mediaURL
                ?? post.playableVideoURL?.absoluteString
            var thumb = post.thumbURL
                ?? post.posterImageURL?.absoluteString

            // Order matters: Sparks before hub long-form so Archive Sparks stay Spark cards.
            if isSpark {
                // Feed re-share of a Spark: media + spark-share marker (NOT __spark__).
                // Feed shows SparkFeedCard; tap → infinite Sparks player.
                // Share post itself is NOT isReel (stays out of Sparks-for-you rail).
                let originForStamp: CountryPost = {
                    if let embed = post.sharedPost?.asCountryPost,
                       embed.isReel || embed.playableVideoURL != nil {
                        return embed
                    }
                    return post
                }()
                input["body"] = SparkShareMarker.markBody(caption: captionBody, origin: originForStamp)
                input["media_type"] = "video"
                mediaURL = originForStamp.mediaURL
                    ?? originForStamp.playableVideoURL?.absoluteString
                    ?? mediaURL
                thumb = originForStamp.thumbURL
                    ?? originForStamp.posterImageURL?.absoluteString
                    ?? thumb
            } else if isHubLongFormShare || isHubCatalog {
                // Feed share of a Hubs video — stamp catalog/original channel (never the sharer).
                // NEVER use HubChannelPostMarker (that would pretend the sharer owns a Hubs channel).
                let origin = await PlayPlatformBridge.resolveHubWatchPresentation(for: post)
                input["body"] = HubOriginShareMarker.markBody(caption: captionBody, origin: origin)
                input["media_type"] = "video"
                if let title = origin.displayHeadline ?? origin.displayTitle ?? post.displayHeadline ?? post.displayTitle,
                   !title.isEmpty {
                    input["title"] = title
                }
                mediaURL = origin.mediaURL ?? origin.playableVideoURL?.absoluteString ?? mediaURL
                thumb = origin.thumbURL ?? origin.posterImageURL?.absoluteString ?? thumb
            } else {
                // Plain long-form video share (not Hubs) — self-contained media, no channel claim.
                input["body"] = captionBody
                input["media_type"] = "video"
                if let title = post.displayHeadline ?? post.displayTitle, !title.isEmpty {
                    input["title"] = title
                }
            }
            if let mediaURL, !mediaURL.isEmpty {
                input["media_url"] = mediaURL
            } else {
                // Cannot stamp without playable media — fall back to pointer if UUID.
                if isServerPost {
                    input["body"] = isSpark
                        ? SparkShareMarker.markBody(caption: captionBody, origin: post)
                        : captionBody
                    input["media_type"] = "none"
                    input["shared_post_id"] = originalID
                    input["visibility"] = "public"
                } else {
                    throw PostsServiceError.shareFailed("This video has no playable media to share.")
                }
            }
            if let thumb, !thumb.isEmpty {
                input["thumb_url"] = thumb
            }
        } else {
            // UUID pointer share (non-spark) — embed original on the feed card.
            input["body"] = captionBody
            input["media_type"] = "none"
            input["shared_post_id"] = originalID
            input["visibility"] = "public"
        }

        let mutation = "mutation($input: CreatePostInput!) { createPost(input: $input) { \(postFields) } }"
        do {
            let result: Response = try await gql.authenticatedRequest(
                query: mutation,
                variables: ["input": input]
            )
            let created = result.createPost.toModel
            ContentCache.shared.invalidateAllFeeds()
            return created
        } catch {
            // UUID pointer share failed (missing row) → retry as self-contained stamp.
            if isServerPost,
               !shouldStampMedia,
               let mediaURL = post.mediaURL ?? post.playableVideoURL?.absoluteString,
               !mediaURL.isEmpty
            {
                var retry = input
                retry.removeValue(forKey: "shared_post_id")
                retry["visibility"] = "public"
                retry["media_type"] = "video"
                retry["media_url"] = mediaURL
                if let thumb = post.thumbURL ?? post.posterImageURL?.absoluteString {
                    retry["thumb_url"] = thumb
                }
                // Same priority: spark card → hub origin → plain.
                if isSpark {
                    // NEVER __spark__ on a share — that flooded Sparks-for-you with re-posts.
                    retry["body"] = SparkShareMarker.markBody(caption: captionBody, origin: post)
                } else if isHubLongFormShare || isHubCatalog {
                    let origin = await PlayPlatformBridge.resolveHubWatchPresentation(for: post)
                    retry["body"] = HubOriginShareMarker.markBody(caption: captionBody, origin: origin)
                    if let title = origin.displayHeadline ?? origin.displayTitle ?? post.displayHeadline,
                       !title.isEmpty {
                        retry["title"] = title
                    }
                } else {
                    retry["body"] = captionBody
                    if let title = post.displayHeadline ?? post.displayTitle, !title.isEmpty {
                        retry["title"] = title
                    }
                }
                let result: Response = try await gql.authenticatedRequest(
                    query: mutation,
                    variables: ["input": retry]
                )
                let created = result.createPost.toModel
                ContentCache.shared.invalidateAllFeeds()
                return created
            }
            throw error
        }
    }

    func createPost(
        authorID: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = nil,
        title: String? = nil,
        visibility: PostVisibility = .public,
        mediaType: String? = nil,
        mediaURL: String? = nil,
        thumbURL: String? = nil,
        sharedPostID: String? = nil
    ) async throws -> CountryPost {
        struct Response: Decodable { let createPost: GraphQLPost }
        let normalizedMediaType = (mediaType ?? "").lowercased()
        // Main feed only: all non-story posts are public (never country-scoped feeds).
        let resolvedVisibility: PostVisibility
        if normalizedMediaType == "story" || body.contains("__story__|") {
            resolvedVisibility = .country
        } else {
            resolvedVisibility = .public
        }
        var input: [String: Any] = [
            "body": body,
            "country_name": countryName,
            "country_code": countryCode.uppercased(),
            "visibility": resolvedVisibility.rawValue
        ]
        if let title { input["title"] = title }
        if let cityName { input["city_name"] = cityName }
        if let mediaType { input["media_type"] = mediaType }
        if let mediaURL { input["media_url"] = mediaURL }
        if let thumbURL { input["thumb_url"] = thumbURL }
        if let sharedPostID { input["shared_post_id"] = sharedPostID }

        let mutation = "mutation($input: CreatePostInput!) { createPost(input: $input) { \(postFields) } }"
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["input": input])
        let created = result.createPost.toModel
        if !created.isStory {
            ContentCache.shared.invalidateAllFeeds()
        }
        return created
    }

    /// Like a post. Never throws — seed/hub stay local; GraphQL failures fall back locally.
    func likePost(_ postID: String, baseLikeCount: Int = 0) async throws {
        if await shouldEngageLocally(postID: postID) {
            HubEngagementStore.shared.like(postID, baseLikeCount: baseLikeCount)
            return
        }
        do {
            let mutation = "mutation($postId: ID!) { likePost(post_id: $postId) { id } }"
            let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        } catch {
            HubEngagementStore.shared.like(postID, baseLikeCount: baseLikeCount)
        }
    }

    /// Unlike a post. Never throws — same local-first policy as `likePost`.
    func unlikePost(_ postID: String, baseLikeCount: Int = 0) async throws {
        if await shouldEngageLocally(postID: postID) {
            HubEngagementStore.shared.unlike(postID, baseLikeCount: baseLikeCount)
            return
        }
        do {
            let mutation = "mutation($postId: ID!) { unlikePost(post_id: $postId) { id } }"
            let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        } catch {
            HubEngagementStore.shared.unlike(postID, baseLikeCount: baseLikeCount)
        }
    }

    func publishPostChange(_ post: CountryPost) {
        if var cached = ContentCache.shared.posts(for: .homeFeed),
           let index = cached.firstIndex(where: { $0.id == post.id }) {
            cached[index] = post
            ContentCache.shared.setPosts(cached, for: .homeFeed)
        }
        NotificationCenter.default.post(
            name: .userPostsDidChange,
            object: nil,
            userInfo: ["post": post]
        )
    }

    private static let localBookmarksOnlyKey = "posts.bookmarks.local_only"

    static var usesLocalBookmarksOnly: Bool {
        get { UserDefaults.standard.bool(forKey: localBookmarksOnlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: localBookmarksOnlyKey) }
    }

    static func isUnsupportedBookmarkError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("savepost")
            || message.contains("unsavepost")
            || message.contains("savedposts")
            || message.contains("saved_by_me")
            || message.contains("post_bookmarks")
            || message.contains("internal server error")
            || message.contains("internal_server_error")
            || message.contains("cannot query field")
            || message.contains("graphql_validation_failed")
    }

    func savedPosts(limit: Int = 80) async throws -> [CountryPost] {
        struct Response: Decodable { let savedPosts: [GraphQLPost] }
        let query = """
        query SavedPosts($limit: Int) {
          savedPosts(limit: $limit) { \(postFieldsWithBookmarks) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["limit": limit])
        Self.usesLocalBookmarksOnly = false
        return result.savedPosts.map(\.toModel)
    }

    func savePost(_ postID: String) async throws -> CountryPost {
        struct Response: Decodable { let savePost: GraphQLPost }
        let mutation = """
        mutation($postId: ID!) {
          savePost(post_id: $postId) { \(postFieldsWithBookmarks) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        Self.usesLocalBookmarksOnly = false
        return result.savePost.toModel
    }

    func unsavePost(_ postID: String) async throws -> CountryPost {
        struct Response: Decodable { let unsavePost: GraphQLPost }
        let mutation = """
        mutation($postId: ID!) {
          unsavePost(post_id: $postId) { \(postFieldsWithBookmarks) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        Self.usesLocalBookmarksOnly = false
        return result.unsavePost.toModel
    }

    func loadBookmarkedPosts(localIDs: Set<String>, limit: Int = 100) async -> [CountryPost] {
        var server: [CountryPost] = []
        if !Self.usesLocalBookmarksOnly {
            do {
                server = try await savedPosts(limit: limit)
            } catch {
                if Self.isUnsupportedBookmarkError(error) {
                    Self.usesLocalBookmarksOnly = true
                } else if let cached = ContentCache.shared.posts(for: .savedPosts), !cached.isEmpty {
                    // Network blip — still resolve local-only Sparks below.
                    server = cached.filter { localIDs.contains($0.id) || localIDs.isEmpty }
                }
            }
        }

        // Always re-hydrate IDs the server never stores (ia_*, hub_*, seed Sparks).
        let serverIDs = Set(server.map(\.id))
        let missing = localIDs.subtracting(serverIDs)
        let localOnly = await resolveLocalBookmarks(ids: missing.isEmpty && server.isEmpty ? localIDs : missing, limit: limit)

        var byID: [String: CountryPost] = [:]
        for post in server {
            byID[post.id] = post.withSavedByMe(true)
        }
        for post in localOnly {
            // Prefer rich local Spark media over a thin server row if both exist.
            if let existing = byID[post.id] {
                let localPlayable = post.playableVideoURL != nil || !(post.mediaURL ?? "").isEmpty
                let serverPlayable = existing.playableVideoURL != nil || !(existing.mediaURL ?? "").isEmpty
                if localPlayable, !serverPlayable || post.isReel || post.isSparkFeedShare {
                    byID[post.id] = post.withSavedByMe(true)
                }
            } else {
                byID[post.id] = post.withSavedByMe(true)
            }
        }
        return byID.values.sorted { $0.createdAt > $1.createdAt }
    }

    /// Seed / Archive / non-UUID Sparks cannot hit `savePost` on the server — keep on device.
    static func mustBookmarkLocally(_ post: CountryPost) -> Bool {
        if UUID(uuidString: post.id) == nil { return true }
        if post.isHubSeedVideo || post.isSeededOrSynthetic { return true }
        if post.isArchiveSparkSource { return true }
        let id = post.id.lowercased()
        if id.hasPrefix("ia_") || id.hasPrefix("hub_") || id.hasPrefix("demo_") || id.hasPrefix("post_") {
            return true
        }
        let author = post.authorID.lowercased()
        if author.hasPrefix("hub_") || author.hasPrefix("hub_spark_") || author.hasPrefix("user_") {
            return true
        }
        return false
    }

    static func isMissingPostBookmarkError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("not found")
            || message.contains("does not exist")
            || message.contains("foreign key")
            || message.contains("invalid input")
            || message.contains("invalid uuid")
            || message.contains("no rows")
            || message.contains("pgrst")
            || message.contains("22p02")
    }

    func toggleBookmark(for post: CountryPost, saved: Bool) async throws -> CountryPost {
        // Always succeed locally for catalog/seed Sparks — server has no row to bookmark.
        if Self.usesLocalBookmarksOnly || Self.mustBookmarkLocally(post) {
            return post.withSavedByMe(saved)
        }
        if await shouldEngageLocally(postID: post.id) {
            return post.withSavedByMe(saved)
        }
        do {
            if saved {
                return try await savePost(post.id)
            }
            return try await unsavePost(post.id)
        } catch {
            if Self.isUnsupportedBookmarkError(error) {
                Self.usesLocalBookmarksOnly = true
                return post.withSavedByMe(saved)
            }
            // Post missing on server (deleted / bad id) — still keep in Saved Sparks on device.
            if Self.isMissingPostBookmarkError(error) || Self.mustBookmarkLocally(post) {
                return post.withSavedByMe(saved)
            }
            throw error
        }
    }

    private func resolveLocalBookmarks(ids: Set<String>, limit: Int) async -> [CountryPost] {
        guard !ids.isEmpty else { return [] }

        var byID: [String: CountryPost] = [:]

        // 1) Disk/memory saved cache (full Spark rows with media).
        if let cached = ContentCache.shared.posts(for: .savedPosts) {
            for post in cached where ids.contains(post.id) {
                byID[post.id] = post.withSavedByMe(true)
            }
        }

        // 2) Resolve remaining IDs (network UUID, then seed/archive catalog).
        let remaining = ids.subtracting(byID.keys)
        for id in remaining.prefix(limit) {
            if let post = try? await getPostByID(id) {
                byID[id] = post.withSavedByMe(true)
                continue
            }
            // Catalog / R2 / Archive Sparks never exist as server posts.
            if let seed = await HubVideoSeedService.shared.post(id: id) {
                byID[id] = seed.withSavedByMe(true)
                continue
            }
            // Last resort: any feed/hubs cache that still holds the row.
            if let fromFeeds = Self.lookupPostInCaches(id: id) {
                byID[id] = fromFeeds.withSavedByMe(true)
            }
        }

        return byID.values.sorted { $0.createdAt > $1.createdAt }
    }

    /// Find a post by id across warm in-memory caches (seed Sparks after process restart).
    private static func lookupPostInCaches(id: String) -> CountryPost? {
        let keys: [ContentCacheKey] = [.savedPosts, .homeFeed, .livingVideos, .profilePosts]
        for key in keys {
            if let hit = ContentCache.shared.posts(for: key)?.first(where: { $0.id == id }) {
                return hit
            }
        }
        return nil
    }

    func updatePost(
        _ postID: String,
        title: String? = nil,
        body: String? = nil,
        visibility: PostVisibility? = nil,
        mediaType: String? = nil,
        mediaURL: String? = nil,
        thumbURL: String? = nil,
        clearMedia: Bool = false
    ) async throws -> CountryPost {
        struct Response: Decodable { let updatePost: GraphQLPost }
        var input: [String: Any] = [:]
        if let title { input["title"] = title }
        if let body { input["body"] = body }
        if let visibility { input["visibility"] = visibility.rawValue }
        if clearMedia {
            input["clear_media"] = true
        } else if let mediaURL {
            input["media_url"] = mediaURL
            if let mediaType { input["media_type"] = mediaType }
            if let thumbURL { input["thumb_url"] = thumbURL }
        }
        let mutation = """
        mutation($postId: ID!, $input: UpdatePostInput!) {
          updatePost(post_id: $postId, input: $input) { \(postFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["postId": postID, "input": input]
        )
        return result.updatePost.toModel
    }

    func deletePost(_ postID: String) async throws -> Bool {
        struct Response: Decodable { let deletePost: Bool }
        let mutation = "mutation($postId: ID!) { deletePost(post_id: $postId) }"
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["postId": postID])
        return result.deletePost
    }

    func reportPost(_ postID: String, reason: String) async throws -> Bool {
        struct Response: Decodable { let reportPost: Bool }
        let mutation = "mutation($postId: ID!, $reason: String!) { reportPost(post_id: $postId, reason: $reason) }"
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["postId": postID, "reason": reason]
        )
        return result.reportPost
    }

    func likeComment(_ commentID: String) async throws -> PostComment {
        if AppConfig.useDemoDataset, let comment = await demo.likeComment(commentID) {
            return comment
        }
        struct Response: Decodable { let likeComment: GraphQLComment }
        let mutation = """
        mutation($commentId: ID!) {
          likeComment(comment_id: $commentId) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["commentId": commentID])
        return result.likeComment.toModel
    }

    func unlikeComment(_ commentID: String) async throws -> PostComment {
        if AppConfig.useDemoDataset, let comment = await demo.unlikeComment(commentID) {
            return comment
        }
        struct Response: Decodable { let unlikeComment: GraphQLComment }
        let mutation = """
        mutation($commentId: ID!) {
          unlikeComment(comment_id: $commentId) {
            id post_id parent_id author_id body like_count liked_by_me created_at updated_at
            author { user_id display_name username avatar_url country_name country_code }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: ["commentId": commentID])
        return result.unlikeComment.toModel
    }

    func videoPosts(for country: Country, limit: Int = 40) async throws -> [CountryPost] {
        let posts = try await listByCountry(country.iso, limit: limit)
        return posts.filter(\.hasVideo)
    }

    func sampleGlobalPosts(limit: Int = 12) async -> [CountryPost] {
        await demo.sampleGlobalPosts(limit: limit)
    }

    private var viewedPostIDs: Set<String> = []

    func recordView(_ post: CountryPost) async {
        guard !post.id.isEmpty, !viewedPostIDs.contains(post.id) else { return }
        viewedPostIDs.insert(post.id)
        SparkDiscoveryEngine.markWatched(post.id)
        await MainActor.run {
            EngagementTracker.shared.videoProgress(post: post, progress: 0.05, durationMs: 0, surface: "view")
        }
    }

    private func fetchRealPostsByCountry(_ code: String, limit: Int) async throws -> [CountryPost] {
        struct Response: Decodable { let postsByCountry: [GraphQLPost] }
        let query = "query($code: String!, $limit: Int) { postsByCountry(country_code: $code, limit: $limit) { \(postFields) } }"
        let result: Response = try await gql.authenticatedRequest(query: query, variables: ["code": code, "limit": limit])
        return result.postsByCountry.map(\.toModel)
    }

    func fetchRecentPosts(limit: Int = 40, before: String? = nil) async -> [CountryPost] {
        struct Response: Decodable { let recentPosts: [GraphQLPost] }
        let query = """
        query($limit: Int, $before: String) {
          recentPosts(limit: $limit, before: $before) { \(postFields) }
        }
        """
        var variables: [String: Any] = ["limit": limit]
        if let before, !before.isEmpty {
            variables["before"] = before
        }
        var real: [CountryPost] = []
        for attempt in 0..<2 {
            do {
                let result: Response = try await gql.authenticatedRequest(
                    query: query,
                    variables: variables
                )
                real = result.recentPosts.map(\.toModel)
                break
            } catch {
                if attempt == 0 {
                    _ = try? await Task { @MainActor in
                        try await AuthService.shared.ensureValidToken()
                    }.value
                    continue
                }
                real = []
            }
        }

        if real.isEmpty {
            real = await fallbackGlobalPosts(limit: limit)
        }

        if AppConfig.useDemoDataset {
            return mergePosts(real: real, demo: await demo.sampleGlobalPosts(limit: limit), limit: limit)
        }
        return real
    }

    private func fetchHomeCountryPosts(limit: Int) async -> [CountryPost] {
        guard let code = await resolvedHomeCountryCode() else { return [] }
        return (try? await listByCountry(code, limit: limit)) ?? []
    }

    private func prepareFeedContext() async {
        _ = try? await AuthService.shared.ensureValidToken()
        _ = await resolvedHomeCountryCode()
    }

    private func resolvedHomeCountryCode() async -> String? {
        if let code = ContentCache.shared.profileCountryCode(), !code.isEmpty {
            return code
        }
        if let code = ContentCache.shared.cachedProfile()?.countryCode?.uppercased(), !code.isEmpty {
            ContentCache.shared.setProfileCountryCode(code)
            return code
        }
        if let profile = try? await ProfileService.shared.meProfile(),
           let code = profile.countryCode?.uppercased(), !code.isEmpty {
            ContentCache.shared.setProfile(profile)
            return code
        }
        return nil
    }

    private func currentAuthorID() -> String? {
        if let userID = ContentCache.shared.cachedProfile()?.userID, !userID.isEmpty {
            return userID
        }
        return AuthService.shared.currentUser?.id
    }

    private func fetchOwnPosts(limit: Int) async -> [CountryPost] {
        guard let userID = currentAuthorID() else { return [] }
        for attempt in 0..<2 {
            do {
                let posts = try await listForAuthor(userID, limit: limit).excludingSparks()
                ContentCache.shared.setPosts(posts, for: .profilePosts)
                return posts
            } catch {
                if attempt == 0 {
                    _ = try? await AuthService.shared.ensureValidToken()
                    continue
                }
            }
        }
        return ContentCache.shared.posts(for: .profilePosts) ?? []
    }

    private func fallbackFeedPosts(limit: Int) async -> [CountryPost] {
        var batches: [[CountryPost]] = []

        let own = await fetchOwnPosts(limit: limit)
        if !own.isEmpty { batches.append(own) }

        let home = await fetchHomeCountryPosts(limit: limit)
        if !home.isEmpty { batches.append(home) }

        if batches.isEmpty, let cached = ContentCache.shared.posts(for: .profilePosts) {
            batches.append(cached)
        }

        if batches.isEmpty, let code = await resolvedHomeCountryCode() {
            let retry = (try? await listByCountry(code, limit: limit)) ?? []
            if !retry.isEmpty { batches.append(retry) }
        }

        guard !batches.isEmpty else { return [] }
        return mergeFeedSources(batches, limit: limit)
    }

    private func fallbackGlobalPosts(limit: Int) async -> [CountryPost] {
        await fallbackFeedPosts(limit: limit)
    }

    func mergeFeedSources(_ batches: [[CountryPost]], limit: Int) -> [CountryPost] {
        var seen = Set<String>()
        var merged: [CountryPost] = []
        let sortedBatches = batches.map {
            $0.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        }
        var indices = Array(repeating: 0, count: sortedBatches.count)

        while merged.count < limit {
            var appended = false
            for batchIndex in sortedBatches.indices {
                let batch = sortedBatches[batchIndex]
                while indices[batchIndex] < batch.count {
                    let post = batch[indices[batchIndex]]
                    indices[batchIndex] += 1
                    guard !seen.contains(post.id), !post.isStory else { continue }
                    seen.insert(post.id)
                    merged.append(post)
                    appended = true
                    break
                }
                if merged.count >= limit { break }
            }
            if !appended { break }
        }

        return merged
    }

    func mergePosts(real: [CountryPost], demo: [CountryPost], limit: Int) -> [CountryPost] {
        mergeFeedSources([real, demo], limit: limit)
    }

    /// Newest `created_at` first (matches GraphQL `recentPosts` and own-post pin behavior).
    func chronologicalNewestFirst(_ posts: [CountryPost]) -> [CountryPost] {
        var seen = Set<String>()
        return posts
            .filter { seen.insert($0.id).inserted && !$0.isStory }
            .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
    }

    /// Home feed order: **newest upload first** so R2 / backend / user posts always surface at top.
    /// Optional pinIDs stay above the timeline (e.g. in-flight local posts); no shuffle.
    func sessionFreshOrder(
        _ posts: [CountryPost],
        pinAuthorID: String? = nil,
        pinIDs: Set<String> = []
    ) -> [CountryPost] {
        _ = pinAuthorID // no longer sticky-own-first — global recency wins
        var seen = Set<String>()
        let unique = posts.filter { seen.insert($0.id).inserted && !$0.isStory }
        guard unique.count > 1 else { return unique }

        var pinned: [CountryPost] = []
        var rest: [CountryPost] = []

        for post in unique {
            if pinIDs.contains(post.id) {
                pinned.append(post)
            } else {
                rest.append(post)
            }
        }

        pinned.sort { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        rest.sort { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        return pinned + rest
    }

    private func uploadVideoThumbnail(
        from videoFileURL: URL,
        prefetchedImage: UIImage?
    ) async throws -> String? {
        let image: UIImage?
        if let prefetchedImage {
            image = prefetchedImage
        } else {
            image = await VideoCompressionService.shared.generateThumbnail(from: videoFileURL)
        }
        guard let image,
              let data = image.jpegData(compressionQuality: 0.82)
        else { return nil }

        let upload = try await MediaService.shared.uploadPostMedia(
            data: data,
            fileExtension: "jpg",
            mimeType: "image/jpeg"
        )
        return upload.publicURL
    }
}

enum PostsServiceError: LocalizedError {
    case momentCannotBeSharedAsPost
    case shareFailed(String)

    var errorDescription: String? {
        switch self {
        case .momentCannotBeSharedAsPost:
            "Moments live in Globe — they can't be shared as feed posts."
        case .shareFailed(let message):
            message
        }
    }
}

// MARK: - Temporary Spark discovery (same file as PostsService so Xcode always compiles it)

/// Pre-launch stand-in for the official recommender: novelty + diversity over the full R2 catalog.
enum SparkDiscoveryEngine {
    private static let defaultsKey = "spark.discovery.impressions.v1"
    private static let maxPersisted = 2_500
    private static let impressionTTLDays: Double = 21
    private static let lock = NSLock()

    private static var impressions: [String: TimeInterval] = load()
    private static var sessionServed: Set<String> = []

    static func markImpressed(_ postID: String) {
        guard !postID.isEmpty else { return }
        lock.lock()
        sessionServed.insert(postID)
        impressions[postID] = Date().timeIntervalSince1970
        lock.unlock()
        trimAndSave()
    }

    static func markImpressed(_ posts: [CountryPost]) {
        let now = Date().timeIntervalSince1970
        lock.lock()
        for post in posts {
            sessionServed.insert(post.id)
            impressions[post.id] = now
        }
        lock.unlock()
        trimAndSave()
    }

    static func markWatched(_ postID: String) {
        markImpressed(postID)
        ReelsRankingEngine.markWatched(postID)
    }

    static func resetSession() {
        lock.lock()
        sessionServed.removeAll()
        lock.unlock()
        ReelsRankingEngine.resetSession()
    }

    static func clearAllHistory() {
        lock.lock()
        sessionServed.removeAll()
        impressions.removeAll()
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        ReelsRankingEngine.resetSession()
    }

    /// Unseen first, then least-recently-seen; R2 + author/country spacing.
    static func rankForDiscovery(
        _ candidates: [CountryPost],
        excluding: Set<String> = [],
        limit: Int? = nil
    ) -> [CountryPost] {
        var seen = Set<String>()
        var pool = candidates.filter { post in
            guard seen.insert(post.id).inserted else { return false }
            guard !excluding.contains(post.id) else { return false }
            return true
        }
        guard !pool.isEmpty else { return [] }

        let now = Date().timeIntervalSince1970
        let ttl = impressionTTLDays * 24 * 3600

        lock.lock()
        let sessionSnap = sessionServed
        let impSnap = impressions
        lock.unlock()

        var fresh: [CountryPost] = []
        var stale: [CountryPost] = []
        var recent: [CountryPost] = []

        for post in pool {
            if sessionSnap.contains(post.id) {
                recent.append(post)
                continue
            }
            if let t = impSnap[post.id], now - t < ttl {
                if now - t > 2 * 24 * 3600 {
                    stale.append(post)
                } else {
                    recent.append(post)
                }
            } else {
                fresh.append(post)
            }
        }

        func diversityShuffle(_ items: [CountryPost]) -> [CountryPost] {
            guard items.count > 2 else { return items.shuffled() }
            let r2 = items.filter(\.isR2HostedMedia).shuffled()
            let rest = items.filter { !$0.isR2HostedMedia }.shuffled()
            return spacedPick(from: r2 + rest, limit: items.count)
        }

        var out = diversityShuffle(fresh) + diversityShuffle(stale) + diversityShuffle(recent)
        out = spacedPick(from: out, limit: out.count)

        if let limit, limit > 0, out.count > limit {
            return Array(out.prefix(limit))
        }
        return out
    }

    static func nextBatch(
        from candidates: [CountryPost],
        excluding existingIDs: Set<String>,
        limit: Int,
        tail: [CountryPost] = [],
        allowRecycle: Bool = false
    ) -> [CountryPost] {
        guard limit > 0 else { return [] }

        lock.lock()
        let sessionSnap = sessionServed
        lock.unlock()

        var pool = candidates.filter {
            !existingIDs.contains($0.id) && ReelsRankingEngine.isSparkEligible($0)
        }
        if pool.isEmpty, allowRecycle {
            pool = candidates.filter {
                !existingIDs.contains($0.id)
                    && ReelsRankingEngine.isSparkEligible($0)
                    && !sessionSnap.contains($0.id)
            }
        }
        if pool.isEmpty, allowRecycle {
            pool = candidates.filter { ReelsRankingEngine.isSparkEligible($0) }
        }
        guard !pool.isEmpty else { return [] }

        let ranked = rankForDiscovery(pool, excluding: existingIDs)
        var picked: [CountryPost] = []
        var context = tail
        var remaining = ranked

        while picked.count < limit, !remaining.isEmpty {
            let recentAuthors = Set(context.suffix(3).map(\.authorID))
            let recentCountries = Set(context.suffix(2).compactMap { $0.countryCode?.uppercased() })

            let diverse = remaining.enumerated().filter { _, post in
                if recentAuthors.contains(post.authorID) { return false }
                if let c = post.countryCode?.uppercased(), recentCountries.contains(c) { return false }
                return true
            }

            let choice: CountryPost
            if let d = diverse.first {
                choice = remaining.remove(at: d.offset)
            } else {
                choice = remaining.removeFirst()
            }
            picked.append(choice)
            context.append(choice)
        }

        // Do NOT markImpressed here — that burned entire batches as “seen” before the
        // user watched them and recycled the same handful of Sparks. markWatched only
        // when a Spark is actually focused in the player / feed.
        return picked
    }

    private static func spacedPick(from items: [CountryPost], limit: Int) -> [CountryPost] {
        guard !items.isEmpty else { return [] }
        var remaining = items
        var out: [CountryPost] = []
        var lastAuthor: String?
        var lastCountry: String?

        while out.count < limit, !remaining.isEmpty {
            let idx = remaining.firstIndex { post in
                if let lastAuthor, post.authorID == lastAuthor { return false }
                if let lastCountry,
                   let c = post.countryCode?.uppercased(),
                   c == lastCountry {
                    return false
                }
                return true
            } ?? remaining.startIndex
            let post = remaining.remove(at: idx)
            out.append(post)
            lastAuthor = post.authorID
            lastCountry = post.countryCode?.uppercased()
        }
        return out
    }

    private static func load() -> [String: TimeInterval] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        else { return [:] }
        let now = Date().timeIntervalSince1970
        let ttl = impressionTTLDays * 24 * 3600
        return decoded.filter { now - $0.value < ttl }
    }

    private static func trimAndSave() {
        lock.lock()
        if impressions.count > maxPersisted {
            let sorted = impressions.sorted { $0.value > $1.value }
            impressions = Dictionary(uniqueKeysWithValues: sorted.prefix(maxPersisted).map { ($0.key, $0.value) })
        }
        let snap = impressions
        lock.unlock()
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}