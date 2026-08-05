import CryptoKit
import ImageIO
import SwiftUI
import UIKit

/// Fast image pipeline: memory first, disk/network off the main thread.
/// Never blocks scroll — decoding and file I/O run in the background.
/// Caps concurrent network loads so first-scroll avatar storms don't jank.
/// Swift 6–safe: no NSLock in async contexts; string keys only.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let inflight = InflightTable()
    /// Slightly higher concurrency so Hubs shelf thumbs fill in while scrolling.
    private let downloadGate = DownloadGate(maxConcurrent: 6)
    private let session: URLSession
    private let diskDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.matterya.imagecache.io", qos: .utility)

    private init() {
        memoryCache.countLimit = 280
        memoryCache.totalCostLimit = 80 * 1024 * 1024

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 14
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.waitsForConnectivity = false
        configuration.urlCache = URLCache(
            memoryCapacity: 40 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDirectory = base.appendingPathComponent("MatteryaImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    static func configureSharedCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 40 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
    }

    /// Memory only — safe to call from the main thread during scroll.
    func imageIfCached(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let fetchURL = Self.cacheableURL(from: url)
        let key = cacheKey(for: fetchURL, maxPixelSize: maxPixelSize)
        return memoryCache.object(forKey: key as NSString)
    }

    /// Background prefetch for upcoming feed rows.
    /// During a fling, only top up a few URLs so we don't stampede the network.
    func prefetch(_ urls: [URL], maxPixelSize: CGFloat = 420) {
        let cap = ScrollBudget.isFlinging ? 4 : 16
        let unique = Array(Set(urls.map(\.absoluteString))).prefix(cap).compactMap(URL.init(string:))
        let priority: TaskPriority = ScrollBudget.isFlinging ? .background : .utility
        for url in unique {
            if imageIfCached(for: url, maxPixelSize: maxPixelSize) != nil { continue }
            Task.detached(priority: priority) {
                _ = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
            }
        }
    }

    func prefetchPostThumbnails(_ posts: [CountryPost], maxPixelSize: CGFloat = 420) {
        let urls = posts.compactMap { post -> URL? in
            post.posterImageURL ?? post.feedImageURL ?? post.thumbURL.flatMap(URL.init(string:))
        }
        prefetch(urls, maxPixelSize: maxPixelSize)
    }

    /// Feed cold-start warm: avatars + media so first scroll hits memory.
    func prefetchFeedMedia(_ posts: [CountryPost], maxPixelSize: CGFloat = 420) {
        // Avatars first — every feed card has one; media is secondary for text-heavy demos.
        // Must match AvatarView feed maxPixelSize (size 36 → max(72, 72) = 72) or cache misses.
        let avatarMax: CGFloat = 72
        let mediaURLs = posts.compactMap {
            $0.posterImageURL ?? $0.feedImageURL ?? $0.thumbURL.flatMap(URL.init(string:))
        }
        let avatarURLs = posts.compactMap { post -> URL? in
            guard let raw = post.author?.avatarURL else { return nil }
            if let normalized = MediaService.normalizedAvatarURL(raw), let url = URL(string: normalized) {
                return url
            }
            return URL(string: raw)
        }
        prefetch(avatarURLs, maxPixelSize: avatarMax)
        prefetch(mediaURLs, maxPixelSize: maxPixelSize)
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let fetchURL = Self.cacheableURL(from: url)
        let key = cacheKey(for: fetchURL, maxPixelSize: maxPixelSize)

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Disk off main thread.
        if let diskImage = await loadFromDiskAsync(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString, cost: estimateCost(diskImage))
            return diskImage
        }

        if let existing = await inflight.task(for: key) {
            return await existing.value
        }

        let cache = self
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            await cache.downloadGate.acquire()
            defer {
                Task { await cache.downloadGate.release() }
            }
            do {
                let (data, response) = try await Self.fetchData(from: fetchURL, session: cache.session)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    return nil
                }
                guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                    return nil
                }
                cache.memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
                cache.saveToDiskAsync(image: image, key: key)
                return image
            } catch {
                return nil
            }
        }

        await inflight.set(task, for: key)
        let image = await task.value
        await inflight.set(nil, for: key)
        return image
    }

    private func estimateCost(_ image: UIImage) -> Int {
        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)
        return max(1, w * h * 4)
    }

    private func cacheKey(for url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)|\(Int(maxPixelSize))"
    }

    private func diskFileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appendingPathComponent("\(hex).jpg")
    }

    private func loadFromDiskAsync(key: String) async -> UIImage? {
        let path = diskFileURL(for: key)
        return await withCheckedContinuation { cont in
            ioQueue.async {
                guard let data = try? Data(contentsOf: path),
                      let image = UIImage(data: data)
                else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: image)
            }
        }
    }

    private func saveToDiskAsync(image: UIImage, key: String) {
        let path = diskFileURL(for: key)
        ioQueue.async {
            guard let data = image.jpegData(compressionQuality: 0.82) else { return }
            try? data.write(to: path, options: .atomic)
        }
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

        // Dicebear / plain HTTPS — skip MediaURLResolver (no need for Archive CDN logic).
        let host = url.host?.lowercased() ?? ""
        if host.contains("dicebear.com") || host.contains("gravatar.com") || host.contains("googleusercontent.com") {
            return try await session.data(for: request)
        }

        let configuration = await MediaURLResolver.playbackConfiguration(for: url)
        request = URLRequest(url: configuration.url)
        request.cachePolicy = .returnCacheDataElseLoad
        if let headers = configuration.headers {
            for (headerKey, value) in headers {
                request.setValue(value, forHTTPHeaderField: headerKey)
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

/// Async-safe map of in-flight loads (replaces NSLock for Swift 6).
private actor InflightTable {
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    func task(for key: String) -> Task<UIImage?, Never>? {
        tasks[key]
    }

    func set(_ task: Task<UIImage?, Never>?, for key: String) {
        if let task {
            tasks[key] = task
        } else {
            tasks.removeValue(forKey: key)
        }
    }
}

/// Caps concurrent network image downloads so cold-scroll doesn't flood MainActor updates.
private actor DownloadGate {
    private let maxConcurrent: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
        // Continuation resumes when a slot opens; claim it.
        active += 1
    }

    func release() {
        active = max(0, active - 1)
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        next.resume()
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    var maxPixelSize: CGFloat = 720
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
        .onAppear {
            ScrollBudget.noteCellAppear()
            // Memory only — never hit disk/network synchronously during scroll.
            guard image == nil, let url else { return }
            if let cached = ImageCache.shared.imageIfCached(for: url, maxPixelSize: maxPixelSize) {
                image = cached
            }
        }
        .task(id: taskID) {
            guard let url else {
                image = nil
                return
            }
            if let cached = ImageCache.shared.imageIfCached(for: url, maxPixelSize: maxPixelSize) {
                if image == nil { image = cached }
                return
            }
            // Fast fling: wait briefly. If the cell is recycled, .task cancels and we never download.
            // Settled scroll: short wait so first paint stays snappy.
            let delayNs: UInt64 = ScrollBudget.isFlinging ? 90_000_000 : 28_000_000
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }

            if let cached = ImageCache.shared.imageIfCached(for: url, maxPixelSize: maxPixelSize) {
                if image == nil { image = cached }
                return
            }
            if image == nil {
                let loaded = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
                if !Task.isCancelled {
                    image = loaded
                }
            }
        }
    }

    private var taskID: String {
        guard let url else { return "nil" }
        return "\(url.absoluteString)|\(Int(maxPixelSize))"
    }
}

/// Tracks rapid cell churn so we can treat a fling differently from a settled scroll.
enum ScrollBudget: Sendable {
    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var lastAppear = Date.distantPast
    nonisolated(unsafe) private static var burst = 0
    nonisolated(unsafe) private static var flingUntil = Date.distantPast

    /// Call from feed/hubs row or image `onAppear`.
    nonisolated static func noteCellAppear() {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        if now.timeIntervalSince(lastAppear) < 0.07 {
            burst += 1
        } else {
            burst = max(0, burst - 1)
        }
        lastAppear = now
        // 4+ cells in quick succession ≈ finger fling / deceleration.
        if burst >= 4 {
            flingUntil = now.addingTimeInterval(0.35)
        }
    }

    nonisolated static var isFlinging: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date() < flingUntil || burst >= 4
    }
}
