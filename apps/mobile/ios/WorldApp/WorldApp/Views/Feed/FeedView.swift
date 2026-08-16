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
            // App open: paint rails from cache instantly, boot feed first, then light strip network.
            // Never run beginFreshSparksSession here — that deep catalog freeze lagged the top of the feed.
            paintStripsFromCache()
            await store.beginFreshSession()
            paintStripsFromCache()
            // Defer strip network so first posts can scroll immediately.
            await refreshStrips(network: true)
        }
        .onAppear {
            paintStripsFromCache()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPostsDidChange)) { notification in
            guard let changed = notification.userInfo?["post"] as? CountryPost else { return }
            if changed.isStory { return }
            if changed.isSpark, !changed.isSparkFeedShare { return }
            store.insertNewPost(changed)
            if changed.isSparkFeedShare || changed.hasVideo {
                Task { await refreshFeedReels(network: true) }
            }
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
                            onPostUpdated: { updated in store.applyLocalUpdate(updated) }
                        )
                        .id(post.id)
                        .onAppear {
                            store.onRowAppear(post: post)
                            EngagementTracker.shared.feedPostAppeared(post, surface: "home")
                            Task { await PostsService.shared.recordView(post) }
                        }
                        .onDisappear {
                            EngagementTracker.shared.feedPostDisappeared(post)
                        }
                    }

                    if store.isLoadingMore {
                        ProgressView()
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    } else {
                        // Endless feed sentinel — always request more as the user nears the tail.
                        // R2 Sparks (28k+) keep filling; this must never be a dead end.
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                store.requestLoadMore()
                            }
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

        // Parallel light fetches — never sequential deep walks.
        async let reelsDone: Void = refreshFeedReels(network: true)
        async let contDone: Void = refreshContinueWatching(network: true)
        async let hubsDone: Void = refreshNewOnPlayNetwork(gen: gen)
        _ = await (reelsDone, contDone, hubsDone)
        guard gen == stripsNetworkGeneration else { return }
        refreshNewOnPlay()
    }

    private func refreshFeedReels(network: Bool) async {
        // Top Sparks strip only — keep this LIGHT. Never call beginFreshSparksSession
        // (deep multi-page catalog) for a 12-tile rail; that froze the feed top.
        var pool: [CountryPost] = PostsService.shared.sparksCatalogSnapshot()
        if network {
            // One small random sample + light catalog grow — not a full player session.
            async let sample = PostsService.shared.fetchDiscoverSparks(limit: 24)
            async let light = PostsService.shared.loadSparksDiscoveryCatalog(
                forceRefresh: pool.count < 20,
                deep: false
            )
            let remote = await sample
            let catalog = await light
            pool = remote + catalog + pool
        } else if pool.count > 1 {
            pool.shuffle()
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
