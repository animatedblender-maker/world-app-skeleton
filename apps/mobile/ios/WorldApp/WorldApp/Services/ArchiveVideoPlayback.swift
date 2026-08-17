import AVFoundation
import Foundation
import SwiftUI
import UIKit

/// Resolves Internet Archive `/download/` URLs to direct CDN MP4s and plays them with AVPlayer.
///
/// Why a dedicated path:
/// - `archive.org/download/...` returns 302 → `dn*.us.archive.org` — AVPlayer often never leaves
///   the poster if handed the redirect URL (or custom headers).
/// - SwiftUI `@State` AVPlayer is torn down on parent re-renders; this controller owns the player.
///
/// **Gated by `AppConfig.archiveContentEnabled`** — when false, resolve is a no-op and
/// callers should not surface Archive media. Full implementation kept for re-enable.
enum ArchiveVideoPlayback {
    /// Async-safe CDN URL cache (NSLock is not allowed from async contexts in Swift 6).
    private actor CDNCache {
        private var urls: [String: URL] = [:]
        func get(_ key: String) -> URL? { urls[key] }
        func set(_ key: String, _ url: URL) { urls[key] = url }
    }

    private static let cdnCache = CDNCache()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func isArchiveURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("archive.org")
    }

    /// Returns a direct playable CDN URL when possible (cached).
    static func resolvedPlaybackURL(for url: URL) async -> URL {
        // Skip CDN chase when Archive content is off (saves network + main-thread work).
        guard AppConfig.archiveContentEnabled else { return url }

        let key = url.absoluteString
        if let cached = await cdnCache.get(key) { return cached }

        // Already a CDN host (dn*.us.archive.org, ia*.us.archive.org, …) — play as-is.
        if let host = url.host?.lowercased(),
           host.contains("archive.org"),
           host != "archive.org",
           host != "www.archive.org",
           !url.path.contains("/download/") {
            await cdnCache.set(key, url)
            return url
        }

        guard isArchiveURL(url) else { return url }

        // Follow redirects. Prefer a ranged GET; fall back to HEAD/GET without range.
        let ranged = await followRedirects(url, range: true)
        let final: URL?
        if let ranged {
            final = ranged
        } else {
            final = await followRedirects(url, range: false)
        }
        if let final {
            await cdnCache.set(key, final)
            #if DEBUG
            print("[ArchiveVideo] resolved \(url.host ?? "") → \(final.host ?? final.absoluteString)")
            #endif
            return final
        }
        return url
    }

    private static func followRedirects(_ url: URL, range: Bool) async -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = range ? "GET" : "HEAD"
        request.setValue(
            "MatteryaHubs/1.0 (iOS; +https://matterya.com)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://archive.org/", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if range {
            request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        }
        request.timeoutInterval = 12
        do {
            let (_, response) = try await session.data(for: request)
            if let final = response.url, final.absoluteString != url.absoluteString || isCDNHost(final) {
                return final
            }
            // HEAD may not rewrite response.url the same way — try GET without range.
            if !range {
                var getReq = request
                getReq.httpMethod = "GET"
                getReq.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
                let (_, getResponse) = try await session.data(for: getReq)
                return getResponse.url
            }
            return response.url
        } catch {
            #if DEBUG
            print("[ArchiveVideo] resolve failed (\(range ? "range" : "head")): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private static func isCDNHost(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("archive.org") && host != "archive.org" && host != "www.archive.org"
    }

    static func warmResolve(_ url: URL) {
        Task { _ = await resolvedPlaybackURL(for: url) }
    }
}

// MARK: - Bridge (SwiftUI controls → UIKit player)

@MainActor
final class ArchivePlayerBridge: ObservableObject {
    weak var controller: ArchiveVideoPlayerController?

    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var currentSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var isReady = false

    /// Always hop to the next main-runloop turn so we never publish during a SwiftUI update pass.
    /// `Task { @MainActor }` is NOT enough — it can run inline when already on the main actor.
    nonisolated func publishPlaying(_ playing: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = playing
        }
    }

    nonisolated func publishProgress(current: Double, duration: Double, playing: Bool?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentSeconds = current
            if duration > 0 { self.durationSeconds = duration }
            if let playing { self.isPlaying = playing }
        }
    }

    nonisolated func publishReady(playing: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            self?.isReady = true
            self?.isPlaying = playing
        }
    }

    nonisolated func publishMuted(_ muted: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isMuted = muted
        }
    }

    func togglePlayPause() {
        controller?.togglePlayPause()
        isPlaying = controller?.isPlaying ?? false
    }

    func seek(to seconds: Double, resumeIfWanted: Bool = false) {
        currentSeconds = seconds
        controller?.seek(to: seconds, resumeIfWanted: resumeIfWanted)
    }

    func toggleMute() {
        let next = !(controller?.isMuted ?? isMuted)
        controller?.setMuted(next)
        isMuted = next
    }

    func skip(by delta: Double) {
        let target = max(0, min(durationSeconds, currentSeconds + delta))
        // ±10s must keep playing from the new time (never land paused).
        seek(to: target, resumeIfWanted: true)
        isPlaying = true
    }

    func beginScrub() {
        controller?.beginScrub()
    }

    /// Finish scrub at `seconds` and always resume if the user was watching.
    func endScrub(at seconds: Double? = nil) {
        if let seconds {
            currentSeconds = seconds
        }
        controller?.endScrub(at: seconds ?? currentSeconds)
        // Scrub pause must never stick — UI + AppState stay "playing".
        isPlaying = true
    }
}

// MARK: - Themed hub player (controls + Archive UIKit surface)

/// Matterya-styled controls over the Archive player: play/pause, mute, scrub, ±10s.
/// Used in Hubs watch, mini handoff, and feed — keep this as the single hub video surface.
struct MatteryaHubPlayerView: View {
    let url: URL
    var posterURL: URL? = nil
    var isActive: Bool = true
    var startTime: Double = 0
    var postID: String? = nil
    /// When false (mini player), hide chrome but keep the same AVPlayer alive.
    var showsControls: Bool = true
    var loops: Bool = false
    /// When true, crop to fill the stage (no black letterbox bars). Hubs always fills.
    var fillsFrame: Bool = true
    /// 0…1 external fade (pull-to-mini slider). 1 = full chrome, 0 = hidden.
    var chromeOpacity: Double = 1
    @Binding var isMuted: Bool
    var onReady: (() -> Void)? = nil
    /// Keeps AppState.hubPlaybackPlaying in sync when chrome play/pause is used.
    var onPlayingChange: ((Bool) -> Void)? = nil
    /// Mini player / external chrome: (currentSeconds, durationSeconds).
    var onProgress: ((Double, Double) -> Void)? = nil
    /// Natural video size once known (for uncropped stage height).
    var onVideoSize: ((CGSize) -> Void)? = nil
    /// When set, seek once then clear via `onSeekConsumed`.
    var seekToSeconds: Double? = nil
    var onSeekConsumed: (() -> Void)? = nil

    /// When true, show the fullscreen control (YouTube expand arrows).
    var allowsFullscreen: Bool = false
    /// External trigger (e.g. swipe-up on player) — set true to open fullscreen, cleared after present.
    @Binding var presentFullscreen: Bool
    /// When set, parent owns fullscreen presentation (required when nested under
    /// HubPassThroughContainer — SwiftUI fullScreenCover inside that host fails silently).
    var onRequestFullscreen: (() -> Void)? = nil
    /// Global continuous Hubs surface — protected from tab-switch silence.
    var isContinuousHubPlayer: Bool = false
    /// Continuous layer is already full-screen (icon becomes exit, no second cover).
    var isFullscreenActive: Bool = false
    /// Mini strip: draw close/mute/play on the film (must be in this tree, not under UIKit).
    var showsMiniChrome: Bool = false
    var onMiniClose: (() -> Void)? = nil

    @StateObject private var bridge = ArchivePlayerBridge()
    @State private var showChrome = false
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var showFullscreen = false
    /// YouTube-style double-tap skip flash (negative = back, positive = forward).
    @State private var skipFlash: Int = 0
    @State private var skipFlashTask: Task<Void, Never>?

    init(
        url: URL,
        posterURL: URL? = nil,
        isActive: Bool = true,
        startTime: Double = 0,
        postID: String? = nil,
        showsControls: Bool = true,
        loops: Bool = false,
        fillsFrame: Bool = true,
        chromeOpacity: Double = 1,
        isMuted: Binding<Bool> = .constant(false),
        allowsFullscreen: Bool = false,
        presentFullscreen: Binding<Bool> = .constant(false),
        onRequestFullscreen: (() -> Void)? = nil,
        isContinuousHubPlayer: Bool = false,
        isFullscreenActive: Bool = false,
        showsMiniChrome: Bool = false,
        onMiniClose: (() -> Void)? = nil,
        onReady: (() -> Void)? = nil,
        onPlayingChange: ((Bool) -> Void)? = nil,
        onProgress: ((Double, Double) -> Void)? = nil,
        onVideoSize: ((CGSize) -> Void)? = nil,
        seekToSeconds: Double? = nil,
        onSeekConsumed: (() -> Void)? = nil
    ) {
        self.url = url
        self.posterURL = posterURL
        self.isActive = isActive
        self.startTime = startTime
        self.postID = postID
        self.showsControls = showsControls
        self.loops = loops
        self.fillsFrame = fillsFrame
        self.chromeOpacity = chromeOpacity
        self._isMuted = isMuted
        self.allowsFullscreen = allowsFullscreen
        self._presentFullscreen = presentFullscreen
        self.onRequestFullscreen = onRequestFullscreen
        self.isContinuousHubPlayer = isContinuousHubPlayer
        self.isFullscreenActive = isFullscreenActive
        self.showsMiniChrome = showsMiniChrome
        self.onMiniClose = onMiniClose
        self.onReady = onReady
        self.onPlayingChange = onPlayingChange
        self.onProgress = onProgress
        self.onVideoSize = onVideoSize
        self.seekToSeconds = seekToSeconds
        self.onSeekConsumed = onSeekConsumed
    }

    /// Prefer parent-owned fullscreen (continuous Hubs layer); fall back to local cover.
    private func enterFullscreen() {
        guard allowsFullscreen else { return }
        if let onRequestFullscreen {
            onRequestFullscreen()
        } else if !isFullscreenActive {
            showFullscreen = true
        }
        scheduleChromeHide()
    }

