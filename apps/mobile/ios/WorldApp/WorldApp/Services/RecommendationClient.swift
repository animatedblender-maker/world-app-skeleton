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

        var byId = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
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
        req.timeoutInterval = 8

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
                policyVersion: json["policyVersion"] as? String ?? "server.v1",
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
}
