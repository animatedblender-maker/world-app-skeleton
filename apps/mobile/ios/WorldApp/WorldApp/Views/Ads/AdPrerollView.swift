import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// In-memory last-serve cache so Hubs pre-roll can start playing immediately
/// while a fresh GraphQL serve refreshes in the background.
@MainActor
enum AdServeCache {
    private static var byPlacement: [String: (slot: AdSlot, at: Date)] = [:]
    private static let maxAge: TimeInterval = 120

    static func peek(placement: String) -> AdSlot? {
        guard let entry = byPlacement[placement],
              Date().timeIntervalSince(entry.at) < maxAge
        else { return nil }
        return entry.slot
    }

    static func store(_ slot: AdSlot, placement: String) {
        byPlacement[placement] = (slot, Date())
        // Video campaigns also feed Sparks reel requests.
        if placement == "video" {
            byPlacement["reel"] = (slot, Date())
        }
    }

    static func clear() {
        byPlacement.removeAll()
    }
}

struct AdPrerollView: View {
    let placement: String
    var countryCode: String?
    var contentCountryCode: String?
    var postID: String?
    let onComplete: () -> Void

    @State private var adSlot: AdSlot?
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var skipAfterSeconds = 5
    @State private var skipReady = false
    @State private var skipSecondsLeft = 0
    @State private var impressionLogged = false
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    private let countdownTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                AdFillPlayerView(player: player)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else if isLoading {
                ProgressView()
                    .tint(Theme.matte)
            }

            // Soft vignette — never a hard black letterbox band over the film.
            LinearGradient(
                colors: [.black.opacity(0.28), .clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Text("Sponsored")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.matte.opacity(0.92), in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let title = adSlot?.creative.title, !title.isEmpty {
                            Text(title)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Theme.matte)
                        }
                        if let body = adSlot?.creative.body, !body.isEmpty {
                            Text(body)
                                .font(.subheadline)
                                .foregroundStyle(Theme.matte.opacity(0.92))
                                .lineLimit(3)
                        }
                        if let clickURL = adSlot?.creative.clickURL, !clickURL.isEmpty {
                            Button {
                                openAdLink(clickURL)
                            } label: {
                                Text(adSlot?.creative.ctaLabel ?? "Learn more")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Theme.matte, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    skipControl
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .task { await prepareAd() }
        .onDisappear { cleanupPlayer() }
        .onReceive(countdownTimer) { _ in
            updateSkipState()
        }
    }

    @ViewBuilder
    private var skipControl: some View {
        if skipReady {
            Button("Skip") { finishAd() }
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.matte.opacity(0.95), in: Capsule())
                .buttonStyle(.plain)
        } else if skipSecondsLeft > 0, player != nil {
            Text("Skip in \(skipSecondsLeft)s")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.matte.opacity(0.75), in: Capsule())
        }
    }

    private func prepareAd() async {
        if SubscriptionService.shared.isPremium {
            onComplete()
            return
        }

        // Instant path: play cached creative while a fresh serve runs.
        if let cached = AdServeCache.peek(placement: placement),
           let url = Self.mediaURL(from: cached.creative.mediaURL) {
            mount(slot: cached, url: url)
            isLoading = false
            Task { await refreshServeInBackground() }
            return
        }

        isLoading = true
        do {
            let slot = try await fetchSlot()
            guard let slot, let url = Self.mediaURL(from: slot.creative.mediaURL) else {
                isLoading = false
                onComplete()
                return
            }
            AdServeCache.store(slot, placement: placement)
            mount(slot: slot, url: url)
            isLoading = false
        } catch {
            isLoading = false
            onComplete()
        }
    }

    private func refreshServeInBackground() async {
        do {
            if let slot = try await fetchSlot() {
                AdServeCache.store(slot, placement: placement)
            }
        } catch {
            // Keep playing the cached creative.
        }
    }

    private func fetchSlot() async throws -> AdSlot? {
        var slot = try await withTimeout(seconds: 8) {
            try await AdsService.shared.serveVideoAd(
                placement: placement,
                countryCode: countryCode,
                contentCountryCode: contentCountryCode,
                postID: postID
            )
        }
        if slot == nil, placement == "reel" {
            slot = try await AdsService.shared.serveVideoAd(
                placement: "video",
                countryCode: countryCode,
                contentCountryCode: contentCountryCode,
                postID: postID
            )
        }
        return slot
    }

