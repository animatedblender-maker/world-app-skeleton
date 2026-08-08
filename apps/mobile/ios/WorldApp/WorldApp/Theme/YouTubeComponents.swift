import AVFoundation
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
            // Hand-drawn TV with Matterya logo on the screen.
            MatteryaHubsLogoView(size: ringSize + (compact ? 4 : 6))
            wordmark
                .foregroundStyle(Theme.ink)
                .matteryaBrandLine(minScale: compact ? 0.82 : 0.88)
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
                    MatteryaHubsLogoView(size: compact ? 16 : 18)
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
        let count = appState.resolvedFollowerCount(for: channel.authorID, base: subscriberCount)
        parts.append("\(count.formatted()) \(MatteryaCopy.followers)")
        if channel.videoCount > 0 {
            parts.append("\(channel.videoCount) videos")
        }
        return parts.joined(separator: " · ")
    }
}

struct YouTubeCompactRelatedRow: View {
    let post: CountryPost
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                YouTubeVideoThumbnail(post: post, maxPixelSize: 520, showsPlayIcon: false, frameStyle: .card)

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
                .padding(.top, 10)
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

/// Shared Sparks chrome — thumbnail + country name + author. Sized by the parent.
private struct SparksTileChrome: View {
    let post: CountryPost
    var playIconSize: CGFloat = 28
    var maxPixelSize: CGFloat = 420

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VideoThumbnailView(
                post: post,
                maxPixelSize: maxPixelSize,
                contentMode: .fill,
                showsPlayIcon: false,
                playIconSize: playIconSize,
                extractFrameIfNeeded: true,
                placeholder: AnyView(
                    LinearGradient(
                        colors: [Theme.canvasMuted, Theme.canvasDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Country name only (shared-from) — no flag emoji.
            if let countryLabel {
                Text(countryLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            Text(post.authorDisplayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .padding(8)
        }
    }

    private var countryLabel: String? {
        if let name = post.countryName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let code = post.countryCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            return code.uppercased()
        }
        return nil
    }
}

/// Shared Sparks tile — fixed size for horizontal strips (Feed / Hubs home).
struct SparksStripTile: View {
    let post: CountryPost
    var width: CGFloat = 108
    var height: CGFloat = 192
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            SparksTileChrome(post: post, playIconSize: 28, maxPixelSize: 420)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border.opacity(0.45), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height)
        // Hard lock so strip cells never reflow when thumbnails load.
        .fixedSize()
    }
}

/// Uniform 9:16 grid cell for Library / channel Sparks — equal width, equal height, never jumps.
struct SparksGridTile: View {
    let post: CountryPost
    let onTap: () -> Void

    /// Portrait shorts ratio (width / height).
    private static let aspect: CGFloat = 9.0 / 16.0

    var body: some View {
        Button(action: onTap) {
            // Color.clear proposes a stable 9:16 frame from column width.
            // Thumbnail is overlaid + clipped so image load never changes cell size.
            Color.clear
                .aspectRatio(Self.aspect, contentMode: .fit)
                .overlay {
                    SparksTileChrome(post: post, playIconSize: 26, maxPixelSize: 480)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        // Cell fills column width; height follows 9:16 so every tile matches.
        .frame(maxWidth: .infinity)
        .aspectRatio(Self.aspect, contentMode: .fit)
    }
}

/// Horizontal Sparks rail — identical chrome on Feed and Hubs.
struct SparksHorizontalStrip: View {
    let posts: [CountryPost]
    var title: String = MatteryaCopy.sparksForYou
    var subtitle: String = "Swipe the world on Matterya"
    var showsBrandMark: Bool = true
    var onOpen: (CountryPost) -> Void
    var onBrandTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                if showsBrandMark, let onBrandTap {
                    Button(action: onBrandTap) {
                        PlayBrandMark(compact: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(posts) { post in
                        SparksStripTile(post: post) {
                            onOpen(post)
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }
}

struct PlayReelTile: View {
    let post: CountryPost
    let onTap: () -> Void

    var body: some View {
        // Full-width column cell with locked 9:16 — no fixed 108×192 stretch.
        SparksGridTile(post: post, onTap: onTap)
    }
}

struct YouTubeMiniPlayerBar: View {
    let post: CountryPost
    let onExpand: () -> Void
    let onClose: () -> Void
    /// When false, parent draws a continuous player over this clear video slot (no restart).
    var embedsVideo: Bool = true
    @Binding var isPlaying: Bool
    @Binding var isMuted: Bool

    /// Default video size (16:9). Prefer `videoSize(forBarWidth:)` so title + X never clip.
    static let videoWidth: CGFloat = 168
    static let videoHeight: CGFloat = 94
    /// Minimum width reserved for title + play/mute + close on the right.
    static let metaMinWidth: CGFloat = 148
    /// Vertical padding inside the mini bar chrome (top + bottom).
    static let barVerticalPadding: CGFloat = 18
    /// Intrinsic height of the floating mini bar only (not including tab bar).
    static var barHeight: CGFloat { videoHeight + barVerticalPadding }
    /// Space content lists should leave so the bar doesn’t cover the last row.
    /// Flush on the tab bar — no extra gap.
    static var contentBottomInset: CGFloat {
        barHeight + Theme.tabBarHeight
    }
    /// Horizontal inset of the bar content (used to align continuous player over the slot).
    /// Matches the mini bar’s inner horizontal padding (full-bleed bar, no outer page inset).
    static let barContentLeading: CGFloat = 12
    static let barContentTrailing: CGFloat = 16
    /// Bottom inset for the video hole inside the mini bar chrome (inner padding only).
    static let videoBottomInset: CGFloat = 8

    /// Fit video so the meta column (title + X) always has room — never overflow the screen.
    static func videoSize(forBarWidth totalWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let hPad = barContentLeading + barContentTrailing
        let gap: CGFloat = 12
        let available = max(120, totalWidth - hPad - gap - metaMinWidth)
        // Cap video so it stays a mini preview, not a second stage.
        let w = min(videoWidth, max(120, available))
        let h = w * 9 / 16
        return (w, h)
    }

    var body: some View {
        GeometryReader { geo in
            let size = Self.videoSize(forBarWidth: geo.size.width)
            HStack(alignment: .center, spacing: 12) {
                // Video slot — tap expands (continuous player drawn on top when embedsVideo is false).
                ZStack {
                    if embedsVideo {
                        if let url = post.playableVideoURL {
                            VideoPlayerView(
                                url: url,
                                posterURL: post.posterImageURL,
                                placement: nil,
                                postID: post.id,
                                adsEnabled: false,
                                isActive: isPlaying,
                                loops: false,
                                muted: isMuted,
                                showsControls: false,
                                startTime: YouTubeCatalogService.shared.playbackPosition(for: post.id),
                                persistsPositionOnTeardown: true
                            )
                        } else {
                            YouTubeVideoThumbnail(post: post, maxPixelSize: 420, showsPlayIcon: false, frameStyle: .card)
                        }
                    } else {
                        // Hole for GlobalHubPlaybackLayer continuous player (drawn above this chrome).
                        Theme.ink
                            .overlay(
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: HubContinuousVideoSlotKey.self,
                                        value: g.frame(in: .global)
                                    )
                                }
                            )
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(5)
                                .background(.black.opacity(0.42), in: Circle())
                                .padding(6)
                        }
                    }
                    .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background(Theme.ink)
                .shadow(color: Theme.ink.opacity(embedsVideo ? 0.16 : 0), radius: 8, y: 3)
                .contentShape(Rectangle())
                .onTapGesture(perform: onExpand)
                .accessibilityLabel("Expand video")
                .accessibilityAddTraits(.isButton)
                .layoutPriority(0)

                // Title + controls — must not be crushed by a wide video.
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let headline = post.displayHeadline {
                            Text(headline)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(post.authorDisplayName)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onExpand)

                    HStack(spacing: 8) {
                        Button {
                            isPlaying.toggle()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Theme.accentBright)
                                    .frame(width: 34, height: 34)
                                    .shadow(color: Theme.ink.opacity(0.18), radius: 4, y: 2)
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.paper)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPlaying ? "Pause" : "Play")

                        Button {
                            isMuted.toggle()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 34, height: 34)
                                .background(Theme.canvasMuted, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isMuted ? "Unmute" : "Mute")

                        Spacer(minLength: 2)

                        // Close — always fully on-screen (extra trailing inset).
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 34, height: 34)
                                .background(Theme.canvasMuted, in: Circle())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close mini player")
                    }
                }
                .frame(minWidth: Self.metaMinWidth, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(.leading, Self.barContentLeading)
            .padding(.trailing, Self.barContentTrailing)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 14,
                style: .continuous
            )
            .fill(Theme.surface)
            .shadow(color: Theme.ink.opacity(0.10), radius: 8, y: -3)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
        }
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 14,
                style: .continuous
            )
            .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
            .allowsHitTesting(false)
        )
        .clipped()
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
                    MatteryaAppIconView(size: 18)
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