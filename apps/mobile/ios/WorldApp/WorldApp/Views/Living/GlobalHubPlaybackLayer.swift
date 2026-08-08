import SwiftUI

/// Global frame of the chat mini “video hole” so continuous playback can dock without remounting.
enum HubContinuousVideoSlotKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// Single continuous hubs AVPlayer for the whole app.
///
/// Hit-testing (critical for navigation):
/// - **Floating mini:** outer frame is only the bottom strip height — the rest of the app stays tappable.
/// - **Expanded / chat dock:** full window, but only the video rect receives hits.
///
/// Expand ↔ mini only resizes the same player (stable `.id`) — playback keeps running.
struct GlobalHubPlaybackLayer: View {
    @Environment(AppState.self) private var appState

    var dockSlotGlobal: CGRect? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isPullingMinimize = false

    private var expanded: Bool { appState.hubPlaybackExpanded }
    private var docked: Bool { appState.hubPlaybackDockInChat }

    private var hasDockSlot: Bool {
        docked
            && dockSlotGlobal != nil
            && (dockSlotGlobal?.width ?? 0) > 8
            && (dockSlotGlobal?.height ?? 0) > 8
    }

    /// Mini bar chrome height (not including tab bar) — no extra gap padding.
    private var miniStripHeight: CGFloat {
        YouTubeMiniPlayerBar.barHeight
    }

    /// When the custom tab bar is visible, sit fully above it (never overlay tabs).
    private var floatingAboveTabBar: Bool {
        !expanded && !hasDockSlot && appState.navigationPath.isEmpty
    }

    private var floatingBottomClearance: CGFloat {
        // This layer only ignores the *top* safe area — its GeometryReader bottom is already
        // the top of the home-indicator inset. The tab bar is `tabBarHeight` tall sitting there
        // (its bg extends into the home indicator). Use ONLY tabBarHeight so the mini is flush
        // with zero gap. Adding safeBottom again was creating the empty strip users saw.
        if hasDockSlot { return 0 }
        if floatingAboveTabBar {
            return Theme.tabBarHeight
        }
        // Pushed routes (no tab bar): sit on the safe bottom edge.
        return 0
    }

