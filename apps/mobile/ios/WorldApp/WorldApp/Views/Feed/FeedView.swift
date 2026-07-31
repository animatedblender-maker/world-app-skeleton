import SwiftUI

/// Home feed UI — rendering only. Loading / cache / cursor paging live in `HomeFeedStore`.
struct FeedView: View {
    @Environment(AppState.self) private var appState
    @State private var store = HomeFeedStore.shared

    @State private var continueWatching: [CountryPost] = []
    @State private var feedReels: [CountryPost] = []
    @State private var sparksReshuffleTask: Task<Void, Never>?
    @State private var actionError: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MatteryaTopBar(showsSearch: true) {
                    appState.navigate(to: .search)
                }

                Group {
                    if store.showsSkeleton {
                        feedSkeleton
                    } else if let error = store.errorMessage ?? actionError, store.posts.isEmpty {
                        ContentUnavailableView(
                            "Feed unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    } else if store.posts.isEmpty {
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
            // Explicit refresh → new feed session + fresh Sparks suggestions.
            await store.bootstrap(forceRefresh: true)
            await reshuffleFeedSparks()
            refreshContinueWatching()
        }
        .task(id: appState.contentLoadGeneration) {
            // Must: cached paint. Later: SWR. Predicted: media warm in store.
            await store.bootstrap(forceRefresh: false)
            await reshuffleFeedSparks()
            refreshContinueWatching()
        }
        .onChange(of: appState.selectedTab) { _, tab in
            // Leaving + returning to Home always gets a new Sparks strip.
            guard tab == .feed else { return }
            Task { await reshuffleFeedSparks() }
        }
        .onAppear {
            // Persistent tab may not re-run task — reshuffle when feed becomes visible.
            if appState.selectedTab == .feed, feedReels.isEmpty {
                Task { await reshuffleFeedSparks() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPostsDidChange)) { notification in
            guard let changed = notification.userInfo?["post"] as? CountryPost else { return }
            if changed.isStory { return }
            if store.posts.contains(where: { $0.id == changed.id }) {
                store.applyLocalUpdate(changed)
            } else if !changed.isSpark {
                store.insertNewPost(changed)
            }
        }
    }

    // MARK: - Skeleton (reserved layout — no spinner-only blank)

    private var feedSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Theme.canvasMuted)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Theme.canvasMuted)
                                    .frame(width: 120, height: 12)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Theme.canvasMuted)
                                    .frame(width: 80, height: 10)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, Theme.feedGutter)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.canvasMuted)
                            .frame(height: 14)
                            .padding(.horizontal, Theme.feedGutter)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.canvasMuted)
                            .frame(height: 14)
                            .padding(.horizontal, Theme.feedGutter)
                            .padding(.trailing, 40)
                        Rectangle()
                            .fill(Theme.canvasMuted)
                            .frame(height: 200)
                        Theme.divider.frame(height: 0.5)
                    }
                    .padding(.vertical, 12)
                    .redacted(reason: .placeholder)
                }
            }
            .padding(.top, 8)
        }
        .allowsHitTesting(false)
    }

    // MARK: - List

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                if !feedReels.isEmpty {
                    feedReelsStrip
                        .id("feed-reels-strip")
                }
                // No “New on Hubs” strip between Sparks and Continue watching.
                if !continueWatching.isEmpty {
                    continueWatchingStrip
                        .id("feed-continue-strip")
                }

                ForEach(store.displayedPosts) { post in
                    FacebookPostCard(
                        post: post,
                        edgeToEdge: true,
                        showsAuthorHeader: false,
                        showsAuthorInJournal: true,
                        onLikeToggle: { Task { await toggleLike(post) } },
                        onOpenPost: { appState.navigate(to: .post(post.id)) },
                        onOpenVideo: PlayPlatformBridge.isLongFormVideo(post)
                            ? { appState.openPost(post) }
                            : nil,
                        onOpenReel: {
                            // Prefer the current shuffled strip, then any reel posts on the feed.
                            var sparks = feedReels
                            if sparks.isEmpty {
                                sparks = store.posts.filter(\.isReel)
                            }
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
                        // Behavior log: how long this post stays on screen.
                        EngagementTracker.shared.feedPostAppeared(post, surface: "home")
                    }
                    .onDisappear {
                        EngagementTracker.shared.feedPostDisappeared(post)
                    }
                }

                if store.isLoadingMore {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    /// Fresh Sparks suggestions every feed reload / tab return.
    private func reshuffleFeedSparks() async {
        sparksReshuffleTask?.cancel()
        let task = Task(priority: .userInitiated) { () -> [CountryPost] in
            let seed = UInt64.random(in: 1...UInt64.max)
                ^ UInt64(Date().timeIntervalSince1970 * 1_000)
            let seeds = await HubVideoSeedService.shared.sparkSeedVideos(
                limit: 18,
                shuffleSeed: seed
            )
            return seeds.filter { $0.playableVideoURL != nil }.prefix(8).map { $0 }
        }
        sparksReshuffleTask = Task {
            let next = await task.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { feedReels = next }
                ImageCache.shared.prefetchFeedMedia(next, maxPixelSize: 320)
                // Warm first few CDNs so opening Sparks feels instant.
                for post in next.prefix(4) {
                    if let url = post.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) {
                        ArchiveVideoPlayback.warmResolve(url)
                    }
                }
            }
        }
        await sparksReshuffleTask?.value
    }

    private var feedReelsStrip: some View {
        SparksHorizontalStrip(
            posts: feedReels,
            onOpen: { post in
                appState.openReelsViewer(startingPost: post, seedPosts: feedReels)
            },
            onBrandTap: {
                if let first = feedReels.first {
                    appState.openReelsViewer(startingPost: first, seedPosts: feedReels)
                } else {
                    Task { await appState.openReelsFromMenu() }
                }
            }
        )
        // Force SwiftUI to rebuild tiles when the shuffle order changes.
        .id(feedReels.map(\.id).joined(separator: "|"))
    }

    private var continueWatchingStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Continue watching")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("See all") { appState.openPlay(tab: .library) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentBright)
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(continueWatching) { post in
                        Button {
                            appState.openPost(post)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                // Matterya Hubs chrome (globe / brand) — not a YouTube play button.
                                YouTubeVideoThumbnail(
                                    post: post,
                                    maxPixelSize: 320,
                                    showsPlayIcon: false,
                                    frameStyle: .card,
                                    extractFrameIfNeeded: false
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
                                Text(post.authorDisplayName)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.inkMuted)
                                    .lineLimit(1)
                                    .frame(width: 168, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    private func refreshContinueWatching() {
        let catalog = YouTubeCatalogService.shared
        let living = ContentCache.shared.posts(for: .livingVideos) ?? []
        var history = catalog.historyVideos(from: living)
        if history.isEmpty {
            history = catalog.historyVideos(from: store.posts)
        }
        continueWatching = Array(history.prefix(4))
    }

    private func toggleLike(_ post: CountryPost) async {
        // Optimistic UI — must feel immediate.
        let optimistic: CountryPost
        if post.likedByMe {
            optimistic = copyPost(post, likedByMe: false, likeCount: max(0, post.likeCount - 1))
        } else {
            optimistic = copyPost(post, likedByMe: true, likeCount: post.likeCount + 1)
        }
        store.applyLocalUpdate(optimistic)
        do {
            if post.likedByMe {
                try await PostsService.shared.unlikePost(post.id)
            } else {
                try await PostsService.shared.likePost(post.id)
            }
            PostsService.shared.publishPostChange(optimistic)
        } catch {
            store.applyLocalUpdate(post)
            actionError = error.localizedDescription
        }
    }

    private func copyPost(_ post: CountryPost, likedByMe: Bool, likeCount: Int) -> CountryPost {
        CountryPost(
            id: post.id, title: post.title, body: post.body,
            mediaType: post.mediaType, mediaURL: post.mediaURL, thumbURL: post.thumbURL,
            mediaCaption: post.mediaCaption, sharedPostID: post.sharedPostID,
            visibility: post.visibility, likeCount: likeCount, commentCount: post.commentCount,
            viewCount: post.viewCount, likedByMe: likedByMe, savedByMe: post.savedByMe,
            createdAt: post.createdAt, updatedAt: post.updatedAt,
            authorID: post.authorID, countryName: post.countryName,
            countryCode: post.countryCode, cityName: post.cityName, author: post.author
        )
    }
}
