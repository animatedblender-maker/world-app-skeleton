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

/// Expanded watch stage hole (global) — kept for YouTubeWatchView preference publishers.
enum HubWatchStageFrameKey: PreferenceKey {
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
        // Smooth morph expand ↔ mini (interactive spring matches pull-down release).
        .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.86), value: expanded)
        .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.88), value: hasDockSlot)
        .animation(.easeOut(duration: 0.2), value: appState.hubPlaybackPost?.id)
        .animation(.easeOut(duration: 0.2), value: appState.navigationPath.isEmpty)
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded {
                // Clear pull offset after layout settles into mini.
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.9)) {
                    dragOffset = 0
                    isPullingMinimize = false
                }
            } else {
                dragOffset = 0
                isPullingMinimize = false
            }
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, _ in
            dragOffset = 0
            isPullingMinimize = false
        }
        .onChange(of: appState.hubPlaybackPlaying) { _, playing in
            // Chat → Hubs / mini play: re-assert AVPlayer the moment AppState wants sound.
            guard playing, appState.hubPlaybackPost != nil else { return }
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
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

            // Film + mini chrome in ONE box, then offset together.
            // Chrome must not be `.overlay` after `.offset` — that left chips at y≈0 (top of screen).
            ZStack {
                playerSurface(for: post, showControls: expanded && !isPullingMinimize)
                    .frame(width: layout.width, height: layout.height)
                    // Ink only under expanded stage (16:9 letterbox); mini hole stays transparent.
                    .background(expanded ? Theme.ink : Color.clear)

                if !expanded {
                    YouTubeMiniPlayerChrome(
                        isPlaying: playingBinding,
                        isMuted: mutedBinding,
                        onClose: { stop() }
                    )
                    .frame(width: layout.width, height: layout.height)
                }

                if expanded, isPullingMinimize, dragOffset > 28 {
                    VStack {
                        Spacer()
                        Label(
                            dragProgress > 0.55 ? "Release for mini player" : "Pull down for mini",
                            systemImage: "rectangle.bottomhalf.inset.filled"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.ink.opacity(0.55), in: Capsule())
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    .frame(width: layout.width, height: layout.height)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: layout.width, height: layout.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: expanded ? (isPullingMinimize ? 12 : 0) : 0,
                    style: .continuous
                )
            )
            .shadow(
                color: expanded
                    ? Theme.ink.opacity(isPullingMinimize ? 0.22 : 0)
                    : .clear,
                radius: expanded ? (isPullingMinimize ? 16 : 0) : 0,
                y: expanded ? (isPullingMinimize ? 8 : 0) : 0
            )
            .scaleEffect(
                expanded ? pullScale : 1,
                anchor: .top
            )
            .offset(x: layout.x, y: layout.y + (expanded ? dragOffset * 0.92 : 0))
            .opacity(expanded && isPullingMinimize ? Double(1 - min(dragProgress * 0.12, 0.12)) : 1)
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
            // Full-bleed mini is ~full width × ¼ screen; chat dock is a side slot.
            let looksLikeMiniOrDock = y > geo.size.height * 0.22
                && global.height < geo.size.height * 0.42
                && global.width > 40
            if looksLikeMiniOrDock,
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

        // Fallback before preference publishes — full-bleed strip under chrome chips.
        let barW = geo.size.width
        let size = YouTubeMiniPlayerBar.videoSize(forBarWidth: barW)
        let x = YouTubeMiniPlayerBar.barContentLeading
        let barTop = geo.size.height - floatingBottomClearance - miniStripHeight
        let y = barTop + YouTubeMiniPlayerBar.videoEdgeInset
        return PlayerLayout(x: x, y: y, width: size.width, height: size.height)
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
                // Expanded: aspect-fit 16:9 (no crop). Mini: fill the full-bleed strip.
                fillsFrame: !expanded,
                isMuted: mutedBinding,
                allowsFullscreen: showControls,
                onReady: {
                    Task { await PostsService.shared.recordView(post) }
                    // Re-assert play if something paused us during mount.
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
        appState.expandHubPlayback()
    }

    private func stop() {
        dragOffset = 0
        isPullingMinimize = false
        appState.stopHubPlayback()
    }

    /// 0…1 progress while pulling expanded stage toward mini.
    private var dragProgress: CGFloat {
        min(max(dragOffset / 220, 0), 1)
    }

    /// Subtle shrink while dragging — eases into the mini morph.
    private var pullScale: CGFloat {
        guard expanded, isPullingMinimize else { return 1 }
        return 1 - dragProgress * 0.12
    }

    private var minimizeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard expanded else { return }
                var offset = dragOffset
                var dragging = isPullingMinimize
                MatteryaPullDownDismiss.applyChanged(value, offset: &offset, isDragging: &dragging)
                // Follow the finger immediately (no laggy spring on change).
                dragOffset = offset
                isPullingMinimize = dragging
            }
            .onEnded { value in
                guard expanded else {
                    dragOffset = 0
                    isPullingMinimize = false
                    return
                }
                let shouldMini = MatteryaPullDownDismiss.shouldDismiss(value)
                    || dragOffset > 110
                if shouldMini {
                    // Keep current offset so the spring morph continues from the finger,
                    // then collapse into the mini slot.
                    withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.86)) {
                        isPullingMinimize = false
                        appState.minimizeHubPlayback()
                    }
                    // Offset clears in onChange(of: expanded).
                } else {
                    withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.84)) {
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
