import SwiftUI

/// Tracks meta ScrollView offset so pull-down-to-fullscreen only fires at the top.
private enum HubWatchMetaScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

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
    /// Scroll offset of meta content (0 = at top). Pull-down-to-FS only when near top.
    @State private var metaScrollOffset: CGFloat = 0
    /// Live pull progress for YT-style grab-to-fullscreen on non-video chrome.
    @State private var fullscreenPullProgress: CGFloat = 0

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

    /// 1 = full chrome visible; 0 = only video.
    /// Tracks pull like a slider: finger down → fade out, finger up → fade in (1:1).
    private var chromeOpacity: Double {
        let localPull = MatteryaPullDownDismiss.pullProgress(forOffset: dismissDragOffset)
        let continuousPull = max(0, min(1, appState.hubPlaybackPullProgress))
        let pull = max(localPull, continuousPull)
        // Soft ease near the ends so the last/first 10% feels less abrupt.
        let t = Double(pull)
        let eased = t * t * (3 - 2 * t)
        return 1 - eased
    }

    private var isMinimizingGrab: Bool {
        isPullingToMinimize
            || dismissDragOffset > 2
            || appState.hubPlaybackPullProgress > 0.01
    }

    private static let watchScrollTopID = "hub-watch-meta-top"

    /// Paper under chrome when expanded. Clear as soon as pull starts so home shows through.
    private var watchChromeBackground: Color {
        if isMinimizingGrab || appState.hubPlaybackPullProgress > 0.02 {
            return .clear
        }
        return Theme.canvas
    }

    /// Root backdrop — clear on pull/mini so Hubs home (underlay) is never covered by white/ink.
    /// Never leave a white slab over the video stage while continuous player owns the pixels.
    private var watchRootBackground: Color {
        if !embedsPlayer {
            if !appState.hubPlaybackExpanded { return .clear }
            if isMinimizingGrab || appState.hubPlaybackPullProgress > 0.02 {
                return .clear
            }
            // Stage hole is clear; only meta below needs paper. Use clear root so the
            // continuous layer never sits under a canvas flash during expand/minimize.
            return .clear
        }
        return Theme.canvas
    }

    private func scrollMetaToTop(_ proxy: ScrollViewProxy) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            proxy.scrollTo(Self.watchScrollTopID, anchor: .top)
        }
    }

    private var isHubContent: Bool {
        PlayPlatformBridge.isHubCatalogContent(currentPost)
            || HubEngagementStore.isHubContentID(currentPost.id)
    }

    var body: some View {
        GeometryReader { geo in
            // Pure 16:9 below the safe area — matches continuous player (y = safeTop).
            // Dynamic Island stays above the video, never inside it.
            let reservedPlayerHeight = YouTubeMediaLayout.hubsExpandedStageHeight(
                containerWidth: geo.size.width,
                videoAspect: appState.hubPlaybackVideoAspect
            )

            VStack(spacing: 0) {
                playerSection
                    .frame(width: geo.size.width, height: max(120, reservedPlayerHeight))
                    // Continuous player paints the stage — never canvas/white under the hole.
                    .background(embedsPlayer ? Theme.ink : Theme.ink.opacity(isMinimizingGrab ? 0 : 1))
                    .background {
                        GeometryReader { stageGeo in
                            Color.clear.preference(
                                key: HubWatchStageFrameKey.self,
                                value: stageGeo.frame(in: .global)
                            )
                        }
                    }
                    .clipped()
                    .zIndex(2)

                // Title + Like/Send/Keep OUTSIDE ScrollView — zero scroll-inset gap.
                // YouTube: drag down on non-video chrome → landscape fullscreen (not minimize).
                titleAndActionsChrome
                    .background(watchChromeBackground)
                    .opacity(chromeOpacity)
                    .allowsHitTesting(chromeOpacity > 0.25)
                    .simultaneousGesture(metaFullscreenDragGesture)

                // Scroll from top (channel → comments). Related is below — never land there
                // when opening a new video from "More on Matterya".
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            GeometryReader { g in
                                Color.clear
                                    .preference(
                                        key: HubWatchMetaScrollOffsetKey.self,
                                        value: g.frame(in: .named("hub-watch-meta-scroll")).minY
                                    )
                            }
                            .frame(height: 0)
                            .id(Self.watchScrollTopID)

                            channelSection
                                .padding(.top, 10)

                            descriptionSection
                                .padding(.horizontal, Theme.pagePadding)
                                .padding(.top, 8)
                                .id("desc-\(currentPost.id)")

                            Divider()
                                .padding(.horizontal, Theme.pagePadding)
                                .padding(.top, 8)

                            commentsSection
                                .padding(.top, 4)
                                .id("comments-\(currentPost.id)")

                            if !related.isEmpty || !relatedWindow.isEmpty {
                                relatedHeader
                                LazyVStack(alignment: .leading, spacing: 0) {
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
                        }
                        .padding(.bottom, 28)
                    }
                    .coordinateSpace(name: "hub-watch-meta-scroll")
                    .onPreferenceChange(HubWatchMetaScrollOffsetKey.self) { y in
                        metaScrollOffset = y
                    }
                    .contentMargins(.all, 0, for: .scrollContent)
                    .scrollDismissesKeyboard(.interactively)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(watchChromeBackground.opacity(chromeOpacity))
                    .opacity(chromeOpacity)
                    .allowsHitTesting(chromeOpacity > 0.25)
                    // Pull-down on meta (at scroll top) → fullscreen, never reloads comments.
                    .simultaneousGesture(metaFullscreenDragGesture)
                    .onAppear {
                        scrollMetaToTop(proxy)
                    }
                    .onChange(of: post.id) { _, _ in
                        scrollMetaToTop(proxy)
                    }
                    .onChange(of: currentPost.id) { _, _ in
                        scrollMetaToTop(proxy)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            // Live grab feedback while pulling meta toward fullscreen (YT-style).
            .overlay(alignment: .top) {
                if fullscreenPullProgress > 0.02 {
                    Capsule()
                        .fill(Color.white.opacity(0.35 + Double(fullscreenPullProgress) * 0.4))
                        .frame(width: 36 + fullscreenPullProgress * 28, height: 4)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
            // When continuous player collapses, never leave title/meta over a white hole.
            .opacity(appState.hubPlaybackExpanded || embedsPlayer ? 1 : 0)
            .allowsHitTesting(appState.hubPlaybackExpanded || embedsPlayer)
        }
        // Continuous player: never flash paper-white under a faded watch route.
        // Grab / mini → canvas (matches home paper) not pure white / ink slab.
        .background(watchRootBackground)
        // No implicit chrome animation while grabbing — 1:1 with finger via pull progress.
        .animation(isMinimizingGrab ? nil : MatteryaMotion.micro, value: chromeOpacity)
        .transaction { txn in
            if isMinimizingGrab { txn.disablesAnimations = true }
        }
        // Stay in the safe area — video begins *below* the Dynamic Island.
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
            // Instant warm paint, then progressive comments (never block on 2k rows).
            if let warm = CommentsWarmCache.shared.cached(currentPost.id), !warm.isEmpty {
                inlineComments = warm
            }
            await hydrateEngagement()
            YouTubeCatalogService.shared.recordWatch(currentPost.id)
            resetRelatedShelf()
        }
        .onChange(of: post.id) { _, _ in
            currentPost = HubEngagementStore.shared.applyLikeState(to: post)
            // Drop previous video's thread so we don't flash wrong comments.
            if let warm = CommentsWarmCache.shared.cached(post.id), !warm.isEmpty {
                inlineComments = warm
            } else {
                inlineComments = []
            }
            commentsExpanded = false
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
        let postID = currentPost.id
        // Re-apply local likes first (never wipe optimistic engagement).
        // Skip getPostByID on the hot path — it delayed first comments paint by a full RTT.
        if isHubContent {
            currentPost = HubEngagementStore.shared.applyLikeState(to: currentPost)
        }

        // Progressive comments: first page paints fast; fuller thread tops up in background.
        // Also seeds CommentsWarmCache so PostCommentsView does not re-fetch 2000 rows.
        let loaded = await CommentsWarmCache.shared.loadProgressive(postID)
        guard !Task.isCancelled, currentPost.id == postID else { return }
        if !loaded.isEmpty || inlineComments.isEmpty {
            inlineComments = loaded
        }
        if isHubContent || loaded.count > currentPost.commentCount {
            currentPost = currentPost.withEngagement(
                likedByMe: currentPost.likedByMe,
                likeCount: currentPost.likeCount,
                commentCount: max(currentPost.commentCount, loaded.count)
            )
        }

        // Background top-up → update the live binding (cache alone wouldn't refresh UI).
        Task { @MainActor in
            let more = (try? await PostsService.shared.listComments(
                postID,
                limit: PostsService.commentsBackgroundLimit,
                resolveOrigin: true
            )) ?? []
            guard currentPost.id == postID, more.count > inlineComments.count else { return }
            inlineComments = more
            CommentsWarmCache.shared.store(postID, comments: more)
            currentPost = currentPost.withEngagement(
                likedByMe: currentPost.likedByMe,
                likeCount: currentPost.likeCount,
                commentCount: max(currentPost.commentCount, more.count)
            )
        }

        // Optional light post refresh (likes) after comments are already on screen.
        if !isHubContent {
            Task {
                if let refreshed = try? await PostsService.shared.getPostByID(postID),
                   currentPost.id == postID {
                    currentPost = HubEngagementStore.shared.applyLikeState(to: refreshed)
                }
            }
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
        } else {
            // Same expand control for hub + live — only appears when text is truncated.
            YouTubeExpandableDescription(text: text)
        }
    }

    private var playerSection: some View {
        ZStack(alignment: .topLeading) {
            // Continuous layer paints into this hole when embedsPlayer is false.
            playerSurface

            // No chevron — pull-down on the video minimizes (continuous layer owns the gesture).
            if embedsPlayer {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(minimizeDragGesture)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(embedsPlayer ? Theme.ink : Color.clear)
        .onDisappear {
            dismissDragOffset = 0
            isPullingToMinimize = false
        }
    }

    private var minimizeDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                var offset = dismissDragOffset
                var dragging = isPullingToMinimize
                MatteryaPullDownDismiss.applyChanged(value, offset: &offset, isDragging: &dragging)
                // Use raw translation for 1:1 slider fade (offset may rubber-band).
                let liveOffset = dragging ? max(0, value.translation.height) : 0
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    dismissDragOffset = liveOffset
                    isPullingToMinimize = dragging
                }
            }
            .onEnded { value in
                // Same rule as continuous layer: leave grab mid-pull → mini now.
                if MatteryaPullDownDismiss.shouldMinimizeOnRelease(
                    value,
                    dragOffset: dismissDragOffset,
                    pullProgress: MatteryaPullDownDismiss.pullProgress(forOffset: dismissDragOffset)
                ) {
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

    /// YouTube-style: drag **down** on non-video chrome (title / comments / related)
    /// → landscape fullscreen with live grab feedback. Does not remount comments.
    private var metaFullscreenDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard appState.hubPlaybackPost != nil, appState.hubPlaybackExpanded else { return }
                guard !isMinimizingGrab else { return }
                // Only when meta is scrolled to top (or title chrome — always "top").
                guard metaScrollOffset > -24 else {
                    if fullscreenPullProgress != 0 { fullscreenPullProgress = 0 }
                    return
                }
                let y = value.translation.height
                let x = abs(value.translation.width)
                guard y > 0, y > x * 0.85 else {
                    if fullscreenPullProgress != 0 { fullscreenPullProgress = 0 }
                    return
                }
                // 1:1 grab feel (cap at 1) — drives continuous player morph + pill.
                let p = min(1, max(0, y / 140))
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    fullscreenPullProgress = p
                    appState.setHubFullscreenPullProgress(p)
                }
            }
            .onEnded { value in
                guard appState.hubPlaybackPost != nil, appState.hubPlaybackExpanded else {
                    withAnimation(MatteryaMotion.ytMorph) {
                        fullscreenPullProgress = 0
                        appState.setHubFullscreenPullProgress(0)
                    }
                    return
                }
                guard !isMinimizingGrab else {
                    withAnimation(MatteryaMotion.ytMorph) {
                        fullscreenPullProgress = 0
                        appState.setHubFullscreenPullProgress(0)
                    }
                    return
                }
                guard metaScrollOffset > -24 else {
                    withAnimation(MatteryaMotion.ytMorph) {
                        fullscreenPullProgress = 0
                        appState.setHubFullscreenPullProgress(0)
                    }
                    return
                }
                let y = value.translation.height
                let x = abs(value.translation.width)
                let predicted = value.predictedEndTranslation.height
                guard y > x * 0.85 else {
                    withAnimation(MatteryaMotion.ytMorph) {
                        fullscreenPullProgress = 0
                        appState.setHubFullscreenPullProgress(0)
                    }
                    return
                }
                if y > 52 || predicted > 120 || fullscreenPullProgress > 0.42 {
                    // Commit: continuous layer springs fsProgress → 1. Do NOT zero
                    // hubFullscreenPullProgress here (that fought the morph and felt like a double enter).
                    ReelsTwistHaptics.pullDismiss()
                    withAnimation(MatteryaMotion.micro) {
                        fullscreenPullProgress = 0
                    }
                    appState.requestHubFullscreen()
                } else {
                    // Snap back to stage.
                    withAnimation(MatteryaMotion.ytMorph) {
                        fullscreenPullProgress = 0
                        appState.setHubFullscreenPullProgress(0)
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
                        allowsFullscreen: false,
                        startTime: YouTubeCatalogService.shared.playbackPosition(for: currentPost.id),
                        fillsFrame: false, // fit full frame — never crop Hubs watch
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

    /// Title + meta + Like/Send/Keep — single tight stack (YouTube: title then actions, no air gap).
    @ViewBuilder
    private var titleAndActionsChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let headline = currentPost.displayHeadline {
                Text(headline)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(isMinimizingGrab ? Theme.paper : Theme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 8)
            }
            // Meta — 2pt under title.
            if currentPost.viewCount > 0 || !currentPost.createdAt.isEmpty {
                HStack(spacing: 6) {
                    if currentPost.viewCount > 0 {
                        Text("\(currentPost.viewCount.formatted()) views")
                            .font(.caption2)
                            .foregroundStyle(isMinimizingGrab ? Theme.paper.opacity(0.7) : Theme.inkMuted)
                    }
                    if currentPost.viewCount > 0, !currentPost.createdAt.isEmpty {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(isMinimizingGrab ? Theme.paper.opacity(0.5) : Theme.inkMuted)
                    }
                    if !currentPost.createdAt.isEmpty {
                        Text(RelativeTime.format(currentPost.createdAt))
                            .font(.caption2)
                            .foregroundStyle(isMinimizingGrab ? Theme.paper.opacity(0.7) : Theme.inkMuted)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 2)
            }

            // Like · Send · Keep — immediately under meta (3pt only).
            actionSection
                .padding(.top, 3)
                .padding(.bottom, 6)
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

    /// Matterya action chips — plain HStack, no nested ScrollView (that added a tall gap).
    private var actionSection: some View {
        HStack(spacing: 8) {
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 0)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func watchActionChip(
        icon: String,
        label: String,
        accent: Bool = false,
        accentColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(
                accent
                    ? (accentColor != nil ? accentColor! : Theme.paper)
                    : Theme.ink
            )
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
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
        ScrollBudget.noteCellAppear()
        // Mid-fling: skip prefetch (cells paint from memory). Settled: next 2–3 only.
        guard !ScrollBudget.isFlinging else { return }
        let end = min(relatedWindow.count, idx + 3)
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
            aggressive: false
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
