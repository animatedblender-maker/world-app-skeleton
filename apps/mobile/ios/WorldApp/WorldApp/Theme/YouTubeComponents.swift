import SwiftUI

enum YouTubeTheme {
    static let accent = Theme.accentBright
    static let surface = Theme.surface
    static let divider = Theme.divider
}

struct PlayBrandMark: View {
    var ringSize: CGFloat = 24
    var compact: Bool = false

    private var wordmark: Text {
        Text(AppConfig.appName)
            .font(.system(size: compact ? 16 : 19, weight: .regular, design: .serif))
            .tracking(0.35)
        + Text("\u{00A0}Hubs")
            .font(compact ? .headline.weight(.bold) : .title3.weight(.bold))
    }

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            wordmark
                .foregroundStyle(Theme.ink)
                .matteryaBrandLine(minScale: compact ? 0.82 : 0.88)
            HandDrawnGlobeStoryRing(size: ringSize, highlighted: true)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MatteryaCopy.matteryaHubs)
    }
}

struct YouTubeAppHeader: View {
    @Environment(AppState.self) private var appState

    var onSearch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            MenuToolbarButton()
                .frame(width: 44, alignment: .leading)

            PlayBrandMark(compact: true)
                .frame(maxWidth: .infinity)
                .layoutPriority(-1)

            HStack(spacing: 4) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Button {
                    toggleNotifications()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        if appState.effectiveNotificationsUnreadCount > 0 {
                            Circle()
                                .fill(Theme.danger)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -2)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Button {
                    appState.globePanel = nil
                    appState.selectedTab = .profile
                } label: {
                    AvatarView(
                        url: appState.currentProfile?.avatarURL,
                        seed: appState.currentProfile?.userID ?? "me",
                        size: 30
                    )
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 8)
    }

    private func toggleNotifications() {
        if appState.globePanel == .notifications {
            appState.globePanel = nil
        } else {
            appState.globePanel = .notifications
            Task { await appState.refreshNotifications() }
        }
    }
}

struct YouTubeFilterChips: View {
    @Binding var selected: YouTubeHomeFilter
    var onLibrary: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let onLibrary {
                    Button(action: onLibrary) {
                        Label("Library", systemImage: "books.vertical")
                    }
                    .pillTab(isSelected: false)
                }

                ForEach(YouTubeHomeFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selected = filter
                        }
                    } label: {
                        Text(filter.title)
                    }
                    .pillTab(isSelected: selected == filter)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
        }
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }
}

struct YouTubeSubscribeButton: View {
    @Environment(AppState.self) private var appState

    let authorID: String
    var compact = false

    private var isFollowing: Bool {
        appState.isFollowing(authorID)
    }

    var body: some View {
        Button {
            Task { await appState.toggleFollow(authorID) }
        } label: {
            HStack(spacing: compact ? 4 : 6) {
                if !isFollowing {
                    HandDrawnGlobeStoryRing(size: compact ? 14 : 16, highlighted: true)
                }
                Text(isFollowing ? MatteryaCopy.following : MatteryaCopy.follow)
                    .font(compact ? .caption.weight(.bold) : .subheadline.weight(.semibold))
            }
            .foregroundStyle(isFollowing ? Theme.ink : Theme.surface)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 8 : 10)
            .background(
                Capsule()
                    .fill(isFollowing ? Theme.canvasMuted : Theme.accentBright)
            )
            .overlay {
                if isFollowing {
                    Capsule().stroke(Theme.border, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(authorID == appState.currentProfile?.userID)
    }
}

struct YouTubeChannelRow: View {
    @Environment(AppState.self) private var appState

    let channel: YouTubeChannel
    var subscriberCount: Int?
    var onTapChannel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTapChannel) {
                AvatarView(url: channel.author?.avatarURL, seed: channel.authorID, size: 48)
            }
            .buttonStyle(.plain)

            Button(action: onTapChannel) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.title)
                        .font(.system(.subheadline, design: .serif))
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.ink)
                    Text(followerLine)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            YouTubeSubscribeButton(authorID: channel.authorID, compact: true)
        }
    }

    private var followerLine: String {
        var parts: [String] = []
        if let subscriberCount, subscriberCount > 0 {
            parts.append("\(subscriberCount.formatted()) \(MatteryaCopy.followers)")
        }
        if channel.videoCount > 0 {
            parts.append("\(channel.videoCount) videos")
        }
        return parts.isEmpty ? (channel.handle ?? MatteryaCopy.creator) : parts.joined(separator: " · ")
    }
}

