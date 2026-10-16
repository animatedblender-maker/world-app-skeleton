import Foundation

/// Server recsys client — scale path (POST /v1/recommendation/rank).
/// Falls back silently so offline / old API never breaks the feed.
enum RecommendationClient {
    struct RankedItem: Sendable {
        var id: String
        var score: Double
        var sources: [String]
    }

    struct RankResult: Sendable {
        var requestId: String
        var policyVersion: String
        var items: [RankedItem]
        var latencyMs: Int
    }

    /// Reorder posts using the server ranker. Returns input order on any failure.
    static func rankPosts(
        _ posts: [CountryPost],
        surface: RecommendationSurface,
        sessionId: String,
        followingIDs: Set<String>,
        limit: Int? = nil
    ) async -> [CountryPost] {
        guard !posts.isEmpty else { return posts }
        let ids = posts.map(\.id)
        guard let ranked = await rank(
            candidateIds: ids,
            surface: surface,
            sessionId: sessionId,
            followingIDs: Array(followingIDs),
            limit: limit ?? min(ids.count, 80)
        ) else {
            return posts
        }

        // Feed/hubs pools can contain the same id twice — uniqueKeysWithValues traps.
        let byId = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
        var out: [CountryPost] = []
        var used = Set<String>()
        for item in ranked.items {
            guard let post = byId[item.id], used.insert(item.id).inserted else { continue }
            out.append(post)
        }
        // Append anything the server dropped (non-UUID hub seeds, etc.).
        for post in posts where used.insert(post.id).inserted {
            out.append(post)
        }
        return out
    }

    static func rank(
        candidateIds: [String],
        surface: RecommendationSurface,
        sessionId: String,
        followingIDs: [String],
        limit: Int
    ) async -> RankResult? {
        guard !candidateIds.isEmpty else { return nil }
        let token: String
        do {
            token = try await AuthService.shared.ensureValidToken()
        } catch {
            return nil
        }

        guard let url = URL(string: "\(AppConfig.apiBaseURL)/v1/recommendation/rank") else {
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Hard cap — client Phase-0 already painted; server is soft re-order only.
        req.timeoutInterval = 4

        let body: [String: Any] = [
            "surface": surface.rawValue,
            "candidateIds": candidateIds,
            "sessionId": sessionId,
            "followingIds": followingIDs,
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data

        do {
            let (respData, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard
                let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                json["ok"] as? Bool == true,
                let itemsRaw = json["items"] as? [[String: Any]]
            else { return nil }

            let items: [RankedItem] = itemsRaw.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                let score = (row["score"] as? Double)
                    ?? (row["score"] as? NSNumber)?.doubleValue
                    ?? 0
                let sources = row["sources"] as? [String] ?? []
                return RankedItem(id: id, score: score, sources: sources)
            }
            return RankResult(
                requestId: json["requestId"] as? String ?? "",
                policyVersion: json["policyVersion"] as? String ?? "server.v2",
                items: items,
                latencyMs: (json["latencyMs"] as? Int)
                    ?? (json["latencyMs"] as? NSNumber)?.intValue
                    ?? 0
            )
        } catch {
            #if DEBUG
            print("[Recsys] rank failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // MARK: - CDN edge warm (batch playback)

    /// Ask the API to freshen R2 / signed play URLs for a head of posts.
    /// Client still warms AVPlayers; this cuts media latency on cold CDN edges.
    ///
    /// Launch guardrails (stops timeout storms that also starve GraphQL):
    /// - Coalesce in-flight calls
    /// - Skip IDs warmed in the last 10 minutes
    /// - Circuit breaker after consecutive failures (cool-down)
    /// - Single-flight queue (max 1 concurrent batch)
    private static let warmLock = NSLock()
    private static var warmInFlight = false
    private static var recentlyWarmed: [String: Date] = [:]
    private static var consecutiveFailures = 0
    private static var circuitOpenUntil: Date = .distantPast
    private static let warmTTL: TimeInterval = 10 * 60
    private static let circuitCooldown: TimeInterval = 20

    /// Edge-warm play URLs (POST /v1/playback/batch). Never blocks UI / token refresh.
    static func warmPlaybackURLs(_ postIDs: [String]) async {
        let now = Date()
        warmLock.lock()
        if now < circuitOpenUntil {
            warmLock.unlock()
            return
        }
        if warmInFlight {
            warmLock.unlock()
            return
        }
        let fresh = Array(
            Set(
                postIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .filter { id in
            if let last = recentlyWarmed[id], now.timeIntervalSince(last) < warmTTL { return false }
            return true
        }
        .prefix(12)
        guard !fresh.isEmpty else {
            warmLock.unlock()
            return
        }
        warmInFlight = true
        warmLock.unlock()
        defer {
            warmLock.lock()
            warmInFlight = false
            warmLock.unlock()
        }

        let token = await MainActor.run { AuthService.shared.accessToken() }
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/v1/playback/batch") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // API wall is ~2.2s; keep client slightly above so we get partial OK.
        req.timeoutInterval = 4.0
        let body: [String: Any] = ["postIds": Array(fresh)]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        req.httpBody = data
        do {
            let (respData, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                recordWarmFailure()
                return
            }
            guard
                let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                let items = json["items"] as? [[String: Any]]
            else {
                recordWarmFailure()
                return
            }
            recordWarmSuccess(ids: Array(fresh))
            for row in items {
                guard let play = row["url"] as? String, let playURL = URL(string: play) else { continue }
                let postID = row["id"] as? String
                Task.detached(priority: .utility) {
                    var head = URLRequest(url: playURL)
                    head.httpMethod = "GET"
                    head.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
                    head.timeoutInterval = 2.5
                    _ = try? await URLSession.shared.data(for: head)
                }
                if ArchiveVideoPlayback.isArchiveURL(playURL) {
                    ArchiveVideoPlayback.warmResolve(playURL)
                }
                if let postID, !postID.isEmpty {
                    await MainActor.run {
                        SparkWarmPool.shared.warmSingle(postID: postID, url: playURL, deep: false)
                    }
                }
            }
        } catch {
            recordWarmFailure()
            #if DEBUG
            print("[Recsys] playback batch warm failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func recordWarmSuccess(ids: [String]) {
        let now = Date()
        warmLock.lock()
        consecutiveFailures = 0
        circuitOpenUntil = .distantPast
        for id in ids { recentlyWarmed[id] = now }
        if recentlyWarmed.count > 400 {
            let cutoff = now.addingTimeInterval(-warmTTL)
            recentlyWarmed = recentlyWarmed.filter { $0.value >= cutoff }
        }
        warmLock.unlock()
    }

    private static func recordWarmFailure() {
        warmLock.lock()
        consecutiveFailures += 1
        if consecutiveFailures >= 2 {
            circuitOpenUntil = Date().addingTimeInterval(circuitCooldown)
            consecutiveFailures = 0
            #if DEBUG
            print("[Recsys] playback batch circuit open \(Int(circuitCooldown))s")
            #endif
        }
        warmLock.unlock()
    }
}
