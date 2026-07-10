import ImageIO
import SwiftUI
import UIKit

@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private var inflight = [NSURL: Task<UIImage?, Never>]()
    private let session: URLSession

    private init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 64 * 1024 * 1024

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    static func configureSharedCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let key = url as NSURL
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        if let existing = inflight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            do {
                let (data, response) = try await Self.fetchData(from: url, session: session)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    return nil
                }
                guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                    return nil
                }
                let cost = data.count
                memoryCache.setObject(image, forKey: key, cost: cost)
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

    private static func fetchData(from url: URL, session: URLSession) async throws -> (Data, URLResponse) {
        let configuration = await MediaURLResolver.playbackConfiguration(for: url)
        var request = URLRequest(url: configuration.url)
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
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
        }
    }
}