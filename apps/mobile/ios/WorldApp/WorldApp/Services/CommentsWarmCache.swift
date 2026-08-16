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
    /// Uses a small first page so warm never blocks for hundreds of R2 comments.
    /// Literal default avoids Swift 6 nonisolated default-arg isolation on PostsService.
    func warm(_ postID: String, limit: Int = 48) {
        let key = normalized(postID)
        guard !key.isEmpty else { return }
        if cache[key] != nil { return }
        if inflight[key] != nil { return }
        let task = Task { [weak self] in
            let loaded = (try? await PostsService.shared.listComments(
                key,
                limit: limit,
                resolveOrigin: true
            )) ?? []
            await MainActor.run {
                self?.store(key, comments: loaded)
                self?.inflight[key] = nil
            }
            return loaded
        }
        inflight[key] = task
    }

    /// Await warm/network; always returns (empty on failure).
    func load(
        _ postID: String,
        limit: Int = 48
    ) async -> [PostComment] {
        let key = normalized(postID)
        guard !key.isEmpty else { return [] }
        if let hit = cache[key] { return hit }
        if let task = inflight[key] {
            return await task.value
        }
        warm(key, limit: limit)
        if let task = inflight[key] {
            return await task.value
        }
        return cache[key] ?? []
    }

    /// Fast first page + optional background top-up (Hubs watch / feed expand).
    func loadProgressive(
        _ postID: String,
        firstPage: Int = 48,
        backgroundLimit: Int = 400
    ) async -> [PostComment] {
        let key = normalized(postID)
        guard !key.isEmpty else { return [] }
        if let hit = cache[key], !hit.isEmpty {
            // Already warm — refresh in background without blocking UI.
            if hit.count < backgroundLimit {
                Task { await self.refreshInBackground(key, limit: backgroundLimit) }
            }
            return hit
        }
        let first = await load(key, limit: firstPage)
        if first.count >= firstPage {
            Task { await self.refreshInBackground(key, limit: backgroundLimit) }
        }
        return first
    }

    private func refreshInBackground(_ postID: String, limit: Int) async {
        let fresh = (try? await PostsService.shared.listComments(
            postID,
            limit: limit,
            resolveOrigin: true
        )) ?? []
        guard !fresh.isEmpty else { return }
        // Only replace if we got more (or equal) — never shrink a fuller warm thread.
        if let existing = cache[postID], existing.count > fresh.count { return }
        store(postID, comments: fresh)
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
