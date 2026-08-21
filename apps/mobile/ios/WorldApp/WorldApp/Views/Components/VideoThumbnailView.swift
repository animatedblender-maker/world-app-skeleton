import AVFoundation
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

    var body: some View {
        ZStack {
            if let posterURL = resolvedPosterURL {
                CachedAsyncImage(
                    url: posterURL,
                    maxPixelSize: maxPixelSize,
                    contentMode: contentMode,
                    placeholder: placeholder
                )
            } else if let frameImage {
                Image(uiImage: frameImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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
            await loadFrameIfNeeded()
        }
    }

    /// Prefer IA services/img (fast) then other posters — never the mp4 URL.
    private var resolvedPosterURL: URL? {
        MediaURLResolver.hubsListPosterURL(for: post)
            ?? post.posterImageURL
            ?? post.feedImageURL
    }

    private var thumbnailTaskID: String {
        [
            post.id,
            resolvedPosterURL?.absoluteString ?? "",
            extractFrameIfNeeded ? "1" : "0",
        ].joined(separator: "|")
    }

    private var needsFrameExtraction: Bool {
        // Only when no remote poster (R2 LongForm uses YouTube CDN; Sparks may extract one frame).
        extractFrameIfNeeded
            && resolvedPosterURL == nil
            && post.playableVideoURL != nil
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

    @State private var frameImage: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let frameImage {
                Image(uiImage: frameImage)
                    .resizable()
                    .aspectRatio(contentMode: fillsFrame ? .fill : .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .task(id: "\(postID)|\(videoURL.absoluteString)") {
            frameImage = await VideoFrameCache.shared.image(for: postID, videoURL: videoURL)
        }
    }
}

@MainActor
final class VideoFrameCache {
    static let shared = VideoFrameCache()

    private var memory: [String: UIImage] = [:]
    /// In-flight extractors — waiters join instead of returning nil (nil = black poster).
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var activeCount = 0
    private let maxConcurrent = 3
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private let directoryURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VideoFrameCache", isDirectory: true)
    }()

    private init() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func image(for postID: String, videoURL: URL) async -> UIImage? {
        let key = cacheKey(postID: postID, videoURL: videoURL)
        if let cached = memory[key] { return cached }
        if let disk = loadFromDisk(key: key) {
            memory[key] = disk
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
                generator.maximumSize = CGSize(width: 720, height: 720)
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.35, preferredTimescale: 600)
                guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
                    return nil
                }
                return UIImage(cgImage: cgImage)
            }.value

            guard let image else { return nil }
            memory[key] = image
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

    private func cacheKey(postID: String, videoURL: URL) -> String {
        let raw = "\(postID)|\(videoURL.absoluteString)"
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