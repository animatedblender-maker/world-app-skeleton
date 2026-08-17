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
    /// Edge-warm play URLs (POST /v1/playback/batch) — same path Hubs slug open relies on.
    /// Never blocks on token refresh (that made shared hubs on feed feel “years” slow).
    static func warmPlaybackURLs(_ postIDs: [String]) async {
        let ids = Array(
            Set(
                postIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).prefix(12)
        guard !ids.isEmpty else { return }
        // Cached token only — never ensureValidToken (that stalled shared hubs on feed).
        let token = await MainActor.run { AuthService.shared.accessToken() }
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/v1/playback/batch") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 3.5
        let body: [String: Any] = ["postIds": Array(ids)]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        req.httpBody = data
        do {
            let (respData, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return
            }
            guard
                let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                let items = json["items"] as? [[String: Any]]
            else { return }
            // Fire-and-forget ranged GET so CDN edge holds the object near the user.
            for row in items {
                guard let play = row["url"] as? String, let playURL = URL(string: play) else { continue }
                let postID = row["id"] as? String
                Task.detached(priority: .utility) {
                    var head = URLRequest(url: playURL)
                    head.httpMethod = "GET"
                    head.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
                    head.timeoutInterval = 3
                    _ = try? await URLSession.shared.data(for: head)
                }
                if ArchiveVideoPlayback.isArchiveURL(playURL) {
                    ArchiveVideoPlayback.warmResolve(playURL)
                }
                // Seed warm pool with the freshened edge URL (shared hubs on feed).
                if let postID, !postID.isEmpty {
                    await MainActor.run {
                        SparkWarmPool.shared.warmSingle(postID: postID, url: playURL, deep: false)
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[Recsys] playback batch warm failed: \(error.localizedDescription)")
            #endif
        }
    }
}
