import Foundation

/// REST client for `/v1/anonymous/*` — Bearer + UncancellableHTTP.
/// Cold Render wakes need headroom beyond a strict 12s (matches raised Feed surface timeouts).
enum AnonymousService {
    /// First paint stays under a soft budget; one retry covers cold wakes.
    private static let timeout: TimeInterval = 45
    /// Fat first page — one fetch covers a long first paint; load-more keeps it endless.
    private static let feedFirstLimit = 48
    static let feedPageLimit = 48
    /// No hard stop — Masquerade For you stays endless (soft-recycle when ledger/cursor thin).
    static let feedSoftCap = 10_000
    /// Prefetch when this many cards remain (light-speed append).
    static let feedPrefetchRemaining = 10
    static let spacePostsPageLimit = 40

    // MARK: - Session / identity

    static func session() async throws -> AnonymousSession {
        try await get("/v1/anonymous/session", as: AnonymousSession.self)
    }

    static func attest() async throws -> AnonymousSession {
        // API requires `{ attest: true }` (not confirmed).
        try await post("/v1/anonymous/attest", body: ["attest": true], as: AnonymousSession.self)
    }

    static func claimProfile(username: String? = nil) async throws -> AnonymousProfile {
        // Live API: POST /v1/anonymous/profile (server allocates a safe handle).
        // Optional username is forwarded for forward-compat; ignored until API accepts it.
        var body: [String: Any] = [:]
        if let username, !username.isEmpty {
            body["username"] = username
        }
        struct Envelope: Decodable {
            let profile: AnonymousProfile?
            // Flat response fallback
            let id: String?
            let username: String?
            let avatarSeed: String?
            let createdAt: String?
            let state: String?

            var resolved: AnonymousProfile? {
                if let profile { return profile }
                guard let id, let username else { return nil }
                return AnonymousProfile(
                    id: id,
                    username: username,
                    avatarSeed: avatarSeed,
                    createdAt: createdAt,
                    state: state
                )
            }
        }
        let env: Envelope = try await post("/v1/anonymous/profile", body: body, as: Envelope.self)
        guard let profile = env.resolved else { throw AnonymousError.decoding }
        return profile
    }

    static func me() async throws -> AnonymousProfile {
        try await get("/v1/anonymous/profile/me", as: AnonymousProfile.self)
    }

    static func suggestUsername() async throws -> String {
        struct Resp: Decodable {
            let username: String?
            let suggestedUsername: String?
        }
        // Prefer live suggest when deployed; otherwise caller falls back to localSafeUsername.
        let resp: Resp = try await get("/v1/anonymous/username/suggest", as: Resp.self)
        if let u = resp.username ?? resp.suggestedUsername, !u.isEmpty { return u }
        throw AnonymousError.server("No username suggestion available.")
    }

    // MARK: - Spaces

    static func listSpaces(
        filter: AnonymousSpaceFilter = .forYou,
        cursor: String? = nil,
        limit: Int = 24
    ) async throws -> AnonymousPage<AnonymousSpace> {
        var q: [String: String] = [
            "filter": filter.rawValue,
            "limit": "\(min(max(limit, 1), 48))",
        ]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await getPage("/v1/anonymous/spaces", query: q, itemType: AnonymousSpace.self)
    }

    static func space(slug: String) async throws -> AnonymousSpace {
        try await get("/v1/anonymous/spaces/\(slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)", as: AnonymousSpace.self)
    }

    static func createSpace(_ input: AnonymousCreateSpaceInput) async throws -> AnonymousSpace {
        let data = try JSONEncoder().encode(input)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return try await post("/v1/anonymous/spaces", body: obj, as: AnonymousSpace.self)
    }

    static func join(spaceId: String) async throws -> AnonymousMembership {
        try await post("/v1/anonymous/spaces/\(spaceId)/join", body: [:], as: AnonymousMembership.self)
    }

    static func leave(spaceId: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await post("/v1/anonymous/spaces/\(spaceId)/leave", body: [:], as: Empty.self, allowEmpty: true)
    }

    // MARK: - Posts / comments

    static func listPosts(
        spaceId: String,
        cursor: String? = nil,
        sort: AnonymousFeedSort = .hot,
        limit: Int = 24
    ) async throws -> AnonymousPage<AnonymousPost> {
        var q: [String: String] = [
            "sort": sort.rawValue,
            "limit": "\(min(max(limit, 1), 48))",
        ]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await getPage("/v1/anonymous/spaces/\(spaceId)/posts", query: q, itemType: AnonymousPost.self)
    }

