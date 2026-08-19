import SwiftUI

/// Home feed UI — rendering + engagement. Loading / cache / cursor paging live in `HomeFeedStore`.
struct FeedView: View {
    @Environment(AppState.self) private var appState
    @State private var store = HomeFeedStore.shared

    @State private var continueWatching: [CountryPost] = []
    @State private var newOnPlay: [CountryPost] = []
    @State private var feedReels: [CountryPost] = []
    @State private var errorMessage: String?
    /// Prevents hammering strip network when task re-runs.
    @State private var stripsNetworkGeneration = 0

    private var hasAnyStrip: Bool {
        !feedReels.isEmpty || !continueWatching.isEmpty || !newOnPlay.isEmpty
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MatteryaTopBar(showsSearch: true) {
                    appState.navigate(to: .search)
                }

                Group {
                    // Full-screen spinner only when we have nothing at all to show.
                    // Hubs / Sparks rails paint from cache even while posts still load.
                    if store.showsSkeleton && !hasAnyStrip {
                        ProgressView("Loading feed…")
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = store.errorMessage ?? errorMessage,
                              store.displayedPosts.isEmpty, !hasAnyStrip {
                        ContentUnavailableView(
                            "Feed unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(err)
                        )
                    } else if store.displayedPosts.isEmpty && !hasAnyStrip {
                        ContentUnavailableView(
                            "Your feed is quiet",
                            systemImage: "newspaper",
                            description: Text("Posts from everywhere will show up here as people share.")
                        )
                    } else {
                        feedList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .screenBackground()
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            paintStripsFromCache()
            // Explicit pull — full reshape is OK (user asked for a new mix).
            await store.beginFreshSession(forceReplace: true)
            await refreshStrips(network: true)
        }
        .task(id: "\(appState.contentLoadGeneration)-\(appState.feedFreshSessionToken)") {
            // Coalesce rapid generation bumps (share / country) so we don't cancel mid-fetch.
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            // App open / away: reshape. contentLoadGeneration also fires on share — still reshape
            // but rank is off-main. Strips network is deferred so first scroll stays smooth.
            PerformanceTelemetry.markIfAbsent("feed_task_start")
            paintStripsFromCache()
            if store.didPaint || !store.displayedPosts.isEmpty || hasAnyStrip {
                PerformanceTelemetry.milestoneFromLaunch(
                    "app_start_to_feed_visible",
                    surface: "feed",
                    meta: ["source": "cache_or_strip"]
                )
            }
            // Soft merge when we already painted — full reshape freezes UI on every generation bump.
            let forceReshape = !store.didPaint || store.displayedPosts.isEmpty
            await store.beginFreshSession(forceReplace: forceReshape)
            guard !Task.isCancelled else { return }
            paintStripsFromCache()
            PerformanceTelemetry.milestoneFromLaunch(
                "app_start_to_feed_interactive",
                surface: "feed",
                meta: [
                    "posts": "\(store.displayedPosts.count)",
                    "didPaint": store.didPaint ? "1" : "0",
                ]
            )
            // Defer strip network well after first paint — hubs longform + deep Sparks
            // were hitching the feed open (loadLivingVideos × N + 600-item catalog).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await refreshStrips(network: true)
            }
        }
        .onAppear {
            paintStripsFromCache()
            PerformanceTelemetry.markIfAbsent("feed_on_appear")
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPostsDidChange)) { notification in
            guard let changed = notification.userInfo?["post"] as? CountryPost else { return }
            if changed.isStory { return }
            // Update in place when an existing card got a fresher media URL (was thumbnail-only).
            if store.posts.contains(where: { $0.id == changed.id }) {
                store.applyLocalUpdate(changed)
            } else if !(changed.isSpark && !changed.isSparkFeedShare) {
                store.insertNewPost(changed)
            }
            if changed.isSparkFeedShare || changed.hasVideo || changed.isSpark {
                Task { await refreshFeedReels(network: true) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPostDidDelete)) { notification in
            guard let id = notification.userInfo?["postID"] as? String else { return }
            store.removePost(id: id)
            feedReels.removeAll { $0.id == id || $0.sharedPostID == id }
            continueWatching.removeAll { $0.id == id || $0.sharedPostID == id }
            newOnPlay.removeAll { $0.id == id || $0.sharedPostID == id }
        }
    }

    private var feedList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 1).id("feed-top")

