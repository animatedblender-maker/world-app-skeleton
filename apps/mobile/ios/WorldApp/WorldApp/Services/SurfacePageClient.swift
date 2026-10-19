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
                // API caps at 64 — walk the full R2-backed library newest-first.
                "limit": "\(min(max(limit, 1), 64))",
                "cursor": cursor,
            ].compactMapValues { $0 },
            allowMissingMedia: true
        )
    }

    static func fetchSparks(limit: Int = 24, cursor: String? = nil, slug: String? = nil) async -> Page? {
        var q: [String: String?] = [
            // API caps at 48 — endless Sparks pages by feed_at.
            "limit": "\(min(max(limit, 1), 48))",
            "cursor": cursor,
        ]
        if let slug, !slug.isEmpty { q["slug"] = slug }
        return await get(
            path: "/v1/sparks",
            query: q.compactMapValues { $0 },
            allowMissingMedia: false
        )
    }

    /// Walk `/v1/sparks` newest-first until `want` unviewed items or the cursor ends.
    /// Phone never holds 306k — this is the pre-KNN full-library pager.
    static func fetchSparksPages(
        want: Int,
        startingCursor: String? = nil,
        maxPages: Int = 8,
        excluding: Set<String> = [],
        skipViewed: Bool = true
    ) async -> (items: [CountryPost], nextCursor: String?) {
        var out: [CountryPost] = []
        var seen = excluding
        var cursor = startingCursor
        var pages = 0
        let pageSize = min(max(want, 24), 48)
        while out.count < want, pages < maxPages {
            pages += 1
            guard let page = await fetchSparks(limit: pageSize, cursor: cursor) else { break }
            if page.items.isEmpty {
                cursor = page.nextCursor
                break
            }
            for post in page.items {
                guard seen.insert(post.id).inserted else { continue }
                if skipViewed, SparkDiscoveryEngine.isViewed(post) { continue }
                out.append(post)
                if out.count >= want { break }
            }
            cursor = page.nextCursor
            if page.nextCursor == nil { break }
        }
        return (out, cursor)
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
        // Render cold / DB hiccup can be 5–8s; 4s caused false [Surface] fail storms.
        req.timeoutInterval = 12
        // Cached token only — never stall first paint on token refresh.
        if let token = await MainActor.run(body: { AuthService.shared.accessToken() }) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            // Survive SwiftUI `.task(id:)` cancellation on launch generation bumps.
            let (data, response) = try await UncancellableHTTP.data(for: req)
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
        // Prefer feed_at (= greatest(updated_at, created_at)) so newest R2 uploads stay on top.
        let updated = ([row["feed_at"] as? String, row["updated_at"] as? String]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }) ?? created
        let body = (row["body"] as? String) ?? ""
        let isHubSurface = mediaType == "video" || mediaType == "reel" || mediaType == "spark"
        // Thin feed used to strip stamps — API now sends shared_post_id / origin_sid for comments.
        let sharedRaw = (row["shared_post_id"] as? String)
            ?? (row["origin_sid"] as? String)
        let sharedPostID: String? = {
            guard let s = sharedRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty, s != id else { return nil }
            return s
        }()

        return CountryPost(
            id: id,
            title: row["title"] as? String,
            body: body,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: thumb,
            sharedPostID: sharedPostID,
            visibility: .public,
            likeCount: intValue(row["like_count"]),
            commentCount: intValue(row["comment_count"]),
            viewCount: 0,
            likedByMe: false,
            savedByMe: false,
            createdAt: created,
            updatedAt: updated,
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
