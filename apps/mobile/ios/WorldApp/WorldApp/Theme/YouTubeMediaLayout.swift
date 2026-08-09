import AVFoundation
import SwiftUI
import UIKit

enum YouTubeMediaLayout {
    static let aspect: CGFloat = 16.0 / 9.0

    /// Full phone height (points) — use for stage math so feed/watch/overlay agree.
    static var keyWindowHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let h = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.bounds.height, h > 0 {
            return h
        }
        if let h = scenes.flatMap(\.windows).first?.bounds.height, h > 0 {
            return h
        }
        return UIScreen.main.bounds.height
    }

    /// Status-bar / notch inset from the key window (overlay GeometryReaders often report 0).
    static var keyWindowSafeTop: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets.top, top > 0 {
            return top
        }
        if let top = scenes.flatMap(\.windows).first?.safeAreaInsets.top, top > 0 {
            return top
        }
        // Dynamic Island / notch phones fall in ~47–59; home-button iPhones ~20.
        return 59
    }

    /// Home-indicator inset (0 on home-button phones).
    static var keyWindowSafeBottom: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let bottom = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets.bottom {
            return bottom
        }
        if let bottom = scenes.flatMap(\.windows).first?.safeAreaInsets.bottom {
            return bottom
        }
        return 0
    }

    /// Space reserved under the continuous player for title + channel (always visible).
    static let hubsWatchMetaReserve: CGFloat = 100

    /// Content column height **above** the custom bottom tab bar (tab bar not included).
    static var hubsContentColumnHeight: CGFloat {
        max(320, keyWindowHeight - Theme.tabBarHeight)
    }

    /// Single max-pixel size for Hubs For you / related / shelf thumbs.
    /// Prefetch + display MUST match or ImageCache keys miss and every row re-downloads.
    static let hubsListThumbMaxPixel: CGFloat = 320

    /// Hubs watch stage = compact **16:9** of width (never half-screen / never taller than classic).
    /// Pair with `fillsFrame: true` so the clip fills edge-to-edge with no black letterbox bars.
    static func hubsContinuousStageHeight(containerWidth: CGFloat) -> CGFloat {
        let w = max(1, containerWidth)
        // Strict 16:9 — do not grow above classic (that created black top/bottom slabs).
        let classic16x9 = w / aspect
        let contentH = hubsContentColumnHeight
        let maxH = max(160, min(classic16x9, contentH - hubsWatchMetaReserve))
        return max(160, min(classic16x9, maxH))
    }

    /// Sticky mini height after scrolling comments under the video (YouTube-style).
    static func hubsCollapsedStageHeight(containerWidth: CGFloat) -> CGFloat {
        let full = hubsContinuousStageHeight(containerWidth: containerWidth)
        // ~38% of full 16:9 — still readable, leaves room for comments.
        return max(88, min(full * 0.38, full - 48))
    }

    /// Live stage height for a 0…1 scroll-collapse progress.
    static func hubsStageHeight(containerWidth: CGFloat, collapse: CGFloat) -> CGFloat {
        let full = hubsContinuousStageHeight(containerWidth: containerWidth)
        let mini = hubsCollapsedStageHeight(containerWidth: containerWidth)
        let t = min(1, max(0, collapse))
        return full + (mini - full) * t
    }

    /// Embedded watch player — same compact 16:9 stage as continuous hubs playback.
    static func watchPlayerHeight(containerWidth: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let w = max(1, containerWidth)
        let classic16x9 = w / aspect
        if containerHeight > 200 {
            let maxH = max(160, min(classic16x9, containerHeight - hubsWatchMetaReserve))
            return max(160, min(classic16x9, maxH))
        }
        return hubsContinuousStageHeight(containerWidth: w)
    }
}

