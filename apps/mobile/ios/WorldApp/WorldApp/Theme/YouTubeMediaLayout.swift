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

    /// Hubs watch stage height for a given **video aspect** (width ÷ height).
    /// Box is sized so aspect-fit shows the full picture without cropping.
    /// - Parameter videoAspect: natural width/height (default 16:9 until the player reports size).
    static func hubsContinuousStageHeight(
        containerWidth: CGFloat,
        videoAspect: CGFloat = aspect
    ) -> CGFloat {
        let w = max(1, containerWidth)
        let ar: CGFloat = {
            guard videoAspect.isFinite, videoAspect > 0.35, videoAspect < 3.2 else { return aspect }
            return videoAspect
        }()
        // Height that shows the full frame at full width (no crop when using aspect-fit).
        let ideal = w / ar
        let contentH = hubsContentColumnHeight
        let maxH = max(160, contentH - hubsWatchMetaReserve)
        // Tall (9:16) clips are capped so title/comments still fit; fit gravity shows the whole frame.
        let minH = max(140, w / 2.4)
        return min(max(ideal, minH), maxH)
    }

    /// Expanded stage — matches continuous player (below Dynamic Island).
    static func hubsExpandedStageHeight(
        containerWidth: CGFloat,
        videoAspect: CGFloat = aspect
    ) -> CGFloat {
        hubsContinuousStageHeight(containerWidth: containerWidth, videoAspect: videoAspect)
    }

    /// Embedded watch player — same stage as continuous hubs playback.
    static func watchPlayerHeight(
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        videoAspect: CGFloat = aspect
    ) -> CGFloat {
        let w = max(1, containerWidth)
        let stage = hubsContinuousStageHeight(containerWidth: w, videoAspect: videoAspect)
        if containerHeight > 200 {
            let maxH = max(160, containerHeight - hubsWatchMetaReserve)
            return min(stage, maxH)
        }
        return stage
    }

    /// Gap between video bottom and title (flush — actions sit tight under title).
    static let hubsTitleGapBelowVideo: CGFloat = 0
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
                    // Clear — ink/black beds show as top/bottom gaps with aspectFit.
                    .background(Color.clear)
                    .overlay {
                        content().clipShape(Rectangle())
                    }
                    .clipShape(Rectangle())
            case .feed:
                // Full-width 16:9 container — film fits (Hubs gravity); timeline overlays bottom of film.
                // No extra black strip under the picture. Like/share/keep sit under this container.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: FacebookMediaLayout.hubFeedVideoHeight())
                    .background(Color.black)
                    .overlay {
                        content()
                    }
                    .clipped()
                    .contentShape(Rectangle())
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
    /// Kept for call-site compatibility — badges on film are off.
    var showsHubBadge: Bool = false

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
        // Soft canvas while posters load — pure black looked like a broken thumb.
        Group {
            if post.hasVideo {
                Theme.canvasDeep
                    .overlay {
                        Image(systemName: "film")
                            .font(.title3)
                            .foregroundStyle(Theme.inkMuted.opacity(0.45))
                    }
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.canvasMuted, Theme.canvasDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(Theme.inkMuted.opacity(0.7))
                    }
            }
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
                    // Mid-clip AV extract only after Frame0/thumb miss (gated, 1 at a time).
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
            // Track fling so parents can skip network/AV work mid-scroll.
            ScrollBudget.noteCellAppear()
            onAppearRow?()
        }
        .task(id: post.id) {
            // Every Browse-all / list row must mint a poster — never stay black.
            let usable = MediaURLResolver.hubsListPosterURL(for: post)
                .map { MediaURLResolver.isUsablePosterURL($0) } ?? false
            if !usable {
                _ = await Frame0PosterResolver.shared.posterURL(postID: post.id)
            }
        }
    }
}

