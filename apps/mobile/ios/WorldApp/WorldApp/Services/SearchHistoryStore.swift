import Foundation
import Observation

/// Recent Search queries (device-local), like other engines — tap to re-run, X to remove one.
@MainActor
@Observable
final class SearchHistoryStore {
    static let shared = SearchHistoryStore()

    private let defaultsKey = "matterya.search.history.v1"
    private let maxEntries = 24

    private(set) var recent: [String] = []

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        recent = Self.normalizeList(stored)
    }

    /// Matching history while typing (prefix / contains), newest first.
    func suggestions(matching raw: String, limit: Int = 8) -> [String] {
        let q = Self.normalize(raw)
        guard !q.isEmpty else { return Array(recent.prefix(limit)) }
        return recent
            .filter { Self.normalize($0).contains(q) || Self.normalize($0).hasPrefix(q) }
            .prefix(limit)
            .map { $0 }
    }

    func record(_ raw: String) {
        let value = Self.normalizeDisplay(raw)
        guard !value.isEmpty else { return }
        var next = recent.filter { Self.normalize($0) != Self.normalize(value) }
        next.insert(value, at: 0)
        if next.count > maxEntries {
            next = Array(next.prefix(maxEntries))
        }
        recent = next
        persist()
    }

    func remove(_ raw: String) {
        let key = Self.normalize(raw)
        guard !key.isEmpty else { return }
        recent = recent.filter { Self.normalize($0) != key }
        persist()
    }

    func clear() {
        recent = []
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(recent, forKey: defaultsKey)
    }

    private static func normalizeDisplay(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ value: String) -> String {
        normalizeDisplay(value).lowercased()
    }

    private static func normalizeList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in values {
            let display = normalizeDisplay(raw)
            let key = normalize(display)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(display)
            if out.count >= 24 { break }
        }
        return out
    }
}
