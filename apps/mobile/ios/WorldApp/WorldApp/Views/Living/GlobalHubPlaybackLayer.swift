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
    /// Aspect-fill only when fully mini — flipped *after* morph so release never hitch-crops.
    @State private var preferMiniFill = false

    private var expanded: Bool { appState.hubPlaybackExpanded }
    private var docked: Bool { appState.hubPlaybackDockInChat }

    /// Single spring for expand ↔ mini — no stacked second phase (that felt “stuck”).
    private static let morphSpring = Animation.spring(response: 0.30, dampingFraction: 0.92, blendDuration: 0.12)

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

    /// Hide transport while dragging or morphing — avoids chrome flash mid-animation.
    private var showTransportChrome: Bool {
        expanded && !isPullingMinimize && dragOffset < 2
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
        // Dock slot can lag one frame — ease only that, not expand (caller owns expand spring).
        .animation(Self.morphSpring, value: hasDockSlot)
        .onChange(of: expanded) { _, isExpanded in
            // Offset is cleared in the *same* animation as collapse — never a second settle phase.
            if isExpanded {
                dragOffset = 0
                isPullingMinimize = false
                preferMiniFill = false
            } else {
                dragOffset = 0
                isPullingMinimize = false
                // Fill after the morph finishes so release doesn't hitch on gravity change.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 280_000_000)
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
            // Chat → Hubs / mini play: re-assert AVPlayer the moment AppState wants sound.
            guard playing, appState.hubPlaybackPost != nil else { return }
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
        .onAppear {
            preferMiniFill = !expanded
        }
    }

    // MARK: - Stage (one tree → one AVPlayer)

    @ViewBuilder
    private func continuousStage(post: CountryPost, geo: GeometryProxy) -> some View {
        let layout = playerLayout(in: geo)
        let liveY = layout.y + (expanded ? dragOffset : 0)

        ZStack(alignment: .topLeading) {
            // Never claim empty space for hits.
            Color.clear
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)

            // Continuous video surface — stable id across expand/mini/dock.
            // Mini chrome is owned by MainTabView’s bottom stack (flush on the tab bar).
            playerSurface(for: post, showControls: showTransportChrome)
                .frame(width: layout.width, height: layout.height)
                .background(expanded && !isPullingMinimize ? Theme.ink : Color.clear)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: expanded ? (isPullingMinimize ? 14 : 0) : 0,
                        style: .continuous
                    )
                )
                // Follow the finger 1:1 while dragging (no spring lag).
                .offset(x: layout.x, y: liveY)
                .scaleEffect(expanded && isPullingMinimize ? pullScale : 1, anchor: .top)
                // Explicit frame animation only when not finger-tracking.
                .animation(isPullingMinimize ? nil : Self.morphSpring, value: expanded)
                .animation(isPullingMinimize ? nil : Self.morphSpring, value: layout.width)
                .animation(isPullingMinimize ? nil : Self.morphSpring, value: layout.height)
                .animation(isPullingMinimize ? nil : Self.morphSpring, value: layout.x)
                .animation(isPullingMinimize ? nil : Self.morphSpring, value: layout.y)
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
            rect: CGRect(x: layout.x, y: liveY, width: layout.width, height: layout.height)
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
        if expanded {
            // Start directly under the notch (status bar), not overlapping it.
            let safeTop = geo.safeAreaInsets.top > 1
                ? geo.safeAreaInsets.top
                : YouTubeMediaLayout.keyWindowSafeTop
            let stageHeight = YouTubeMediaLayout.hubsContinuousStageHeight(containerWidth: geo.size.width)
            return PlayerLayout(x: 0, y: safeTop, width: geo.size.width, height: stageHeight)
        }

        // Mini / chat dock: use the **exact** video-hole frame only.
        if let global = dockSlotGlobal,
           global.width > 8, global.height > 8 {
            let containerGlobal = geo.frame(in: .global)
            let x = global.minX - containerGlobal.minX
            let y = global.minY - containerGlobal.minY
            // Accept lower-half slots (bar can be ~¼ screen tall).
            let looksLikeMiniSlot = y > geo.size.height * 0.28
                && global.height < geo.size.height * 0.40
                && global.width < geo.size.width * 0.85
            if looksLikeMiniSlot,
               y > -20, y < geo.size.height + 20,
               x > -20, x < geo.size.width + 20 {
                return PlayerLayout(
                    x: x,
                    y: y,
                    width: global.width,
                    height: global.height
                )
            }
        }

        // Fallback before preference publishes — full mini card (edge-to-edge video).
        let barW = geo.size.width
        let size = YouTubeMiniPlayerBar.videoSize(forBarWidth: barW)
        let barTop = geo.size.height - floatingBottomClearance - miniStripHeight
        return PlayerLayout(x: 0, y: barTop, width: size.width, height: size.height)
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
        // Resume mid-clip only when already deep into the video — never block first frame
        // with a hard seek on open (that made Hubs feel laggy).
        let stored = YouTubeCatalogService.shared.playbackPosition(for: post.id)
        let resumeAt = stored > 3 ? stored : 0
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
                // Expanded: fit (no crop). Mini fill applied after morph (preferMiniFill).
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

    private func stop() {
        dragOffset = 0
        isPullingMinimize = false
        appState.stopHubPlayback()
    }

    /// 0…1 progress while pulling expanded stage toward mini.
    private var dragProgress: CGFloat {
        min(max(dragOffset / 200, 0), 1)
    }

    /// Mild shrink while dragging — release morphs frame, not a second scale phase.
    private var pullScale: CGFloat {
        guard expanded, isPullingMinimize else { return 1 }
        return 1 - dragProgress * 0.08
    }

    private var minimizeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard expanded else { return }
                var offset = dragOffset
                var dragging = isPullingMinimize
                MatteryaPullDownDismiss.applyChanged(value, offset: &offset, isDragging: &dragging)
                // 1:1 finger tracking — never animate dragOffset while pulling.
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
                    || dragOffset > 100
                    || value.predictedEndTranslation.height > 180
                if shouldMini {
                    ReelsTwistHaptics.pullDismiss()
                    // One atomic morph: zero drag + collapse. No nested onChange settle.
                    withAnimation(Self.morphSpring) {
                        dragOffset = 0
                        isPullingMinimize = false
                        appState.minimizeHubPlayback(returnToChat: true, animated: false)
                    }
                } else {
                    withAnimation(Self.morphSpring) {
                        dragOffset = 0
                        isPullingMinimize = false
                    }
                }
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
