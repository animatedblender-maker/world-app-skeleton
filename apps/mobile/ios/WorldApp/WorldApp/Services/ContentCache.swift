import Foundation

enum ContentCacheKey: String, CaseIterable {
    case homeFeed
    case livingVideos
    case savedPosts
    case profilePosts
    case profileCountryCode
    case currentProfile
}

@MainActor
final class ContentCache {
    static let shared = ContentCache()

    private let freshTTL: TimeInterval = 5 * 60
    private let staleTTL: TimeInterval = 24 * 60 * 60
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var memoryPosts: [ContentCacheKey: CachedPostList] = [:]
    private var memoryProfileCountryCode: String?
    private var memoryProfile: Profile?
    private var memoryTimestamps: [ContentCacheKey: Date] = [:]

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
        restoreFromDisk()
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
        guard let posts = memoryPosts[key]?.posts, !posts.isEmpty else { return nil }
        return posts
    }

    func setPosts(_ posts: [CountryPost], for key: ContentCacheKey) {
        guard !posts.isEmpty else {
            invalidate(key)
            return
        }
        let entry = CachedPostList(savedAt: Date(), posts: posts)
        memoryPosts[key] = entry
        memoryTimestamps[key] = entry.savedAt
        persist(entry, for: key)
    }

    func isFresh(_ key: ContentCacheKey) -> Bool {
        guard let entry = memoryPosts[key], !entry.posts.isEmpty else { return false }
        return Date().timeIntervalSince(entry.savedAt) < freshTTL
    }

    func hasStale(_ key: ContentCacheKey) -> Bool {
        guard let savedAt = memoryTimestamps[key] ?? memoryPosts[key]?.savedAt else { return false }
        return Date().timeIntervalSince(savedAt) < staleTTL
    }

    func invalidate(_ keys: ContentCacheKey...) {
        for key in keys {
            memoryPosts[key] = nil
            memoryTimestamps[key] = nil
            try? FileManager.default.removeItem(at: fileURL(for: key))
        }
    }

    func invalidateAllFeeds() {
        invalidate(.homeFeed, .livingVideos, .profilePosts)
    }

    private func restoreFromDisk() {
        if let profile: Profile = load(.currentProfile) {
            memoryProfile = profile
            memoryProfileCountryCode = profile.countryCode?.uppercased()
        } else if let code: String = load(.profileCountryCode) {
            memoryProfileCountryCode = code
        }
        for key in [ContentCacheKey.homeFeed, .livingVideos, .savedPosts, .profilePosts] {
            guard let entry: CachedPostList = load(key) else { continue }
            guard !entry.posts.isEmpty else {
                try? FileManager.default.removeItem(at: fileURL(for: key))
                continue
            }
            memoryPosts[key] = entry
            memoryTimestamps[key] = entry.savedAt
        }
    }

    private func fileURL(for key: ContentCacheKey) -> URL {
        directoryURL.appendingPathComponent("\(key.rawValue).json")
    }

    private func persist<T: Encodable>(_ value: T, for key: ContentCacheKey) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    private func load<T: Decodable>(_ key: ContentCacheKey) -> T? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}