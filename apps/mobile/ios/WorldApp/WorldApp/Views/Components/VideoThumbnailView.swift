import AVFoundation
import Combine
import CryptoKit
import SwiftUI
import UIKit

struct VideoThumbnailView: View {
    let post: CountryPost
    var maxPixelSize: CGFloat = 480
    var contentMode: ContentMode = .fill
    /// Center play circle — default off (clean thumbs in feed / hubs / search).
    var showsPlayIcon = false
    var playIconSize: CGFloat = 36
    var extractFrameIfNeeded = true
    var placeholder: AnyView = AnyView(Color.clear)

    @State private var frameImage: UIImage?
    /// Live Frame 0 from /v1/poster — refreshes cells after dead r2.dev thumbs are rejected.
    @State private var liveFrame0URL: URL?
    /// URLs that 403/failed decode — skip so LongForm YouTube / Frame0 can win.
    @State private var failedPosterKeys: Set<String> = []

    var body: some View {
        ZStack {
            // Soft canvas until a real poster paints (black forever looked “broken”).
            if post.hasVideo {
                Theme.canvasDeep
            }

            if let posterURL = resolvedPosterURL {
                CachedAsyncImage(
                    url: posterURL,
                    maxPixelSize: maxPixelSize,
                    contentMode: contentMode,
                    placeholder: post.hasVideo ? AnyView(Theme.canvasDeep) : placeholder,
                    onLoadFailed: { failed in
                        failedPosterKeys.insert(failed.absoluteString)
                    }
                )
            } else if let videoURL = post.playableVideoURL ?? MediaURLResolver.videoURL(for: post) {
                // R2 Sparks/Hubs often lack a usable thumb until Frame0 is signed.
                FrameZeroFallbackPoster(
                    postID: post.id,
                    videoURL: videoURL,
                    fillsFrame: contentMode == .fill,
                    allowClientExtract: extractFrameIfNeeded,
                    seedPosterURL: liveFrame0URL ?? Frame0PosterCache.url(for: post.id)
                )
            } else if let frameImage {
                Image(uiImage: frameImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if post.hasVideo {
                Theme.canvasDeep
                    .overlay {
                        Image(systemName: "film")
                            .font(.title3)
                            .foregroundStyle(Theme.inkMuted.opacity(0.55))
                    }
            } else {
                placeholder
            }

            // Intentionally no center play circle by default.
            if showsPlayIcon, post.hasVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: playIconSize))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
        }
        .task(id: thumbnailTaskID) {
            await ensureFrame0Poster()
            await loadFrameIfNeeded()
        }
        // Frame0PosterCache is not Observable — batch prefetch must poke visible cells.
        .onReceive(
            NotificationCenter.default.publisher(for: .frame0PostersDidUpdate)
                .receive(on: DispatchQueue.main)
        ) { note in
            let ids = note.userInfo?["postIDs"] as? [String]
            if ScrollBudget.isFlinging {
                // Don't drop forever — Hubs list never AV-extracts, so a missed
                // Frame0 notify left cards blank until another batch.
                Task { @MainActor in
                    for _ in 0..<5 {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        if !ScrollBudget.isFlinging { break }
                    }
                    guard !ScrollBudget.isFlinging else { return }
                    applyFrame0CacheIfNeeded(postIDs: ids)
                }
                return
            }
            applyFrame0CacheIfNeeded(postIDs: ids)
        }
    }

    /// Prefer usable Frame 0, then **instant LongForm YouTube**, then other posters.
    /// Dead/expired R2 must not block YouTube hqdefault or every Hubs tile stays black.
    private var resolvedPosterURL: URL? {
        let yt = MediaURLResolver.r2LongformYouTubePosterURL(for: post)
        let candidates: [URL?] = [
            liveFrame0URL,
            Frame0PosterCache.url(for: post.id),
            // Paint LongForm immediately — Frame0 can upgrade when the batch lands.
            yt,
            MediaURLResolver.hubsListPosterURL(for: post),
            post.posterImageURL,
            post.feedImageURL,
        ]
        for candidate in candidates {
            guard let url = candidate, MediaURLResolver.isUsablePosterURL(url) else { continue }
            if failedPosterKeys.contains(url.absoluteString) { continue }
            return url
        }
        return nil
    }

    private var thumbnailTaskID: String {
        [
            post.id,
            liveFrame0URL?.absoluteString ?? "",
            extractFrameIfNeeded ? "1" : "0",
        ].joined(separator: "|")
    }

    @MainActor
    private func applyFrame0CacheIfNeeded(postIDs: [String]?) {
        if let liveFrame0URL, MediaURLResolver.isUsablePosterURL(liveFrame0URL) { return }
        if let postIDs, !postIDs.isEmpty, !postIDs.contains(post.id) { return }
        if let cached = Frame0PosterCache.url(for: post.id),
           MediaURLResolver.isUsablePosterURL(cached) {
            liveFrame0URL = cached
        }
    }

