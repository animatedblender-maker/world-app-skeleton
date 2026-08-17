import AVFoundation
import SwiftUI
import UIKit

struct VideoPlayerView: View {
    @Environment(AppState.self) private var appState

    let url: URL
    let posterURL: URL?
    var placement: String? = nil
    var countryCode: String? = nil
    var contentCountryCode: String? = nil
    var postID: String? = nil
    var adsEnabled: Bool = true
    var isActive: Bool = true
    var loops: Bool = false
    var muted: Bool = false
    var showsControls: Bool = false
    var allowsFullscreen: Bool = false
    var startTime: Double? = nil
    /// When false, teardown won't write a lower position over an existing resume point (mini player).
    var persistsPositionOnTeardown: Bool = true
    /// When true, mute/unmute updates app-wide feed mute (all feed videos stay in sync).
    var sharesFeedMute: Bool = false
    /// When true, crop to fill the card — no black bars. Always preferred for Hubs / feed video.
    var fillsFrame: Bool = true
    /// When true, build/buffer a silent player even while `isActive` is false (feed Sparks).
    var preloadsWhenInactive: Bool = false
    var onViewed: (() -> Void)? = nil
    /// Progress callback for Sparks timeline scrubber: (currentSeconds, durationSeconds).
    var onProgress: ((Double, Double) -> Void)? = nil
    /// Natural presentation size (for Sparks smart fill vs letterbox).
    var onVideoSize: ((CGSize) -> Void)? = nil
    /// When set to a non-nil value, seek there once then clear via `onSeekConsumed`.
    var seekToSeconds: Double? = nil
    var onSeekConsumed: (() -> Void)? = nil
    /// Sparks player: bump when the page becomes focused so playback always starts at 0
    /// (independent of pause/unpause, which only toggles `isActive`).
    var restartFromBeginningToken: UInt = 0
    /// User pause on the focused Spark — freezes the **current frame** (does not deactivate
    /// the page, seek to 0, or swap to poster/black).
    var isPausedByUser: Bool = false

    @State private var adFinished = false
    @State private var player: AVPlayer?
    @State private var didReportView = false
    @State private var loopObserver: NSObjectProtocol?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var timeObserver: Any?
    @State private var timeObserverPlayer: AVPlayer?
    @State private var loadFailed = false
    @State private var didRetryWithPublicURL = false
    /// Hard cap on cold recoveries — prevents infinite fail loops on dead media.
    @State private var playbackRecoveryPasses = 0
    @State private var configuredURL: URL?
    @State private var showFullscreen = false
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var currentSeconds: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var showChrome = false
    @State private var chromeTask: Task<Void, Never>?
    @State private var lastNotedPlaybackSecond: Int = -1
    /// When the user pauses via chrome, do not auto-resume until they press play or leave the slot.
    @State private var userWantsPause = false
    /// Live flags for AVPlayer observers — View `isActive` is a struct capture and goes stale
    /// when LazyVStack keeps inactive Spark cards mounted (ghost audio from 1–2 pages ago).
    @State private var liveGate = VideoPlayerLiveGate()
    /// Last Sparks page-focus restart we already applied (so unpause doesn't re-seek → black flash).
    @State private var lastHandledRestartToken: UInt = 0
    /// Hide AVPlayerLayer while seeking to t=0 so the poster underlay stays visible (no black flash).
    @State private var isRestartSeeking = false
    /// Keep poster on top until AVPlayer is actually producing frames (not just “play() called”).
    @State private var showPosterCover = true
    @State private var didReportVideoSize = false
    @State private var presentationSizeObserver: NSKeyValueObservation?
    /// Debounce loop restarts (DidPlayToEnd + near-end time observer can both fire).
    @State private var lastLoopRestartAt: Date = .distantPast
    @State private var isLoopRestarting = false

    private var shouldShowAd: Bool {
        adsEnabled && isActive && !adFinished && placement != nil
    }

    private var shouldShowChrome: Bool {
        showsControls && showChrome && player != nil && !shouldShowAd
    }

    /// Poster only when we truly have no usable video surface.
    /// Never cover just because `!isPlaying` — that re-flashes black/poster on every swipe.
    /// User-paused keeps the live video layer visible so the frame freezes in place.
    private var shouldShowPosterCover: Bool {
        if isPausedByUser, player != nil, !isRestartSeeking { return false }
        if player == nil { return true }
        // Mid hard-seek with no ready item: keep poster. Once ready, leave layer visible.
        if isRestartSeeking, player?.currentItem?.status != .readyToPlay { return true }
        return showPosterCover
    }

