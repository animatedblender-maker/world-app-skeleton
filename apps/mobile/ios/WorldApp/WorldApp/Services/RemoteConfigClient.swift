import Foundation

/// Versioned remote flags (ADR-002). No UI. Kill switches + prefetch depths.
@MainActor
enum RemoteConfigClient {
    private static var version: String = ""
    private static var flags: [String: Any] = [:]
    private static var fetchedAt: Date?
    private static var ttlSec: TimeInterval = 60

    static var currentVersion: String { version }

    static func bool(_ key: String, default def: Bool) -> Bool {
        if let b = flags[key] as? Bool { return b }
        if let n = flags[key] as? NSNumber { return n.boolValue }
        return def
    }

    static func int(_ key: String, default def: Int) -> Int {
        if let i = flags[key] as? Int { return i }
        if let n = flags[key] as? NSNumber { return n.intValue }
        return def
    }

    static func double(_ key: String, default def: Double) -> Double {
        if let d = flags[key] as? Double { return d }
        if let n = flags[key] as? NSNumber { return n.doubleValue }
        return def
    }

    /// Refresh if TTL expired. Safe to call often.
    static func refreshIfNeeded() async {
        if let at = fetchedAt, Date().timeIntervalSince(at) < ttlSec, !flags.isEmpty {
            return
        }
        await fetch()
    }

    static func fetch() async {
        var comps = URLComponents(string: "\(AppConfig.apiBaseURL)/v1/config")
        if !version.isEmpty {
            comps?.queryItems = [URLQueryItem(name: "v", value: version)]
        }
        guard let url = comps?.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 4
        if let token = try? await AuthService.shared.ensureValidToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["ok"] as? Bool == true
            else { return }

            if json["unchanged"] as? Bool == true {
                fetchedAt = Date()
                if let ttl = json["ttlSec"] as? Int { ttlSec = TimeInterval(ttl) }
                else if let n = json["ttlSec"] as? NSNumber { ttlSec = n.doubleValue }
                return
            }
            if let v = json["version"] as? String { version = v }
            if let ttl = json["ttlSec"] as? Int { ttlSec = TimeInterval(ttl) }
            else if let n = json["ttlSec"] as? NSNumber { ttlSec = n.doubleValue }
            if let f = json["flags"] as? [String: Any] { flags = f }
            fetchedAt = Date()
        } catch {
            // Keep last flags offline.
        }
    }
}
