import Foundation

/// Recent Search queries (device-local), like other engines — tap to re-run, X to remove one.
/// Surfaces keep **separate** histories (main / hubs / masquerade).
@MainActor
enum SearchHistoryStore {
    enum Surface: String {
        case main
        case hubs
        case masquerade

        fileprivate var defaultsKey: String {
            switch self {
            case .main: "matterya.search.history.v1"
            case .hubs: "matterya.search.history.hubs.v1"
            case .masquerade: "matterya.search.history.masquerade.v1"
            }
        }
    }

    private static let maxEntries = 24

    static func recent(for surface: Surface) -> [String] {
        let stored = UserDefaults.standard.stringArray(forKey: surface.defaultsKey) ?? []
        return normalizeList(stored)
    }

    /// Matching history while typing. Never includes the exact in-progress query.
    static func suggestions(matching raw: String, surface: Surface, limit: Int = 8) -> [String] {
        let q = normalize(raw)
        let all = recent(for: surface)
        guard !q.isEmpty else { return Array(all.prefix(limit)) }
        return all
            .filter {
                let n = normalize($0)
                // Do not show the word currently being typed as if it were already history.
                if n == q { return false }
                return n.contains(q) || n.hasPrefix(q)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Call only on Return, result tap, or picking a Recent row — never on every keystroke.
    static func record(_ raw: String, surface: Surface) {
        let value = normalizeDisplay(raw)
        guard !value.isEmpty else { return }
        var next = recent(for: surface).filter { normalize($0) != normalize(value) }
        next.insert(value, at: 0)
        if next.count > maxEntries {
            next = Array(next.prefix(maxEntries))
        }
        UserDefaults.standard.set(next, forKey: surface.defaultsKey)
    }

    static func remove(_ raw: String, surface: Surface) {
        let key = normalize(raw)
        guard !key.isEmpty else { return }
        let next = recent(for: surface).filter { normalize($0) != key }
        UserDefaults.standard.set(next, forKey: surface.defaultsKey)
    }

    static func clear(surface: Surface) {
        UserDefaults.standard.set([String](), forKey: surface.defaultsKey)
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
            if out.count >= maxEntries { break }
        }
        return out
    }
}
