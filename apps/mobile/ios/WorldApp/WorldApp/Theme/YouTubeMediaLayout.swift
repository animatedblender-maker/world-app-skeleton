import AVFoundation
import SwiftUI

enum YouTubeMediaLayout {
    static let aspect: CGFloat = 16.0 / 9.0

    /// Full-bleed watch stage height (about 42–56% of the screen).
    static func watchPlayerHeight(containerWidth: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let classic = containerWidth / aspect
        let preferred = max(classic, containerHeight * 0.42)
        return min(preferred, containerHeight * 0.56)
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
                Color.clear
                    .aspectRatio(YouTubeMediaLayout.aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Theme.canvasDeep)
                    .overlay {
                        content().clipShape(Rectangle())
                    }
                    .clipShape(Rectangle())
            case .card:
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

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Hubs list: clean thumbs, no Hubs badge (badge is feed-share only).
                YouTubeVideoThumbnail(
                    post: post,
                    showsPlayIcon: false,
                    frameStyle: .card,
                    showsHubBadge: false
                )
                YouTubeVideoMetadataRow(post: post)
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .buttonStyle(.plain)
    }
}

struct YouTubeVideoMetadataRow: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    var showsMenu = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                openAuthorProfile()
            } label: {
                AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 40)
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
        var parts: [String] = [post.authorDisplayName]
        if post.viewCount > 0 {
            parts.append("\(post.viewCount.formatted()) views")
        }
        parts.append(RelativeTime.format(post.createdAt))
        return parts.joined(separator: " · ")
    }

    private func openAuthorProfile() {
        appState.openPublicProfile(username: post.author?.username, userID: post.authorID)
    }
}

/// Hub video in Feed / shares: same player as Hubs watch + small Hubs badge (hub content only).
struct PlayFeedLinkCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    /// Opens full Matterya Hubs watch (more related videos, shelves, etc.).
    var onOpen: () -> Void
    var edgeToEdge: Bool = true

    /// Feed hub clips play with audio; user can mute from the overlay.
    @State private var isMuted = false
    @State private var isPlaying = true

    /// Never fight the global hubs continuous player (double audio).
    private var feedPlayerActive: Bool {
        isPlaying
            && appState.hubPlaybackPost == nil
            && appState.selectedTab == .feed
    }

    private var horizontalPadding: CGFloat {
        edgeToEdge ? Theme.feedGutter : Theme.pagePadding
    }

    var body: some View {
        // Player full-bleed; Hubs badge sits above scrubber chrome so it stays visible.
        YouTubeVideoFrame(style: .feed) {
            hubFeedPlayerSurface
        }
        .overlay(alignment: .bottomLeading) {
            Button(action: onOpen) {
                HubsOriginBadge()
            }
            .buttonStyle(.plain)
            // Lift above bottom transport (play / scrub) ~40pt.
            .padding(.leading, 12)
            .padding(.bottom, 46)
            .accessibilityLabel(MatteryaCopy.watchOnHubs)
            .accessibilityHint("Opens this video in Matterya Hubs")
        }
        .clipShape(RoundedRectangle(cornerRadius: edgeToEdge ? 0 : 12, style: .continuous))
        .overlay {
            if !edgeToEdge {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .padding(.horizontal, edgeToEdge ? 0 : horizontalPadding)
        .padding(.top, edgeToEdge ? 0 : 8)
        .onAppear {
            // Feed hub videos should be audible (user asked) — activate playback session.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback, options: [])
            try? session.setActive(true, options: [])
            isMuted = false
            isPlaying = appState.hubPlaybackPost == nil
            YouTubeCatalogService.shared.recordWatch(post.id)
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, id in
            if id != nil {
                isPlaying = false
            }
        }
        .onChange(of: appState.selectedTab) { _, tab in
            if tab != .feed {
                isPlaying = false
            }
        }
    }

    @ViewBuilder
    private var hubFeedPlayerSurface: some View {
        if let url = post.playableVideoURL {
            if ArchiveVideoPlayback.isArchiveURL(url) || post.isHubSeedVideo {
                // Same hub player as watch: scrubber + play/pause + mute.
                MatteryaHubPlayerView(
                    url: url,
                    posterURL: post.posterImageURL,
                    isActive: feedPlayerActive,
                    startTime: YouTubeCatalogService.shared.playbackPosition(for: post.id),
                    postID: post.id,
                    showsControls: true,
                    loops: false,
                    isMuted: $isMuted,
                    allowsFullscreen: false,
                    onReady: {
                        Task { await PostsService.shared.recordView(post) }
                    }
                )
                .id("hub-feed-\(post.id)")
            } else {
                // Same control surface as Hubs watch for non-archive long-form.
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
                    muted: isMuted,
                    showsControls: true,
                    allowsFullscreen: false,
                    startTime: YouTubeCatalogService.shared.playbackPosition(for: post.id),
                    persistsPositionOnTeardown: true,
                    onViewed: { Task { await PostsService.shared.recordView(post) } }
                )
                .id("hub-feed-\(post.id)")
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

/// Vertical Matterya card for related / shelf thumbnails — not a side-by-side YT row.
struct MatteryaHubVideoCard: View {
    let post: CountryPost
    var width: CGFloat = 168
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                YouTubeVideoThumbnail(
                    post: post,
                    maxPixelSize: 360,
                    showsPlayIcon: false,
                    frameStyle: .card,
                    showsHubBadge: false
                )
                .frame(width: width, height: width / YouTubeMediaLayout.aspect)

                if let headline = post.displayHeadline {
                    Text(headline)
                        .font(.system(.caption, design: .serif))
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: width, alignment: .leading)
                }

                Text(metadataLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var metadataLine: String {
        var parts = [post.authorDisplayName]
        if post.viewCount > 0 { parts.append("\(post.viewCount.formatted()) views") }
        return parts.joined(separator: " · ")
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
