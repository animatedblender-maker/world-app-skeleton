import AVFoundation
import SwiftUI
import UIKit

struct VideoPlayerView: View {
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
    var onViewed: (() -> Void)? = nil

    @State private var adFinished = false
    @State private var player: AVPlayer?
    @State private var didReportView = false
    @State private var loopObserver: NSObjectProtocol?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var timeObserver: Any?
    @State private var timeObserverPlayer: AVPlayer?
    @State private var loadFailed = false
    @State private var didRetryWithPublicURL = false
    @State private var configuredURL: URL?
    @State private var showFullscreen = false
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var currentSeconds: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var showChrome = true
    @State private var chromeTask: Task<Void, Never>?
    @State private var lastNotedPlaybackSecond: Int = -1
    /// When the user pauses via chrome, do not auto-resume until they press play or leave the slot.
    @State private var userWantsPause = false

    private var shouldShowAd: Bool {
        adsEnabled && isActive && !adFinished && placement != nil
    }

    private var shouldShowChrome: Bool {
        showsControls && showChrome && player != nil && !shouldShowAd
    }

    var body: some View {
        ZStack {
            Color.black

            if shouldShowAd, let placement {
                AdPrerollView(
                    placement: placement,
                    countryCode: countryCode,
                    contentCountryCode: contentCountryCode,
                    postID: postID,
                    onComplete: { adFinished = true }
                )
            } else if let player {
                MatteryaVideoSurface(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            } else if let posterURL {
                CachedAsyncImage(
                    url: posterURL,
                    maxPixelSize: 600,
                    contentMode: .fit,
                    placeholder: AnyView(ProgressView().tint(Theme.accentBright))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().tint(Theme.accentBright)
            }
        }
        .clipped()
        .onAppear {
            isMuted = muted
            configureAudioSession()
            Task { await ensurePlayer(forceRebuild: player?.currentItem == nil) }
            if showsControls { scheduleChromeHide() }
        }
        .onChange(of: isActive) { _, active in
            if active {
                userWantsPause = false
                // Rebuild if coordinator soft/hard-stopped the item while we stayed mounted.
                Task { await ensurePlayer(forceRebuild: player?.currentItem == nil) }
            } else {
                persistPlaybackPosition()
                player?.pause()
                isPlaying = false
                userWantsPause = false
            }
        }
        .onChange(of: muted) { _, newValue in
            isMuted = newValue
            player?.isMuted = newValue
        }
        .onChange(of: adFinished) { _, finished in
            if finished {
                Task { await ensurePlayer(forceRebuild: true) }
            }
        }
        .onChange(of: url) { _, _ in
            Task { await ensurePlayer(forceRebuild: true) }
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
        VStack(spacing: 8) {
            Image(systemName: "play.slash")
                .font(.title2)
                .foregroundStyle(Theme.accentBright.opacity(0.85))
            Text("Video unavailable")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
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
            player.pause()
            isPlaying = false
        } else {
            userWantsPause = false
            player.play()
            player.playImmediately(atRate: 1.0)
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
        guard isActive else {
            player?.pause()
            isPlaying = false
            return
        }
        guard adFinished || !shouldShowAd else { return }

        // stopAllPlayback() can nil out currentItem while the view stays mounted (persistent feed).
        let itemMissing = player != nil && player?.currentItem == nil
        if forceRebuild || configuredURL != url || itemMissing {
            teardownPlayer()
            configuredURL = url
            didRetryWithPublicURL = false
            userWantsPause = false
        }

        if player == nil {
            loadFailed = false
            let configuration = await MediaURLResolver.playbackConfiguration(for: url)
            installPlayer(using: configuration)
        }

        player?.isMuted = isMuted
        if player?.currentItem?.status == .readyToPlay {
            if userWantsPause {
                player?.pause()
                isPlaying = false
            } else {
                player?.play()
                player?.playImmediately(atRate: 1.0)
                isPlaying = true
                reportViewIfNeeded()
            }
        }
    }

    @MainActor
    private func installPlayer(using configuration: MediaPlaybackConfiguration) {
        let item = makePlayerItem(for: configuration)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = isMuted
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.actionAtItemEnd = loops ? .none : .pause

        statusObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    loadFailed = false
                    updateDuration(from: item)
                    let resumeAt = resolvedStartTime()
                    if resumeAt > 0.5 {
                        await newPlayer.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
                        currentSeconds = resumeAt
                    }
                    if isActive, !userWantsPause {
                        newPlayer.play()
                        // Some Archive CDN items leave rate at 0 after the first play().
                        newPlayer.playImmediately(atRate: 1.0)
                        isPlaying = true
                        reportViewIfNeeded()
                    }
                case .failed:
                    await handlePlaybackFailure(for: configuration.url)
                default:
                    break
                }
            }
        }

        attachTimeObserver(to: newPlayer)

        if loops {
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                newPlayer.seek(to: .zero)
                newPlayer.play()
            }
        }

        player = newPlayer
        MediaPlaybackCoordinator.shared.register(newPlayer)
    }