struct YouTubeVideoMetadataRow: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    var showsMenu = false
    @State private var showReportConfirm = false

    private let reportReasons = ["Spam", "Harassment", "Misinformation", "Other"]

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
        .confirmationDialog(
            "Report this video",
            isPresented: $showReportConfirm,
            titleVisibility: .visible
        ) {
            ForEach(reportReasons, id: \.self) { reason in
                Button(reason, role: .destructive) {
                    Task { await reportVideo(reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var hubsMenu: some View {
        Menu {
            Button {
                showReportConfirm = true
            } label: {
                Label("Report video", systemImage: "flag")
            }
            if !post.authorID.isEmpty {
                Button(role: .destructive) {
                    appState.blockUser(
                        post.authorID,
                        username: post.author?.username,
                        displayName: post.author?.displayName
                    )
                } label: {
                    Label("Block creator", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis.vertical")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Video options")
    }

    private func reportVideo(reason: String) async {
        _ = try? await PostsService.shared.reportPost(post.id, reason: reason)
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
/// Participates in `FeedVideoFocus` — only one feed video plays; starts at ≥25% on-screen.
struct PlayFeedLinkCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    /// Opens full Matterya Hubs watch (more related videos, shelves, etc.).
    var onOpen: () -> Void
    var edgeToEdge: Bool = true
    /// Kept for call-site compatibility — Hubs badges on film are off.
    var forceHubsBadge: Bool = false
    /// Home feed vs profile — same ≥25% (quarter) autoplay rules on both.
    var autoplaySurface: FeedAutoplaySurface = .home

    private var horizontalPadding: CGFloat {
        edgeToEdge ? Theme.feedGutter : Theme.pagePadding
    }

    var body: some View {
        // Player full-bleed. Avoid clipping the overlay scrubber on edge-to-edge cards.
        Group {
            if edgeToEdge {
                YouTubeVideoFrame(style: .feed) {
                    hubFeedPlayerSurface
                }
            } else {
                YouTubeVideoFrame(style: .feed) {
                    hubFeedPlayerSurface
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                }
            }
        }
        .padding(.horizontal, edgeToEdge ? 0 : horizontalPadding)
        .padding(.top, edgeToEdge ? 0 : 8)
        .onAppear {
            YouTubeCatalogService.shared.recordWatch(post.id)
        }
    }

    @ViewBuilder
    private var hubFeedPlayerSurface: some View {
        // Prefer origin catalog media (share stamps) so feed plays the real Hubs file, not a dead stamp.
        let presentation = PlayPlatformBridge.hubWatchPresentation(for: post)
        let playPost = presentation.playableVideoURL != nil ? presentation : post
        if let url = playPost.playableVideoURL
            ?? MediaURLResolver.videoURL(for: playPost)
            ?? post.sharedPost.flatMap({ shared in
                shared.asCountryPost.playableVideoURL
                    ?? MediaURLResolver.videoURL(for: shared.asCountryPost)
            }) {
            // Same resolve as Sparks: Frame 0 / thumb_url before YouTube hqdefault fallback.
            let poster = MediaURLResolver.posterURL(for: playPost)
                ?? MediaURLResolver.posterURL(for: post)
                ?? playPost.posterImageURL
                ?? post.posterImageURL
            // Feed: only Archive CDN needs the UIKit archive path. R2 long-form uses the
            // light VideoPlayerView path — mounting MatteryaHubPlayer on every hub share
            // froze the feed (AV + warm storms).
            let useArchivePath = ArchiveVideoPlayback.isArchiveURL(url)
            ZStack {
                Color.black
                if let poster {
                    CachedAsyncImage(
                        url: poster,
                        maxPixelSize: 720,
                        contentMode: .fit,
                        placeholder: AnyView(Color.black)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                } else {
                    FrameZeroFallbackPoster(
                        postID: playPost.id,
                        videoURL: url,
                        fillsFrame: false,
                        allowClientExtract: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }

                InFrameVideoPlayer(
                    url: url,
                    posterURL: poster,
                    placement: nil,
                    countryCode: playPost.countryCode ?? post.countryCode,
                    contentCountryCode: playPost.countryCode ?? post.countryCode,
                    postID: playPost.id,
                    muted: appState.feedVideosMuted,
                    loops: true,
                    preferArchivePlayer: useArchivePath,
                    showsControls: true,
                    muteOnlyControls: false,
                    // Hubs player uses fit (resizeAspect). Timeline overlays the film — no black margin strip.
                    fillsFrame: false,
                    topChromeReserve: 0,
                    bottomChromeReserve: 0,
                    sharesFeedMute: true,
                    autoplaySurface: autoplaySurface,
                    tapToRevealControls: true,
                    allowsFullscreen: true,
                    onFullscreenRequest: {
                        appState.startHubPlayback(post, expanded: true)
                        appState.requestHubFullscreen()
                    },
                    onViewed: { Task { await PostsService.shared.recordView(post) } }
                )
            }
            .id("hub-feed-\(playPost.id)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            // Open Hubs via badge; taps on film toggle chrome inside the player.
        } else {
            YouTubeVideoThumbnail(
                post: post,
                maxPixelSize: 480,
                showsPlayIcon: true,
                frameStyle: .feed,
                embedsFrame: false
            )
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
        }
    }
}

/// Former Hubs origin chip on video — removed (product: no Hubs/Sparks badges on film).
struct HubsOriginBadge: View {
    var compact: Bool = false
    var body: some View { EmptyView() }
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
                    let poster = MediaURLResolver.posterURL(for: post) ?? post.posterImageURL
                    // Same fit gravity as Hubs watch (not fill/zoom).
                    ZStack {
                        Color.black
                        if let poster {
                            CachedAsyncImage(
                                url: poster,
                                maxPixelSize: 720,
                                contentMode: .fit,
                                placeholder: AnyView(Color.black)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .allowsHitTesting(false)
                        }
                        InFrameVideoPlayer(
                            url: url,
                            posterURL: poster,
                            countryCode: post.countryCode,
                            contentCountryCode: post.countryCode,
                            postID: post.id,
                            muted: true,
                            fillsFrame: false,
                            bottomChromeReserve: 0,
                            allowsFullscreen: true,
                            onFullscreenRequest: {
                                appState.startHubPlayback(post, expanded: true)
                                appState.requestHubFullscreen()
                            },
                            onViewed: { Task { await PostsService.shared.recordView(post) } }
                        )
                    }
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
    /// Last-resort mid-clip frame when Frame0/thumb missing — VideoFrameCache caps concurrency.
    var extractFrameIfNeeded: Bool = true
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
                    extractFrameIfNeeded: extractFrameIfNeeded,
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
                .task(id: post.id) {
                    // Strip tiles must never stay black — mint Frame 0 if thumb is missing/expired.
                    let usable = MediaURLResolver.hubsListPosterURL(for: post)
                        .map { MediaURLResolver.isUsablePosterURL($0) } ?? false
                    if !usable {
                        _ = await Frame0PosterResolver.shared.posterURL(postID: post.id)
                    }
                }

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
