import CryptoKit
import ImageIO
import SwiftUI
import UIKit

@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private var inflight = [NSString: Task<UIImage?, Never>]()
    private let session: URLSession
    private let diskDirectory: URL

    private init() {
        memoryCache.countLimit = 120
        memoryCache.totalCostLimit = 48 * 1024 * 1024

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 192 * 1024 * 1024
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDirectory = base.appendingPathComponent("MatteryaImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    static func configureSharedCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 192 * 1024 * 1024
        )
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let fetchURL = Self.cacheableURL(from: url)
        let key = cacheKey(for: fetchURL, maxPixelSize: maxPixelSize)
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key, cost: diskImage.pngData()?.count ?? 0)
            return diskImage
        }
        if let existing = inflight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            do {
                let (data, response) = try await Self.fetchData(from: fetchURL, session: session)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    return nil
                }
                guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                    return nil
                }
                let cost = data.count
                memoryCache.setObject(image, forKey: key, cost: cost)
                saveToDisk(image: image, key: key)
                return image
            } catch {
                return nil
            }
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        return image
    }

    private func cacheKey(for url: URL, maxPixelSize: CGFloat) -> NSString {
        let raw = "\(url.absoluteString)|\(Int(maxPixelSize))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex as NSString
    }

    private func diskFileURL(for key: NSString) -> URL {
        diskDirectory.appendingPathComponent("\(key).img")
    }

    private func loadFromDisk(key: NSString) -> UIImage? {
        let url = diskFileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(image: UIImage, key: NSString) {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return }
        try? data.write(to: diskFileURL(for: key), options: .atomic)
    }

    private static func cacheableURL(from url: URL) -> URL {
        if SupabaseStorageAccess.isPostsBucketURL(url),
           let publicURL = SupabaseStorageAccess.publicURL(from: url) {
            return publicURL
        }
        if url.absoluteString.contains("/object/authenticated/avatars/"),
           let publicURL = url.absoluteString
            .replacingOccurrences(of: "/object/authenticated/avatars/", with: "/object/public/avatars/")
            .addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
            .flatMap(URL.init(string:)) {
            return publicURL
        }
        return url
    }

    private static func fetchData(from url: URL, session: URLSession) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        if SupabaseStorageAccess.isPostsBucketURL(url) {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return (data, response)
            }
            if let fallback = MediaURLResolver.playbackFallbackConfiguration(for: url) {
                var fallbackRequest = URLRequest(url: fallback.url)
                fallbackRequest.cachePolicy = .returnCacheDataElseLoad
                return try await session.data(for: fallbackRequest)
            }
            return (data, response)
        }

        let configuration = await MediaURLResolver.playbackConfiguration(for: url)
        request = URLRequest(url: configuration.url)
        request.cachePolicy = .returnCacheDataElseLoad
        if let headers = configuration.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode),
           let fallback = MediaURLResolver.playbackFallbackConfiguration(for: configuration.url) {
            var fallbackRequest = URLRequest(url: fallback.url)
            fallbackRequest.cachePolicy = .returnCacheDataElseLoad
            return try await session.data(for: fallbackRequest)
        }
        return (data, response)
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    var maxPixelSize: CGFloat = 900
    var contentMode: ContentMode = .fill
    var placeholder: AnyView?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let placeholder {
                placeholder
            } else {
                Theme.canvasMuted
            }
        }
        .task(id: taskID) {
            guard let url else {
                image = nil
                return
            }
            if image == nil {
                image = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
            }
        }
    }

    private var taskID: String {
        guard let url else { return "nil" }
        return "\(url.absoluteString)|\(Int(maxPixelSize))"
    }
}