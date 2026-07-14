import SwiftUI

enum YouTubeChannelTab: String, CaseIterable, Identifiable {
    case videos, reels, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .videos: "Videos"
        case .reels: MatteryaCopy.sparks
        case .about: "About"
        }
    }
}

struct YouTubeChannelView: View {
    @Environment(AppState.self) private var appState

    let channel: YouTubeChannel
    var subscriberCount: Int?
    var onBack: () -> Void
    var onOpenVideo: (CountryPost) -> Void

    @State private var selectedTab: YouTubeChannelTab = .videos

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner
                header
                tabPicker
                tabContent
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface.opacity(0.94), in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                    .shadow(color: Theme.ink.opacity(0.08), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 12)
        }
    }

    private var banner: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Theme.accentSoft, Theme.canvasMuted, Theme.paper],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 108)

            HandDrawnGlobeStoryRing(size: 72, highlighted: true)
                .opacity(0.22)
                .padding(.trailing, Theme.pagePadding)
                .padding(.bottom, 8)

            if let latest = channel.latestVideo {
                YouTubeVideoThumbnail(post: latest, maxPixelSize: 360, showsPlayIcon: false, frameStyle: .card)
                    .opacity(0.12)
                    .frame(width: 200)
                    .padding(.leading, Theme.pagePadding)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 14) {
                AvatarView(url: channel.author?.avatarURL, seed: channel.authorID, size: 84)
                    .overlay {
                        Circle().stroke(Theme.surface, lineWidth: 4)
                    }
                    .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 3)
                    .offset(y: -32)

                Spacer()

                YouTubeSubscribeButton(authorID: channel.authorID)
            }
            .padding(.top, -32)

            VStack(alignment: .leading, spacing: 6) {
                Text(channel.title)
                    .font(.system(.title2, design: .serif))
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.ink)
                if let handle = channel.handle {
                    Text(handle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }
                Text(statsLine)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 12)
    }

    private var statsLine: String {
        var parts: [String] = []
        if let subscriberCount, subscriberCount > 0 {
            parts.append("\(subscriberCount.formatted()) \(MatteryaCopy.followers)")
        }
        parts.append("\(channel.videoCount) videos")
        if channel.totalViews > 0 {
            parts.append("\(channel.totalViews.formatted()) views")
        }
        return parts.joined(separator: " · ")
    }

    private var availableTabs: [YouTubeChannelTab] {
        YouTubeChannelTab.allCases.filter { tab in
            tab != .reels || channel.reelCount > 0
        }
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableTabs) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.title)
                    }
                    .pillTab(isSelected: selectedTab == tab)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 14)
        }
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .videos:
            videoList(channel.videos)
        case .reels:
            reelsGrid
        case .about:
            aboutSection
        }
    }

    private func videoList(_ videos: [CountryPost]) -> some View {
        Group {
            if videos.isEmpty {
                ContentUnavailableView("No videos yet", systemImage: "film")
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 22) {
                    ForEach(videos) { post in
                        YouTubeVideoListRow(post: post) {
                            onOpenVideo(post)
                        }
                    }
                }
                .padding(.top, 16)
            }
        }
    }

    private var reelsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(channel.reels) { post in
                PlayReelTile(post: post) {
                    onOpenVideo(post)
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 16)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MatteryaCopy.aboutThisHub)
                .font(.system(.headline, design: .serif))
                .fontWeight(.regular)
            if channel.hasCustomChannelName {
                Label(MatteryaCopy.verifiedHubsChannel, systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accentBright)
            }
            if let country = channel.author?.countryName {
                Label(country, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Text("\(channel.reelCount) \(MatteryaCopy.sparks.lowercased()) · \(channel.videoCount) videos")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)

            ShareLink(item: PlayPlatformBridge.channelURL(
                authorID: channel.authorID,
                username: channel.author?.username
            )) {
                Label(MatteryaCopy.shareCreatorHub, systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.accentBright)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.pagePadding)
        .padding(.top, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .padding(.horizontal, Theme.pagePadding)
    }
}