import Foundation

/// REST client for `/v1/anonymous/*` — Mirror SurfacePageClient style (12s timeout, Bearer, UncancellableHTTP).
enum AnonymousService {
    private static let timeout: TimeInterval = 12

    // MARK: - Session / identity

    static func session() async throws -> AnonymousSession {
        try await get("/v1/anonymous/session", as: AnonymousSession.self)
    }

    static func attest() async throws -> AnonymousSession {
        try await post("/v1/anonymous/attest", body: ["confirmed": true], as: AnonymousSession.self)
    }

    static func claimProfile(username: String? = nil) async throws -> AnonymousProfile {
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
        let env: Envelope = try await post("/v1/anonymous/profile/claim", body: body, as: Envelope.self)
        guard let profile = env.resolved else { throw AnonymousError.decoding }
        return profile
    }

    static func me() async throws -> AnonymousProfile {
        try await get("/v1/anonymous/me", as: AnonymousProfile.self)
    }

    static func suggestUsername() async throws -> String {
        struct Resp: Decodable {
            let username: String?
            let suggestedUsername: String?
        }
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
        let data = try JSONEncoder().encode(input)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return try await post("/v1/anonymous/spaces/\(spaceId)/posts", body: obj, as: AnonymousPost.self)
    }

    static func listComments(
        postId: String,
        cursor: String? = nil,
        limit: Int = 40
    ) async throws -> AnonymousPage<AnonymousComment> {
        var q: [String: String] = ["limit": "\(min(max(limit, 1), 80))"]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await getPage("/v1/anonymous/posts/\(postId)/comments", query: q, itemType: AnonymousComment.self)
    }

    static func createComment(postId: String, input: AnonymousCreateCommentInput) async throws -> AnonymousComment {
        let data = try JSONEncoder().encode(input)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return try await post("/v1/anonymous/posts/\(postId)/comments", body: obj, as: AnonymousComment.self)
    }

    static func vote(targetType: String, targetId: String, value: Int) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await post(
            "/v1/anonymous/vote",
            body: ["targetType": targetType, "targetId": targetId, "value": value],
            as: Empty.self,
            allowEmpty: true
        )
    }

    static func report(targetType: String, targetId: String, reason: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await post(
            "/v1/anonymous/report",
            body: ["targetType": targetType, "targetId": targetId, "reason": reason],
            as: Empty.self,
            allowEmpty: true
        )
    }

    static func block(profileId: String) async throws {
        struct Empty: Codable {}
        let _: Empty = try await post(
            "/v1/anonymous/block",
            body: ["profileId": profileId],
            as: Empty.self,
            allowEmpty: true
        )
    }

    static func feed(
        sort: AnonymousFeedSort = .hot,
        cursor: String? = nil,
        limit: Int = 24
    ) async throws -> AnonymousPage<AnonymousPost> {
        var q: [String: String] = [
            "sort": sort.rawValue,
            "limit": "\(min(max(limit, 1), 48))",
        ]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        return try await getPage("/v1/anonymous/feed", query: q, itemType: AnonymousPost.self)
    }

    // MARK: - HTTP

    private static func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let req = try await makeRequest(path: path, method: "GET", query: nil, body: nil)
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
                message = json["message"] as? String ?? json["error"] as? String
            }
            throw AnonymousError.from(code: code, message: message ?? "HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnonymousError.decoding
        }
        if let code = json["code"] as? String, json["ok"] as? Bool == false {
            throw AnonymousError.from(code: code, message: json["message"] as? String)
        }
        let payload = (json["data"] as? [String: Any]) ?? json
        let rawItems = payload["items"] as? [[String: Any]] ?? []
        let itemsData = try JSONSerialization.data(withJSONObject: rawItems)
        let items = (try? JSONDecoder.anonymous.decode([T].self, from: itemsData)) ?? []
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

        // Cached token only — never stall first paint on token refresh.
        if let token = await MainActor.run(body: { AuthService.shared.accessToken() }) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
                    throw AnonymousError.from(code: code, message: json["message"] as? String)
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
            message = json["message"] as? String ?? json["error"] as? String
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
}

private extension JSONDecoder {
    static let anonymous: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
