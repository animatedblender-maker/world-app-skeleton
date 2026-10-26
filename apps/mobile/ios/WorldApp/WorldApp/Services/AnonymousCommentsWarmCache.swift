import Foundation

/// In-memory Masquerade comments warm cache — paint threads without a spinner.
@MainActor
final class AnonymousCommentsWarmCache {
    static let shared = AnonymousCommentsWarmCache()

    private var cache: [String: [AnonymousComment]] = [:]
    private var inflight: [String: Task<[AnonymousComment], Never>] = [:]
    private let maxEntries = 64

    private init() {}

    func cached(_ postID: String) -> [AnonymousComment]? {
        let key = normalized(postID)
        guard !key.isEmpty, let hit = cache[key], !hit.isEmpty else { return nil }
        return hit
    }

    func warm(_ postID: String, limit: Int = 40) {
        let key = normalized(postID)
        guard !key.isEmpty else { return }
        if let hit = cache[key], !hit.isEmpty { return }
        if inflight[key] != nil { return }
        let task = Task { [weak self] in
            let page = try? await AnonymousService.listComments(postId: key, limit: limit)
            let loaded = page?.items ?? []
            await MainActor.run {
                if !loaded.isEmpty {
                    self?.store(key, comments: loaded)
                }
                self?.inflight[key] = nil
            }
            return loaded
        }
        inflight[key] = task
    }

    func load(_ postID: String, limit: Int = 40) async -> [AnonymousComment] {
        let key = normalized(postID)
        guard !key.isEmpty else { return [] }
        if let hit = cache[key], !hit.isEmpty { return hit }
        if let task = inflight[key] {
            return await task.value
        }
        warm(key, limit: limit)
        if let task = inflight[key] {
            return await task.value
        }
        return cache[key] ?? []
    }

    func store(_ postID: String, comments: [AnonymousComment]) {
        let key = normalized(postID)
        guard !key.isEmpty else { return }
        if cache[key] == nil, cache.count >= maxEntries, let first = cache.keys.first {
            cache.removeValue(forKey: first)
        }
        cache[key] = comments
    }

    func invalidate(_ postID: String) {
        let key = normalized(postID)
        cache.removeValue(forKey: key)
        inflight[key]?.cancel()
        inflight[key] = nil
    }

    private func normalized(_ postID: String) -> String {
        postID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
