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

/// Single continuous hubs AVPlayer for the whole app.
///
/// **Minimize model (flawless path):**
/// One continuous progress `collapse` 0…1 interpolates the player frame between
/// full watch stage and mini strip. Finger drag updates `collapse` 1:1.
/// On release we animate `collapse` → 1, then flip `hubPlaybackExpanded = false`
/// with animations disabled so layout does not jump a second time.
///
/// **Fullscreen:** same AVPlayer expands in place (no second player / fullScreenCover).
/// That avoids rebuffer pause + double-enter animation. Landscape uses content rotation
/// when the system orientation lock blocks UIKit rotation.
/// Hit-testing: only the video rect receives touches (UIKit pass-through host).
struct GlobalHubPlaybackLayer: View {
    @Environment(AppState.self) private var appState

    var dockSlotGlobal: CGRect? = nil
    var watchStageGlobal: CGRect? = nil

    /// 0 = full expanded stage, 1 = mini dock. Drives geometry every frame.
    @State private var collapse: CGFloat = 0
    @State private var isDragging = false
    @State private var miniCurrentSeconds: Double = 0
    @State private var miniDurationSeconds: Double = 0
    @State private var miniSeekToSeconds: Double? = nil
    /// In-place fullscreen on the continuous player (no second AVPlayer).
    @State private var isHubFullscreen = false
    /// Debounce so swipe + button + meta token cannot open twice.
    @State private var fullscreenGate = false
    /// YT-style content rotation when UIKit stays portrait under system lock.
    @State private var contentRotation: Angle = .zero
    @State private var useLandscapeLayout = false
    @State private var fsDismissDrag: CGFloat = 0

    private var expanded: Bool { appState.hubPlaybackExpanded }

    /// Chat dock only — floating mini uses a fixed bottom strip.
    private var hasChatDockSlot: Bool {
        !expanded
            && !isHubFullscreen
            && appState.hubPlaybackDockInChat
            && dockSlotGlobal != nil
            && (dockSlotGlobal?.width ?? 0) > 8
            && (dockSlotGlobal?.height ?? 0) > 8
    }

    private var floatingBottomClearance: CGFloat {
        if isHubFullscreen { return 0 }
        if hasChatDockSlot { return 0 }
        if collapse > 0.5 || !expanded, appState.navigationPath.isEmpty {
            return Theme.tabBarHeight
        }
        return 0
    }

    private var showTransportChrome: Bool {
        if isHubFullscreen { return true }
        // Hide in-player chrome once mostly collapsed (mini bar owns controls).
        return expanded && collapse < 0.55
    }

