import SwiftUI
import UIKit

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

// MARK: - YouTube-smooth continuous Hubs player

/// Single continuous hubs AVPlayer for the whole app — **YouTube geometry model**.
///
/// One surface, one AVPlayer, three destinations interpolated by continuous progress:
/// - `collapse` 0…1 → watch stage ↔ mini strip (finger 1:1, spring on release)
/// - `fsProgress` 0…1 → watch stage ↔ full window (finger 1:1, spring on release)
///
/// Never remounts for fullscreen. Never spawns a second player. Landscape uses
/// free UIKit axes when possible; content rotation only when the system lock
/// keeps the interface portrait (and never both at once).
struct GlobalHubPlaybackLayer: View {
    @Environment(AppState.self) private var appState

    var dockSlotGlobal: CGRect? = nil
    var watchStageGlobal: CGRect? = nil

    /// 0 = full watch stage, 1 = mini dock.
    @State private var collapse: CGFloat = 0
    /// 0 = watch stage, 1 = immersive fullscreen. Same continuous player.
    @State private var fsProgress: CGFloat = 0
    @State private var isDragging = false
    @State private var isFSDragging = false
    @State private var miniCurrentSeconds: Double = 0
    @State private var miniDurationSeconds: Double = 0
    @State private var miniSeekToSeconds: Double? = nil
    /// Debounce open so swipe + button + meta token cannot double-fire.
    @State private var fullscreenGate = false
    /// Content rotation only when UIKit cannot leave portrait (system lock).
    @State private var contentRotation: Angle = .zero
    @State private var useLandscapeLayout = false

    private var expanded: Bool { appState.hubPlaybackExpanded }

    /// True once mostly fullscreen — unlocks landscape + hides status bar.
    private var isHubFullscreen: Bool { fsProgress > 0.88 }

    /// Any measured mini hole (floating bar OR chat dock) — not chat-only.
    /// Floating mini used to ignore dockSlotGlobal → film misaligned → solid black ink bed.
    private var hasMiniDockSlot: Bool {
        !expanded
            && fsProgress < 0.05
            && dockSlotGlobal != nil
            && (dockSlotGlobal?.width ?? 0) > 8
            && (dockSlotGlobal?.height ?? 0) > 8
    }

    private var floatingBottomClearance: CGFloat {
        if fsProgress > 0.2 { return 0 }
        if hasMiniDockSlot { return 0 }
        if collapse > 0.5 || !expanded, appState.navigationPath.isEmpty {
            return Theme.tabBarHeight
        }
        return 0
    }

    private var showTransportChrome: Bool {
        // Mini strip never shows transport (HubMiniPlayerChrome owns play/mute/close).
        if !expanded || collapse > 0.55 { return false }
        if fsProgress > 0.5 { return true }
        return true
    }

    private var transportChromeOpacity: Double {
        // Mini: fully hide player chrome so no black dim / scrubber slab paints over film.
        if !expanded || collapse > 0.55 { return 0 }
        if fsProgress > 0.01 {
            return Double(min(1, max(0.35, fsProgress)))
        }
        return Double(1 - min(1, max(0, collapse)))
    }

    /// Mini (and mid-collapse) must **fill** the strip — aspect-fit letterbox reads as black.
    private var filmFillsFrame: Bool {
        if fsProgress > 0.5 { return false } // FS: fit full picture
        if !expanded { return true }
        return collapse > 0.2
    }

    private var mutedBinding: Binding<Bool> {
        Binding(
            get: { appState.hubPlaybackMuted },
            set: { appState.hubPlaybackMuted = $0 }
        )
    }

