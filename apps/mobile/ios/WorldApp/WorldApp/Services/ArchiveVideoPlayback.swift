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

    func seek(to seconds: Double) {
        controller?.seek(to: seconds)
        currentSeconds = seconds
    }

    func toggleMute() {
        let next = !(controller?.isMuted ?? isMuted)
        controller?.setMuted(next)
        isMuted = next
    }

    func skip(by delta: Double) {
        let target = max(0, min(durationSeconds, currentSeconds + delta))
        seek(to: target)
    }

    func beginScrub() {
        controller?.beginScrub()
    }

    func endScrub() {
        controller?.endScrub()
        isPlaying = controller?.isPlaying ?? isPlaying
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
    /// Always fill the stage (`.resizeAspectFill`) — never black bars on sides or top.
    var fillsFrame: Bool = true
    @Binding var isMuted: Bool
    var onReady: (() -> Void)? = nil
    /// Keeps AppState.hubPlaybackPlaying in sync when chrome play/pause is used.
    var onPlayingChange: ((Bool) -> Void)? = nil

    var allowsFullscreen: Bool = true

    @StateObject private var bridge = ArchivePlayerBridge()
    @State private var showChrome = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var showFullscreen = false

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
        allowsFullscreen: Bool = true,
        onReady: (() -> Void)? = nil,
        onPlayingChange: ((Bool) -> Void)? = nil
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
                    if let postID, current >= 0.5 {
                        YouTubeCatalogService.shared.notePlaybackPosition(
                            current,
                            for: postID,
                            duration: duration > 0 ? duration : nil
                        )
                    }
                }
            )

            if showsControls {
                // Chrome / tap-to-reveal first (under transport).
                if showChrome || !bridge.isReady {
                    hubChrome
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showChrome = true
                            }
                            scheduleChromeHide()
                        }
                        .zIndex(1)
                }

                // Mute + fullscreen ALWAYS on top of chrome/tap layers so hits never get stolen.
                VStack {
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        chromeIconButton(
                            systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                        ) {
                            isMuted.toggle()
                            bridge.controller?.setMuted(isMuted)
                            bridge.publishMuted(isMuted)
                            // Feed binding already updates appState.feedVideosMuted when shared.
                            scheduleChromeHide()
                        }
                        if allowsFullscreen {
                            chromeIconButton(systemName: "arrow.up.left.and.arrow.down.right") {
                                showFullscreen = true
                                chromeHideTask?.cancel()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    Spacer(minLength: 0)
                }
                .zIndex(50)
                .allowsHitTesting(true)
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

    /// Center transport (like the provided Hubs chrome): −10s · play/pause · +10s, scrubber bottom.
    private var hubChrome: some View {
        ZStack {
            // Tap empty area to hide chrome (transport + scrubber sit above this layer).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showChrome = false
                    }
                    chromeHideTask?.cancel()
                }

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
                        .frame(width: 42, alignment: .leading)

                    HubTimelineScrubber(
                        value: scrubberValue,
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if editing {
                                chromeHideTask?.cancel()
                                bridge.beginScrub()
                            } else if bridge.durationSeconds > 0 {
                                bridge.seek(to: bridge.currentSeconds)
                                bridge.endScrub()
                                scheduleChromeHide()
                            }
                        },
                        onValueChanged: { fraction in
                            guard bridge.durationSeconds > 0 else { return }
                            bridge.currentSeconds = fraction * bridge.durationSeconds
                        }
                    )

                    Text(formatTime(bridge.durationSeconds))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(Theme.paper.opacity(0.75))
                        .frame(width: 42, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .padding(.top, 18)
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

    private func scheduleChromeHide() {
        chromeHideTask?.cancel()
        // Stay up while paused so center play / ±10s never vanish mid-pause.
        guard bridge.isPlaying else { return }
        chromeHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
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
        let m = total / 60
        let s = total % 60
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

            if showChrome {
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
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if editing {
                                chromeHideTask?.cancel()
                                bridge.beginScrub()
                            } else if bridge.durationSeconds > 0 {
                                bridge.seek(to: bridge.currentSeconds)
                                bridge.endScrub()
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
                        .foregroundStyle(.white.opacity(0.75))
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
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func refreshSupportedOrientations() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
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
    /// When true, fill the stage (no black bars). Hubs always fills.
    var fillsFrame: Bool = true
    /// Optional content id for continuity / engagement (not required for playback).
    var postID: String? = nil
    var bridge: ArchivePlayerBridge? = nil
    var onReady: (() -> Void)? = nil
    var onFailed: ((String) -> Void)? = nil
    var onProgress: ((Double, Double) -> Void)? = nil
    /// When set, seek once then clear via `onSeekConsumed`.
    var seekToSeconds: Double? = nil
    var onSeekConsumed: (() -> Void)? = nil

    final class Coordinator {
        var lastURL: URL?
        var lastActive: Bool?
        var lastMuted: Bool?
        var lastSeekToken: Double?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var videoGravity: AVLayerVideoGravity {
        fillsFrame ? .resizeAspectFill : .resizeAspect
    }

    func makeUIViewController(context: Context) -> ArchiveVideoPlayerController {
        let vc = ArchiveVideoPlayerController()
        vc.loops = loops
        vc.postID = postID
        vc.onReady = onReady
        vc.onFailed = onFailed
        vc.onProgress = onProgress
        vc.onPlayingChanged = { [weak bridge] playing in
            bridge?.publishPlaying(playing)
        }
        bridge?.controller = vc
        bridge?.publishMuted(muted)
        context.coordinator.lastURL = url
        context.coordinator.lastActive = isActive
        context.coordinator.lastMuted = muted
        vc.configure(url: url, posterURL: posterURL, muted: muted, startTime: startTime, active: isActive)
        vc.applyVideoGravity(videoGravity)
        return vc
    }

    func updateUIViewController(_ vc: ArchiveVideoPlayerController, context: Context) {
        vc.loops = loops
        vc.postID = postID
        vc.onReady = onReady
        vc.onFailed = onFailed
        vc.onProgress = onProgress
        vc.applyVideoGravity(videoGravity)
        vc.onPlayingChanged = { [weak bridge] playing in
            bridge?.publishPlaying(playing)
        }
        bridge?.controller = vc

        let urlChanged = context.coordinator.lastURL != url
        let activeChanged = context.coordinator.lastActive != isActive
        let mutedChanged = context.coordinator.lastMuted != muted

        if urlChanged {
            context.coordinator.lastURL = url
            context.coordinator.lastActive = isActive
            context.coordinator.lastMuted = muted
            vc.configure(url: url, posterURL: posterURL, muted: muted, startTime: startTime, active: isActive)
            return
        }

        // Only react to real state changes — do not re-kick play on every SwiftUI redraw
        // (that caused Sparks to start, restart, then settle).
        if mutedChanged {
            context.coordinator.lastMuted = muted
            vc.setMuted(muted)
        }
        if activeChanged {
            context.coordinator.lastActive = isActive
            if isActive {
                // pauseAll() may have forced player.isMuted = true; restore SwiftUI mute flag.
                vc.setMuted(muted)
                vc.setActive(true)
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
    /// Sparks loop by default so clips don't freeze on the last frame.
    var loops = true
    /// Used to claim a pre-buffered player from SparkWarmPool.
    var postID: String?

    /// User intent — survives SwiftUI re-renders during pull-down drag.
    private var userWantsPlayback = true
    /// True while scrubbing timeline (paused for seek, but intent may still be play).
    private var isScrubbing = false
    /// Last known playhead — used when remounting so mini↔full never restarts at 0.
    private var lastKnownSeconds: Double = 0
    /// Chrome / user mute — separate from forced silence when the Spark page is inactive.
    private var mutedFlag = false
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
        view.backgroundColor = .black
        view.clipsToBounds = true

        posterView.contentMode = .scaleAspectFit
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
        // Disable implicit animations so mini expand/collapse doesn't blank the layer for a frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = view.bounds
        // Keep the picture filling the mini slot (196×110) and full watch stage by default.
        playerLayer?.videoGravity = preferredVideoGravity
        CATransaction.commit()
    }

    private var preferredVideoGravity: AVLayerVideoGravity = .resizeAspectFill

    func applyVideoGravity(_ gravity: AVLayerVideoGravity) {
        preferredVideoGravity = gravity
        playerLayer?.videoGravity = gravity
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
        resolvedPlayURL = nil
        errorLabel.isHidden = true
        loadPoster(posterURL)
        setMuted(muted)
        if active {
            startPlayback(url: url, muted: muted, startTime: startTime)
        } else {
            pauseOnly()
        }
    }

    func setActive(_ active: Bool) {
        if active {
            userWantsPlayback = true
            // Restore audible output after inactive force-silence (must not stick after play).
            if let player {
                applyUserAudioOutput(on: player)
            }
            // If we already have a player, resume gently; don't re-resolve or seek to 0.
            if player != nil {
                ensureContinuingPlayback()
            } else if let sourceURL {
                // Remount recovery — resume near last progress, never hard-restart at 0.
                let resume = max(lastKnownSeconds, currentSeconds)
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
            DispatchQueue.main.async { [weak self] in
                self?.onPlayingChanged?(false)
            }
        }
    }

    /// Resume only if genuinely stalled — never re-seek or re-create the item.
    func ensureContinuingPlayback() {
        guard userWantsPlayback, !isScrubbing, let player else { return }
        applyUserAudioOutput(on: player)
        // Avoid fighting a healthy playhead (rate can briefly report 0 while buffering).
        if player.rate < 0.05, player.timeControlStatus != .waitingToPlayAtSpecifiedRate {
            player.play()
            player.safePlayImmediately(atRate: 1.0)
            DispatchQueue.main.async { [weak self] in
                self?.onPlayingChanged?(true)
            }
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
        MediaPlaybackCoordinator.shared.soloSparkAudio(keeping: player)
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

    func seek(to seconds: Double) {
        guard let player else { return }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Pause only for timeline scrub — does not clear play intent.
    func beginScrub() {
        isScrubbing = true
        player?.pause()
    }

    func endScrub() {
        isScrubbing = false
        if userWantsPlayback {
            ensureContinuingPlayback()
        }
    }

    func teardown() {
        loadTask?.cancel()
        loadTask = nil
        removeObservers()
        if let postID {
            SparkWarmPool.shared.release(postID: postID)
        }
        if let player {
            player.pause()
            player.replaceCurrentItem(with: nil)
            MediaPlaybackCoordinator.shared.unregister(player)
        }
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        // Release audio so Sparks/DB clips cannot keep playing outside the viewer.
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startPlayback(url: URL, muted: Bool, startTime: Double) {
        loadTask?.cancel()
        spinner.startAnimating()
        errorLabel.isHidden = true

        // Instagram-speed: claim a pre-buffered player before any CDN resolve.
        if let postID, let claimed = SparkWarmPool.shared.claim(postID: postID) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.installClaimedPlayer(claimed, original: url, muted: muted, startTime: startTime)
            }
            return
        }
        if let postID {
            SparkWarmPool.shared.markInUse(postID: postID)
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            let playURL = await ArchiveVideoPlayback.resolvedPlaybackURL(for: url)
            guard !Task.isCancelled else { return }
            await self.installPlayer(url: playURL, original: url, muted: muted, startTime: startTime)
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
        MediaPlaybackCoordinator.shared.soloSparkAudio(keeping: claimed)
        if userWantsPlayback {
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
                            if startTime > 0.5 {
                                await claimed.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                            }
                            if self.userWantsPlayback {
                                MediaPlaybackCoordinator.shared.soloSparkAudio(keeping: claimed)
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
        layer.videoGravity = preferredVideoGravity
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, above: posterView.layer)
        playerLayer = layer
        player = newPlayer
        resolvedPlayURL = url
        mutedFlag = muted
        MediaPlaybackCoordinator.shared.register(newPlayer)
        configureAudioSession()
        // Optimistic start — Sparks feel instant; readyToPlay will re-kick if needed.
        if userWantsPlayback {
            MediaPlaybackCoordinator.shared.soloSparkAudio(keeping: newPlayer)
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
                        if self.userWantsPlayback {
                            MediaPlaybackCoordinator.shared.soloSparkAudio(keeping: newPlayer)
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
            DispatchQueue.main.async { [weak self] in
                self?.lastKnownSeconds = current
                self?.onProgress?(current, dur)
                self?.onPlayingChanged?(playing)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.loops, self.userWantsPlayback {
                    newPlayer.seek(to: .zero)
                    self.lastKnownSeconds = 0
                    newPlayer.safePlayImmediately(atRate: 1.0)
                    self.onPlayingChanged?(true)
                } else {
                    self.onPlayingChanged?(false)
                }
            }
        }
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
