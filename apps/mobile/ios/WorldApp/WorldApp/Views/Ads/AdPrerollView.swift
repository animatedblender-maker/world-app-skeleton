import AVFoundation
import SwiftUI
import UIKit

/// Hubs / long-form pre-roll overlay. Standalone Sparks ads use `SparkAdStandaloneCard`.
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
        guard AdDeliveryPolicy.adsEnabled else {
            onComplete()
            return
        }

        // Instant path: play cached creative while a fresh serve runs.
        if let cached = AdServeCache.peek(placement: placement),
           let url = AdURL.media(cached.creative.mediaURL) {
            mount(slot: cached, url: url)
            isLoading = false
            Task { await refreshServeInBackground() }
            return
        }

        isLoading = true
        do {
            let slot = try await fetchSlot()
            guard let slot, let url = AdURL.media(slot.creative.mediaURL) else {
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
        var slot = try await withTimeout(seconds: AdDeliveryPolicy.serveTimeoutSeconds) {
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
        let clamp = AdDeliveryPolicy.skipAfterSecondsClamp
        skipAfterSeconds = min(max(slot.skipAfterSeconds, clamp.lowerBound), clamp.upperBound)
        skipSecondsLeft = skipAfterSeconds
        skipReady = false
        impressionLogged = false

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
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
        guard let url = AdURL.normalized(urlString) else { return }
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
}
