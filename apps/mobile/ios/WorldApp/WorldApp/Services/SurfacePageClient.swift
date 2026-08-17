import Foundation

/// Thin-page client for **whole app** surfaces (feed / sparks / hubs).
/// Same card shape as Hubs slug shelves — never download fat GraphQL catalogs for first paint.
enum SurfacePageClient {
    struct Page: Sendable {
        var items: [CountryPost]
        var nextCursor: String?
        var surface: String
    }

    // MARK: - Surfaces

    static func fetchHomeFeed(limit: Int = 24, cursor: String? = nil) async -> Page? {
        await get(
            path: "/v1/feed",
            query: [
                "limit": "\(min(max(limit, 1), 48))",
                "cursor": cursor,
            ].compactMapValues { $0 },
            allowMissingMedia: true
        )
    }

    static func fetchSparks(limit: Int = 20, cursor: String? = nil, slug: String? = nil) async -> Page? {
        var q: [String: String?] = [
            "limit": "\(min(max(limit, 1), 40))",
            "cursor": cursor,
        ]
        if let slug, !slug.isEmpty { q["slug"] = slug }
        return await get(
            path: "/v1/sparks",
            query: q.compactMapValues { $0 },
            allowMissingMedia: false
        )
    }

    // MARK: - HTTP

    private static func get(
        path: String,
        query: [String: String],
        allowMissingMedia: Bool
    ) async -> Page? {
        var comps = URLComponents(string: "\(AppConfig.apiBaseURL)\(path)")
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 6
        if let token = try? await AuthService.shared.ensureValidToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["ok"] as? Bool == true,
                let rawItems = json["items"] as? [[String: Any]]
            else { return nil }

            let posts = rawItems.compactMap {
                mapThinCard($0, allowMissingMedia: allowMissingMedia)
            }
            #if DEBUG
            print("[Surface] \(path) items=\(posts.count) next=\(json["nextCursor"] != nil)")
            #endif
            return Page(
                items: posts,
                nextCursor: json["nextCursor"] as? String,
                surface: (json["surface"] as? String) ?? path
            )
        } catch {
            #if DEBUG
            print("[Surface] fail \(path): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Shared thin-card → CountryPost (Hubs / feed / sparks).
    static func mapThinCard(
        _ row: [String: Any],
        allowMissingMedia: Bool = false,
        fallbackSlug: String? = nil
    ) -> CountryPost? {
        guard let id = row["id"] as? String, !id.isEmpty else { return nil }
        let slug = ((row["slug"] as? String) ?? fallbackSlug ?? "daily").lowercased()
        let mediaType = (row["media_type"] as? String) ?? "none"
        let mediaURL = row["media_url"] as? String
        let thumb = row["thumb_url"] as? String
        if !allowMissingMedia {
            guard let mediaURL, !mediaURL.isEmpty else { return nil }
        }

        let authorID = (row["author_id"] as? String) ?? "unknown"
        let author = PostAuthor(
            userID: authorID,
            displayName: row["author_name"] as? String,
            username: row["author_username"] as? String,
            avatarURL: row["author_avatar"] as? String,
            countryName: row["country_name"] as? String,
            countryCode: row["country_code"] as? String,
            lastReadAt: nil
        )
        let created = (row["created_at"] as? String) ?? ISO8601DateFormatter().string(from: Date())
        let body = (row["body"] as? String) ?? ""
        let isHubSurface = mediaType == "video" || mediaType == "reel" || mediaType == "spark"

        return CountryPost(
            id: id,
            title: row["title"] as? String,
            body: body,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: thumb,
            visibility: .public,
            likeCount: intValue(row["like_count"]),
            commentCount: intValue(row["comment_count"]),
            viewCount: 0,
            likedByMe: false,
            savedByMe: false,
            createdAt: created,
            updatedAt: created,
            authorID: authorID,
            countryName: row["country_name"] as? String,
            countryCode: row["country_code"] as? String,
            author: author,
            externalRefType: isHubSurface ? "hub" : nil,
            externalRefID: isHubSurface ? slug : nil
        )
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        return 0
    }
}
