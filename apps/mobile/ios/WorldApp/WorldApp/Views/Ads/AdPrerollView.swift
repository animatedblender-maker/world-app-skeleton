import AVFoundation
import AVKit
import SwiftUI
import UIKit

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

            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let adSlot, let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .disabled(true)

                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        Text("Sponsored")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                        Spacer()
                        if skipReady {
                            Button("Skip") { finishAd() }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                        } else if skipSecondsLeft > 0 {
                            Text("Skip in \(skipSecondsLeft)s")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Spacer()

                    VStack(alignment: .leading, spacing: 10) {
                        if let title = adSlot.creative.title, !title.isEmpty {
                            Text(title)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        if let body = adSlot.creative.body, !body.isEmpty {
                            Text(body)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(3)
                        }
                        if let clickURL = adSlot.creative.clickURL, !clickURL.isEmpty {
                            Button(adSlot.creative.ctaLabel ?? "Learn more") {
                                openAdLink(clickURL)
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.facebookBlue, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .padding(.bottom, 28)
                }
            }
        }
        .task { await prepareAd() }
        .onDisappear { cleanupPlayer() }
        .onReceive(countdownTimer) { _ in
            updateSkipState()
        }
    }

    private func prepareAd() async {
        isLoading = true
        defer { isLoading = false }

        if SubscriptionService.shared.isPremium {
            onComplete()
            return
        }

        do {
            var slot = try await withTimeout(seconds: 3) {
                try await AdsService.shared.serveVideoAd(
                    placement: placement,
                    countryCode: countryCode,
                    contentCountryCode: contentCountryCode,
                    postID: postID
                )
            }

            if slot == nil, placement == "reel" {
                let attempts: [(String?, String?)] = [
                    (countryCode, contentCountryCode),
                    (contentCountryCode, contentCountryCode),
                    (countryCode, countryCode),
                ]
                for attempt in attempts where slot == nil {
                    slot = try await AdsService.shared.serveVideoAd(
                        placement: "video",
                        countryCode: attempt.0,
                        contentCountryCode: attempt.1,
                        postID: postID
                    )
                }
            }

            guard let slot, let url = URL(string: slot.creative.mediaURL) else {
                onComplete()
                return
            }

            adSlot = slot
            skipAfterSeconds = max(5, slot.skipAfterSeconds)
            skipSecondsLeft = skipAfterSeconds
            skipReady = false

            let avPlayer = AVPlayer(url: url)
            player = avPlayer

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: avPlayer.currentItem,
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
        } catch {
            onComplete()
        }
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
        guard let token = adSlot?.impressionToken else { return }
        Task { try? await AdsService.shared.logClick(impressionToken: token) }
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
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
                VideoPlayer(player: player)
                    .disabled(true)
                    .ignoresSafeArea()
            } else if let url = post.playableVideoURL ?? post.mediaURL.flatMap(URL.init(string:)) {
                Color.black
                    .task(id: post.id) { mount(url: url) }
            }

            LinearGradient(
                colors: [.black.opacity(0.4), .clear, .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Text("Sponsored")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                    Spacer()
                    Text("Swipe up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    if let title = post.title, !title.isEmpty {
                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    if !post.body.isEmpty {
                        Text(post.body)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(3)
                    }
                    if let click = post.linkURL, !click.isEmpty {
                        Button(post.linkTitle ?? "Learn more") {
                            openLink(click)
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.facebookBlue, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
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
        let av = AVPlayer(url: url)
        player = av
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: av.currentItem,
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
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
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