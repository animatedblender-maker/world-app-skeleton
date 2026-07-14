import AVFoundation
import CryptoKit
import SwiftUI
import UIKit

struct VideoThumbnailView: View {
    let post: CountryPost
    var maxPixelSize: CGFloat = 480
    var contentMode: ContentMode = .fill
    var showsPlayIcon = true
    var playIconSize: CGFloat = 36
    var extractFrameIfNeeded = true
    var placeholder: AnyView = AnyView(Color.clear)

    @State private var frameImage: UIImage?

    var body: some View {
        ZStack {
            if let posterURL = post.posterImageURL ?? post.feedImageURL {
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

    private var thumbnailTaskID: String {
        [
            post.id,
            post.thumbURL ?? "",
            post.playableVideoURL?.absoluteString ?? "",
            extractFrameIfNeeded ? "1" : "0",
        ].joined(separator: "|")
    }

    private var needsFrameExtraction: Bool {
        extractFrameIfNeeded
            && post.posterImageURL == nil
            && post.feedImageURL == nil
            && post.playableVideoURL != nil
    }

    @MainActor
    private func loadFrameIfNeeded() async {
        guard needsFrameExtraction, frameImage == nil, let videoURL = post.playableVideoURL else { return }
        frameImage = await VideoFrameCache.shared.image(for: post.id, videoURL: videoURL)
    }
}

@MainActor
final class VideoFrameCache {
    static let shared = VideoFrameCache()

    private var memory: [String: UIImage] = [:]
    private var inflightKeys = Set<String>()
    private let maxConcurrent = 2
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

        while inflightKeys.count >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        guard !inflightKeys.contains(key) else { return nil }
        inflightKeys.insert(key)
        defer { inflightKeys.remove(key) }

        let playback = await MediaURLResolver.playbackConfiguration(for: videoURL)
        let asset: AVURLAsset
        if let headers = playback.headers {
            asset = AVURLAsset(
                url: playback.url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
        } else {
            asset = AVURLAsset(url: playback.url)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        let image = UIImage(cgImage: cgImage)
        memory[key] = image
        saveToDisk(image: image, key: key)
        return image
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