    var body: some View {
        ZStack {
            // Never pure black under Sparks — poster or dark paper while buffering.
            Color.black

            // Poster matches video gravity (fill/fit) so there is no framing jump.
            if let posterURL {
                CachedAsyncImage(
                    url: posterURL,
                    maxPixelSize: 900,
                    contentMode: fillsFrame ? .fill : .fit,
                    placeholder: AnyView(Color.black)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
            }

            if shouldShowAd, let placement {
                AdPrerollView(
                    placement: placement,
                    countryCode: countryCode,
                    contentCountryCode: contentCountryCode,
                    postID: postID,
                    onComplete: { adFinished = true }
                )
            } else if let player {
                MatteryaVideoSurface(player: player, fillsFrame: fillsFrame)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    // Always keep the layer visible once mounted. Hiding it on swipe
                    // (opacity ~0) caused the black "refresh" even when the item was ready.
                    .opacity(1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard showsControls else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showChrome.toggle()
                        }
                        scheduleChromeHide()
                    }

                if shouldShowChrome {
                    MatteryaVideoControls(
                        isPlaying: isPlaying,
                        isMuted: isMuted,
                        currentSeconds: currentSeconds,
                        durationSeconds: durationSeconds,
                        showsFullscreen: allowsFullscreen,
                        isFullscreen: false,
                        onPlayPause: { togglePlayback() },
                        onMuteToggle: { toggleMute() },
                        onSeek: { seek(to: $0) },
                        onFullscreen: allowsFullscreen ? { openFullscreen() } : nil,
                        onExitFullscreen: nil
                    )
                    .transition(.opacity)
                }
            } else if loadFailed {
                unavailableState
            } else if posterURL == nil {
                ProgressView().tint(Theme.accentBright)
            }

            // Poster cover only while cold — same gravity as video.
            if let posterURL, shouldShowPosterCover {
                CachedAsyncImage(
                    url: posterURL,
                    maxPixelSize: 900,
                    contentMode: fillsFrame ? .fill : .fit,
                    placeholder: AnyView(Color.black)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
            }
        }
        .background(Color.black)
        .onAppear {
            liveGate.isActive = isActive
            liveGate.userWantsPause = userWantsPause
            liveGate.onProgress = onProgress
            // Only cover cold mounts — reclaiming a warm player must not flash poster/black.
            if player?.currentItem?.status != .readyToPlay {
                showPosterCover = true
            } else {
                showPosterCover = false
            }
            if isActive {
                liveGate.pageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
            }
            isMuted = sharesFeedMute ? appState.feedVideosMuted : muted
            liveGate.isMuted = isMuted
            configureAudioSession()
            // Buffer the moment the cell mounts (feed + Sparks) — don't wait for focus.
            handleActivationOrMount(forceRebuild: player?.currentItem == nil)
            // Chrome starts hidden — only a tap reveals transport (no scroll noise).
            reportVideoSizeIfNeeded(from: player?.currentItem)
        }
        // Screenshot / Control Center must not leave video paused.
        .onReceive(NotificationCenter.default.publisher(for: .matteryaResumePlaybackAfterInterrupt)) { _ in
            // liveGate + solo only — never resume an off-screen / non-solo Spark
            // (comments overlay used to wake “older” pages that still had isActive=true).
            guard liveGate.isActive, !liveGate.userWantsPause, let player, player.currentItem != nil else { return }
            // Must already be solo — do not claim solo here (that stole audio from the current Spark).
            guard MediaPlaybackCoordinator.shared.isSolo(player) else {
                player.pause()
                player.isMuted = true
                player.volume = 0
                return
            }
            if player.rate < 0.01 {
                kickAudiblePlayback(on: player)
            }
        }
        .onChange(of: isActive) { _, active in
            liveGate.isActive = active
            liveGate.onProgress = onProgress
            if active {
                // Bind to the current page epoch so late observers from prior pages cannot re-solo.
                liveGate.pageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
                // Respect user pause if they paused then we re-entered the same page.
                userWantsPause = isPausedByUser
                liveGate.userWantsPause = isPausedByUser
                if isPausedByUser {
                    // Stay on frozen frame — no poster swap, no restart seek.
                    player?.pause()
                    isPlaying = false
                    showPosterCover = false
                    return
                }
                // Warm / ready items already have a decoded frame — never slam poster (blink).
                if player?.currentItem?.status == .readyToPlay {
                    showPosterCover = false
                } else if player != nil {
                    // Feed focus won while still buffering — poll briefly so we don't stay on thumb.
                    Task { @MainActor in
                        for _ in 0..<25 {
                            if player?.currentItem?.status == .readyToPlay {
                                showPosterCover = false
                                return
                            }
                            try? await Task.sleep(nanoseconds: 40_000_000)
                        }
                        // Fallback: reveal anyway so we never stick on thumbnail forever.
                        showPosterCover = false
                    }
                }
                // Re-bind progress + ensure observer is alive after focus (preload path).
                if let player {
                    attachTimeObserver(to: player)
                    // Push one immediate tick so the rail isn't stuck at 0 until the next interval.
                    let t = player.currentTime().seconds
                    let cur = t.isFinite ? max(0, t) : 0
                    currentSeconds = cur
                    if let item = player.currentItem {
                        updateDuration(from: item)
                        reportVideoSizeIfNeeded(from: item)
                    }
                    liveGate.onProgress?(cur, durationSeconds)
                }
                handleActivationOrMount(forceRebuild: false)
            } else {
                // Page left the viewport — not a user pause.
                if restartFromBeginningToken == 0 {
                    persistPlaybackPosition()
                }
                player?.pause()
                player?.isMuted = true
                player?.volume = 0
                isPlaying = false
                // Keep last decoded frame under the next page; don't force poster swap.
                isRestartSeeking = false
                userWantsPause = false
                liveGate.userWantsPause = false
                // Pre-seek to 0 while OFF-SCREEN so next focus can play without a seek flash.
                if restartFromBeginningToken > 0 {
                    softSeekToBeginning(playAfter: false)
                }
            }
        }
        .onChange(of: isPausedByUser) { _, paused in
            liveGate.userWantsPause = paused
            userWantsPause = paused
            guard liveGate.isActive, let player, player.currentItem != nil else { return }
            if paused {
                // Freeze current frame — keep AVPlayer layer visible (no poster / black).
                player.pause()
                isPlaying = false
                showPosterCover = false
                isRestartSeeking = false
            } else {
                kickAudiblePlayback(on: player)
            }
        }
        .onChange(of: restartFromBeginningToken) { _, token in
            guard token > 0, token != lastHandledRestartToken else { return }
            guard !isPausedByUser else {
                lastHandledRestartToken = token
                return
            }
            // Never force poster on warm ready players (blink on swipe).
            if player?.currentItem?.status == .readyToPlay {
                showPosterCover = false
            }
            guard isActive || liveGate.isActive else {
                softSeekToBeginning(playAfter: false)
                return
            }
            handleActivationOrMount(forceRebuild: false)
        }
        .onChange(of: muted) { _, newValue in
            guard !sharesFeedMute else { return }
            isMuted = newValue
            liveGate.isMuted = newValue
            player?.isMuted = newValue
        }
        .onChange(of: appState.feedVideosMuted) { _, globalMuted in
            guard sharesFeedMute else { return }
            isMuted = globalMuted
            liveGate.isMuted = globalMuted
            player?.isMuted = globalMuted
        }
        .onChange(of: userWantsPause) { _, paused in
            liveGate.userWantsPause = paused
        }
        .onChange(of: isMuted) { _, mutedNow in
            liveGate.isMuted = mutedNow
        }
        .onChange(of: adFinished) { _, finished in
            if finished {
                Task { await ensurePlayer(forceRebuild: true) }
            }
        }
        .onChange(of: url) { _, _ in
            // Drop the old surface immediately — never paint one Spark’s frame on another.
            showPosterCover = true
            isRestartSeeking = false
            teardownPlayer(park: false)
            Task { await ensurePlayer(forceRebuild: true) }
        }
        .onChange(of: postID) { _, _ in
            showPosterCover = true
            isRestartSeeking = false
            teardownPlayer(park: false)
            Task { await ensurePlayer(forceRebuild: true) }
        }
        .onChange(of: seekToSeconds) { _, target in
            guard let target else { return }
            seek(to: target)
            currentSeconds = target
            if isActive, !userWantsPause {
                player?.play()
                player?.safePlayImmediately(atRate: 1.0)
                isPlaying = true
            }
            onSeekConsumed?()
        }
        .onDisappear {
            teardownPlayer()
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            MatteryaFullscreenPlayer(
                url: url,
                posterURL: posterURL,
                startTime: currentSeconds,
                initialMuted: isMuted,
                onViewed: onViewed
            )
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.slash")
                .font(.title2)
                .foregroundStyle(Theme.accentBright.opacity(0.85))
            Text("Video unavailable")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Button("Try again") {
                loadFailed = false
                didRetryWithPublicURL = false
                playbackRecoveryPasses = 0
                Task { await ensurePlayer(forceRebuild: true) }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.accentBright)
        }
    }

    private func openFullscreen() {
        player?.pause()
        isPlaying = false
        showFullscreen = true
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            userWantsPause = true
            liveGate.userWantsPause = true
            player.pause()
            isPlaying = false
        } else {
            // Resume: inactive path force-mutes — restore user mute state or audio is gone.
            userWantsPause = false
            liveGate.userWantsPause = false
            kickAudiblePlayback(on: player)
        }
        scheduleChromeHide()
    }

