import Foundation

/// Recent Search queries (device-local). Surfaces keep **separate** histories.
///
/// Record **only** on keyboard Search/Return or opening a result — never while typing
/// or after a short pause mid-word.
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
    /// Ignore 1-character noise from older debounce bugs.
    private static let minLength = 2

    static func recent(for surface: Surface) -> [String] {
        normalizeList(UserDefaults.standard.stringArray(forKey: surface.defaultsKey) ?? [])
    }

    /// Completions while typing — longer history rows that start with the query.
    /// Never returns the exact in-progress string (that felt like “saving while typing”).
    static func suggestions(matching raw: String, surface: Surface, limit: Int = 8) -> [String] {
        let q = normalize(raw)
        let all = recent(for: surface)
        guard !q.isEmpty else { return Array(all.prefix(limit)) }
        return all
            .filter {
                let n = normalize($0)
                guard n != q else { return false }
                // Completions only (easy when typing ea) — not every contains-match.
                return n.hasPrefix(q) && n.count > q.count
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Call only from Return / result tap / Recent pick.
    static func record(_ raw: String, surface: Surface) {
        let value = normalizeDisplay(raw)
        guard value.count >= minLength else { return }
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
            guard key.count >= minLength, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(display)
            if out.count >= maxEntries { break }
        }
        return out
    }
}
