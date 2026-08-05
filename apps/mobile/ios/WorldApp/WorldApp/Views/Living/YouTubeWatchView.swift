import SwiftUI

struct YouTubeWatchView: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    let channel: YouTubeChannel?
    let related: [CountryPost]
    var subscriberCount: Int?
    /// When false, the parent owns a continuous player layer (seamless minimize).
    var embedsPlayer: Bool = true
    var onBack: () -> Void
    var onOpenVideo: (CountryPost) -> Void
    var onOpenChannel: (YouTubeChannel) -> Void

    @State private var currentPost: CountryPost
    @State private var inlineComments: [PostComment] = []
    @State private var commentError: String?
    @State private var commentsExpanded = false
    @State private var dismissDragOffset: CGFloat = 0
    @State private var isPullingToMinimize = false
    @State private var isLiking = false
    /// Endless related shelf — grows as the user scrolls.
    @State private var relatedWindow: [RelatedShelfItem] = []
    @State private var relatedCursor = 0

    init(
        post: CountryPost,
        channel: YouTubeChannel?,
        related: [CountryPost],
        subscriberCount: Int? = nil,
        embedsPlayer: Bool = true,
        onBack: @escaping () -> Void,
        onOpenVideo: @escaping (CountryPost) -> Void,
        onOpenChannel: @escaping (YouTubeChannel) -> Void
    ) {
        self.post = post
        self.channel = channel
        self.related = related
        self.subscriberCount = subscriberCount
        self.embedsPlayer = embedsPlayer
        self.onBack = onBack
        self.onOpenVideo = onOpenVideo
        self.onOpenChannel = onOpenChannel
        _currentPost = State(initialValue: HubEngagementStore.shared.applyLikeState(to: post).withCommentCount(
            HubEngagementStore.shared.commentCount(post.id, seed: post.commentCount)
        ))
    }

    /// 1 = full chrome visible; 0 = only video (while pulling down to mini player).
    private var chromeOpacity: Double {
        let progress = min(max(dismissDragOffset, 0) / MatteryaPullDownDismiss.dismissDistance, 1)
        return Double(1 - progress)
    }

    private var isHubContent: Bool {
        PlayPlatformBridge.isHubCatalogContent(currentPost)
            || HubEngagementStore.isHubContentID(currentPost.id)
    }

    var body: some View {
        GeometryReader { geo in
            // Content-space stage height. Parent continuous player extends under the
            // status bar by +topInset; the spacer here must stay stage-only so title
            // sits flush under the video (no white band).
            let stageHeight = YouTubeMediaLayout.watchPlayerHeight(
                containerWidth: geo.size.width,
                containerHeight: geo.size.height
            )
            VStack(spacing: 0) {
                playerSection
                    .frame(width: geo.size.width, height: stageHeight)
                    .background(Theme.ink)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        titleSection
                        channelSection
                        actionSection
                        descriptionSection
                            .padding(.horizontal, Theme.pagePadding)
                            .id("desc-\(currentPost.id)")

                        Divider().padding(.horizontal, Theme.pagePadding)

                        commentsSection
                        relatedSection
                    }
                    // Clear gap under the video so the title isn’t covered by the player.
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .opacity(chromeOpacity)
                .allowsHitTesting(chromeOpacity > 0.2 && !isPullingToMinimize)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(Theme.canvas)
        .animation(isPullingToMinimize ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: chromeOpacity)
        .sharePostSheet(appState: appState)
        .task(id: currentPost.id) {
            await hydrateEngagement()
            YouTubeCatalogService.shared.recordWatch(currentPost.id)
            resetRelatedShelf()
        }
        .onChange(of: post.id) { _, _ in
            currentPost = HubEngagementStore.shared.applyLikeState(to: post)
            resetRelatedShelf()
        }
        .onChange(of: related.count) { _, _ in
            if relatedWindow.isEmpty { resetRelatedShelf() }
        }
        .onChange(of: inlineComments.count) { _, count in
            guard isHubContent else { return }
            if count != currentPost.commentCount {
                currentPost = currentPost.withEngagement(
                    likedByMe: currentPost.likedByMe,
                    likeCount: currentPost.likeCount,
                    commentCount: count
                )
            }
        }
    }

    private func hydrateEngagement() async {
        // Re-apply local likes first (never wipe optimistic engagement).
        if isHubContent {
            currentPost = HubEngagementStore.shared.applyLikeState(to: currentPost)
        } else if let refreshed = try? await PostsService.shared.getPostByID(currentPost.id) {
            currentPost = refreshed
        }

        // PostsService loads demo Reddit threads + merges local replies (hub / post_* / GraphQL).
        let loaded = (try? await PostsService.shared.listComments(currentPost.id, limit: 50)) ?? []
        inlineComments = loaded
        if isHubContent || loaded.count > currentPost.commentCount {
            currentPost = currentPost.withEngagement(
                likedByMe: currentPost.likedByMe,
                likeCount: currentPost.likeCount,
                commentCount: max(currentPost.commentCount, loaded.count)
            )
        }
    }

    private func descriptionText(for post: CountryPost) -> String {
        let body = post.displayBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { return body }
        return (post.displayCaption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var descriptionSection: some View {
        let text = descriptionText(for: currentPost)
        if text.isEmpty {
            EmptyView()
        } else if isHubContent {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            YouTubeExpandableDescription(text: text)
        }
    }

    private var playerSection: some View {
        ZStack(alignment: .topLeading) {
            // When embedsPlayer is false, GlobalHubPlaybackLayer owns the real video + pull-down.
            // Keep this stage as a static black spacer (no second drag fighting the continuous player).
            playerSurface

            LinearGradient(
                colors: [Theme.ink.opacity(0.4), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 72)
            .allowsHitTesting(false)
            .opacity(embedsPlayer ? chromeOpacity : 1)

            Button(action: { onBack() }) {
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
            .opacity(embedsPlayer ? chromeOpacity : 1)
            .allowsHitTesting(embedsPlayer ? (chromeOpacity > 0.2 && !isPullingToMinimize) : true)

            // Pull-down only when this view embeds its own player (not GlobalHub).
            if embedsPlayer {
                Color.clear
                    .frame(height: 72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .highPriorityGesture(minimizeDragGesture)
                    .opacity(chromeOpacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink)
        .onDisappear {
            dismissDragOffset = 0
            isPullingToMinimize = false
        }
    }

    private var minimizeDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                guard vertical > 6, vertical > horizontal * 0.65 else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dismissDragOffset = max(0, vertical)
                    isPullingToMinimize = true
                }
            }
            .onEnded { value in
                if value.translation.height > 90 || value.predictedEndTranslation.height > 180 {
                    dismissDragOffset = 0
                    isPullingToMinimize = false
                    onBack()
                } else {
                    withAnimation(.easeOut(duration: 0.16)) {
                        dismissDragOffset = 0
                        isPullingToMinimize = false
                    }
                }
            }
    }

    private var playerSurface: some View {
        Group {
            if embedsPlayer, let url = currentPost.playableVideoURL {
                YouTubeVideoFrame(style: .watch) {
                    VideoPlayerView(
                        url: url,
                        posterURL: currentPost.posterImageURL,
                        placement: nil,
                        countryCode: currentPost.countryCode,
                        contentCountryCode: currentPost.countryCode,
                        postID: currentPost.id,
                        adsEnabled: false,
                        isActive: true,
                        loops: false,
                        muted: false,
                        showsControls: true,
                        allowsFullscreen: true,
                        startTime: YouTubeCatalogService.shared.playbackPosition(for: currentPost.id),
                        onViewed: { Task { await PostsService.shared.recordView(currentPost) } }
                    )
                }
            } else if embedsPlayer {
                YouTubeVideoFrame(style: .watch) {
                    YouTubeVideoThumbnail(
                        post: currentPost,
                        maxPixelSize: 900,
                        frameStyle: .watch,
                        embedsFrame: false
                    )
                }
            } else {
                // Parent continuous player draws the video; keep a black stage for layout + gestures.
                YouTubeVideoFrame(style: .watch) {
                    Color.black
                }
            }
        }
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
        HStack(spacing: 20) {
            Button {
                toggleLike()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: currentPost.likedByMe ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundStyle(currentPost.likedByMe ? Theme.like : Theme.ink)
                    if currentPost.likeCount > 0 {
                        Text("\(currentPost.likeCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isLiking)

            Button {
                Task {
                    // Bookmark is local for hub videos; never toast GraphQL failures.
                    _ = await appState.toggleSavePost(currentPost)
                }
            } label: {
                Image(systemName: appState.isPostSaved(currentPost.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                // Leaving the watch surface for a sheet — collapse to mini (stay put).
                appState.minimizeHubPlayback(returnToChat: false)
                appState.presentShareSheet(for: currentPost)
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(max(currentPost.commentCount, inlineComments.count)) Comments")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if max(currentPost.commentCount, inlineComments.count) > 3 {
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
                totalCommentCount: max(currentPost.commentCount, inlineComments.count),
                onViewAllComments: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        commentsExpanded = true
                    }
                },
                onError: { message in
                    // Suppress GraphQL Yoga masked failures on hub seed videos.
                    if message.localizedCaseInsensitiveContains("unexpected") { return }
                    commentError = message
                }
            )
            .padding(.horizontal, Theme.pagePadding)

            if let commentError, !commentError.localizedCaseInsensitiveContains("unexpected") {
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
        if !related.isEmpty || !relatedWindow.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(MatteryaCopy.moreOnHubs)
                    .font(.system(.headline, design: .serif))
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.ink)
                    .matteryaBrandLine()
                    .padding(.horizontal, Theme.pagePadding)

                // Same full-width card + thumbnail chrome as the Hubs home scroll.
                LazyVStack(spacing: 18) {
                    ForEach(relatedWindow) { item in
                        YouTubeVideoListRow(post: item.post) {
                            // Stay on watch — switch video (player stays expanded).
                            onOpenVideo(item.post)
                        }
                        .onAppear {
                            if item.id == relatedWindow.last?.id {
                                appendRelatedPage()
                            }
                            // Prefetch thumbs a few rows ahead (same size as Hubs shelves).
                            warmRelatedAround(item)
                        }
                    }
                }
            }
        }
    }

    private struct RelatedShelfItem: Identifiable {
        let id: String
        let post: CountryPost
    }

    private func resetRelatedShelf() {
        relatedCursor = 0
        relatedWindow = []
        appendRelatedPage(count: 16)
    }

    private func appendRelatedPage(count: Int = 12) {
        guard !related.isEmpty else { return }
        var next: [RelatedShelfItem] = []
        next.reserveCapacity(count)
        for i in 0..<count {
            let index = (relatedCursor + i) % related.count
            let post = related[index]
            let cycle = (relatedCursor + i) / related.count
            // Stable unique row id even when the catalog cycles.
            next.append(RelatedShelfItem(id: "\(post.id)#\(cycle)-\(relatedCursor + i)", post: post))
        }
        relatedCursor += count
        relatedWindow.append(contentsOf: next)
        // Prefetch thumbs for the new page; resolve Archive only for the first couple.
        warmRelatedMedia(prefix: min(4, next.count), from: next, resolveArchive: relatedWindow.count <= 16)
    }

    private func warmRelatedAround(_ item: RelatedShelfItem) {
        guard let idx = relatedWindow.firstIndex(where: { $0.id == item.id }) else { return }
        // Only the immediate next row — bulk warm was flooding the network.
        let end = min(relatedWindow.count, idx + 2)
        guard idx < end else { return }
        warmRelatedMedia(prefix: end - idx, from: Array(relatedWindow[idx..<end]), resolveArchive: idx == 0)
    }

    private func warmRelatedMedia(
        prefix: Int,
        from items: [RelatedShelfItem]? = nil,
        resolveArchive: Bool = false
    ) {
        let slice = items ?? Array(relatedWindow.prefix(prefix))
        let posts = slice.map(\.post)
        // Thumbnails only (cheap). Archive resolve is limited to the next 1–2 clips.
        // Match Hubs home list / MatteryaHubVideoCard warm size.
        ImageCache.shared.prefetchPostThumbnails(posts, maxPixelSize: 420)
        guard resolveArchive else { return }
        for post in posts.prefix(2) {
            if let url = post.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) {
                ArchiveVideoPlayback.warmResolve(url)
            }
        }
    }

    /// Optimistic like — seed/hub IDs always succeed locally (no GraphQL "Unexpected error").
    private func toggleLike() {
        guard !isLiking else { return }
        isLiking = true
        let wasLiked = currentPost.likedByMe
        let previous = currentPost
        let nextLiked = !wasLiked
        let nextCount = nextLiked ? currentPost.likeCount + 1 : max(0, currentPost.likeCount - 1)
        currentPost = currentPost.withEngagement(
            likedByMe: nextLiked,
            likeCount: nextCount,
            commentCount: currentPost.commentCount
        )
        commentError = nil

        Task { @MainActor in
            defer { isLiking = false }
            // likePost/unlikePost never throw for seed/hub; GraphQL failures fall back locally.
            if wasLiked {
                try? await PostsService.shared.unlikePost(previous.id, baseLikeCount: previous.likeCount)
            } else {
                try? await PostsService.shared.likePost(previous.id, baseLikeCount: previous.likeCount)
            }
            // Keep optimistic UI; re-apply store when it has a recorded state.
            let applied = HubEngagementStore.shared.applyLikeState(
                to: previous.withEngagement(
                    likedByMe: nextLiked,
                    likeCount: nextCount,
                    commentCount: previous.commentCount
                )
            )
            currentPost = applied
            PostsService.shared.publishPostChange(currentPost)
            commentError = nil
        }
    }
}

private extension CountryPost {
    func withCommentCount(_ count: Int) -> CountryPost {
        withEngagement(likedByMe: likedByMe, likeCount: likeCount, commentCount: count)
    }
}