    var body: some View {
        Group {
            if let post = appState.hubPlaybackPost {
                // Always full-window host so expand/mini/nav never remounts AVPlayer
                // (remount was restarting from 0). Layout only moves the same surface.
                GeometryReader { geo in
                    continuousStage(post: post, geo: geo)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .top)
            }
        }
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.88), value: expanded)
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.88), value: hasDockSlot)
        .animation(.easeInOut(duration: 0.2), value: appState.hubPlaybackPost?.id)
        .animation(.easeInOut(duration: 0.2), value: appState.navigationPath.isEmpty)
        .onChange(of: expanded) { _, isExpanded in
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

    // MARK: - Stage (one tree → one AVPlayer)

    @ViewBuilder
    private func continuousStage(post: CountryPost, geo: GeometryProxy) -> some View {
        let layout = playerLayout(in: geo)

        ZStack(alignment: .topLeading) {
            // Never claim empty space for hits.
            Color.clear
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)

            // Continuous video surface — stable id across expand/mini/dock.
            // Mini chrome is owned by MainTabView’s bottom stack (flush on the tab bar).
            // This layer only draws the video hole over that chrome’s reported slot.
            playerSurface(for: post, showControls: expanded)
                .frame(width: layout.width, height: layout.height)
                .background(Theme.ink)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: expanded ? 0 : 12,
                        style: .continuous
                    )
                )
                .shadow(
                    color: expanded ? .clear : Theme.ink.opacity(0.18),
                    radius: expanded ? 0 : 8,
                    y: expanded ? 0 : 3
                )
                .offset(x: layout.x, y: layout.y + (expanded ? dragOffset : 0))
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
                .simultaneousGesture(minimizeGesture)
                .onTapGesture {
                    // Mini / dock: tap video → maximize. Expanded: transport owns taps.
                    guard !expanded else { return }
                    expand()
                }
                .id("global-hub-continuous-\(post.id)")
                .allowsHitTesting(true)
                .zIndex(5)
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        // Only the video rect receives hits — mini chrome is outside this layer now.
        .modifier(HubHitShapeModifier(
            enabled: true,
            rect: hitRect(for: layout, geo: geo)
        ))
    }

    private func hitRect(for layout: PlayerLayout, geo: GeometryProxy) -> CGRect {
        CGRect(
            x: layout.x,
            y: layout.y + (expanded ? dragOffset : 0),
            width: layout.width,
            height: layout.height
        )
    }

    // MARK: - Layout

    private struct PlayerLayout {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func playerLayout(in geo: GeometryProxy) -> PlayerLayout {
        let miniW = YouTubeMiniPlayerBar.videoWidth
        let miniH = YouTubeMiniPlayerBar.videoHeight

        if expanded {
            // Start directly under the notch (status bar), not overlapping it.
            let safeTop = geo.safeAreaInsets.top > 1
                ? geo.safeAreaInsets.top
                : YouTubeMediaLayout.keyWindowSafeTop
            let stageHeight = YouTubeMediaLayout.hubsContinuousStageHeight(containerWidth: geo.size.width)
            return PlayerLayout(x: 0, y: safeTop, width: geo.size.width, height: stageHeight)
        }

        // Mini / chat dock: always prefer the reported video-hole frame (global → local).
        if let global = dockSlotGlobal,
           global.width > 8, global.height > 8 {
            let containerGlobal = geo.frame(in: .global)
            // Guard against bad transforms that park the surface off-screen (white hole).
            let x = global.minX - containerGlobal.minX
            let y = global.minY - containerGlobal.minY
            if y > -20, y < geo.size.height + 20,
               x > -20, x < geo.size.width + 20 {
                return PlayerLayout(
                    x: x,
                    y: y,
                    width: max(global.width, miniW),
                    height: max(global.height, miniH)
                )
            }
        }

        // Fallback before preference publishes — sit in the mini strip above the tab bar.
        let x = YouTubeMiniPlayerBar.barContentLeading
        let barTop = geo.size.height - floatingBottomClearance - miniStripHeight
        let y = barTop + max(0, (miniStripHeight - miniH) / 2)
        return PlayerLayout(x: x, y: y, width: miniW, height: miniH)
    }

    // MARK: - Player

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
        // Always resume from catalog position if the surface is recreated (should be rare).
        let resumeAt = YouTubeCatalogService.shared.playbackPosition(for: post.id)
        if let url = post.playableVideoURL {
            // One Hubs chrome for every long-form surface (R2 + Archive):
            // center play · −10s · +10s · bottom scrubber (MatteryaHubPlayerView).
            MatteryaHubPlayerView(
                url: url,
                posterURL: post.posterImageURL,
                isActive: appState.hubPlaybackPlaying,
                startTime: resumeAt,
                postID: post.id,
                showsControls: showControls,
                loops: false,
                // Full-bleed — never black bars on sides or top.
                fillsFrame: true,
                isMuted: mutedBinding,
                allowsFullscreen: showControls,
                onReady: {
                    Task { await PostsService.shared.recordView(post) }
                },
                onPlayingChange: { playing in
                    appState.hubPlaybackPlaying = playing
                }
            )
        } else {
            YouTubeVideoThumbnail(
                post: post,
                maxPixelSize: showControls ? 900 : 420,
                showsPlayIcon: false,
                frameStyle: showControls ? .watch : .card,
                embedsFrame: false
            )
        }
    }

    private func expand() {
        dragOffset = 0
        isPullingMinimize = false
        appState.expandHubPlayback()
    }

    private func stop() {
        dragOffset = 0
        isPullingMinimize = false
        appState.stopHubPlayback()
    }

    private var minimizeGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { value in
                guard expanded else { return }
                var offset = dragOffset
                var dragging = isPullingMinimize
                MatteryaPullDownDismiss.applyChanged(value, offset: &offset, isDragging: &dragging)
                dragOffset = offset
                isPullingMinimize = dragging
            }
            .onEnded { value in
                guard expanded else {
                    dragOffset = 0
                    isPullingMinimize = false
                    return
                }
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

// MARK: - Hit shape helper

/// When enabled, only `rect` receives hits; everything else passes through to views below.
private struct HubHitShapeModifier: ViewModifier {
    let enabled: Bool
    let rect: CGRect

    func body(content: Content) -> some View {
        if enabled {
            content.contentShape(.interaction, Path(rect))
        } else {
            // Mini strip: the whole (short) frame may receive hits — that's intentional.
            content
        }
    }
}
