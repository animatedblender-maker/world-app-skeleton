import SwiftUI

/// Home feed UI — rendering + engagement. Loading / cache / cursor paging live in `HomeFeedStore`.
struct FeedView: View {
    @Environment(AppState.self) private var appState
    @State private var store = HomeFeedStore.shared

    @State private var continueWatching: [CountryPost] = []
    @State private var newOnPlay: [CountryPost] = []
    @State private var feedReels: [CountryPost] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MatteryaTopBar(showsSearch: true) {
                    appState.navigate(to: .search)
                }

                Group {
                    if store.showsSkeleton {
                        ProgressView("Loading feed…")
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = store.errorMessage ?? errorMessage, store.displayedPosts.isEmpty {
                        ContentUnavailableView(
                            "Feed unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(err)
                        )
                    } else if store.displayedPosts.isEmpty {
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
            await store.bootstrap(forceRefresh: true)
            await refreshStrips()
        }
        .task(id: appState.contentLoadGeneration) {
            await store.bootstrap(forceRefresh: false)
            await refreshStrips()
            _ = await PostsService.shared.loadPlayCatalog(
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs
            )
            await refreshContinueWatching()
            refreshNewOnPlay()
        }
        .onAppear {
            if feedReels.isEmpty || newOnPlay.isEmpty || continueWatching.isEmpty {
                Task { await refreshStrips() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPostsDidChange)) { notification in
            guard let changed = notification.userInfo?["post"] as? CountryPost else { return }
            if changed.isStory { return }
            if changed.isSpark { return }
            // Prefer insert (new posts) over silent update-only.
            store.insertNewPost(changed)
        }
    }

    private var feedList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 1).id("feed-top")

                    // Uploading video shadows pin above everything else.
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

                    // Sparks → Continue watching (Hubs) → New on Hubs → posts.
                    if !feedReels.isEmpty {
                        feedReelsStrip
                    }
                    if !continueWatching.isEmpty {
                        continueWatchingStrip
                    }
                    if !newOnPlay.isEmpty {
                        newOnPlayStrip
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
                                // Hub long-form → Hubs watch; plain feed video → post detail.
                                appState.openPost(post)
                            },
                            onOpenReel: {
                                var sparks = store.posts.filter(\.isReel)
                                if !sparks.contains(where: { $0.id == post.id }) {
                                    sparks.insert(post, at: 0)
                                }
                                appState.openReelsViewer(startingPost: post, seedPosts: sparks)
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
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: store.pendingUploads.map(\.id))
            }
            .onChange(of: appState.feedScrollToTopToken) { _, _ in
                withAnimation(.easeOut(duration: 0.35)) {
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
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("upload-\(newID)", anchor: .top)
                }
            }
        }
    }

    private var feedReelsStrip: some View {
        SparksHorizontalStrip(
            posts: feedReels,
            onOpen: { post in
                appState.openReelsViewer(startingPost: post, seedPosts: feedReels)
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
                HStack(spacing: 12) {
                    ForEach(newOnPlay) { post in
                        Button {
                            appState.openPost(post)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                YouTubeVideoThumbnail(
                                    post: post,
                                    maxPixelSize: 320,
                                    showsPlayIcon: false,
                                    frameStyle: .card,
                                    extractFrameIfNeeded: false,
                                    showsHubBadge: false
                                )
                                .frame(width: 168, height: 94)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                if let headline = post.displayHeadline {
                                    Text(headline)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(2)
                                        .frame(width: 168, alignment: .leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
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
                Text("Continue watching")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
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
                HStack(spacing: 12) {
                    ForEach(continueWatching) { post in
                        Button {
                            appState.openPost(post)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                YouTubeVideoThumbnail(
                                    post: post,
                                    maxPixelSize: 320,
                                    showsPlayIcon: false,
                                    frameStyle: .card,
                                    extractFrameIfNeeded: false,
                                    showsHubBadge: false
                                )
                                .frame(width: 168, height: 94)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                if let headline = post.displayHeadline {
                                    Text(headline)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(2)
                                        .frame(width: 168, alignment: .leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
        .padding(.bottom, 12)
    }

    private func refreshStrips() async {
        await refreshFeedReels()
        await refreshContinueWatching()
        refreshNewOnPlay()
    }

    private func refreshFeedReels() async {
        let reels = await PostsService.shared.loadReelsFeed(
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs
        )
        feedReels = reels
            .filter { $0.playableVideoURL != nil }
            .prefix(10)
            .map { $0 }
        if !feedReels.isEmpty {
            SparkWarmPool.shared.prepare(posts: feedReels, around: 0, ahead: 2, behind: 0)
        }
    }

    private func refreshNewOnPlay() {
        let living = ContentCache.shared.posts(for: .livingVideos) ?? []
        let following = appState.followingIDs
        // Strip is hub-only (same rule as Hubs catalog).
        var candidates = living.filter {
            PlayPlatformBridge.isHubFeedCardVideo($0) && following.contains($0.authorID)
        }
        if candidates.isEmpty {
            candidates = store.posts.filter {
                PlayPlatformBridge.isHubFeedCardVideo($0) && following.contains($0.authorID)
            }
        }
        newOnPlay = candidates
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .map { $0 }
    }

    /// Hubs resume row — history + partial progress, resolved against living cache + seeds.
    private func refreshContinueWatching() async {
        let catalog = YouTubeCatalogService.shared
        var pool: [CountryPost] = []
        var seen = Set<String>()
        func append(_ posts: [CountryPost]) {
            for post in posts where seen.insert(post.id).inserted {
                pool.append(post)
            }
        }
        append(ContentCache.shared.posts(for: .livingVideos) ?? [])
        append(store.posts)
        append(await HubVideoSeedService.shared.longFormVideos())

        let hubLongForm = pool.filter {
            !$0.isReel && PlayPlatformBridge.isHubCatalogContent($0) && $0.playableVideoURL != nil
        }

        var ordered: [CountryPost] = []
        var orderedIDs = Set<String>()
        for post in catalog.historyVideos(from: hubLongForm) where orderedIDs.insert(post.id).inserted {
            ordered.append(post)
        }
        // Also surface anything with a saved resume point (watched mid-video).
        let inProgress = hubLongForm
            .filter { catalog.playbackPosition(for: $0.id) >= 1 }
            .sorted { catalog.playbackPosition(for: $0.id) > catalog.playbackPosition(for: $1.id) }
        for post in inProgress where orderedIDs.insert(post.id).inserted {
            ordered.append(post)
        }

        continueWatching = Array(ordered.prefix(8))
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
                EngagementTracker.shared.enqueueLike(post: post, liked: false)
            } else {
                try await PostsService.shared.likePost(post.id, baseLikeCount: post.likeCount)
                updated = post.withEngagement(
                    likedByMe: true,
                    likeCount: post.likeCount + 1,
                    commentCount: post.commentCount
                )
                EngagementTracker.shared.enqueueLike(post: post, liked: true)
            }
            store.applyLocalUpdate(updated)
            PostsService.shared.publishPostChange(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