/// Scroll offset of Hubs watch meta/comments (drives sticky player collapse).
enum HubWatchScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum MatteryaPlayerFrameStyle {
    /// Rounded card with border — home, library, related.
    case card
    /// Flush to top edge — in-feed long-form video.
    case feed
    /// Watch screen — padded player with soft shadow.
    case watch
}

/// Matterya Hubs video frame — warm paper chrome, never a black letterbox.
struct YouTubeVideoFrame<Content: View>: View {
    var style: MatteryaPlayerFrameStyle = .card
    @ViewBuilder var content: () -> Content

    private var cornerRadius: CGFloat {
        switch style {
        case .card: 14
        case .feed: 0
        case .watch: 0
        }
    }

    var body: some View {
        Group {
            switch style {
            case .watch:
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.ink)
                    .overlay {
                        content().clipShape(Rectangle())
                    }
                    .clipShape(Rectangle())
            case .feed:
                // Facebook-style in-feed height (~55–68% of screen), not short 16:9.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: FacebookMediaLayout.dominantFeedVideoHeight())
                    .background(Theme.ink)
                    .overlay {
                        content().clipShape(Rectangle())
                    }
                    .clipShape(Rectangle())
            case .card:
                // Shelf / search cards stay compact 16:9.
                Color.clear
                    .aspectRatio(YouTubeMediaLayout.aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Theme.canvasDeep)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
                    .overlay {
                        content()
                            .clipShape(
                                RoundedRectangle(cornerRadius: max(0, cornerRadius - 1), style: .continuous)
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .shadow(
            color: style == .watch ? Theme.ink.opacity(0.12) : .clear,
            radius: style == .watch ? 16 : 0,
            y: style == .watch ? 8 : 0
        )
    }
}

struct YouTubeVideoThumbnail: View {
    let post: CountryPost
    var maxPixelSize: CGFloat = 720
    /// Center play chrome — always off for clean previews (feed / hubs / search).
    var showsPlayIcon = false
    var frameStyle: MatteryaPlayerFrameStyle = .card
    /// When false, renders only the thumbnail (for use inside an existing frame).
    var embedsFrame: Bool = true
    /// Feed must never extract video frames on scroll (main-thread hang).
    var extractFrameIfNeeded: Bool = false
    /// Hubs badge: only feed share cards (`PlayFeedLinkCard`) — never hubs shelves / search.
    var showsHubBadge: Bool = false

    private var shouldShowHubBadge: Bool {
        showsHubBadge && PlayPlatformBridge.isHubCatalogContent(post)
    }

    var body: some View {
        Group {
            if embedsFrame {
                YouTubeVideoFrame(style: frameStyle) {
                    thumbnailContent
                }
            } else {
                thumbnailContent
            }
        }
        .overlay(alignment: .bottomLeading) {
            if shouldShowHubBadge {
                HubsOriginBadge(compact: true)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var thumbnailContent: some View {
        // Poster / frame only — no center circle.
        VideoThumbnailView(
            post: post,
            maxPixelSize: maxPixelSize,
            // Fill the 16:9 card — never black margins on sides/top.
            contentMode: .fill,
            showsPlayIcon: false,
            extractFrameIfNeeded: extractFrameIfNeeded,
            placeholder: AnyView(matteryaPlaceholder)
        )
    }

    private var matteryaPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Theme.canvasMuted, Theme.canvasDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: post.hasVideo ? "film" : "photo")
                    .font(.title3)
                    .foregroundStyle(Theme.inkMuted.opacity(0.7))
            }
    }
}

struct YouTubeVideoListRow: View {
    let post: CountryPost
    let onTap: () -> Void
    /// Optional: called when the row appears so parents can prefetch neighbors.
    var onAppearRow: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Hubs list: clean thumbs, no Hubs badge (badge is feed-share only).
                YouTubeVideoThumbnail(
                    post: post,
                    maxPixelSize: YouTubeMediaLayout.hubsListThumbMaxPixel,
                    showsPlayIcon: false,
                    frameStyle: .card,
                    // R2 LongForm → YouTube poster URL; Sparks without poster extract one frame (cached).
                    extractFrameIfNeeded: true,
                    showsHubBadge: false
                )
                YouTubeVideoMetadataRow(post: post)
                    // Small air gap between video frame and title row.
                    .padding(.top, 10)
            }
            // Full-width card with side inset — avoid double padding / horizontal crop.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.pagePadding)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            onAppearRow?()
        }
    }
}

