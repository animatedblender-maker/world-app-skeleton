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
/// **Minimize model (flawless path):**
/// One continuous progress `collapse` 0…1 interpolates the player frame between
/// full watch stage and mini strip. Finger drag updates `collapse` 1:1.
/// On release we animate `collapse` → 1, then flip `hubPlaybackExpanded = false`
/// with animations disabled so layout does not jump a second time.
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
    /// YouTube: swipe up on the player → landscape fullscreen.
    @State private var presentFullscreen = false

    private var expanded: Bool { appState.hubPlaybackExpanded }

    /// Chat dock only — floating mini uses a fixed bottom strip.
    private var hasChatDockSlot: Bool {
        !expanded
            && appState.hubPlaybackDockInChat
            && dockSlotGlobal != nil
            && (dockSlotGlobal?.width ?? 0) > 8
            && (dockSlotGlobal?.height ?? 0) > 8
    }

    private var floatingBottomClearance: CGFloat {
        if hasChatDockSlot { return 0 }
        if collapse > 0.5 || !expanded, appState.navigationPath.isEmpty {
            return Theme.tabBarHeight
        }
        return 0
    }

    private var showTransportChrome: Bool {
        // Hide in-player chrome once mostly collapsed (mini bar owns controls).
        expanded && collapse < 0.55
    }

    private var transportChromeOpacity: Double {
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
                    let layout = playerLayout(in: geo, collapse: collapse)
                    let hitRect = CGRect(
                        x: layout.x,
                        y: layout.y,
                        width: layout.width,
                        height: layout.height
                    )

                    HubPassThroughContainer(interactiveRect: hitRect) {
                        videoStack(post: post, layout: layout)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            collapse = expanded ? 0 : 1
            syncPullProgressFromCollapse()
        }
        .onChange(of: expanded) { _, isExpanded in
            // External expand/minimize (tab switch, chevron, mini tap from chat).
            isDragging = false
            if isExpanded {
                // YouTube maximize: spring collapse 1 → 0 (full stage).
                appState.hubPlaybackPullProgress = 0
                withAnimation(MatteryaMotion.expand) {
                    collapse = 0
                }
            } else {
                // External minimize (tab leave): spring to mini strip.
                withAnimation(MatteryaMotion.minimize) {
                    collapse = 1
                    appState.hubPlaybackPullProgress = 1
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    guard !appState.hubPlaybackExpanded else { return }
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
        }
        .onChange(of: appState.hubPlaybackPlaying) { _, playing in
            guard playing, appState.hubPlaybackPost != nil else { return }
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
    }

    // MARK: - Video stack

    @ViewBuilder
    private func videoStack(post: CountryPost, layout: PlayerLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                Theme.ink
                playerSurface(
                    for: post,
                    showControls: showTransportChrome,
                    chromeOpacity: transportChromeOpacity
                )
                .frame(width: layout.width, height: layout.height)
                .clipped()
            }
            .frame(width: layout.width, height: layout.height)
            .background(Theme.ink)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: collapse > 0.08 ? 12 : 0,
                    style: .continuous
                )
            )
            .clipped()
            .offset(x: layout.x, y: layout.y)
            // Finger 1:1 while dragging; spring only on settle / expand.
            .animation(isDragging ? nil : MatteryaMotion.minimize, value: collapse)
            // YouTube: pull down → mini · pull up (expanded) → fullscreen · pull up (mini) → expand.
            .simultaneousGesture(playerDragGesture)
            .id("global-hub-continuous-\(post.id)")
        }
    }

    // MARK: - Layout (lerp expanded ↔ mini)

    private struct PlayerLayout {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func expandedFrame(in geo: GeometryProxy) -> PlayerLayout {
        // Stage height follows the clip’s natural aspect so aspect-fit never crops.
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
                isActive: appState.hubPlaybackPlaying,
                startTime: resumeAt,
                postID: post.id,
                showsControls: showControls,
                loops: false,
                // Expanded: fit full picture (no crop). Mini strip: fill the bar edge-to-edge.
                fillsFrame: collapse > 0.55,
                chromeOpacity: chromeOpacity,
                isMuted: mutedBinding,
                // YouTube-style landscape fullscreen from the player chrome + swipe-up.
                allowsFullscreen: collapse < 0.25,
                presentFullscreen: $presentFullscreen,
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
                    presentFullscreen = true
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

    /// Animate collapse → 1, then flip session to mini **without** a second layout jump.
    private func commitMinimize() {
        // Drive chrome + geometry to mini in one short easeOut.
        withAnimation(MatteryaMotion.minimize) {
            collapse = 1
            appState.hubPlaybackPullProgress = 1
        }
        // Flip expanded after the morph starts painting — geometry already at mini
        // so this must NOT re-animate. Side-effects (chat return) stay deferred.
        Task { @MainActor in
            // Let one frame paint collapse=1.
            try? await Task.sleep(nanoseconds: 16_000_000)
            appState.minimizeHubPlayback(returnToChat: true, animated: false)
            // Ensure collapse stays 1 after state flip (onChange may race).
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                collapse = 1
            }
            // Clear pull flag after mini bar is up so home isn't treated as "grabbing".
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !appState.hubPlaybackExpanded else { return }
            appState.hubPlaybackPullProgress = 0
        }
    }
}
