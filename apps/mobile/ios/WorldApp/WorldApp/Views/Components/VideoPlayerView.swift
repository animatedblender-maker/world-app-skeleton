import AVFoundation
import AVKit
import SwiftUI

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
    var onViewed: (() -> Void)? = nil

    @State private var adFinished = false
    @State private var player: AVPlayer?
    @State private var didReportView = false
    @State private var loopObserver: NSObjectProtocol?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var loadFailed = false
    @State private var didRetryWithPublicURL = false
    @State private var configuredURL: URL?

    private var shouldShowAd: Bool {
        adsEnabled && isActive && !adFinished && placement != nil
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)

            if shouldShowAd, let placement {
                AdPrerollView(
                    placement: placement,
                    countryCode: countryCode,
                    contentCountryCode: contentCountryCode,
                    postID: postID,
                    onComplete: { adFinished = true }
                )
            } else if let player {
                SystemVideoPlayer(player: player, showsControls: showsControls)
            } else if loadFailed {
                VStack(spacing: 8) {
                    Image(systemName: "play.slash")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Video unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            } else if let posterURL {
                CachedAsyncImage(
                    url: posterURL,
                    maxPixelSize: 600,
                    contentMode: .fill,
                    placeholder: AnyView(ProgressView().tint(.white))
                )
            } else {
                ProgressView().tint(.white)
            }
        }
        .clipped()
        .onAppear {
            configureAudioSession()
            Task { await ensurePlayer() }
        }
        .onChange(of: isActive) { _, active in
            if active {
                Task { await ensurePlayer() }
            } else {
                player?.pause()
            }
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
    }

    @MainActor
    private func ensurePlayer(forceRebuild: Bool = false) async {
        guard isActive else {
            player?.pause()
            return
        }
        guard adFinished || !shouldShowAd else { return }

        if forceRebuild || configuredURL != url {
            teardownPlayer()
            configuredURL = url
            didRetryWithPublicURL = false
        }

        if player == nil {
            loadFailed = false
            let configuration = await MediaURLResolver.playbackConfiguration(for: url)
            installPlayer(using: configuration)
        }

        player?.isMuted = muted
        if player?.currentItem?.status == .readyToPlay {
            player?.play()
            reportViewIfNeeded()
        }
    }

    @MainActor
    private func installPlayer(using configuration: MediaPlaybackConfiguration) {
        let item = makePlayerItem(for: configuration)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = muted
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.actionAtItemEnd = loops ? .none : .pause

        statusObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    loadFailed = false
                    if isActive {
                        newPlayer.play()
                        reportViewIfNeeded()
                    }
                case .failed:
                    await handlePlaybackFailure(for: configuration.url)
                default:
                    break
                }
            }
        }

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
    }

    @MainActor
    private func handlePlaybackFailure(for failedURL: URL) async {
        if !didRetryWithPublicURL,
           let fallback = MediaURLResolver.playbackFallbackConfiguration(for: failedURL) {
            didRetryWithPublicURL = true
            teardownPlayerObservers()
            player = nil
            installPlayer(using: fallback)
            return
        }
        loadFailed = true
        player = nil
    }

    private func makePlayerItem(for configuration: MediaPlaybackConfiguration) -> AVPlayerItem {
        if let headers = configuration.headers {
            let asset = AVURLAsset(
                url: configuration.url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
            return AVPlayerItem(asset: asset)
        }
        return AVPlayerItem(url: configuration.url)
    }

    private func teardownPlayer() {
        teardownPlayerObservers()
        player?.pause()
        player = nil
        configuredURL = nil
        didRetryWithPublicURL = false
        loadFailed = false
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
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

private struct SystemVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var showsControls: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsControls
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        controller.showsPlaybackControls = showsControls
        controller.videoGravity = .resizeAspectFill
    }
}

/// Plays video when the view enters the scroll viewport.
struct InFrameVideoPlayer: View {
    let url: URL
    let posterURL: URL?
    var placement: String? = nil
    var countryCode: String? = nil
    var contentCountryCode: String? = nil
    var postID: String? = nil
    var muted: Bool = true
    var onViewed: (() -> Void)? = nil

    @State private var isInFrame = false

    var body: some View {
        VideoPlayerView(
            url: url,
            posterURL: posterURL,
            placement: placement,
            countryCode: countryCode,
            contentCountryCode: contentCountryCode,
            postID: postID,
            isActive: isInFrame,
            loops: false,
            muted: muted,
            onViewed: onViewed
        )
        .onAppear { isInFrame = true }
        .onDisappear { isInFrame = false }
    }
}