    @MainActor
    private func ensureFrame0Poster() async {
        if let cached = liveFrame0URL ?? Frame0PosterCache.url(for: post.id),
           MediaURLResolver.isUsablePosterURL(cached) {
            liveFrame0URL = cached
            return
        }
        // Missing frame0_*.webp is common — do not re-GET after a known miss.
        if Frame0PosterCache.isKnownMiss(post.id) {
            return
        }
        // Skip Frame0 fetch when a non-R2 usable poster already paints (e.g. IA services/img).
        if let existing = MediaURLResolver.hubsListPosterURL(for: post),
           MediaURLResolver.isUsablePosterURL(existing),
           !MediaURLResolver.hasMatteryaR2VideoKey(post) {
            return
        }
        if let signed = await Frame0PosterResolver.shared.posterURL(postID: post.id),
           MediaURLResolver.isUsablePosterURL(signed) {
            liveFrame0URL = signed
            return
        }
        // Batch may have landed while the single GET failed/timed out.
        if let cached = Frame0PosterCache.url(for: post.id),
           MediaURLResolver.isUsablePosterURL(cached) {
            liveFrame0URL = cached
        }
    }

    private var needsFrameExtraction: Bool {
        // Only when no remote poster AND Frame0 path is not already handling the cell.
        // Strip tiles use FrameZeroFallbackPoster instead of per-tile AV extract.
        extractFrameIfNeeded
            && resolvedPosterURL == nil
            && (post.playableVideoURL ?? MediaURLResolver.videoURL(for: post)) == nil
    }

    @MainActor
    private func loadFrameIfNeeded() async {
        guard needsFrameExtraction, frameImage == nil, let videoURL = post.playableVideoURL else { return }
        frameImage = await VideoFrameCache.shared.image(for: post.id, videoURL: videoURL)
    }
}

/// Sparks-style Frame 0 hold when `thumb_url` is missing (feed / hubs / hub shares).
struct FrameZeroFallbackPoster: View {
    let postID: String
    let videoURL: URL
    var fillsFrame: Bool = true
    /// When false (default), only fetch signed `frame0_*.webp` — never download the full
    /// video for AV extract. Full-video extract storms R2 and freezes Sparks/feed.
    var allowClientExtract: Bool = false
    /// Skip network if the post already has a usable remote poster URL.
    var seedPosterURL: URL? = nil

    @State private var frameImage: UIImage?
    @State private var remotePosterURL: URL?

