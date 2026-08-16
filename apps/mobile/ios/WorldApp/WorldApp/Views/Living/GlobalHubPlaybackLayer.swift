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

/// Expanded watch stage hole (global) — continuous player must match this rect exactly
/// so the video never paints over the title.
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
/// Hit-testing: only the **video rect** receives touches (UIKit pass-through host).
/// Everything else (ScrollView under the player) scrolls normally.
/// Expand ↔ mini only resizes the same player (stable `.id`) — playback keeps running.
struct GlobalHubPlaybackLayer: View {
    @Environment(AppState.self) private var appState

    var dockSlotGlobal: CGRect? = nil
    /// Live frame of the watch-page stage hole (expanded only).
    var watchStageGlobal: CGRect? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isPullingMinimize = false
    @State private var preferMiniFill = false
    @State private var miniCurrentSeconds: Double = 0
    @State private var miniDurationSeconds: Double = 0
    @State private var miniSeekToSeconds: Double? = nil

    private var expanded: Bool { appState.hubPlaybackExpanded }

    /// Expand / minimize — short easeOut only (never spring — springs hang mid-screen).
    private static let morphAnim = MatteryaMotion.expand
    private static let minimizeMorphAnim = MatteryaMotion.minimize

    /// Chat dock only — floating mini uses a fixed bottom strip (no preference lag).
    private var hasChatDockSlot: Bool {
        !expanded
            && appState.hubPlaybackDockInChat
            && dockSlotGlobal != nil
            && (dockSlotGlobal?.width ?? 0) > 8
            && (dockSlotGlobal?.height ?? 0) > 8
    }

