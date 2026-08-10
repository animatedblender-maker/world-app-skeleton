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
/// Hit-testing: only the **video rect** receives touches (UIKit pass-through host).
/// Everything else (ScrollView under the player) scrolls normally.
/// Expand ↔ mini only resizes the same player (stable `.id`) — playback keeps running.
struct GlobalHubPlaybackLayer: View {
    @Environment(AppState.self) private var appState

    var dockSlotGlobal: CGRect? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isPullingMinimize = false
    @State private var preferMiniFill = false
    @State private var miniCurrentSeconds: Double = 0
    @State private var miniDurationSeconds: Double = 0
    @State private var miniSeekToSeconds: Double? = nil

    private var expanded: Bool { appState.hubPlaybackExpanded }

    private static let morphAnim = Animation.easeOut(duration: 0.24)

    /// Prefer docking into the reported mini-bar / chat hole whenever minimized.
    /// (Floating mini reports the same preference key as the chat dock.)
    private var hasDockSlot: Bool {
        !expanded
            && dockSlotGlobal != nil
            && (dockSlotGlobal?.width ?? 0) > 8
            && (dockSlotGlobal?.height ?? 0) > 8
    }

    private var miniStripHeight: CGFloat {
        YouTubeMiniPlayerBar.barHeight
    }

    /// When preference dock isn’t ready yet, sit the strip above the tab bar.
    private var floatingBottomClearance: CGFloat {
        if hasDockSlot { return 0 }
        if !expanded && appState.navigationPath.isEmpty {
            return Theme.tabBarHeight
        }
        return 0
    }