    static func createPost(spaceId: String, input: AnonymousCreatePostInput) async throws -> AnonymousPost {
        // Explicit dict — JSONEncoder Optional nulls + CodingKeys have dropped media before.
        var body: [String: Any] = [
            "body": input.body,
        ]
        if let title = input.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            body["title"] = title
        }
        if let mediaType = input.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines), !mediaType.isEmpty {
            body["media_type"] = mediaType
            body["mediaType"] = mediaType
        }
        if let mediaURL = input.mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines), !mediaURL.isEmpty {
            body["media_url"] = mediaURL
            body["mediaUrl"] = mediaURL
        }
        if let thumbURL = input.thumbURL?.trimmingCharacters(in: .whitespacesAndNewlines), !thumbURL.isEmpty {
            body["thumb_url"] = thumbURL
            body["thumbUrl"] = thumbURL
        }
        return try await post("/v1/anonymous/spaces/\(spaceId)/posts", body: body, as: AnonymousPost.self)
    }

    static func getPost(id: String) async throws -> AnonymousPost {
        try await get("/v1/anonymous/posts/\(id)", as: AnonymousPost.self)
    }

    static func listComments(
        postId: String,
        cursor: String? = nil,
        limit: Int = 40
    ) async throws -> AnonymousPage<AnonymousComment> {
        var q: [String: String] = ["limit": "\(min(max(limit, 1), 80))"]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        // Dedicated path — generic getPage + convertFromSnakeCase silently dropped comments.
        let req = try await makeRequest(
            path: "/v1/anonymous/posts/\(postId)/comments",
            method: "GET",
            query: q,
            body: nil
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await UncancellableHTTP.data(for: req)
        } catch {
            throw AnonymousError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AnonymousError.network("Bad response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            var code: String?
            var message: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                code = json["code"] as? String
                message = Self.apiMessage(from: json)
            }
            throw AnonymousError.from(code: code, message: message ?? "HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnonymousError.decoding
        }
        if let code = json["code"] as? String, json["ok"] as? Bool == false {
            throw AnonymousError.from(code: code, message: Self.apiMessage(from: json))
        }
        let payload = (json["data"] as? [String: Any]) ?? json
        let rawItems = (payload["comments"] as? [[String: Any]])
            ?? (payload["items"] as? [[String: Any]])
            ?? []
        let itemsData = try JSONSerialization.data(withJSONObject: rawItems)
        // Plain decoder — models already accept snake_case CodingKeys.
        let decoder = JSONDecoder()
        let items = try decoder.decode([AnonymousComment].self, from: itemsData)
        let cursorOut = payload["nextCursor"] as? String ?? payload["next_cursor"] as? String
        return AnonymousPage(items: items, nextCursor: cursorOut)
    }

    static func createComment(postId: String, input: AnonymousCreateCommentInput) async throws -> AnonymousComment {
        var body: [String: Any] = ["body": input.body]
        if let parent = input.parentCommentId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !parent.isEmpty {
            body["parent_id"] = parent
        }
        return try await post("/v1/anonymous/posts/\(postId)/comments", body: body, as: AnonymousComment.self)
    }

    static func vote(targetType: String, targetId: String, value: Int) async throws {
        struct Empty: Decodable {}
        // API route is `/votes` and reads snake_case (`target_type` / `target_id`).
        let _: Empty = try await post(
            "/v1/anonymous/votes",
            body: [
                "target_type": targetType,
                "target_id": targetId,
                "value": value,
                "targetType": targetType,
                "targetId": targetId,
            ],
            as: Empty.self,
            allowEmpty: true
        )
    }

    static func report(targetType: String, targetId: String, reason: String) async throws {
        struct Empty: Decodable {}
        // API: POST /v1/anonymous/reports with snake_case fields.
        let _: Empty = try await post(
            "/v1/anonymous/reports",
            body: [
                "target_type": targetType,
                "target_id": targetId,
                "reason": reason,
                "targetType": targetType,
                "targetId": targetId,
            ],
            as: Empty.self,
            allowEmpty: true
        )
    }

    static func block(profileId: String) async throws {
        struct Empty: Codable {}
        // API: POST /v1/anonymous/blocks with blocked_profile_id (snake_case).
        let _: Empty = try await post(
            "/v1/anonymous/blocks",
            body: [
                "blocked_profile_id": profileId,
                "blockedProfileId": profileId,
            ],
            as: Empty.self,
            allowEmpty: true
        )
    }

    static func feed(
        sort: AnonymousFeedSort = .forYou,
        cursor: String? = nil,
        limit: Int? = nil
    ) async throws -> AnonymousPage<AnonymousPost> {
        let resolvedLimit = min(max(limit ?? feedFirstLimit, 1), 50)
        var q: [String: String] = [
            "sort": sort.rawValue,
            "limit": "\(resolvedLimit)",
        ]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await getPage("/v1/anonymous/feed", query: q, itemType: AnonymousPost.self)
    }

    static func notifications(
        cursor: String? = nil,
        limit: Int = 40
    ) async throws -> AnonymousNotificationsPage {
        var q: [String: String] = [
            "limit": "\(min(max(limit, 1), 80))",
        ]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        let req = try await makeRequest(
            path: "/v1/anonymous/notifications",
            method: "GET",
            query: q,
            body: nil
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await UncancellableHTTP.data(for: req)
        } catch {
            throw AnonymousError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AnonymousError.network("Bad response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AnonymousError.from(code: nil, message: "HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnonymousError.decoding
        }
        let payload = (json["data"] as? [String: Any]) ?? json
        let rawItems = (payload["notifications"] as? [[String: Any]])
            ?? (payload["items"] as? [[String: Any]])
            ?? []
        let itemsData = try JSONSerialization.data(withJSONObject: rawItems)
        let items = try JSONDecoder().decode([AnonymousNotification].self, from: itemsData)
        let cursorOut = payload["nextCursor"] as? String ?? payload["next_cursor"] as? String
        let unread = (payload["unread_count"] as? Int)
            ?? (payload["unreadCount"] as? Int)
            ?? items.filter(\.isUnread).count
        return AnonymousNotificationsPage(
            items: items,
            nextCursor: cursorOut,
            unreadCount: unread
        )
    }

    @discardableResult
    static func markNotificationRead(id: String) async throws -> Bool {
        struct Resp: Decodable { let ok: Bool?; let updated: Bool? }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let resp: Resp = try await post(
            "/v1/anonymous/notifications/\(trimmed)/read",
            body: [:],
            as: Resp.self,
            allowEmpty: true
        )
        return resp.updated ?? resp.ok ?? true
    }

    @discardableResult
    static func markAllNotificationsRead() async throws -> Int {
        struct Resp: Decodable { let ok: Bool?; let updated: Int? }
        let resp: Resp = try await post(
            "/v1/anonymous/notifications/read-all",
            body: [:],
            as: Resp.self,
            allowEmpty: true
        )
        return resp.updated ?? 0
    }

    static func search(query: String, limit: Int = 12) async throws -> AnonymousSearchResults {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return AnonymousSearchResults() }
        return try await get(
            "/v1/anonymous/search",
            query: [
                "q": q,
                "limit": "\(min(max(limit, 1), 24))",
            ],
            as: AnonymousSearchResults.self
        )
    }

    static func publicProfile(username: String) async throws -> AnonymousPublicProfilePayload {
        let handle = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        return try await get(
            "/v1/anonymous/profiles/\(encoded)",
            as: AnonymousPublicProfilePayload.self
        )
    }

    static func authorPosts(
        username: String,
        cursor: String? = nil,
        limit: Int = 24
    ) async throws -> AnonymousPage<AnonymousPost> {
        let handle = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        var q: [String: String] = [
            "limit": "\(min(max(limit, 1), 48))",
        ]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await getPage(
            "/v1/anonymous/profiles/\(encoded)/posts",
            query: q,
            itemType: AnonymousPost.self
        )
    }

    // MARK: - HTTP

    private static func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await get(path, query: nil, as: type)
    }

    private static func get<T: Decodable>(
        _ path: String,
        query: [String: String]?,
        as type: T.Type
    ) async throws -> T {
        let req = try await makeRequest(path: path, method: "GET", query: query, body: nil)
        return try await perform(req, as: type)
    }

    private static func getPage<T: Decodable>(
        _ path: String,
        query: [String: String],
        itemType: T.Type
    ) async throws -> AnonymousPage<T> {
        let req = try await makeRequest(path: path, method: "GET", query: query, body: nil)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await UncancellableHTTP.data(for: req)
        } catch {
            throw AnonymousError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AnonymousError.network("Bad response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            var code: String?
            var message: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                code = json["code"] as? String
                message = Self.apiMessage(from: json)
            }
            throw AnonymousError.from(code: code, message: message ?? "HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnonymousError.decoding
        }
        if let code = json["code"] as? String, json["ok"] as? Bool == false {
            throw AnonymousError.from(code: code, message: Self.apiMessage(from: json))
        }
        let payload = (json["data"] as? [String: Any]) ?? json
        // API uses resource keys (spaces / posts / notifications / comments), not always `items`.
        let rawItems: [[String: Any]] = {
            for key in ["items", "spaces", "posts", "notifications", "comments"] {
                if let arr = payload[key] as? [[String: Any]] { return arr }
            }
            return []
        }()
        let itemsData = try JSONSerialization.data(withJSONObject: rawItems)
        // Models already declare snake_case CodingKeys — convertFromSnakeCase silently
        // emptied comments before; use a plain decoder and surface failures.
        let decoder = JSONDecoder()
        let items: [T]
        do {
            items = try decoder.decode([T].self, from: itemsData)
        } catch {
            throw AnonymousError.decoding
        }
        let cursor = payload["nextCursor"] as? String ?? payload["next_cursor"] as? String
        return AnonymousPage(items: items, nextCursor: cursor)
    }

    private static func post<T: Decodable>(
        _ path: String,
        body: [String: Any],
        as type: T.Type,
        allowEmpty: Bool = false
    ) async throws -> T {
        let req = try await makeRequest(path: path, method: "POST", query: nil, body: body)
        return try await perform(req, as: type, allowEmpty: allowEmpty)
    }

    private static func makeRequest(
        path: String,
        method: String,
        query: [String: String]?,
        body: [String: Any]?
    ) async throws -> URLRequest {
        var comps = URLComponents(string: "\(AppConfig.apiBaseURL)\(path)")
        if let query, !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else {
            throw AnonymousError.network("Invalid Anonymous URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = timeout

        // Always refresh-near-expiry — a stale non-empty token caused 401 → empty feed.
        do {
            let token = try await AuthService.shared.ensureValidToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            throw AnonymousError.network("Sign in again to open Masquerade.")
        }

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private static func perform<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type,
        allowEmpty: Bool = false
    ) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await UncancellableHTTP.data(for: request)
        } catch {
            throw AnonymousError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AnonymousError.network("Bad response.")
        }

        if (200..<300).contains(http.statusCode) {
            if allowEmpty, data.isEmpty || data.count < 3 {
                if let decoded = try? JSONDecoder.anonymous.decode(type, from: Data("{}".utf8)) {
                    return decoded
                }
            }
            // Prefer unwrapping `{ ok, ...payload }` envelopes.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let code = json["code"] as? String, json["ok"] as? Bool == false {
                    throw AnonymousError.from(code: code, message: Self.apiMessage(from: json))
                }
                // If top-level matches the type fields, decode whole body.
                if let decoded = try? JSONDecoder.anonymous.decode(type, from: data) {
                    return decoded
                }
                // Nested under `data` or resource key.
                for key in ["data", "session", "profile", "space", "post", "comment", "membership"] {
                    if let nested = json[key] {
                        let nestedData = try JSONSerialization.data(withJSONObject: nested)
                        if let decoded = try? JSONDecoder.anonymous.decode(type, from: nestedData) {
                            return decoded
                        }
                    }
                }
            }
            do {
                return try JSONDecoder.anonymous.decode(type, from: data)
            } catch {
                throw AnonymousError.decoding
            }
        }

        // Map HTTP status + body code.
        var code: String?
        var message: String?
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            code = json["code"] as? String
            message = Self.apiMessage(from: json)
        }

        switch http.statusCode {
        case 401, 403:
            throw AnonymousError.from(code: code ?? "forbidden", message: message)
        case 404:
            throw AnonymousError.notFound
        case 409:
            throw AnonymousError.from(code: code ?? "username_taken", message: message)
        case 422:
            throw AnonymousError.from(code: code ?? "username_invalid", message: message)
        case 429:
            throw AnonymousError.rateLimited
        default:
            throw AnonymousError.from(code: code, message: message ?? "HTTP \(http.statusCode)")
        }
    }

    /// API errors use `reason` (and sometimes `message` / `error`).
    private static func apiMessage(from json: [String: Any]) -> String? {
        if let reason = json["reason"] as? String, !reason.isEmpty { return reason }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        if let error = json["error"] as? String, !error.isEmpty { return error }
        return nil
    }
}

private extension JSONDecoder {
    /// Plain decoder — Anonymous models already declare dual snake/camel CodingKeys.
    /// `convertFromSnakeCase` maps `media_url` → `mediaUrl`, which never matches
    /// CodingKey `mediaURL`, so getPost silently dropped image/video URLs and
    /// rememberPost then blanked feed cards on back navigation.
    static let anonymous: JSONDecoder = {
        JSONDecoder()
    }()
}
