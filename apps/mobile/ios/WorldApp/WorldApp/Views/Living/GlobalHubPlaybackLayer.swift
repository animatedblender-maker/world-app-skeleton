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
/// - **Floating mini:** only the video rect receives hits; chrome buttons sit on the same surface.
/// - **Expanded:** full stage + transport; pull-down collapses to mini.
///
/// Expand ↔ mini only resizes the same player (stable `.id`) — playback keeps running.
struct GlobalHubPlaybackLayer: View {
    @Environment(AppState.self) private var appState

    var dockSlotGlobal: CGRect? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isPullingMinimize = false
    /// Aspect-fill only when fully mini — applied after morph settles.
    @State private var preferMiniFill = false

    private var expanded: Bool { appState.hubPlaybackExpanded }
    private var docked: Bool { appState.hubPlaybackDockInChat }

    /// Fast ease-out — springs mid-path felt “stuck” halfway down the screen.
    private static let morphAnim = Animation.easeOut(duration: 0.24)

    private var hasDockSlot: Bool {
        docked
            && dockSlotGlobal != nil
            && (dockSlotGlobal?.width ?? 0) > 8
            && (dockSlotGlobal?.height ?? 0) > 8
    }

    private var miniStripHeight: CGFloat {
        YouTubeMiniPlayerBar.barHeight
    }

    private var floatingAboveTabBar: Bool {
        !expanded && !hasDockSlot && appState.navigationPath.isEmpty
    }

    private var floatingBottomClearance: CGFloat {
        if hasDockSlot { return 0 }
        if floatingAboveTabBar {
            return Theme.tabBarHeight
        }
        return 0
    }

