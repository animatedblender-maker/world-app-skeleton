import Foundation

/// MIND-019 interest controls + people discovery + creator insights (thin REST).
enum MindInterestClient {
    struct Controls: Sendable {
        var mutedHubs: [String]
        var mutedCreators: [String]
        var boostedTopics: [String]
        var chronoPreferred: Bool
    }

    struct Snapshot: Sendable {
        var controls: Controls
        var coldStart: Bool
        var eventsCounted: Int
    }

    struct PersonSuggestion: Sendable, Identifiable {
        var id: String { userId }
        var userId: String
        var displayName: String
        var username: String?
        var avatarUrl: String?
        var countryCode: String?
        var reason: String
    }

    static func fetchInterests() async -> Snapshot? {
        guard let json = await getJSON(path: "/v1/me/interests") else { return nil }
        guard json["ok"] as? Bool == true else { return nil }
        let controlsRaw = json["controls"] as? [String: Any] ?? [:]
        let inferred = json["inferred"] as? [String: Any] ?? [:]
        return Snapshot(
            controls: Controls(
                mutedHubs: (controlsRaw["mutedHubs"] as? [String]) ?? [],
                mutedCreators: (controlsRaw["mutedCreators"] as? [String]) ?? [],
                boostedTopics: (controlsRaw["boostedTopics"] as? [String]) ?? [],
                chronoPreferred: (controlsRaw["chronoPreferred"] as? Bool) ?? false
            ),
            coldStart: (inferred["coldStart"] as? Bool) ?? false,
            eventsCounted: (inferred["eventsCounted"] as? Int) ?? 0
        )
    }

    static func patchInterests(
        mutedHubs: [String]? = nil,
        mutedCreators: [String]? = nil,
        boostedTopics: [String]? = nil,
        chronoPreferred: Bool? = nil,
        replace: Bool = false
    ) async -> Controls? {
        var body: [String: Any] = ["mode": replace ? "replace" : "merge"]
        if let mutedHubs { body["mutedHubs"] = mutedHubs }
        if let mutedCreators { body["mutedCreators"] = mutedCreators }
        if let boostedTopics { body["boostedTopics"] = boostedTopics }
        if let chronoPreferred { body["chronoPreferred"] = chronoPreferred }
        guard let json = await sendJSON(path: "/v1/me/interests", method: "PATCH", body: body) else {
            return nil
        }
        guard json["ok"] as? Bool == true,
              let controlsRaw = json["controls"] as? [String: Any]
        else { return nil }
        return Controls(
            mutedHubs: (controlsRaw["mutedHubs"] as? [String]) ?? [],
            mutedCreators: (controlsRaw["mutedCreators"] as? [String]) ?? [],
            boostedTopics: (controlsRaw["boostedTopics"] as? [String]) ?? [],
            chronoPreferred: (controlsRaw["chronoPreferred"] as? Bool) ?? false
        )
    }

    static func resetInterests() async -> Bool {
        let json = await sendJSON(path: "/v1/me/interests/reset", method: "POST", body: [:])
        return json?["ok"] as? Bool == true
    }

    static func suggestPeople(limit: Int = 12, countryCode: String? = nil) async -> [PersonSuggestion] {
        var q = ["limit": String(limit)]
        if let countryCode, !countryCode.isEmpty { q["country"] = countryCode }
        guard let json = await getJSON(path: "/v1/people/suggest", query: q) else { return [] }
        guard json["ok"] as? Bool == true,
              let people = json["people"] as? [[String: Any]]
        else { return [] }
        return people.compactMap { row in
            guard let userId = row["userId"] as? String else { return nil }
            return PersonSuggestion(
                userId: userId,
                displayName: (row["displayName"] as? String) ?? "Creator",
                username: row["username"] as? String,
                avatarUrl: row["avatarUrl"] as? String,
                countryCode: row["countryCode"] as? String,
                reason: (row["reason"] as? String) ?? "active_creator"
            )
        }
    }

    // MARK: - HTTP

    private static func getJSON(
        path: String,
        query: [String: String] = [:]
    ) async -> [String: Any]? {
        var comps = URLComponents(string: "\(AppConfig.apiBaseURL)\(path)")
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        if let token = try? await AuthService.shared.ensureValidToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func sendJSON(
        path: String,
        method: String,
        body: [String: Any]
    ) async -> [String: Any]? {
        guard let url = URL(string: "\(AppConfig.apiBaseURL)\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        guard let token = try? await AuthService.shared.ensureValidToken() else { return nil }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }
}