    /// Solo + play only when this card is the live focused Spark / feed winner.
    @MainActor
    private func kickAudiblePlayback(on player: AVPlayer) {
        // liveGate is authoritative (View `isActive` can be stale in async end-of-clip
        // callbacks — that blocked Sparks from looping after they finished).
        guard liveGate.isActive, !liveGate.userWantsPause else {
            player.pause()
            player.isMuted = true
            player.volume = 0
            player.rate = 0
            isPlaying = false
            return
        }
        // Re-sync epoch so feed Sparks keep looping after a prior full-screen Sparks session.
        liveGate.pageEpoch = MediaPlaybackCoordinator.shared.sparkPageEpoch
        let epoch = liveGate.pageEpoch
        guard MediaPlaybackCoordinator.shared.soloSparkAudio(keeping: player, pageEpoch: epoch) else {
            isPlaying = false
            return
        }
        guard MediaPlaybackCoordinator.shared.allowPlaybackIfSolo(player, pageEpoch: epoch) else {
            isPlaying = false
            return
        }
        player.isMuted = liveGate.isMuted
        player.volume = liveGate.isMuted ? 0 : 1
        // Ensure end-of-item still notifies so loop restarts (pool may have set .pause).
        if loops {
            player.actionAtItemEnd = .none
        }
        player.play()
        player.safePlayImmediately(atRate: 1.0)
        isPlaying = true
        isRestartSeeking = false
        reportViewIfNeeded()
        // Warm / ready: drop poster *now* — no poll delay (that felt like a refresh).
        let itemReady = player.currentItem?.status == .readyToPlay
        let alreadyHasRate = player.rate > 0.01
            || player.timeControlStatus == .playing
            || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if itemReady || alreadyHasRate {
            showPosterCover = false
        } else {
            revealPlayerWhenFramesReady(player)
        }
    }

    /// Drop poster cover only after AVPlayer is producing frames (cold path only).
    @MainActor
    private func revealPlayerWhenFramesReady(_ player: AVPlayer) {
        Task { @MainActor in
            for _ in 0..<16 {
                try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame @60fps
                guard liveGate.isActive, !liveGate.userWantsPause else { return }
                let rateOK = player.rate > 0.01
                let statusOK = player.timeControlStatus == .playing
                    || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                let itemOK = player.currentItem?.status == .readyToPlay
                if rateOK || (statusOK && itemOK) {
                    isRestartSeeking = false
                    showPosterCover = false
                    return
                }
            }
            // Fallback: reveal anyway so we never stick on poster forever.
            if liveGate.isActive {
                isRestartSeeking = false
                showPosterCover = false
            }
        }
    }

    /// Restart from 0 for looping Sparks (full player + feed shares).
    /// Always seek to beginning and play again when the clip finishes.
    @MainActor
    private func restartLoop(on player: AVPlayer) {
        guard loops else { return }
        guard liveGate.isActive, !liveGate.userWantsPause else { return }
        // Debounce dual end signals (notification + near-end time observer).
        let now = Date()
        if isLoopRestarting || now.timeIntervalSince(lastLoopRestartAt) < 0.35 {
            return
        }
        isLoopRestarting = true
        lastLoopRestartAt = now
        currentSeconds = 0
        liveGate.onProgress?(0, durationSeconds)
        player.pause()
        player.rate = 0
        player.actionAtItemEnd = .none
        Task { @MainActor in
            defer { self.isLoopRestarting = false }
            // Exact start — Sparks must never resume mid-clip after a loop.
            _ = await player.seek(
                to: .zero,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            guard self.player === player else { return }
            guard self.liveGate.isActive, !self.liveGate.userWantsPause, self.loops else { return }
            self.currentSeconds = 0
            self.showPosterCover = false
            self.kickAudiblePlayback(on: player)
            // If solo gate flaked, force one more play attempt at t=0.
            if player.rate < 0.01, self.liveGate.isActive, !self.liveGate.userWantsPause {
                player.isMuted = self.liveGate.isMuted
                player.volume = self.liveGate.isMuted ? 0 : 1
                player.play()
                player.safePlayImmediately(atRate: 1.0)
                self.isPlaying = true
            }
        }
    }

    /// Activate / mount: Sparks page-focus restarts from 0 once per token; unpause resumes mid-clip.
    @MainActor
    private func handleActivationOrMount(forceRebuild: Bool) {
        let needsRestart = restartFromBeginningToken > 0
            && restartFromBeginningToken != lastHandledRestartToken
        if needsRestart {
            lastHandledRestartToken = restartFromBeginningToken
            restartPlaybackFromBeginning()
            return
        }
        resumeOrEnsurePlayer(forceRebuild: forceRebuild)
    }

    /// Prefer sync resume when a buffered player already exists; async only for cold start.
    @MainActor
    private func resumeOrEnsurePlayer(forceRebuild: Bool) {
        if !forceRebuild, let player, player.currentItem != nil {
            if liveGate.isActive, !liveGate.userWantsPause {
                kickAudiblePlayback(on: player)
                if player.status != .readyToPlay || player.currentItem?.status != .readyToPlay {
                    Task { await ensurePlayer(forceRebuild: false) }
                }
                return
            }
            if preloadsWhenInactive || liveGate.isActive {
                player.pause()
                player.isMuted = true
                player.volume = 0
                isPlaying = false
                return
            }
        }
        Task { await ensurePlayer(forceRebuild: forceRebuild || player?.currentItem == nil) }
    }

    /// Soft seek to start. When already at t≈0, play immediately — never free-play then snap.
    @MainActor
    private func softSeekToBeginning(playAfter: Bool) {
        currentSeconds = 0
        lastNotedPlaybackSecond = -1
        guard let player, player.currentItem != nil else {
            isRestartSeeking = false
            return
        }
        // Warm pool parks at exact 0 — only treat true start as ready (not <1.5s mid-clip).
        if SparkWarmPool.isAtStart(player) {
            isRestartSeeking = false
            showPosterCover = false
            if playAfter, liveGate.isActive, !liveGate.userWantsPause {
                kickAudiblePlayback(on: player)
            }
            return
        }
        // Mid-clip → exact 0, then play. Zero tolerance so we don't land on a late keyframe.
        isRestartSeeking = false
        showPosterCover = false
        player.pause()
        player.rate = 0
        Task { @MainActor in
            guard self.player === player else { return }
            _ = await player.seek(
                to: .zero,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            guard self.player === player else { return }
            self.currentSeconds = 0
            self.isRestartSeeking = false
            self.showPosterCover = false
            if playAfter, self.liveGate.isActive, !self.liveGate.userWantsPause {
                self.kickAudiblePlayback(on: player)
            }
        }
    }

    /// Sparks page focus: play from t=0 without a black flash when already parked at start.
    @MainActor
    private func restartPlaybackFromBeginning() {
        if let player, player.currentItem != nil {
            softSeekToBeginning(playAfter: true)
            return
        }
        // Cold path — ensure player (installClaimed also soft-seeks to 0).
        Task {
            await ensurePlayer(forceRebuild: player?.currentItem == nil)
            await MainActor.run {
                self.softSeekToBeginning(playAfter: true)
            }
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        player?.volume = isMuted ? 0 : 1
        if sharesFeedMute {
            appState.feedVideosMuted = isMuted
        }
        scheduleChromeHide()
    }

    private func seek(to seconds: Double) {
        guard let player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
        currentSeconds = seconds
        lastNotedPlaybackSecond = -1
        trackPlaybackPositionIfNeeded()
        scheduleChromeHide()
    }

    private func scheduleChromeHide() {
        guard showsControls else { return }
        chromeTask?.cancel()
        chromeTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showChrome = false
                }
            }
        }
    }