    var body: some View {
        ZStack {
            ArchiveVideoPlayerView(
                url: url,
                posterURL: posterURL,
                // Keep buffering/playing under parent-owned fullscreen so handoff never freezes.
                // Local cover still deactivates to avoid dual audio when this view owns FS.
                isActive: isActive && (onRequestFullscreen != nil || !showFullscreen),
                muted: isMuted,
                startTime: startTime,
                loops: loops,
                fillsFrame: fillsFrame,
                bridge: bridge,
                onReady: {
                    // Ready ≠ playing chrome. Buttons only appear after an intentional tap.
                    let playing = bridge.controller?.isPlaying == true || isActive
                    bridge.publishReady(playing: playing && isActive)
                    if isContinuousHubPlayer, let p = bridge.controller?.avPlayer {
                        MediaPlaybackCoordinator.shared.protectContinuous(p)
                    }
                    DispatchQueue.main.async {
                        onReady?()
                    }
                },
                onProgress: { current, duration in
                    guard !isScrubbing else { return }
                    let playing = bridge.controller?.isPlaying
                    bridge.publishProgress(current: current, duration: duration, playing: playing)
                    onProgress?(current, duration)
                    if let postID, current >= 0.5 {
                        YouTubeCatalogService.shared.notePlaybackPosition(
                            current,
                            for: postID,
                            duration: duration > 0 ? duration : nil
                        )
                    }
                },
                onVideoSize: { size in
                    onVideoSize?(size)
                },
                seekToSeconds: seekToSeconds,
                onSeekConsumed: onSeekConsumed,
                // Must follow callbacks (memberwise property order on ArchiveVideoPlayerView).
                isContinuousHubPlayer: isContinuousHubPlayer
            )

            if showsControls {
                // Spinner only while this slot is actively trying to play (never mid-scroll).
                if !bridge.isReady, isActive {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.15)
                        .opacity(chromeOpacity)
                        .zIndex(2)
                }

                // Buttons only after the user taps the video — never while scrolling.
                if showChrome {
                    hubChrome
                        .opacity(chromeOpacity)
                        .allowsHitTesting(chromeOpacity > 0.2)
                        .transition(.opacity)
                        .zIndex(3)
                } else {
                    // Capture taps + double-tap skip without drawing transport chrome.
                    youtubeHiddenChromeHitLayer
                        .opacity(chromeOpacity)
                        .allowsHitTesting(chromeOpacity > 0.2)
                        .zIndex(3)
                }

                // Double-tap skip flash (YouTube left/right arcs).
                if skipFlash != 0 {
                    HStack {
                        if skipFlash < 0 {
                            skipFlashBadge(seconds: 10, systemName: "gobackward.10")
                            Spacer(minLength: 0)
                        } else {
                            Spacer(minLength: 0)
                            skipFlashBadge(seconds: 10, systemName: "goforward.10")
                        }
                    }
                    .padding(.horizontal, 28)
                    .allowsHitTesting(false)
                    .opacity(chromeOpacity)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(40)
                }
            }

            // Continuous mini: chrome must live here (same host as film). Sibling SwiftUI
            // chrome under the pass-through UIView was invisible and untappable.
            if showsMiniChrome, isContinuousHubPlayer {
                HubMiniPlayerChrome(
                    isPlaying: Binding(
                        get: { bridge.isPlaying || isActive },
                        set: { want in
                            if want {
                                bridge.controller?.setMuted(isMuted)
                                bridge.controller?.setActive(true)
                                bridge.controller?.ensureContinuingPlayback()
                                bridge.isPlaying = true
                                onPlayingChange?(true)
                                NotificationCenter.default.post(
                                    name: .matteryaHubContinuousSetPlaying,
                                    object: nil,
                                    userInfo: ["playing": true]
                                )
                            } else {
                                bridge.controller?.pauseKeepingFrame()
                                bridge.isPlaying = false
                                onPlayingChange?(false)
                                NotificationCenter.default.post(
                                    name: .matteryaHubContinuousSetPlaying,
                                    object: nil,
                                    userInfo: ["playing": false]
                                )
                            }
                        }
                    ),
                    isMuted: Binding(
                        get: { isMuted },
                        set: { newValue in
                            isMuted = newValue
                            bridge.controller?.setMuted(newValue)
                            NotificationCenter.default.post(
                                name: .matteryaHubContinuousSetMuted,
                                object: nil,
                                userInfo: ["muted": newValue]
                            )
                        }
                    ),
                    onClose: {
                        onMiniClose?()
                    }
                )
                .allowsHitTesting(true)
                .zIndex(60)
            }
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            MatteryaLandscapeFullscreenPlayer(
                url: url,
                posterURL: posterURL,
                startTime: bridge.currentSeconds,
                initialMuted: isMuted,
                isArchive: true,
                onDismiss: { muted, seconds in
                    isMuted = muted
                    if let postID {
                        YouTubeCatalogService.shared.notePlaybackPosition(
                            seconds,
                            for: postID,
                            duration: bridge.durationSeconds > 0 ? bridge.durationSeconds : nil
                        )
                    }
                    bridge.seek(to: seconds)
                    bridge.controller?.setMuted(muted)
                    showFullscreen = false
                    // Must call setActive(true) — ensureContinuingPlayback alone leaves userWantsPlayback false.
                    DispatchQueue.main.async {
                        bridge.controller?.setActive(isActive)
                        if isActive {
                            bridge.controller?.ensureContinuingPlayback()
                        }
                    }
                }
            )
        }
        .onChange(of: isActive) { _, active in
            if !active, !isContinuousHubPlayer {
                // Leaving the focused feed slot — hide noisy transport chrome immediately.
                chromeHideTask?.cancel()
                showChrome = false
            }
            if isContinuousHubPlayer {
                // Continuous mini/watch: play/pause only from AppState / chrome intent.
                // setActive(false) is ignored on the controller (layout thrash safe);
                // intentional pause uses pauseKeepingFrame so audio stops cleanly.
                if active {
                    bridge.controller?.setMuted(isMuted)
                    bridge.controller?.setActive(true)
                    bridge.controller?.ensureContinuingPlayback()
                    bridge.isPlaying = true
                } else {
                    bridge.controller?.pauseKeepingFrame()
                    bridge.isPlaying = false
                }
                return
            }
            // Always setActive so userWantsPlayback + audio output are restored after pause.
            bridge.controller?.setActive(active)
            if !active {
                bridge.isPlaying = false
            } else {
                // Expand/mini / mini play button: re-assert mute from chrome, then resume.
                bridge.controller?.setMuted(isMuted)
                bridge.controller?.ensureContinuingPlayback()
                bridge.isPlaying = true
            }
        }
        .onChange(of: presentFullscreen) { _, want in
            // YouTube swipe-up / parent gesture → open landscape fullscreen.
            guard want, allowsFullscreen else {
                if want { presentFullscreen = false }
                return
            }
            presentFullscreen = false
            enterFullscreen()
        }
        .onChange(of: showsControls) { _, visible in
            if visible {
                // Keep chrome hidden until the user taps — feed scroll must stay clean.
                // Continuous / FS surfaces still reveal chrome on their own enter events.
                if isContinuousHubPlayer || isFullscreenActive {
                    showChrome = true
                    scheduleChromeHide()
                } else {
                    showChrome = false
                    chromeHideTask?.cancel()
                }
            } else {
                // Mini player: hide chrome but keep the AVPlayer actively rendering.
                chromeHideTask?.cancel()
                showChrome = false
            }
            // Expand ↔ mini / stage ↔ FS only toggles chrome — never pause or remount.
            // Continuous hubs: skip re-solo on every chrome flip (keeps YT-smooth morph).
            if isActive, !isContinuousHubPlayer {
                bridge.controller?.setActive(true)
                bridge.controller?.ensureContinuingPlayback()
            }
        }
        .onChange(of: fillsFrame) { _, fill in
            // Gravity update only — never reconfigure the item (would hitch mid-morph).
            // Mini must fill immediately or letterbox reads as a black overlay.
            bridge.controller?.applyVideoGravity(fill ? .resizeAspectFill : .resizeAspect)
        }
        .onChange(of: isContinuousHubPlayer) { _, continuous in
            guard continuous else { return }
            // Continuous mini/stage: re-assert gravity when ownership flips.
            bridge.controller?.applyVideoGravity(fillsFrame ? .resizeAspectFill : .resizeAspect)
        }
        .onChange(of: isFullscreenActive) { _, full in
            // YT: reveal chrome on FS enter; auto-hide after a beat while playing.
            if full {
                showChrome = true
                scheduleChromeHide()
            }
        }
        .onChange(of: isMuted) { _, muted in
            bridge.controller?.setMuted(muted)
            bridge.publishMuted(muted)
        }
        .onChange(of: bridge.isPlaying) { _, playing in
            // Never push "paused" while scrubbing — that cleared hubPlaybackPlaying and
            // left the clip frozen after the timeline seek.
            guard !isScrubbing else { return }
            if isContinuousHubPlayer {
                // Buffer stalls / layout reflow briefly set rate=0 — do NOT clear
                // AppState.hubPlaybackPlaying or mini goes silent after tab minimize.
                if playing {
                    onPlayingChange?(true)
                }
                return
            }
            // Chrome play/pause must update hubPlaybackPlaying so mini bar + isActive stay aligned.
            onPlayingChange?(playing)
        }
        .onAppear {
            bridge.controller?.setMuted(isMuted)
            if isActive {
                bridge.controller?.setActive(true)
            }
        }
        .onDisappear {
            chromeHideTask?.cancel()
            if let postID {
                YouTubeCatalogService.shared.notePlaybackPosition(
                    bridge.currentSeconds,
                    for: postID,
                    duration: bridge.durationSeconds > 0 ? bridge.durationSeconds : nil
                )
            }
            // Do NOT teardown — keeps continuous full ↔ mini seamless.
        }
    }

    /// Matterya-styled chrome, YouTube behaviors (tap hide, double-tap ±10s, auto-hide, scrub).
    private var hubChrome: some View {
        // Edge-to-edge FS film still needs chrome inset for notch + home indicator,
        // otherwise bottom transport is cropped out of frame.
        let safeTop = isFullscreenActive ? max(8, YouTubeMediaLayout.keyWindowSafeTop) : 10
        let safeBottom = isFullscreenActive ? max(12, YouTubeMediaLayout.keyWindowSafeBottom + 6) : 10

        return ZStack {
            // Soft dim when paused — keep transparent enough to avoid “black bar” slabs.
            if !bridge.isPlaying {
                Color.black.opacity(0.18)
                    .allowsHitTesting(false)
            }

            // Single tap empty area → hide chrome when playing; double-tap L/R → ±10s.
            youtubeGestureLayer
                .zIndex(0)

            // Top tools — mute only (fullscreen lives once, on the bottom scrubber row).
            VStack {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    youtubeTopIcon(
                        systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: isMuted ? "Unmute" : "Mute"
                    ) {
                        isMuted.toggle()
                        bridge.controller?.setMuted(isMuted)
                        bridge.publishMuted(isMuted)
                        scheduleChromeHide()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, safeTop)
                Spacer(minLength: 0)
            }
            .zIndex(5)

            // Center transport: −10s · play/pause · +10s (Matterya warm accent family)
            HStack(spacing: 32) {
                hubSkipButton(systemName: "gobackward.10", label: "Back 10 seconds") {
                    performSkip(by: -10)
                    scheduleChromeHide()
                }

                Button {
                    bridge.togglePlayPause()
                    if bridge.isPlaying {
                        scheduleChromeHide()
                    } else {
                        chromeHideTask?.cancel()
                        showChrome = true
                    }
                } label: {
                    Image(systemName: bridge.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: bridge.isPlaying ? 26 : 30, weight: .bold))
                        .foregroundStyle(Theme.paper)
                        .offset(x: bridge.isPlaying ? 0 : 2)
                        .frame(width: 72, height: 72)
                        .background(Theme.accentBright, in: Circle())
                        .shadow(color: Theme.ink.opacity(0.35), radius: 14, y: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bridge.isPlaying ? "Pause" : "Play")

                hubSkipButton(systemName: "goforward.10", label: "Forward 10 seconds") {
                    performSkip(by: 10)
                    scheduleChromeHide()
                }
            }
            .zIndex(4)

            // Bottom bar: scrubber + times (Matterya accent rail)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    HubTimelineScrubber(
                        value: scrubberValue,
                        accent: Theme.accentBright,
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if editing {
                                chromeHideTask?.cancel()
                                showChrome = true
                                bridge.beginScrub()
                            } else if bridge.durationSeconds > 0 {
                                let target = bridge.currentSeconds
                                bridge.endScrub(at: target)
                                onPlayingChange?(true)
                                scheduleChromeHide()
                            }
                        },
                        onValueChanged: { fraction in
                            guard bridge.durationSeconds > 0 else { return }
                            bridge.currentSeconds = fraction * bridge.durationSeconds
                        }
                    )
                    .padding(.horizontal, 12)

                    HStack(spacing: 8) {
                        Text(formatTime(bridge.currentSeconds))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.paper.opacity(0.95))

                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(Theme.paper.opacity(0.4))

                        Text(formatTime(bridge.durationSeconds))
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(Theme.paper.opacity(0.72))

                        Spacer(minLength: 0)

                        if allowsFullscreen {
                            Button {
                                enterFullscreen()
                            } label: {
                                Image(systemName: isFullscreenActive
                                      ? "arrow.down.right.and.arrow.up.left"
                                      : "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.paper.opacity(0.95))
                                    .frame(width: 32, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isFullscreenActive ? "Exit full screen" : "Full screen")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, safeBottom)
                }
                .padding(.top, 20)
                .background(
                    LinearGradient(
                        colors: [
                            .clear,
                            Theme.ink.opacity(0.5),
                            Theme.ink.opacity(0.88),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .zIndex(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    /// When chrome is auto-hidden: single-tap shows chrome, double-tap L/R skips.
    private var youtubeHiddenChromeHitLayer: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { performSkip(by: -10) }
                    .onTapGesture(count: 1) { revealChrome() }
                    .frame(width: geo.size.width * 0.42)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1) {
                        // Center band: tap toggles play (YT) and shows chrome.
                        bridge.togglePlayPause()
                        revealChrome()
                    }
                    .frame(maxWidth: .infinity)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { performSkip(by: 10) }
                    .onTapGesture(count: 1) { revealChrome() }
                    .frame(width: geo.size.width * 0.42)
            }
        }
    }

    private var youtubeGestureLayer: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { performSkip(by: -10) }
                    .onTapGesture(count: 1) {
                        if bridge.isPlaying {
                            withAnimation(.easeInOut(duration: 0.15)) { showChrome = false }
                            chromeHideTask?.cancel()
                        } else {
                            bridge.togglePlayPause()
                            scheduleChromeHide()
                        }
                    }
                    .frame(width: geo.size.width * 0.42)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1) {
                        if bridge.isPlaying {
                            withAnimation(.easeInOut(duration: 0.15)) { showChrome = false }
                            chromeHideTask?.cancel()
                        }
                    }
                    .frame(maxWidth: .infinity)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { performSkip(by: 10) }
                    .onTapGesture(count: 1) {
                        if bridge.isPlaying {
                            withAnimation(.easeInOut(duration: 0.15)) { showChrome = false }
                            chromeHideTask?.cancel()
                        } else {
                            bridge.togglePlayPause()
                            scheduleChromeHide()
                        }
                    }
                    .frame(width: geo.size.width * 0.42)
            }
        }
    }

    private func youtubeTopIcon(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.paper)
                .frame(width: 36, height: 36)
                .background(Theme.ink.opacity(0.52), in: Circle())
                .overlay(Circle().stroke(Theme.paper.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// ±10s control — Matterya secondary disc (warm paper + accent ring, pairs with play).
    private func hubSkipButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.paper)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(Theme.accentBright.opacity(0.92))
                )
                .overlay(
                    Circle()
                        .stroke(Theme.paper.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: Theme.ink.opacity(0.28), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func skipFlashBadge(seconds: Int, systemName: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
            Text("\(seconds)")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(Theme.paper)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.ink.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(Theme.accentBright.opacity(0.45), lineWidth: 1))
    }

    private func revealChrome() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showChrome = true
        }
        scheduleChromeHide()
    }

    private func performSkip(by delta: Double) {
        bridge.skip(by: delta)
        onPlayingChange?(true)
        skipFlashTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            skipFlash = delta < 0 ? -1 : 1
        }
        skipFlashTask = Task {
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { skipFlash = 0 }
            }
        }
        revealChrome()
    }

    private var scrubberValue: Double {
        guard bridge.durationSeconds > 0 else { return 0 }
        return min(1, max(0, bridge.currentSeconds / bridge.durationSeconds))
    }

    private func scheduleChromeHide() {
        chromeHideTask?.cancel()
        // Stay up while paused so center play never vanishes mid-pause.
        guard bridge.isPlaying else { return }
        chromeHideTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled, !isScrubbing else { return }
            await MainActor.run {
                guard bridge.isPlaying else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showChrome = false
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = SafeNumeric.int(SafeNumeric.nonNegativeSeconds(seconds), max: 359_999)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Fullscreen (hub / archive) — portrait + landscape

/// Full-screen hub player. Follows the phone’s orientation (portrait or landscape).
/// Aspect-fit only — never crop or zoom the picture. Drag down to dismiss.
struct MatteryaLandscapeFullscreenPlayer: View {
    let url: URL
    var posterURL: URL? = nil
    var startTime: Double = 0
    var initialMuted: Bool = false
    /// Kept for API compatibility; Archive surface plays archive + other remote MP4s.
    var isArchive: Bool = true
    var onDismiss: (_ muted: Bool, _ seconds: Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var bridge = ArchivePlayerBridge()
    @State private var isMuted = false
    @State private var showChrome = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var isScrubbing = false
    /// YouTube drag-down dismiss offset (no scale/zoom).
    @State private var dismissDrag: CGFloat = 0
    /// When Control Center orientation lock blocks UIKit rotation, rotate content like YT.
    @State private var contentRotation: Angle = .zero
    @State private var useLandscapeLayout = false

    var body: some View {
        GeometryReader { geo in
            let portraitSize = geo.size
            // When UI stays portrait under lock, swap axes so video still lays out landscape.
            let layoutW = useLandscapeLayout ? max(portraitSize.width, portraitSize.height) : portraitSize.width
            let layoutH = useLandscapeLayout ? min(portraitSize.width, portraitSize.height) : portraitSize.height
            ZStack {
                Color.black.ignoresSafeArea()
                    .opacity(max(0.4, 1 - Double(dismissDrag / 480)))

                // Full bounds + aspect-fit: entire frame visible in portrait *and* landscape.
                // Never fillsFrame (that crops) and never scaleEffect (that zooms).
                ArchiveVideoPlayerView(
                    url: url,
                    posterURL: posterURL,
                    isActive: true,
                    muted: isMuted,
                    startTime: startTime,
                    loops: false,
                    fillsFrame: false,
                    bridge: bridge,
                    onReady: {
                        bridge.publishReady(playing: true)
                        // Re-assert fit after first frame (configure must not force fill).
                        bridge.controller?.applyVideoGravity(.resizeAspect)
                        bridge.controller?.setActive(true)
                        bridge.controller?.ensureContinuingPlayback()
                        scheduleChromeHide()
                    },
                    onProgress: { current, duration in
                        guard !isScrubbing else { return }
                        let playing = bridge.controller?.isPlaying
                        bridge.publishProgress(current: current, duration: duration, playing: playing)
                    }
                )
                .frame(width: layoutW, height: layoutH)
                .rotationEffect(contentRotation)
                .frame(width: portraitSize.width, height: portraitSize.height)
                .offset(y: max(0, dismissDrag))
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showChrome.toggle()
                    }
                    if showChrome { scheduleChromeHide() }
                }
                .gesture(fullscreenDismissGesture)

                if (showChrome || !bridge.isPlaying), dismissDrag < 24 {
                    fullscreenChrome
                        .frame(width: portraitSize.width, height: portraitSize.height)
                        .rotationEffect(contentRotation)
                        .transition(.opacity)
                }
            }
            .frame(width: portraitSize.width, height: portraitSize.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        // Rotate with the device while fullscreen (portrait + landscape).
        .onAppear {
            isMuted = initialMuted
            // Unlock rotation — free axes only (no force-landscape-then-revert flip-flops).
            AppDelegate.orientationLock = .allButUpsideDown
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            Self.refreshSupportedOrientations()
            Self.requestGeometryUpdateIfNeeded()
            applyContentOrientationFromDevice()
            bridge.controller?.setMuted(isMuted)
            bridge.controller?.setActive(true)
            bridge.controller?.ensureContinuingPlayback()
            bridge.controller?.applyVideoGravity(.resizeAspect)
            scheduleChromeHide()
        }
        .onDisappear {
            chromeHideTask?.cancel()
            AppDelegate.orientationLock = .portrait
            Self.refreshSupportedOrientations()
            Self.requestGeometryUpdateIfNeeded()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onChange(of: isMuted) { _, muted in
            bridge.controller?.setMuted(muted)
            bridge.publishMuted(muted)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Keep aspect-fit; content rotation covers system orientation lock.
            // Do NOT force landscape geometry then flip back — that caused FS hallucinations.
            bridge.controller?.applyVideoGravity(.resizeAspect)
            AppDelegate.orientationLock = .allButUpsideDown
            Self.refreshSupportedOrientations()
            Self.requestGeometryUpdateIfNeeded()
            withAnimation(.easeInOut(duration: 0.2)) {
                applyContentOrientationFromDevice()
            }
        }
    }

    /// Rotate video content when UIKit cannot leave portrait (system orientation lock).
    private func applyContentOrientationFromDevice() {
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
        case .portrait, .faceUp, .faceDown, .unknown:
            // If interface already landscape, don't fight it.
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                switch scene.interfaceOrientation {
                case .landscapeLeft:
                    contentRotation = .degrees(90)
                    useLandscapeLayout = true
                    return
                case .landscapeRight:
                    contentRotation = .degrees(-90)
                    useLandscapeLayout = true
                    return
                default:
                    break
                }
            }
            contentRotation = .degrees(0)
            useLandscapeLayout = false
        @unknown default:
            contentRotation = .degrees(0)
            useLandscapeLayout = false
        }
    }

    private var fullscreenDismissGesture: some Gesture {
        // Swipe **up** to exit fullscreen (matches continuous Hubs layer).
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !isScrubbing else { return }
                let y = value.translation.height
                let x = abs(value.translation.width)
                guard y < 0, -y > x * 0.6 else { return }
                dismissDrag = -y
                showChrome = false
            }
            .onEnded { value in
                let y = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if y < -140 || predicted < -280 {
                    close()
                } else {
                    withAnimation(MatteryaMotion.fullscreen) {
                        dismissDrag = 0
                    }
                    showChrome = true
                    scheduleChromeHide()
                }
            }
    }

    private var fullscreenChrome: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Theme.ink.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        isMuted.toggle()
                        scheduleChromeHide()
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Theme.ink.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .safeAreaPadding(.top, 8)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Text(formatTime(bridge.currentSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 42, alignment: .leading)

                    HubTimelineScrubber(
                        value: scrubberValue,
                        accent: Theme.accentBright,
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if editing {
                                chromeHideTask?.cancel()
                                bridge.beginScrub()
                            } else if bridge.durationSeconds > 0 {
                                bridge.endScrub(at: bridge.currentSeconds)
                                scheduleChromeHide()
                            }
                        },
                        onValueChanged: { fraction in
                            guard bridge.durationSeconds > 0 else { return }
                            bridge.currentSeconds = fraction * bridge.durationSeconds
                        }
                    )

                    Text(formatTime(bridge.durationSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.paper.opacity(0.75))
                        .frame(width: 42, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .padding(.top, 12)
                .safeAreaPadding(.bottom, 8)
                .background(
                    LinearGradient(
                        colors: [.clear, Theme.ink.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Center −10s · play · +10s (same as watch stage).
            HStack(spacing: 44) {
                Button {
                    bridge.skip(by: -10)
                    scheduleChromeHide()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Theme.ink.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    bridge.togglePlayPause()
                    scheduleChromeHide()
                } label: {
                    Image(systemName: bridge.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.paper)
                        .frame(width: 68, height: 68)
                        .background(Theme.accentBright, in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    bridge.skip(by: 10)
                    scheduleChromeHide()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Theme.ink.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var scrubberValue: Double {
        guard bridge.durationSeconds > 0 else { return 0 }
        return min(1, max(0, bridge.currentSeconds / bridge.durationSeconds))
    }

    private func close() {
        chromeHideTask?.cancel()
        AppDelegate.orientationLock = .portrait
        Self.refreshSupportedOrientations()
        onDismiss(isMuted, bridge.currentSeconds)
        dismiss()
    }

    private func scheduleChromeHide() {
        chromeHideTask?.cancel()
        chromeHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, !isScrubbing else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showChrome = false
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = SafeNumeric.int(SafeNumeric.nonNegativeSeconds(seconds), max: 359_999)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        // Long Hubs videos: 1:01:00 not 61:00
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private static func refreshSupportedOrientations() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        for window in scene.windows {
            // Walk presented stack (fullScreenCover) so landscape unlock applies to FS VC.
            var vc: UIViewController? = window.rootViewController
            while let current = vc {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                vc = current.presentedViewController
            }
        }
    }

    /// Ask the window scene to re-evaluate orientation so portrait↔landscape follows the phone.
    private static func requestGeometryUpdateIfNeeded() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        // Free axes only — never snap landscape then revert (double-rotate hallucination).
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: AppDelegate.orientationLock)) { _ in }
        refreshSupportedOrientations()
    }
}

/// YouTube-style progress rail — thin bar, red fill, knobby only while scrubbing.
private struct HubTimelineScrubber: View {
    let value: Double
    var accent: Color = Theme.accentBright
    let onEditingChanged: (Bool) -> Void
    let onValueChanged: (Double) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fraction = isDragging ? dragValue : value
            let fill = max(0, min(1, fraction)) * width
            let trackH: CGFloat = isDragging ? 5 : 3
            let knob: CGFloat = isDragging ? 14 : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: trackH)

                Capsule()
                    .fill(accent)
                    .frame(width: max(fill, trackH), height: trackH)

                if isDragging {
                    Circle()
                        .fill(accent)
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: max(0, fill - knob / 2))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let next = min(1, max(0, gesture.location.x / width))
                        dragValue = next
                        onValueChanged(next)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .onChange(of: value) { _, newValue in
            if !isDragging { dragValue = newValue }
        }
        .onAppear { dragValue = value }
    }
}

// MARK: - UIKit player (survives SwiftUI redraws)

/// Full-bleed Internet Archive / remote MP4 player owned by UIKit.
struct ArchiveVideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    var posterURL: URL? = nil
    var isActive: Bool = true
    var muted: Bool = false
    var startTime: Double = 0
    /// When true, loops the clip at end (Sparks). Avoids a dead pause after first playthrough.
    var loops: Bool = true
    /// When true, fill the stage (no black bars). Hubs always fills.
    var fillsFrame: Bool = true
    /// Optional content id for continuity / engagement (not required for playback).
    var postID: String? = nil
    /// When false (Sparks pager), UIView does not eat pans — ScrollView can page immediately.
    var interactive: Bool = true
    var bridge: ArchivePlayerBridge? = nil
    var onReady: (() -> Void)? = nil
    var onFailed: ((String) -> Void)? = nil
    var onProgress: ((Double, Double) -> Void)? = nil
    var onVideoSize: ((CGSize) -> Void)? = nil
    /// When set, seek once then clear via `onSeekConsumed`.
    var seekToSeconds: Double? = nil
    var onSeekConsumed: (() -> Void)? = nil
    /// Sparks player: bump on page focus so clip always starts at t=0.
    var restartFromBeginningToken: UInt = 0
    /// User pause while page is still focused — freeze frame, don't deactivate / seek to 0.
    var isPausedByUser: Bool = false
    /// Global continuous Hubs player — protected from tab-switch silence.
    var isContinuousHubPlayer: Bool = false

    final class Coordinator {
        var lastURL: URL?
        var lastActive: Bool?
        var lastMuted: Bool?
        var lastSeekToken: Double?
        var lastRestartToken: UInt = 0
        var lastUserPaused: Bool = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var videoGravity: AVLayerVideoGravity {
        fillsFrame ? .resizeAspectFill : .resizeAspect
    }

    func makeUIViewController(context: Context) -> ArchiveVideoPlayerController {
        let vc = ArchiveVideoPlayerController()
        vc.loops = loops
        vc.postID = postID
        vc.isContinuousHubPlayer = isContinuousHubPlayer
        vc.restartsFromBeginningOnFocus = restartFromBeginningToken > 0
        vc.onReady = onReady
        vc.onFailed = onFailed
        vc.onProgress = onProgress
        vc.onVideoSize = onVideoSize
        vc.onPlayingChanged = { [weak bridge] playing in
            bridge?.publishPlaying(playing)
        }
        bridge?.controller = vc
        bridge?.publishMuted(muted)
        context.coordinator.lastURL = url
        context.coordinator.lastActive = isActive
        context.coordinator.lastMuted = muted
        context.coordinator.lastRestartToken = restartFromBeginningToken
        // Gravity BEFORE configure/install — never play one frame at fill then snap to fit.
        vc.applyVideoGravity(videoGravity)
        // Sparks always start at 0.
        let initialStart = restartFromBeginningToken > 0 ? 0 : startTime
        vc.configure(url: url, posterURL: posterURL, muted: muted, startTime: initialStart, active: isActive)
        // Sparks: pass all touches through to the SwiftUI ScrollView (critical for first swipe).
        vc.view.isUserInteractionEnabled = interactive
        vc.view.isMultipleTouchEnabled = false
        return vc
    }

    func updateUIViewController(_ vc: ArchiveVideoPlayerController, context: Context) {
        // Gravity first on every update so install paths never see the wrong default.
        vc.applyVideoGravity(videoGravity)
        vc.loops = loops
        vc.postID = postID
        vc.isContinuousHubPlayer = isContinuousHubPlayer
        vc.restartsFromBeginningOnFocus = restartFromBeginningToken > 0
        vc.onReady = onReady
        vc.onFailed = onFailed
        vc.onProgress = onProgress
        vc.onVideoSize = onVideoSize
        vc.view.isUserInteractionEnabled = interactive
        vc.view.isMultipleTouchEnabled = false
        vc.onPlayingChanged = { [weak bridge] playing in
            bridge?.publishPlaying(playing)
        }
        bridge?.controller = vc

        let urlChanged = context.coordinator.lastURL != url
        let activeChanged = context.coordinator.lastActive != isActive
        let mutedChanged = context.coordinator.lastMuted != muted
        let restartChanged = context.coordinator.lastRestartToken != restartFromBeginningToken
        let pauseChanged = context.coordinator.lastUserPaused != isPausedByUser

        if urlChanged {
            context.coordinator.lastURL = url
            context.coordinator.lastActive = isActive
            context.coordinator.lastMuted = muted
            context.coordinator.lastRestartToken = restartFromBeginningToken
            context.coordinator.lastUserPaused = isPausedByUser
            let initialStart = restartFromBeginningToken > 0 ? 0 : startTime
            vc.configure(url: url, posterURL: posterURL, muted: muted, startTime: initialStart, active: isActive && !isPausedByUser)
            if isActive, isPausedByUser {
                vc.pauseKeepingFrame()
            }
            return
        }

        // Only react to real state changes — do not re-kick play on every SwiftUI redraw
        // (that caused Sparks to start, restart, then settle).
        if mutedChanged {
            context.coordinator.lastMuted = muted
            vc.setMuted(muted)
        }
        // User pause/unpause while still on the page — freeze frame, never seek to 0.
        if pauseChanged {
            context.coordinator.lastUserPaused = isPausedByUser
            if isPausedByUser {
                vc.pauseKeepingFrame()
            } else if isActive {
                vc.setMuted(muted)
                vc.setActive(true)
            }
        }
        // Focus restart is token-only. Never also restart on active flip — that double-fired
        // (play in wrong frame → re-layout → play again = “angle then center”).
        if restartChanged {
            context.coordinator.lastRestartToken = restartFromBeginningToken
            context.coordinator.lastActive = isActive
            if isActive, !isPausedByUser, restartFromBeginningToken > 0 {
                vc.setMuted(muted)
                vc.restartFromBeginningAndPlay()
            } else if isActive, isPausedByUser {
                vc.pauseKeepingFrame()
            } else if !isActive {
                vc.restartsFromBeginningOnFocus = restartFromBeginningToken > 0
                vc.setActive(false)
            }
        } else if activeChanged {
            context.coordinator.lastActive = isActive
            if isActive {
                vc.setMuted(muted)
                if isPausedByUser {
                    vc.pauseKeepingFrame()
                } else if restartFromBeginningToken > 0 {
                    // Token already applied earlier this focus — resume only, do not re-seek.
                    vc.ensureContinuingPlayback()
                } else {
                    vc.setActive(true)
                }
            } else {
                vc.setActive(false)
            }
        } else if isActive {
            // Keep mute in sync even when only coordinator paused/muted us.
            vc.setMuted(muted)
        }

        // Sparks timeline scrub — apply once per request, then clear token so re-seeks work.
        if seekToSeconds == nil {
            context.coordinator.lastSeekToken = nil
        } else if let target = seekToSeconds, context.coordinator.lastSeekToken != target {
            context.coordinator.lastSeekToken = target
            vc.seek(to: target)
            // Keep playing after scrub when the page is active.
            if isActive {
                vc.setActive(true)
            }
            DispatchQueue.main.async {
                onSeekConsumed?()
            }
        }
    }

    static func dismantleUIViewController(_ vc: ArchiveVideoPlayerController, coordinator: Coordinator) {
        vc.teardown()
    }
}

final class ArchiveVideoPlayerController: UIViewController {
    private(set) var sourceURL: URL?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var statusObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var didRetry = false
    private var didKickPlayback = false
    private var resolvedPlayURL: URL?

    private let posterView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()

    var onReady: (() -> Void)?
    var onFailed: ((String) -> Void)?
    var onProgress: ((Double, Double) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    var onVideoSize: ((CGSize) -> Void)?
    private var presentationSizeObs: NSKeyValueObservation?
    private var didReportVideoSize = false
    /// Sparks loop by default so clips don't freeze on the last frame.
    var loops = true
    /// Used to claim a pre-buffered player from SparkWarmPool.
    var postID: String?

    /// User intent — survives SwiftUI re-renders during pull-down drag.
    private var userWantsPlayback = true
    /// True while scrubbing timeline (paused for seek, but intent may still be play).
    private var isScrubbing = false
    /// Remember play intent across a scrub (pause-for-seek must not clear it).
    private var resumeAfterScrub = true
    /// Last known playhead — used when remounting so mini↔full never restarts at 0.
    private var lastKnownSeconds: Double = 0
    /// Chrome / user mute — separate from forced silence when the Spark page is inactive.
    private var mutedFlag = false
    /// Epoch captured when this surface last became active (invalidated on page change).
    private var activePageEpoch: UInt64 = 0
    private var interruptResumeObserver: NSObjectProtocol?
    private var continuousPlayObserver: NSObjectProtocol?
    private var continuousMuteObserver: NSObjectProtocol?

    var isPlaying: Bool {
        (player?.rate ?? 0) > 0.01
    }

    var isMuted: Bool {
        mutedFlag
    }

    var currentSeconds: Double {
        if let t = player?.currentTime().seconds, t.isFinite, t >= 0 {
            return t
        }
        return lastKnownSeconds
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Clear bed — black backgrounds show as gaps around aspectFit frames.
        view.backgroundColor = .clear
        view.clipsToBounds = true

        // Default fill — matches FB/IG; may switch to fit for wide clips only.
        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.backgroundColor = .clear
        posterView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(posterView)
        view.backgroundColor = .black

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        errorLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        errorLabel.font = .preferredFont(forTextStyle: .caption1)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 3
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            posterView.topAnchor.constraint(equalTo: view.topAnchor),
            posterView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            posterView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        // Screenshots fire willResignActive — never leave Hubs/Sparks paused after that.
        interruptResumeObserver = NotificationCenter.default.addObserver(
            forName: .matteryaResumePlaybackAfterInterrupt,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensureContinuingPlayback()
        }
        // Mini chrome lives in SwiftUI above/with film; play/mute must not re-host the tree.
        continuousPlayObserver = NotificationCenter.default.addObserver(
            forName: .matteryaHubContinuousSetPlaying,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Only the live continuous hubs surface — never feed/archive cells.
            guard let self, self.isContinuousHubPlayer, self.player != nil else { return }
            let playing = (note.userInfo?["playing"] as? Bool) ?? true
            if playing {
                self.setActive(true)
                self.ensureContinuingPlayback()
            } else {
                self.pauseKeepingFrame()
            }
        }
        continuousMuteObserver = NotificationCenter.default.addObserver(
            forName: .matteryaHubContinuousSetMuted,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, self.isContinuousHubPlayer, self.player != nil else { return }
            let muted = (note.userInfo?["muted"] as? Bool) ?? false
            self.setMuted(muted)
        }
    }

    deinit {
        if let interruptResumeObserver {
            NotificationCenter.default.removeObserver(interruptResumeObserver)
        }
        if let continuousPlayObserver {
            NotificationCenter.default.removeObserver(continuousPlayObserver)
        }
        if let continuousMuteObserver {
            NotificationCenter.default.removeObserver(continuousMuteObserver)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 2, view.bounds.height > 2 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Layer tracks the host view only — never a larger “screen” frame (that zoomed/cropped).
        playerLayer?.frame = view.bounds
        playerLayer?.videoGravity = preferredVideoGravity
        playerLayer?.opacity = 1
        CATransaction.commit()
    }

    /// Default fill (FB/IG); landscape Sparks may switch to fit when crop would be hard.
    private var preferredVideoGravity: AVLayerVideoGravity = .resizeAspectFill

    func applyVideoGravity(_ gravity: AVLayerVideoGravity) {
        preferredVideoGravity = gravity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.videoGravity = gravity
        if view.bounds.width > 2, view.bounds.height > 2 {
            playerLayer?.frame = view.bounds
        }
        playerLayer?.opacity = 1
        playerLayer?.backgroundColor = UIColor.black.cgColor
        CATransaction.commit()
        posterView.contentMode = gravity == .resizeAspectFill ? .scaleAspectFill : .scaleAspectFit
        view.backgroundColor = .black
    }

    func configure(url: URL, posterURL: URL?, muted: Bool, startTime: Double, active: Bool) {
        // Same source already loading/playing — don't tear down and restart (Sparks restart bug).
        if sourceURL == url, player != nil || loadTask != nil {
            setMuted(muted)
            if active {
                userWantsPlayback = true
                ensureContinuingPlayback()
            } else {
                setActive(false)
            }
            return
        }

        sourceURL = url
        didRetry = false
        didKickPlayback = false
        didReportVideoSize = false
        // Do NOT reset preferredVideoGravity here — SwiftUI already set fill vs fit via
        // `applyVideoGravity` from `fillsFrame`. Forcing fill re-cropped Hubs watch.
        presentationSizeObs?.invalidate()
        presentationSizeObs = nil
        resolvedPlayURL = nil
        errorLabel.isHidden = true
        loadPoster(posterURL)
        setMuted(muted)
        if active {
            startPlayback(url: url, muted: muted, startTime: startTime, autoplay: true)
        } else {
            // Always pre-buffer off-screen Sparks (silent) so swipe-in is pure play — no black flash.
            startPlayback(url: url, muted: true, startTime: restartsFromBeginningOnFocus ? 0 : startTime, autoplay: false)
        }
    }

    /// Publish natural size so Hubs can size the stage without cropping.
    func reportVideoSizeIfNeeded(from item: AVPlayerItem? = nil) {
        let target = item ?? player?.currentItem
        guard let target else { return }
        let size = target.presentationSize
        guard size.width > 2, size.height > 2 else { return }
        if !didReportVideoSize {
            didReportVideoSize = true
            onVideoSize?(size)
        } else {
            onVideoSize?(size)
        }
        // Keep observing in case the first non-zero size arrives late.
        if presentationSizeObs == nil {
            presentationSizeObs = target.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
                let s = item.presentationSize
                guard s.width > 2, s.height > 2 else { return }
                DispatchQueue.main.async {
                    self?.didReportVideoSize = true
                    self?.onVideoSize?(s)
                }
            }
        }
    }

    /// When true (Sparks player), becoming focused always seeks to t=0.
    var restartsFromBeginningOnFocus = false
    /// Continuous Hubs mini/watch — protected from tab-switch silence.
    var isContinuousHubPlayer = false

    /// Exposed for continuous-hub protection registration.
    var avPlayer: AVPlayer? { player }

    func setActive(_ active: Bool) {
        if active {
            userWantsPlayback = true
            activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
            // Do NOT restart-from-0 here. Sparks focus restarts only via
            // `restartFromBeginningAndPlay()` (token). Calling both caused
            // play → re-layout → play (video “jumps to center” and restarts).
            //
            // After Sparks dismiss, stopAllPlayback may have nil'd currentItem while
            // the AVPlayer shell remains → audio-only / black until reconfigure.
            if let player, player.currentItem == nil, let sourceURL {
                let resume = restartsFromBeginningOnFocus
                    ? 0
                    : max(lastKnownSeconds, currentSeconds)
                startPlayback(
                    url: sourceURL,
                    muted: mutedFlag,
                    startTime: resume > 0.5 ? resume : 0,
                    autoplay: true
                )
                return
            }
            if let player {
                if isContinuousHubPlayer {
                    MediaPlaybackCoordinator.shared.protectContinuous(player)
                }
                applyUserAudioOutput(on: player)
                _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                    keeping: player,
                    pageEpoch: isContinuousHubPlayer ? nil : activePageEpoch
                )
                // Re-assert layer geometry so video paints (not audio-only black).
                if view.bounds.width > 2, view.bounds.height > 2 {
                    playerLayer?.frame = view.bounds
                    playerLayer?.opacity = 1
                    playerLayer?.isHidden = false
                }
                // Already playing continuous film — never re-cover with poster (mini freeze).
                if isContinuousHubPlayer || didKickPlayback {
                    posterView.isHidden = true
                }
                if player.currentItem != nil {
                    player.play()
                    player.safePlayImmediately(atRate: 1.0)
                    DispatchQueue.main.async { [weak self] in
                        self?.onPlayingChanged?(true)
                    }
                }
            }
            if player != nil {
                ensureContinuingPlayback()
            } else if let sourceURL {
                // Remount recovery — resume near last progress, never hard-restart at 0.
                let resume = restartsFromBeginningOnFocus
                    ? 0
                    : max(lastKnownSeconds, currentSeconds)
                startPlayback(
                    url: sourceURL,
                    muted: mutedFlag,
                    startTime: resume > 0.5 ? resume : 0
                )
            }
        } else {
            isScrubbing = false
            // Continuous Hubs: layout thrash during mini/tab morph must not kill audio.
            // Intentional pause uses pauseKeepingFrame / continuous play notification only.
            if isContinuousHubPlayer {
                if let player {
                    MediaPlaybackCoordinator.shared.protectContinuous(player)
                }
                // Keep last frame visible — never flash poster/black mid-mini.
                posterView.isHidden = true
                spinner.stopAnimating()
                return
            }
            userWantsPlayback = false
            // Silence inactive pages — prevents stacked audio. mutedFlag stays as user choice.
            player?.pause()
            player?.isMuted = true
            player?.volume = 0
            // Keep last frame only if we already painted one; otherwise show poster (no black).
            posterView.isHidden = didKickPlayback
            spinner.stopAnimating()
            // Pre-seek to start while off-screen so next focus is a pure play().
            if restartsFromBeginningOnFocus {
                softSeekToBeginning(playAfter: false)
            }
            DispatchQueue.main.async { [weak self] in
                self?.onPlayingChanged?(false)
            }
        }
    }

    /// User pause on focused Spark — freeze current frame (no seek, no poster swap).
    func pauseKeepingFrame() {
        userWantsPlayback = false
        isScrubbing = false
        player?.pause()
        // Keep layer visible + unmuted flag for instant resume; volume can stay.
        posterView.isHidden = true
        spinner.stopAnimating()
        DispatchQueue.main.async { [weak self] in
            self?.onPlayingChanged?(false)
        }
    }

    /// Soft start seek — skip if already at t≈0; never play-then-snap (mid-clip first frame).
    private func softSeekToBeginning(playAfter: Bool) {
        lastKnownSeconds = 0
        guard let player, player.currentItem != nil else { return }
        // True start only — wide windows (<1s) caused free-play from mid-buffer then jump.
        if SparkWarmPool.isAtStart(player) {
            posterView.isHidden = true
            spinner.stopAnimating()
            if playAfter, userWantsPlayback {
                applyUserAudioOutput(on: player)
                _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                    keeping: player,
                    pageEpoch: activePageEpoch
                )
                player.play()
                player.safePlayImmediately(atRate: 1.0)
                onPlayingChanged?(true)
            }
            return
        }
        posterView.isHidden = true
        player.pause()
        player.rate = 0
        player.seek(
            to: .zero,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished, let self else { return }
            Task { @MainActor in
                self.lastKnownSeconds = 0
                self.posterView.isHidden = true
                self.spinner.stopAnimating()
                guard playAfter, self.userWantsPlayback else { return }
                _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                    keeping: player,
                    pageEpoch: self.activePageEpoch
                )
                self.applyUserAudioOutput(on: player)
                player.play()
                player.safePlayImmediately(atRate: 1.0)
                self.onPlayingChanged?(true)
                let duration = player.currentItem?.duration.seconds ?? 0
                let dur = (duration.isFinite && duration > 0) ? duration : 0
                self.onProgress?(0, dur)
            }
        }
    }

    /// Sparks page focus / scroll-to: play from t=0 instantly when already parked there.
    func restartFromBeginningAndPlay() {
        userWantsPlayback = true
        isScrubbing = false
        activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
        lastKnownSeconds = 0
        posterView.isHidden = true
        spinner.stopAnimating()
        if let player, player.currentItem != nil {
            // Instant path: already at exact start → play, never seek-after-play.
            if SparkWarmPool.isAtStart(player) {
                posterView.isHidden = true
                spinner.stopAnimating()
                applyUserAudioOutput(on: player)
                _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                    keeping: player,
                    pageEpoch: activePageEpoch
                )
                player.play()
                player.safePlayImmediately(atRate: 1.0)
                onPlayingChanged?(true)
                return
            }
            // Mid-clip: seek to exact 0 first, then play (never play-then-adjust).
            softSeekToBeginning(playAfter: true)
            return
        }
        if let sourceURL {
            startPlayback(url: sourceURL, muted: mutedFlag, startTime: 0)
        }
    }

    /// Resume only if genuinely stalled — never re-seek or re-create the item.
    /// Never **steal** solo from another Spark (comments overlay used to wake older pages).
    func ensureContinuingPlayback() {
        guard userWantsPlayback, !isScrubbing, let player else { return }
        // Continuous Hubs always reclaims solo (tab switch may have reassigned).
        if isContinuousHubPlayer {
            MediaPlaybackCoordinator.shared.protectContinuous(player)
            _ = MediaPlaybackCoordinator.shared.soloSparkAudio(keeping: player)
        } else {
            // Only the current solo may resume. Off-screen / previous Sparks stay silent.
            guard MediaPlaybackCoordinator.shared.isSolo(player) else {
                player.pause()
                player.isMuted = true
                player.volume = 0
                return
            }
        }
        applyUserAudioOutput(on: player)
        if player.rate < 0.05 {
            player.play()
            player.safePlayImmediately(atRate: 1.0)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPlayingChanged?(true)
        }
    }

    func setMuted(_ muted: Bool) {
        mutedFlag = muted
        // Apply when this surface is allowed to make sound (active playback intent).
        if userWantsPlayback, let player {
            applyUserAudioOutput(on: player)
        }
    }

    /// Restore mute/volume from the user's mute chrome (not the inactive force-silence).
    private func applyUserAudioOutput(on player: AVPlayer) {
        // Only claim solo when this surface still wants playback — otherwise a
        // late readyToPlay on a previous Spark steals audio from the current page.
        guard userWantsPlayback else {
            player.pause()
            player.isMuted = true
            player.volume = 0
            return
        }
        guard MediaPlaybackCoordinator.shared.soloSparkAudio(
            keeping: player,
            pageEpoch: activePageEpoch
        ) else {
            return
        }
        configureAudioSession()
        player.isMuted = mutedFlag
        player.volume = mutedFlag ? 0 : 1
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.rate > 0.01 || player.timeControlStatus == .playing {
            userWantsPlayback = false
            player.pause()
            DispatchQueue.main.async { [weak self] in
                self?.onPlayingChanged?(false)
            }
        } else {
            // Resume: inactive path force-mutes the AVPlayer — must restore mutedFlag or audio is gone.
            userWantsPlayback = true
            isScrubbing = false
            applyUserAudioOutput(on: player)
            player.play()
            player.safePlayImmediately(atRate: 1.0)
            DispatchQueue.main.async { [weak self] in
                self?.onPlayingChanged?(true)
            }
        }
    }

    func seek(to seconds: Double, resumeIfWanted: Bool = false) {
        guard let player else { return }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        lastKnownSeconds = max(0, seconds)
        // Precise scrub seek, then resume from the landed frame when requested.
        let shouldResume = resumeIfWanted || (userWantsPlayback && !isScrubbing)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished, let self else { return }
            DispatchQueue.main.async {
                self.lastKnownSeconds = max(0, seconds)
                guard shouldResume, self.userWantsPlayback, !self.isScrubbing else { return }
                self.applyUserAudioOutput(on: player)
                player.play()
                player.safePlayImmediately(atRate: 1.0)
                self.onPlayingChanged?(true)
            }
        }
    }

    /// Pause only for timeline scrub — does **not** clear play intent / AppState playing.
    func beginScrub() {
        // Scrub while watching → always resume after; scrub while already paused stays paused
        // only if the user had intentionally paused (userWantsPlayback false).
        resumeAfterScrub = userWantsPlayback
        isScrubbing = true
        // Soft pause for a stable scrub frame — do NOT publish "paused" (that killed Hubs play).
        player?.pause()
    }

    /// Seek to the scrubbed time and keep playing from that moment.
    func endScrub(at seconds: Double? = nil) {
        isScrubbing = false
        if resumeAfterScrub {
            userWantsPlayback = true
        }
        // Hubs continuous player may have had epoch bumped while we scrubbed — re-bind.
        activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
        let target = seconds ?? lastKnownSeconds
        lastKnownSeconds = max(0, target)
        guard let player else {
            if resumeAfterScrub { onPlayingChanged?(true) }
            return
        }
        let time = CMTime(seconds: max(0, target), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished, let self else { return }
            DispatchQueue.main.async {
                guard self.userWantsPlayback || self.resumeAfterScrub else {
                    self.onPlayingChanged?(false)
                    return
                }
                self.userWantsPlayback = true
                self.activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
                // Claim solo again — page-change silence may have cleared it mid-scrub.
                _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                    keeping: player,
                    pageEpoch: self.activePageEpoch
                )
                self.applyUserAudioOutput(on: player)
                player.play()
                player.safePlayImmediately(atRate: 1.0)
                self.onPlayingChanged?(true)
            }
        }
    }

    func teardown() {
        loadTask?.cancel()
        loadTask = nil
        removeObservers()
        if let player {
            player.pause()
            player.isMuted = true
            player.volume = 0
            if let postID, player.currentItem != nil, player.status != .failed {
                // Park buffered item for instant scroll-back (feed Sparks + hubs shares).
                SparkWarmPool.shared.park(postID: postID, player: player)
            } else {
                if let postID {
                    SparkWarmPool.shared.release(postID: postID)
                }
                player.replaceCurrentItem(with: nil)
                MediaPlaybackCoordinator.shared.unregister(player)
            }
        } else if let postID {
            SparkWarmPool.shared.release(postID: postID)
        }
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        // Don't deactivate the whole audio session here — other feed cards may still be live.
    }

    private func startPlayback(url: URL, muted: Bool, startTime: Double, autoplay: Bool = true) {
        loadTask?.cancel()
        errorLabel.isHidden = true
        userWantsPlayback = autoplay
        activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch

        // Claim by postID when the warm item is healthy (claim() rejects failed items).
        if let postID, let claimed = SparkWarmPool.shared.claim(postID: postID) {
            installClaimedPlayerSync(claimed, original: url, muted: muted, startTime: startTime, autoplay: autoplay)
            return
        }

        // Never spin on Sparks swipe — poster stays until first frame.
        spinner.stopAnimating()
        loadTask = Task { [weak self] in
            guard let self else { return }

            // Only wait on warm if one is already in-flight / parked — never add a fixed
            // 400ms stall on a true cold open (that made every hubs share feel laggy).
            if let postID {
                SparkWarmPool.shared.warmSingle(postID: postID, url: url)
                if SparkWarmPool.shared.hasWarmOrInflight(postID: postID) {
                    let timeout: TimeInterval = ArchiveVideoPlayback.isArchiveURL(url) ? 0.28 : 0.18
                    await SparkWarmPool.shared.awaitReady(postIDs: [postID], timeout: timeout)
                    if let claimed = SparkWarmPool.shared.claim(postID: postID) {
                        await MainActor.run {
                            self.installClaimedPlayerSync(
                                claimed,
                                original: url,
                                muted: muted,
                                startTime: startTime,
                                autoplay: autoplay
                            )
                        }
                        return
                    }
                }
                SparkWarmPool.shared.markInUse(postID: postID)
            }

            // Resolve live play URL: Archive CDN hop, or R2 re-presign (pub-*.r2.dev often 403).
            let playURL: URL
            if ArchiveVideoPlayback.isArchiveURL(url) {
                playURL = await ArchiveVideoPlayback.resolvedPlaybackURL(for: url)
            } else if MediaURLResolver.looksLikeR2HostedURL(url), let postID, !postID.isEmpty {
                // Never hand AVPlayer a dead public R2 link — always ask API for a signed GET.
                playURL = await R2PlaybackResolver.shared.playURL(postID: postID, fallback: url) ?? url
            } else {
                playURL = await MediaURLResolver.playbackConfiguration(for: url, postID: postID).url
            }
            guard !Task.isCancelled else { return }
            await self.installPlayer(url: playURL, original: url, muted: muted, startTime: startTime)
            if !autoplay {
                self.userWantsPlayback = false
                self.player?.pause()
                self.player?.isMuted = true
                self.player?.volume = 0
                if self.restartsFromBeginningOnFocus {
                    self.softSeekToBeginning(playAfter: false)
                }
            }
        }
    }

    /// Sync warm-pool claim: attach layer + play now. Seek only if not already near 0.
    private func installClaimedPlayerSync(
        _ claimed: AVPlayer,
        original: URL,
        muted: Bool,
        startTime: Double,
        autoplay: Bool = true
    ) {
        removeObservers()
        if let existing = player, existing !== claimed {
            existing.pause()
            MediaPlaybackCoordinator.shared.unregister(existing)
        }
        playerLayer?.removeFromSuperlayer()
        didKickPlayback = false
        userWantsPlayback = autoplay

        claimed.automaticallyWaitsToMinimizeStalling = false
        claimed.actionAtItemEnd = loops ? .none : .pause
        mutedFlag = muted

        let layer = AVPlayerLayer(player: claimed)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.videoGravity = preferredVideoGravity
        layer.frame = view.bounds
        layer.opacity = 1
        layer.backgroundColor = UIColor.black.cgColor
        view.layer.insertSublayer(layer, above: posterView.layer)
        CATransaction.commit()
        playerLayer = layer
        player = claimed
        resolvedPlayURL = original
        MediaPlaybackCoordinator.shared.register(claimed)
        if autoplay {
            configureAudioSession()
        }
        spinner.stopAnimating()
        errorLabel.isHidden = true
        claimed.pause()
        claimed.rate = 0

        let atStart = SparkWarmPool.isAtStart(claimed)
        let needsExactStart = restartsFromBeginningOnFocus || startTime < 0.5

        let playNow = {
            if self.view.bounds.width > 2 {
                self.playerLayer?.frame = self.view.bounds
            }
            guard autoplay, self.userWantsPlayback else {
                // Prebuffer / off-screen: keep poster so scroll never paints a black layer.
                claimed.isMuted = true
                claimed.volume = 0
                claimed.pause()
                self.posterView.isHidden = false
                return
            }
            // IG/YT: keep poster until rate is real — never hide before first paint.
            self.posterView.isHidden = false
            _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                keeping: claimed,
                pageEpoch: self.activePageEpoch
            )
            claimed.isMuted = muted
            claimed.volume = muted ? 0 : 1
            claimed.safePlayImmediately(atRate: 1.0)
            self.didKickPlayback = true
            self.revealPosterWhenFramesReady(claimed)
            self.reportVideoSizeIfNeeded(from: claimed.currentItem)
            self.onReady?()
        }

        if atStart || !needsExactStart {
            lastKnownSeconds = 0
            playNow()
        } else {
            claimed.isMuted = true
            claimed.volume = 0
            claimed.seek(
                to: .zero,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [weak self] finished in
                guard finished, let self else { return }
                DispatchQueue.main.async {
                    self.lastKnownSeconds = 0
                    playNow()
                }
            }
        }

        if let item = claimed.currentItem {
            statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        if !self.didKickPlayback, self.userWantsPlayback {
                            // Keep poster until rate — readyToPlay still paints black briefly.
                            self.posterView.isHidden = false
                            self.didKickPlayback = true
                            _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                                keeping: claimed,
                                pageEpoch: self.activePageEpoch
                            )
                            claimed.isMuted = self.mutedFlag
                            claimed.volume = self.mutedFlag ? 0 : 1
                            claimed.safePlayImmediately(atRate: 1.0)
                            self.revealPosterWhenFramesReady(claimed)
                            self.onReady?()
                        } else if !self.userWantsPlayback {
                            // Warm buffer ready while scrolling — keep poster, no black flash.
                            self.posterView.isHidden = false
                        }
                    case .failed:
                        self.teardown()
                        self.startPlayback(url: original, muted: muted, startTime: startTime, autoplay: autoplay)
                    default:
                        break
                    }
                }
            }
            attachLoopObserver(for: item, player: claimed)
            attachTimeObserver(for: item, player: claimed)
        }
    }

    private func attachTimeObserver(for item: AVPlayerItem, player observed: AVPlayer) {
        // Always detach from the player that owns the token (may not be `observed` yet).
        if let timeObserver, let owner = player {
            owner.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        } else if let timeObserver {
            observed.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = observed.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let current = SafeNumeric.nonNegativeSeconds(time.seconds)
            let dur = SafeNumeric.seconds(item.duration.seconds)
            let playing = observed.rate > 0.01
            let scrubbing = self.isScrubbing
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // While scrubbing, UI owns the playhead — don't fight the thumb or publish pause.
                if !scrubbing {
                    self.lastKnownSeconds = current
                    // Always publish — parent must not rely on stale isActive captures.
                    self.onProgress?(current, dur > 0 ? dur : 0)
                    self.onPlayingChanged?(playing)
                    // Drop poster only once frames are actually advancing (IG/YT).
                    if playing, self.userWantsPlayback, !self.posterView.isHidden {
                        self.posterView.isHidden = true
                    }
                    self.maybeLoopNearEnd(current: current, duration: dur > 0 ? dur : 0, player: observed)
                }
            }
        }
    }

    /// Keep poster until AVPlayer is producing frames — never black hole after thumb.
    private func revealPosterWhenFramesReady(_ player: AVPlayer) {
        if player.rate > 0.05 || player.timeControlStatus == .playing {
            posterView.isHidden = true
            onPlayingChanged?(true)
            return
        }
        Task { @MainActor [weak self] in
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 40_000_000)
                guard let self else { return }
                guard self.userWantsPlayback else { return }
                if player.rate > 0.05 || player.timeControlStatus == .playing {
                    self.posterView.isHidden = true
                    self.onPlayingChanged?(true)
                    return
                }
            }
            // Prefer poster over black if still not painting.
            if let self = self, self.userWantsPlayback, player.rate > 0.01 {
                self.posterView.isHidden = true
                self.onPlayingChanged?(true)
            }
        }
    }

    private func installClaimedPlayer(
        _ claimed: AVPlayer,
        original: URL,
        muted: Bool,
        startTime: Double
    ) async {
        removeObservers()
        player?.pause()
        if let existing = player {
            MediaPlaybackCoordinator.shared.unregister(existing)
        }
        playerLayer?.removeFromSuperlayer()
        didKickPlayback = false

        claimed.automaticallyWaitsToMinimizeStalling = false
        claimed.actionAtItemEnd = loops ? .none : .pause
        mutedFlag = muted

        let layer = AVPlayerLayer(player: claimed)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.videoGravity = preferredVideoGravity
        layer.frame = view.bounds
        layer.opacity = 1
        layer.backgroundColor = UIColor.black.cgColor
        CATransaction.commit()
        view.layer.insertSublayer(layer, above: posterView.layer)
        playerLayer = layer
        player = claimed
        resolvedPlayURL = original
        MediaPlaybackCoordinator.shared.register(claimed)
        // Sparks / warm-pool: soft-seek to 0 only when not already there (avoids black flash).
        let forcedStart = restartsFromBeginningOnFocus ? 0 : startTime
        if restartsFromBeginningOnFocus || forcedStart < 0.5 {
            let t = claimed.currentTime().seconds
            if !(t.isFinite && t >= 0 && t < 0.35) {
                await claimed.seek(
                    to: .zero,
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }
            lastKnownSeconds = 0
        }
        if userWantsPlayback {
            _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                keeping: claimed,
                pageEpoch: activePageEpoch
            )
            claimed.isMuted = muted
            claimed.volume = muted ? 0 : 1
        } else {
            claimed.pause()
            claimed.isMuted = true
            claimed.volume = 0
        }
        configureAudioSession()
        spinner.stopAnimating()
        // Only uncover the layer when we intend to play; else keep poster under scroll.
        posterView.isHidden = userWantsPlayback
        errorLabel.isHidden = true

        if let item = claimed.currentItem {
            statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        if !self.didKickPlayback {
                            self.didKickPlayback = true
                            if self.restartsFromBeginningOnFocus {
                                let t = claimed.currentTime().seconds
                                if !(t.isFinite && t >= 0 && t < 0.35) {
                                    await claimed.seek(
                                        to: .zero,
                                        toleranceBefore: .positiveInfinity,
                                        toleranceAfter: .positiveInfinity
                                    )
                                }
                                self.lastKnownSeconds = 0
                            } else if forcedStart > 0.5 {
                                await claimed.seek(to: CMTime(seconds: forcedStart, preferredTimescale: 600))
                            }
                            if self.userWantsPlayback,
                               MediaPlaybackCoordinator.shared.soloSparkAudio(
                                   keeping: claimed,
                                   pageEpoch: self.activePageEpoch
                               ) {
                                claimed.isMuted = self.mutedFlag
                                claimed.volume = self.mutedFlag ? 0 : 1
                                claimed.safePlayImmediately(atRate: 1.0)
                            } else {
                                claimed.pause()
                                claimed.isMuted = true
                                claimed.volume = 0
                            }
                            DispatchQueue.main.async { [weak self] in
                                self?.onPlayingChanged?(true)
                                self?.onReady?()
                            }
                        }
                    case .failed:
                        // Fall back to cold install.
                        self.teardown()
                        self.startPlayback(url: original, muted: muted, startTime: startTime)
                    default:
                        break
                    }
                }
            }
            // Warm-pool claims used to skip this — feed Sparks never looped.
            attachLoopObserver(for: item, player: claimed)
        }

        if userWantsPlayback {
            claimed.safePlayImmediately(atRate: 1.0)
            didKickPlayback = true
            DispatchQueue.main.async { [weak self] in
                self?.onPlayingChanged?(true)
                self?.onReady?()
            }
        }
    }

    /// Seek-to-zero + play when the item ends (Sparks / feed Spark cards).
    private func attachLoopObserver(for item: AVPlayerItem, player: AVPlayer) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        guard loops else { return }
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.loops, self.userWantsPlayback else { return }
                self.restartFromBeginning(player: player)
            }
        }
    }

    private var lastLoopRestartAt: Date = .distantPast
    private var isLoopRestarting = false

    private func restartFromBeginning(player: AVPlayer) {
        guard loops, userWantsPlayback else { return }
        let now = Date()
        if isLoopRestarting || now.timeIntervalSince(lastLoopRestartAt) < 0.35 { return }
        isLoopRestarting = true
        lastLoopRestartAt = now
        // Refresh epoch so a prior Sparks page-change doesn't block feed loop restarts.
        activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
        _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
            keeping: player,
            pageEpoch: activePageEpoch
        )
        player.actionAtItemEnd = .none
        player.isMuted = mutedFlag
        player.volume = mutedFlag ? 0 : 1
        player.pause()
        player.rate = 0
        // Exact start for Sparks — never resume mid-clip after a loop.
        player.seek(
            to: .zero,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoopRestarting = false
                guard finished, self.userWantsPlayback, self.loops else { return }
                self.activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
                _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                    keeping: player,
                    pageEpoch: self.activePageEpoch
                )
                player.isMuted = self.mutedFlag
                player.volume = self.mutedFlag ? 0 : 1
                player.play()
                player.safePlayImmediately(atRate: 1.0)
                self.lastKnownSeconds = 0
                self.onProgress?(0, player.currentItem?.duration.seconds ?? 0)
                self.onPlayingChanged?(true)
            }
        }
    }

    /// Fallback when DidPlayToEndTime never fires (some R2/HLS streams).
    private func maybeLoopNearEnd(current: Double, duration: Double, player: AVPlayer) {
        guard loops, userWantsPlayback, !isScrubbing, !isLoopRestarting else { return }
        guard duration > 0.4 else { return }
        let atEnd = current >= duration - 0.08
        let stalledAtEnd = atEnd && player.rate < 0.01
        if stalledAtEnd || current >= duration - 0.02 {
            restartFromBeginning(player: player)
        }
    }

    private func installPlayer(url: URL, original: URL, muted: Bool, startTime: Double) async {
        removeObservers()
        player?.pause()
        if let existing = player {
            MediaPlaybackCoordinator.shared.unregister(existing)
        }
        playerLayer?.removeFromSuperlayer()
        didKickPlayback = false

        // Important: no custom HTTP headers — Archive CDN + AVPlayer + headers = hang on poster.
        let asset = AVURLAsset(
            url: url,
            options: [
                AVURLAssetAllowsCellularAccessKey: true,
                AVURLAssetAllowsExpensiveNetworkAccessKey: true,
                AVURLAssetAllowsConstrainedNetworkAccessKey: true,
            ]
        )

        // Let AVPlayerItem pull playable/duration — no deprecated loadValuesAsynchronously.
        guard !Task.isCancelled else { return }

        let item = AVPlayerItem(asset: asset)
        // Hubs long-form needs a bit more head buffer; Sparks stay lighter.
        item.preferredForwardBufferDuration = loops ? 4 : 8
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.preferredPeakBitRate = 0

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = muted
        // false = kick playback as soon as enough is buffered (snappier Sparks / Hubs).
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.actionAtItemEnd = loops ? .none : .pause

        let layer = AVPlayerLayer(player: newPlayer)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.videoGravity = preferredVideoGravity
        layer.frame = view.bounds
        layer.opacity = 1
        layer.backgroundColor = UIColor.black.cgColor
        view.layer.insertSublayer(layer, above: posterView.layer)
        CATransaction.commit()
        playerLayer = layer
        player = newPlayer
        resolvedPlayURL = url
        mutedFlag = muted
        MediaPlaybackCoordinator.shared.register(newPlayer)
        if userWantsPlayback {
            configureAudioSession()
        }
        // Optimistic start — Sparks feel instant; readyToPlay will re-kick if needed.
        if userWantsPlayback,
           MediaPlaybackCoordinator.shared.soloSparkAudio(
               keeping: newPlayer,
               pageEpoch: activePageEpoch
           ) {
            newPlayer.isMuted = muted
            newPlayer.volume = muted ? 0 : 1
            newPlayer.safePlayImmediately(atRate: 1.0)
        } else {
            newPlayer.pause()
            newPlayer.isMuted = true
            newPlayer.volume = 0
        }

        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.spinner.stopAnimating()
                    self.errorLabel.isHidden = true
                    // Kick playback only once per item — double play() caused visible restarts.
                    if !self.didKickPlayback {
                        if startTime > 0.5 {
                            await newPlayer.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                        }
                        if self.userWantsPlayback,
                           MediaPlaybackCoordinator.shared.soloSparkAudio(
                               keeping: newPlayer,
                               pageEpoch: self.activePageEpoch
                           ) {
                            // Keep poster until rate — never black flash after thumb.
                            self.posterView.isHidden = false
                            self.didKickPlayback = true
                            newPlayer.isMuted = self.mutedFlag
                            newPlayer.volume = self.mutedFlag ? 0 : 1
                            newPlayer.safePlayImmediately(atRate: 1.0)
                            self.revealPosterWhenFramesReady(newPlayer)
                            DispatchQueue.main.async { [weak self] in
                                self?.onReady?()
                            }
                        } else {
                            // Prebuffer while scrolling: stay on poster (never black AVPlayerLayer).
                            newPlayer.pause()
                            newPlayer.isMuted = true
                            newPlayer.volume = 0
                            self.posterView.isHidden = false
                            DispatchQueue.main.async { [weak self] in
                                self?.onPlayingChanged?(false)
                                // Still signal ready so warm pool can claim, without chrome.
                                self?.onReady?()
                            }
                        }
                    } else if self.userWantsPlayback {
                        self.revealPosterWhenFramesReady(newPlayer)
                    } else {
                        self.posterView.isHidden = false
                    }
                    #if DEBUG
                    print("[ArchiveVideo] ready \(url.host ?? "") rate=\(newPlayer.rate)")
                    #endif
                case .failed:
                    let msg = item.error?.localizedDescription ?? "Playback failed"
                    #if DEBUG
                    print("[ArchiveVideo] item failed: \(msg)")
                    #endif
                    await self.handleFailure(
                        message: msg,
                        original: original,
                        attempted: url,
                        muted: muted,
                        startTime: startTime
                    )
                default:
                    break
                }
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let current = max(0, time.seconds)
            let duration = item.duration.seconds
            let dur = duration.isFinite && duration > 0 ? duration : 0
            let playing = newPlayer.rate > 0.01
            let scrubbing = self.isScrubbing
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !scrubbing {
                    self.lastKnownSeconds = current
                    self.onProgress?(current, dur)
                    self.onPlayingChanged?(playing)
                    self.maybeLoopNearEnd(current: current, duration: dur, player: newPlayer)
                }
            }
        }

        attachLoopObserver(for: item, player: newPlayer)
    }

    private func handleFailure(
        message: String,
        original: URL,
        attempted: URL,
        muted: Bool,
        startTime: Double
    ) async {
        // One retry: re-resolve archive.org/download → CDN (or flip back to the other URL).
        if !didRetry {
            didRetry = true
            let retryURL: URL
            if attempted == original {
                retryURL = await ArchiveVideoPlayback.resolvedPlaybackURL(for: original)
            } else {
                // CDN failed — try a fresh resolve from the download URL (cache may be stale).
                let again = await ArchiveVideoPlayback.resolvedPlaybackURL(for: original)
                retryURL = again != attempted ? again : original
            }
            if retryURL.absoluteString != attempted.absoluteString {
                #if DEBUG
                print("[ArchiveVideo] retry \(attempted.host ?? "") → \(retryURL.host ?? retryURL.absoluteString)")
                #endif
                await installPlayer(url: retryURL, original: original, muted: muted, startTime: startTime)
                return
            }
        }

        spinner.stopAnimating()
        posterView.isHidden = false
        errorLabel.isHidden = false
        errorLabel.text = "Can't play this video\n\(message)"
        onFailed?(message)
    }

    private func pauseOnly() {
        player?.pause()
        spinner.stopAnimating()
    }

    private func removeObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true, options: [])
    }

    private func loadPoster(_ url: URL?) {
        posterView.isHidden = false
        posterView.image = nil
        guard let url else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    self.posterView.image = image
                }
            } catch {
                // Keep black / spinner.
            }
        }
    }
}