    @MainActor
    private func attachTimeObserver(to player: AVPlayer) {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                currentSeconds = max(0, time.seconds)
                if let item = player.currentItem {
                    updateDuration(from: item)
                }
                isPlaying = player.rate > 0.01
                trackPlaybackPositionIfNeeded()
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
        if !didRetryWithPublicURL,
           let fallback = MediaURLResolver.playbackFallbackConfiguration(for: failedURL) {
            didRetryWithPublicURL = true
            removeTimeObserver()
            teardownPlayerObservers()
            player = nil
            installPlayer(using: fallback)
            return
        }
        removeTimeObserver()
        teardownPlayerObservers()
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

    private func teardownPlayer() {
        persistPlaybackPosition()
        removeTimeObserver()
        teardownPlayerObservers()
        if let player {
            player.pause()
            player.replaceCurrentItem(with: nil)
            MediaPlaybackCoordinator.shared.unregister(player)
        }
        player = nil
        configuredURL = nil
        didRetryWithPublicURL = false
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

    func makeUIView(context: Context) -> MatteryaPlayerUIView {
        let view = MatteryaPlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: MatteryaPlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class MatteryaPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

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

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.paper)
                            .frame(width: 42, height: 42)
                            .background(Theme.accentBright, in: Circle())
                            .shadow(color: Theme.ink.opacity(0.25), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)

                    Text(formatTime(currentSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))

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
                }
                .padding(.horizontal, 14)
                .padding(.bottom, isFullscreen ? 0 : 14)
                .safeAreaPadding(.bottom, isFullscreen ? 10 : 0)
            }
            .background(
                LinearGradient(
                    colors: [.clear, Theme.ink.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var scrubberValue: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, max(0, currentSeconds / durationSeconds))
    }

    private func controlIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.ink.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
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
        self.onViewed = onViewed
        _isMuted = State(initialValue: muted)
    }

    private var focusID: String {
        postID ?? url.absoluteString
    }

    /// Winner of FeedVideoFocus + allowed surface (feed/profile, no hubs/reels takeover).
    private var shouldPlay: Bool {
        isFocusWinner
            && (appState.selectedTab == .feed || appState.selectedTab == .profile)
            && appState.reelsViewerContext == nil
            && appState.hubPlaybackPost == nil
    }

    private var usesArchivePath: Bool {
        preferArchivePlayer || ArchiveVideoPlayback.isArchiveURL(url)
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
                        // Keep controls mounted; only the active winner should show chrome.
                        // Tying this to shouldPlay remounted chrome and caused mid-play stutters.
                        showsControls: showsControls && playGate,
                        loops: loops,
                        isMuted: $isMuted,
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
                        showsControls: showsControls && playGate,
                        allowsFullscreen: false,
                        onViewed: onViewed
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .feedVideoFocusDidChange)) { _ in
            refreshFocusWinner()
        }
        .background(visibilityProbe)
        .onAppear {
            isMuted = muted
            // Kick Archive CDN resolve as soon as the cell appears (not after focus).
            if usesArchivePath {
                ArchiveVideoPlayback.warmResolve(url)
            }
            refreshFocusWinner()
            syncPlayGate(immediate: true)
            if playGate, !isMuted {
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
        .onChange(of: appState.hubPlaybackPost?.id) { _, hubID in
            syncPlayGate(immediate: hubID != nil)
            if hubID == nil, shouldPlay, !isMuted {
                activatePlaybackAudioIfNeeded(unmuted: true)
            }
        }
        .onChange(of: appState.selectedTab) { _, _ in
            syncPlayGate(immediate: true)
        }
        .onChange(of: appState.reelsViewerContext?.id) { _, ctx in
            syncPlayGate(immediate: ctx != nil)
        }
        .onChange(of: shouldPlay) { _, play in
            syncPlayGate(immediate: play)
            if play, !isMuted {
                activatePlaybackAudioIfNeeded(unmuted: true)
            }
        }
    }

    private func refreshFocusWinner() {
        let win = FeedVideoFocus.shared.isActive(id: focusID)
        if win != isFocusWinner {
            isFocusWinner = win
        }
        syncPlayGate(immediate: win)
    }

    /// Instant on for play; short delay off so layout/scroll jitter doesn't hard-pause.
    private func syncPlayGate(immediate: Bool) {
        if shouldPlay {
            deactivateTask?.cancel()
            deactivateTask = nil
            if !playGate {
                playGate = true
            }
            return
        }
        // Leaving feed / hubs takeover / reels: pause immediately.
        let leftAutoplaySurface =
            (appState.selectedTab != .feed && appState.selectedTab != .profile)
            || appState.reelsViewerContext != nil
            || appState.hubPlaybackPost != nil
        if immediate || leftAutoplaySurface {
            deactivateTask?.cancel()
            deactivateTask = nil
            playGate = false
            return
        }
        // Focus lost briefly — hold playback ~280ms before pausing.
        guard playGate else { return }
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
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { reportVisibility(proxy.frame(in: .global)) }
                .onChange(of: frame.minY) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
                .onChange(of: frame.midY) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
                .onChange(of: frame.height) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
                .onChange(of: appState.selectedTab) { _, _ in
                    reportVisibility(proxy.frame(in: .global))
                }
        }
        .allowsHitTesting(false)
    }

    private func reportVisibility(_ frame: CGRect) {
        let ratio = FeedVideoFocus.visibleRatio(for: frame)
        // Skip noise when unchanged (avoids recompute thrash while scrolling).
        if abs(ratio - lastReportedRatio) < 0.04, lastReportedRatio >= 0 {
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