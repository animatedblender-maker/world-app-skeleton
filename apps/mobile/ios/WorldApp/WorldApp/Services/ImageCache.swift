import CryptoKit
import ImageIO
import Observation
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
    /// Cap concurrent image loads — keep low so Feed+Hubs dual-mount never storms the radio.
    private let downloadGate = DownloadGate(maxConcurrent: 3)
    private let session: URLSession
    private let diskDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.matterya.imagecache.io", qos: .utility)
    /// Sizes we may have prefetched — used to hit memory even if display size differs slightly.
    private static let sizeBuckets: [CGFloat] = [240, 280, 320, 360, 420, 480, 720, 1080, 1440]

    private init() {
        memoryCache.countLimit = 120
        memoryCache.totalCostLimit = 32 * 1024 * 1024

        let configuration = URLSessionConfiguration.default
        // Short timeouts — fail fast and fall back to services/img rather than hang on .thumbs.
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.waitsForConnectivity = false
        configuration.urlCache = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 160 * 1024 * 1024
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDirectory = base.appendingPathComponent("MatteryaImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    static func configureSharedCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 160 * 1024 * 1024
        )
    }

    /// Memory only — safe to call from the main thread during scroll.
    /// May reuse a **larger-or-equal** size bucket for the same URL — never a smaller one
    /// (that made full-width feed photos look soft after a 420px prefetch).
    func imageIfCached(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let fetchURL = Self.cacheableURL(from: url)
        let want = Int(maxPixelSize)
        let primary = cacheKey(for: fetchURL, maxPixelSize: maxPixelSize)
        if let hit = memoryCache.object(forKey: primary as NSString) { return hit }
        for size in Self.sizeBuckets where Int(size) >= want && Int(size) != want {
            let key = cacheKey(for: fetchURL, maxPixelSize: size)
            if let hit = memoryCache.object(forKey: key as NSString) { return hit }
        }
        return nil
    }

    /// Background prefetch for upcoming feed / Hubs rows.
    /// - Parameter aggressive: settled scroll only — far-ahead warm. Mid-fling always stays tiny.
    func prefetch(_ urls: [URL], maxPixelSize: CGFloat = 420, aggressive: Bool = false) {
        let fling = ScrollBudget.isFlinging
        // Fast fling: starve the network so decode/download don't hitch the main thread.
        // Settled: tiny ahead window — Balanced light whole-app weight.
        let cap: Int
        if fling {
            cap = 2
        } else {
            cap = aggressive ? 5 : 4
        }
        let unique = Array(Set(urls.map(\.absoluteString))).prefix(cap).compactMap(URL.init(string:))
        let priority: TaskPriority = fling
            ? .background
            : (aggressive ? .utility : .utility)
        for url in unique {
            if imageIfCached(for: url, maxPixelSize: maxPixelSize) != nil { continue }
            Task.detached(priority: priority) {
                _ = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
            }
        }
    }

    func prefetchPostThumbnails(_ posts: [CountryPost], maxPixelSize: CGFloat = 420, aggressive: Bool = false) {
        var missingFrame0IDs: [String] = []
        let urls = posts.compactMap { post -> URL? in
            if let u = MediaURLResolver.hubsListPosterURL(for: post),
               MediaURLResolver.isUsablePosterURL(u) {
                return u
            }
            // Expired / missing thumb — must mint Frame 0 or shelves stay black forever.
            missingFrame0IDs.append(post.id)
            return nil
        }
        prefetch(urls, maxPixelSize: maxPixelSize, aggressive: aggressive)
        if !missingFrame0IDs.isEmpty {
            Task {
                await Frame0PosterResolver.shared.prefetch(postIDs: missingFrame0IDs)
            }
        }
    }

    /// Hubs For you / shelves — every visible card needs a poster. Balanced-light Feed caps
    /// (prefetch 4) left most hub rows black; this path warms a denser settled band + Frame0.
    func prefetchHubsListThumbnails(
        _ posts: [CountryPost],
        maxPixelSize: CGFloat = YouTubeMediaLayout.hubsListThumbMaxPixel
    ) {
        guard !posts.isEmpty else { return }
        var missingFrame0IDs: [String] = []
        let urls = posts.compactMap { post -> URL? in
            if let u = MediaURLResolver.hubsListPosterURL(for: post),
               MediaURLResolver.isUsablePosterURL(u) {
                return u
            }
            missingFrame0IDs.append(post.id)
            return nil
        }
        let fling = ScrollBudget.isFlinging
        // Cap is independent of how many poster URLs already resolve — when every
        // row needs Frame0, urls.count==0 used to zero the cap and leave black tiles.
        // Settled Hubs open/rails need a denser band so R2 long-form never stays black.
        let cap = fling ? 2 : 28
        let unique = Array(Set(urls.map(\.absoluteString))).prefix(min(cap, max(urls.count, 0)))
            .compactMap(URL.init(string:))
        let priority: TaskPriority = fling ? .background : .utility
        for url in unique {
            if imageIfCached(for: url, maxPixelSize: maxPixelSize) != nil { continue }
            Task.detached(priority: priority) {
                _ = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
            }
        }
        let frame0Source = missingFrame0IDs.isEmpty
            ? posts.map(\.id)
            : missingFrame0IDs
        let frame0IDs = Array(frame0Source.prefix(cap))
        if !frame0IDs.isEmpty {
            Task {
                await Frame0PosterResolver.shared.prefetch(postIDs: frame0IDs)
            }
        }
    }

    /// Hubs For you: prefetch a sliding window around `index` (behind + ahead).
    /// Settled-only callers pass a Feed-sized window; mid-fling stays tiny.
    func prefetchHubsWindow(
        posts: [CountryPost],
        around index: Int,
        behind: Int = 1,
        ahead: Int = 3,
        maxPixelSize: CGFloat = YouTubeMediaLayout.hubsListThumbMaxPixel
    ) {
        guard !posts.isEmpty else { return }
        let fling = ScrollBudget.isFlinging
        let useBehind = fling ? min(behind, 0) : min(behind, 1)
        let useAhead = fling ? min(ahead, 1) : min(ahead, 3)
        let lo = max(0, index - useBehind)
        let hi = min(posts.count, index + useAhead + 1)
        guard lo < hi else { return }
        // Dense hubs thumb path — Feed prefetchPostThumbnails caps left most cards black.
        prefetchHubsListThumbnails(
            Array(posts[lo..<hi]),
            maxPixelSize: maxPixelSize
        )
    }

    /// Prefetch an entire hub_slug shelf (category chip) for instant filter switches.
    func prefetchHubSlug(
        _ slug: String,
        from posts: [CountryPost],
        limit: Int = 16,
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
    /// Photos warm at ≥540 (matches FeedPinchZoomPhoto) so image cards stay scroll-light.
    /// Video posters stay at `maxPixelSize` (Frame0 / thumbs).
    func prefetchFeedMedia(_ posts: [CountryPost], maxPixelSize: CGFloat = 420) {
        // Avatars first — every feed card has one; media is secondary for text-heavy demos.
        // Must match AvatarView feed maxPixelSize (size 36 → max(72, 72) = 72) or cache misses.
        let avatarMax: CGFloat = 72
        // Fling callers pass 320 for posters; photos still need 540 so display hits memory.
        let photoMax: CGFloat = max(540, maxPixelSize)
        var missingFrame0IDs: [String] = []
        var photoURLs: [URL] = []
        var posterURLs: [URL] = []
        for post in posts {
            let isPhoto = PlayPlatformBridge.isWrittenHomePost(post)
                && !post.hasVideo
                && post.feedImageURL != nil
            if isPhoto, let url = post.feedImageURL, MediaURLResolver.isUsablePosterURL(url) {
                photoURLs.append(url)
                continue
            }
            let candidates = [
                MediaURLResolver.hubsListPosterURL(for: post),
                post.posterImageURL,
                post.feedImageURL,
                post.thumbURL.flatMap(URL.init(string:)),
            ]
            var hit = false
            for candidate in candidates {
                guard let url = candidate, MediaURLResolver.isUsablePosterURL(url) else { continue }
                posterURLs.append(url)
                hit = true
                break
            }
            if !hit {
                missingFrame0IDs.append(post.id)
            }
        }
        let avatarURLs = posts.compactMap { post -> URL? in
            guard let raw = post.author?.avatarURL else { return nil }
            if let normalized = MediaService.normalizedAvatarURL(raw), let url = URL(string: normalized) {
                return url
            }
            return URL(string: raw)
        }
        prefetch(avatarURLs, maxPixelSize: avatarMax)
        prefetch(photoURLs, maxPixelSize: photoMax)
        prefetch(posterURLs, maxPixelSize: maxPixelSize)
        if !missingFrame0IDs.isEmpty {
            Task {
                await Frame0PosterResolver.shared.prefetch(postIDs: missingFrame0IDs)
            }
        }
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        // Never fetch banned pub-*.r2.dev (CF 1010) — callers should fall through to Frame0.
        if MediaURLResolver.isBlockedR2PublicURL(url) { return nil }
        if !MediaURLResolver.isUsablePosterURL(url), MediaURLResolver.looksLikeR2HostedURL(url) {
            return nil
        }

        if let hit = imageIfCached(for: url, maxPixelSize: maxPixelSize) {
            return hit
        }

        let fetchURL = Self.cacheableURL(from: url)
        let key = cacheKey(for: fetchURL, maxPixelSize: maxPixelSize)
        let want = Int(maxPixelSize)

        // Disk: exact key, then only larger-or-equal buckets (never serve a soft 420 as 1080).
        if let diskImage = await loadFromDiskAsync(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString, cost: estimateCost(diskImage))
            return diskImage
        }
        for size in Self.sizeBuckets where Int(size) >= want && Int(size) != want {
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
            // Dead pub-*.r2.dev / expired R2 embeds — skip fetch so Frame0 can win.
            if MediaURLResolver.isBlockedR2PublicURL(url)
                || (!MediaURLResolver.isUsablePosterURL(url) && MediaURLResolver.looksLikeR2HostedURL(url)) {
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
            // Fast fling: wait longer — if the cell is recycled, .task cancels and we never download.
            // Feed photos (≥480) wait out the fling so decoding does not hitch scroll
            // (Sparks/Hubs cards skip this path and stay butter-smooth).
            let photoHeavy = maxPixelSize >= 480
            let delayNs: UInt64 = ScrollBudget.isFlinging
                ? (photoHeavy ? 180_000_000 : 110_000_000)
                : 24_000_000
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            if photoHeavy {
                // Still flinging after wait — skip apply; next settle .task will paint.
                while ScrollBudget.isFlinging {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard !Task.isCancelled else { return }
                }
            }
            if let cached = ImageCache.shared.imageIfCached(for: url, maxPixelSize: maxPixelSize) {
                image = cached
                loadedURL = url.absoluteString
                return
            }
            let loaded = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            // Avoid assigning a large bitmap mid-fling (main-thread hitch on meme cards).
            if photoHeavy, ScrollBudget.isFlinging { return }
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

/// Locks Home feed scrolling while a photo is pinched (Instagram-style).
@MainActor
@Observable
final class FeedPhotoZoomGate {
    static let shared = FeedPhotoZoomGate()
    private(set) var isZooming = false
    private var depth = 0

    func begin() {
        depth += 1
        isZooming = true
    }

    func end() {
        depth = max(0, depth - 1)
        if depth == 0 { isZooming = false }
    }
}

/// Feed photo: UIKit pinch (ScrollView swallows SwiftUI MagnificationGesture).
/// Zooms under the fingers; release springs back to 1×.
struct FeedPinchZoomPhoto: View {
    let url: URL
    /// Feed-width memes: 540 keeps scroll light; pinch still looks sharp on phone widths.
    var maxPixelSize: CGFloat = 540
    var contentMode: ContentMode = .fit
    var placeholder: AnyView = AnyView(Theme.canvasMuted)
    var onZoomingChanged: ((Bool) -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var announcedZooming = false

    private var isZooming: Bool { scale > 1.01 || announcedZooming }

    var body: some View {
        ZStack {
            Theme.canvasMuted
            if isZooming {
                Color.black.opacity(min(0.55, Double(max(scale, 1.15) - 1) * 0.35))
                    .allowsHitTesting(false)
            }
            CachedAsyncImage(
                url: url,
                maxPixelSize: maxPixelSize,
                contentMode: contentMode,
                placeholder: placeholder
            )
            .scaleEffect(scale)
            .offset(offset)
            .allowsHitTesting(false)
            // Pinch overlay must NOT steal 1-finger scroll (Sparks/Hubs stay smooth
            // because they have no UIKit hit layer). Overlay only claims 2-finger / zoom.
            FeedPhotoPinchOverlay(
                onBegan: {
                    setZooming(true)
                },
                onChanged: { next, pan in
                    let clamped = min(max(next, 1), 4)
                    setZooming(true)
                    scale = clamped
                    offset = pan
                },
                onEnded: {
                    withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
                        scale = 1
                        offset = .zero
                    } completion: {
                        setZooming(false)
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
        .contentShape(Rectangle())
        // Tap lives in SwiftUI so 1-finger scroll is never owned by the UIKit overlay.
        .onTapGesture {
            guard !isZooming else { return }
            onTap?()
        }
        .onDisappear {
            if announcedZooming {
                announcedZooming = false
                onZoomingChanged?(false)
                FeedPhotoZoomGate.shared.end()
            }
            scale = 1
            offset = .zero
        }
    }

    private func setZooming(_ zooming: Bool) {
        guard zooming != announcedZooming else { return }
        announcedZooming = zooming
        onZoomingChanged?(zooming)
        if zooming {
            FeedPhotoZoomGate.shared.begin()
        } else {
            FeedPhotoZoomGate.shared.end()
        }
    }
}

/// UIPinchGestureRecognizer host — two-finger pinch only; 1-finger scroll passes through.
private struct FeedPhotoPinchOverlay: UIViewRepresentable {
    var onBegan: () -> Void
    var onChanged: (_ scale: CGFloat, _ pan: CGSize) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> FeedPhotoPinchView {
        let view = FeedPhotoPinchView()
        view.isUserInteractionEnabled = true
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.isOpaque = false
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: FeedPhotoPinchView, context: Context) {
        uiView.onBegan = onBegan
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
    }
}

private final class FeedPhotoPinchView: UIView, UIGestureRecognizerDelegate {
    var onBegan: (() -> Void)?
    var onChanged: ((CGFloat, CGSize) -> Void)?
    var onEnded: (() -> Void)?

    private var pinch: UIPinchGestureRecognizer!
    private var pan: UIPanGestureRecognizer!
    private var baseScale: CGFloat = 1
    private var liveScale: CGFloat = 1
    private var panTranslation: CGSize = .zero
    private var pinchActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Clear — hitTest decides when we own touches (2-finger / zoom only).
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        isOpaque = false

        pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        pinch.cancelsTouchesInView = true
        pinch.delaysTouchesBegan = false
        pinch.delaysTouchesEnded = false
        addGestureRecognizer(pinch)

        pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        switch gr.state {
        case .began:
            pinchActive = true
            baseScale = max(liveScale, 1)
            panTranslation = .zero
            // Lock feed scroll immediately — before scale exceeds 1×.
            onBegan?()
            liveScale = min(max(baseScale * gr.scale, 1), 4)
            onChanged?(liveScale, panTranslation)
        case .changed:
            liveScale = min(max(baseScale * gr.scale, 1), 4)
            onChanged?(liveScale, panTranslation)
        case .ended, .cancelled, .failed:
            pinchActive = false
            liveScale = 1
            baseScale = 1
            panTranslation = .zero
            onEnded?()
        default:
            break
        }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard pinchActive || liveScale > 1.05 else { return }
        let t = gr.translation(in: self)
        panTranslation = CGSize(width: t.x, height: t.y)
        onChanged?(max(liveScale, 1.05), panTranslation)
        if gr.state == .ended || gr.state == .cancelled {
            panTranslation = .zero
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === pinch && other === pan { return true }
        if gestureRecognizer === pan && other === pinch { return true }
        // Until a real pinch starts, let the feed UIScrollView pan run freely.
        // Blocking it made image cards feel frozen while Sparks/Hubs stayed smooth.
        if !pinchActive, other is UIPanGestureRecognizer, other !== pan {
            return true
        }
        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        // Never make the feed scroll wait on our pinch/pan.
        false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === pinch {
            return gestureRecognizer.numberOfTouches >= 2
        }
        if gestureRecognizer === pan {
            return pinchActive || liveScale > 1.05
        }
        return true
    }
}

/// Tracks rapid cell churn so we can treat a fling differently from a settled scroll.
enum ScrollBudget: Sendable {
    private static let lock = NSLock()
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
        // 3+ cells in quick succession ≈ finger fling / deceleration.
        if burst >= 3 {
            flingUntil = now.addingTimeInterval(0.45)
        }
    }

    /// Sparks / UIScrollView: mark fling from drag velocity so warm/prefetch stay off the main thread.
    nonisolated static func noteScrollActivity(velocityY: CGFloat = 0, dragging: Bool = false) {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        if dragging || abs(velocityY) > 0.25 {
            // Hold through deceleration only — settle handlers call `noteSettled()` to clear.
            flingUntil = now.addingTimeInterval(0.55)
            burst = max(burst, 3)
        }
    }

    /// Call from Sparks DidEndDecelerating / DidEndDragging(no decelerate) before refill warm.
    /// Without this, `burst >= 3` kept `isFlinging` true forever after the first swipe
    /// (Sparks never decays burst via noteCellAppear) → every next clip cold-started.
    nonisolated static func noteSettled() {
        lock.lock()
        defer { lock.unlock() }
        flingUntil = .distantPast
        burst = 0
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .scrollBudgetDidSettle, object: nil)
        }
    }

    nonisolated static var isFlinging: Bool {
        lock.lock()
        defer { lock.unlock() }
        // Time-gated only. Burst alone must not stick after Sparks flings
        // (feed decays burst via noteCellAppear; Sparks does not).
        return Date() < flingUntil
    }
}
