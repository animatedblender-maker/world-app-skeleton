import AVFoundation
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
    /// Morph-first minimize: use mini layout while `hubPlaybackExpanded` is still true
    /// so watch chrome can clear before the session flips (no canvas/grey hole).
    @State private var forceMiniLayout = false
    /// Ignore pause blips for a beat after morph (layout settle used to clear hubPlaybackPlaying).
    @State private var ignorePauseUntil: Date = .distantPast

    private var expanded: Bool { appState.hubPlaybackExpanded }
    private var landscapeFullscreen: Bool { appState.hubPlaybackLandscapeFullscreen }
    private var docked: Bool { appState.hubPlaybackDockInChat }
    /// Stage shows full watch only when expanded and not mid morph-to-mini.
    private var showExpandedStage: Bool { expanded && !forceMiniLayout }

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
        !showExpandedStage && !hasDockSlot && appState.navigationPath.isEmpty
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
                // Landscape FS: own the whole window (YouTube). Else clear the notch only.
                .ignoresSafeArea(edges: landscapeFullscreen ? .all : .top)
                .statusBarHidden(landscapeFullscreen)
                .persistentSystemOverlays(landscapeFullscreen ? .hidden : .automatic)
            }
        }
        // YouTube-smooth morph: spring the film frame only. Never animate on tab/nav path
        // (that re-laid out mini on every push). Pull-drag stays 1:1 (nil animation).
        .animation(isPullingMinimize ? nil : MatteryaMotion.ytMorph, value: forceMiniLayout)
        .animation(isPullingMinimize ? nil : MatteryaMotion.ytExpand, value: expanded)
        .animation(MatteryaMotion.ytMorph, value: landscapeFullscreen)
        // Never animate dock-slot appearance — bar mount after mini-land used to
        // re-tween the film and looked like a second hitch at the top-half stage.
        .animation(nil, value: hasDockSlot)
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded {
                // Session already mini — pin geometry, clear grab state.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    dragOffset = 0
                    isPullingMinimize = false
                    forceMiniLayout = false
                }
            } else {
                dragOffset = 0
                isPullingMinimize = false
                forceMiniLayout = false
            }
        }
        .onChange(of: appState.hubExpandToken) { _, _ in
            forceMiniLayout = false
            dragOffset = 0
            isPullingMinimize = false
        }
        .onChange(of: appState.hubMinimizeMorphToken) { _, _ in
            guard appState.hubPlaybackPost != nil else {
                appState.finishMinimizeHubPlayback(returnToChat: appState.hubMinimizeReturnToChat)
                return
            }
            commitMinimizeMorph()
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, _ in
            dragOffset = 0
            isPullingMinimize = false
            forceMiniLayout = false
        }
        .onChange(of: appState.hubPlaybackPlaying) { _, playing in
            // Only kick AV when leaving a true pause — morph/tab leave must not spam resume.
            guard playing, appState.hubPlaybackPost != nil else { return }
            guard MediaPlaybackCoordinator.shared.continuousHubPlayer?.rate ?? 0 < 0.05 else { return }
            MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                userMuted: appState.hubPlaybackMuted,
                rate: appState.hubPlaybackRate
            )
        }
    }

    /// Drive film into the mini strip, then flip session flags (morph-first — no grey hole).
    /// Same idea as YouTube: animate the player frame, keep AV rolling, flip chrome after land.
    private func commitMinimizeMorph() {
        let returnToChat = appState.hubMinimizeReturnToChat
        // Keep audio/video alive for the entire morph — never accept a pause blip.
        if !appState.hubPlaybackPlaying {
            appState.hubPlaybackPlaying = true
        }
        ignorePauseUntil = Date().addingTimeInterval(0.45)
        // Do NOT touch AppState here — pullProgress is already ≥ threshold from the
        // finger, and writing it again re-entered YouTubeAppView on the morph frame.
        // Animate ONLY local geometry from the current pull offset into the mini strip.
        withAnimation(MatteryaMotion.ytMorph) {
            forceMiniLayout = true
            isPullingMinimize = false
            dragOffset = 0
        }
        Task { @MainActor in
            // Match MatteryaMotion.ytMorph easeOut 0.22s — flip session once the film has landed.
            try? await Task.sleep(nanoseconds: 230_000_000)
            var pin = Transaction()
            pin.disablesAnimations = true
            withTransaction(pin) {
                forceMiniLayout = true
                dragOffset = 0
                isPullingMinimize = false
            }
            ignorePauseUntil = Date().addingTimeInterval(0.15)
            // Single finish — no AV reassert storm (was hitching mid-morph).
            appState.finishMinimizeHubPlayback(returnToChat: returnToChat)
        }
    }

    /// Pull / morph scrim — blur home behind the shrinking film.
    private var minimizeScrimVisible: Bool {
        // Only while the session is still expanded (incl. morph-first). Drop the
        // instant mini lands so the blur never sticks under the floating strip.
        !landscapeFullscreen
            && expanded
            && (isPullingMinimize || forceMiniLayout || appState.hubPlaybackPullProgress > 0.02)
    }

    private var minimizeScrimOpacity: Double {
        if forceMiniLayout { return 0.92 }
        let p = max(dragProgress, appState.hubPlaybackPullProgress)
        return Double(min(1, 0.15 + p * 0.85))
    }

    private var minimizeScrimInk: Double {
        if forceMiniLayout { return 0.22 }
        let p = max(dragProgress, appState.hubPlaybackPullProgress)
        return Double(min(0.28, 0.06 + p * 0.22))
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

            // Pre-warmed UIKit blur — always mounted (opacity 0 when idle) so the first
            // pull never pays UIVisualEffect creation cost (that was a 1–2s stall).
            HubMinimizeBlurBackdrop()
                .opacity(minimizeScrimVisible ? minimizeScrimOpacity : 0)
                .overlay(Theme.ink.opacity(minimizeScrimVisible ? minimizeScrimInk : 0))
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(isPullingMinimize ? nil : MatteryaMotion.ytMorph, value: minimizeScrimOpacity)
                .allowsHitTesting(false)

            // Film + mini chrome in ONE box, then offset together.
            // Chrome must not be `.overlay` after `.offset` — that left chips at y≈0 (top of screen).
            ZStack {
                playerSurface(
                    for: post,
                    showControls: (showExpandedStage || landscapeFullscreen) && !isPullingMinimize
                )
                    .frame(width: layout.width, height: layout.height)
                    // Never animate ink↔clear — SwiftUI interpolates that as a grey slab.
                    // Solid ink only while fully expanded and not grabbing/morphing.
                    .background(stageBackdrop)

                if !showExpandedStage, !landscapeFullscreen {
                    YouTubeMiniPlayerChrome(
                        isPlaying: playingBinding,
                        isMuted: mutedBinding,
                        onClose: { stop() }
                    )
                    .frame(width: layout.width, height: layout.height)
                }
            }
            .frame(width: layout.width, height: layout.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: (showExpandedStage && !landscapeFullscreen && isPullingMinimize) ? 12 : 0,
                    style: .continuous
                )
            )
            .shadow(
                color: (showExpandedStage && !landscapeFullscreen)
                    ? Theme.ink.opacity(isPullingMinimize ? 0.22 : 0)
                    : .clear,
                radius: (showExpandedStage && !landscapeFullscreen && isPullingMinimize) ? 16 : 0,
                y: (showExpandedStage && !landscapeFullscreen && isPullingMinimize) ? 8 : 0
            )
            .scaleEffect(
                (showExpandedStage && !landscapeFullscreen) ? pullScale : 1,
                anchor: .top
            )
            .offset(
                x: layout.x,
                y: layout.y + ((showExpandedStage && !landscapeFullscreen) ? dragOffset * 0.92 : 0)
            )
            .opacity(
                showExpandedStage && !landscapeFullscreen && isPullingMinimize
                    ? Double(1 - min(dragProgress * 0.12, 0.12))
                    : 1
            )
            .simultaneousGesture(minimizeGesture)
            .onTapGesture {
                // Mini / dock: tap video → maximize. Expanded / FS: transport owns taps.
                guard !showExpandedStage, !landscapeFullscreen else { return }
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
            y: layout.y + (showExpandedStage ? dragOffset : 0),
            width: layout.width,
            height: layout.height
        )
    }

    /// Solid ink only for settled expanded / FS. Clear during pull + morph so home
    /// shows through — never interpolate Theme.ink → Color.clear (grey slab).
    private var stageBackdrop: Color {
        if landscapeFullscreen { return Theme.ink }
        if showExpandedStage,
           !isPullingMinimize,
           appState.hubPlaybackPullProgress < 0.02 {
            return Theme.ink
        }
        return Color.clear
    }

    // MARK: - Layout

    private struct PlayerLayout {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func playerLayout(in geo: GeometryProxy) -> PlayerLayout {
        // YouTube landscape FS: same AVPlayer, full window, aspect-fit (letterbox OK).
        if landscapeFullscreen {
            return PlayerLayout(x: 0, y: 0, width: geo.size.width, height: geo.size.height)
        }
        if showExpandedStage {
            // Start directly under the notch (status bar), not overlapping it.
            let safeTop = geo.safeAreaInsets.top > 1
                ? geo.safeAreaInsets.top
                : YouTubeMediaLayout.keyWindowSafeTop
            let stageHeight = YouTubeMediaLayout.hubsContinuousStageHeight(
                containerWidth: geo.size.width,
                videoAspect: appState.hubPlaybackVideoAspect
            )
            return PlayerLayout(x: 0, y: safeTop, width: geo.size.width, height: stageHeight)
        }

        // Always target the **bottom mini strip first** so morph never parks mid-screen
        // waiting for the dock preference key.
        let barW = geo.size.width
        let size = YouTubeMiniPlayerBar.videoSize(forBarWidth: barW)
        let fallbackTop = max(0, geo.size.height - floatingBottomClearance - miniStripHeight)
        let fallback = PlayerLayout(
            x: YouTubeMiniPlayerBar.barContentLeading,
            y: fallbackTop + YouTubeMiniPlayerBar.videoEdgeInset,
            width: size.width,
            height: size.height
        )

        // Mini / chat dock: use the **exact** video-hole frame only when clearly bottom-band.
        if let global = dockSlotGlobal,
           global.width > 8, global.height > 8 {
            let containerGlobal = geo.frame(in: .global)
            let x = global.minX - containerGlobal.minX
            let y = global.minY - containerGlobal.minY
            let inBottomBand = y >= geo.size.height * 0.55
            let looksLikeMiniOrDock = global.height > 40
                && global.height < geo.size.height * 0.42
                && global.width > 40
                && (inBottomBand || hasDockSlot)
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

        return fallback
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

    private var rateBinding: Binding<Float> {
        Binding(
            get: { appState.hubPlaybackRate },
            set: { appState.hubPlaybackRate = $0 }
        )
    }

    @ViewBuilder
    private func playerSurface(for post: CountryPost, showControls: Bool) -> some View {
        // Resume from the furthest known playhead so Continue watching opens at the
        // last second watched (stored), while live feed handoff still wins via park.
        let parkedT = SparkWarmPool.shared.parkedPlayer(for: post.id)?.currentTime().seconds
        let stored = YouTubeCatalogService.shared.playbackPosition(for: post.id)
        let sharedStored: Double = {
            guard let shared = post.sharedPostID, shared != post.id else { return 0 }
            return YouTubeCatalogService.shared.playbackPosition(for: shared)
        }()
        let forced = appState.hubPlaybackForcedResumeSeconds
        let resumeAt: Double = {
            let parked = (parkedT?.isFinite == true && (parkedT ?? 0) > 0.05) ? (parkedT ?? 0) : 0
            let disk = max(stored, sharedStored, forced)
            // Prefer live mid-clip park when it's clearly ahead; otherwise disk resume.
            if parked > 0.45, parked + 1 >= disk { return parked }
            return disk > 0.05 ? disk : parked
        }()
        if let url = post.playableVideoURL {
            let posterCandidates: [URL?] = [
                Frame0PosterCache.url(for: post.id),
                MediaURLResolver.posterURL(for: post),
                post.posterImageURL,
            ]
            let poster = posterCandidates.compactMap { candidate -> URL? in
                guard let candidate, MediaURLResolver.isUsablePosterURL(candidate) else { return nil }
                return candidate
            }.first
            // One Hubs chrome for every long-form surface (R2 + Archive):
            // center play · −10s · +10s · bottom scrubber (MatteryaHubPlayerView).
            // Sparks pattern: Frame 0 poster under film until AV paints.
            ZStack {
                Color.black
                // Keep gravity stable while morphing — flipping fit↔fill mid-shrink pauses AV
                // and leaves a grey trail. Only fill once the session is settled mini.
                let settledMini = !appState.hubPlaybackExpanded
                    && !forceMiniLayout
                    && !landscapeFullscreen
                let morphing = forceMiniLayout || isPullingMinimize
                    || appState.hubPlaybackPullProgress > 0.02
                let fitFilm = !settledMini
                // Settled mini + mid-morph: AV layer alone. Poster decode/layout mid-shrink
                // was hitching the morph for a second or two.
                if !settledMini, !morphing {
                    if let poster {
                        CachedAsyncImage(
                            url: poster,
                            maxPixelSize: 720,
                            contentMode: fitFilm ? .fit : .fill,
                            placeholder: AnyView(Color.black)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .allowsHitTesting(false)
                    } else {
                        FrameZeroFallbackPoster(
                            postID: post.id,
                            videoURL: url,
                            fillsFrame: !fitFilm
                        )
                        .allowsHitTesting(false)
                    }
                }
                MatteryaHubPlayerView(
                    url: url,
                    posterURL: poster,
                    isActive: appState.hubPlaybackPlaying,
                    startTime: resumeAt,
                    postID: post.id,
                    showsControls: showControls,
                    loops: false,
                    // Always fit on the continuous player — flipping fit↔fill after minimize
                    // paused AV and lagged the morph. Mini letterboxes slightly; worth it.
                    fillsFrame: false,
                    isMuted: mutedBinding,
                    playbackRate: rateBinding,
                    allowsFullscreen: showControls,
                    isLandscapeFullscreen: landscapeFullscreen,
                    // Survive Sparks open/close — resume mid-clip without black remount.
                    protectAsContinuousHubs: true,
                    // Meta-pull / FS button → same-player landscape (no remount cover).
                    externalFullscreenToken: appState.hubPlaybackFullscreenToken,
                    onFullscreenToggle: {
                        if appState.hubPlaybackLandscapeFullscreen {
                            appState.exitHubLandscapeFullscreen()
                        } else {
                            appState.requestHubFullscreen()
                        }
                    },
                    onReady: {
                        Task { await PostsService.shared.recordView(post) }
                        if appState.shouldContinuePlayback(for: post.id)
                            || SparkWarmPool.shared.shouldContinueFromCurrentTime(postID: post.id)
                            || SparkWarmPool.shared.lastClaimWasContinuing {
                            PerformanceTelemetry.milestone(
                                "hubs_feed_handoff_first_frame",
                                surface: "hubs",
                                from: "hubs_feed_handoff_start",
                                meta: ["post": String(post.id.prefix(12))]
                            )
                            PerformanceTelemetry.flushSoon()
                            appState.clearContinuePlayback(for: post.id)
                        }
                        // Continue watching safety net: if we still opened behind the saved
                        // playhead (warm-pool claim raced ahead of seek), force seek now.
                        let target = max(resumeAt, appState.hubPlaybackForcedResumeSeconds)
                        if target > 1,
                           let live = MediaPlaybackCoordinator.shared.continuousHubPlayer {
                            let head = live.currentTime().seconds
                            if !(head.isFinite && head + 1.5 >= target) {
                                live.seek(
                                    to: CMTime(seconds: target, preferredTimescale: 600),
                                    toleranceBefore: .zero,
                                    toleranceAfter: .zero
                                ) { finished in
                                    guard finished else { return }
                                    DispatchQueue.main.async {
                                        if appState.hubPlaybackPlaying {
                                            live.safePlayImmediately(atRate: appState.hubPlaybackRate)
                                        }
                                        appState.hubPlaybackForcedResumeSeconds = 0
                                    }
                                }
                            } else {
                                appState.hubPlaybackForcedResumeSeconds = 0
                            }
                        }
                        // Re-assert play if something paused us during mount.
                        if appState.hubPlaybackPlaying {
                            NotificationCenter.default.post(
                                name: .matteryaResumePlaybackAfterInterrupt,
                                object: nil
                            )
                        }
                    },
                    onPlayingChange: { playing in
                        // Don't clear playing while Sparks is open (we paused intentionally).
                        if appState.reelsViewerContext != nil, !playing { return }
                        // Minimize morph / settle: ignore pause blips from layout churn.
                        if !playing,
                           forceMiniLayout
                            || isPullingMinimize
                            || appState.hubPlaybackPullProgress > 0.01
                            || Date() < ignorePauseUntil {
                            appState.hubPlaybackPlaying = true
                            NotificationCenter.default.post(
                                name: .matteryaResumePlaybackAfterInterrupt,
                                object: nil
                            )
                            return
                        }
                        appState.hubPlaybackPlaying = playing
                    },
                    onVideoSize: { size in
                        appState.noteHubPlaybackVideoSize(size)
                    }
                )
            }
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
        forceMiniLayout = false
        appState.expandHubPlayback()
    }

    private func stop() {
        dragOffset = 0
        isPullingMinimize = false
        forceMiniLayout = false
        appState.stopHubPlayback()
    }

    /// 0…1 progress while pulling expanded stage toward mini.
    private var dragProgress: CGFloat {
        min(max(dragOffset / 220, 0), 1)
    }

    /// Subtle shrink while dragging — eases into the mini morph.
    private var pullScale: CGFloat {
        guard showExpandedStage, isPullingMinimize else { return 1 }
        return 1 - dragProgress * 0.12
    }

    private var minimizeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard showExpandedStage, !landscapeFullscreen else { return }
                var offset = dragOffset
                var dragging = isPullingMinimize
                MatteryaPullDownDismiss.applyChanged(value, offset: &offset, isDragging: &dragging)
                let progress = dragging
                    ? MatteryaPullDownDismiss.pullProgress(forVertical: max(0, value.translation.height))
                    : 0
                // Local geometry every frame; AppState only when crossing the watch-drop
                // threshold (once) — continuous AppState writes rebuilt Hubs every tick.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    dragOffset = offset
                    isPullingMinimize = dragging
                    let previous = appState.hubPlaybackPullProgress
                    if dragging, previous < 0.05, progress >= 0.05 {
                        appState.setHubPlaybackPullProgress(0.05)
                    } else if !dragging, previous > 0 {
                        appState.setHubPlaybackPullProgress(0)
                    }
                }
            }
            .onEnded { value in
                guard showExpandedStage, !landscapeFullscreen else {
                    dragOffset = 0
                    isPullingMinimize = false
                    return
                }
                let shouldMini = MatteryaPullDownDismiss.shouldMinimizeOnRelease(
                    value,
                    dragOffset: dragOffset,
                    pullProgress: MatteryaPullDownDismiss.pullProgress(forOffset: dragOffset)
                )
                if shouldMini {
                    ReelsTwistHaptics.pullDismiss()
                    // One AppState write to drop watch chrome; keep dragOffset so the film
                    // does not snap back to the top-half stage before morph.
                    var pin = Transaction()
                    pin.disablesAnimations = true
                    withTransaction(pin) {
                        if appState.hubPlaybackPullProgress < 0.99 {
                            appState.hubPlaybackPullProgress = 1
                        }
                    }
                    appState.minimizeHubPlayback(returnToChat: true)
                } else {
                    withAnimation(MatteryaMotion.ytMorph) {
                        dragOffset = 0
                        isPullingMinimize = false
                        appState.hubPlaybackPullProgress = 0
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

/// Always-mounted system blur (UIKit). Opacity is faded by the parent — never create
/// the effect view on the pull/morph frame.
private struct HubMinimizeBlurBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
