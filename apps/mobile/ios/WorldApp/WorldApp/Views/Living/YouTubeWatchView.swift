import SwiftUI

struct YouTubeWatchView: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    let channel: YouTubeChannel?
    let related: [CountryPost]
    var subscriberCount: Int?
    var onBack: () -> Void
    var onOpenVideo: (CountryPost) -> Void
    var onOpenChannel: (YouTubeChannel) -> Void

    @State private var currentPost: CountryPost
    @State private var inlineComments: [PostComment] = []
    @State private var commentError: String?
    @State private var commentsExpanded = false
    @State private var dismissDragOffset: CGFloat = 0
    @State private var isPullingToMinimize = false

    init(
        post: CountryPost,
        channel: YouTubeChannel?,
        related: [CountryPost],
        subscriberCount: Int? = nil,
        onBack: @escaping () -> Void,
        onOpenVideo: @escaping (CountryPost) -> Void,
        onOpenChannel: @escaping (YouTubeChannel) -> Void
    ) {
        self.post = post
        self.channel = channel
        self.related = related
        self.subscriberCount = subscriberCount
        self.onBack = onBack
        self.onOpenVideo = onOpenVideo
        self.onOpenChannel = onOpenChannel
        _currentPost = State(initialValue: post)
    }

    var body: some View {
        VStack(spacing: 0) {
            playerSection

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleSection
                    channelSection
                    actionSection
                    YouTubeExpandableDescription(text: currentPost.displayExcerpt)
                        .padding(.horizontal, Theme.pagePadding)

                    Divider().padding(.horizontal, Theme.pagePadding)

                    commentsSection
                    relatedSection
                }
                .padding(.bottom, 24)
            }
        }
        .background(Theme.canvas)
        .sharePostSheet(appState: appState)
        .task(id: currentPost.id) {
            if let refreshed = try? await PostsService.shared.getPostByID(currentPost.id) {
                currentPost = refreshed
            }
            YouTubeCatalogService.shared.recordWatch(currentPost.id)
            inlineComments = (try? await PostsService.shared.listComments(currentPost.id, limit: 30)) ?? []
        }
        .onChange(of: post.id) { _, _ in
            currentPost = post
        }
    }

    private var playerSection: some View {
        ZStack(alignment: .topLeading) {
            playerSurface
                .matteryaPullDownDismissTransform(offset: dismissDragOffset)
                .matteryaPullDownToDismiss(
                    offset: $dismissDragOffset,
                    isDragging: $isPullingToMinimize,
                    onDismiss: onBack
                )

            Button(action: onBack) {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface.opacity(0.94), in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                    .shadow(color: Theme.ink.opacity(0.08), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .safeAreaPadding(.top, 6)
            .padding(.horizontal, Theme.pagePadding + 4)
            .allowsHitTesting(!isPullingToMinimize)
        }
        .aspectRatio(YouTubeMediaLayout.aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
        .onDisappear {
            dismissDragOffset = 0
            isPullingToMinimize = false
        }
    }

    private var playerSurface: some View {
        Group {
            if let url = currentPost.playableVideoURL {
                YouTubeVideoFrame(style: .watch) {
                    VideoPlayerView(
                        url: url,
                        posterURL: currentPost.posterImageURL,
                        placement: "living",
                        countryCode: currentPost.countryCode,
                        contentCountryCode: currentPost.countryCode,
                        postID: currentPost.id,
                        isActive: true,
                        loops: false,
                        muted: false,
                        showsControls: true,
                        allowsFullscreen: true,
                        startTime: YouTubeCatalogService.shared.playbackPosition(for: currentPost.id),
                        onViewed: { Task { await PostsService.shared.recordView(currentPost) } }
                    )
                    .allowsHitTesting(!isPullingToMinimize)
                }
            } else {
                YouTubeVideoFrame(style: .watch) {
                    YouTubeVideoThumbnail(
                        post: currentPost,
                        maxPixelSize: 900,
                        frameStyle: .watch,
                        embedsFrame: false
                    )
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isPullingToMinimize, dismissDragOffset > 28 {
                Label("Release to minimize", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.ink.opacity(0.5), in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var titleSection: some View {
        if let headline = currentPost.displayHeadline {
            Text(headline)
                .postHeadlineStyle(lineLimit: 4)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var channelSection: some View {
        if let channel {
            YouTubeChannelRow(
                channel: channel,
                subscriberCount: subscriberCount,
                onTapChannel: { onOpenChannel(channel) }
            )
            .padding(.horizontal, Theme.pagePadding)
        } else {
            YouTubeVideoMetadataRow(post: currentPost, showsMenu: true)
                .padding(.horizontal, Theme.pagePadding)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 24) {
            Button { Task { await toggleLike() } } label: {
                Image(systemName: currentPost.likedByMe ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundStyle(currentPost.likedByMe ? Theme.like : Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    if let error = await appState.toggleSavePost(currentPost) {
                        appState.showToast(error, style: .error)
                    }
                }
            } label: {
                Image(systemName: appState.isPostSaved(currentPost.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                appState.presentShareSheet(for: currentPost)
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            if let country = countryFromPost(currentPost) {
                Button {
                    appState.selectCountry(country)
                    appState.selectedTab = .feed
                    appState.navigationPath.removeAll()
                    appState.navigate(to: .countryFeed(country))
                } label: {
                    Text(CountryFlag.emoji(for: country.iso))
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if currentPost.authorID != appState.currentProfile?.userID,
               !currentPost.authorID.hasPrefix("user_") {
                Button { Task { await messageCreator() } } label: {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private func countryFromPost(_ post: CountryPost) -> Country? {
        guard let code = post.countryCode?.uppercased(), !code.isEmpty else { return nil }
        let name = post.countryName ?? code
        return Country(id: code, name: name, iso: code, continent: nil, centerLat: nil, centerLng: nil)
    }

    private func messageCreator() async {
        guard !currentPost.authorID.hasPrefix("user_") else { return }
        do {
            let conversation = try await MessagesService.shared.startConversation(targetID: currentPost.authorID)
            appState.openConversation(id: conversation.id)
        } catch {
            commentError = error.localizedDescription
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(currentPost.commentCount) Comments")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if currentPost.commentCount > 3 {
                    Button(commentsExpanded ? "Show less" : "View all") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            commentsExpanded.toggle()
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentBright)
                }
            }
            .padding(.horizontal, Theme.pagePadding)

            PostCommentsView(
                postID: currentPost.id,
                comments: $inlineComments,
                showsComposer: true,
                maxVisibleComments: commentsExpanded ? nil : 3,
                totalCommentCount: currentPost.commentCount,
                onViewAllComments: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        commentsExpanded = true
                    }
                },
                onError: { commentError = $0 }
            )
            .padding(.horizontal, Theme.pagePadding)

            if let commentError {
                Text(commentError)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, Theme.pagePadding)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var relatedSection: some View {
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(MatteryaCopy.moreOnHubs)
                    .font(.system(.headline, design: .serif))
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.ink)
                    .matteryaBrandLine()
                    .padding(.horizontal, Theme.pagePadding)

                LazyVStack(spacing: 20) {
                    ForEach(related) { item in
                        YouTubeCompactRelatedRow(post: item) {
                            onOpenVideo(item)
                        }
                        .padding(.horizontal, Theme.pagePadding)
                    }
                }
            }
        }
    }

    private func toggleLike() async {
        do {
            if currentPost.likedByMe {
                try await PostsService.shared.unlikePost(currentPost.id)
                currentPost = copyPost(currentPost, likedByMe: false, likeCount: max(0, currentPost.likeCount - 1))
            } else {
                try await PostsService.shared.likePost(currentPost.id)
                currentPost = copyPost(currentPost, likedByMe: true, likeCount: currentPost.likeCount + 1)
            }
        } catch {
            commentError = error.localizedDescription
            appState.showToast(error.localizedDescription, style: .error)
        }
    }
}

private func copyPost(_ post: CountryPost, likedByMe: Bool, likeCount: Int) -> CountryPost {
    CountryPost(
        id: post.id,
        title: post.title,
        body: post.body,
        mediaType: post.mediaType,
        mediaURL: post.mediaURL,
        thumbURL: post.thumbURL,
        mediaCaption: post.mediaCaption,
        sharedPostID: post.sharedPostID,
        sharedPost: post.sharedPost,
        visibility: post.visibility,
        likeCount: likeCount,
        commentCount: post.commentCount,
        viewCount: post.viewCount,
        likedByMe: likedByMe,
        savedByMe: post.savedByMe,
        createdAt: post.createdAt,
        updatedAt: post.updatedAt,
        authorID: post.authorID,
        countryName: post.countryName,
        countryCode: post.countryCode,
        cityName: post.cityName,
        author: post.author
    )
}