    @MainActor
    private func ensurePlayer(forceRebuild: Bool = false) async {
        // Always preload when we have a post id (feed Sparks / hubs shares / reels pager).
        let shouldPreload = preloadsWhenInactive || liveGate.isActive
        // Inactive + no preload → hard silence and bail.
        if !isActive, !shouldPreload {
            player?.pause()
            player?.isMuted = true
            player?.volume = 0
            isPlaying = false
            return
        }
        // Ads only when actively playing the slot.
        if isActive {
            guard adFinished || !shouldShowAd else { return }
        }

        // stopAllPlayback() can nil out currentItem while the view stays mounted (persistent feed).
        let itemMissing = player != nil && player?.currentItem == nil
        if forceRebuild || configuredURL != url || itemMissing {
            // Don't park a broken/wrong URL player — rebuild cold.
            teardownPlayer(park: false)
            configuredURL = url
            didRetryWithPublicURL = false
            playbackRecoveryPasses = 0
            userWantsPause = false
        }

        if player == nil {
            loadFailed = false
            // Instagram-speed: claim warm-pool by postID when the item is still healthy.
            var installedClaim = false
            if let postID, let claimed = SparkWarmPool.shared.claim(postID: postID) {
                installClaimedPlayer(claimed)
                installedClaim = true
            }
            if !installedClaim {
                if let postID { SparkWarmPool.shared.markInUse(postID: postID) }
                // Play direct when URL is still valid. API re-sign only if near/past expiry.
                let configuration = await MediaURLResolver.playbackConfiguration(
                    for: url,
                    postID: postID
                )
                // After await: user may have swiped away — never install audible on a dead page.
                guard liveGate.isActive || preloadsWhenInactive else {
                    if let postID { SparkWarmPool.shared.release(postID: postID) }
                    return
                }
                if configuration.url != url {
                    configuredURL = configuration.url
                }
                installPlayer(using: configuration)
            }
        }

        // Preload / inactive: hard silence (also after slow resolve returns).
        if !isActive || !liveGate.isActive {
            player?.pause()
            player?.isMuted = true
            player?.volume = 0
            player?.rate = 0
            isPlaying = false
            return
        }

        // Solo this player — kill every other Spark / feed / warm-pool voice.
        if let player {
            if liveGate.isActive, !liveGate.userWantsPause, isActive {
                kickAudiblePlayback(on: player)
            } else {
                player.pause()
                player.isMuted = true
                player.volume = 0
                player.rate = 0
                isPlaying = false
            }
        }
    }

    @MainActor
    private func installClaimedPlayer(_ claimed: AVPlayer) {
        // Warm pool kept it muted/paused at t≈0. Never free-play then seek — that was the
        // “wrong position → adjust → play” glitch on every Spark.
        claimed.pause()
        claimed.rate = 0
        claimed.automaticallyWaitsToMinimizeStalling = false
        claimed.actionAtItemEnd = loops ? .none : .pause
        MediaPlaybackCoordinator.shared.register(claimed)

        let gate = liveGate
        let needsExactStart = restartFromBeginningToken > 0 || loops
        let alreadyAtStart = SparkWarmPool.isAtStart(claimed)

        if liveGate.isActive {
            _ = MediaPlaybackCoordinator.shared.soloSparkAudio(
                keeping: claimed,
                pageEpoch: liveGate.pageEpoch
            )
            // Stay muted until playhead is confirmed at 0.
            claimed.isMuted = true
            claimed.volume = 0
        } else {
            claimed.pause()
            claimed.isMuted = true
            claimed.volume = 0
        }

        if let item = claimed.currentItem {
            item.preferredForwardBufferDuration = 8
            statusObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
                Task { @MainActor in
                    switch item.status {
                    case .readyToPlay:
                        loadFailed = false
                        updateDuration(from: item)
                        reportVideoSizeIfNeeded(from: item)
                    case .failed:
                        // Dump dead warm item and cold-start with a fresh resolve.
                        teardownPlayer(park: false)
                        loadFailed = false
                        didRetryWithPublicURL = false
                        playbackRecoveryPasses = 0
                        Task { await ensurePlayer(forceRebuild: true) }
                    default:
                        break
                    }
                }
            }
            attachLoopObserver(for: item, player: claimed, gate: gate)
        }
        attachTimeObserver(to: claimed)
        player = claimed
        reportVideoSizeIfNeeded(from: claimed.currentItem)
        currentSeconds = 0
        // Claimed warm players must still loop when the Spark finishes.
        claimed.actionAtItemEnd = loops ? .none : .pause

        // If already at t≈0 (warm pool contract), play immediately — no seek, no jump.
        if alreadyAtStart || !needsExactStart {
            showPosterCover = false
            if liveGate.isActive, !liveGate.userWantsPause {
                kickAudiblePlayback(on: claimed)
            }
            return
        }

        // Rare: claim mid-fill. Seek to exact 0 *before* unmuting / play so first paint is start.
        Task { @MainActor in
            guard self.player === claimed else { return }
            _ = await claimed.seek(
                to: .zero,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            guard self.player === claimed else { return }
            claimed.pause()
            claimed.rate = 0
            self.currentSeconds = 0
            self.showPosterCover = false
            if self.liveGate.isActive, !self.liveGate.userWantsPause {
                self.kickAudiblePlayback(on: claimed)
            } else {
                claimed.isMuted = true
                claimed.volume = 0
            }
        }
    }

    private func reportVideoSizeIfNeeded(from item: AVPlayerItem?) {
        guard let item else { return }
        let size = item.presentationSize
        if size.width > 2, size.height > 2 {
            didReportVideoSize = true
            onVideoSize?(size)
        }
        if presentationSizeObserver == nil {
            presentationSizeObserver = item.observe(\.presentationSize, options: [.new, .initial]) { item, _ in
                let s = item.presentationSize
                guard s.width > 2, s.height > 2 else { return }
                Task { @MainActor in
                    self.didReportVideoSize = true
                    self.onVideoSize?(s)
                }
            }
        }
    }

    @MainActor
    private func installPlayer(using configuration: MediaPlaybackConfiguration) {
        let item = makePlayerItem(for: configuration)
        // Deep forward buffer so scroll-back / next-page feel instant.
        item.preferredForwardBufferDuration = (liveGate.isActive || preloadsWhenInactive) ? 6 : 3
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = liveGate.isActive ? liveGate.isMuted : true
        newPlayer.volume = (liveGate.isActive && !liveGate.isMuted) ? 1 : 0
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.actionAtItemEnd = loops ? .none : .pause

        let gate = liveGate
        statusObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    loadFailed = false
                    updateDuration(from: item)
                    reportVideoSizeIfNeeded(from: item)
                    let resumeAt = resolvedStartTime()
                    if resumeAt > 0.5 {
                        // Hubs resume only — Sparks always 0 (never start mid then snap).
                        await newPlayer.seek(
                            to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        currentSeconds = resumeAt
                    } else if restartFromBeginningToken > 0 || loops {
                        // Cold Spark path: lock exact start before first play.
                        await newPlayer.seek(
                            to: .zero,
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        currentSeconds = 0
                    }
                    if gate.isActive, !gate.userWantsPause {
                        kickAudiblePlayback(on: newPlayer)
                    } else {
                        // Preload path: stay paused at start (never free-play to buffer).
                        newPlayer.pause()
                        newPlayer.rate = 0
                        newPlayer.isMuted = true
                        newPlayer.volume = 0
                        isPlaying = false
                        showPosterCover = false
                    }
                case .failed:
                    await handlePlaybackFailure(for: configuration.url)
                default:
                    break
                }
            }
        }

        attachTimeObserver(to: newPlayer)

        attachLoopObserver(for: item, player: newPlayer, gate: gate)

