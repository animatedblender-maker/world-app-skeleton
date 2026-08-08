import Foundation

enum ContentCacheKey: String, CaseIterable {
    /// Bump suffix whenever feed identity changes (kills stale Reddit disk cache).
    case homeFeed = "homeFeed.v6_backend_only_no_reddit"
    case livingVideos
    case savedPosts
    case profilePosts
    case profileCountryCode
    case currentProfile
}

/// Disk + memory cache for feeds.
///
/// **Smoothness rules:**
/// - Never decode megabyte feed JSON on the main thread at launch (that froze login typing).
/// - Cap how many posts we persist / hold (scroll load-more is the long tail).
/// - Profile is tiny and restored eagerly; feed lists restore lazily / in background.
@MainActor
final class ContentCache {
    static let shared = ContentCache()

    /// Hard cap for any feed list on disk/memory — keeps encode/decode snappy.
    static let maxCachedPosts = 48

    private let freshTTL: TimeInterval = 5 * 60
    private let staleTTL: TimeInterval = 24 * 60 * 60
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var memoryPosts: [ContentCacheKey: CachedPostList] = [:]
    private var memoryProfileCountryCode: String?
    private var memoryProfile: Profile?
    private var memoryTimestamps: [ContentCacheKey: Date] = [:]
    private var feedKeysLoadedFromDisk: Set<ContentCacheKey> = []

    private let directoryURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MatteryaContentCache", isDirectory: true)
    }()

    private struct CachedPostList: Codable {
        let savedAt: Date
        let posts: [CountryPost]
    }

    private init() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        // Profile only — never bulk-decode homeFeed/livingVideos here (main-thread freeze).
        restoreProfileFromDisk()
        // Drop oversized legacy cache files so the next load is cheap.
        Task(priority: .utility) {
            await Self.pruneOversizedFiles(in: directoryURL)
        }
    }

    func cachedProfile() -> Profile? {
        memoryProfile
    }

    func setProfile(_ profile: Profile?) {
        memoryProfile = profile
        setProfileCountryCode(profile?.countryCode)
        guard let profile else {
            try? FileManager.default.removeItem(at: fileURL(for: .currentProfile))
            return
        }
        persist(profile, for: .currentProfile)
    }

    func profileCountryCode() -> String? {
        memoryProfileCountryCode
    }

    func setProfileCountryCode(_ code: String?) {
        let normalized = code?.uppercased()
        memoryProfileCountryCode = normalized
        guard let normalized else {
            try? FileManager.default.removeItem(at: fileURL(for: .profileCountryCode))
            return
        }
        persist(normalized, for: .profileCountryCode)
    }

    func posts(for key: ContentCacheKey) -> [CountryPost]? {
        ensureFeedLoaded(key)
        guard let posts = memoryPosts[key]?.posts, !posts.isEmpty else { return nil }
        return posts
    }

    func setPosts(_ posts: [CountryPost], for key: ContentCacheKey) {
        guard !posts.isEmpty else {
            invalidate(key)
            return
        }
        // Cap — never write 800+ R2 rows to disk (killed launch decode).
        let trimmed = Array(posts.prefix(Self.maxCachedPosts))
        let entry = CachedPostList(savedAt: Date(), posts: trimmed)
        memoryPosts[key] = entry
        memoryTimestamps[key] = entry.savedAt
        feedKeysLoadedFromDisk.insert(key)
        // Persist off the hot path when possible.
        let url = fileURL(for: key)
        Task.detached(priority: .utility) {
            let enc = JSONEncoder()
            guard let data = try? enc.encode(entry) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func isFresh(_ key: ContentCacheKey) -> Bool {
        ensureFeedLoaded(key)
        guard let entry = memoryPosts[key], !entry.posts.isEmpty else { return false }
        return Date().timeIntervalSince(entry.savedAt) < freshTTL
    }

    func hasStale(_ key: ContentCacheKey) -> Bool {
        ensureFeedLoaded(key)
        guard let savedAt = memoryTimestamps[key] ?? memoryPosts[key]?.savedAt else { return false }
        return Date().timeIntervalSince(savedAt) < staleTTL
    }

    func invalidate(_ keys: ContentCacheKey...) {
        for key in keys {
            memoryPosts[key] = nil
            memoryTimestamps[key] = nil
            feedKeysLoadedFromDisk.remove(key)
            try? FileManager.default.removeItem(at: fileURL(for: key))
        }
    }

    func invalidateAllFeeds() {
        invalidate(.homeFeed, .livingVideos, .profilePosts)
    }

    // MARK: - Private

    private func restoreProfileFromDisk() {
        if let profile: Profile = loadSync(.currentProfile) {
            memoryProfile = profile
            memoryProfileCountryCode = profile.countryCode?.uppercased()
        } else if let code: String = loadSync(.profileCountryCode) {
            memoryProfileCountryCode = code
        }
    }

    /// Lazy load one feed key. Skips / deletes files that are absurdly large.
    private func ensureFeedLoaded(_ key: ContentCacheKey) {
        guard key == .homeFeed || key == .livingVideos || key == .savedPosts || key == .profilePosts else {
            return
        }
        guard !feedKeysLoadedFromDisk.contains(key) else { return }
        feedKeysLoadedFromDisk.insert(key)

        let url = fileURL(for: key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber
        else {
            // Missing file — mark loaded empty.
            return
        }
        // > 2 MB of JSON for a feed list is a bad cache (legacy full-catalog dumps).
        if size.intValue > 2_000_000 {
            try? FileManager.default.removeItem(at: url)
            #if DEBUG
            print("[ContentCache] pruned oversized \(key.rawValue) (\(size.intValue / 1024) KB)")
            #endif
            return
        }

        guard let entry: CachedPostList = loadSync(key) else { return }
        guard !entry.posts.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        // Trim legacy oversized entries in memory + rewrite small.
        if entry.posts.count > Self.maxCachedPosts {
            let trimmed = CachedPostList(
                savedAt: entry.savedAt,
                posts: Array(entry.posts.prefix(Self.maxCachedPosts))
            )
            memoryPosts[key] = trimmed
            memoryTimestamps[key] = trimmed.savedAt
            setPosts(trimmed.posts, for: key)
            return
        }
        memoryPosts[key] = entry
        memoryTimestamps[key] = entry.savedAt
    }

    private func fileURL(for key: ContentCacheKey) -> URL {
        directoryURL.appendingPathComponent("\(key.rawValue).json")
    }

    private func persist<T: Encodable>(_ value: T, for key: ContentCacheKey) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    private func loadSync<T: Decodable>(_ key: ContentCacheKey) -> T? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Background: delete any leftover multi‑MB feed dumps.
    nonisolated private static func pruneOversizedFiles(in directory: URL) async {
        let keys = [
            ContentCacheKey.homeFeed.rawValue,
            ContentCacheKey.livingVideos.rawValue,
            ContentCacheKey.savedPosts.rawValue,
            ContentCacheKey.profilePosts.rawValue,
        ]
        for name in keys {
            let url = directory.appendingPathComponent("\(name).json")
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber,
                  size.intValue > 2_000_000
            else { continue }
            try? FileManager.default.removeItem(at: url)
            #if DEBUG
            print("[ContentCache] background prune \(name) (\(size.intValue / 1024) KB)")
            #endif
        }
    }
}