    private var transportChromeOpacity: Double {
        if isHubFullscreen { return 1 }
        if !expanded { return 1 }
        return Double(1 - min(1, max(0, collapse)))
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
                    let layout = playerLayout(in: geo, collapse: isHubFullscreen ? 0 : collapse)
                    let hitRect = isHubFullscreen
                        ? CGRect(origin: .zero, size: geo.size)
                        : CGRect(
                            x: layout.x,
                            y: layout.y,
                            width: layout.width,
                            height: layout.height
                        )

                    HubPassThroughContainer(interactiveRect: hitRect) {
                        videoStack(post: post, layout: layout, containerSize: geo.size)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Fullscreen sits above tabs / other chrome.
                .zIndex(isHubFullscreen ? 500 : 0)
            }
        }
        .onAppear {
            collapse = expanded ? 0 : 1
            syncPullProgressFromCollapse()
        }
        .onChange(of: expanded) { _, isExpanded in
            // External expand / session flip after morph-minimize.
            isDragging = false
            if isExpanded {
                // YouTube maximize: spring collapse 1 → 0 (full stage) immediately.
                appState.hubPlaybackPullProgress = 0
                // If already open, still re-assert full stage (tap maximize while mid-drag).
                withAnimation(MatteryaMotion.expand) {
                    collapse = 0
                }
            } else {
                // Leaving expanded → cannot stay fullscreen.
                if isHubFullscreen { closeFullscreen(animated: false) }
                // Session already mini — geometry must already be at strip (no white hole).
                // Never re-animate 0→1 here (that left a clear mini chrome over home paper).
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    collapse = 1
                }
                if appState.hubPlaybackPullProgress > 0.5 {
                    appState.hubPlaybackPullProgress = 0
                }
            }
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, _ in
            isDragging = false
            collapse = expanded ? 0 : 1
            appState.hubPlaybackPullProgress = 0
            miniCurrentSeconds = 0
            miniDurationSeconds = 0
            miniSeekToSeconds = nil
            if isHubFullscreen { closeFullscreen(animated: false) }
        }
        .onChange(of: appState.hubPlaybackPlaying) { _, playing in
            guard playing, appState.hubPlaybackPost != nil else { return }
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
        .onChange(of: appState.hubPlaybackFullscreenToken) { _, _ in
            // Meta-area drag / external request → fullscreen (YouTube).
            guard !isHubFullscreen, expanded, collapse < 0.35, appState.hubPlaybackPost != nil else { return }
            openFullscreenSeamless()
        }
        .onChange(of: appState.hubExpandToken) { _, _ in
            // Mini maximize — force spring even if expanded was already true.
            guard appState.hubPlaybackPost != nil else { return }
            isDragging = false
            if isHubFullscreen { closeFullscreen(animated: false) }
            appState.hubPlaybackPullProgress = 0
            withAnimation(MatteryaMotion.expand) {
                collapse = 0
            }
            appState.hubPlaybackPlaying = true
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
        .onChange(of: appState.hubFullscreenPullProgress) { _, _ in
            // Live layout morph while grabbing meta (no animation lag).
        }
        .onChange(of: appState.hubMinimizeMorphToken) { _, _ in
            // AppState requested morph-then-mini (close, tab leave, etc.).
            if isHubFullscreen { closeFullscreen(animated: false) }
            guard expanded, appState.hubPlaybackPost != nil else {
                appState.finishMinimizeHubPlayback(returnToChat: appState.hubMinimizeReturnToChat)
                return
            }
            commitMinimize()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            guard isHubFullscreen else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                applyContentOrientationFromDevice()
            }
        }
    }

    // MARK: - Video stack

    @ViewBuilder
    private func videoStack(post: CountryPost, layout: PlayerLayout, containerSize: CGSize) -> some View {
        let screenW = containerSize.width
        let screenH = containerSize.height
        // When content is rotated 90° under orientation lock, size the film to landscape bounds.
        let filmW = (isHubFullscreen && useLandscapeLayout) ? max(screenW, screenH) : layout.width
        let filmH = (isHubFullscreen && useLandscapeLayout) ? min(screenW, screenH) : layout.height

        ZStack(alignment: .topLeading) {
            if isHubFullscreen {
                Color.black
                    .frame(width: screenW, height: screenH)
                    .ignoresSafeArea()
                    .opacity(max(0.45, 1 - Double(fsDismissDrag / 420)))
            }

            ZStack {
                Theme.ink
                playerSurface(
                    for: post,
                    showControls: showTransportChrome,
                    chromeOpacity: transportChromeOpacity
                )
                .frame(width: filmW, height: filmH)
                .clipped()
            }
            .frame(width: filmW, height: filmH)
            .background(Theme.ink)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: isHubFullscreen ? 0 : (collapse > 0.08 ? 12 : 0),
                    style: .continuous
                )
            )
            .clipped()
            .rotationEffect(isHubFullscreen ? contentRotation : .zero)
            .frame(
                width: isHubFullscreen ? screenW : layout.width,
                height: isHubFullscreen ? screenH : layout.height
            )
            .offset(
                x: isHubFullscreen ? 0 : layout.x,
                y: isHubFullscreen ? max(0, fsDismissDrag) : layout.y
            )
            // Finger 1:1 while dragging; spring only on settle / expand.
            .animation(
                isDragging || isHubFullscreen
                    ? nil
                    : (expanded ? MatteryaMotion.expand : MatteryaMotion.minimize),
                value: collapse
            )
            // YouTube: pull down → mini · pull up (expanded) → fullscreen · pull up (mini) → expand.
            .simultaneousGesture(playerDragGesture)
            .id("global-hub-continuous-\(post.id)")
        }
        .statusBarHidden(isHubFullscreen)
    }

    // MARK: - Layout (lerp expanded ↔ mini)

    private struct PlayerLayout {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func expandedFrame(in geo: GeometryProxy) -> PlayerLayout {
        if isHubFullscreen {
            // Same continuous player, full window — no second presentation.
            return PlayerLayout(x: 0, y: 0, width: geo.size.width, height: geo.size.height)
        }
        // Stage height follows the clip’s natural aspect so aspect-fit never crops.
        let stageHeight = YouTubeMediaLayout.hubsExpandedStageHeight(
            containerWidth: geo.size.width,
            videoAspect: appState.hubPlaybackVideoAspect
        )
        // Pull-to-fullscreen morph: grow stage toward full screen while grabbing meta.
        let pull = min(1, max(0, appState.hubFullscreenPullProgress))
        let fullH = geo.size.height
        let h = max(120, stageHeight + (fullH - stageHeight) * pull)
        return PlayerLayout(
            x: 0,
            y: 0,
            width: geo.size.width,
            height: h
        )
    }

    private func miniFrame(in geo: GeometryProxy) -> PlayerLayout {
        let barW = max(1, geo.size.width)
        let size = YouTubeMiniPlayerBar.videoSize(forBarWidth: barW)
        var y = max(0, geo.size.height - floatingBottomClearance - size.height)
        if hasChatDockSlot, let global = dockSlotGlobal {
            let containerGlobal = geo.frame(in: .global)
            let dockY = global.minY - containerGlobal.minY
            let dockH = global.height
            if dockH > 40, dockH < 280,
               dockY > -20, dockY + size.height <= geo.size.height + 48 {
                y = dockY
            }
        }
        return PlayerLayout(x: 0, y: y, width: size.width, height: size.height)
    }

    private func playerLayout(in geo: GeometryProxy, collapse tRaw: CGFloat) -> PlayerLayout {
        if isHubFullscreen {
            return expandedFrame(in: geo)
        }
        let t = min(1, max(0, tRaw))
        // Ease slightly so the last bit settles cleanly into the mini strip.
        let tEased = t * t * (3 - 2 * t)
        let a = expandedFrame(in: geo)
        let b = miniFrame(in: geo)
        return PlayerLayout(
            x: a.x + (b.x - a.x) * tEased,
            y: a.y + (b.y - a.y) * tEased,
            width: a.width + (b.width - a.width) * tEased,
            height: a.height + (b.height - a.height) * tEased
        )
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
        if let url = post.playableVideoURL {
            MatteryaHubPlayerView(
                url: url,
                posterURL: post.posterImageURL,
                // Always the same continuous instance — never pause/mute for FS handoff.
                isActive: appState.hubPlaybackPlaying,
                startTime: resumeAt,
                postID: post.id,
                showsControls: showControls,
                loops: false,
                // Expanded + fullscreen: fit full picture (no crop). Mini strip: fill.
                fillsFrame: !isHubFullscreen && collapse > 0.55,
                chromeOpacity: chromeOpacity,
                isMuted: mutedBinding,
                // Expand / collapse icon on scrubber row.
                allowsFullscreen: isHubFullscreen || (collapse < 0.35 && expanded),
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
                frameStyle: .feed,
                embedsFrame: false
            )
        }
    }

    // MARK: - Gesture (YouTube mini + fullscreen)

    /// Unified vertical drag on the continuous player:
    /// - Fullscreen + drag **down** → exit fullscreen
    /// - Expanded + drag **down** → mini player
    /// - Expanded + drag **up** → landscape fullscreen (like YT)
    /// - Mini + drag **up** → maximize to full watch
    private var playerDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                let y = value.translation.height
                let x = abs(value.translation.width)
                // Horizontal pans ignored.
                guard abs(y) > x * 0.65 else { return }

                // Fullscreen dismiss drag (YT).
                if isHubFullscreen {
                    if y > 0, y > x * 0.55 {
                        fsDismissDrag = y
                    }
                    return
                }

                if expanded, collapse < 0.98 {
                    // Only track downward collapse while expanded (up is handled on end → FS).
                    if y > 0 {
                        if !isDragging {
                            guard y > 8 else { return }
                            isDragging = true
                        }
                        let progress = MatteryaPullDownDismiss.pullProgress(forVertical: y)
                        applyCollapse(progress, animated: false)
                    } else if isDragging {
                        // Finger reversed upward while collapsing → ease back toward full.
                        let progress = MatteryaPullDownDismiss.pullProgress(forVertical: max(0, y))
                        applyCollapse(progress, animated: false)
                    }
                }
                // Mini: no live collapse tracking; expand commits on end.
            }
            .onEnded { value in
                let y = value.translation.height
                let x = abs(value.translation.width)
                let predicted = value.predictedEndTranslation.height
                isDragging = false

                // ── Fullscreen: swipe down → exit (same continuous player) ──
                if isHubFullscreen {
                    if y > 120 || predicted > 240 {
                        closeFullscreen(animated: true)
                    } else {
                        withAnimation(MatteryaMotion.fullscreen) {
                            fsDismissDrag = 0
                        }
                    }
                    return
                }

                // ── Mini: swipe up → maximize (YouTube) ──
                if !expanded || collapse > 0.85 {
                    if y < -28 || predicted < -80 {
                        ReelsTwistHaptics.pullDismiss()
                        appState.expandHubPlayback()
                    }
                    return
                }

                guard expanded else { return }
                guard abs(y) > x * 0.5 else {
                    // Ambiguous → snap open.
                    withAnimation(MatteryaMotion.expand) {
                        collapse = 0
                        appState.hubPlaybackPullProgress = 0
                    }
                    return
                }

                // ── Expanded: swipe up → fullscreen (YouTube) ──
                if y < -36 || predicted < -120 {
                    withAnimation(MatteryaMotion.expand) {
                        collapse = 0
                        appState.hubPlaybackPullProgress = 0
                    }
                    openFullscreenSeamless()
                    return
                }

                // ── Expanded: swipe down → mini ──
                let shouldMini = MatteryaPullDownDismiss.shouldMinimizeOnRelease(
                    value,
                    dragOffset: max(0, y),
                    pullProgress: collapse
                )
                if shouldMini {
                    ReelsTwistHaptics.pullDismiss()
                    commitMinimize()
                } else {
                    withAnimation(MatteryaMotion.expand) {
                        collapse = 0
                        appState.hubPlaybackPullProgress = 0
                    }
                }
            }
    }

    private func applyCollapse(_ progress: CGFloat, animated: Bool) {
        let p = min(1, max(0, progress))
        if animated {
            withAnimation(MatteryaMotion.minimize) {
                collapse = p
                appState.hubPlaybackPullProgress = p
            }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                collapse = p
                appState.hubPlaybackPullProgress = p
            }
        }
    }

    private func syncPullProgressFromCollapse() {
        appState.hubPlaybackPullProgress = expanded ? collapse : 0
    }

    /// Expand the continuous player to full screen — same AVPlayer, no second mount.
    private func openFullscreenSeamless() {
        guard !isHubFullscreen, !fullscreenGate else { return }
        fullscreenGate = true
        // Keep playing — never mute, never remount.
        appState.hubPlaybackPlaying = true
        appState.hubFullscreenPullProgress = 0
        fsDismissDrag = 0
        collapse = 0
        withAnimation(MatteryaMotion.fullscreen) {
            isHubFullscreen = true
        }
        unlockLandscapeForFullscreen()
        applyContentOrientationFromDevice()
        NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        // Short gate so simultaneous swipe + button + meta token don't double-fire.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            fullscreenGate = false
        }
    }

    private func closeFullscreen(animated: Bool) {
        guard isHubFullscreen || contentRotation != .zero || useLandscapeLayout else {
            lockPortraitAfterFullscreen()
            return
        }
        let apply = {
            isHubFullscreen = false
            fsDismissDrag = 0
            contentRotation = .zero
            useLandscapeLayout = false
            appState.hubFullscreenPullProgress = 0
            collapse = 0
        }
        if animated {
            withAnimation(MatteryaMotion.fullscreen) { apply() }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { apply() }
        }
        lockPortraitAfterFullscreen()
        // Continuous player never stopped — just re-assert play after layout settles.
        appState.hubPlaybackPlaying = true
        NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
    }

    // MARK: - Orientation (fullscreen only)

    private func unlockLandscapeForFullscreen() {
        AppDelegate.orientationLock = .allButUpsideDown
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        Self.refreshSupportedOrientations()
        // Prefer free rotate; do NOT force landscape then flip back (that caused FS “hallucinations”).
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

    /// Rotate film with the phone when UIKit cannot leave portrait (Control Center lock).
    private func applyContentOrientationFromDevice() {
        guard isHubFullscreen else {
            contentRotation = .zero
            useLandscapeLayout = false
            return
        }
        let o = UIDevice.current.orientation
        switch o {
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
        case .faceUp, .faceDown, .unknown:
            // Keep last stable rotation; if interface is already landscape, match it.
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                switch scene.interfaceOrientation {
                case .landscapeLeft:
                    contentRotation = .degrees(90)
                    useLandscapeLayout = true
                case .landscapeRight:
                    contentRotation = .degrees(-90)
                    useLandscapeLayout = true
                case .portrait, .portraitUpsideDown:
                    contentRotation = .zero
                    useLandscapeLayout = false
                @unknown default:
                    break
                }
            }
        @unknown default:
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

    /// Animate collapse → 1, then flip session to mini **without** a second layout jump.
    /// Critical: wait until the morph has mostly landed before mounting the clear mini chrome
    /// (flipping expanded after ~16ms left a white hole where the strip is).
    private func commitMinimize() {
        if isHubFullscreen { closeFullscreen(animated: false) }
        let returnToChat = appState.hubMinimizeReturnToChat
        // Drive chrome + geometry to mini in one short spring.
        withAnimation(MatteryaMotion.minimize) {
            collapse = 1
            appState.hubPlaybackPullProgress = 1
        }
        Task { @MainActor in
            // ~spring response — video must sit in the mini strip before chrome mounts.
            try? await Task.sleep(nanoseconds: 200_000_000)
            // Pin geometry before session flip.
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
        }
    }
}
