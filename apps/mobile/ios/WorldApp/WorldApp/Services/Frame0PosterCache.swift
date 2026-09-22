import Foundation

/// MainActor mirror of Frame0 signed URLs so SwiftUI can paint first frames
/// immediately after `Frame0PosterResolver.prefetch` (actor cache alone is invisible to views).
@MainActor
enum Frame0PosterCache {
    private static var map: [String: URL] = [:]

    static func url(for postID: String) -> URL? {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return map[key]
    }

    static func store(_ postID: String, _ url: URL) {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        map[key] = url
        if map.count > 4000, let first = map.keys.first {
            map.removeValue(forKey: first)
        }
    }

    static func storeBatch(_ posters: [String: URL]) {
        for (id, url) in posters {
            store(id, url)
        }
    }
}