struct YouTubeVideoMetadataRow: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    var showsMenu = false

    /// Channel for Hubs / re-shares — never the person who saved or shared the clip.
    private var creator: (name: String, avatarURL: String?, seed: String, authorID: String, username: String?) {
        PlayPlatformBridge.displayCreator(for: post)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                openAuthorProfile()
            } label: {
                AvatarView(url: creator.avatarURL, seed: creator.seed, size: 40)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                if let headline = post.displayHeadline {
                    Text(headline)
                        .font(.system(.subheadline, design: .serif))
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if showsMenu {
                hubsMenu
            }
        }
    }

    private var hubsMenu: some View {
        Menu {
            Button {
                appState.presentShareSheet(for: post)
            } label: {
                Label("Share", systemImage: "arrowshape.turn.up.right")
            }
            Button {
                Task { _ = await appState.toggleSavePost(post) }
            } label: {
                Label(
                    appState.isPostSaved(post.id) ? "Remove from saved" : "Save video",
                    systemImage: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark"
                )
            }
            Button {
                appState.openPostInFeed(postID: post.id)
            } label: {
                Label("Open in Feed", systemImage: "newspaper")
            }
            Button {
                appState.openPublicProfile(username: post.author?.username, userID: post.authorID)
            } label: {
                Label(MatteryaCopy.viewCreatorHub, systemImage: "globe.americas")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 28, height: 28)
        }
    }

    private var metadataLine: String {
        var parts: [String] = [creator.name]
        if post.viewCount > 0 {
            parts.append("\(post.viewCount.formatted()) views")
        }
        parts.append(RelativeTime.format(post.createdAt))
        return parts.joined(separator: " · ")
    }

    private func openAuthorProfile() {
        let c = creator
        if c.authorID.hasPrefix("hub_") || HubVideoSeedService.isArchiveChannelAuthor(c.authorID) {
            appState.openPlayChannel(authorID: c.authorID, username: c.username)
            return
        }
        appState.openPublicProfile(username: c.username, userID: c.authorID)
    }
}