    var body: some View {
        ZStack {
            Theme.canvasDeep
            if let url = remotePosterURL ?? seedPosterURL ?? Frame0PosterCache.url(for: postID) {
                CachedAsyncImage(
                    url: url,
                    maxPixelSize: 720,
                    contentMode: fillsFrame ? .fill : .fit,
                    placeholder: AnyView(Theme.canvasDeep)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else if let frameImage {
                Image(uiImage: frameImage)
                    .resizable()
                    .aspectRatio(contentMode: fillsFrame ? .fill : .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .onAppear {
            if remotePosterURL == nil,
               let cached = seedPosterURL ?? Frame0PosterCache.url(for: postID),
               MediaURLResolver.isUsablePosterURL(cached) {
                remotePosterURL = cached
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .frame0PostersDidUpdate)
                .receive(on: DispatchQueue.main)
        ) { note in
            let ids = note.userInfo?["postIDs"] as? [String]
            if ScrollBudget.isFlinging {
                Task { @MainActor in
                    for _ in 0..<5 {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        if !ScrollBudget.isFlinging { break }
                    }
                    guard !ScrollBudget.isFlinging else { return }
                    applyFrame0Notify(postIDs: ids)
                }
                return
            }
            applyFrame0Notify(postIDs: ids)
        }
        .task(id: "\(postID)|\(videoURL.absoluteString)|\(allowClientExtract)") {
            if let seed = seedPosterURL ?? Frame0PosterCache.url(for: postID),
               MediaURLResolver.isUsablePosterURL(seed) {
                remotePosterURL = seed
                return
            }
            // Pack-path Frame 0 only (cheap). Do not AV-extract on every cell.
            if let signed = await Frame0PosterResolver.shared.posterURL(postID: postID),
               MediaURLResolver.isUsablePosterURL(signed) {
                remotePosterURL = signed
                return
            }
            if let cached = Frame0PosterCache.url(for: postID),
               MediaURLResolver.isUsablePosterURL(cached) {
                remotePosterURL = cached
                return
            }
            guard allowClientExtract else { return }
            // Wait out fling so Hubs scroll never fights AV decode.
            for _ in 0..<8 {
                if !ScrollBudget.isFlinging { break }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard !ScrollBudget.isFlinging else { return }
            frameImage = await VideoFrameCache.shared.image(for: postID, videoURL: videoURL)
        }
    }

    @MainActor
    private func applyFrame0Notify(postIDs: [String]?) {
        if let remotePosterURL, MediaURLResolver.isUsablePosterURL(remotePosterURL) { return }
        if let postIDs, !postIDs.isEmpty, !postIDs.contains(postID) { return }
        if let cached = Frame0PosterCache.url(for: postID),
           MediaURLResolver.isUsablePosterURL(cached) {
            remotePosterURL = cached
        }
    }
}

@MainActor
final class VideoFrameCache {
    static let shared = VideoFrameCache()

    private var memory: [String: UIImage] = [:]
    private var memoryOrder: [String] = []
    private let memoryLimit = 40
    /// In-flight extractors — waiters join instead of returning nil (nil = black poster).
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var activeCount = 0
    private let maxConcurrent = 1
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private let directoryURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VideoFrameCache", isDirectory: true)
    }()

    private init() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func remember(_ image: UIImage, key: String) {
        if memory[key] == nil {
            memoryOrder.append(key)
        }
        memory[key] = image
        while memoryOrder.count > memoryLimit {
            let evict = memoryOrder.removeFirst()
            memory.removeValue(forKey: evict)
        }
    }

    func image(for postID: String, videoURL: URL, atFirstFrame: Bool = false) async -> UIImage? {
        let key = cacheKey(postID: postID, videoURL: videoURL, atFirstFrame: atFirstFrame)
        if let cached = memory[key] { return cached }
        if let disk = loadFromDisk(key: key) {
            remember(disk, key: key)
            return disk
        }

        if let existing = inflight[key] {
            return await existing.value
        }

        await acquireSlot()
        if let cached = memory[key] {
            releaseSlot()
            return cached
        }
        if let existing = inflight[key] {
            releaseSlot()
            return await existing.value
        }

        let task = Task<UIImage?, Never> { @MainActor in
            defer {
                inflight[key] = nil
                releaseSlot()
            }
            let playback = await MediaURLResolver.playbackConfiguration(for: videoURL)
            let playURL = playback.url
            let headers = playback.headers
            // Stable "random" mid-clip time per post — avoids black first frames / title cards.
            // Masquerade feed posters pass atFirstFrame=true (literal t≈0).
            let sampleSeed = postID.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fffffff }
            let preferFirstFrame = atFirstFrame

            // Never block MainActor with AVAssetImageGenerator (Hubs freeze root cause).
            let image: UIImage? = await Task.detached(priority: .utility) {
                let asset: AVURLAsset
                if let headers {
                    asset = AVURLAsset(
                        url: playURL,
                        options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
                    )
                } else {
                    asset = AVURLAsset(url: playURL)
                }
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 480, height: 480)

                if preferFirstFrame {
                    // Literal first displayed frame — Masquerade outside thumbnail.
                    generator.requestedTimeToleranceBefore = .zero
                    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)
                    if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                        return UIImage(cgImage: cgImage)
                    }
                    // Tiny nudge if t=0 is an empty keyframe.
                    let nudge = CMTime(seconds: 0.04, preferredTimescale: 600)
                    if let cgImage = try? generator.copyCGImage(at: nudge, actualTime: nil) {
                        return UIImage(cgImage: cgImage)
                    }
                    return nil
                }

                let duration = (try? await asset.load(.duration)) ?? .zero
                let seconds = CMTimeGetSeconds(duration)
                let targetSeconds: Double
                if seconds.isFinite, seconds > 2 {
                    // Pick ~15–55% into the clip (deterministic per post id).
                    let frac = 0.15 + (Double(sampleSeed % 400) / 1000.0)
                    targetSeconds = min(max(seconds * frac, 0.5), max(seconds - 0.25, 0.5))
                } else if seconds.isFinite, seconds > 0.4 {
                    targetSeconds = min(seconds * 0.35, seconds - 0.05)
                } else {
                    targetSeconds = 1.0
                }
                let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)
                generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    return UIImage(cgImage: cgImage)
                }
                // Fall back to t≈0 when mid-clip extract fails (short/corrupt packs).
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    return UIImage(cgImage: cgImage)
                }
                return nil
            }.value

            guard let image else { return nil }
            remember(image, key: key)
            saveToDisk(image: image, key: key)
            return image
        }
        inflight[key] = task
        return await task.value
    }

    private func acquireSlot() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            gateWaiters.append(cont)
        }
        activeCount += 1
    }

    private func releaseSlot() {
        activeCount = max(0, activeCount - 1)
        if !gateWaiters.isEmpty {
            let next = gateWaiters.removeFirst()
            next.resume()
        }
    }

    private func cacheKey(postID: String, videoURL: URL, atFirstFrame: Bool = false) -> String {
        let raw = "\(postID)|\(videoURL.absoluteString)|\(atFirstFrame ? "f0" : "mid")"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func diskURL(for key: String) -> URL {
        directoryURL.appendingPathComponent("\(key).jpg")
    }

    private func loadFromDisk(key: String) -> UIImage? {
        guard let data = try? Data(contentsOf: diskURL(for: key)) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(image: UIImage, key: String) {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        try? data.write(to: diskURL(for: key), options: .atomic)
    }
}