                    ForEach(store.pendingUploads) { draft in
                        FeedUploadingShadowCard(draft: draft)
                            .id("upload-\(draft.id)")
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))
                                )
                            )
                    }

                    // Sparks → Continue watching (Hubs) → New on Hubs — always above posts.
                    // Single unified feed (Phase-0 recsys mixes following + discovery).
                    if !feedReels.isEmpty {
                        feedReelsStrip
                    }
                    if !continueWatching.isEmpty {
                        continueWatchingStrip
                    }
                    if !newOnPlay.isEmpty {
                        newOnPlayStrip
                    }

                    // Posts still bootstrapping but rails already visible.
                    if store.showsSkeleton && store.displayedPosts.isEmpty {
                        ProgressView()
                            .padding(.vertical, 28)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(store.displayedPosts) { post in
                        FacebookPostCard(
                            post: post,
                            edgeToEdge: true,
                            showsAuthorHeader: false,
                            showsAuthorInJournal: true,
                            onLikeToggle: { Task { await toggleLike(post) } },
                            onOpenPost: { appState.navigate(to: .post(post.id)) },
                            onOpenVideo: {
                                appState.openPost(post)
                            },
                            onOpenReel: {
                                appState.openGlobalSparksViewer(startingPost: post)
                            },
                            onPostDeleted: { id in store.removePost(id: id) },
                            onPostUpdated: { updated in store.applyLocalUpdate(updated) },
                            onHide: { id in
                                store.applyNegativeFeedback(postID: id, kind: .hide)
                                appState.showToast("Hidden from your feed.", style: .info)
                            },
                            onNotInterested: { id in
                                store.applyNegativeFeedback(postID: id, kind: .notInterested)
                                appState.showToast("We'll show less like this.", style: .info)
                            }
                        )
                        .id(post.id)
                        .onAppear {
                            store.onRowAppear(post: post)
                            // Media session 09: mid-fling skip engagement/network (scroll budget).
                            guard !ScrollBudget.isFlinging else { return }
                            EngagementTracker.shared.feedPostAppeared(
                                post,
                                surface: RecommendationSurface.homeForYou.rawValue
                            )
                            Task { await PostsService.shared.recordView(post) }
                        }
                        .onDisappear {
                            EngagementTracker.shared.feedPostDisappeared(post)
                        }
                    }

                    // Endless sentinel — always top up ahead. Spinner only when truly empty tail.
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            store.requestLoadMore()
                        }
                    if store.isLoadingMore, store.displayedPosts.count < 6 {
                        ProgressView()
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
                .animation(MatteryaMotion.insert, value: store.pendingUploads.map(\.id))
            }
            .onChange(of: appState.feedScrollToTopToken) { _, _ in
                withAnimation(MatteryaMotion.scroll) {
                    if let firstUpload = store.pendingUploads.first {
                        proxy.scrollTo("upload-\(firstUpload.id)", anchor: .top)
                    } else if let first = store.displayedPosts.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    } else {
                        proxy.scrollTo("feed-top", anchor: .top)
                    }
                }
            }
            .onChange(of: store.pendingUploads.first?.id) { _, newID in
                guard let newID else { return }
                withAnimation(MatteryaMotion.insert) {
                    proxy.scrollTo("upload-\(newID)", anchor: .top)
                }
            }
        }
    }

    private var feedReelsStrip: some View {
        SparksHorizontalStrip(
            posts: feedReels,
            onOpen: { post in
                appState.openGlobalSparksViewer(startingPost: post)
            },
            onBrandTap: { appState.openPlay() }
        )
    }

    private var newOnPlayStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(MatteryaCopy.newOnHubs)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .matteryaBrandLine()
                    .layoutPriority(1)
                Spacer()
                Button {
                    appState.openPlay(tab: .subscriptions)
                } label: {
                    PlayBrandMark(compact: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(newOnPlay) { post in
                        HubsShelfThumbCard(
                            post: post,
                            width: 160,
                            extractFrameIfNeeded: false
                        ) {
                            appState.openPost(post)
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
        .padding(.bottom, 12)
    }

    private var continueWatchingStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(MatteryaCopy.continueWatching)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .layoutPriority(1)
                Spacer()
                Button {
                    appState.openPlay(tab: .home)
                } label: {
                    Text(MatteryaCopy.matteryaHubs)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentBright)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(continueWatching) { post in
                        HubsShelfThumbCard(
                            post: post,
                            width: 160,
                            extractFrameIfNeeded: false
                        ) {
                            appState.openPost(post)
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Strips (instant cache → light network)

    /// Zero-network paint so Hubs / Sparks rails appear with the first frame.
    private func paintStripsFromCache() {
        let living = ContentCache.shared.posts(for: .livingVideos) ?? []
        let catalog = PostsService.shared.sparksCatalogSnapshot()
        let home = ContentCache.shared.posts(for: .homeFeed) ?? store.posts
        let sessionHubs = PostsService.shared.hubsSessionCatalog

        // Sparks-for-you rail — only seed when empty. Session reshuffle lives in
        // `refreshFeedReels` (pure shuffle of the R2 catalog). Re-ranking here used to
        // overwrite that shuffle with the same sticky discovery order every paint.
        if feedReels.isEmpty {
            var seen = Set<String>()
            var reels: [CountryPost] = []
            let pool = (catalog + living + home + sessionHubs)
                .filter { ReelsRankingEngine.isSparkEligible($0) && $0.playableVideoURL != nil }
                .shuffled()
            for post in pool {
                guard seen.insert(post.id).inserted else { continue }
                reels.append(post)
                if reels.count >= 14 { break }
            }
            if !reels.isEmpty {
                feedReels = reels
            }
        }

        // New on Hubs — always fill from cache pools.
        refreshNewOnPlay(from: living)

        // Continue watching — cache + history only (no Archive seed walk, no network).
        if continueWatching.isEmpty {
            continueWatching = buildContinueWatching(
                pools: [living, home, sessionHubs],
                allowSeed: false
            )
        }
    }

    private func refreshStrips(network: Bool) async {
        // Always re-paint cache first so UI updates even if network is slow.
        paintStripsFromCache()
        guard network else { return }

        stripsNetworkGeneration += 1
        let gen = stripsNetworkGeneration

        // Sparks rail only on the hot path — never pull hubs longform catalog here
        // (that froze Feed while Hubs tab’s own loader already runs loadLivingVideos).
        await refreshFeedReels(network: true)
        guard gen == stripsNetworkGeneration else { return }
        // Cache-only hubs strips; network hubs stay on the Hubs tab.
        refreshNewOnPlay()
        await refreshContinueWatching(network: false)
    }

    private func refreshFeedReels(network: Bool) async {
        // Top Sparks strip only — keep this LIGHT. Never call beginFreshSparksSession
        // (deep multi-page catalog) for a 12-tile rail; that froze the feed top.
        let snapshot = PostsService.shared.sparksCatalogSnapshot()
        let pool: [CountryPost]
        if network {
            // One small random sample + light catalog grow — not a full player session.
            // Capture snapshot.count only — never mutate a var across async-let boundaries.
            let forceRefresh = snapshot.count < 20
            async let sample = PostsService.shared.fetchDiscoverSparks(limit: 24)
            async let light = PostsService.shared.loadSparksDiscoveryCatalog(
                forceRefresh: forceRefresh,
                deep: false
            )
            let remote = await sample
            let catalog = await light
            pool = remote + catalog + snapshot
        } else if snapshot.count > 1 {
            var shuffled = snapshot
            shuffled.shuffle()
            pool = shuffled
        } else {
            pool = snapshot
        }

        // Unviewed first so the rail matches discovery rules without heavy ranking.
        let ranked = SparkDiscoveryEngine.rankForDiscovery(
            pool.filter { ReelsRankingEngine.isSparkEligible($0) && $0.playableVideoURL != nil }
        )
        var seen = Set<String>()
        var merged: [CountryPost] = []
        for post in ranked {
            guard seen.insert(post.id).inserted else { continue }
            merged.append(post)
            if merged.count >= 12 { break }
        }
        if !merged.isEmpty {
            feedReels = merged
            // Thumbnails only — do not deep-warm AVPlayers for the whole strip.
            ImageCache.shared.prefetchFeedMedia(Array(merged.prefix(4)), maxPixelSize: 280)
        }
    }

    private func refreshNewOnPlay(from livingOverride: [CountryPost]? = nil) {
        let living = livingOverride ?? ContentCache.shared.posts(for: .livingVideos) ?? []
        let following = appState.followingIDs
        var candidates = living.filter {
            PlayPlatformBridge.isHubFeedCardVideo($0)
                && (following.isEmpty || following.contains($0.authorID))
        }
        if candidates.isEmpty {
            candidates = living.filter { PlayPlatformBridge.isHubFeedCardVideo($0) }
        }
        if candidates.isEmpty {
            candidates = store.posts.filter { PlayPlatformBridge.isHubFeedCardVideo($0) }
        }
        // Session hubs catalog (may already be warm from Hubs tab).
        if candidates.count < 4 {
            let session = PostsService.shared.hubsSessionCatalog.filter {
                PlayPlatformBridge.isHubFeedCardVideo($0)
            }
            candidates.append(contentsOf: session)
        }
        var seen = Set<String>()
        newOnPlay = candidates
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .map { $0 }
    }

    /// Light hubs longform for New on Hubs when disk/session cache is thin.
    private func refreshNewOnPlayNetwork(gen: Int) async {
        let living = ContentCache.shared.posts(for: .livingVideos) ?? []
        let sessionLong = PostsService.shared.hubsSessionCatalog.filter {
            PlayPlatformBridge.isHubFeedCardVideo($0)
        }
        guard living.count + sessionLong.count < 6 else { return }
        let fast = await PostsService.shared.loadLivingVideos(
            globalLimit: 16,
            forceRefresh: false,
            fast: true
        )
        guard gen == stripsNetworkGeneration else { return }
        if !fast.isEmpty {
            refreshNewOnPlay(from: fast)
        }
    }

    private func refreshContinueWatching(network: Bool) async {
        let catalog = YouTubeCatalogService.shared
        guard !catalog.historyIDs().isEmpty else {
            continueWatching = []
            return
        }
        var pools: [[CountryPost]] = [
            ContentCache.shared.posts(for: .livingVideos) ?? [],
            store.posts,
            PostsService.shared.hubsSessionCatalog,
        ]
        // Only hit network if we still have nothing to show from cache.
        if network, buildContinueWatching(pools: pools, allowSeed: false).isEmpty {
            let fast = await PostsService.shared.loadLivingVideos(
                globalLimit: 16,
                forceRefresh: false,
                fast: true
            )
            pools.append(fast)
        }
        continueWatching = buildContinueWatching(pools: pools, allowSeed: false)
    }

    private func buildContinueWatching(pools: [[CountryPost]], allowSeed: Bool) -> [CountryPost] {
        let catalog = YouTubeCatalogService.shared
        var pool: [CountryPost] = []
        var seen = Set<String>()
        for batch in pools {
            for post in batch where seen.insert(post.id).inserted {
                pool.append(post)
            }
        }
        if allowSeed, AppConfig.archiveContentEnabled {
            // Intentionally skipped on hot path.
        }

        let hubLongForm = pool.filter {
            !$0.isReel && PlayPlatformBridge.isHubCatalogContent($0) && $0.playableVideoURL != nil
        }

        var ordered: [CountryPost] = []
        var orderedIDs = Set<String>()
        for post in catalog.historyVideos(from: hubLongForm) where orderedIDs.insert(post.id).inserted {
            ordered.append(post)
        }
        let inProgress = hubLongForm
            .filter { catalog.playbackPosition(for: $0.id) >= 1 }
            .sorted {
                catalog.playbackPosition(for: $0.id) > catalog.playbackPosition(for: $1.id)
            }
        for post in inProgress where orderedIDs.insert(post.id).inserted {
            ordered.append(post)
        }
        return Array(ordered.prefix(8))
    }

    private func toggleLike(_ post: CountryPost) async {
        do {
            let updated: CountryPost
            if post.likedByMe {
                try await PostsService.shared.unlikePost(post.id, baseLikeCount: post.likeCount)
                updated = post.withEngagement(
                    likedByMe: false,
                    likeCount: max(0, post.likeCount - 1),
                    commentCount: post.commentCount
                )
            } else {
                try await PostsService.shared.likePost(post.id, baseLikeCount: post.likeCount)
                updated = post.withEngagement(
                    likedByMe: true,
                    likeCount: post.likeCount + 1,
                    commentCount: post.commentCount
                )
            }
            store.applyLocalUpdate(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
