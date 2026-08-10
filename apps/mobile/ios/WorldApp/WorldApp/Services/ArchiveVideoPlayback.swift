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

    /// Hubs watch never shows a fullscreen control (top or bottom).
    var allowsFullscreen: Bool = false

    @StateObject private var bridge = ArchivePlayerBridge()
    @State private var showChrome = true
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
        isMuted: Binding<Bool> = .constant(false),
        allowsFullscreen: Bool = false,
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
        self._isMuted = isMuted
        self.allowsFullscreen = allowsFullscreen
        self.onReady = onReady
        self.onPlayingChange = onPlayingChange
        self.onProgress = onProgress
        self.onVideoSize = onVideoSize
        self.seekToSeconds = seekToSeconds
        self.onSeekConsumed = onSeekConsumed
    }

    var body: some View {
        ZStack {
            ArchiveVideoPlayerView(
                url: url,
                posterURL: posterURL,
                // Stay active under fullscreen cover so resume is reliable after dismiss.
                isActive: isActive && !showFullscreen,
                muted: isMuted,
                startTime: startTime,
                loops: loops,
                fillsFrame: fillsFrame,
                bridge: bridge,
                onReady: {
                    bridge.publishReady(playing: true)
                    DispatchQueue.main.async {
                        onReady?()
                        if showsControls {
                            showChrome = true
                            scheduleChromeHide()
                        }
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
                onSeekConsumed: onSeekConsumed
            )

            if showsControls {
                // Loading / buffering spinner (YouTube center ring).
                if !bridge.isReady {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.15)
                        .zIndex(2)
                }

                if showChrome || !bridge.isPlaying {
                    hubChrome
                        .transition(.opacity)
                        .zIndex(3)
                } else {
                    // Chrome hidden while playing — still capture taps + double-tap skip.
                    youtubeHiddenChromeHitLayer
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
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(40)
                }
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
        .onChange(of: showsControls) { _, visible in
            if visible {
                showChrome = true
                scheduleChromeHide()
            } else {
                // Mini player: hide chrome but keep the AVPlayer actively rendering.
                chromeHideTask?.cancel()
                showChrome = false
            }
            // Expand ↔ mini only toggles chrome — never pause or remount.
            if isActive {
                bridge.controller?.setActive(true)
                bridge.controller?.ensureContinuingPlayback()
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
        ZStack {
            // Soft dim when paused — keep transparent enough to avoid “black bar” slabs.
            if !bridge.isPlaying {
                Color.black.opacity(0.18)
                    .allowsHitTesting(false)
            }

            // Single tap empty area → hide chrome when playing; double-tap L/R → ±10s.
            youtubeGestureLayer
                .zIndex(0)

            // Top tools — mute only (no fullscreen control on Hubs watch).
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
                // Stage already sits below the island — no extra safe-top pad.
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
            .zIndex(5)

            // Center play — Matterya accent disc
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
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
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
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Landscape fullscreen (hub / archive)

/// Full-screen hub player. Unlocks landscape so tilting the device rotates playback.
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
                bridge: bridge,
                onReady: {
                    bridge.publishReady(playing: true)
                    scheduleChromeHide()
                },
                onProgress: { current, duration in
                    guard !isScrubbing else { return }
                    let playing = bridge.controller?.isPlaying
                    bridge.publishProgress(current: current, duration: duration, playing: playing)
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

            if showChrome || !bridge.isPlaying {
                fullscreenChrome
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            isMuted = initialMuted
            AppDelegate.orientationLock = .allButUpsideDown
            Self.refreshSupportedOrientations()
            scheduleChromeHide()
        }
        .onDisappear {
            chromeHideTask?.cancel()
            AppDelegate.orientationLock = .portrait
            Self.refreshSupportedOrientations()
        }
        .onChange(of: isMuted) { _, muted in
            bridge.controller?.setMuted(muted)
            bridge.publishMuted(muted)
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

    private static func refreshSupportedOrientations() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
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

        // Match video gravity (updated in applyVideoGravity) — avoid poster/video framing jump.
        // Default fill so Sparks never flash fit→fill on first layout.
        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.backgroundColor = .clear
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

    /// Updated every layout via `applyVideoGravity` — default fit (no crop) until told otherwise.
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
        // Clear bed — no black letterbox slabs around aspectFit.
        posterView.backgroundColor = .clear
        view.backgroundColor = .clear
        playerLayer?.backgroundColor = UIColor.clear.cgColor
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

    func setActive(_ active: Bool) {
        if active {
            userWantsPlayback = true
            activePageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
            // Do NOT restart-from-0 here. Sparks focus restarts only via
            // `restartFromBeginningAndPlay()` (token). Calling both caused
            // play → re-layout → play (video “jumps to center” and restarts).
            if let player {
                applyUserAudioOutput(on: player)
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
            userWantsPlayback = false
            isScrubbing = false
            // Silence inactive pages — prevents stacked audio. mutedFlag stays as user choice.
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
                player.safePlayImmediately(atRate: 1.0)
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
                player.safePlayImmediately(atRate: 1.0)
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
        // Only the current solo may resume. Off-screen / previous Sparks stay silent.
        guard MediaPlaybackCoordinator.shared.isSolo(player) else {
            player.pause()
            player.isMuted = true
            player.volume = 0
            return
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

        // Instagram-speed: claim a pre-buffered player before any CDN resolve.
        // Install + play synchronously so the first painted frame is video, not black/poster.
        if let postID, let claimed = SparkWarmPool.shared.claim(postID: postID) {
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
            let playURL = await ArchiveVideoPlayback.resolvedPlaybackURL(for: url)
            guard !Task.isCancelled else { return }
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

        claimed.automaticallyWaitsToMinimizeStalling = false
        claimed.actionAtItemEnd = loops ? .none : .pause
        mutedFlag = muted

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
        if autoplay {
            configureAudioSession()
        }
        spinner.stopAnimating()
        // Keep poster until we have a ready item — then hide (no black gap).
        posterView.isHidden = claimed.currentItem?.status == .readyToPlay
        errorLabel.isHidden = true
        // Do not layoutIfNeeded with zero bounds — wait for viewDidLayoutSubviews.

        let forcedStart = restartsFromBeginningOnFocus ? 0 : startTime
        let t = claimed.currentTime().seconds
        // Wide near-zero: warm park is rarely exact 0 — skip seek to kill swipe flash.
        let nearZero = t.isFinite && t >= 0 && t < 1.0
        let needsSeek = (restartsFromBeginningOnFocus || forcedStart < 0.5) && !nearZero

        if autoplay, userWantsPlayback {
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

        if needsSeek {
            // Keyframe seek without covering with poster — keep layer visible.
            claimed.seek(
                to: .zero,
                toleranceBefore: .positiveInfinity,
                toleranceAfter: .positiveInfinity
            ) { [weak self] finished in
                guard finished, let self else { return }
                DispatchQueue.main.async {
                    self.lastKnownSeconds = 0
                    self.posterView.isHidden = true
                    guard self.userWantsPlayback else { return }
                    // Already playing after a prior kick — don't re-play (visible restart).
                    if self.didKickPlayback, claimed.rate > 0.01 { return }
                    _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                        keeping: claimed,
                        pageEpoch: self.activePageEpoch
                    )
                    claimed.isMuted = self.mutedFlag
                    claimed.volume = self.mutedFlag ? 0 : 1
                    claimed.safePlayImmediately(atRate: 1.0)
                    self.didKickPlayback = true
                    self.onPlayingChanged?(true)
                    self.reportVideoSizeIfNeeded(from: claimed.currentItem)
                    self.onReady?()
                }
            }
        } else if userWantsPlayback {
            lastKnownSeconds = nearZero ? 0 : lastKnownSeconds
            posterView.isHidden = true
            claimed.safePlayImmediately(atRate: 1.0)
            didKickPlayback = true
            onPlayingChanged?(true)
            reportVideoSizeIfNeeded(from: claimed.currentItem)
            onReady?()
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
            }
            lastKnownSeconds = 0
        }

        if let item = claimed.currentItem {
            statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.posterView.isHidden = true
                        if !self.didKickPlayback, self.userWantsPlayback {
                            self.didKickPlayback = true
                            _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                                keeping: claimed,
                                pageEpoch: self.activePageEpoch
                            )
                            claimed.isMuted = self.mutedFlag
                            claimed.volume = self.mutedFlag ? 0 : 1
                            claimed.safePlayImmediately(atRate: 1.0)
                            self.onPlayingChanged?(true)
                            self.onReady?()
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
            let raw = time.seconds
            let current = raw.isFinite ? max(0, raw) : 0
            let duration = item.duration.seconds
            let dur = duration.isFinite && duration > 0 ? duration : 0
            let playing = observed.rate > 0.01
            let scrubbing = self.isScrubbing
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // While scrubbing, UI owns the playhead — don't fight the thumb or publish pause.
                if !scrubbing {
                    self.lastKnownSeconds = current
                    // Always publish — parent must not rely on stale isActive captures.
                    self.onProgress?(current, dur)
                    self.onPlayingChanged?(playing)
                }
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
        // Sparks / warm-pool: soft-seek to 0 only when not already there (avoids black flash).
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
                player.safePlayImmediately(atRate: 1.0)
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

        // Important: no custom HTTP headers — Archive CDN + AVPlayer + headers = hang on poster.
        let asset = AVURLAsset(
            url: url,
            options: [
                AVURLAssetAllowsCellularAccessKey: true,
                AVURLAssetAllowsExpensiveNetworkAccessKey: true,
                AVURLAssetAllowsConstrainedNetworkAccessKey: true,
            ]
        )

        // Don't block first frame on duration metadata (slow on Archive CDN).
        asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {}

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
                    self.posterView.isHidden = true
                    self.errorLabel.isHidden = true
                    // Kick playback only once per item — double play() caused visible restarts.
                    if !self.didKickPlayback {
                        self.didKickPlayback = true
                        if startTime > 0.5 {
                            await newPlayer.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                        }
                        if self.userWantsPlayback,
                           MediaPlaybackCoordinator.shared.soloSparkAudio(
                               keeping: newPlayer,
                               pageEpoch: self.activePageEpoch
                           ) {
                            newPlayer.isMuted = self.mutedFlag
                            newPlayer.volume = self.mutedFlag ? 0 : 1
                            newPlayer.safePlayImmediately(atRate: 1.0)
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
