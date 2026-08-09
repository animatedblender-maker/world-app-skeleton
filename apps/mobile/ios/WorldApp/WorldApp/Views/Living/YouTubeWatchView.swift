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
    /// The moment a minimize grab starts (local or continuous layer), everything else vanishes.
    private var chromeOpacity: Double {
        if isPullingToMinimize || dismissDragOffset > 4 {
            return 0
        }
        // Continuous player pull (GlobalHubPlaybackLayer → AppState).
        if appState.hubPlaybackPullProgress > 0.01 {
            return 0
        }
        return 1
    }

    private var isMinimizingGrab: Bool {
        isPullingToMinimize
            || dismissDragOffset > 4
            || appState.hubPlaybackPullProgress > 0.01
    }

    private var isHubContent: Bool {
        PlayPlatformBridge.isHubCatalogContent(currentPost)
            || HubEngagementStore.isHubContentID(currentPost.id)
    }

    var body: some View {
        GeometryReader { geo in
            // Match continuous player: stage from physical top (under island/notch), no gap.
            let safeTop = geo.safeAreaInsets.top > 1
                ? geo.safeAreaInsets.top
                : YouTubeMediaLayout.keyWindowSafeTop
            let bodyH = embedsPlayer
                ? YouTubeMediaLayout.watchPlayerHeight(
                    containerWidth: geo.size.width,
                    containerHeight: max(200, geo.size.height + safeTop)
                )
                : YouTubeMediaLayout.hubsContinuousStageHeight(containerWidth: geo.size.width)
            // Include safe-top bleed so spacer matches GlobalHubPlaybackLayer (y=0).
            let reservedPlayerHeight = max(120, bodyH + max(0, safeTop))

            VStack(spacing: 0) {
                // Sticky player — edge-to-edge under Dynamic Island / notch.
                // When embedsPlayer is false, keep the stage transparent so minimize
                // never leaves a black rectangle at the top of Hubs.
                playerSection
                    .frame(width: geo.size.width, height: reservedPlayerHeight)
                    .background(embedsPlayer ? Theme.ink : Color.clear)
                    .zIndex(2)

                // Title, channel, actions, comments, related — all scroll under the player
                // so the related shelf gets the full remaining height.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Color.clear
                            .frame(height: 8)
                            .frame(maxWidth: .infinity)

                        titleSection
                        channelSection
                        actionSection

                        descriptionSection
                            .padding(.horizontal, Theme.pagePadding)
                            .id("desc-\(currentPost.id)")

                        Divider().padding(.horizontal, Theme.pagePadding)

                        commentsSection

                        if !related.isEmpty || !relatedWindow.isEmpty {
                            relatedHeader
                            ForEach(relatedWindow) { item in
                                YouTubeVideoListRow(post: item.post) {
                                    onOpenVideo(item.post)
                                }
                                .onAppear {
                                    if item.id == relatedWindow.last?.id {
                                        appendRelatedPage()
                                    }
                                    warmRelatedAround(item)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isMinimizingGrab ? Color.clear : Theme.canvas)
                .opacity(chromeOpacity)
                .allowsHitTesting(!isMinimizingGrab && chromeOpacity > 0.2)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        // During grab: pure video over clear/ink — no paper canvas behind.
        .background(isMinimizingGrab ? Theme.ink : Theme.canvas)
        .animation(nil, value: isMinimizingGrab)
        // Player bleeds under Dynamic Island / notch (same as continuous layer).
        .ignoresSafeArea(edges: .top)
        // Feed / non-expanded share still uses the sheet. Expanded Hubs uses an overlay so
        // GlobalHubPlaybackLayer never pauses or collapses to mini.
        .sharePostSheet(appState: appState)
        .overlay {
            if appState.hubPlaybackExpanded,
               !isMinimizingGrab,
               let sharePost = appState.sharePostSheet {
                HubsShareOverlay(post: sharePost) {
                    appState.sharePostSheet = nil
                    appState.hubPlaybackPlaying = true
                    NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(80)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: appState.sharePostSheet?.id)
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
        // Full R2 threads often exceed 50 — match Sparks sheet (2000).
        let loaded = (try? await PostsService.shared.listComments(currentPost.id, limit: 2000)) ?? []
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

            // Minimize / close — over player, clear of Dynamic Island.
            Button(action: { onBack() }) {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8 + YouTubeMediaLayout.keyWindowSafeTop)
            .padding(.horizontal, 12)
            .opacity(embedsPlayer ? chromeOpacity : 1)
            .allowsHitTesting(embedsPlayer ? (chromeOpacity > 0.2 && !isPullingToMinimize) : true)
            .zIndex(20)

            // Pull-down only when this view embeds its own player (not GlobalHub continuous).
            if embedsPlayer {
                Color.clear
                    .frame(height: 72)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .gesture(minimizeDragGesture)
                    .opacity(chromeOpacity)
                    .allowsHitTesting(chromeOpacity > 0.2 && !isPullingToMinimize)
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
                // Continuous GlobalHubPlaybackLayer draws the video into this hole.
                // Never solid black — that stayed on screen as a “black slab” after minimize.
                YouTubeVideoFrame(style: .watch) {
                    Color.clear
                }
            }
        }
    }

    @ViewBuilder
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let headline = currentPost.displayHeadline {
                Text(headline)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Meta line — views · time (YouTube-style under title).
            HStack(spacing: 6) {
                if currentPost.viewCount > 0 {
                    Text("\(currentPost.viewCount.formatted()) views")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                if currentPost.viewCount > 0, !currentPost.createdAt.isEmpty {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                if !currentPost.createdAt.isEmpty {
                    Text(RelativeTime.format(currentPost.createdAt))
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 6)
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

    /// Matterya action chips (Like · Send · Keep) — pill chips, warm paper chrome.
    private var actionSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                watchActionChip(
                    icon: currentPost.likedByMe ? "heart.fill" : "heart",
                    label: currentPost.likeCount > 0 ? "\(currentPost.likeCount)" : "Like",
                    accent: currentPost.likedByMe,
                    accentColor: Theme.like
                ) {
                    toggleLike()
                }
                .disabled(isLiking)

                watchActionChip(icon: "arrowshape.turn.up.right", label: "Send") {
                    appState.hubPlaybackPlaying = true
                    appState.presentShareSheet(for: currentPost)
                    NotificationCenter.default.post(
                        name: .matteryaResumePlaybackAfterInterrupt,
                        object: nil
                    )
                }

                watchActionChip(
                    icon: appState.isPostSaved(currentPost.id) ? "bookmark.fill" : "bookmark",
                    label: appState.isPostSaved(currentPost.id) ? "Kept" : "Keep",
                    accent: appState.isPostSaved(currentPost.id)
                ) {
                    Task { _ = await appState.toggleSavePost(currentPost) }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
    }

    private func watchActionChip(
        icon: String,
        label: String,
        accent: Bool = false,
        accentColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(
                accent
                    ? (accentColor != nil ? accentColor! : Theme.paper)
                    : Theme.ink
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(
                    accent
                        ? (accentColor != nil ? accentColor!.opacity(0.14) : Theme.ink)
                        : Theme.surface
                )
            )
            .overlay(
                Capsule().stroke(
                    accent
                        ? (accentColor ?? Theme.border).opacity(0.35)
                        : Theme.border.opacity(0.8),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
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

    private var relatedHeader: some View {
        Text(MatteryaCopy.moreOnHubs)
            .font(.system(.headline, design: .serif))
            .fontWeight(.regular)
            .foregroundStyle(Theme.ink)
            .matteryaBrandLine()
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        // Next few posters only — never Archive CDN resolve on scroll (that was the lag).
        let end = min(relatedWindow.count, idx + 5)
        guard idx < end else { return }
        warmRelatedMedia(prefix: end - idx, from: Array(relatedWindow[idx..<end]), resolveArchive: false)
    }

    private func warmRelatedMedia(
        prefix: Int,
        from items: [RelatedShelfItem]? = nil,
        resolveArchive: Bool = false
    ) {
        let slice = items ?? Array(relatedWindow.prefix(prefix))
        let posts = slice.map(\.post)
        // Thumbnails only (cheap JPEG posters). Match list maxPixelSize.
        ImageCache.shared.prefetchPostThumbnails(
            posts,
            maxPixelSize: YouTubeMediaLayout.hubsListThumbMaxPixel,
            aggressive: true
        )
        guard resolveArchive else { return }
        // At most the next play candidate — never a bulk CDN storm under the player.
        for post in posts.prefix(1) {
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
