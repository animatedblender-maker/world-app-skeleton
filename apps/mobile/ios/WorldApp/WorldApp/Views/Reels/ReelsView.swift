import SwiftUI

struct ReelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let country: Country

    @State private var posts: [CountryPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var activeIndex = 0
    @State private var scrollPosition: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading \(MatteryaCopy.sparks.lowercased())…").tint(.white)
            } else if let errorMessage {
                ContentUnavailableView("\(MatteryaCopy.sparks) unavailable", systemImage: "video.slash", description: Text(errorMessage))
            } else if posts.isEmpty {
                ContentUnavailableView("No videos yet", systemImage: "video", description: Text("\(MatteryaCopy.noSparksForCountry) \(country.name) yet."))
            } else {
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                                ReelCard(
                                    post: post,
                                    country: country,
                                    isActive: activeIndex == index
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
                        guard let newValue else { return }
                        activeIndex = newValue
                    }
                }
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button("Back") { dismiss() }
                        .foregroundStyle(.white)
                    Spacer()
                    Text(country.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 44)
                }
                .safeAreaPadding(.top, 6)
                .padding(.horizontal, Theme.pagePadding)
                Spacer()
            }
        }
        .task {
            await load()
            scrollPosition = 0
        }
        .onDisappear {
            MediaPlaybackCoordinator.shared.stopAllPlayback()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await PostsService.shared.videoPosts(for: country)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReelCard: View {
    @Environment(AppState.self) private var appState
    @State private var post: CountryPost
    let country: Country
    let isActive: Bool

    init(post: CountryPost, country: Country, isActive: Bool) {
        self.country = country
        self.isActive = isActive
        _post = State(initialValue: post)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = post.playableVideoURL {
                if ArchiveVideoPlayback.isArchiveURL(url) || post.isHubSeedVideo {
                    ArchiveVideoPlayerView(
                        url: url,
                        posterURL: post.posterImageURL,
                        isActive: isActive,
                        muted: false,
                        // Sparks sessions start at 0; preload neighbors for instant swipe.
                        startTime: 0,
                        fillsFrame: false,
                        postID: post.id
                    )
                    .ignoresSafeArea()
                    .background(Color.black)
                } else {
                    VideoPlayerView(
                        url: url,
                        posterURL: post.posterImageURL,
                        placement: "reel",
                        countryCode: country.iso,
                        contentCountryCode: post.countryCode ?? country.iso,
                        postID: post.id,
                        adsEnabled: false,
                        isActive: isActive,
                        loops: true,
                        muted: false,
                        fillsFrame: false
                    )
                    .ignoresSafeArea()
                }
            }

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        appState.openPublicProfile(username: post.author?.username, userID: post.authorID)
                    } label: {
                        HStack {
                            AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 36)
                            Text(post.author?.displayName ?? "Member")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    if post.authorID != appState.currentProfile?.userID, !post.authorID.isEmpty {
                        FollowButton(userID: post.authorID, compact: true, onDark: true)
                    }
                }

                if let text = post.displayCaption ?? post.displayHeadline {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(4)
                }

                HStack {
                    Button {
                        Task { await toggleLike() }
                    } label: {
                        Label("\(post.likeCount)", systemImage: post.likedByMe ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.openPostInFeed(postID: post.id)
                    } label: {
                        Label("\(post.commentCount)", systemImage: "bubble.right")
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    Button("Open post") {
                        appState.openPostInFeed(postID: post.id)
                    }
                    .font(.caption.weight(.bold))
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20)
            .padding(.bottom, 40)
        }
    }

    private func toggleLike() async {
        let nextLiked = !post.likedByMe
        let nextCount = nextLiked ? post.likeCount + 1 : max(0, post.likeCount - 1)
        post = copyPost(likedByMe: nextLiked, likeCount: nextCount)
        if nextLiked {
            try? await PostsService.shared.likePost(post.id, baseLikeCount: nextCount - 1)
        } else {
            try? await PostsService.shared.unlikePost(post.id, baseLikeCount: nextCount + 1)
        }
    }

    private func copyPost(likedByMe: Bool, likeCount: Int) -> CountryPost {
        CountryPost(
            id: post.id, title: post.title, body: post.body,
            mediaType: post.mediaType, mediaURL: post.mediaURL, thumbURL: post.thumbURL,
            mediaCaption: post.mediaCaption, sharedPostID: post.sharedPostID,
            visibility: post.visibility, likeCount: likeCount, commentCount: post.commentCount,
            viewCount: post.viewCount, likedByMe: likedByMe, savedByMe: post.savedByMe,
            createdAt: post.createdAt, updatedAt: post.updatedAt,
            authorID: post.authorID, countryName: post.countryName,
            countryCode: post.countryCode, cityName: post.cityName, author: post.author,
            linkURL: post.linkURL, linkTitle: post.linkTitle,
            externalRefType: post.externalRefType, externalRefID: post.externalRefID
        )
    }
}