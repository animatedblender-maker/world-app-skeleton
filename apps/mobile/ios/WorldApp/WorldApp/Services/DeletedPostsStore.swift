import Foundation

/// Durable tombstones for posts the user deleted.
///
/// Server delete can lag, fail for seed/non-UUID rows, or be overwritten by disk cache
/// on next launch. This store keeps deleted ids out of feed / profile / hubs rails
/// until the server catalog no longer returns them.
///
/// Thread-safe / nonisolated-friendly so array helpers and feed ranking can call it
/// without MainActor hops (Swift 6).
final class DeletedPostsStore: @unchecked Sendable {
    static let shared = DeletedPostsStore()

    private let defaultsKey = "posts.deleted.tombstones.v1"
    private let lock = NSLock()
    private var ids: Set<String> = []

    private init() {
        let raw = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        ids = Set(raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }

    func isDeleted(_ postID: String) -> Bool {
        let key = normalized(postID)
        guard !key.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(key)
    }

    func markDeleted(_ postID: String) {
        let key = normalized(postID)
        guard !key.isEmpty else { return }
        lock.lock()
        ids.insert(key)
        if ids.count > 4_000 {
            ids = Set(ids.suffix(3_500))
        }
        let snapshot = Array(ids)
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    func filter(_ posts: [CountryPost]) -> [CountryPost] {
        posts.filter { !isDeleted($0.id) }
    }

    private func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Array where Element == CountryPost {
    /// Drop posts the user has deleted (tombstone store).
    func excludingDeletedPosts() -> [CountryPost] {
        DeletedPostsStore.shared.filter(self)
    }
}