    private func mount(slot: AdSlot, url: URL) {
        cleanupPlayer()
        adSlot = slot
        skipAfterSeconds = max(3, min(5, slot.skipAfterSeconds))
        skipSecondsLeft = skipAfterSeconds
        skipReady = false
        impressionLogged = false

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        // Prefer immediate start — preferPreciseDurationAndTiming off by default.
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        player = avPlayer

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            finishAd()
        }

        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { _ in
            if avPlayer.rate > 0 {
                markImpression()
            }
        }

        avPlayer.play()
        markImpression()
    }

    private func updateSkipState() {
        guard let player else { return }
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        skipSecondsLeft = max(0, Int(ceil(Double(skipAfterSeconds) - current)))
        skipReady = current >= Double(skipAfterSeconds)
    }

    private func markImpression() {
        guard let token = adSlot?.impressionToken, !impressionLogged else { return }
        impressionLogged = true
        Task {
            try? await AdsService.shared.logImpression(impressionToken: token)
        }
    }

    private func openAdLink(_ urlString: String) {
        let token = adSlot?.impressionToken
        Task {
            if let token {
                try? await AdsService.shared.logClick(impressionToken: token)
            }
        }
        guard let url = Self.normalizedURL(urlString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func finishAd() {
        cleanupPlayer()
        adSlot = nil
        onComplete()
    }

    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func cleanupPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
    }

    static func mediaURL(from raw: String) -> URL? {
        normalizedURL(raw)
    }

    /// `matterya.com` (no scheme) must become https://… or open() does nothing.
    static func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }
}

/// Aspect-fill AV layer — no black letterbox bars like stock `VideoPlayer`.
private struct AdFillPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> AdPlayerUIView {
        let view = AdPlayerUIView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: AdPlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = .resizeAspectFill
    }
}

private final class AdPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Standalone Sparks ad card — its own swipe page, never an overlay on organic Sparks.
struct SparkAdStandaloneCard: View {
    let post: CountryPost
    let isActive: Bool

    @State private var player: AVPlayer?
    @State private var impressionLogged = false
    @State private var endObserver: NSObjectProtocol?
    @State private var timeObserver: Any?

    private var slot: AdSlot? { SparkAdRegistry.slot(forPostID: post.id) }

    var body: some View {
        ZStack {
            Color.black
            if let player {
                AdFillPlayerView(player: player)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else if let url = post.playableVideoURL
                ?? AdPrerollView.normalizedURL(post.mediaURL ?? "") {
                Color.black
                    .task(id: post.id) { mount(url: url) }
            }

            LinearGradient(
                colors: [.black.opacity(0.32), .clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Text("Sponsored")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.matte.opacity(0.92), in: Capsule())
                    Spacer()
                    Text("Swipe up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.matte.opacity(0.75), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    if let title = post.title, !title.isEmpty {
                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Theme.matte)
                    }
                    if !post.body.isEmpty {
                        Text(post.body)
                            .font(.subheadline)
                            .foregroundStyle(Theme.matte.opacity(0.92))
                            .lineLimit(3)
                    }
                    if let click = post.linkURL, !click.isEmpty {
                        Button {
                            openLink(click)
                        } label: {
                            Text(post.linkTitle ?? "Learn more")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Theme.matte, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                player?.play()
                markImpression()
            } else {
                player?.pause()
            }
        }
        .onDisappear { cleanup() }
    }

    private func mount(url: URL) {
        cleanup()
        let item = AVPlayerItem(url: url)
        let av = AVPlayer(playerItem: item)
        av.automaticallyWaitsToMinimizeStalling = false
        player = av
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            av.seek(to: .zero)
            if isActive { av.play() }
        }
        timeObserver = av.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { _ in
            if av.rate > 0 { markImpression() }
        }
        if isActive {
            av.play()
            markImpression()
        }
    }

    private func markImpression() {
        guard let token = slot?.impressionToken ?? post.externalRefID, !impressionLogged else { return }
        impressionLogged = true
        Task { try? await AdsService.shared.logImpression(impressionToken: token) }
    }

    private func openLink(_ urlString: String) {
        if let token = slot?.impressionToken ?? post.externalRefID {
            Task { try? await AdsService.shared.logClick(impressionToken: token) }
        }
        guard let url = AdPrerollView.normalizedURL(urlString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func cleanup() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
    }
}
