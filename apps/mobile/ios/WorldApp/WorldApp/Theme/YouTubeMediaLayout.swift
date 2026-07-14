import SwiftUI

enum YouTubeMediaLayout {
    static let aspect: CGFloat = 16.0 / 9.0
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
        case .watch: 16
        }
    }

    var body: some View {
        Color.clear
            .aspectRatio(YouTubeMediaLayout.aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(frameBackground)
            .overlay(frameBorder)
            .overlay {
                content()
                    .clipShape(innerClip)
            }
            .clipShape(outerClip)
            .shadow(
                color: style == .watch ? Theme.ink.opacity(0.08) : .clear,
                radius: style == .watch ? 12 : 0,
                y: style == .watch ? 6 : 0
            )
    }

    @ViewBuilder
    private var frameBackground: some View {
        switch style {
        case .feed:
            Theme.canvasDeep
        case .card, .watch:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.canvasDeep)
        }
    }

    @ViewBuilder
    private var frameBorder: some View {
        switch style {
        case .feed:
            EmptyView()
        case .card, .watch:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        }
    }

    private var innerClip: AnyShape {
        switch style {
        case .feed:
            AnyShape(Rectangle())
        case .card, .watch:
            AnyShape(RoundedRectangle(cornerRadius: max(0, cornerRadius - 1), style: .continuous))
        }
    }

    private var outerClip: AnyShape {
        switch style {
        case .feed:
            AnyShape(Rectangle())
        case .card, .watch:
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathBuilder = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

struct YouTubeVideoThumbnail: View {
    let post: CountryPost
    var maxPixelSize: CGFloat = 720
    var showsPlayIcon = true
    var frameStyle: MatteryaPlayerFrameStyle = .card
    /// When false, renders only the thumbnail (for use inside an existing frame).
    var embedsFrame: Bool = true

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
        ZStack {
            VideoThumbnailView(
                post: post,
                maxPixelSize: maxPixelSize,
                contentMode: .fill,
                showsPlayIcon: false,
                placeholder: AnyView(matteryaPlaceholder)
            )

            if showsPlayIcon, post.hasVideo {
                matteryaPlayChrome
            }
        }
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
                HandDrawnGlobeStoryRing(size: 44, highlighted: false)
                    .opacity(0.55)
            }
    }

    private var matteryaPlayChrome: some View {
        ZStack {
            Circle()
                .fill(Theme.surface.opacity(0.92))
                .frame(width: 58, height: 58)
                .shadow(color: Theme.ink.opacity(0.12), radius: 8, y: 3)
            HandDrawnGlobeStoryRing(size: 40, highlighted: true)
        }
        .allowsHitTesting(false)
    }
}

struct YouTubeVideoListRow: View {
    let post: CountryPost
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                YouTubeVideoThumbnail(post: post, frameStyle: .card)
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

/// Compact Play link preview for the Feed — social awareness without inline video.
struct PlayFeedLinkCard: View {
    let post: CountryPost
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.accentSoft)
                        .frame(width: 52, height: 52)
                    HandDrawnGlobeStoryRing(size: 34, highlighted: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let headline = post.displayHeadline {
                        Text(headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Text(metadataLine)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(MatteryaCopy.watchOnHubs)
                            .font(.caption.weight(.bold))
                            .matteryaBrandLine(minScale: 0.8)
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Theme.accentBright)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.canvasMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
    }

    private var metadataLine: String {
        var parts = [MatteryaCopy.matteryaHubs]
        if post.viewCount > 0 {
            parts.append("\(post.viewCount.formatted()) views")
        }
        parts.append(RelativeTime.format(post.createdAt))
        return parts.joined(separator: " · ")
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
                YouTubeVideoThumbnail(post: post, maxPixelSize: 360, showsPlayIcon: true, frameStyle: .card)
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