/// Hub video in Feed / shares: same player as Hubs watch + small Hubs badge (hub content only).
/// Participates in `FeedVideoFocus` — only one feed video plays; needs ≥50% on-screen.
struct PlayFeedLinkCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    /// Opens full Matterya Hubs watch (more related videos, shelves, etc.).
    var onOpen: () -> Void
    var edgeToEdge: Bool = true
    /// Feed shares always show the Hubs logo even when stamp markers were lost.
    var forceHubsBadge: Bool = false
    /// Home feed vs profile — same ≥50% autoplay rules on both.
    var autoplaySurface: FeedAutoplaySurface = .home

    /// Bound to app-wide feed mute — one mute/unmute affects every feed video.
    private var feedMutedBinding: Binding<Bool> {
        Binding(
            get: { appState.feedVideosMuted },
            set: { appState.feedVideosMuted = $0 }
        )
    }

    @State private var isFocusWinner = false
    @State private var playGate = false
    @State private var lastReportedRatio: CGFloat = -1
    @State private var deactivateTask: Task<Void, Never>?

    private var focusID: String { "\(autoplaySurface.rawValue):\(post.id)" }

    private var surfaceLive: Bool {
        autoplaySurface.isLive(appState: appState)
    }

    /// Winner of FeedVideoFocus + allowed surface.
    /// Mini or expanded Hubs continuous player → no feed autoplay.
    private var shouldPlay: Bool {
        isFocusWinner
            && surfaceLive
            && appState.reelsViewerContext == nil
            && appState.hubPlaybackPost == nil
    }

    private var feedPlayerActive: Bool { playGate }

    private var horizontalPadding: CGFloat {
        edgeToEdge ? Theme.feedGutter : Theme.pagePadding
    }

    /// Hub catalog clips + forced share path show the Hubs origin chip.
    private var showsHubsOriginBadge: Bool {
        forceHubsBadge || PlayPlatformBridge.isHubCatalogContent(post)
    }

    var body: some View {
        // Player full-bleed. Hubs badge is top-leading so transport chrome never covers it.
        YouTubeVideoFrame(style: .feed) {
            hubFeedPlayerSurface
        }
        .overlay(alignment: .topLeading) {
            if showsHubsOriginBadge {
                Button(action: onOpen) {
                    HubsOriginBadge()
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.top, 12)
                .zIndex(40)
                .accessibilityLabel(MatteryaCopy.watchOnHubs)
                .accessibilityHint("Opens this video in Matterya Hubs")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: edgeToEdge ? 0 : 12, style: .continuous))
        .overlay {
            if !edgeToEdge {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            }
        }
        .padding(.horizontal, edgeToEdge ? 0 : horizontalPadding)
        .padding(.top, edgeToEdge ? 0 : 8)
        .background(visibilityProbe)
        .onReceive(NotificationCenter.default.publisher(for: .feedVideoFocusDidChange)) { _ in
            refreshFocusWinner()
        }
        .onAppear {
            if !appState.feedVideosMuted {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .moviePlayback, options: [])
                try? session.setActive(true, options: [])
            }
            YouTubeCatalogService.shared.recordWatch(post.id)
            refreshFocusWinner()
            syncPlayGate(immediate: true)
        }
        .onDisappear {
            deactivateTask?.cancel()
            deactivateTask = nil
            FeedVideoFocus.shared.clear(id: focusID)
            isFocusWinner = false
            playGate = false
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, postID in
            // Miniplayer on → hard-stop feed cards immediately.
            syncPlayGate(immediate: postID != nil)
        }
        .onChange(of: appState.hubPlaybackExpanded) { _, _ in
            syncPlayGate(immediate: appState.hubPlaybackPost != nil)
        }
        .onChange(of: appState.selectedTab) { _, _ in
            lastReportedRatio = -1
            syncPlayGate(immediate: true)
        }
        .onChange(of: appState.navigationPath.count) { _, _ in
            lastReportedRatio = -1
            syncPlayGate(immediate: true)
        }
        .onChange(of: appState.reelsViewerContext?.id) { _, ctx in
            syncPlayGate(immediate: ctx != nil)
        }
        .onChange(of: shouldPlay) { _, play in
            syncPlayGate(immediate: play)
        }
    }

    @ViewBuilder
    private var hubFeedPlayerSurface: some View {
        if let url = post.playableVideoURL {
            if ArchiveVideoPlayback.isArchiveURL(url) || post.isHubSeedVideo {
                MatteryaHubPlayerView(
                    url: url,
                    posterURL: post.posterImageURL,
                    isActive: feedPlayerActive,
                    startTime: YouTubeCatalogService.shared.playbackPosition(for: post.id),
                    postID: post.id,
                    showsControls: true,
                    loops: false,
                    fillsFrame: false,
                    isMuted: feedMutedBinding,
                    allowsFullscreen: false,
                    onReady: {
                        Task { await PostsService.shared.recordView(post) }
                    }
                )
                .id("hub-feed-\(post.id)")
            } else {
                VideoPlayerView(
                    url: url,
                    posterURL: post.posterImageURL,
                    placement: nil,
                    countryCode: post.countryCode,
                    contentCountryCode: post.countryCode,
                    postID: post.id,
                    adsEnabled: false,
                    isActive: feedPlayerActive,
                    loops: false,
                    muted: appState.feedVideosMuted,
                    showsControls: true,
                    allowsFullscreen: false,
                    startTime: YouTubeCatalogService.shared.playbackPosition(for: post.id),
                    persistsPositionOnTeardown: true,
                    sharesFeedMute: true,
                    fillsFrame: false,
                    preloadsWhenInactive: true,
                    onViewed: { Task { await PostsService.shared.recordView(post) } }
                )
                .id("hub-feed-\(post.id)")
                .onAppear {
                    if let url = post.playableVideoURL {
                        SparkWarmPool.shared.warmSingle(postID: post.id, url: url)
                    }
                }
            }
        } else {
            YouTubeVideoThumbnail(
                post: post,
                maxPixelSize: 900,
                showsPlayIcon: true,
                frameStyle: .feed,
                embedsFrame: false
            )
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
        }
    }

    private var visibilityProbe: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { reportVisibility(proxy.frame(in: .global)) }
                .onChange(of: frame.minY) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
                .onChange(of: frame.midY) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
                .onChange(of: frame.height) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
                .onChange(of: appState.selectedTab) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
                .onChange(of: appState.navigationPath.count) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
        }
        .allowsHitTesting(false)
    }

    private func reportVisibility(_ frame: CGRect) {
        guard surfaceLive else {
            if lastReportedRatio >= 0 {
                lastReportedRatio = -1
                FeedVideoFocus.shared.clear(id: focusID)
            }
            if isFocusWinner { isFocusWinner = false }
            syncPlayGate(immediate: true)
            return
        }

        let ratio = FeedVideoFocus.visibleRatio(for: frame)
        if abs(ratio - lastReportedRatio) < 0.03, lastReportedRatio >= 0 {
            refreshFocusWinner()
            return
        }
        lastReportedRatio = ratio
        FeedVideoFocus.shared.report(id: focusID, visibleRatio: ratio)
        refreshFocusWinner()
    }

    private func refreshFocusWinner() {
        let win = surfaceLive && FeedVideoFocus.shared.isActive(id: focusID)
        if win != isFocusWinner {
            isFocusWinner = win
        }
        // Win → play now. Lose → soft pause (debounced).
        syncPlayGate(immediate: win)
    }

    private func syncPlayGate(immediate: Bool) {
        if shouldPlay {
            deactivateTask?.cancel()
            deactivateTask = nil
            playGate = true
            return
        }
        let leaveSurface =
            !surfaceLive
            || appState.reelsViewerContext != nil
            || appState.hubPlaybackPost != nil
        if leaveSurface {
            deactivateTask?.cancel()
            deactivateTask = nil
            playGate = false
            return
        }
        // Focus lost — debounce so layout glitches never pause a fully visible card.
        guard playGate else { return }
        _ = immediate
        deactivateTask?.cancel()
        deactivateTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !shouldPlay { playGate = false }
            }
        }
    }
}