    /// Global film rect for hit-testing — **only** this region intercepts touches.
    /// Comments under the video, feed above mini, and mini chrome buttons sit outside
    /// and must receive events (pass-through returns nil).
    private var interactiveHitGlobal: CGRect {
        let full = Self.windowGlobalFrame()

        // Immersive FS — whole window is the player.
        if fsProgress > 0.5 {
            return full
        }

        // Mini session — dock hole only (never the full bar chrome buttons region if
        // preference is late; still clamp to bottom strip so we don't eat the whole screen).
        if !expanded || collapse > 0.85 {
            if let dock = dockSlotGlobal, dock.width > 20, dock.height > 20 {
                // Inset slightly so play/mute/close chips on the bar edge stay hittable
                // even if z-order races the continuous film for one frame.
                return dock.insetBy(dx: 0, dy: 0)
            }
            let barH = YouTubeMiniPlayerBar.barHeight
            let tabH: CGFloat = appState.navigationPath.isEmpty ? Theme.tabBarHeight : 0
            return CGRect(
                x: full.minX,
                y: full.maxY - tabH - barH,
                width: full.width,
                height: barH
            )
        }

        // Expanded watch stage — measured hole only (never full window).
        if let stage = watchStageGlobal, stage.width > 40, stage.height > 80 {
            return stage
        }

        // Fallback: top stage strip (16:9-ish) — still leaves comments free.
        let stageH = YouTubeMediaLayout.hubsExpandedStageHeight(
            containerWidth: full.width,
            videoAspect: appState.hubPlaybackVideoAspect
        )
        let top = YouTubeMediaLayout.keyWindowSafeTop
        return CGRect(x: full.minX, y: full.minY + top, width: full.width, height: stageH)
    }

