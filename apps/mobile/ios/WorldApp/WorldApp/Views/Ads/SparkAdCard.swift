import AVFoundation
import SwiftUI
import UIKit

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
            } else if let url = post.playableVideoURL ?? AdURL.media(post.mediaURL ?? "") {
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
        guard let url = AdURL.normalized(urlString) else { return }
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
