import Foundation

/// Durable tombstones for posts the user deleted.
///
/// Server delete can lag, fail for seed/non-UUID rows, or be **re-seeded under a new UUID**
/// by the content pipeline for the same media. Tombstones therefore store **content identity**
/// (post id + share/origin + R2/media keys), not only the row id that was tapped.
///
/// Thread-safe / nonisolated-friendly so array helpers and feed ranking can call it
/// without MainActor hops (Swift 6).
final class DeletedPostsStore: @unchecked Sendable {
    static let shared = DeletedPostsStore()

    private let defaultsKey = "posts.deleted.tombstones.v2"
    private let legacyKey = "posts.deleted.tombstones.v1"
    private let lock = NSLock()
    private var keys: Set<String> = []

    private init() {
        var loaded = Set(
            (UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
                .map { normalized($0) }
                .filter { !$0.isEmpty }
        )
        // Migrate v1 id-only tombstones.
        if loaded.isEmpty {
            let legacy = UserDefaults.standard.stringArray(forKey: legacyKey) ?? []
            loaded = Set(legacy.map { normalized($0) }.filter { !$0.isEmpty })
            if !loaded.isEmpty {
                UserDefaults.standard.set(Array(loaded), forKey: defaultsKey)
            }
        }
        keys = loaded
    }

    // MARK: - Query

    func isDeleted(_ postID: String) -> Bool {
        let key = normalized(postID)
        guard !key.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return keys.contains(key) || keys.contains("id:\(key)")
    }

    /// True if this clip (any id / share / same media) was deleted by the user.
    func isDeleted(post: CountryPost) -> Bool {
        let candidates = identityKeys(for: post)
        guard !candidates.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        for c in candidates where keys.contains(c) {
            return true
        }
        return false
    }

    // MARK: - Mutate

    func markDeleted(_ postID: String) {
        insertKeys([normalized(postID), "id:\(normalized(postID))"].filter { !$0.isEmpty && $0 != "id:" })
    }

    /// Tombstone every identity for this clip so re-seeds / shares cannot resurrect it.
    func markDeleted(post: CountryPost) {
        insertKeys(identityKeys(for: post))
    }

    func filter(_ posts: [CountryPost]) -> [CountryPost] {
        posts.filter { !isDeleted(post: $0) }
    }

    // MARK: - Identity keys

    /// Stable keys that all mean "this same video / post" for hide-forever after delete.
    func identityKeys(for post: CountryPost) -> [String] {
        var out: [String] = []
        func add(_ raw: String?) {
            guard let n = raw.map(normalized), !n.isEmpty else { return }
            if !out.contains(n) { out.append(n) }
            let idKey = "id:\(n)"
            if !out.contains(idKey) { out.append(idKey) }
        }

        add(post.id)
        add(post.sharedPostID)
        add(SparkShareMarker.originID(from: post.body))
        if let hubSid = HubOriginShareMarker.parseFields(from: post.body)?["sid"] {
            add(hubSid)
        }

        // Content-collapse key used by home feed dedupe.
        let hk = post.homeFeedContentKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !hk.isEmpty, !out.contains(hk) {
            out.append(hk)
        }

        // R2 object key — survives re-seed under a new post UUID.
        if let r2 = post.mediaPayload?.r2Key.map(normalized), !r2.isEmpty {
            let r2Key = "r2:\(r2)"
            if !out.contains(r2Key) { out.append(r2Key) }
        }

        // Bare media URL (strip signed query).
        let mediaCandidates: [String?] = [
            post.playableVideoURL?.absoluteString,
            post.mediaURL,
            post.mediaPayload?.primaryURL,
            post.thumbURL,
        ]
        for raw in mediaCandidates {
            guard var m = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty else { continue }
            if let q = m.firstIndex(of: "?") {
                m = String(m[..<q])
            }
            m = m.lowercased()
            guard m.contains("http") || m.contains("r2") || m.contains(".mp4") || m.contains("video") else {
                continue
            }
            let mediaKey = "media:\(m)"
            if !out.contains(mediaKey) { out.append(mediaKey) }
        }

        return out
    }

    // MARK: - Private

    private func insertKeys(_ newKeys: [String]) {
        let cleaned = newKeys.map(normalized).filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        lock.lock()
        for k in cleaned {
            keys.insert(k)
        }
        if keys.count > 8_000 {
            keys = Set(keys.suffix(6_000))
        }
        let snapshot = Array(keys)
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    private func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Array where Element == CountryPost {
    /// Drop posts the user has deleted (id **or** same media / share / origin).
    func excludingDeletedPosts() -> [CountryPost] {
        DeletedPostsStore.shared.filter(self)
    }
}
