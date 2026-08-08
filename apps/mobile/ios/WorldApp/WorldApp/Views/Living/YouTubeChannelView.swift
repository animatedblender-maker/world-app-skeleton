import PhotosUI
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
    @State private var managedChannel: HubChannel?
    @State private var showChannelSettings = false
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var isUploadingCover = false
    @State private var coverError: String?

    private var canManageChannel: Bool {
        managedChannel?.isStaff == true
            || channel.authorID == appState.currentProfile?.userID
    }

    /// Live count — parent may already resolve deltas; still re-read AppState so Follow updates instantly.
    private var liveFollowerCount: Int {
        appState.resolvedFollowerCount(for: channel.authorID, base: subscriberCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Banner + header stay above the tab strip (not mixed with video rows).
            VStack(alignment: .leading, spacing: 0) {
                banner
                header
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Tabs are fixed — never share a scroll/hit region with the first video.
            tabPicker
                .frame(maxWidth: .infinity)

            ScrollView {
                tabContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep content inside safe area so left/right isn't clipped under notch/edges.
        .safeAreaPadding(.horizontal, 0)
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
            .zIndex(20)
        }
        .overlay(alignment: .topTrailing) {
            if canManageChannel, let managed = managedChannel {
                Button {
                    showChannelSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface.opacity(0.94), in: Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 12)
                .accessibilityLabel("Channel settings")
                .zIndex(20)
                .sheet(isPresented: $showChannelSettings, onDismiss: {
                    Task { await loadManagedChannel() }
                }) {
                    ChannelSettingsView(channelID: managed.id)
                        .withAppState(appState)
                }
            }
        }
        .task(id: channel.authorID) {
            await loadManagedChannel()
        }
    }

    private var channelAboutText: String {
        (managedChannel?.about ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadManagedChannel() async {
        // Seed / Archive channels have no human admins.
        if HubVideoSeedService.isArchiveChannelAuthor(channel.authorID) {
            managedChannel = nil
            return
        }
        // Prefer channel owned by this author; also detect if I'm an admin elsewhere.
        if let byOwner = try? await ChannelsService.shared.channelByOwner(userID: channel.authorID) {
            managedChannel = byOwner
            return
        }
        if let mine = try? await ChannelsService.shared.myChannel(),
           mine.ownerUserID == channel.authorID {
            managedChannel = mine
            return
        }
        if let admined = try? await ChannelsService.shared.channelsIAdmin(),
           let match = admined.first(where: { $0.ownerUserID == channel.authorID }) {
            managedChannel = match
            return
        }
        managedChannel = nil
    }

    private var banner: some View {
        ZStack(alignment: .bottomTrailing) {
            // Cover photo (full-bleed) or decorative fallback.
            Group {
                if let coverURL = managedChannel?.coverURL,
                   let url = URL(string: coverURL), !coverURL.isEmpty {
                    CachedAsyncImage(
                        url: url,
                        maxPixelSize: 1200,
                        contentMode: .fill,
                        placeholder: AnyView(coverPlaceholder)
                    )
                } else {
                    coverPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 128)
            .clipped()

            if canManageChannel, managedChannel != nil {
                PhotosPicker(selection: $coverPickerItem, matching: .images) {
                    HStack(spacing: 6) {
                        if isUploadingCover {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.paper)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.caption.weight(.semibold))
                        }
                        Text(managedChannel?.coverURL == nil ? "Add cover" : "Change cover")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.ink.opacity(0.55), in: Capsule())
                }
                .disabled(isUploadingCover)
                .padding(.trailing, Theme.pagePadding)
                .padding(.bottom, 10)
                .onChange(of: coverPickerItem) { _, item in
                    Task { await uploadCover(item) }
                }
            }
        }
        .frame(height: 128)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }

    private var coverPlaceholder: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Theme.accentSoft, Theme.canvasMuted, Theme.paper],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
                    .allowsHitTesting(false)
            }
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
        // Always show followers so Follow/Unfollow is visible immediately.
        parts.append("\(liveFollowerCount.formatted()) \(MatteryaCopy.followers)")
        parts.append("\(channel.videoCount) videos")
        if channel.totalViews > 0 {
            parts.append("\(channel.totalViews.formatted()) views")
        }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func uploadCover(_ item: PhotosPickerItem?) async {
        guard let item, let managed = managedChannel else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            coverError = "Could not read photo."
            return
        }
        isUploadingCover = true
        coverError = nil
        defer {
            isUploadingCover = false
            coverPickerItem = nil
        }
        do {
            let jpeg = (try? PhotosPickerMediaLoader.normalizeToJPEG(data, quality: 0.78, maxEdge: 1920)) ?? data
            let upload = try await MediaService.shared.uploadPostMedia(
                data: jpeg,
                fileExtension: "jpg",
                mimeType: "image/jpeg"
            )
            let updated = try await ChannelsService.shared.updateChannel(
                id: managed.id,
                coverURL: upload.publicURL
            )
            managedChannel = updated
        } catch {
            coverError = error.localizedDescription
        }
    }

    private var availableTabs: [YouTubeChannelTab] {
        YouTubeChannelTab.allCases.filter { tab in
            tab != .reels || channel.reelCount > 0
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs) { tab in
                Button {
                    // No animation on the selection itself — keeps the About
                    // tap from being swallowed by the first video row re-layout.
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(selectedTab == tab ? Theme.ink : Theme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(Theme.ink)
                                    .frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .background(Theme.canvas)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
        .zIndex(5)
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
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 22) {
                    ForEach(videos) { post in
                        YouTubeVideoListRow(post: post) {
                            onOpenVideo(post)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reelsGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0), spacing: 8),
                count: 3
            ),
            alignment: .center,
            spacing: 8
        ) {
            ForEach(channel.reels) { post in
                PlayReelTile(post: post) {
                    onOpenVideo(post)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 16)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MatteryaCopy.aboutThisHub)
                .font(.system(.headline, design: .serif))
                .fontWeight(.regular)

            if channelAboutText.isEmpty {
                Text("No about text yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                Text(channelAboutText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

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