    private var showTransportChrome: Bool {
        expanded && !isPullingMinimize && dragOffset < 2
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

    var body: some View {
        Group {
            if let post = appState.hubPlaybackPost {
                GeometryReader { geo in
                    continuousStage(post: post, geo: geo)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .top)
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded {
                dragOffset = 0
                isPullingMinimize = false
                preferMiniFill = false
            } else {
                dragOffset = 0
                isPullingMinimize = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 260_000_000)
                    guard !appState.hubPlaybackExpanded else { return }
                    preferMiniFill = true
                }
            }
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, _ in
            dragOffset = 0
            isPullingMinimize = false
            preferMiniFill = !appState.hubPlaybackExpanded
        }
        .onChange(of: appState.hubPlaybackPlaying) { _, playing in
            guard playing, appState.hubPlaybackPost != nil else { return }
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
        .onAppear {
            preferMiniFill = !expanded
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private func continuousStage(post: CountryPost, geo: GeometryProxy) -> some View {
        let layout = playerLayout(in: geo)
        let liveY = layout.y + (expanded ? dragOffset : 0)

        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)

            ZStack {
                playerSurface(for: post, showControls: showTransportChrome)
                    .frame(width: layout.width, height: layout.height)
                    .background(expanded && !isPullingMinimize ? Theme.ink : Color.clear)
                    .clipped()

                // Mini controls ON TOP of continuous video (bar chrome is under zIndex 55).
                if !expanded, !isPullingMinimize {
                    HubMiniPlayerChrome(
                        isPlaying: playingBinding,
                        isMuted: mutedBinding,
                        onClose: { appState.stopHubPlayback() }
                    )
                    .frame(width: layout.width, height: layout.height)
                    .allowsHitTesting(true)
                }
            }
            .frame(width: layout.width, height: layout.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: expanded ? (isPullingMinimize ? 14 : 0) : 0,
                    style: .continuous
                )
            )
            .offset(x: layout.x, y: liveY)
            // Animate layout only when not finger-dragging.
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: expanded)
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: layout.width)
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: layout.height)
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: layout.x)
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: layout.y)
            .simultaneousGesture(minimizeGesture)
            .onTapGesture {
                guard !expanded else { return }
                expand()
            }
            .id("global-hub-continuous-\(post.id)")
            .allowsHitTesting(true)
            .zIndex(5)
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        .modifier(HubHitShapeModifier(
            enabled: true,
            rect: CGRect(x: layout.x, y: liveY, width: layout.width, height: layout.height)
        ))
    }

    // MARK: - Layout

    private struct PlayerLayout {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func playerLayout(in geo: GeometryProxy) -> PlayerLayout {
        if expanded {
            let safeTop = geo.safeAreaInsets.top > 1
                ? geo.safeAreaInsets.top
                : YouTubeMediaLayout.keyWindowSafeTop
            let stageHeight = YouTubeMediaLayout.hubsContinuousStageHeight(containerWidth: geo.size.width)
            return PlayerLayout(x: 0, y: safeTop, width: geo.size.width, height: stageHeight)
        }

        // Prefer stable fallback for floating mini (full width ¼-screen).
        // Dock preference used to reject full-width slots (`width < 0.85`) and thrash mid-morph.
        if hasDockSlot, let global = dockSlotGlobal {
            let containerGlobal = geo.frame(in: .global)
            let x = global.minX - containerGlobal.minX
            let y = global.minY - containerGlobal.minY
            let looksLikeMiniSlot = y > geo.size.height * 0.25
                && global.height > 48
                && global.height < geo.size.height * 0.45
                && global.width > 40
            if looksLikeMiniSlot,
               y > -20, y < geo.size.height + 20,
               x > -40, x < geo.size.width + 40 {
                return PlayerLayout(x: x, y: y, width: global.width, height: global.height)
            }
        }

        let barW = geo.size.width
        let size = YouTubeMiniPlayerBar.videoSize(forBarWidth: barW)
        let barTop = geo.size.height - floatingBottomClearance - miniStripHeight
        return PlayerLayout(x: 0, y: barTop, width: size.width, height: size.height)
    }

    // MARK: - Player

    @ViewBuilder
    private func playerSurface(for post: CountryPost, showControls: Bool) -> some View {
        let stored = YouTubeCatalogService.shared.playbackPosition(for: post.id)
        let resumeAt = stored > 3 ? stored : 0
        if let url = post.playableVideoURL {
            MatteryaHubPlayerView(
                url: url,
                posterURL: post.posterImageURL,
                isActive: appState.hubPlaybackPlaying,
                startTime: resumeAt,
                postID: post.id,
                showsControls: showControls,
                loops: false,
                fillsFrame: preferMiniFill && !expanded,
                isMuted: mutedBinding,
                allowsFullscreen: showControls,
                onReady: {
                    Task { await PostsService.shared.recordView(post) }
                    if appState.hubPlaybackPlaying {
                        NotificationCenter.default.post(
                            name: .matteryaResumePlaybackAfterInterrupt,
                            object: nil
                        )
                    }
                },
                onPlayingChange: { playing in
                    appState.hubPlaybackPlaying = playing
                }
            )
            .id("hub-continuous-\(post.id)")
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
        preferMiniFill = false
        appState.expandHubPlayback()
    }

    private var minimizeGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard expanded else { return }
                var offset = dragOffset
                var dragging = isPullingMinimize
                MatteryaPullDownDismiss.applyChanged(value, offset: &offset, isDragging: &dragging)
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    dragOffset = offset
                    isPullingMinimize = dragging
                }
            }
            .onEnded { value in
                guard expanded else {
                    dragOffset = 0
                    isPullingMinimize = false
                    return
                }
                let shouldMini = MatteryaPullDownDismiss.shouldDismiss(value)
                    || dragOffset > 90
                    || value.predictedEndTranslation.height > 160
                if shouldMini {
                    ReelsTwistHaptics.pullDismiss()
                    // Snap drag to 0 with no animation, then ease frame to mini (one path only).
                    var snap = Transaction()
                    snap.disablesAnimations = true
                    withTransaction(snap) {
                        dragOffset = 0
                        isPullingMinimize = false
                    }
                    withAnimation(Self.morphAnim) {
                        appState.minimizeHubPlayback(returnToChat: true, animated: false)
                    }
                } else {
                    withAnimation(Self.morphAnim) {
                        dragOffset = 0
                        isPullingMinimize = false
                    }
                }
            }
    }
}

// MARK: - Hit shape helper

private struct HubHitShapeModifier: ViewModifier {
    let enabled: Bool
    let rect: CGRect

    func body(content: Content) -> some View {
        if enabled {
            content.contentShape(.interaction, Path(rect))
        } else {
            content
        }
    }
}
