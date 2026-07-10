import SwiftUI

struct ReelsTabView: View {
    @Environment(AppState.self) private var appState

    @State private var posts: [CountryPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var activeIndex = 0
    @State private var scrollPosition: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            if isLoading {
                ProgressView("Loading reels…")
                    .tint(.white)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Reels unavailable",
                    systemImage: "video.slash",
                    description: Text(errorMessage)
                )
            } else if posts.isEmpty {
                ContentUnavailableView(
                    "No videos yet",
                    systemImage: "video",
                    description: Text("Check back soon for reels from around the world.")
                )
            } else {
                horizontalReelsFeed
            }

            MenuToolbarButton(tint: .white)
                .padding(.top, 8)
                .padding(.leading, Theme.pagePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            ReelsRankingEngine.resetSession()
            await loadReels()
        }
        .task {
            await loadReels()
            scrollPosition = activeIndex
            recordView(at: activeIndex)
        }
    }

    private var horizontalReelsFeed: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                        ReelsTabCard(
                            post: post,
                            isActive: activeIndex == index,
                            onLikeToggle: { Task { await toggleLike(post) } },
                            onOpenPost: { appState.navigate(to: .post(post.id)) }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollPosition)
            .onChange(of: scrollPosition) { _, newValue in
                guard let newValue, newValue != activeIndex else { return }
                activeIndex = newValue
                recordView(at: newValue)
            }
        }
    }

    private func recordView(at index: Int) {
        guard posts.indices.contains(index) else { return }
        let post = posts[index]
        Task { await PostsService.shared.recordView(post) }
    }

    private func loadReels() async {
        isLoading = posts.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        let pool = await PostsService.shared.loadReelsPool()
        let viewerCountry = appState.currentProfile?.countryCode
        posts = ReelsRankingEngine.rank(
            pool,
            viewerCountry: viewerCountry,
            followingIDs: appState.followingIDs
        )
        if activeIndex >= posts.count {
            activeIndex = 0
            scrollPosition = 0
        }
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

private struct ReelsTabCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    let isActive: Bool
    let onLikeToggle: () -> Void
    let onOpenPost: () -> Void

    @State private var showComments = false
    @State private var comments: [PostComment] = []
    @State private var commentError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let url = post.playableVideoURL {
                VideoPlayerView(
                    url: url,
                    posterURL: post.posterImageURL,
                    placement: "reel",
                    countryCode: post.countryCode,
                    contentCountryCode: post.countryCode,
                    postID: post.id,
                    isActive: isActive,
                    loops: true,
                    muted: false,
                    onViewed: { Task { await PostsService.shared.recordView(post) } }
                )
            } else {
                Color.black
                Image(systemName: "video.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.5))
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    authorRow
                    Text(post.displayCaption ?? post.displayHeadline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(4)
                    if let country = post.countryName {
                        Text(country)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.leading, 20)
                .padding(.bottom, Theme.tabBarHeight + 12)

                Spacer()

                VStack(spacing: 22) {
                    actionButton(
                        icon: post.likedByMe ? "heart.fill" : "heart",
                        label: "\(post.likeCount)",
                        tint: post.likedByMe ? Theme.like : .white,
                        action: onLikeToggle
                    )

                    actionButton(
                        icon: "bubble.right.fill",
                        label: "\(post.commentCount)",
                        tint: .white
                    ) {
                        showComments = true
                    }

                    actionButton(
                        icon: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark",
                        label: "Save",
                        tint: appState.isPostSaved(post.id) ? Theme.facebookBlue : .white
                    ) {
                        Task { await appState.toggleSavePost(post, reelPresentation: true) }
                    }

                    actionButton(
                        icon: "arrow.up.right",
                        label: "Open",
                        tint: .white,
                        action: onOpenPost
                    )
                }
                .padding(.trailing, 16)
                .padding(.bottom, Theme.tabBarHeight + 12)
            }
        }
        .sheet(isPresented: $showComments) {
            NavigationStack {
                ScrollView {
                    PostCommentsView(
                        postID: post.id,
                        comments: $comments,
                        onError: { commentError = $0 }
                    )
                    .padding(Theme.pagePadding)

                    if let commentError {
                        Text(commentError)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, Theme.pagePadding)
                    }
                }
                .screenBackground()
                .navigationTitle("Comments")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showComments = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var authorRow: some View {
        Button {
            if let username = post.author?.username {
                appState.navigate(to: .publicProfile(username: username))
            }
        } label: {
            HStack(spacing: 10) {
                AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 36)
                Text(post.author?.displayName ?? "Member")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private func actionButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .buttonStyle(.plain)
    }
}