    private var showTransportChrome: Bool {
        // Hide transport when collapsed by comment-scroll (too short for scrubber).
        expanded
            && !isPullingMinimize
            && dragOffset < 2
            && appState.hubWatchScrollCollapse < 0.22
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
                    let layout = playerLayout(in: geo)
                    let liveY = layout.y + (expanded ? dragOffset : 0)
                    let hitRect = CGRect(
                        x: layout.x,
                        y: liveY,
                        width: layout.width,
                        height: layout.height
                    )

                    // UIKit pass-through: touches outside hitRect go to ScrollView underneath.
                    HubPassThroughContainer(interactiveRect: hitRect) {
                        videoStack(post: post, layout: layout, liveY: liveY)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Stay in the safe area so the stage starts *below* the Dynamic Island
                // (not mid-island). Mini docks via preference frame.
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded {
                dragOffset = 0
                isPullingMinimize = false
                preferMiniFill = false
                appState.hubPlaybackPullProgress = 0
            } else {
                dragOffset = 0
                isPullingMinimize = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 260_000_000)
                    guard !appState.hubPlaybackExpanded else { return }
                    preferMiniFill = true
                    appState.hubPlaybackPullProgress = 0
                }
            }
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, _ in
            dragOffset = 0
            isPullingMinimize = false
            preferMiniFill = !appState.hubPlaybackExpanded
            appState.hubPlaybackPullProgress = 0
            miniCurrentSeconds = 0
            miniDurationSeconds = 0
            miniSeekToSeconds = nil
        }
        .onChange(of: appState.hubPlaybackPlaying) { _, playing in
            guard playing, appState.hubPlaybackPost != nil else { return }
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
        .onAppear {
            preferMiniFill = !expanded
        }
    }

    // MARK: - Video stack (only this rect is hit-testable via pass-through host)

    @ViewBuilder
    private func videoStack(post: CountryPost, layout: PlayerLayout, liveY: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                playerSurface(for: post, showControls: showTransportChrome)
                    .frame(width: layout.width, height: layout.height)
                    // No ink bed under filled video — ink read as black top/bottom margins.
                    .background(Color.clear)
                    .clipped()

                // Mini chrome lives on YouTubeMiniPlayerBar (above this layer) so buttons work.
            }
            .frame(width: layout.width, height: layout.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: expanded ? (isPullingMinimize ? 14 : 0) : 0,
                    style: .continuous
                )
            )
            .offset(x: layout.x, y: liveY)
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: expanded)
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: layout.width)
            // Scroll collapse must track the finger — no laggy spring on height.
            .animation(nil, value: appState.hubWatchScrollCollapse)
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: layout.height)
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: layout.x)
            .animation(isPullingMinimize ? nil : Self.morphAnim, value: layout.y)
            // Pull-to-mini only while expanded (mini chrome owns taps when minimized).
            .simultaneousGesture(expanded ? minimizeGesture : nil)
            .id("global-hub-continuous-\(post.id)")
        }
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
            // Pure 16:9 at y=0 of the *safe* coordinate system.
            // Do NOT add keyWindowSafeTop — GeometryReader is already below the island,
            // and that double-offset left an empty gap at the top of the stage.
            let stageHeight = YouTubeMediaLayout.hubsStageHeight(
                containerWidth: geo.size.width,
                collapse: appState.hubWatchScrollCollapse,
                videoAspect: appState.hubPlaybackVideoAspect
            )
            return PlayerLayout(x: 0, y: 0, width: geo.size.width, height: stageHeight)
        }

        // Lock to the mini bar’s real frame (floating or chat).
        if hasDockSlot, let global = dockSlotGlobal {
            let containerGlobal = geo.frame(in: .global)
            let x = global.minX - containerGlobal.minX
            let y = global.minY - containerGlobal.minY
            let looksLikeMiniSlot = global.height > 48
                && global.height < max(120, geo.size.height * 0.45)
                && global.width > 40
                && y > geo.size.height * 0.15
            if looksLikeMiniSlot,
               y > -20, y + global.height <= geo.size.height + 24,
               x > -40, x < geo.size.width + 40 {
                return PlayerLayout(x: x, y: y, width: global.width, height: global.height)
            }
        }

        // Fallback: full-width strip flush above the tab bar.
        let barW = geo.size.width
        let size = YouTubeMiniPlayerBar.videoSize(forBarWidth: barW)
        let barTop = max(0, geo.size.height - floatingBottomClearance - miniStripHeight)
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
                // Expanded: aspectFit (no crop). Mini strip: aspectFill (full-bleed crop).
                fillsFrame: !expanded,
                isMuted: mutedBinding,
                allowsFullscreen: false,
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
                },
                onProgress: { current, duration in
                    miniCurrentSeconds = current
                    if duration > 0.25 { miniDurationSeconds = duration }
                },
                onVideoSize: { size in
                    appState.noteHubPlaybackVideoSize(size)
                },
                seekToSeconds: miniSeekToSeconds,
                onSeekConsumed: { miniSeekToSeconds = nil }
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
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
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
                    appState.hubPlaybackPullProgress = dragging
                        ? min(1, max(0.08, offset / 100))
                        : 0
                }
            }
            .onEnded { value in
                guard expanded else {
                    dragOffset = 0
                    isPullingMinimize = false
                    appState.hubPlaybackPullProgress = 0
                    return
                }
                let shouldMini = MatteryaPullDownDismiss.shouldDismiss(value)
                    || dragOffset > 90
                    || value.predictedEndTranslation.height > 160
                if shouldMini {
                    ReelsTwistHaptics.pullDismiss()
                    appState.hubPlaybackPullProgress = 1
                    var snap = Transaction()
                    snap.disablesAnimations = true
                    withTransaction(snap) {
                        dragOffset = 0
                        isPullingMinimize = false
                    }
                    withAnimation(Self.morphAnim) {
                        appState.minimizeHubPlayback(returnToChat: true, animated: false)
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 280_000_000)
                        if !appState.hubPlaybackExpanded {
                            appState.hubPlaybackPullProgress = 0
                        }
                    }
                } else {
                    withAnimation(Self.morphAnim) {
                        dragOffset = 0
                        isPullingMinimize = false
                        appState.hubPlaybackPullProgress = 0
                    }
                }
            }
    }
}
