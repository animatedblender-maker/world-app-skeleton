import Foundation

/// In-memory comments warm cache so Chat / feed expand show threads instantly
/// (no spinner after tap). Populated on idle warm + tap-before-open.
@MainActor
final class CommentsWarmCache {
    static let shared = CommentsWarmCache()

    private var cache: [String: [PostComment]] = [:]
    private var inflight: [String: Task<[PostComment], Never>] = [:]
    private let maxEntries = 64

    private init() {}

    func cached(_ postID: String) -> [PostComment]? {
        let key = normalized(postID)
        guard !key.isEmpty else { return nil }
        return cache[key]
    }

    /// Fire-and-forget warm (tap Chat, idle on active Spark, feed card appear).
    func warm(_ postID: String) {
        let key = normalized(postID)
        guard !key.isEmpty else { return }
        if cache[key] != nil { return }
        if inflight[key] != nil { return }
        let task = Task { [weak self] in
            let loaded = (try? await PostsService.shared.listComments(key, limit: 2000)) ?? []
            await MainActor.run {
                self?.store(key, comments: loaded)
                self?.inflight[key] = nil
            }
            return loaded
        }
        inflight[key] = task
    }

    /// Await warm/network; always returns (empty on failure).
    func load(_ postID: String) async -> [PostComment] {
        let key = normalized(postID)
        guard !key.isEmpty else { return [] }
        if let hit = cache[key] { return hit }
        if let task = inflight[key] {
            return await task.value
        }
        warm(key)
        if let task = inflight[key] {
            return await task.value
        }
        return cache[key] ?? []
    }

    func store(_ postID: String, comments: [PostComment]) {
        let key = normalized(postID)
        guard !key.isEmpty else { return }
        if cache[key] == nil, cache.count >= maxEntries {
            // Drop an arbitrary oldest-ish entry (dict order is insertion-ish).
            if let first = cache.keys.first {
                cache.removeValue(forKey: first)
            }
        }
        cache[key] = comments
    }

    func invalidate(_ postID: String) {
        let key = normalized(postID)
        cache.removeValue(forKey: key)
        inflight[key]?.cancel()
        inflight[key] = nil
    }

    private func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
