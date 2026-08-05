import SwiftUI

/// Single continuous hubs AVPlayer for the whole app.
/// Full stage on Hubs watch, mini bar on any tab — same player instance, never remounted.
struct GlobalHubPlaybackLayer: View {
    @Environment(AppState.self) private var appState

    @State private var dragOffset: CGFloat = 0
    @State private var isPullingMinimize = false

    var body: some View {
        GeometryReader { geo in
            let stageHeight = YouTubeMediaLayout.watchPlayerHeight(
                containerWidth: geo.size.width,
                containerHeight: geo.size.height
            )
            let expanded = appState.hubPlaybackExpanded
            let dockInChat = appState.hubPlaybackDockInChat
            let miniW = YouTubeMiniPlayerBar.videoWidth
            let miniH = YouTubeMiniPlayerBar.videoHeight
            let videoW = expanded ? geo.size.width : miniW
            let videoH = expanded ? stageHeight : miniH
            // Floating mini is hidden in chat — ConversationView docks it under the composer.
            let showFloatingMini = !expanded && !dockInChat

            ZStack(alignment: .top) {
                // ONE continuous surface — only frame/position change between full and mini.
                // Never branch into separate if/else player trees (that remounted AVPlayer).
                if let post = appState.hubPlaybackPost {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                        .overlay(alignment: expanded ? .top : .bottomLeading) {
                            // In chat, continuous video is hidden here; chat dock owns a hole + chrome.
                            // Keep AVPlayer alive via isActive on playerSurface (still mounted off-layout).
                            if expanded || showFloatingMini {
                                playerSurface(for: post, showControls: expanded)
                                    .frame(width: videoW, height: videoH)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: expanded ? 0 : 12,
                                            style: .continuous
                                        )
                                    )
                                    .background {
                                        if expanded {
                                            Theme.ink
                                        } else {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Theme.ink)
                                        }
                                    }
                                    .shadow(
                                        color: expanded ? .clear : Theme.ink.opacity(0.18),
                                        radius: expanded ? 0 : 8,
                                        y: expanded ? 0 : 3
                                    )
                                    .offset(y: expanded ? dragOffset : 0)
                                    .overlay {
                                        if expanded, isPullingMinimize, dragOffset > 24 {
                                            VStack {
                                                Spacer()
                                                Label(
                                                    "Release for mini player",
                                                    systemImage: "rectangle.bottomhalf.inset.filled"
                                                )
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Theme.paper)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(Theme.ink.opacity(0.55), in: Capsule())
                                                .padding(.bottom, 16)
                                            }
                                            .allowsHitTesting(false)
                                        }
                                    }
                                    .padding(.leading, expanded ? 0 : YouTubeMiniPlayerBar.barContentLeading)
                                    .padding(.bottom, expanded ? 0 : YouTubeMiniPlayerBar.videoBottomInset)
                                    .simultaneousGesture(expanded ? minimizeGesture : nil)
                                    .onTapGesture {
                                        guard !expanded else { return }
                                        dragOffset = 0
                                        isPullingMinimize = false
                                        appState.expandHubPlayback()
                                    }
                                    .allowsHitTesting(true)
                            } else {
                                // Chat dock mode: keep player mounted but invisible so state survives.
                                playerSurface(for: post, showControls: false)
                                    .frame(width: 1, height: 1)
                                    .opacity(0.01)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .zIndex(expanded ? 1 : 6)
                }

                if showFloatingMini, let post = appState.hubPlaybackPost {
                    VStack {
                        Spacer(minLength: 0)
                        YouTubeMiniPlayerBar(
                            post: post,
                            onExpand: {
                                dragOffset = 0
                                isPullingMinimize = false
                                appState.expandHubPlayback()
                            },
                            onClose: {
                                dragOffset = 0
                                isPullingMinimize = false
                                appState.stopHubPlayback()
                            },
                            embedsVideo: false,
                            isPlaying: playingBinding,
                            isMuted: mutedBinding
                        )
                        .padding(.bottom, Theme.tabBarHeight + 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
                    .allowsHitTesting(true)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .animation(.easeInOut(duration: 0.22), value: expanded)
            .animation(.easeInOut(duration: 0.2), value: appState.hubPlaybackPost?.id)
            .allowsHitTesting(appState.hubPlaybackPost != nil)
            .onChange(of: appState.hubPlaybackExpanded) { _, isExpanded in
                if isExpanded {
                    dragOffset = 0
                    isPullingMinimize = false
                }
            }
            .onChange(of: appState.hubPlaybackPost?.id) { _, _ in
                dragOffset = 0
                isPullingMinimize = false
            }
        }
    }

    private var playingBinding: Binding<Bool> {
        Binding(
            get: { appState.hubPlaybackPlaying },
            set: { appState.hubPlaybackPlaying = $0 }
        )
    }

    private var mutedBinding: Binding<Bool> {
        Binding(
            get: { appState.hubPlaybackMuted },
            set: { appState.hubPlaybackMuted = $0 }
        )
    }

    @ViewBuilder
    private func playerSurface(for post: CountryPost, showControls: Bool) -> some View {
        // When docked in chat, ConversationView owns the audible mini player — pause continuous
        // so we don't double audio. Expanded / floating mini use this continuous surface.
        let continuousActive = appState.hubPlaybackPlaying
            && (appState.hubPlaybackExpanded || !appState.hubPlaybackDockInChat)
        if let url = post.playableVideoURL {
            if ArchiveVideoPlayback.isArchiveURL(url) || post.isHubSeedVideo {
                MatteryaHubPlayerView(
                    url: url,
                    posterURL: post.posterImageURL,
                    isActive: continuousActive,
                    startTime: YouTubeCatalogService.shared.playbackPosition(for: post.id),
                    postID: post.id,
                    showsControls: showControls,
                    loops: false,
                    isMuted: mutedBinding,
                    onReady: {
                        Task { await PostsService.shared.recordView(post) }
                    }
                )
                // Stable id across expand/mini so AVPlayer is not recreated.
                .id("global-hub-continuous-\(post.id)")
            } else {
                VideoPlayerView(
                    url: url,
                    posterURL: post.posterImageURL,
                    placement: nil,
                    countryCode: post.countryCode,
                    contentCountryCode: post.countryCode,
                    postID: post.id,
                    adsEnabled: false,
                    isActive: continuousActive,
                    loops: false,
                    muted: appState.hubPlaybackMuted,
                    showsControls: showControls,
                    allowsFullscreen: showControls,
                    startTime: YouTubeCatalogService.shared.playbackPosition(for: post.id),
                    persistsPositionOnTeardown: true,
                    onViewed: { Task { await PostsService.shared.recordView(post) } }
                )
                .id("global-hub-continuous-\(post.id)")
            }
        } else {
            YouTubeVideoThumbnail(
                post: post,
                maxPixelSize: showControls ? 900 : 420,
                showsPlayIcon: false,
                frameStyle: showControls ? .watch : .card,
                embedsFrame: false
            )
            .id("global-hub-continuous-\(post.id)")
        }
    }

    private var minimizeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                var offset = dragOffset
                var dragging = isPullingMinimize
                MatteryaPullDownDismiss.applyChanged(value, offset: &offset, isDragging: &dragging)
                dragOffset = offset
                isPullingMinimize = dragging
            }
            .onEnded { value in
                var offset = dragOffset
                var dragging = isPullingMinimize
                MatteryaPullDownDismiss.applyEnded(
                    value,
                    offset: &offset,
                    isDragging: &dragging,
                    dismiss: {
                        dragOffset = 0
                        isPullingMinimize = false
                        appState.minimizeHubPlayback()
                    }
                )
                if dragging == false, offset != 0 {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                } else {
                    dragOffset = offset
                }
                isPullingMinimize = dragging
            }
    }
}