/// Compact mark that a clip lives on Matterya Hubs (not used for plain feed videos).
struct HubsOriginBadge: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            MatteryaHubsLogoView(size: compact ? 12 : 16)
            Text("Hubs")
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
                .tracking(0.35)
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.accentBright.opacity(0.92))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MatteryaCopy.matteryaHubs)
    }
}

struct YouTubeFeedVideoCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    var onLikeToggle: (() -> Void)?
    var onOpenVideo: () -> Void
    var onPostDeleted: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            YouTubeVideoFrame(style: .feed) {
                if let url = post.playableVideoURL {
                    InFrameVideoPlayer(
                        url: url,
                        posterURL: post.posterImageURL,
                        countryCode: post.countryCode,
                        contentCountryCode: post.countryCode,
                        postID: post.id,
                        muted: true,
                        fillsFrame: true,
                        onViewed: { Task { await PostsService.shared.recordView(post) } }
                    )
                } else {
                    YouTubeVideoThumbnail(
                        post: post,
                        maxPixelSize: 900,
                        showsPlayIcon: true,
                        frameStyle: .feed,
                        embedsFrame: false
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenVideo() }

            YouTubeVideoMetadataRow(post: post)
                .padding(.horizontal, Theme.pagePadding)

            if !post.displayExcerpt.isEmpty {
                Text(post.displayExcerpt)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(3)
                    .padding(.horizontal, Theme.pagePadding)
            }

            HStack(spacing: 22) {
                Button { onLikeToggle?() } label: {
                    Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundStyle(post.likedByMe ? Theme.like : Theme.ink)
                }
                .buttonStyle(.plain)

                Button(action: onOpenVideo) {
                    Image(systemName: "globe.americas")
                        .font(.system(size: 21))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 4)
        }
        .padding(.bottom, 8)
    }
}