        player = newPlayer
        MediaPlaybackCoordinator.shared.register(newPlayer)
        if liveGate.isActive, !liveGate.userWantsPause {
            kickAudiblePlayback(on: newPlayer)
        } else {
            // Inactive preload: stay silent but keep the item warming.
            newPlayer.pause()
            newPlayer.isMuted = true
            newPlayer.volume = 0
            isPlaying = false
        }
    }

    /// Observe end-of-item and restart from t=0 while this Spark is focused.
    @MainActor
    private func attachLoopObserver(for item: AVPlayerItem, player: AVPlayer, gate: VideoPlayerLiveGate) {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        guard loops else { return }
        player.actionAtItemEnd = .none
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard gate.isActive, !gate.userWantsPause else { return }
                self.restartLoop(on: player)
            }
        }
    }

    @MainActor
    private func attachTimeObserver(to player: AVPlayer) {
        removeTimeObserver()
        // Keep liveGate.onProgress current so preloaded Sparks still tick the timeline.
        liveGate.onProgress = onProgress
        // ~10 Hz — smooth enough for Sparks timeline without burning main-thread budget.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        let gate = liveGate
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                let seconds = time.seconds
                let cur = seconds.isFinite ? max(0, seconds) : 0
                currentSeconds = cur
                if let item = player.currentItem {
                    updateDuration(from: item)
                }
                isPlaying = player.rate > 0.01
                trackPlaybackPositionIfNeeded()
                // Always publish — parent decides whether to paint the rail.
                // Prefer liveGate so we never call a stale View-struct capture.
                gate.onProgress?(cur, durationSeconds)

                // Fallback loop: some R2/HLS items never fire DidPlayToEndTime.
                // When the playhead sits at/near the end, restart from 0.
                if self.loops,
                   gate.isActive,
                   !gate.userWantsPause,
                   !self.isLoopRestarting,
                   self.durationSeconds > 0.4 {
                    let atEnd = cur >= self.durationSeconds - 0.08
                    let stalledAtEnd = atEnd && player.rate < 0.01
                    if stalledAtEnd || cur >= self.durationSeconds - 0.02 {
                        self.restartLoop(on: player)
                    }
                }
            }
        }
        timeObserverPlayer = player
    }

    @MainActor
    private func removeTimeObserver() {
        if let timeObserver, let timeObserverPlayer {
            timeObserverPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeObserverPlayer = nil
    }

    @MainActor
    private func updateDuration(from item: AVPlayerItem) {
        let seconds = item.duration.seconds
        if seconds.isFinite, seconds > 0 {
            durationSeconds = seconds
        }
    }

    @MainActor
    private func handlePlaybackFailure(for failedURL: URL) async {
        // Drop any dead warm-pool slot so a later claim/cold start can rebuild cleanly.
        if let postID {
            SparkWarmPool.shared.release(postID: postID)
        }
        playbackRecoveryPasses += 1
        removeTimeObserver()
        teardownPlayerObservers()
        player = nil
        loadFailed = false

        // Pass 1: invalidate cache + force API playbackMedia (permanent object, new link).
        if playbackRecoveryPasses == 1 {
            didRetryWithPublicURL = true
            if let postID {
                await R2PlaybackResolver.shared.invalidate(postID: postID)
                if let live = await R2PlaybackResolver.shared.playURL(postID: postID, fallback: nil) {
                    configuredURL = live
                    installPlayer(using: MediaPlaybackConfiguration(url: live, headers: nil))
                    return
                }
            }
            // 1b) Full resolve of the card’s original URL (Archive / Supabase).
            let primary = await MediaURLResolver.playbackConfiguration(for: url, postID: postID)
            if primary.url != failedURL || primary.headers != nil {
                installPlayer(using: primary)
                return
            }
            // 2) Re-resolve the failed hop (Archive CDN / auth).
            let config = await MediaURLResolver.playbackConfiguration(for: failedURL, postID: postID)
            if config.url != failedURL || config.headers != nil {
                installPlayer(using: config)
                return
            }
            // 3) Supabase public bucket flip.
            if let fallback = MediaURLResolver.playbackFallbackConfiguration(for: failedURL)
                ?? MediaURLResolver.playbackFallbackConfiguration(for: url) {
                installPlayer(using: fallback)
                return
            }
            // 4) Plain original URL once more (transient CDN flake).
            installPlayer(using: MediaPlaybackConfiguration(url: url, headers: nil))
            return
        }

        // Pass 2: brief pause + hard re-resolve (network flake).
        if playbackRecoveryPasses == 2 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard liveGate.isActive || preloadsWhenInactive else {
                loadFailed = true
                return
            }
            if let postID {
                await R2PlaybackResolver.shared.invalidate(postID: postID)
                if let live = await R2PlaybackResolver.shared.playURL(postID: postID, fallback: url) {
                    configuredURL = live
                    installPlayer(using: MediaPlaybackConfiguration(url: live, headers: nil))
                    return
                }
            }
            let lastChance = await MediaURLResolver.playbackConfiguration(for: url, postID: postID)
            installPlayer(using: lastChance)
            return
        }

        // Terminal — show unavailable (user can swipe; Retry button still works).
        loadFailed = true
        player = nil
    }

    private func makePlayerItem(for configuration: MediaPlaybackConfiguration) -> AVPlayerItem {
        // Never attach HTTP headers for Archive URLs — AVPlayer + Archive CDN + headers sticks on the poster.
        if let headers = configuration.headers, !headers.isEmpty,
           !ArchiveVideoPlayback.isArchiveURL(configuration.url) {
            let asset = AVURLAsset(
                url: configuration.url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
            return AVPlayerItem(asset: asset)
        }
        if ArchiveVideoPlayback.isArchiveURL(configuration.url) {
            let asset = AVURLAsset(
                url: configuration.url,
                options: [
                    AVURLAssetAllowsCellularAccessKey: true,
                    AVURLAssetAllowsExpensiveNetworkAccessKey: true,
                    AVURLAssetAllowsConstrainedNetworkAccessKey: true,
                ]
            )
            return AVPlayerItem(asset: asset)
        }
        return AVPlayerItem(url: configuration.url)
    }

    private func resolvedStartTime() -> Double {
        // Sparks player always opens / re-focuses at 0 — ignore Hubs resume points.
        if restartFromBeginningToken > 0 {
            return 0
        }
        if let startTime, startTime > 0 {
            return startTime
        }
        guard let postID else { return 0 }
        return YouTubeCatalogService.shared.playbackPosition(for: postID)
    }

    private func trackPlaybackPositionIfNeeded() {
        guard let postID, currentSeconds >= 0.5 else { return }
        let wholeSecond = Int(currentSeconds.rounded(.down))
        guard wholeSecond != lastNotedPlaybackSecond else { return }
        lastNotedPlaybackSecond = wholeSecond
        YouTubeCatalogService.shared.notePlaybackPosition(
            currentSeconds,
            for: postID,
            duration: durationSeconds > 0 ? durationSeconds : nil
        )
    }

    private func persistPlaybackPosition() {
        guard let postID else { return }
        guard persistsPositionOnTeardown else { return }
        YouTubeCatalogService.shared.savePlaybackPosition(
            currentSeconds,
            for: postID,
            duration: durationSeconds > 0 ? durationSeconds : nil
        )
    }

    private func teardownPlayer(park: Bool = true) {
        persistPlaybackPosition()
        removeTimeObserver()
        teardownPlayerObservers()
        presentationSizeObserver?.invalidate()
        presentationSizeObserver = nil
        didReportVideoSize = false
        if let player {
            player.pause()
            player.isMuted = true
            player.volume = 0
            if park, let postID, player.currentItem != nil, player.status != .failed {
                // Keep the buffered item for instant re-entry when the user scrolls back.
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
        player = nil
        configuredURL = nil
        didRetryWithPublicURL = false
        playbackRecoveryPasses = 0
        loadFailed = false
        isPlaying = false
        chromeTask?.cancel()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // Do not mixWithOthers — Sparks/DB video audio must stop when leaving the screen.
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }

    private func teardownPlayerObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
    }

    private func reportViewIfNeeded() {
        guard isActive, !didReportView else { return }
        didReportView = true
        onViewed?()
    }
}

// MARK: - Live gate (observer-safe)

/// Reference type so KVO / NotificationCenter closures always read the *current* active/mute state.
@MainActor
private final class VideoPlayerLiveGate {
    var isActive = false
    var userWantsPause = false
    var isMuted = false
    /// Snapshot of `MediaPlaybackCoordinator.sparkPageEpoch` when this card last became active.
    var pageEpoch: UInt64 = 0
    /// Latest progress handler — time observers must not capture a stale View struct closure.
    var onProgress: ((Double, Double) -> Void)?
}

// MARK: - Fullscreen

private struct MatteryaFullscreenPlayer: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let posterURL: URL?
    let startTime: Double
    let initialMuted: Bool
    var onViewed: (() -> Void)?

    @State private var player: AVPlayer?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var timeObserver: Any?
    @State private var timeObserverPlayer: AVPlayer?
    @State private var loadFailed = false
    @State private var isPlaying = true
    @State private var isMuted = false
    @State private var currentSeconds: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var showChrome = true
    @State private var chromeTask: Task<Void, Never>?
    @State private var didReportView = false
    @State private var dismissDragOffset: CGFloat = 0
    @State private var isPullingToDismiss = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if let player {
                    MatteryaVideoSurface(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showChrome.toggle()
                            }
                            scheduleChromeHide()
                        }
                } else if loadFailed {
                    Text("Video unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                } else if let posterURL {
                    CachedAsyncImage(
                        url: posterURL,
                        maxPixelSize: 900,
                        contentMode: .fit,
                        placeholder: AnyView(ProgressView().tint(Theme.accentBright))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().tint(Theme.accentBright)
                }

                if showChrome, player != nil {
                    MatteryaVideoControls(
                        isPlaying: isPlaying,
                        isMuted: isMuted,
                        currentSeconds: currentSeconds,
                        durationSeconds: durationSeconds,
                        showsFullscreen: false,
                        isFullscreen: true,
                        onPlayPause: { togglePlayback() },
                        onMuteToggle: { toggleMute() },
                        onSeek: { seek(to: $0) },
                        onFullscreen: nil,
                        onExitFullscreen: { dismiss() }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(!isPullingToDismiss)
                }
            }
            .matteryaPullDownDismissTransform(offset: dismissDragOffset)
            .matteryaPullDownToDismiss(
                offset: $dismissDragOffset,
                isDragging: $isPullingToDismiss,
                onDismiss: { dismiss() }
            )
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            isMuted = initialMuted
            Task { await setupPlayer() }
            scheduleChromeHide()
        }
        .onDisappear {
            teardown()
        }
    }

    @MainActor
    private func setupPlayer() async {
        let configuration = await MediaURLResolver.playbackConfiguration(for: url)
        let item: AVPlayerItem
        if let headers = configuration.headers {
            let asset = AVURLAsset(
                url: configuration.url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
            item = AVPlayerItem(asset: asset)
        } else {
            item = AVPlayerItem(url: configuration.url)
        }

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = isMuted
        newPlayer.automaticallyWaitsToMinimizeStalling = false

        statusObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    loadFailed = false
                    updateDuration(from: item)
                    if startTime > 0 {
                        newPlayer.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                    }
                    newPlayer.play()
                    isPlaying = true
                    if !didReportView {
                        didReportView = true
                        onViewed?()
                    }
                case .failed:
                    loadFailed = true
                default:
                    break
                }
            }
        }

        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                currentSeconds = max(0, time.seconds)
                if let current = newPlayer.currentItem {
                    updateDuration(from: current)
                }
                isPlaying = newPlayer.rate > 0.01
            }
        }
        timeObserverPlayer = newPlayer

        player = newPlayer
        currentSeconds = startTime
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        scheduleChromeHide()
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        scheduleChromeHide()
    }

    private func seek(to seconds: Double) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentSeconds = seconds
        scheduleChromeHide()
    }

    // Note: fullscreen player keeps local mute only (not feed-wide).

    private func scheduleChromeHide() {
        chromeTask?.cancel()
        chromeTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showChrome = false
                }
            }
        }
    }

    @MainActor
    private func updateDuration(from item: AVPlayerItem) {
        let seconds = item.duration.seconds
        if seconds.isFinite, seconds > 0 {
            durationSeconds = seconds
        }
    }

    @MainActor
    private func removeTimeObserver() {
        if let timeObserver, let timeObserverPlayer {
            timeObserverPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeObserverPlayer = nil
    }

    @MainActor
    private func teardown() {
        removeTimeObserver()
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
        player = nil
        chromeTask?.cancel()
    }
}