    private var hasDockSlot: Bool { hasChatDockSlot }

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
        // Keep controls mounted while expanded so opacity can fade with the pull slider.
        // Mini never shows in-player transport (HubMiniPlayerChrome owns controls).
        expanded
    }

    /// 1 = full player chrome; 0 = fully faded (mirrors meta chrome under the video).
    /// Mini: always 1 for the video layer (chrome is off via showTransportChrome).
    private var transportChromeOpacity: Double {
        if !expanded { return 1 }
        return Double(1 - min(1, max(0, appState.hubPlaybackPullProgress)))
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
                // Stay in the safe area — video starts *below* the Dynamic Island, never under it.
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    dragOffset = 0
                    isPullingMinimize = false
                    preferMiniFill = false
                    appState.hubPlaybackPullProgress = 0
                }
            } else {
                // Morph already owns dragOffset→0 in the gesture end. Don't re-animate here
                // (double animation made grab-to-mini feel sluggish).
                preferMiniFill = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !appState.hubPlaybackExpanded else { return }
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        isPullingMinimize = false
                        dragOffset = 0
                        appState.hubPlaybackPullProgress = 0
                    }
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
                // Ink bed so mini never shows white letterbox while video fills.
                Theme.ink
                playerSurface(
                    for: post,
                    showControls: showTransportChrome,
                    chromeOpacity: transportChromeOpacity
                )
                    .frame(width: layout.width, height: layout.height)
                    .clipped()

                // Mini chrome lives on YouTubeMiniPlayerBar (above this layer) so buttons work.
            }
            .frame(width: layout.width, height: layout.height)
            .background(Theme.ink)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: isPullingMinimize ? 12 : 0,
                    style: .continuous
                )
            )
            .clipped()
            .offset(x: layout.x, y: liveY)
            // No implicit .animation on geometry — those stacked with withAnimation and
            // made pull-to-mini feel sluggish. Finger: Transaction disablesAnimations.
            // Release: single withAnimation(MatteryaMotion.minimize) in the gesture end.
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
            // This layer is laid out in the safe area (no ignoresSafeArea).
            // y = 0 is already the first point *below* the Dynamic Island — do not add
            // safeAreaInsets.top again (that left a large empty gap under the island).
            let stageHeight = YouTubeMediaLayout.hubsExpandedStageHeight(
                containerWidth: geo.size.width
            )
            return PlayerLayout(
                x: 0,
                y: 0,
                width: geo.size.width,
                height: max(120, stageHeight)
            )
        }

        // Mini: full-bleed strip matching YouTubeMiniPlayerBar — same size as the clear hole.
        let barW = max(1, geo.size.width)
        let size = YouTubeMiniPlayerBar.videoSize(forBarWidth: barW)
        // Default: fixed strip above the tab bar (stable — no preference-key lag mid-morph).
        var y = max(0, geo.size.height - floatingBottomClearance - size.height)
        // Chat dock only: follow the message bubble hole once reported.
        if hasChatDockSlot, let global = dockSlotGlobal {
            let containerGlobal = geo.frame(in: .global)
            let dockY = global.minY - containerGlobal.minY
            let dockH = global.height
            if dockH > 40, dockH < 280,
               dockY > -20, dockY + size.height <= geo.size.height + 48 {
                y = dockY
            }
        }
        // Full width × bar height — aspect-fill paints edge-to-edge in this rect.
        return PlayerLayout(x: 0, y: y, width: size.width, height: size.height)
    }

    // MARK: - Player

    @ViewBuilder
    private func playerSurface(
        for post: CountryPost,
        showControls: Bool,
        chromeOpacity: Double = 1
    ) -> some View {
        let stored = YouTubeCatalogService.shared.playbackPosition(for: post.id)
        let resumeAt = stored > 3 ? stored : 0
        // Mini + expanded: always aspect-fill the container (no letterbox).
        let mustFill = true
        if let url = post.playableVideoURL {
            MatteryaHubPlayerView(
                url: url,
                posterURL: post.posterImageURL,
                isActive: appState.hubPlaybackPlaying,
                startTime: resumeAt,
                postID: post.id,
                showsControls: showControls,
                loops: false,
                fillsFrame: mustFill,
                chromeOpacity: chromeOpacity,
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
                seekToSeconds: miniSeekToSeconds,
                onSeekConsumed: { miniSeekToSeconds = nil }
            )
            // Stable id — remounting on expand/mini would restart audio (never do that).
            .id("hub-continuous-\(post.id)")
        } else {
            YouTubeVideoThumbnail(
                post: post,
                maxPixelSize: showControls ? 900 : 420,
                showsPlayIcon: false,
                frameStyle: .feed,
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
        // minimumDistance 4 — engage instantly on a real grab (8 felt sticky).
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard expanded else { return }
                var offset = dragOffset
                var dragging = isPullingMinimize
                MatteryaPullDownDismiss.applyChanged(value, offset: &offset, isDragging: &dragging)
                // Progress from *raw* finger Y so fade is a true 1:1 slider (not rubber-band).
                let progress = dragging
                    ? MatteryaPullDownDismiss.pullProgress(forVertical: value.translation.height)
                    : 0
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    dragOffset = offset
                    isPullingMinimize = dragging
                    appState.hubPlaybackPullProgress = progress
                }
            }
            .onEnded { value in
                guard expanded else {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        dragOffset = 0
                        isPullingMinimize = false
                        appState.hubPlaybackPullProgress = 0
                    }
                    return
                }
                // Moment finger leaves: if not still “up”, commit mini immediately.
                // Never zero dragOffset while still expanded — that hangs the video mid-screen.
                let shouldMini = MatteryaPullDownDismiss.shouldMinimizeOnRelease(
                    value,
                    dragOffset: dragOffset,
                    pullProgress: appState.hubPlaybackPullProgress
                )
                if shouldMini {
                    ReelsTwistHaptics.pullDismiss()
                    // Commit mini on this frame: pullProgress=1 fades watch chrome; home underlay
                    // is already painted (no white). One short easeOut for geometry only.
                    var lock = Transaction()
                    lock.disablesAnimations = true
                    withTransaction(lock) {
                        appState.hubPlaybackPullProgress = 1
                        preferMiniFill = true
                    }
                    withAnimation(Self.minimizeMorphAnim) {
                        // animated:false → expanded flips inside this withAnimation only once.
                        appState.minimizeHubPlayback(returnToChat: true, animated: false)
                        dragOffset = 0
                    }
                } else {
                    // Release still “up” — chrome snaps back.
                    withAnimation(MatteryaMotion.micro) {
                        dragOffset = 0
                        isPullingMinimize = false
                        appState.hubPlaybackPullProgress = 0
                    }
                }
            }
    }
}
