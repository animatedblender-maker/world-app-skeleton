import Foundation

/// Durable tombstones for posts the user deleted.
///
/// Server delete can lag, fail for seed/non-UUID rows, or be overwritten by disk cache
/// on next launch. This store keeps deleted ids out of feed / profile / hubs rails
/// until the server catalog no longer returns them.
@MainActor
final class DeletedPostsStore {
    static let shared = DeletedPostsStore()

    private let defaultsKey = "posts.deleted.tombstones.v1"
    private var ids: Set<String> = []

    private init() {
        let raw = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        ids = Set(raw)
    }

    func isDeleted(_ postID: String) -> Bool {
        let key = normalized(postID)
        guard !key.isEmpty else { return false }
        return ids.contains(key)
    }

    func markDeleted(_ postID: String) {
        let key = normalized(postID)
        guard !key.isEmpty else { return }
        ids.insert(key)
        // Cap growth — keep newest ~4k.
        if ids.count > 4_000 {
            ids = Set(ids.suffix(3_500))
        }
        UserDefaults.standard.set(Array(ids), forKey: defaultsKey)
    }

    func filter<S: Sequence>(_ posts: S) -> [CountryPost] where S.Element == CountryPost {
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
