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
    @Published var playbackRate: Float = 1.0

    /// Apply progress on the main actor — skip no-op publishes (0.25s ticks were rebuilding chrome).
    func applyProgress(current: Double, duration: Double, playing: Bool?) {
        if abs(currentSeconds - current) >= 0.2 {
            currentSeconds = current
        }
        if duration > 0, abs(durationSeconds - duration) >= 0.05 {
            durationSeconds = duration
        }
        if let playing, playing != isPlaying {
            isPlaying = playing
        }
    }

    /// Scrub thumb — sync write, already on main from the gesture.
    func applyScrubFraction(_ fraction: Double) {
        guard durationSeconds > 0 else { return }
        currentSeconds = fraction * durationSeconds
    }

    /// Hop to main only when the caller may be off-main (AV callbacks).
    nonisolated func publishPlaying(_ playing: Bool) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if self.isPlaying != playing { self.isPlaying = playing }
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                if self.isPlaying != playing { self.isPlaying = playing }
            }
        }
    }

    nonisolated func publishProgress(current: Double, duration: Double, playing: Bool?) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.applyProgress(current: current, duration: duration, playing: playing)
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.applyProgress(current: current, duration: duration, playing: playing)
            }
        }
    }

    nonisolated func publishReady(playing: Bool = true) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if !self.isReady { self.isReady = true }
                if self.isPlaying != playing { self.isPlaying = playing }
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                if !self.isReady { self.isReady = true }
                if self.isPlaying != playing { self.isPlaying = playing }
            }
        }
    }

    nonisolated func publishMuted(_ muted: Bool) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if self.isMuted != muted { self.isMuted = muted }
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                if self.isMuted != muted { self.isMuted = muted }
            }
        }
    }

    func togglePlayPause() {
        controller?.togglePlayPause()
        let next = controller?.isPlaying ?? false
        if isPlaying != next { isPlaying = next }
    }

    func seek(to seconds: Double, resumeIfWanted: Bool = false) {
        currentSeconds = seconds
        controller?.seek(to: seconds, resumeIfWanted: resumeIfWanted)
    }

    func toggleMute() {
        let next = !(controller?.isMuted ?? isMuted)
        controller?.setMuted(next)
        if isMuted != next { isMuted = next }
    }

    func skip(by delta: Double) {
        let target = max(0, min(durationSeconds, currentSeconds + delta))
        // ±10s must keep playing from the new time (never land paused).
        seek(to: target, resumeIfWanted: true)
        if !isPlaying { isPlaying = true }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        controller?.setPlaybackRate(rate)
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
        if !isPlaying { isPlaying = true }
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
    /// When true, crop to fill (Sparks / feed hubs film). Expanded watch uses false.
    var fillsFrame: Bool = false
    /// Top strip for mute so fill doesn’t crop the control.
    var topChromeReserve: CGFloat = 0
    /// Bottom strip for feed timeline so fill doesn’t crop scrubber/buttons.
    var bottomChromeReserve: CGFloat = 0
    /// Feed hubs: chrome hidden until tap; 3s auto-hide; tap again dismisses.
    var tapToRevealControls: Bool = false
    /// Hubs long-form CC. Feed passes true; Sparks must never enable.
    var allowsCaptions: Bool = true
    @Binding var isMuted: Bool
    var onReady: (() -> Void)? = nil
    /// Keeps AppState.hubPlaybackPlaying in sync when chrome play/pause is used.
    var onPlayingChange: ((Bool) -> Void)? = nil
    /// Progress for Frame 0 hold (feed/hubs) — current seconds, duration.
    var onProgress: ((Double, Double) -> Void)? = nil
    /// Natural video size — feed Spark cards resize stage from this.
    var onVideoSize: ((CGSize) -> Void)? = nil

    var allowsFullscreen: Bool = true
    /// When true, FS chrome shows the exit icon (continuous landscape mode).
    var isLandscapeFullscreen: Bool = false
    /// Keep the same AVPlayer when Sparks opens over hubs mini (resume mid-clip, no black).
    var protectAsContinuousHubs: Bool = false
    /// Bumped by AppState.requestHubFullscreen (meta pull) to open landscape FS.
    var externalFullscreenToken: Int = 0
    /// Prefer this over remounting `MatteryaLandscapeFullscreenPlayer` (YouTube-smooth).
    /// Continuous hubs + feed handoff set this to toggle AppState landscape FS.
    var onFullscreenToggle: (() -> Void)? = nil

    @StateObject private var bridge = ArchivePlayerBridge()
    @State private var showChrome = false
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var showFullscreen = false
    /// Local speed when no external binding (feed/archive embeds).
    @State private var localPlaybackRate: Float = 1.0

    /// Optional shared rate (continuous Hubs AppState) — keeps expand/mini/FS in sync.
    var playbackRate: Binding<Float>? = nil

    private static let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// Always start off — never inherit CC from a previous video / UserDefaults.
    @State private var captionsEnabled = false
    @State private var transcript: TranscriptService.Transcript?
    @State private var activeCaption: String?
    @State private var captionsHint: String?
    @State private var liveCaptionHandle: LiveCaptionHandle?
    @State private var captionClock = CaptionPlayheadClock()

    private var activePlaybackRate: Float {
        playbackRate?.wrappedValue ?? localPlaybackRate
    }

    init(
        url: URL,
        posterURL: URL? = nil,
        isActive: Bool = true,
        startTime: Double = 0,
        postID: String? = nil,
        showsControls: Bool = true,
        loops: Bool = false,
        fillsFrame: Bool = false,
        topChromeReserve: CGFloat = 0,
        bottomChromeReserve: CGFloat = 0,
        tapToRevealControls: Bool = false,
        allowsCaptions: Bool = true,
        isMuted: Binding<Bool> = .constant(false),
        playbackRate: Binding<Float>? = nil,
        allowsFullscreen: Bool = true,
        isLandscapeFullscreen: Bool = false,
        protectAsContinuousHubs: Bool = false,
        externalFullscreenToken: Int = 0,
        onFullscreenToggle: (() -> Void)? = nil,
        onReady: (() -> Void)? = nil,
        onPlayingChange: ((Bool) -> Void)? = nil,
        onProgress: ((Double, Double) -> Void)? = nil,
        onVideoSize: ((CGSize) -> Void)? = nil
    ) {
        self.url = url
        self.posterURL = posterURL
        self.isActive = isActive
        self.startTime = startTime
        self.postID = postID
        self.showsControls = showsControls
        self.loops = loops
        self.fillsFrame = fillsFrame
        self.topChromeReserve = topChromeReserve
        self.bottomChromeReserve = bottomChromeReserve
        self.tapToRevealControls = tapToRevealControls
        self.allowsCaptions = allowsCaptions
        self._isMuted = isMuted
        self.playbackRate = playbackRate
        self.allowsFullscreen = allowsFullscreen
        self.isLandscapeFullscreen = isLandscapeFullscreen
        self.protectAsContinuousHubs = protectAsContinuousHubs
        self.externalFullscreenToken = externalFullscreenToken
        self.onFullscreenToggle = onFullscreenToggle
        self.onReady = onReady
        self.onPlayingChange = onPlayingChange
        self.onProgress = onProgress
        self.onVideoSize = onVideoSize
        // Feed hubs: start fully chrome-hidden (CC/mute/FS/scrubber) until tap.
        _showChrome = State(initialValue: showsControls && !tapToRevealControls)
        _localPlaybackRate = State(initialValue: playbackRate?.wrappedValue ?? 1.0)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if topChromeReserve > 0 {
                    Color.black
                        .frame(height: topChromeReserve)
                        .allowsHitTesting(false)
                }

                ArchiveVideoPlayerView(
                    url: url,
                    posterURL: posterURL,
                    // Continuous / toggle FS keeps the same player active. Legacy cover remount pauses.
                    isActive: isActive && (onFullscreenToggle != nil || !showFullscreen),
                    muted: isMuted,
                    startTime: startTime,
                    loops: loops,
                    fillsFrame: fillsFrame,
                    postID: postID,
                    bridge: bridge,
                    onReady: {
                        bridge.publishReady(playing: true)
                        bridge.setPlaybackRate(activePlaybackRate)
                        DispatchQueue.main.async {
                            onReady?()
                            // Feed hubs: stay chrome-hidden until the user taps.
                            if showsControls, !tapToRevealControls {
                                showChrome = true
                                scheduleChromeHide()
                            }
                        }
                    },
                    onProgress: { current, duration in
                        guard !isScrubbing else { return }
                        // Play/pause edges arrive via onPlayingChanged — don't republish playing here.
                        bridge.applyProgress(current: current, duration: duration, playing: nil)
                        onProgress?(current, duration)
                        if let postID, current >= 0.5 {
                            YouTubeCatalogService.shared.notePlaybackPosition(
                                current,
                                for: postID,
                                duration: duration > 0 ? duration : nil
                            )
                        }
                    },
                    onVideoSize: onVideoSize,
                    protectAsContinuousHubs: protectAsContinuousHubs
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if bottomChromeReserve > 0 {
                    Color.black
                        .frame(height: bottomChromeReserve)
                        .allowsHitTesting(false)
                }
            }

            // Captions stay on-film while CC is on (chrome can auto-hide).
            if captionsEnabled, let line = activeCaption, !line.isEmpty {
                MatteryaFilmCaption(
                    text: line,
                    maxWidthPadding: isLandscapeFullscreen ? 56 : 36,
                    bottomPadding: (showsControls && showChrome ? (isLandscapeFullscreen ? 72 : 58) : 28)
                        + bottomChromeReserve
                )
                .zIndex(40)
                .transition(.opacity)
            }

            if let captionsHint, !captionsHint.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    Text(captionsHint)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.ink.opacity(0.7), in: Capsule())
                        .padding(.bottom, 88)
                }
                .allowsHitTesting(false)
                .zIndex(45)
                .transition(.opacity)
            }

            if showsControls {
                // Feed (tapToReveal): chrome only while showChrome.
                // Matterya Hubs watch: chrome while showChrome or still buffering; after
                // auto-hide, a clear tap target must remain so tap-anywhere restores chrome.
                if showChrome || (!tapToRevealControls && !bridge.isReady) {
                    hubChrome
                        .padding(.top, topChromeReserve)
                        .padding(.bottom, bottomChromeReserve)
                        .transition(.opacity)
                        .zIndex(1)
                    if showChrome || !tapToRevealControls {
                        topTrailingChrome
                            .padding(.top, topChromeReserve)
                            .padding(.bottom, bottomChromeReserve)
                            .transition(.opacity)
                            .zIndex(50)
                    }
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { toggleChromeFromTap() }
                        .padding(.top, topChromeReserve)
                        .padding(.bottom, bottomChromeReserve)
                        .zIndex(1)
                }
            }
        }
        // Legacy remount cover only when no continuous toggle is wired (avoid double-player lag).
        .fullScreenCover(isPresented: $showFullscreen) {
            MatteryaLandscapeFullscreenPlayer(
                url: url,
                posterURL: posterURL,
                startTime: bridge.currentSeconds,
                initialMuted: isMuted,
                initialPlaybackRate: activePlaybackRate,
                postID: postID,
                isArchive: true,
                onDismiss: { muted, seconds, rate in
                    isMuted = muted
                    applyPlaybackRate(rate)
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
        .task(id: postID) {
            // New clip → CC off. Do NOT prefetch transcripts here — that stormed
            // MainActor/network on every Hubs card during tab hops (keep-mounted shells).
            // Transcripts load only when the user taps CC (`toggleCaptions`).
            resetCaptionsForNewVideo()
        }
        .onChange(of: bridge.currentSeconds) { _, seconds in
            captionClock.seconds = seconds
            captionClock.duration = bridge.durationSeconds
            refreshActiveCaption(at: seconds)
        }
        .onChange(of: captionsEnabled) { _, enabled in
            if enabled {
                refreshActiveCaption(at: bridge.currentSeconds)
            } else {
                activeCaption = nil
            }
        }
        .onChange(of: externalFullscreenToken) { oldToken, newToken in
            guard allowsFullscreen, newToken > 0, newToken != oldToken else { return }
            // Token already flipped AppState landscape flag — keep chrome visible briefly.
            chromeHideTask?.cancel()
            if onFullscreenToggle == nil, !protectAsContinuousHubs {
                showFullscreen = true
            } else if showChrome == false {
                showChrome = true
                scheduleChromeHide()
            }
        }
        .onChange(of: isActive) { _, active in
            // Always setActive so userWantsPlayback + audio output are restored after pause.
            bridge.controller?.setActive(active)
            if !active {
                bridge.publishPlaying(false)
            } else if protectAsContinuousHubs {
                // Continuous hubs: setActive already no-ops when rolling — don't publish again.
                bridge.controller?.setMuted(isMuted)
            } else {
                // Expand/mini / mini play button: re-assert mute from chrome, then resume.
                bridge.controller?.setMuted(isMuted)
                bridge.controller?.ensureContinuingPlayback()
                bridge.publishPlaying(true)
            }
        }
        .onChange(of: showsControls) { _, visible in
            if visible, !tapToRevealControls {
                showChrome = true
                scheduleChromeHide()
            } else if !visible {
                // Mini player: hide chrome but keep the AVPlayer actively rendering.
                chromeHideTask?.cancel()
                showChrome = false
            }
            // Expand ↔ mini only toggles chrome — never pause, remount, or re-kick AV.
            // (ensureContinuingPlayback here was hitching every minimize.)
        }
        .onChange(of: fillsFrame) { _, _ in
            // Gravity flip must not leave the continuous hubs clip paused.
            guard isActive, protectAsContinuousHubs else { return }
            bridge.controller?.setActive(true)
            bridge.controller?.ensureContinuingPlayback()
            bridge.publishPlaying(true)
        }
        .onChange(of: isMuted) { _, muted in
            bridge.controller?.setMuted(muted)
            bridge.publishMuted(muted)
        }
        .onChange(of: activePlaybackRate) { _, rate in
            bridge.setPlaybackRate(rate)
        }
        .onChange(of: bridge.isPlaying) { _, playing in
            // Never push "paused" while scrubbing — that cleared hubPlaybackPlaying and
            // left the clip frozen after the timeline seek.
            guard !isScrubbing else { return }
            // Chrome play/pause must update hubPlaybackPlaying so mini bar + isActive stay aligned.
            onPlayingChange?(playing)
        }
        .onAppear {
            bridge.setPlaybackRate(activePlaybackRate)
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

    /// YouTube-smooth: prefer continuous same-player toggle; remount cover only as fallback.
    private func enterOrToggleFullscreen() {
        chromeHideTask?.cancel()
        if let onFullscreenToggle {
            onFullscreenToggle()
            return
        }
        if protectAsContinuousHubs {
            // Continuous hubs without a toggle wired — still avoid remount; no-op chrome.
            showChrome = true
            scheduleChromeHide()
            return
        }
        showFullscreen = true
    }

    /// Top-trailing Hubs chrome: speed · CC · mute · fullscreen (same cluster on feed + Hubs watch).
    private var topTrailingChrome: some View {
        VStack {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                playbackSpeedMenuButton
                if allowsCaptions, TranscriptService.isTranscriptablePostID(postID) {
                    captionsToggleButton
                }
                chromeIconButton(
                    systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                ) {
                    isMuted.toggle()
                    bridge.controller?.setMuted(isMuted)
                    bridge.publishMuted(isMuted)
                    scheduleChromeHide()
                }
                if allowsFullscreen {
                    chromeIconButton(
                        systemName: isLandscapeFullscreen
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                    ) {
                        enterOrToggleFullscreen()
                    }
                }
            }
            .padding(.horizontal, isLandscapeFullscreen ? 28 : 14)
            .padding(.top, isLandscapeFullscreen ? 10 : 12)
            .safeAreaPadding(.top, isLandscapeFullscreen ? 14 : 0)
            .safeAreaPadding(.trailing, isLandscapeFullscreen ? 10 : 0)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(true)
    }

    /// Center transport (like the provided Hubs chrome): −10s · play/pause · +10s, scrubber bottom.
    private var hubChrome: some View {
        ZStack {
            // Tap empty film: dismiss chrome early (before 3s) when tap-to-reveal.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleChromeFromTap() }

            // TRUE center: skip back · large play · skip forward
            HStack(spacing: 40) {
                chromeIconButton(systemName: "gobackward.10", size: 46) {
                    bridge.skip(by: -10)
                    scheduleChromeHide()
                }
                .accessibilityLabel("Back 10 seconds")

                Button {
                    bridge.togglePlayPause()
                    scheduleChromeHide()
                } label: {
                    Image(systemName: bridge.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.paper)
                        .frame(width: 68, height: 68)
                        .background(Theme.accentBright, in: Circle())
                        .shadow(color: Theme.ink.opacity(0.34), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bridge.isPlaying ? "Pause" : "Play")

                chromeIconButton(systemName: "goforward.10", size: 46) {
                    bridge.skip(by: 10)
                    scheduleChromeHide()
                }
                .accessibilityLabel("Forward 10 seconds")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .zIndex(2)

            // Timeline only — pinned to bottom of the stage.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Text(formatTime(bridge.currentSeconds))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(Theme.paper.opacity(0.92))
                        .frame(width: hubTimeLabelWidth, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HubTimelineScrubber(
                        value: scrubberValue,
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if editing {
                                chromeHideTask?.cancel()
                                bridge.beginScrub()
                            } else if bridge.durationSeconds > 0 {
                                // Land on scrub time and keep playing (never pause at seek).
                                let target = bridge.currentSeconds
                                bridge.endScrub(at: target)
                                onPlayingChange?(true)
                                scheduleChromeHide()
                            }
                        },
                        onValueChanged: { fraction in
                            bridge.applyScrubFraction(fraction)
                        }
                    )

                    Text(formatTime(bridge.durationSeconds))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(Theme.paper.opacity(0.75))
                        .frame(width: hubTimeLabelWidth, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, isLandscapeFullscreen ? 28 : 16)
                // On-film timeline (no black margin strip under the picture).
                .padding(.bottom, isLandscapeFullscreen ? 14 : 10)
                .padding(.top, 12)
                .safeAreaPadding(.bottom, isLandscapeFullscreen ? 10 : 0)
                .safeAreaPadding(.leading, isLandscapeFullscreen ? 10 : 0)
                .safeAreaPadding(.trailing, isLandscapeFullscreen ? 10 : 0)
                .background(
                    LinearGradient(
                        colors: [.clear, Theme.ink.opacity(0.55), Theme.ink.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    /// Long Hubs clips use h:mm:ss — 42pt cropped both ends in landscape.
    private var hubTimeLabelWidth: CGFloat {
        let sample = max(bridge.currentSeconds, bridge.durationSeconds)
        if sample >= 3600 { return isLandscapeFullscreen ? 68 : 62 }
        return isLandscapeFullscreen ? 52 : 48
    }

    private var scrubberValue: Double {
        guard bridge.durationSeconds > 0 else { return 0 }
        return min(1, max(0, bridge.currentSeconds / bridge.durationSeconds))
    }

    private func chromeIconButton(
        systemName: String,
        size: CGFloat = 36,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size > 36 ? 18 : 14, weight: .semibold))
                .foregroundStyle(Theme.paper)
                .frame(width: size, height: size)
                .background(Theme.ink.opacity(0.48), in: Circle())
                .overlay(Circle().stroke(Theme.paper.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var playbackSpeedMenuButton: some View {
        Menu {
            ForEach(Self.speedOptions, id: \.self) { rate in
                Button {
                    applyPlaybackRate(rate)
                } label: {
                    if abs(activePlaybackRate - rate) < 0.01 {
                        Label(Self.speedLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(Self.speedLabel(rate))
                    }
                }
            }
        } label: {
            Text(Self.speedLabel(activePlaybackRate))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(Theme.ink.opacity(0.48), in: Capsule())
                .overlay(Capsule().stroke(Theme.paper.opacity(0.12), lineWidth: 0.5))
        }
        .accessibilityLabel("Playback speed")
    }

    private var captionsToggleButton: some View {
        Button {
            Task { await toggleCaptions() }
        } label: {
            Text("CC")
                .font(.caption.weight(.bold))
                .foregroundStyle(captionsEnabled ? Theme.ink : Theme.paper)
                .frame(width: 36, height: 36)
                .background(
                    captionsEnabled ? Theme.matte : Theme.ink.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.paper.opacity(captionsEnabled ? 0 : 0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(captionsEnabled ? "Captions on" : "Captions off")
        .accessibilityAddTraits(.isButton)
    }

    @MainActor
    private func toggleCaptions() async {
        scheduleChromeHide()
        let next = !captionsEnabled
        guard next else {
            liveCaptionHandle?.cancel()
            liveCaptionHandle = nil
            captionsEnabled = false
            activeCaption = nil
            captionsHint = nil
            return
        }
        guard let postID, TranscriptService.isTranscriptablePostID(postID) else {
            setCaptionsHint("Captions unavailable")
            return
        }
        captionsEnabled = true
        captionsHint = nil

        // Cached full transcript → captions on instantly.
        if let cached = TranscriptService.cached(postID), cached.isReady,
           !TranscriptService.looksTruncated(cached, videoDuration: bridge.durationSeconds) {
            transcript = cached
            refreshActiveCaption(at: bridge.currentSeconds)
            return
        }

        // Live: caption just ahead of playhead — first lines in a few seconds.
        liveCaptionHandle?.cancel()
        captionClock.seconds = bridge.currentSeconds
        captionClock.duration = bridge.durationSeconds
        let mediaURL = url
        let clock = captionClock
        liveCaptionHandle = LiveCaptionEngine.start(
            postID: postID,
            mediaURL: mediaURL,
            playhead: { clock.seconds },
            duration: { clock.duration }
        ) { updated in
            transcript = updated
            if updated.status == "failed" {
                captionsEnabled = false
                setCaptionsHint(captionsUnavailableHint(for: updated))
                liveCaptionHandle?.cancel()
                liveCaptionHandle = nil
                return
            }
            refreshActiveCaption(at: bridge.currentSeconds)
        }
    }

    private func captionsUnavailableHint(for transcript: TranscriptService.Transcript?) -> String {
        let err = transcript?.error?.lowercased() ?? ""
        if err.contains("audio_missing") || err.contains("audio_export") || err.contains("export")
            || err.contains("operation stopped") || err.contains("cannot open")
            || err.contains("audio_download") {
            return "Couldn’t extract audio — tap CC to retry"
        }
        if err.contains("captions_model_missing") || err.contains("modelsunavailable") {
            return "Captions model missing — rebuild the app"
        }
        if err.contains("empty_transcript") {
            return "No speech detected"
        }
        // Surface a short real reason so retries aren’t a black box.
        if let raw = transcript?.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let short = raw.count > 72 ? String(raw.prefix(69)) + "…" : raw
            return "Captions unavailable — \(short)"
        }
        return "Captions unavailable"
    }

    @MainActor
    private func resetCaptionsForNewVideo() {
        liveCaptionHandle?.cancel()
        liveCaptionHandle = nil
        captionsEnabled = false
        activeCaption = nil
        captionsHint = nil
        transcript = nil
    }

    private func loadTranscriptIfNeeded(force: Bool = false) async {
        guard let postID, TranscriptService.isTranscriptablePostID(postID) else {
            transcript = nil
            activeCaption = nil
            return
        }
        if !force, let cached = TranscriptService.cached(postID) {
            transcript = cached
            if captionsEnabled { refreshActiveCaption(at: bridge.currentSeconds) }
            if cached.isReady { return }
        }
        if let fetched = await TranscriptService.fetch(postID: postID, force: force) {
            transcript = fetched
            if captionsEnabled { refreshActiveCaption(at: bridge.currentSeconds) }
        }
    }

    private func refreshActiveCaption(at seconds: Double) {
        guard captionsEnabled, let transcript else {
            activeCaption = nil
            return
        }
        let next = TranscriptService.textAt(time: seconds, in: transcript)
        if next != activeCaption {
            activeCaption = next
        }
    }

    private func setCaptionsHint(_ message: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            captionsHint = message
        }
    }

    private func flashCaptionsHint(_ message: String) {
        setCaptionsHint(message)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if captionsHint == message {
                withAnimation(.easeInOut(duration: 0.2)) {
                    captionsHint = nil
                }
            }
        }
    }

    private func applyPlaybackRate(_ rate: Float) {
        if let playbackRate {
            playbackRate.wrappedValue = rate
        } else {
            localPlaybackRate = rate
        }
        bridge.setPlaybackRate(rate)
        scheduleChromeHide()
    }

    /// Shared with landscape FS chrome in this file.
    fileprivate static func speedLabel(_ rate: Float) -> String {
        if abs(rate - rate.rounded()) < 0.01 {
            return "\(Int(rate.rounded()))x"
        }
        let text = String(format: "%g", rate)
        return "\(text)x"
    }

    private func toggleChromeFromTap() {
        guard showsControls else { return }
        let next = !showChrome
        withAnimation(.easeInOut(duration: 0.18)) {
            showChrome = next
        }
        if next {
            scheduleChromeHide()
        } else {
            chromeHideTask?.cancel()
            chromeHideTask = nil
        }
    }

    private func scheduleChromeHide() {
        chromeHideTask?.cancel()
        // Stay up while paused so center play / ±10s never vanish mid-pause.
        guard bridge.isPlaying else { return }
        // Idle 3s auto-hide; earlier tap dismisses via toggleChromeFromTap.
        chromeHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, !isScrubbing else { return }
            await MainActor.run {
                guard bridge.isPlaying else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    showChrome = false
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        // Long Hubs videos: 1:01:00 not 61:00
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Landscape fullscreen (hub / archive)

/// Full-screen hub player. Forces landscape on enter; aspect-fit so film never crops.
struct MatteryaLandscapeFullscreenPlayer: View {
    let url: URL
    var posterURL: URL? = nil
    var startTime: Double = 0
    var initialMuted: Bool = false
    var initialPlaybackRate: Float = 1.0
    var postID: String? = nil
    /// Kept for API compatibility; Archive surface plays archive + other remote MP4s.
    var isArchive: Bool = true
    var onDismiss: (_ muted: Bool, _ seconds: Double, _ rate: Float) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var bridge = ArchivePlayerBridge()
    @State private var isMuted = false
    @State private var playbackRate: Float = 1.0
    @State private var showChrome = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var isScrubbing = false
    /// Fullscreen cover also starts CC off — never inherit from the previous clip.
    @State private var captionsEnabled = false
    @State private var transcript: TranscriptService.Transcript?
    @State private var activeCaption: String?
    @State private var liveCaptionHandle: LiveCaptionHandle?
    @State private var captionClock = CaptionPlayheadClock()

    private static let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ArchiveVideoPlayerView(
                url: url,
                posterURL: posterURL,
                isActive: true,
                muted: isMuted,
                startTime: startTime,
                loops: false,
                // Fullscreen = aspect-fit (letterbox/pillarbox OK). Never crop.
                fillsFrame: false,
                postID: postID,
                bridge: bridge,
                onReady: {
                    bridge.publishReady(playing: true)
                    bridge.setPlaybackRate(playbackRate)
                    scheduleChromeHide()
                },
                onProgress: { current, duration in
                    guard !isScrubbing else { return }
                    bridge.applyProgress(current: current, duration: duration, playing: nil)
                }
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showChrome.toggle()
                }
                if showChrome { scheduleChromeHide() }
            }

            if captionsEnabled, let line = activeCaption, !line.isEmpty {
                MatteryaFilmCaption(
                    text: line,
                    maxWidthPadding: 56,
                    bottomPadding: showChrome ? 78 : 32
                )
                .zIndex(40)
            }

            if showChrome {
                fullscreenChrome
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task(id: postID) {
            // Reset CC for the new clip. Cache-only — never network-fetch on appear
            // (prefetch froze tab hops when many Archive players stayed mounted).
            liveCaptionHandle?.cancel()
            liveCaptionHandle = nil
            captionsEnabled = false
            activeCaption = nil
            transcript = nil
            guard let postID, TranscriptService.isTranscriptablePostID(postID) else { return }
            if let cached = TranscriptService.cached(postID) {
                transcript = cached
            }
        }
        .onChange(of: bridge.currentSeconds) { _, seconds in
            captionClock.seconds = seconds
            captionClock.duration = bridge.durationSeconds
            refreshFSCaption(at: seconds)
        }
        .onChange(of: captionsEnabled) { _, enabled in
            if enabled {
                refreshFSCaption(at: bridge.currentSeconds)
            } else {
                activeCaption = nil
            }
        }
        .onAppear {
            isMuted = initialMuted
            playbackRate = initialPlaybackRate
            bridge.setPlaybackRate(initialPlaybackRate)
            AppOrientation.lock(.landscape, prefer: .landscapeRight)
            scheduleChromeHide()
        }
        .onDisappear {
            chromeHideTask?.cancel()
            AppOrientation.lock(.portrait, prefer: .portrait)
        }
        .onChange(of: isMuted) { _, muted in
            bridge.controller?.setMuted(muted)
            bridge.publishMuted(muted)
        }
    }

    private func refreshFSCaption(at seconds: Double) {
        guard captionsEnabled, let transcript else {
            activeCaption = nil
            return
        }
        let next = TranscriptService.textAt(time: seconds, in: transcript)
        if next != activeCaption { activeCaption = next }
    }

    @MainActor
    private func toggleFullscreenCaptions() async {
        scheduleChromeHide()
        let next = !captionsEnabled
        guard next else {
            liveCaptionHandle?.cancel()
            liveCaptionHandle = nil
            captionsEnabled = false
            activeCaption = nil
            return
        }
        captionsEnabled = true
        guard let postID, TranscriptService.isTranscriptablePostID(postID) else {
            captionsEnabled = false
            return
        }
        if let cached = TranscriptService.cached(postID), cached.isReady {
            transcript = cached
            refreshFSCaption(at: bridge.currentSeconds)
            return
        }
        liveCaptionHandle?.cancel()
        captionClock.seconds = bridge.currentSeconds
        captionClock.duration = bridge.durationSeconds
        let mediaURL = url
        let clock = captionClock
        liveCaptionHandle = LiveCaptionEngine.start(
            postID: postID,
            mediaURL: mediaURL,
            playhead: { clock.seconds },
            duration: { clock.duration }
        ) { updated in
            transcript = updated
            if updated.status == "failed" {
                captionsEnabled = false
                liveCaptionHandle?.cancel()
                liveCaptionHandle = nil
                return
            }
            refreshFSCaption(at: bridge.currentSeconds)
        }
    }

    private var fullscreenTimeLabelWidth: CGFloat {
        let sample = max(bridge.currentSeconds, bridge.durationSeconds)
        return sample >= 3600 ? 68 : 52
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

                    Menu {
                        ForEach(Self.speedOptions, id: \.self) { rate in
                            Button {
                                playbackRate = rate
                                bridge.setPlaybackRate(rate)
                                scheduleChromeHide()
                            } label: {
                                if abs(playbackRate - rate) < 0.01 {
                                    Label(MatteryaHubPlayerView.speedLabel(rate), systemImage: "checkmark")
                                } else {
                                    Text(MatteryaHubPlayerView.speedLabel(rate))
                                }
                            }
                        }
                    } label: {
                        Text(MatteryaHubPlayerView.speedLabel(playbackRate))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(Theme.ink.opacity(0.5), in: Capsule())
                    }

                    if TranscriptService.isTranscriptablePostID(postID) {
                        Button {
                            Task { await toggleFullscreenCaptions() }
                        } label: {
                            Text("CC")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(captionsEnabled ? Theme.ink : .white)
                                .frame(width: 36, height: 36)
                                .background(
                                    captionsEnabled ? Theme.matte : Theme.ink.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(captionsEnabled ? "Captions on" : "Captions off")
                    }

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
                .padding(.horizontal, 28)
                .safeAreaPadding(.top, 16)
                .safeAreaPadding(.leading, 12)
                .safeAreaPadding(.trailing, 12)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Text(formatTime(bridge.currentSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: fullscreenTimeLabelWidth, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HubTimelineScrubber(
                        value: scrubberValue,
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
                            bridge.applyScrubFraction(fraction)
                        }
                    )

                    Text(formatTime(bridge.durationSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: fullscreenTimeLabelWidth, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
                .padding(.top, 12)
                .safeAreaPadding(.bottom, 12)
                .safeAreaPadding(.leading, 12)
                .safeAreaPadding(.trailing, 12)
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
        AppOrientation.lock(.portrait, prefer: .portrait)
        onDismiss(isMuted, bridge.currentSeconds, playbackRate)
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
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        // Long Hubs videos: 1:01:00 not 61:00
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

/// Portrait-locked app; temporarily force landscape for hub fullscreen, then restore.
enum AppOrientation {
    static func lock(_ mask: UIInterfaceOrientationMask, prefer: UIInterfaceOrientation) {
        AppDelegate.orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        // Prefer the side the device is already tilted toward when entering landscape.
        let resolvedPrefer: UIInterfaceOrientation = {
            if mask.contains(.landscapeLeft) || mask.contains(.landscapeRight) {
                switch scene.effectiveGeometry.interfaceOrientation {
                case .landscapeLeft: return .landscapeLeft
                case .landscapeRight: return .landscapeRight
                default: return prefer
                }
            }
            return prefer
        }()
        let geometryMask: UIInterfaceOrientationMask
        switch resolvedPrefer {
        case .landscapeLeft: geometryMask = .landscapeLeft
        case .landscapeRight: geometryMask = .landscapeRight
        case .portraitUpsideDown: geometryMask = .portraitUpsideDown
        default: geometryMask = .portrait
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: geometryMask)) { _ in }
        // Cover present can race the first geometry update — nudge once more next tick.
        DispatchQueue.main.async {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: geometryMask)) { _ in }
        }
    }
}

private struct HubTimelineScrubber: View {
    let value: Double
    let onEditingChanged: (Bool) -> Void
    let onValueChanged: (Double) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fill = (isDragging ? dragValue : value) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.paper.opacity(0.22))
                    .frame(height: 4)

                Capsule()
                    .fill(Theme.accentBright)
                    .frame(width: max(fill, 0), height: 4)

                Circle()
                    .fill(Theme.paper)
                    .frame(width: 15, height: 15)
                    .shadow(color: Theme.ink.opacity(0.3), radius: 3, y: 1)
                    .offset(x: max(0, fill - 7.5))
            }
            .frame(height: 22)
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
    /// When true, fill the stage (crop). Fullscreen + expanded hubs watch use false (fit).
    var fillsFrame: Bool = true
    /// Optional content id for continuity / engagement (not required for playback).
    var postID: String? = nil
    /// When false (Sparks pager), UIView does not eat pans — ScrollView can page immediately.
    var interactive: Bool = true
    var bridge: ArchivePlayerBridge? = nil
    var onReady: (() -> Void)? = nil
    var onFailed: ((String) -> Void)? = nil
    var onProgress: ((Double, Double) -> Void)? = nil
    /// Natural video size once known (Sparks fill vs fit).
    var onVideoSize: ((CGSize) -> Void)? = nil
    /// When set, seek once then clear via `onSeekConsumed`.
    var seekToSeconds: Double? = nil
    var onSeekConsumed: (() -> Void)? = nil
    /// Sparks player: bump on page focus so clip always starts at t=0.
    var restartFromBeginningToken: UInt = 0
    /// User pause while page is still focused — freeze frame, don't deactivate / seek to 0.
    var isPausedByUser: Bool = false
    /// Hubs continuous mini/watch — keep AVPlayer across Sparks open/close.
    var protectAsContinuousHubs: Bool = false

    final class Coordinator {
        var lastURL: URL?
        var lastActive: Bool?
        var lastMuted: Bool?
        var lastSeekToken: Double?
        var lastRestartToken: UInt = 0
        var lastUserPaused: Bool = false
        var lastGravity: AVLayerVideoGravity?
        /// Last startTime applied to the controller (Continue watching resume).
        var lastStartTime: Double = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var videoGravity: AVLayerVideoGravity {
        fillsFrame ? .resizeAspectFill : .resizeAspect
    }

    func makeUIViewController(context: Context) -> ArchiveVideoPlayerController {
        let vc = ArchiveVideoPlayerController()
        vc.loops = loops
        vc.postID = postID
        vc.protectAsContinuousHubs = protectAsContinuousHubs
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
        context.coordinator.lastStartTime = startTime
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
        // Only touch AV when something actually changed — tab leave used to hit
        // applyVideoGravity + setMuted on every SwiftUI redraw (main leave hitch).
        let urlChanged = context.coordinator.lastURL != url
        let activeChanged = context.coordinator.lastActive != isActive
        let mutedChanged = context.coordinator.lastMuted != muted
        let restartChanged = context.coordinator.lastRestartToken != restartFromBeginningToken
        let pauseChanged = context.coordinator.lastUserPaused != isPausedByUser
        let gravityChanged = context.coordinator.lastGravity != videoGravity
        let startChanged = abs(context.coordinator.lastStartTime - startTime) >= 1.0

        vc.loops = loops
        vc.postID = postID
        vc.protectAsContinuousHubs = protectAsContinuousHubs
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

        if gravityChanged {
            context.coordinator.lastGravity = videoGravity
            vc.applyVideoGravity(videoGravity)
        }

        if urlChanged {
            context.coordinator.lastURL = url
            context.coordinator.lastActive = isActive
            context.coordinator.lastMuted = muted
            context.coordinator.lastRestartToken = restartFromBeginningToken
            context.coordinator.lastUserPaused = isPausedByUser
            context.coordinator.lastStartTime = startTime
            if !gravityChanged {
                vc.applyVideoGravity(videoGravity)
                context.coordinator.lastGravity = videoGravity
            }
            let initialStart = restartFromBeginningToken > 0 ? 0 : startTime
            vc.configure(url: url, posterURL: posterURL, muted: muted, startTime: initialStart, active: isActive && !isPausedByUser)
            if isActive, isPausedByUser {
                vc.pauseKeepingFrame()
            }
            return
        }

        // Continue watching: startTime can arrive/update after first mount with same URL.
        if startChanged, restartFromBeginningToken == 0, startTime >= 0.5, isActive, !isPausedByUser {
            context.coordinator.lastStartTime = startTime
            let head = vc.currentSeconds
            if !(head.isFinite && abs(head - startTime) < 1.5),
               !(head.isFinite && head > 0.45 && head + 1.5 >= startTime) {
                vc.seek(to: startTime, resumeIfWanted: true)
            }
        }

        // Only react to real state changes — do not re-kick play on every SwiftUI redraw.
        if mutedChanged {
            context.coordinator.lastMuted = muted
            vc.setMuted(muted)
        }
        if pauseChanged {
            context.coordinator.lastUserPaused = isPausedByUser
            if isPausedByUser {
                vc.pauseKeepingFrame()
            } else if isActive {
                vc.setMuted(muted)
                vc.setActive(true)
            }
        }
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
                    vc.ensureContinuingPlayback()
                } else {
                    vc.setActive(true)
                }
            } else {
                vc.setActive(false)
            }
        }
        // Intentionally no `else if isActive { setMuted }` — that ran every redraw.

        if seekToSeconds == nil {
            context.coordinator.lastSeekToken = nil
        } else if let target = seekToSeconds, context.coordinator.lastSeekToken != target {
            context.coordinator.lastSeekToken = target
            vc.seek(to: target)
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
    /// Retains GET-only R2 resource loader for the active AVURLAsset.
    private var r2ResourceLoader: R2PresignedResourceLoader?

    private let posterView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()

    var onReady: (() -> Void)?
    var onFailed: ((String) -> Void)?
    var onProgress: ((Double, Double) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    var onVideoSize: ((CGSize) -> Void)?
    /// Sparks loop by default so clips don't freeze on the last frame.
    var loops = true
    /// Used to claim a pre-buffered player from SparkWarmPool.
    var postID: String?
    /// Global Hubs mini/watch — survive Sparks open/close without remount (no black flash).
    var protectAsContinuousHubs = false

    /// User intent — survives SwiftUI re-renders during pull-down drag.
    private var userWantsPlayback = true
    /// Hubs / archive playback speed (YouTube-style). Applied on every resume.
    private var preferredRate: Float = 1.0
    /// True while scrubbing timeline (paused for seek, but intent may still be play).
    private var isScrubbing = false
    /// Remember play intent across a scrub (pause-for-seek must not clear it).
    private var resumeAfterScrub = true
    /// Last known playhead — used when remounting so mini↔full never restarts at 0.
    private var lastKnownSeconds: Double = 0
    /// Continue watching: seek target applied once the item reaches `.readyToPlay`.
    /// Seeking before ready often returns `finished=false` and leaves the clip at 0.
    private var pendingResumeSeconds: Double = 0
    /// Last play/pause edge sent to SwiftUI — avoid republishing every time tick.
    private var lastPublishedPlaying: Bool?
    /// Chrome / user mute — separate from forced silence when the Spark page is inactive.
    private var mutedFlag = false
    /// Epoch captured when this surface last became active (invalidated on page change).
    private var activePageEpoch: UInt64 = 0
    private var interruptResumeObserver: NSObjectProtocol?
    private var exportHandoffObserver: NSObjectProtocol?

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

    /// Letterbox / empty AV floor — black (IG/YT), never paper-white.
    private static let softFloor = UIColor.black

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.softFloor
        view.clipsToBounds = true

        // Feed → Sparks/Hubs: park live buffer mid-playhead (same as VideoPlayerView).
        exportHandoffObserver = NotificationCenter.default.addObserver(
            forName: .matteryaExportPlaybackForHandoff,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.exportForHandoff(note)
            }
        }

        // Match video gravity (updated in applyVideoGravity) — avoid poster/video framing jump.
        // Default fill so Sparks never flash fit→fill on first layout.
        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.backgroundColor = Self.softFloor
        posterView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(posterView)

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
    }

    deinit {
        if let interruptResumeObserver {
            NotificationCenter.default.removeObserver(interruptResumeObserver)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Only size when host has real bounds — never animate gravity/frame (Sparks zoom jump).
        guard view.bounds.width > 2, view.bounds.height > 2 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = view.bounds
        playerLayer?.videoGravity = preferredVideoGravity
        CATransaction.commit()
    }

    /// Default aspect-fit — Sparks pass fit; Hubs pass fill. Never flip after first frame.
    private var preferredVideoGravity: AVLayerVideoGravity = .resizeAspect

    func applyVideoGravity(_ gravity: AVLayerVideoGravity) {
        preferredVideoGravity = gravity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.videoGravity = gravity
        // Only size when host has real bounds (zero-size install was the zoom pop).
        if view.bounds.width > 2, view.bounds.height > 2 {
            playerLayer?.frame = view.bounds
        }
        CATransaction.commit()
        posterView.contentMode = gravity == .resizeAspectFill ? .scaleAspectFill : .scaleAspectFit
        posterView.backgroundColor = Self.softFloor
    }

    func configure(url: URL, posterURL: URL?, muted: Bool, startTime: Double, active: Bool) {
        // Same source already loading/playing — don't tear down and restart (Sparks restart bug).
        if sourceURL == url, player != nil || loadTask != nil {
            setMuted(muted)
            if active {
                userWantsPlayback = true
                // Continue watching: same URL remount must still seek to the saved playhead
                // when the live head is behind (warm-pool claim at ~0 used to skip this).
                let resume = restartsFromBeginningOnFocus ? 0 : startTime
                let head = currentSeconds
                if resume >= 0.5,
                   !(head.isFinite && abs(head - resume) < 1.5),
                   !(head.isFinite && head > 0.45 && head + 1.5 >= resume) {
                    seek(to: resume, resumeIfWanted: true)
                } else {
                    ensureContinuingPlayback()
                }
            } else {
                setActive(false)
            }
            return
        }

        sourceURL = url
        didRetry = false
        didKickPlayback = false
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

    /// When true (Sparks player), becoming focused always seeks to t=0.
    var restartsFromBeginningOnFocus = false

    private func noteContinuousProtection(_ avPlayer: AVPlayer) {
        guard protectAsContinuousHubs else { return }
        MediaPlaybackCoordinator.shared.protectContinuous(avPlayer)
    }

    /// Masquerade watch only (`postID` nil) — never Hubs feed embeds (those froze tab hops
    /// when silence storms spared them and called `play()`).
    private var shouldProtectForegroundWatch: Bool {
        !protectAsContinuousHubs
            && !restartsFromBeginningOnFocus
            && (postID == nil || postID?.isEmpty == true)
    }

    private func noteForegroundWatchProtection(_ avPlayer: AVPlayer) {
        guard shouldProtectForegroundWatch, userWantsPlayback else { return }
        MediaPlaybackCoordinator.shared.protectForegroundWatch(avPlayer)
    }

    private func clearForegroundWatchProtectionIfNeeded(_ avPlayer: AVPlayer?) {
        guard shouldProtectForegroundWatch else { return }
        MediaPlaybackCoordinator.shared.clearForegroundWatchProtection(for: avPlayer)
    }

    func setActive(_ active: Bool) {
        if active {
            let wasWanting = userWantsPlayback
            userWantsPlayback = true
            activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
            if let player {
                noteForegroundWatchProtection(player)
            }
            // Continuous hubs already rolling — never re-kick play/safePlay (tab/minimize lag).
            if protectAsContinuousHubs,
               let player,
               player.currentItem != nil,
               player.rate >= 0.05,
               MediaPlaybackCoordinator.shared.isSolo(player) {
                applyUserAudioOutput(on: player)
                if !wasWanting {
                    DispatchQueue.main.async { [weak self] in
                        self?.onPlayingChanged?(true)
                    }
                }
                return
            }
            // Do NOT restart-from-0 here. Sparks focus restarts only via
            // `restartFromBeginningAndPlay()` (token). Calling both caused
            // play → re-layout → play (video “jumps to center” and restarts).
            if let player {
                applyUserAudioOutput(on: player)
                if player.currentItem != nil {
                    player.play()
                    player.safePlayImmediately(atRate: preferredRate)
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
            userWantsPlayback = false
            isScrubbing = false
            clearForegroundWatchProtectionIfNeeded(player)
            // Silence inactive pages — prevents stacked audio. mutedFlag stays as user choice.
            // Continuous hubs still pauses here when Sparks/overlay sets hubPlaybackPlaying=false.
            player?.pause()
            player?.isMuted = true
            player?.volume = 0
            // Keep last frame painted (no poster) so a fast swipe-back never blacks out.
            posterView.isHidden = true
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

    /// Soft start seek — skip if already near 0; never swap to poster (that was the swipe black flash).
    private func softSeekToBeginning(playAfter: Bool) {
        lastKnownSeconds = 0
        guard let player, player.currentItem != nil else { return }
        let t = player.currentTime().seconds
        // Wide near-zero: skip seek (seek = swipe flicker).
        if t.isFinite, t >= 0, t < 1.0 {
            // Keep decoded first frame visible — no poster swap.
            posterView.isHidden = true
            spinner.stopAnimating()
            if playAfter, userWantsPlayback {
                applyUserAudioOutput(on: player)
                _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                    keeping: player,
                    pageEpoch: activePageEpoch
                )
                player.play()
                player.safePlayImmediately(atRate: preferredRate)
                onPlayingChanged?(true)
            }
            return
        }
        // Mid-clip → 0: keep the live layer (last frame) while keyframe-seeking.
        // Showing poster here felt like a full refresh on scroll.
        posterView.isHidden = true
        player.seek(
            to: .zero,
            toleranceBefore: .positiveInfinity,
            toleranceAfter: .positiveInfinity
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
                player.safePlayImmediately(atRate: self.preferredRate)
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
            // Instant path: item ready + near 0 → solo + play on this runloop (no async hop).
            let t = player.currentTime().seconds
            let nearZero = t.isFinite && t >= 0 && t < 1.0
            let ready = player.currentItem?.status == .readyToPlay
                || player.status == .readyToPlay
            // Even if not "ready", kick play first — seek only when clearly mid-clip.
            if nearZero {
                posterView.isHidden = true
                spinner.stopAnimating()
                applyUserAudioOutput(on: player)
                _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                    keeping: player,
                    pageEpoch: activePageEpoch
                )
                applyUserAudioOutput(on: player)
                player.play()
                player.safePlayImmediately(atRate: preferredRate)
                onPlayingChanged?(true)
                return
            }
            if ready {
                applyUserAudioOutput(on: player)
                softSeekToBeginning(playAfter: true)
                return
            }
            // Not ready and mid-clip: play now, soft-seek without blanking.
            applyUserAudioOutput(on: player)
            player.play()
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
        // Intentional Masquerade/archive watch: re-claim solo instead of staying hard-muted
        // after a Feed silence storm bumped the page epoch.
        if !MediaPlaybackCoordinator.shared.isSolo(player) {
            if protectAsContinuousHubs {
                return
            }
            if shouldProtectForegroundWatch {
                noteForegroundWatchProtection(player)
                activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
                applyUserAudioOutput(on: player)
                if player.rate < 0.05 {
                    player.play()
                    player.safePlayImmediately(atRate: preferredRate)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onPlayingChanged?(true)
                }
                return
            }
            player.pause()
            player.isMuted = true
            player.volume = 0
            return
        }
        // Already flying — do not re-apply audio / publish playing (minimize/tab feather path).
        if player.rate >= 0.05, abs(player.rate - preferredRate) <= 0.05 {
            // Still re-assert mute preference — silence storms can leave isMuted=true
            // while rate keeps rolling (picture with no sound).
            if player.isMuted != mutedFlag || (!mutedFlag && player.volume < 0.5) {
                applyUserAudioOutput(on: player)
            }
            return
        }
        applyUserAudioOutput(on: player)
        if player.rate < 0.05 {
            player.play()
            player.safePlayImmediately(atRate: preferredRate)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPlayingChanged?(true)
        }
    }

    func setMuted(_ muted: Bool) {
        mutedFlag = muted
        // Apply when this surface is allowed to make sound (active playback intent).
        if userWantsPlayback, let player {
            if shouldProtectForegroundWatch {
                noteForegroundWatchProtection(player)
                activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
            }
            applyUserAudioOutput(on: player)
        }
    }

    /// YouTube-style speed. Keeps playing at the new rate when already active.
    func setPlaybackRate(_ rate: Float) {
        let clamped = max(0.25, min(rate, 3.0))
        preferredRate = clamped
        guard let player, !isScrubbing else { return }
        // Always remember preferredRate even while paused; apply live when audible.
        guard userWantsPlayback else { return }
        guard MediaPlaybackCoordinator.shared.isSolo(player)
            || player.rate > 0.01
            || player.timeControlStatus == .playing
            || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        else { return }
        applyUserAudioOutput(on: player)
        player.rate = clamped
        player.safePlayImmediately(atRate: clamped)
    }

    var currentPlaybackRate: Float { preferredRate }

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
        if shouldProtectForegroundWatch {
            // Masquerade intentional watch: always re-protect + skip page-epoch rejection.
            // Prior path refreshed epoch but skipped protect → continuous hubs hard-muted us
            // and we returned without ever applying mutedFlag (picture, no sound).
            noteForegroundWatchProtection(player)
            activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
            _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                keeping: player,
                pageEpoch: nil,
                aggressive: true
            )
            configureAudioSession()
            player.isMuted = mutedFlag
            player.volume = mutedFlag ? 0 : 1
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
            player.safePlayImmediately(atRate: preferredRate)
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
                player.safePlayImmediately(atRate: self.preferredRate)
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
                player.safePlayImmediately(atRate: self.preferredRate)
                self.onPlayingChanged?(true)
            }
        }
    }

    private func exportForHandoff(_ note: Notification) {
        guard let ids = note.userInfo?["postIDs"] as? [String],
              let postID,
              ids.contains(postID),
              let player,
              player.currentItem != nil,
              player.status != .failed
        else { return }
        let sec = currentSeconds
        if sec >= 0.05 {
            var dur: Double?
            if let item = player.currentItem {
                let d = CMTimeGetSeconds(item.duration)
                if d.isFinite, d > 0 { dur = d }
            }
            YouTubeCatalogService.shared.notePlaybackPosition(sec, for: postID, duration: dur)
            for id in ids where id != postID {
                YouTubeCatalogService.shared.notePlaybackPosition(sec, for: id, duration: dur)
            }
        }
        // Only mid-clip parks are "continuing". Parking a t≈0 preview as continuing made
        // Continue watching claim it and skip the seek to the saved playhead.
        if sec > 0.45 {
            SparkWarmPool.shared.parkContinuing(postID: postID, player: player)
        } else {
            SparkWarmPool.shared.park(postID: postID, player: player)
        }
        // Detach without destroying the item (pool owns it now).
        removeObservers()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        self.player = nil
        onPlayingChanged?(false)
    }

    func teardown() {
        loadTask?.cancel()
        loadTask = nil
        if let exportHandoffObserver {
            NotificationCenter.default.removeObserver(exportHandoffObserver)
            self.exportHandoffObserver = nil
        }
        removeObservers()
        if let player {
            // Persist playhead before any park-to-0 so Continue watching keeps the second.
            let sec = currentSeconds
            if let postID, sec >= 0.5 {
                var dur: Double?
                if let item = player.currentItem {
                    let d = CMTimeGetSeconds(item.duration)
                    if d.isFinite, d > 0 { dur = d }
                }
                YouTubeCatalogService.shared.notePlaybackPosition(sec, for: postID, duration: dur)
                YouTubeCatalogService.shared.savePlaybackPosition(sec, for: postID, duration: dur)
            }
            player.pause()
            player.isMuted = true
            player.volume = 0
            if let postID, player.currentItem != nil, player.status != .failed {
                // Hubs continuous / mid-clip: park without rewind. Sparks scroll-away parks at 0.
                let midClip = sec > 0.45 || protectAsContinuousHubs
                if midClip
                    || SparkWarmPool.shared.shouldContinueFromCurrentTime(postID: postID)
                    || SparkWarmPool.shared.isParked(postID: postID, player: player) {
                    SparkWarmPool.shared.parkContinuing(postID: postID, player: player)
                } else {
                    SparkWarmPool.shared.park(postID: postID, player: player)
                }
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
        pendingResumeSeconds = 0
        // Don't deactivate the whole audio session here — other feed cards may still be live.
    }

    private func startPlayback(url: URL, muted: Bool, startTime: Double, autoplay: Bool = true) {
        loadTask?.cancel()
        errorLabel.isHidden = true
        userWantsPlayback = autoplay
        activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
        pendingResumeSeconds = (!restartsFromBeginningOnFocus && startTime >= 0.5) ? startTime : 0
        if pendingResumeSeconds >= 0.5 {
            lastKnownSeconds = pendingResumeSeconds
        }

        // Instagram-speed: claim a pre-buffered player before any CDN resolve.
        // Install + play synchronously so the first painted frame is video, not black/poster.
        let claimed = postID.flatMap { SparkWarmPool.shared.claim(postID: $0) }
            ?? SparkWarmPool.shared.claimFirstContinuing()
        if let claimed {
            installClaimedPlayerSync(claimed, original: url, muted: muted, startTime: startTime, autoplay: autoplay)
            return
        }
        if let postID {
            SparkWarmPool.shared.markInUse(postID: postID)
        }

        // Never spin on Sparks swipe — poster stays until first frame.
        spinner.stopAnimating()
        loadTask = Task { [weak self] in
            guard let self else { return }
            // Hubs R2 long-form: resolve via /v1/playback (fresh signed). Raw shelf URLs are
            // often pub-*.r2.dev (CF 1010) or expired embeds — that yields AVPlayer permission errors.
            var playURL: URL
            if MediaURLResolver.looksLikeR2HostedURL(url), let postID = self.postID, !postID.isEmpty {
                let config = await MediaURLResolver.playbackConfiguration(for: url, postID: postID)
                playURL = config.url
                // Never hand banned pub-*.r2.dev to AVPlayer — force another live resolve.
                if MediaURLResolver.isBlockedR2PublicURL(playURL) {
                    await R2PlaybackResolver.shared.invalidate(postID: postID)
                    if let live = await R2PlaybackResolver.shared.playURL(postID: postID, fallback: nil),
                       !MediaURLResolver.isBlockedR2PublicURL(live) {
                        playURL = live
                    }
                }
            } else if ArchiveVideoPlayback.isArchiveURL(url) {
                playURL = await ArchiveVideoPlayback.resolvedPlaybackURL(for: url)
            } else {
                playURL = url
            }
            guard !Task.isCancelled else { return }
            if MediaURLResolver.isBlockedR2PublicURL(playURL) {
                await self.handleFailure(
                    message: "You do not have permission to access the requested resource.",
                    original: url,
                    attempted: playURL,
                    muted: muted,
                    startTime: startTime
                )
                return
            }
            await self.installPlayer(url: playURL, original: url, muted: muted, startTime: startTime)
            if !autoplay {
                self.userWantsPlayback = false
                self.player?.pause()
                self.player?.isMuted = true
                self.player?.volume = 0
                // Park head at 0 for instant next focus.
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
        r2ResourceLoader = nil

        claimed.automaticallyWaitsToMinimizeStalling = false
        claimed.actionAtItemEnd = loops ? .none : .pause
        mutedFlag = muted
        // Keep GET-only R2 proxy alive after warm-pool Slot is removed.
        r2ResourceLoader = SparkWarmPool.shared.takePendingResourceLoader(for: claimed)

        let layer = AVPlayerLayer(player: claimed)
        // Gravity + frame match the host view only — NEVER UIScreen.main.bounds
        // (that painted full-screen zoomed video, then snapped to the page = creep).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.videoGravity = preferredVideoGravity
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, above: posterView.layer)
        CATransaction.commit()
        playerLayer = layer
        player = claimed
        resolvedPlayURL = original
        MediaPlaybackCoordinator.shared.register(claimed)
        noteContinuousProtection(claimed)
        if autoplay {
            noteForegroundWatchProtection(claimed)
            configureAudioSession()
        }
        spinner.stopAnimating()
        errorLabel.isHidden = true
        // Do not layoutIfNeeded with zero bounds — wait for viewDidLayoutSubviews.

        let claimWasContinuing = SparkWarmPool.shared.takeLastClaimWasContinuing()
        let t = claimed.currentTime().seconds
        let midClipHead = t.isFinite && t > 0.45
        // Mid-clip handoff ONLY when the claimed head is actually mid-clip.
        // `claimWasContinuing` alone used to be enough — Continue watching often claimed a
        // near-zero "continuing" park (handoff export from a t≈0 preview) and skipped the
        // seek to the saved playhead, so the video always restarted at 0.
        let handoffFlag = claimWasContinuing
            || (postID.map { SparkWarmPool.shared.shouldContinueFromCurrentTime(postID: $0) } ?? false)
            || SparkWarmPool.shared.hasContinuingParked
        let continueMid = midClipHead && handoffFlag
        if handoffFlag, let postID {
            SparkWarmPool.shared.clearContinueFlag(postID: postID)
        }
        let forcedStart = restartsFromBeginningOnFocus ? 0 : startTime
        // Wide near-zero: warm park is rarely exact 0 — skip seek to kill swipe flash.
        let nearZero = t.isFinite && t >= 0 && t < 1.0
        // Saved playhead clearly ahead of live head → always seek (Continue watching).
        let savedAheadOfHead = forcedStart >= 0.5
            && !(t.isFinite && abs(t - forcedStart) < 1.0)
            && !(t.isFinite && t + 1.5 >= forcedStart)
        // Resume to a saved playhead when not a true mid-clip handoff, or when disk is ahead.
        let needsResumeSeek = savedAheadOfHead && (!continueMid || forcedStart > (t.isFinite ? t : 0) + 1.5)
        // Sparks / restart-from-0 path.
        let needsZeroSeek = !continueMid && !needsResumeSeek
            && (restartsFromBeginningOnFocus || forcedStart < 0.5)
            && !nearZero

        // Handoff: hide poster BEFORE play — never flash Frame 0 under mid-clip.
        posterView.isHidden = continueMid

        if autoplay, userWantsPlayback {
            // Prefer applyUserAudioOutput — refreshes epoch + foreground-watch protection
            // so a mid-load Feed silence bump cannot leave picture-with-no-sound.
            applyUserAudioOutput(on: claimed)
        } else {
            claimed.pause()
            claimed.isMuted = true
            claimed.volume = 0
        }

        if continueMid, userWantsPlayback {
            lastKnownSeconds = t.isFinite ? max(0, t) : 0
            posterView.isHidden = true
            claimed.safePlayImmediately(atRate: preferredRate)
            didKickPlayback = true
            onPlayingChanged?(true)
            onReady?()
        } else if needsResumeSeek {
            // Continue watching — do NOT seek until readyToPlay. Early seeks often finish=false
            // and leave the claimed warm player stuck at t=0 while we already "kicked".
            didKickPlayback = false
            pendingResumeSeconds = forcedStart
            lastKnownSeconds = forcedStart
            claimed.pause()
            claimed.rate = 0
            claimed.isMuted = true
            claimed.volume = 0
            posterView.isHidden = false
        } else if needsZeroSeek {
            // Seek under poster — reveal only after rate > 0.
            claimed.seek(
                to: .zero,
                toleranceBefore: .positiveInfinity,
                toleranceAfter: .positiveInfinity
            ) { [weak self] finished in
                guard finished, let self else { return }
                DispatchQueue.main.async {
                    self.lastKnownSeconds = 0
                    self.posterView.isHidden = false
                    guard self.userWantsPlayback else { return }
                    // Already playing after a prior kick — don't re-play (visible restart).
                    if self.didKickPlayback, claimed.rate > 0.01 {
                        self.revealPosterWhenPlaying(claimed)
                        return
                    }
                    _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                        keeping: claimed,
                        pageEpoch: self.activePageEpoch
                    )
                    claimed.isMuted = self.mutedFlag
                    claimed.volume = self.mutedFlag ? 0 : 1
                    claimed.safePlayImmediately(atRate: self.preferredRate)
                    self.didKickPlayback = true
                    self.onPlayingChanged?(true)
                    self.onReady?()
                    self.revealPosterWhenPlaying(claimed)
                }
            }
        } else if userWantsPlayback {
            lastKnownSeconds = nearZero ? 0 : lastKnownSeconds
            posterView.isHidden = false
            claimed.safePlayImmediately(atRate: preferredRate)
            didKickPlayback = true
            onPlayingChanged?(true)
            onReady?()
            revealPosterWhenPlaying(claimed)
        } else {
            // Silent pre-buffer (off-screen page).
            claimed.pause()
            claimed.isMuted = true
            claimed.volume = 0
            if restartsFromBeginningOnFocus, !nearZero {
                claimed.seek(
                    to: .zero,
                    toleranceBefore: .positiveInfinity,
                    toleranceAfter: .positiveInfinity
                )
            } else if forcedStart >= 0.5 {
                claimed.seek(
                    to: CMTime(seconds: forcedStart, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                lastKnownSeconds = forcedStart
                return
            }
            lastKnownSeconds = 0
        }

        if let item = claimed.currentItem {
            statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        // Stay on poster until rate > 0 (ready ≠ painted).
                        self.posterView.isHidden = false
                        if !self.didKickPlayback, self.userWantsPlayback {
                            self.didKickPlayback = true
                            let resume = self.pendingResumeSeconds
                            self.pendingResumeSeconds = 0
                            if resume >= 0.5 {
                                let head = claimed.currentTime().seconds
                                if !(head.isFinite && abs(head - resume) < 1.0) {
                                    await claimed.seek(
                                        to: CMTime(seconds: resume, preferredTimescale: 600),
                                        toleranceBefore: .zero,
                                        toleranceAfter: .zero
                                    )
                                }
                                self.lastKnownSeconds = resume
                            }
                            _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                                keeping: claimed,
                                pageEpoch: self.activePageEpoch
                            )
                            claimed.isMuted = self.mutedFlag
                            claimed.volume = self.mutedFlag ? 0 : 1
                            claimed.safePlayImmediately(atRate: self.preferredRate)
                            self.onPlayingChanged?(true)
                            self.onReady?()
                            self.revealPosterWhenPlaying(claimed)
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

    /// Drop poster only after AV is actually painting (never on readyToPlay alone).
    /// `rate > 0` alone still blinks — wait until time advances, then settle 1–2 frames.
    private func revealPosterWhenPlaying(_ player: AVPlayer) {
        Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 40_000_000)
                guard self.player === player else { return }
                let t = player.currentTime().seconds
                let advanced = t.isFinite && t >= 0.08
                let moving = player.rate > 0.05
                    || (player.timeControlStatus == .playing && player.rate > 0.01)
                if moving, advanced {
                    try? await Task.sleep(nanoseconds: 64_000_000)
                    guard self.player === player else { return }
                    self.posterView.isHidden = true
                    self.spinner.stopAnimating()
                    return
                }
            }
            // Last resort only if clearly playing with advanced time.
            if self.player === player {
                let t = player.currentTime().seconds
                if player.rate > 0.01, t.isFinite, t >= 0.08 {
                    self.posterView.isHidden = true
                    self.spinner.stopAnimating()
                }
            }
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
        // ~2 Hz — enough for the timeline, light enough not to rebuild SwiftUI chrome every tick.
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = observed.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            // Already on main (queue: .main) — do not nested-async (that lagged hubs chrome).
            let raw = time.seconds
            let current = raw.isFinite ? max(0, raw) : 0
            let duration = item.duration.seconds
            let dur = duration.isFinite && duration > 0 ? duration : 0
            let playing = observed.rate > 0.01
            self.lastKnownSeconds = current
            self.onProgress?(current, dur)
            if self.lastPublishedPlaying != playing {
                self.lastPublishedPlaying = playing
                self.onPlayingChanged?(playing)
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
        layer.videoGravity = preferredVideoGravity
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, above: posterView.layer)
        playerLayer = layer
        player = claimed
        resolvedPlayURL = original
        MediaPlaybackCoordinator.shared.register(claimed)
        noteContinuousProtection(claimed)
        if userWantsPlayback {
            noteForegroundWatchProtection(claimed)
        }
        // Sparks / warm-pool: soft-seek to 0 only when not already there (avoids black flash).
        // Continue watching: seek to saved playhead before first play.
        let forcedStart = restartsFromBeginningOnFocus ? 0 : startTime
        if restartsFromBeginningOnFocus || forcedStart < 0.5 {
            let t = claimed.currentTime().seconds
            if !(t.isFinite && t >= 0 && t < 0.35) {
                await claimed.seek(
                    to: .zero,
                    toleranceBefore: .positiveInfinity,
                    toleranceAfter: .positiveInfinity
                )
            }
            lastKnownSeconds = 0
        } else if forcedStart >= 0.5 {
            let t = claimed.currentTime().seconds
            if !(t.isFinite && abs(t - forcedStart) < 1.0) {
                await claimed.seek(
                    to: CMTime(seconds: forcedStart, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }
            lastKnownSeconds = forcedStart
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
        posterView.isHidden = true
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
                                claimed.safePlayImmediately(atRate: self.preferredRate)
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
            claimed.safePlayImmediately(atRate: preferredRate)
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

    private func restartFromBeginning(player: AVPlayer) {
        // Refresh epoch so a prior Sparks page-change doesn't block feed loop restarts.
        activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
        _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
            keeping: player,
            pageEpoch: activePageEpoch
        )
        player.isMuted = mutedFlag
        player.volume = mutedFlag ? 0 : 1
        player.seek(
            to: .zero,
            toleranceBefore: .positiveInfinity,
            toleranceAfter: .positiveInfinity
        ) { [weak self] finished in
            guard finished else { return }
            DispatchQueue.main.async {
                guard let self, self.userWantsPlayback else { return }
                player.play()
                player.safePlayImmediately(atRate: self.preferredRate)
                self.lastKnownSeconds = 0
                self.onPlayingChanged?(true)
            }
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
        r2ResourceLoader = nil

        // Important: no custom HTTP headers — Archive CDN + AVPlayer + headers = hang on poster.
        // GET-only R2/S3 presigns 403 on HEAD — proxy via matterya-r2:// so Range GET answers.
        let (asset, loader) = R2PresignedPlayback.makeAsset(for: url)
        r2ResourceLoader = loader

        // Kick playable/duration off the hot path (don’t await — Archive CDN is slow).
        Task(priority: .utility) {
            _ = try? await asset.load(.isPlayable, .duration)
        }

        guard !Task.isCancelled else { return }

        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = muted
        // false = kick playback as soon as enough is buffered (snappier Sparks).
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.actionAtItemEnd = loops ? .none : .pause

        let layer = AVPlayerLayer(player: newPlayer)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.videoGravity = preferredVideoGravity
        // Host view bounds only — never full-screen interim frame (zoom pop).
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, above: posterView.layer)
        CATransaction.commit()
        playerLayer = layer
        player = newPlayer
        resolvedPlayURL = url
        mutedFlag = muted
        MediaPlaybackCoordinator.shared.register(newPlayer)
        noteContinuousProtection(newPlayer)
        if userWantsPlayback {
            noteForegroundWatchProtection(newPlayer)
            configureAudioSession()
        }
        // Optimistic start only when NOT resuming mid-clip — Continue watching must
        // wait for readyToPlay seek so the first audible frame is the saved second.
        let resumeTarget = startTime > 0.5 ? startTime : pendingResumeSeconds
        if resumeTarget > 0.5 {
            pendingResumeSeconds = resumeTarget
            lastKnownSeconds = resumeTarget
            newPlayer.pause()
            newPlayer.isMuted = true
            newPlayer.volume = 0
        } else if userWantsPlayback {
            applyUserAudioOutput(on: newPlayer)
            if MediaPlaybackCoordinator.shared.isSolo(newPlayer) {
                newPlayer.safePlayImmediately(atRate: preferredRate)
            } else {
                newPlayer.pause()
                newPlayer.isMuted = true
                newPlayer.volume = 0
            }
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
                    // Keep poster until rate > 0 — readyToPlay still paints black.
                    self.posterView.isHidden = false
                    self.errorLabel.isHidden = true
                    // Kick playback only once per item — double play() caused visible restarts.
                    if !self.didKickPlayback {
                        self.didKickPlayback = true
                        let resume = self.pendingResumeSeconds > 0.5
                            ? self.pendingResumeSeconds
                            : (startTime > 0.5 ? startTime : 0)
                        self.pendingResumeSeconds = 0
                        if resume > 0.5 {
                            await newPlayer.seek(
                                to: CMTime(seconds: resume, preferredTimescale: 600),
                                toleranceBefore: .zero,
                                toleranceAfter: .zero
                            )
                            self.lastKnownSeconds = resume
                        }
                        if self.userWantsPlayback,
                           MediaPlaybackCoordinator.shared.soloSparkAudio(
                               keeping: newPlayer,
                               pageEpoch: self.activePageEpoch
                           ) {
                            newPlayer.isMuted = self.mutedFlag
                            newPlayer.volume = self.mutedFlag ? 0 : 1
                            newPlayer.safePlayImmediately(atRate: self.preferredRate)
                            self.revealPosterWhenPlaying(newPlayer)
                        } else {
                            newPlayer.pause()
                            newPlayer.isMuted = true
                            newPlayer.volume = 0
                        }
                        DispatchQueue.main.async { [weak self] in
                            self?.onPlayingChanged?(true)
                            self?.onReady?()
                        }
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

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            let current = max(0, time.seconds)
            let duration = item.duration.seconds
            let dur = duration.isFinite && duration > 0 ? duration : 0
            let playing = newPlayer.rate > 0.01
            self.lastKnownSeconds = current
            self.onProgress?(current, dur)
            if self.lastPublishedPlaying != playing {
                self.lastPublishedPlaying = playing
                self.onPlayingChanged?(playing)
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
        // One retry: R2 → /v1/playback; archive → CDN flip.
        if !didRetry {
            didRetry = true
            let looksR2 = MediaURLResolver.looksLikeR2HostedURL(original)
                || MediaURLResolver.looksLikeR2HostedURL(attempted)
                || MediaURLResolver.isBlockedR2PublicURL(attempted)
            let permissionDenied = message.localizedCaseInsensitiveContains("permission")
            if (looksR2 || permissionDenied), let postID, !postID.isEmpty {
                await R2PlaybackResolver.shared.invalidate(postID: postID)
                if let live = await R2PlaybackResolver.shared.playURL(postID: postID, fallback: nil),
                   !MediaURLResolver.isBlockedR2PublicURL(live),
                   live.absoluteString != attempted.absoluteString {
                    #if DEBUG
                    print("[ArchiveVideo] R2 playback retry \(attempted.host ?? "") → \(live.host ?? "")")
                    #endif
                    await installPlayer(url: live, original: original, muted: muted, startTime: startTime)
                    return
                }
            }
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
        // Never setActive on main — SessionCore warns and freezes UI (chat composer during hubs).
        MediaPlaybackCoordinator.shared.ensurePlaybackAudioSession()
    }

    private func loadPoster(_ url: URL?) {
        posterView.isHidden = false
        posterView.image = nil
        // Reject banned pub-*.r2.dev / expired embeds — fall through to Frame0 below.
        let usable = url.flatMap { MediaURLResolver.isUsablePosterURL($0) ? $0 : nil }
        Task {
            if let usable {
                if let image = await ImageCache.shared.image(for: usable, maxPixelSize: 900) {
                    self.posterView.image = image
                    return
                }
            }
            if let postID,
               let signed = await Frame0PosterResolver.shared.posterURL(postID: postID),
               MediaURLResolver.isUsablePosterURL(signed),
               let image = await ImageCache.shared.image(for: signed, maxPixelSize: 900) {
                self.posterView.image = image
            }
        }
    }
}
