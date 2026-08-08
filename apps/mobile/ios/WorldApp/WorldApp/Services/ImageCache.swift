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
    /// High concurrency so Hubs For you thumbs keep filling while scrolling far.
    private let downloadGate = DownloadGate(maxConcurrent: 20)
    private let session: URLSession
    private let diskDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.matterya.imagecache.io", qos: .utility)
    /// Sizes we may have prefetched — used to hit memory even if display size differs slightly.
    private static let sizeBuckets: [CGFloat] = [240, 280, 320, 360, 420, 480, 720]

    private init() {
        memoryCache.countLimit = 900
        memoryCache.totalCostLimit = 180 * 1024 * 1024

        let configuration = URLSessionConfiguration.default
        // Short timeouts — fail fast and fall back to services/img rather than hang on .thumbs.
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        configuration.httpMaximumConnectionsPerHost = 12
        configuration.waitsForConnectivity = false
        configuration.urlCache = URLCache(
            memoryCapacity: 80 * 1024 * 1024,
            diskCapacity: 500 * 1024 * 1024
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
    /// Accepts any prefetched size bucket for the same URL so list/prefetch size mismatches still hit.
    func imageIfCached(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let fetchURL = Self.cacheableURL(from: url)
        let primary = cacheKey(for: fetchURL, maxPixelSize: maxPixelSize)
        if let hit = memoryCache.object(forKey: primary as NSString) { return hit }
        for size in Self.sizeBuckets where Int(size) != Int(maxPixelSize) {
            let key = cacheKey(for: fetchURL, maxPixelSize: size)
            if let hit = memoryCache.object(forKey: key as NSString) { return hit }
        }
        return nil
    }

    /// Background prefetch for upcoming feed / Hubs rows.
    /// - Parameter aggressive: Hubs For you far-scroll — larger window, higher priority.
    func prefetch(_ urls: [URL], maxPixelSize: CGFloat = 420, aggressive: Bool = false) {
        let cap: Int
        if aggressive {
            // Keep warming far ahead even while flinging — blank For you was from starving this.
            cap = ScrollBudget.isFlinging ? 28 : 48
        } else {
            cap = ScrollBudget.isFlinging ? 10 : 24
        }
        let unique = Array(Set(urls.map(\.absoluteString))).prefix(cap).compactMap(URL.init(string:))
        let priority: TaskPriority = aggressive
            ? .userInitiated
            : (ScrollBudget.isFlinging ? .utility : .userInitiated)
        for url in unique {
            if imageIfCached(for: url, maxPixelSize: maxPixelSize) != nil { continue }
            Task.detached(priority: priority) {
                _ = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
            }
        }
    }

    func prefetchPostThumbnails(_ posts: [CountryPost], maxPixelSize: CGFloat = 420, aggressive: Bool = false) {
        let urls = posts.compactMap { MediaURLResolver.hubsListPosterURL(for: $0) }
        prefetch(urls, maxPixelSize: maxPixelSize, aggressive: aggressive)
    }

    /// Hubs For you: prefetch a sliding window around `index` (behind + ahead).
    func prefetchHubsWindow(
        posts: [CountryPost],
        around index: Int,
        behind: Int = 6,
        ahead: Int = 24,
        maxPixelSize: CGFloat = YouTubeMediaLayout.hubsListThumbMaxPixel
    ) {
        guard !posts.isEmpty else { return }
        let lo = max(0, index - behind)
        let hi = min(posts.count, index + ahead + 1)
        guard lo < hi else { return }
        prefetchPostThumbnails(Array(posts[lo..<hi]), maxPixelSize: maxPixelSize, aggressive: true)
    }

    /// Prefetch an entire hub_slug shelf (category chip) for instant filter switches.
    func prefetchHubSlug(
        _ slug: String,
        from posts: [CountryPost],
        limit: Int = 48,
        maxPixelSize: CGFloat = YouTubeMediaLayout.hubsListThumbMaxPixel
    ) {
        let needle = slug.lowercased()
        let matched = posts.filter { post in
            let s = (post.hubSlug ?? post.externalRefID ?? "").lowercased()
            return s == needle || s.hasPrefix(needle + "_")
        }
        prefetchPostThumbnails(Array(matched.prefix(limit)), maxPixelSize: maxPixelSize, aggressive: true)
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
        if let hit = imageIfCached(for: url, maxPixelSize: maxPixelSize) {
            return hit
        }

        let fetchURL = Self.cacheableURL(from: url)
        let key = cacheKey(for: fetchURL, maxPixelSize: maxPixelSize)

        // Disk off main thread (exact key + any size-bucket key for this URL).
        if let diskImage = await loadFromDiskAsync(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString, cost: estimateCost(diskImage))
            return diskImage
        }
        for size in Self.sizeBuckets where Int(size) != Int(maxPixelSize) {
            let altKey = cacheKey(for: fetchURL, maxPixelSize: size)
            if let diskImage = await loadFromDiskAsync(key: altKey) {
                memoryCache.setObject(diskImage, forKey: key as NSString, cost: estimateCost(diskImage))
                return diskImage
            }
        }

        if let existing = await inflight.task(for: key) {
            return await existing.value
        }

        let cache = self
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            await cache.downloadGate.acquire()
            defer {
                Task { await cache.downloadGate.release() }
            }
            // Primary URL, then Archive services/img fallback when nested thumbs fail/timeout.
            let candidates = Self.fetchCandidates(for: fetchURL)
            for candidate in candidates {
                do {
                    let (data, response) = try await Self.fetchData(from: candidate, session: cache.session)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continue
                    }
                    guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                        continue
                    }
                    // Store under the *requested* URL key so the list hits even if we used a fallback host.
                    cache.memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
                    cache.saveToDiskAsync(image: image, key: key)
                    return image
                } catch {
                    continue
                }
            }
            return nil
        }

        await inflight.set(task, for: key)
        let image = await task.value
        await inflight.set(nil, for: key)
        return image
    }

    /// Primary + Archive services/img fallback (when handed a slow `.thumbs` download URL).
    private static func fetchCandidates(for url: URL) -> [URL] {
        var list: [URL] = [url]
        let raw = url.absoluteString
        if raw.contains("archive.org"),
           !raw.contains("/services/img/"),
           let id = MediaURLResolver.archiveItemIdentifier(from: raw),
           let alt = URL(string: "https://archive.org/services/img/\(id)"),
           alt != url {
            list.insert(alt, at: 0) // prefer services/img first
        }
        return list
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
        // Archive.org often rate-limits anonymous clients without a UA.
        request.setValue(
            "MatteryaHubs/1.0 (iOS; +https://matterya.com)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

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

        let host = url.host?.lowercased() ?? ""

        // Thumbnails / posters: NEVER run Archive video CDN resolution (Range GET + redirect
        // storms). That path was starving For you thumbs and janking scroll under the player.
        if MediaURLResolver.isImageURL(url)
            || host.contains("dicebear.com")
            || host.contains("gravatar.com")
            || host.contains("googleusercontent.com")
            || host.contains("cloudflare")
            || host.contains("r2.cloudflarestorage.com") {
            return try await session.data(for: request)
        }

        // Archive image hosts without extension (rare) — still fetch directly.
        if host.contains("archive.org"), !MediaURLResolver.isVideoURL(url) {
            // Prefer services/img when handed a /download/ page-ish URL.
            if let id = MediaURLResolver.archiveItemIdentifier(from: url.absoluteString),
               let imgURL = URL(string: "https://archive.org/services/img/\(id)"),
               imgURL != url {
                var imgReq = request
                imgReq.url = imgURL
                if let (data, response) = try? await session.data(for: imgReq),
                   let http = response as? HTTPURLResponse,
                   (200...299).contains(http.statusCode) {
                    return (data, response)
                }
            }
            return try await session.data(for: request)
        }

        // Remaining (signed video posters etc.): optional auth headers only — no Archive CDN.
        let configuration = await MediaURLResolver.playbackConfiguration(for: url)
        // If playback config rewrote to a video CDN, still try original for image bytes.
        if MediaURLResolver.isImageURL(configuration.url) || configuration.url == url {
            request = URLRequest(url: configuration.url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue(
                "MatteryaHubs/1.0 (iOS; +https://matterya.com)",
                forHTTPHeaderField: "User-Agent"
            )
            if let headers = configuration.headers {
                for (headerKey, value) in headers {
                    request.setValue(value, forHTTPHeaderField: headerKey)
                }
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
    @State private var loadedURL: String?

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
            guard let url else { return }
            if image != nil, loadedURL == url.absoluteString { return }
            if let cached = ImageCache.shared.imageIfCached(for: url, maxPixelSize: maxPixelSize) {
                image = cached
                loadedURL = url.absoluteString
            }
        }
        .task(id: taskID) {
            guard let url else {
                image = nil
                loadedURL = nil
                return
            }
            // Keep prior frame while a new URL loads (reduces flash on recycle).
            if loadedURL != url.absoluteString {
                if let cached = ImageCache.shared.imageIfCached(for: url, maxPixelSize: maxPixelSize) {
                    image = cached
                    loadedURL = url.absoluteString
                    return
                }
            } else if image != nil {
                return
            }
            let loaded = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
            // Apply even if the task was cancelled after the download finished —
            // SwiftUI cancels .task on fling; dropping the result left blank cells.
            if let loaded {
                image = loaded
                loadedURL = url.absoluteString
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
