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

    /// Screen height for sizing (key window when available).
    private static var screenHeight: CGFloat {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            let height = scene.screen.bounds.height
            if height > 1 { return height }
        }
        return UIScreen.main.bounds.height
    }

    /// Mini bar = **¼ of the screen** (clamped for short / tall phones).
    static var barHeight: CGFloat {
        let quarter = screenHeight * 0.25
        return min(max(quarter, 160), min(screenHeight * 0.28, 230))
    }

    static var layoutScale: CGFloat {
        min(2.0, max(1.35, barHeight / 100))
    }

    /// Full-bleed video slot = entire mini card (continuous player docks here).
    static var videoHeight: CGFloat { barHeight }
    static var videoWidth: CGFloat {
        // Prefer full width of a typical phone; callers use `videoSize(forBarWidth:)`.
        UIScreen.main.bounds.width
    }
    static var contentBottomInset: CGFloat {
        barHeight + Theme.tabBarHeight
    }
    /// Full-bleed — video paints edge-to-edge of the mini card.
    static var barContentLeading: CGFloat { 0 }
    static var barContentTrailing: CGFloat { 0 }
    static var videoEdgeInset: CGFloat { 0 }
    static let videoBottomInset: CGFloat = 0

    static var controlButtonSize: CGFloat {
        min(44, max(32, 22 * layoutScale))
    }

    static var playButtonSize: CGFloat {
        min(52, max(40, 28 * layoutScale))
    }

    /// Video fills the **whole** mini card (width × barHeight).
    static func videoSize(forBarWidth totalWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        (max(1, totalWidth), barHeight)
    }

    var body: some View {
        GeometryReader { geo in
            let playSize = Self.playButtonSize
            let btn = Self.controlButtonSize
            let pad: CGFloat = 10

            ZStack {
                // Full-bleed video under chrome.
                Theme.ink

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
                            persistsPositionOnTeardown: true,
                            // Fill the mini card completely (crop if needed).
                            fillsFrame: true
                        )
                    } else {
                        YouTubeVideoThumbnail(
                            post: post,
                            maxPixelSize: 720,
                            showsPlayIcon: false,
                            frameStyle: .card
                        )
                    }
                } else {
                    // Hole for GlobalHubPlaybackLayer — entire card is the video surface.
                    Color.clear
                        .overlay(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: HubContinuousVideoSlotKey.self,
                                    value: g.frame(in: .global)
                                )
                            }
                        )
                }

                // Soft scrims so controls stay readable on bright frames.
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.45), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 48)
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 56)
                }
                .allowsHitTesting(false)

                // Chrome over video — X top-right (never bottom), play + mute bottom-right.
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        Spacer(minLength: 0)
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: btn * 0.36, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: btn, height: btn)
                                .background(.black.opacity(0.45), in: Circle())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close mini player")
                    }
                    .padding(.top, pad)
                    .padding(.trailing, pad)

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        Spacer(minLength: 0)

                        Button {
                            isMuted.toggle()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: btn * 0.38, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: btn, height: btn)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isMuted ? "Unmute" : "Mute")

                        Button {
                            isPlaying.toggle()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Theme.accentBright)
                                    .frame(width: playSize, height: playSize)
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: playSize * 0.34, weight: .bold))
                                    .foregroundStyle(Theme.paper)
                                    .offset(x: isPlaying ? 0 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPlaying ? "Pause" : "Play")
                    }
                    .padding(.trailing, pad)
                    .padding(.bottom, pad)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
            .accessibilityLabel("Expand video")
            .accessibilityAddTraits(.isButton)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
        .background(Theme.ink)
        .shadow(color: Theme.ink.opacity(0.32), radius: 12, y: -3)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
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