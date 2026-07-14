import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var appState

    @State private var posts: [CountryPost] = []
    @State private var continueWatching: [CountryPost] = []
    @State private var newOnPlay: [CountryPost] = []
    @State private var feedReels: [CountryPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var visibleLimit = 10

    private let pageSize = 12

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MatteryaTopBar(showsSearch: true) {
                    appState.navigate(to: .search)
                }

                Group {
                    if isLoading && posts.isEmpty {
                        ProgressView("Loading feed…")
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage, posts.isEmpty {
                        ContentUnavailableView(
                            "Feed unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else if posts.isEmpty {
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
            await refreshFeed(showSpinner: false, resetPagination: true, forceRefresh: true)
        }
        .task(id: appState.contentLoadGeneration) {
            await refreshFeed(showSpinner: posts.isEmpty, resetPagination: posts.isEmpty, forceRefresh: false)
            Task { await appState.refreshStories() }
            Task {
                _ = await PostsService.shared.loadPlayCatalog(
                    viewerCountry: appState.currentProfile?.countryCode,
                    followingIDs: appState.followingIDs
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPostsDidChange)) { notification in
            if let created = notification.userInfo?["post"] as? CountryPost,
               !created.isStory,
               !posts.contains(where: { $0.id == created.id }) {
                posts.insert(created, at: 0)
            }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                StoriesStripView()
                    .padding(.horizontal, Theme.pagePadding)

                if !feedReels.isEmpty {
                    feedReelsStrip
                }

                if !newOnPlay.isEmpty {
                    newOnPlayStrip
                }

                if !continueWatching.isEmpty {
                    continueWatchingStrip
                }

                ForEach(displayedPosts) { post in
                    FacebookPostCard(
                        post: post,
                        showsAuthorHeader: false,
                        showsAuthorInJournal: true,
                        onLikeToggle: { Task { await toggleLike(post) } },
                        onOpenPost: { appState.navigate(to: .post(post.id)) },
                        onOpenVideo: PlayPlatformBridge.isLongFormVideo(post)
                            ? { appState.openPost(post) }
                            : nil,
                        onOpenReel: {
                            var sparks = posts.filter(\.isReel)
                            if !sparks.contains(where: { $0.id == post.id }) {
                                sparks.insert(post, at: 0)
                            }
                            appState.openReelsViewer(startingPost: post, seedPosts: sparks)
                        },
                        onPostDeleted: { id in posts.removeAll { $0.id == id } },
                        onPostUpdated: { updated in
                            if let index = posts.firstIndex(where: { $0.id == updated.id }) {
                                posts[index] = updated
                            }
                        }
                    )
                    .padding(.horizontal, Theme.pagePadding)
                    .onAppear {
                        loadMoreIfNeeded(for: post)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private var displayedPosts: [CountryPost] {
        Array(posts.prefix(visibleLimit))
    }

    private var feedReelsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MatteryaCopy.sparksForYou)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("Swipe the world on Matterya")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Button {
                    appState.openPlay()
                } label: {
                    PlayBrandMark(compact: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(feedReels) { post in
                        Button {
                            appState.openReelsViewer(startingPost: post, seedPosts: feedReels)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let code = post.countryCode {
                                    Text(CountryFlag.emoji(for: code))
                                        .font(.caption2)
                                        .padding(5)
                                        .background(.black.opacity(0.42), in: Circle())
                                        .padding(6)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                }
                                VideoThumbnailView(
                                    post: post,
                                    maxPixelSize: 420,
                                    contentMode: .fill,
                                    showsPlayIcon: true,
                                    playIconSize: 28,
                                    placeholder: AnyView(Color.black.opacity(0.2))
                                )
                                .frame(width: 108, height: 192)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text(post.authorDisplayName)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    private func refreshFeedReels() {
        feedReels = posts
            .filter { $0.isReel && $0.playableVideoURL != nil }
            .prefix(10)
            .map { $0 }
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
                HStack(spacing: 10) {
                    ForEach(newOnPlay) { post in
                        Button {
                            appState.openPost(post)
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Theme.accentBright.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                    HandDrawnGlobeStoryRing(size: 28, highlighted: true)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    if let headline = post.displayHeadline {
                                        Text(headline)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Text(post.authorDisplayName)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.inkMuted)
                                        .lineLimit(1)
                                }
                                .frame(width: 140, alignment: .leading)
                            }
                            .padding(10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    private var continueWatchingStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Continue watching")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("See all") {
                    appState.openPlay(tab: .library)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentBright)
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(continueWatching) { post in
                        Button {
                            appState.openPost(post)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                YouTubeVideoThumbnail(post: post, maxPixelSize: 420, showsPlayIcon: true)
                                    .frame(width: 168, height: 94)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                if let headline = post.displayHeadline {
                                    Text(headline)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
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
    }

    private func loadMoreIfNeeded(for post: CountryPost) {
        guard let index = displayedPosts.firstIndex(where: { $0.id == post.id }) else { return }
        guard index >= displayedPosts.count - 3 else { return }
        guard visibleLimit < posts.count else { return }
        visibleLimit = min(posts.count, visibleLimit + pageSize)
    }

    private func refreshFeed(showSpinner: Bool, resetPagination: Bool, forceRefresh: Bool) async {
        if posts.isEmpty, let cached = ContentCache.shared.posts(for: .homeFeed) {
            posts = BlockService.shared.filterPosts(cached.filter { !$0.isStory })
            isLoading = false
        }
        if showSpinner && posts.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        defer { isLoading = false }

        var loaded = await PostsService.shared.loadHomeFeed(forceRefresh: forceRefresh)
        if loaded.isEmpty {
            loaded = await PostsService.shared.loadHomeFeed(forceRefresh: true)
        }
        posts = BlockService.shared.filterPosts(loaded.filter { !$0.isStory })
        refreshContinueWatching()
        refreshNewOnPlay()
        refreshFeedReels()
        if resetPagination {
            visibleLimit = min(pageSize, posts.count)
        } else {
            visibleLimit = min(max(visibleLimit, pageSize), posts.count)
        }
    }

    private func refreshNewOnPlay() {
        let living = ContentCache.shared.posts(for: .livingVideos) ?? []
        let following = appState.followingIDs
        var candidates = living.filter {
            PlayPlatformBridge.isLongFormVideo($0) && following.contains($0.authorID)
        }
        if candidates.isEmpty {
            candidates = posts.filter {
                PlayPlatformBridge.isLongFormVideo($0) && following.contains($0.authorID)
            }
        }
        newOnPlay = candidates
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .map { $0 }
    }

    private func refreshContinueWatching() {
        let catalog = YouTubeCatalogService.shared
        let living = ContentCache.shared.posts(for: .livingVideos) ?? []
        var history = catalog.historyVideos(from: living)
        if history.isEmpty {
            history = catalog.historyVideos(from: posts)
        }
        continueWatching = Array(history.prefix(8))
    }

    private func toggleLike(_ post: CountryPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        do {
            if post.likedByMe {
                try await PostsService.shared.unlikePost(post.id)
                posts[index] = copyPost(post, likedByMe: false, likeCount: max(0, post.likeCount - 1))
            } else {
                try await PostsService.shared.likePost(post.id)
                posts[index] = copyPost(post, likedByMe: true, likeCount: post.likeCount + 1)
            }
        } catch {
            errorMessage = error.localizedDescription
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