    var body: some View {
        Group {
            if let post = appState.hubPlaybackPost {
                // OUTERMOST = pass-through gated on global film rect.
                // GeometryReader lives *inside* so it can never claim comment / feed / mini taps.
                HubPassThroughContainer(
                    interactiveRectGlobal: interactiveHitGlobal,
                    contentID: post.id
                ) {
                    ZStack {
                        if fsProgress > 0.02 {
                            Color.black
                                .opacity(Double(min(1, max(0, fsProgress))))
                                .ignoresSafeArea(.all)
                                .allowsHitTesting(false)
                        }

                        GeometryReader { geo in
                            let layout = playerLayout(in: geo)
                            videoStack(post: post, layout: layout, containerSize: geo.size)
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .ignoresSafeArea(.all)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .zIndex(fsProgress > 0.15 ? 500 : 0)
            }
        }
        .onAppear {
            collapse = expanded ? 0 : 1
            fsProgress = 0
            syncPullProgressFromCollapse()
        }
        .onChange(of: expanded) { _, isExpanded in
            isDragging = false
            isFSDragging = false
            if isExpanded {
                appState.hubPlaybackPullProgress = 0
                withAnimation(MatteryaMotion.ytExpand) {
                    collapse = 0
                }
            } else {
                if fsProgress > 0.01 { closeFullscreen(animated: false) }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    collapse = 1
                    fsProgress = 0
                }
                appState.hubFullscreenPullProgress = 0
                if appState.hubPlaybackPullProgress > 0.5 {
                    appState.hubPlaybackPullProgress = 0
                }
                // Mini handoff: re-assert paint + audio so the strip never stays black.
                appState.hubPlaybackPlaying = true
                MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                    userMuted: appState.hubPlaybackMuted
                )
                NotificationCenter.default.post(
                    name: .matteryaResumePlaybackAfterInterrupt,
                    object: nil
                )
                // Dock hole often measures one frame late — force fill gravity + audio again.
                Task { @MainActor in
                    for delay in [16_000_000, 80_000_000, 200_000_000, 400_000_000] as [UInt64] {
                        try? await Task.sleep(nanoseconds: delay)
                        guard appState.hubPlaybackPost != nil, !appState.hubPlaybackExpanded else { return }
                        // Snap layout state hard to mini every beat (no stuck mid-collapse).
                        collapse = 1
                        fsProgress = 0
                        appState.hubPlaybackPlaying = true
                        MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                            userMuted: appState.hubPlaybackMuted
                        )
                        NotificationCenter.default.post(
                            name: .matteryaResumePlaybackAfterInterrupt,
                            object: nil
                        )
                    }
                }
            }
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, _ in
            isDragging = false
            isFSDragging = false
            collapse = expanded ? 0 : 1
            fsProgress = 0
            appState.hubPlaybackPullProgress = 0
            appState.hubFullscreenPullProgress = 0
            miniCurrentSeconds = 0
            miniDurationSeconds = 0
            miniSeekToSeconds = nil
            contentRotation = .zero
            useLandscapeLayout = false
            lockPortraitAfterFullscreen()
        }
        .onChange(of: appState.hubPlaybackPlaying) { _, playing in
            guard playing, appState.hubPlaybackPost != nil else { return }
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
        .onChange(of: appState.hubPlaybackFullscreenToken) { _, _ in
            guard fsProgress < 0.9, expanded, collapse < 0.35, appState.hubPlaybackPost != nil else { return }
            openFullscreenSeamless()
        }
        .onChange(of: appState.hubExpandToken) { _, _ in
            guard appState.hubPlaybackPost != nil else { return }
            isDragging = false
            isFSDragging = false
            if fsProgress > 0.01 { closeFullscreen(animated: false) }
            appState.hubPlaybackPullProgress = 0
            withAnimation(MatteryaMotion.ytExpand) {
                collapse = 0
            }
            appState.hubPlaybackPlaying = true
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
        .onChange(of: appState.hubFullscreenPullProgress) { _, pull in
            // Meta grab drives the same continuous morph as player swipe-up (YT).
            // Skip while FS is committed / opening so a zeroed pull cannot fight the spring.
            guard expanded, collapse < 0.2, !isFSDragging, !fullscreenGate else { return }
            guard fsProgress < 0.95 else { return }
            let p = min(1, max(0, pull))
            // Live 1:1 — no animation lag while finger is down.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                fsProgress = p
            }
        }
        .onChange(of: appState.hubMinimizeMorphToken) { _, _ in
            if fsProgress > 0.01 { closeFullscreen(animated: false) }
            guard expanded, appState.hubPlaybackPost != nil else {
                appState.finishMinimizeHubPlayback(returnToChat: appState.hubMinimizeReturnToChat)
                return
            }
            commitMinimize()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            guard isHubFullscreen else { return }
            withAnimation(MatteryaMotion.ytRotate) {
                applyContentOrientationFromDevice()
            }
        }
        .onChange(of: isHubFullscreen) { _, full in
            if full {
                unlockLandscapeForFullscreen()
                applyContentOrientationFromDevice()
            } else if fsProgress < 0.05 {
                lockPortraitAfterFullscreen()
                contentRotation = .zero
                useLandscapeLayout = false
            }
        }
    }

    // MARK: - Video stack

    @ViewBuilder
    private func videoStack(post: CountryPost, layout: PlayerLayout, containerSize: CGSize) -> some View {
        let screenW = containerSize.width
        let screenH = containerSize.height
        // Content rotation only when interface is still portrait under system lock.
        let filmW = (useLandscapeLayout && isHubFullscreen) ? max(screenW, screenH) : layout.width
        let filmH = (useLandscapeLayout && isHubFullscreen) ? min(screenW, screenH) : layout.height
        let scrimOpacity = Double(fsProgress) * max(0.35, 1 - Double(max(0, layout.y) / 480))

        ZStack(alignment: .topLeading) {
            // Full-window black under the film (covers any letterbox / safe-area residual).
            if fsProgress > 0.02 {
                Color.black
                    .frame(width: screenW, height: screenH)
                    .opacity(scrimOpacity)
                    .allowsHitTesting(false)
            }

            ZStack {
                // Mini: ink only as last resort under poster/film — never a solid black plate
                // that reads as “black overlay” when gravity is late.
                if filmFillsFrame {
                    Theme.ink
                } else {
                    Color.black
                }
                // Always keep poster under film in mini / collapse so a 1-frame dock lag
                // never shows empty ink.
                if filmFillsFrame || collapse > 0.2, let poster = post.posterImageURL {
                    CachedAsyncImage(
                        url: poster,
                        maxPixelSize: 900,
                        contentMode: .fill,
                        placeholder: AnyView(Theme.ink)
                    )
                    .frame(width: max(1, filmW), height: max(1, filmH))
                    .clipped()
                    .allowsHitTesting(false)
                }
                playerSurface(
                    for: post,
                    showControls: showTransportChrome,
                    chromeOpacity: transportChromeOpacity
                )
                .frame(width: max(1, filmW), height: max(1, filmH))
                .clipped()
            }
            .frame(width: max(1, filmW), height: max(1, filmH))
            .background(filmFillsFrame ? Theme.ink : Color.black)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius(for: layout),
                    style: .continuous
                )
            )
            .clipped()
            .rotationEffect(contentRotation)
            .frame(width: max(1, layout.width), height: max(1, layout.height))
            .offset(x: layout.x, y: layout.y)
            // Finger 1:1 while dragging; YT spring only on settle.
            .animation(interactiveAnimation, value: collapse)
            .animation(interactiveAnimation, value: fsProgress)
            .simultaneousGesture(playerDragGesture)
            // Stable identity — never remount across stage / FS / mini.
            .id("global-hub-continuous-\(post.id)")
        }
        .frame(width: screenW, height: screenH, alignment: .topLeading)
        .background(fsProgress > 0.5 ? Color.black : Color.clear)
        .statusBarHidden(isHubFullscreen)
        .persistentSystemOverlays(isHubFullscreen ? .hidden : .automatic)
    }

    private var interactiveAnimation: Animation? {
        if isDragging || isFSDragging { return nil }
        return MatteryaMotion.ytMorph
    }

    private func cornerRadius(for layout: PlayerLayout) -> CGFloat {
        if fsProgress > 0.85 { return 0 }
        if collapse > 0.08 { return 12 }
        // Soften corners while mid-morph into FS.
        return max(0, 10 * (1 - fsProgress))
    }

    // MARK: - Layout (lerp stage ↔ fullscreen ↔ mini)

    private struct PlayerLayout {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func stageFrame(in geo: GeometryProxy) -> PlayerLayout {
        // Prefer measured watch-stage hole so expand lands on the real video rect.
        if expanded, let global = watchStageGlobal,
           global.width > 40, global.height > 80 {
            let container = geo.frame(in: .global)
            let x = global.minX - container.minX
            let y = global.minY - container.minY
            if y > -40, y + global.height <= geo.size.height + 80 {
                return PlayerLayout(
                    x: max(0, x),
                    y: max(0, y),
                    width: min(geo.size.width, global.width),
                    height: max(120, global.height)
                )
            }
        }
        let stageHeight = YouTubeMediaLayout.hubsExpandedStageHeight(
            containerWidth: geo.size.width,
            videoAspect: appState.hubPlaybackVideoAspect
        )
        return PlayerLayout(
            x: 0,
            y: 0,
            width: geo.size.width,
            height: max(120, stageHeight)
        )
    }

    private func fullscreenFrame(in geo: GeometryProxy) -> PlayerLayout {
        // Prefer the GeometryReader's own size when it already spans the key window
        // (layer uses ignoresSafeArea). Mapping window→local with a mismatched container
        // was pushing the film down and cropping bottom transport chrome.
        let full = Self.windowGlobalFrame()
        let container = geo.frame(in: .global)
        let sizeMatch =
            abs(container.width - full.width) < 4
            && abs(container.height - full.height) < 4
            && abs(geo.size.width - full.width) < 4
            && abs(geo.size.height - full.height) < 4
        if sizeMatch {
            return PlayerLayout(x: 0, y: 0, width: geo.size.width, height: geo.size.height)
        }
        // Fallback: map full window into this container's local space.
        return PlayerLayout(
            x: full.minX - container.minX,
            y: full.minY - container.minY,
            width: full.width,
            height: full.height
        )
    }

    private func miniFrame(in geo: GeometryProxy) -> PlayerLayout {
        let container = geo.frame(in: .global)
        let full = Self.windowGlobalFrame()
        let barH = YouTubeMiniPlayerBar.barHeight
        let tabH: CGFloat = appState.navigationPath.isEmpty ? Theme.tabBarHeight : 0

        // Prefer live measured mini hole (floating bar or chat dock).
        if let dock = dockSlotGlobal, dock.width > 20, dock.height > 20 {
            var x = dock.minX - container.minX
            var y = dock.minY - container.minY
            // If coordinate spaces disagree (hosting vs window), fall back to window bottom.
            let looksOffScreen =
                y + dock.height < -20
                || y > geo.size.height + 20
                || x + dock.width < -20
                || x > geo.size.width + 20
            if !looksOffScreen {
                return PlayerLayout(
                    x: x,
                    y: y,
                    width: max(1, dock.width),
                    height: max(1, min(dock.height, barH + 8))
                )
            }
        }

        // Fallback: bottom strip of the window (matches MainTabView mini + tab bar stack).
        let yGlobal = full.maxY - tabH - barH
        return PlayerLayout(
            x: full.minX - container.minX,
            y: yGlobal - container.minY,
            width: max(1, full.width),
            height: barH
        )
    }

    /// Full key-window frame in global coordinates.
    private static func windowGlobalFrame() -> CGRect {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
        else {
            return UIScreen.main.bounds
        }
        // bounds in window space → global
        return window.convert(window.bounds, to: nil)
    }

    private func playerLayout(in geo: GeometryProxy) -> PlayerLayout {
        // Fullscreen morph wins over mini while active (YT never minis while FS).
        if fsProgress > 0.001 {
            let a = stageFrame(in: geo)
            let b = fullscreenFrame(in: geo)
            let t = smoothstep(fsProgress)
            return lerp(a, b, t: t)
        }

        // Snap hard to mini when mostly collapsed or already mini session.
        if !expanded || collapse > 0.92 {
            return miniFrame(in: geo)
        }

        let t = smoothstep(min(1, max(0, collapse)))
        let a = stageFrame(in: geo)
        let b = miniFrame(in: geo)
        return lerp(a, b, t: t)
    }

    private func lerp(_ a: PlayerLayout, _ b: PlayerLayout, t: CGFloat) -> PlayerLayout {
        PlayerLayout(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    /// Smooth hermite ease — YouTube-like settle without linear stiffness.
    private func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    // MARK: - Player (same instance always)

    @ViewBuilder
    private func playerSurface(
        for post: CountryPost,
        showControls: Bool,
        chromeOpacity: Double = 1
    ) -> some View {
        let stored = YouTubeCatalogService.shared.playbackPosition(for: post.id)
        let resumeAt = stored > 3 ? stored : 0
        if let url = post.playableVideoURL {
            MatteryaHubPlayerView(
                url: url,
                posterURL: post.posterImageURL,
                // Keep surface active for whole hubs session (mini/tab morph must not deactivate).
                // Play/pause follows hubPlaybackPlaying; false only from user chrome.
                isActive: appState.hubPlaybackPlaying,
                startTime: resumeAt,
                postID: post.id,
                showsControls: showControls,
                loops: false,
                // YT: aspect-fit on stage + FS. Mini / collapse **must fill** or letterbox = black.
                fillsFrame: filmFillsFrame,
                chromeOpacity: chromeOpacity,
                isMuted: mutedBinding,
                allowsFullscreen: expanded && collapse < 0.4,
                presentFullscreen: .constant(false),
                onRequestFullscreen: {
                    if isHubFullscreen {
                        closeFullscreen(animated: true)
                    } else {
                        guard expanded, collapse < 0.35 else { return }
                        openFullscreenSeamless()
                    }
                },
                isContinuousHubPlayer: true,
                isFullscreenActive: isHubFullscreen,
                onReady: {
                    Task { await PostsService.shared.recordView(post) }
                    // Re-assert solo after ready so tab silence always has a keep target.
                    MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                        userMuted: appState.hubPlaybackMuted
                    )
                    if appState.hubPlaybackPlaying {
                        NotificationCenter.default.post(
                            name: .matteryaResumePlaybackAfterInterrupt,
                            object: nil
                        )
                    }
                },
                onPlayingChange: { playing in
                    // Continuous: stalls no longer emit false (see MatteryaHubPlayerView).
                    // true → keep AppState playing; false → intentional chrome pause.
                    appState.hubPlaybackPlaying = playing
                },
                onProgress: { current, duration in
                    // Throttle @State — 4Hz is enough for mini chrome; 0.25s ticks re-bodied the layer.
                    if abs(current - miniCurrentSeconds) >= 0.35 {
                        miniCurrentSeconds = current
                    }
                    if duration > 0.25, abs(duration - miniDurationSeconds) > 0.5 {
                        miniDurationSeconds = duration
                    }
                },
                onVideoSize: { size in
                    appState.noteHubPlaybackVideoSize(size)
                },
                seekToSeconds: miniSeekToSeconds,
                onSeekConsumed: { miniSeekToSeconds = nil }
            )
            // Identity must stay stable — do not key on fs/collapse.
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

    // MARK: - Gestures (YouTube)

    /// Unified vertical drag:
    /// - FS: drag **up** → shrink fsProgress (exit)
    /// - Stage: drag up → grow fsProgress (enter FS)
    /// - Stage: drag down → collapse to mini
    /// - Mini: drag up → maximize
    private var playerDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                let y = value.translation.height
                let x = abs(value.translation.width)
                guard abs(y) > x * 0.55 else { return }

                // ── Fullscreen active: swipe **up** exits 1:1 (not down) ──
                if fsProgress > 0.5 {
                    if y < 0 {
                        isFSDragging = true
                        // Map upward pull to remaining progress (1 → 0).
                        let p = 1 - min(1, max(0, -y / 280))
                        setFSProgress(p, animated: false)
                    }
                    return
                }

                // ── Expanded stage (gesture only fires inside film hit-rect) ──
                if expanded, collapse < 0.98 {
                    if y < 0, collapse < 0.08, fsProgress < 0.08 {
                        // Swipe up on **video only** → live fullscreen morph (YT).
                        // Never armed from comments — pass-through keeps meta pans off this gesture.
                        isFSDragging = true
                        isDragging = false
                        let p = min(1, max(0, -y / 220))
                        setFSProgress(p, animated: false)
                        return
                    }
                    if y > 0, fsProgress < 0.08 {
                        // Swipe down → live mini morph.
                        if !isDragging {
                            guard y > 6 else { return }
                            isDragging = true
                        }
                        isFSDragging = false
                        let progress = MatteryaPullDownDismiss.pullProgress(forVertical: y)
                        applyCollapse(progress, animated: false)
                    } else if isDragging, y <= 0 {
                        let progress = MatteryaPullDownDismiss.pullProgress(forVertical: max(0, y))
                        applyCollapse(progress, animated: false)
                    }
                }
            }
            .onEnded { value in
                let y = value.translation.height
                let x = abs(value.translation.width)
                let predicted = value.predictedEndTranslation.height
                let wasFS = isFSDragging
                isDragging = false
                isFSDragging = false

                // ── Fullscreen morph settle: swipe **up** exits ──
                if wasFS || fsProgress > 0.12 {
                    let flingUp = predicted < -160 || y < -100
                    let flingDown = predicted > 100 || y > 36
                    // Exit on upward fling or if progress collapsed past threshold.
                    if flingUp || (fsProgress < 0.42 && !flingDown) {
                        closeFullscreen(animated: true)
                    } else {
                        openFullscreenSeamless()
                    }
                    return
                }

                // ── Mini: swipe up → maximize ──
                if !expanded || collapse > 0.85 {
                    if y < -28 || predicted < -80 {
                        ReelsTwistHaptics.pullDismiss()
                        appState.expandHubPlayback()
                    }
                    return
                }

                guard expanded else { return }
                guard abs(y) > x * 0.45 else {
                    withAnimation(MatteryaMotion.ytExpand) {
                        collapse = 0
                        appState.hubPlaybackPullProgress = 0
                    }
                    return
                }

                // ── Stage: swipe up on video → fullscreen ──
                if y < -36 || predicted < -120 {
                    openFullscreenSeamless()
                    return
                }

                // ── Stage: swipe down → mini ──
                let shouldMini = MatteryaPullDownDismiss.shouldMinimizeOnRelease(
                    value,
                    dragOffset: max(0, y),
                    pullProgress: collapse
                )
                if shouldMini {
                    ReelsTwistHaptics.pullDismiss()
                    commitMinimize()
                } else {
                    withAnimation(MatteryaMotion.ytExpand) {
                        collapse = 0
                        appState.hubPlaybackPullProgress = 0
                    }
                }
            }
    }

    private func setFSProgress(_ p: CGFloat, animated: Bool) {
        let clamped = min(1, max(0, p))
        if animated {
            withAnimation(MatteryaMotion.ytMorph) {
                fsProgress = clamped
            }
            appState.hubFullscreenPullProgress = clamped
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                fsProgress = clamped
            }
            // Sparse FS pull publish (meta grab already throttled in AppState setter).
            if abs(clamped - appState.hubFullscreenPullProgress) > 0.05 {
                appState.hubFullscreenPullProgress = clamped
            }
        }
    }

    private func applyCollapse(_ progress: CGFloat, animated: Bool) {
        let p = min(1, max(0, progress))
        if animated {
            withAnimation(MatteryaMotion.ytMorph) {
                collapse = p
            }
            // Threshold publish only — continuous AppState writes re-bodyed whole home+watch.
            publishPullProgressIfNeeded(p)
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                collapse = p
            }
            publishPullProgressIfNeeded(p)
        }
    }

    /// Publish pull progress sparsely so YouTubeAppView opacity doesn't rebuild 60×/s.
    private func publishPullProgressIfNeeded(_ p: CGFloat) {
        let published = appState.hubPlaybackPullProgress
        // Buckets: 0, ~0.15 (start hide home), ~0.5, ~0.85, 1
        let bucket: CGFloat
        if p < 0.08 { bucket = 0 }
        else if p < 0.35 { bucket = 0.2 }
        else if p < 0.65 { bucket = 0.5 }
        else if p < 0.92 { bucket = 0.85 }
        else { bucket = 1 }
        if abs(bucket - published) > 0.04 {
            appState.hubPlaybackPullProgress = bucket
        }
    }

    private func syncPullProgressFromCollapse() {
        appState.hubPlaybackPullProgress = expanded ? collapse : 0
    }

    /// Commit to immersive fullscreen — same AVPlayer, spring morph only.
    private func openFullscreenSeamless() {
        guard !fullscreenGate else {
            // Already opening — just ensure we land at 1.
            setFSProgress(1, animated: true)
            return
        }
        fullscreenGate = true
        appState.hubPlaybackPlaying = true
        collapse = 0
        appState.hubPlaybackPullProgress = 0
        withAnimation(MatteryaMotion.ytMorph) {
            fsProgress = 1
            appState.hubFullscreenPullProgress = 1
        }
        unlockLandscapeForFullscreen()
        applyContentOrientationFromDevice()
        NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            fullscreenGate = false
        }
    }

    private func closeFullscreen(animated: Bool) {
        let finish = {
            fsProgress = 0
            appState.hubFullscreenPullProgress = 0
            contentRotation = .zero
            useLandscapeLayout = false
            collapse = 0
        }
        if animated {
            withAnimation(MatteryaMotion.ytMorph) { finish() }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { finish() }
        }
        // Always clear AppState FS pull so MainTabView doesn't keep immersive chrome hidden
        // (that was wiping mini play/mute/close after exit).
        appState.hubFullscreenPullProgress = 0
        lockPortraitAfterFullscreen()
        appState.hubPlaybackPlaying = true
        NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
    }

    // MARK: - Orientation

    private func unlockLandscapeForFullscreen() {
        AppDelegate.orientationLock = .allButUpsideDown
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        Self.refreshSupportedOrientations()
        // Free axes only — never force landscape then revert (YT doesn't thrash geometry).
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .allButUpsideDown)) { _ in }
        }
    }

    private func lockPortraitAfterFullscreen() {
        AppDelegate.orientationLock = .portrait
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        Self.refreshSupportedOrientations()
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        }
    }

    /// Content rotation **only** when UIKit interface is still portrait but the phone is landscape.
    /// If the interface already rotated, geometry handles it — never double-rotate.
    private func applyContentOrientationFromDevice() {
        guard isHubFullscreen else {
            contentRotation = .zero
            useLandscapeLayout = false
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        switch scene.interfaceOrientation {
        case .landscapeLeft, .landscapeRight:
            // UIKit already landscape — film fills geo; no content rotation.
            contentRotation = .zero
            useLandscapeLayout = false
            return
        default:
            break
        }

        // Interface stuck in portrait (Control Center lock) — rotate content with device.
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            contentRotation = .degrees(90)
            useLandscapeLayout = true
        case .landscapeRight:
            contentRotation = .degrees(-90)
            useLandscapeLayout = true
        case .portraitUpsideDown:
            contentRotation = .degrees(180)
            useLandscapeLayout = false
        case .portrait:
            contentRotation = .zero
            useLandscapeLayout = false
        default:
            // faceUp / unknown — keep last stable orientation.
            break
        }
    }

    private static func refreshSupportedOrientations() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        for window in scene.windows {
            var vc: UIViewController? = window.rootViewController
            while let current = vc {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                vc = current.presentedViewController
            }
        }
    }

    /// Animate collapse → 1, then flip session to mini without a second layout jump.
    private func commitMinimize() {
        if fsProgress > 0.01 { closeFullscreen(animated: false) }
        // Belt-and-suspenders: never leave immersive FS flags stuck over mini chrome.
        fsProgress = 0
        appState.hubFullscreenPullProgress = 0
        // Audio must keep running through the morph.
        appState.hubPlaybackPlaying = true
        MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
            userMuted: appState.hubPlaybackMuted
        )
        let returnToChat = appState.hubMinimizeReturnToChat
        withAnimation(MatteryaMotion.ytMorph) {
            collapse = 1
            appState.hubPlaybackPullProgress = 1
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                collapse = 1
            }
            appState.finishMinimizeHubPlayback(returnToChat: returnToChat)
            var t2 = Transaction()
            t2.disablesAnimations = true
            withTransaction(t2) {
                collapse = 1
            }
            // After chrome mounts: re-solo (tab/feed may have stolen focus mid-morph).
            appState.hubPlaybackPlaying = true
            MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                userMuted: appState.hubPlaybackMuted
            )
            NotificationCenter.default.post(
                name: .matteryaResumePlaybackAfterInterrupt,
                object: nil
            )
        }
    }
}