struct YouTubeWatchPlayer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        YouTubeVideoFrame(style: .watch) {
            content()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }
}

/// Fixed-size horizontal shelf card (Continue watching / New on Hubs / Hubs rails).
/// Every card shares the same width, 16:9 thumb, and title block so the row stays aligned.
struct HubsShelfThumbCard: View {
    let post: CountryPost
    var width: CGFloat = 168
    /// When true, show a one-line meta row under the title (channel · views).
    var showsMetadata: Bool = false
    var titleFont: Font = .caption.weight(.semibold)
    var onTap: () -> Void

    private var thumbHeight: CGFloat { (width / YouTubeMediaLayout.aspect).rounded() }
    /// Reserve space for exactly two caption lines so missing/short titles don't shift neighbors.
    private var titleBlockHeight: CGFloat { 34 }
    private var metaBlockHeight: CGFloat { showsMetadata ? 16 : 0 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // `embedsFrame: false` — outer frame owns size; avoid card aspect fighting fixed height.
                YouTubeVideoThumbnail(
                    post: post,
                    maxPixelSize: YouTubeMediaLayout.hubsListThumbMaxPixel,
                    showsPlayIcon: false,
                    frameStyle: .card,
                    embedsFrame: false,
                    extractFrameIfNeeded: true,
                    showsHubBadge: false
                )
                .frame(width: width, height: thumbHeight)
                .clipped()
                .background(Theme.canvasDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
                )

                Text(post.displayHeadline ?? " ")
                    .font(titleFont)
                    .foregroundStyle(post.displayHeadline == nil ? Color.clear : Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: width, height: titleBlockHeight, alignment: .topLeading)
                    .padding(.top, 6)

                if showsMetadata {
                    Text(metadataLine)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                        .frame(width: width, height: metaBlockHeight, alignment: .topLeading)
                        .padding(.top, 2)
                }
            }
            .frame(width: width, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        // Lock total cell height so HStack top-aligns every card identically.
        .frame(
            width: width,
            height: thumbHeight + 6 + titleBlockHeight + (showsMetadata ? 2 + metaBlockHeight : 0),
            alignment: .top
        )
    }

    private var metadataLine: String {
        var parts = [post.authorDisplayName]
        if post.viewCount > 0 { parts.append("\(post.viewCount.formatted()) views") }
        return parts.joined(separator: " · ")
    }
}

/// Vertical Matterya card for related / shelf thumbnails — not a side-by-side YT row.
struct MatteryaHubVideoCard: View {
    let post: CountryPost
    var width: CGFloat = 168
    let onTap: () -> Void

    var body: some View {
        HubsShelfThumbCard(
            post: post,
            width: width,
            showsMetadata: true,
            titleFont: .system(.caption, design: .serif).weight(.medium),
            onTap: onTap
        )
    }
}
/// In-app use of the home-screen app icon (`MatteryaAppIcon` imageset ← AppIcon.png).
struct MatteryaAppIconView: View {
    var size: CGFloat = 40

    var body: some View {
        Image("MatteryaAppIcon")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(Theme.border.opacity(0.35), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