// MARK: - Shared UI

private struct MatteryaVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var fillsFrame: Bool = true

    func makeUIView(context: Context) -> MatteryaPlayerUIView {
        let view = MatteryaPlayerUIView()
        // Gravity BEFORE player attach — first decoded frame already correct.
        view.lockGravity(fillsFrame: fillsFrame)
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: MatteryaPlayerUIView, context: Context) {
        uiView.lockGravity(fillsFrame: fillsFrame)
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class MatteryaPlayerUIView: UIView {
    /// AVPlayerLayer **is** the view's layer — never set `playerLayer.frame`.
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var lockedGravity: AVLayerVideoGravity = .resizeAspectFill
    private var gravityLocked = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        // Default fill (FB/IG feed + Sparks); host may switch to fit for wide clips.
        playerLayer.videoGravity = .resizeAspectFill
        lockedGravity = .resizeAspectFill
        isUserInteractionEnabled = false
        clipsToBounds = true
        playerLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "contents": NSNull(),
            "videoGravity": NSNull(),
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Apply gravity without CA zoom. Allows one fill↔fit switch when Sparks learns size.
    func lockGravity(fillsFrame: Bool) {
        let gravity: AVLayerVideoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        if lockedGravity == gravity, playerLayer.videoGravity == gravity {
            return
        }
        lockedGravity = gravity
        gravityLocked = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.videoGravity = gravity
        playerLayer.backgroundColor = UIColor.black.cgColor
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if playerLayer.videoGravity != lockedGravity {
            playerLayer.videoGravity = lockedGravity
        }
        CATransaction.commit()
    }
}

/// Shared transport chrome: center −10s · play · +10s, scrubber bottom (matches Hubs player).
private struct MatteryaVideoControls: View {
    let isPlaying: Bool
    let isMuted: Bool
    let currentSeconds: Double
    let durationSeconds: Double
    let showsFullscreen: Bool
    let isFullscreen: Bool
    let onPlayPause: () -> Void
    let onMuteToggle: () -> Void
    let onSeek: (Double) -> Void
    let onFullscreen: (() -> Void)?
    let onExitFullscreen: (() -> Void)?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    if isFullscreen, let onExitFullscreen {
                        controlIconButton(systemName: "xmark", action: onExitFullscreen)
                    }
                    Spacer()
                    controlIconButton(
                        systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        action: onMuteToggle
                    )
                    if showsFullscreen, let onFullscreen {
                        controlIconButton(
                            systemName: "arrow.up.left.and.arrow.down.right",
                            action: onFullscreen
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, isFullscreen ? 0 : 10)
                .safeAreaPadding(.top, isFullscreen ? 6 : 0)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Text(formatTime(currentSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 42, alignment: .leading)

                    MatteryaScrubber(
                        value: scrubberValue,
                        onEditingChanged: { editing in
                            if !editing, durationSeconds > 0 {
                                onSeek(currentSeconds)
                            }
                        },
                        onValueChanged: { newValue in
                            if durationSeconds > 0 {
                                onSeek(newValue * durationSeconds)
                            }
                        }
                    )

                    Text(formatTime(durationSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 42, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, isFullscreen ? 0 : 14)
                .padding(.top, 12)
                .safeAreaPadding(.bottom, isFullscreen ? 10 : 0)
                .background(
                    LinearGradient(
                        colors: [.clear, Theme.ink.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Dead-center transport (Hubs-style).
            HStack(spacing: 40) {
                controlIconButton(systemName: "gobackward.10", size: 46) {
                    onSeek(max(0, currentSeconds - 10))
                }
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.paper)
                        .frame(width: 68, height: 68)
                        .background(Theme.accentBright, in: Circle())
                        .shadow(color: Theme.ink.opacity(0.34), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                controlIconButton(systemName: "goforward.10", size: 46) {
                    let next = durationSeconds > 0
                        ? min(durationSeconds, currentSeconds + 10)
                        : currentSeconds + 10
                    onSeek(next)
                }
            }
        }
    }

    private var scrubberValue: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, max(0, currentSeconds / durationSeconds))
    }

    private func controlIconButton(
        systemName: String,
        size: CGFloat = 34,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size > 36 ? 18 : 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.ink.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        // Long Hubs videos: 1:01:00 not 61:00
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct MatteryaScrubber: View {
    let value: Double
    let onEditingChanged: (Bool) -> Void
    let onEditingChangedValue: ((Double) -> Void)?
    let onValueChanged: (Double) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    init(
        value: Double,
        onEditingChanged: @escaping (Bool) -> Void,
        onValueChanged: @escaping (Double) -> Void
    ) {
        self.value = value
        self.onEditingChanged = onEditingChanged
        self.onEditingChangedValue = nil
        self.onValueChanged = onValueChanged
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fill = (isDragging ? dragValue : value) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 4)

                Capsule()
                    .fill(Theme.accentBright)
                    .frame(width: fill, height: 4)

                Circle()
                    .fill(Theme.paper)
                    .frame(width: 14, height: 14)
                    .shadow(color: Theme.ink.opacity(0.25), radius: 3, y: 1)
                    .offset(x: max(0, fill - 7))
            }
            .frame(height: 20)
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
        .frame(height: 20)
        .onChange(of: value) { _, newValue in
            if !isDragging {
                dragValue = newValue
            }
        }
        .onAppear {
            dragValue = value
        }
    }
}

/// Plays video when it wins feed focus (highest on-screen ratio). Only one plays at a time.
/// In-feed chrome: scrub, pause, mute — does not navigate away.
struct InFrameVideoPlayer: View {
    @Environment(AppState.self) private var appState

    let url: URL
    let posterURL: URL?
    var placement: String? = nil
    var countryCode: String? = nil
    var contentCountryCode: String? = nil
    var postID: String? = nil
    /// Default unmuted so feed videos have sound.
    var muted: Bool = false
    var loops: Bool = true
    var preferArchivePlayer: Bool = false
    /// Full transport chrome (play/pause + scrubber + mute) while this slot is active.
    var showsControls: Bool = true
    /// When true, only a mute chip is shown (Sparks feed) — no scrubber / play-pause.
    var muteOnlyControls: Bool = false
    /// Full-bleed fill — never black bars on sides/top.
    var fillsFrame: Bool = true
    /// When true, mute chip drives app-wide feed mute (all feed videos stay in sync).
    var sharesFeedMute: Bool = true
    /// Home feed vs profile — prevents opacity-0 feed cards from stealing profile autoplay.
    var autoplaySurface: FeedAutoplaySurface = .home
    var onViewed: (() -> Void)? = nil

    @State private var isMuted: Bool
    @State private var isFocusWinner = false
    /// Debounced play gate — brief focus blips must not hard-pause mid-clip.
    @State private var playGate = false
    @State private var deactivateTask: Task<Void, Never>?
    @State private var lastReportedRatio: CGFloat = -1

    init(
        url: URL,
        posterURL: URL?,
        placement: String? = nil,
        countryCode: String? = nil,
        contentCountryCode: String? = nil,
        postID: String? = nil,
        muted: Bool = false,
        loops: Bool = true,
        preferArchivePlayer: Bool = false,
        showsControls: Bool = true,
        muteOnlyControls: Bool = false,
        fillsFrame: Bool = true,
        forceSilentUntilUnmute: Bool = false,
        sharesFeedMute: Bool = true,
        autoplaySurface: FeedAutoplaySurface = .home,
        onViewed: (() -> Void)? = nil
    ) {
        self.url = url
        self.posterURL = posterURL
        self.placement = placement
        self.countryCode = countryCode
        self.contentCountryCode = contentCountryCode
        self.postID = postID
        self.muted = muted
        self.loops = loops
        self.preferArchivePlayer = preferArchivePlayer
        self.showsControls = showsControls
        self.muteOnlyControls = muteOnlyControls
        self.fillsFrame = fillsFrame
        self.sharesFeedMute = sharesFeedMute
        self.autoplaySurface = autoplaySurface
        self.onViewed = onViewed
        // Initial mute: prefer global feed mute when sharing; else constructor flag.
        _isMuted = State(initialValue: muted || forceSilentUntilUnmute)
    }

    private var focusID: String {
        // Prefix so the same post on feed + profile don't collide in the focus map.
        "\(autoplaySurface.rawValue):\(postID ?? url.absoluteString)"
    }

    private var surfaceLive: Bool {
        autoplaySurface.isLive(appState: appState)
    }

    /// Winner of FeedVideoFocus + allowed surface.
    /// Mini or expanded Hubs continuous player → no feed/profile autoplay.
    private var shouldPlay: Bool {
        isFocusWinner
            && surfaceLive
            && appState.reelsViewerContext == nil
            && !(appState.hubPlaybackPost != nil && appState.hubPlaybackExpanded)
    }

    private var usesArchivePath: Bool {
        preferArchivePlayer || ArchiveVideoPlayback.isArchiveURL(url)
    }

    private var transportChrome: Bool {
        showsControls && !muteOnlyControls && playGate
    }

    var body: some View {
        ZStack {
            Group {
                if usesArchivePath {
                    // Keep player mounted so CDN resolve happens before focus wins.
                    // isActive uses debounced playGate so brief focus flaps don't pause mid-clip.
                    MatteryaHubPlayerView(
                        url: url,
                        posterURL: posterURL,
                        isActive: playGate,
                        startTime: 0,
                        postID: postID,
                        showsControls: transportChrome,
                        loops: loops,
                        fillsFrame: fillsFrame,
                        isMuted: Binding(
                            get: { isMuted },
                            set: { newValue in
                                isMuted = newValue
                                if sharesFeedMute {
                                    appState.feedVideosMuted = newValue
                                }
                            }
                        ),
                        allowsFullscreen: false,
                        onReady: { onViewed?() }
                    )
                } else {
                    VideoPlayerView(
                        url: url,
                        posterURL: posterURL,
                        placement: placement,
                        countryCode: countryCode,
                        contentCountryCode: contentCountryCode,
                        postID: postID,
                        adsEnabled: false,
                        isActive: playGate,
                        loops: loops,
                        muted: isMuted,
                        showsControls: transportChrome,
                        allowsFullscreen: false,
                        sharesFeedMute: sharesFeedMute,
                        fillsFrame: fillsFrame,
                        // Only the focus winner should build a heavy buffer — neighbors stay light.
                        preloadsWhenInactive: false,
                        onViewed: onViewed
                    )
                }
            }

            // Cover black AV layer until this card actually wins focus + plays.
            if !playGate {
                if let posterURL {
                    CachedAsyncImage(
                        url: posterURL,
                        maxPixelSize: 480,
                        contentMode: .fill,
                        placeholder: AnyView(Theme.ink)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                } else {
                    Theme.ink.allowsHitTesting(false)
                }
            }

            if muteOnlyControls {
                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            let next = !isMuted
                            isMuted = next
                            if sharesFeedMute {
                                appState.feedVideosMuted = next
                            }
                            if !next {
                                activatePlaybackAudioIfNeeded(unmuted: true)
                            }
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Theme.ink.opacity(0.45), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                    }
                    .padding(10)
                    Spacer(minLength: 0)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .feedVideoFocusDidChange)) { _ in
            refreshFocusWinner()
        }
        .background(visibilityProbe)
        .onAppear {
            // Sync to global feed mute so every card matches.
            if sharesFeedMute {
                isMuted = appState.feedVideosMuted
            } else {
                isMuted = muted
            }
            // CDN resolve only — never warm AVPlayers for every feed/hubs cell (freezes scroll).
            if usesArchivePath {
                ArchiveVideoPlayback.warmResolve(url)
            }
            refreshFocusWinner()
            syncPlayGate(immediate: true)
            // Never auto-activate audible session while still muted.
            if playGate, !isMuted {
                activatePlaybackAudioIfNeeded(unmuted: true)
            }
        }
        .onChange(of: appState.feedVideosMuted) { _, globalMuted in
            guard sharesFeedMute else { return }
            isMuted = globalMuted
            if !globalMuted {
                activatePlaybackAudioIfNeeded(unmuted: true)
            }
        }
        .onChange(of: isMuted) { _, mutedNow in
            if !mutedNow {
                activatePlaybackAudioIfNeeded(unmuted: true)
            }
        }
        .onDisappear {
            deactivateTask?.cancel()
            deactivateTask = nil
            FeedVideoFocus.shared.clear(id: focusID)
            isFocusWinner = false
            playGate = false
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, postID in
            syncPlayGate(immediate: postID != nil)
            if shouldPlay, !isMuted {
                activatePlaybackAudioIfNeeded(unmuted: true)
            }
        }
        .onChange(of: appState.hubPlaybackExpanded) { _, _ in
            syncPlayGate(immediate: appState.hubPlaybackPost != nil)
            if shouldPlay, !isMuted {
                activatePlaybackAudioIfNeeded(unmuted: true)
            }
        }
        .onChange(of: appState.selectedTab) { _, _ in
            lastReportedRatio = -1
            syncPlayGate(immediate: true)
        }
        .onChange(of: appState.navigationPath.count) { _, _ in
            lastReportedRatio = -1
            syncPlayGate(immediate: true)
        }
        .onChange(of: appState.reelsViewerContext?.id) { _, ctx in
            if ctx == nil {
                lastReportedRatio = -1
                refreshFocusWinner()
                syncPlayGate(immediate: true)
                if shouldPlay, !isMuted {
                    activatePlaybackAudioIfNeeded(unmuted: true)
                }
            } else {
                syncPlayGate(immediate: true)
            }
        }
        .onChange(of: shouldPlay) { _, play in
            // Start immediately; delay pause so layout noise never kills a fully visible card.
            syncPlayGate(immediate: play)
            if play {
                if let postID {
                    SparkWarmPool.shared.warmSingle(postID: postID, url: url, deep: true)
                }
                if !isMuted {
                    activatePlaybackAudioIfNeeded(unmuted: true)
                }
            }
        }
        .onChange(of: playGate) { _, active in
            // Focus won — ensure warm pool is deep-ready so first frames aren't a frozen poster.
            guard active else { return }
            if let postID {
                SparkWarmPool.shared.warmSingle(postID: postID, url: url, deep: true)
                Task {
                    await SparkWarmPool.shared.awaitReady(postIDs: [postID], timeout: 0.5)
                }
            }
            if !isMuted {
                activatePlaybackAudioIfNeeded(unmuted: true)
            }
        }
    }

    private func refreshFocusWinner() {
        let win = surfaceLive && FeedVideoFocus.shared.isActive(id: focusID)
        if win != isFocusWinner {
            isFocusWinner = win
        }
        // Win → play now. Lose → soft pause (debounced) unless surface left.
        syncPlayGate(immediate: win)
    }

    /// Instant on for play; delayed off so GeometryReader glitches don't pause full-screen cards.
    private func syncPlayGate(immediate: Bool) {
        if shouldPlay {
            deactivateTask?.cancel()
            deactivateTask = nil
            playGate = true
            return
        }
        // Hard stop when leaving feed surface, opening Sparks, or any Hubs mini/expanded player.
        let leftAutoplaySurface =
            !surfaceLive
            || appState.reelsViewerContext != nil
            || (appState.hubPlaybackPost != nil && appState.hubPlaybackExpanded)
        if leftAutoplaySurface {
            deactivateTask?.cancel()
            deactivateTask = nil
            playGate = false
            return
        }
        // Focus lost (scrolled away / another winner) — hold briefly, then pause.
        // Never hard-cut on `immediate` alone; that was pausing 100%-visible videos on layout ticks.
        guard playGate else { return }
        if immediate {
            // Still debounce — "immediate" only means we schedule sooner, not kill this frame.
        }
        deactivateTask?.cancel()
        deactivateTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !shouldPlay {
                    playGate = false
                }
            }
        }
    }

    /// Reports on-screen fraction so only the most-visible video plays.
    private var visibilityProbe: some View {
        // Match parent bounds only — never let GeometryReader inflate the card off-screen.
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { reportVisibility(proxy.frame(in: .global)) }
                // One axis only — minY+midY+height was 3× FeedVideoFocus elections per layout.
                .onChange(of: frame.midY) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
                .onChange(of: appState.selectedTab) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func reportVisibility(_ frame: CGRect) {
        // Hidden feed (still mounted under Profile) must not steal the autoplay winner.
        guard surfaceLive else {
            if lastReportedRatio >= 0 {
                lastReportedRatio = -1
                FeedVideoFocus.shared.clear(id: focusID)
            }
            if isFocusWinner { isFocusWinner = false }
            syncPlayGate(immediate: true)
            return
        }

        let ratio = FeedVideoFocus.visibleRatio(for: frame)
        // Skip tiny noise; still re-check winner (pause only when >70% off-screen).
        if abs(ratio - lastReportedRatio) < 0.03, lastReportedRatio >= 0 {
            refreshFocusWinner()
            return
        }
        lastReportedRatio = ratio
        FeedVideoFocus.shared.report(id: focusID, visibleRatio: ratio)
        refreshFocusWinner()
    }

    private func activatePlaybackAudioIfNeeded(unmuted: Bool) {
        guard unmuted else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }
}