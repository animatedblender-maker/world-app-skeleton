import Foundation

/// In-memory + short disk warm cache for Masquerade comments — paint threads without waiting.
@MainActor
final class AnonymousCommentsWarmCache {
    static let shared = AnonymousCommentsWarmCache()

    private var cache: [String: [AnonymousComment]] = [:]
    private var inflight: [String: Task<[AnonymousComment], Never>] = [:]
    private let maxEntries = 64
    private let diskKey = "matterya.anonymous.comments.warm.v2"
    private let diskMaxPosts = 24

    private init() {
        hydrateFromDisk()
    }

    func cached(_ postID: String) -> [AnonymousComment]? {
        let key = normalized(postID)
        guard !key.isEmpty, let hit = cache[key], !hit.isEmpty else { return nil }
        return hit
    }

    func warm(_ postID: String, limit: Int = 80) {
        let key = normalized(postID)
        guard !key.isEmpty else { return }
        if let hit = cache[key], !hit.isEmpty { return }
        if inflight[key] != nil { return }
        let task = Task { [weak self] in
            let page = try? await AnonymousService.listComments(postId: key, limit: limit)
            let loaded = page?.items ?? []
            await MainActor.run {
                guard let self else { return }
                if !loaded.isEmpty {
                    self.store(key, comments: loaded)
                }
                self.inflight[key] = nil
            }
            return loaded
        }
        inflight[key] = task
    }

    /// Prefetch several visible feed posts so open feels instant.
    func warmMany(_ postIDs: [String], limitEach: Int = 80) {
        for id in postIDs.prefix(12) {
            warm(id, limit: limitEach)
        }
    }

    func load(_ postID: String, limit: Int = 80) async -> [AnonymousComment] {
        let key = normalized(postID)
        guard !key.isEmpty else { return [] }
        if let hit = cache[key], !hit.isEmpty { return hit }
        if let task = inflight[key] {
            let loaded = await task.value
            if !loaded.isEmpty { return loaded }
        }
        warm(key, limit: limit)
        if let task = inflight[key] {
            let loaded = await task.value
            if !loaded.isEmpty { return loaded }
        }
        return cache[key] ?? []
    }

    func store(_ postID: String, comments: [AnonymousComment]) {
        let key = normalized(postID)
        guard !key.isEmpty, !comments.isEmpty else { return }
        if cache[key] == nil, cache.count >= maxEntries, let first = cache.keys.first {
            cache.removeValue(forKey: first)
        }
        cache[key] = comments
        persistToDisk()
    }

    func invalidate(_ postID: String) {
        let key = normalized(postID)
        cache.removeValue(forKey: key)
        inflight[key]?.cancel()
        inflight[key] = nil
        persistToDisk()
    }

    private func normalized(_ postID: String) -> String {
        postID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hydrateFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: diskKey),
              let decoded = try? JSONDecoder().decode([String: [AnonymousComment]].self, from: data)
        else { return }
        for (key, comments) in decoded where !comments.isEmpty {
            cache[key] = comments
        }
    }

    private func persistToDisk() {
        let sliced = Dictionary(uniqueKeysWithValues: cache.prefix(diskMaxPosts).map { ($0.key, $0.value) })
        guard let data = try? JSONEncoder().encode(sliced) else { return }
        UserDefaults.standard.set(data, forKey: diskKey)
    }
}