struct YouTubeCompactRelatedRow: View {
    let post: CountryPost
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                YouTubeVideoThumbnail(post: post, maxPixelSize: 520, showsPlayIcon: true, frameStyle: .card)

                VStack(alignment: .leading, spacing: 4) {
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
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var metadataLine: String {
        var parts = [post.authorDisplayName]
        if post.viewCount > 0 { parts.append("\(post.viewCount.formatted()) views") }
        parts.append(RelativeTime.format(post.createdAt))
        return parts.joined(separator: " · ")
    }
}

struct YouTubeExpandableDescription: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(expanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(expanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentBright)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
    }
}

struct PlayReelTile: View {
    let post: CountryPost
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if post.playableVideoURL != nil {
                        VideoThumbnailView(
                            post: post,
                            maxPixelSize: 480,
                            contentMode: .fill,
                            showsPlayIcon: false,
                            placeholder: AnyView(reelPlaceholder)
                        )
                    } else {
                        reelPlaceholder
                    }
                }
                .aspectRatio(9.0 / 16.0, contentMode: .fill)
                .clipped()

                if let code = post.countryCode {
                    Text(CountryFlag.emoji(for: code))
                        .font(.caption)
                        .padding(6)
                        .background(Theme.surface.opacity(0.88), in: Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [.clear, Theme.ink.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 4) {
                    if let headline = post.displayHeadline {
                        Text(headline)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.iconFill)
                            .lineLimit(2)
                    }
                    Text(post.authorDisplayName)
                        .font(.caption2)
                        .foregroundStyle(Theme.iconFill.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var reelPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Theme.canvasMuted, Theme.accentSoft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                HandDrawnGlobeStoryRing(size: 32, highlighted: true)
                    .opacity(0.7)
            }
    }
}

struct YouTubeMiniPlayerBar: View {
    let post: CountryPost
    let onExpand: () -> Void
    let onClose: () -> Void

    @State private var isPlaying = true

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let url = post.playableVideoURL {
                    VideoPlayerView(
                        url: url,
                        posterURL: post.posterImageURL,
                        placement: "living",
                        postID: post.id,
                        adsEnabled: false,
                        isActive: isPlaying,
                        loops: false,
                        muted: true,
                        showsControls: false,
                        startTime: YouTubeCatalogService.shared.playbackPosition(for: post.id),
                        persistsPositionOnTeardown: false
                    )
                } else {
                    YouTubeVideoThumbnail(post: post, maxPixelSize: 120, showsPlayIcon: false, frameStyle: .card)
                }

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .frame(width: 76, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                isPlaying.toggle()
            } label: {
                ZStack {
                    HandDrawnGlobeStoryRing(size: 22, highlighted: true)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button(action: onExpand) {
                VStack(alignment: .leading, spacing: 2) {
                    if let headline = post.displayHeadline {
                        Text(headline)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    Text(post.authorDisplayName)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.ink.opacity(0.12), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .padding(.horizontal, Theme.pagePadding)
    }
}

struct YouTubeChannelCard: View {
    let channel: YouTubeChannel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(url: channel.author?.avatarURL, seed: channel.authorID, size: 64)
                    HandDrawnGlobeStoryRing(size: 18, highlighted: true)
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.title)
                        .font(.system(.headline, design: .serif))
                        .fontWeight(.regular)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text(channel.handle ?? MatteryaCopy.creator)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                    Text("\(channel.videoCount) videos · \(channel.totalViews.formatted()) views")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}