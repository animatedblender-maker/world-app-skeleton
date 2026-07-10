import Foundation

@MainActor
final class StreamingHubService {
    static let shared = StreamingHubService()

    private let followService = FollowService.shared
    private let profileService = ProfileService.shared
    private let rest = SupabaseRESTClient.shared

    private let nowPlayingTTL: TimeInterval = 30 * 60

    private init() {}

    func loadHub() async throws -> ConnectedHubSnapshot {
        async let connections = fetchConnections()
        async let nowPlaying = fetchMyNowPlaying()
        async let friends = fetchFriendsActivity()
        let rooms = try await buildMomentRooms(
            mine: try await nowPlaying,
            friends: try await friends
        )

        return ConnectedHubSnapshot(
            accounts: ConnectedHubContent.mergedAccounts(try await connections),
            nowPlaying: try await nowPlaying,
            friends: try await friends,
            momentRooms: rooms
        )
    }

    func linkPlatform(_ platform: StreamingPlatform) async throws -> ConnectedAccount {
        let userID = try currentUserID()
        let now = isoNow()
        let rows: [SupabaseStreamingConnection] = try await rest.upsert(
            table: "streaming_platform_connections",
            rows: [[
                "user_id": userID,
                "platform": platform.apiSlug,
                "is_linked": true,
                "sharing_enabled": true,
                "linked_at": now,
                "updated_at": now,
            ]],
            onConflict: "user_id,platform"
        )
        return (rows.first ?? SupabaseStreamingConnection(
            platform: platform.apiSlug,
            isLinked: true,
            sharingEnabled: true,
            linkedAt: now
        )).toModel()
    }

    func unlinkPlatform(_ platform: StreamingPlatform) async throws {
        let userID = try currentUserID()
        try await rest.patchVoid(
            table: "streaming_platform_connections",
            filters: [
                "user_id": "eq.\(userID)",
                "platform": "eq.\(platform.apiSlug)",
            ],
            body: [
                "is_linked": false,
                "sharing_enabled": false,
                "updated_at": isoNow(),
            ]
        )
        _ = try await rest.delete(
            table: "now_playing_status",
            filters: [
                "user_id": "eq.\(userID)",
                "platform": "eq.\(platform.apiSlug)",
            ]
        )
    }

    func setPlatformSharing(_ platform: StreamingPlatform, enabled: Bool) async throws -> ConnectedAccount {
        let userID = try currentUserID()
        let now = isoNow()
        let rows: [SupabaseStreamingConnection] = try await rest.upsert(
            table: "streaming_platform_connections",
            rows: [[
                "user_id": userID,
                "platform": platform.apiSlug,
                "is_linked": true,
                "sharing_enabled": enabled,
                "linked_at": now,
                "updated_at": now,
            ]],
            onConflict: "user_id,platform"
        )
        try await rest.patchVoid(
            table: "now_playing_status",
            filters: [
                "user_id": "eq.\(userID)",
                "platform": "eq.\(platform.apiSlug)",
            ],
            body: [
                "is_sharing": enabled,
                "updated_at": now,
            ]
        )
        return (rows.first ?? SupabaseStreamingConnection(
            platform: platform.apiSlug,
            isLinked: true,
            sharingEnabled: enabled,
            linkedAt: now
        )).toModel()
    }

    func fetchFriendsActivityOnly() async throws -> [FriendActivity] {
        try await fetchFriendsActivity()
    }

    func updateNowPlaying(
        platform: StreamingPlatform,
        title: String,
        subtitle: String?,
        momentLabel: String?,
        progressMinutes: Int,
        progressSeconds: Int,
        durationMinutes: Int,
        isSharing: Bool,
        contentId: String? = nil
    ) async throws -> YourNowPlaying {
        let progressMs = (progressMinutes * 60 + progressSeconds) * 1000
        let durationMs = max(durationMinutes * 60 * 1000, progressMs + 60_000)
        return try await updateNowPlaying(
            platform: platform,
            title: title,
            subtitle: subtitle,
            momentLabel: momentLabel,
            progressMs: progressMs,
            durationMs: durationMs,
            isSharing: isSharing,
            contentId: contentId
        )
    }

    func updateNowPlaying(
        platform: StreamingPlatform,
        title: String,
        subtitle: String?,
        momentLabel: String?,
        progressMs: Int,
        durationMs: Int,
        isSharing: Bool,
        contentId: String? = nil
    ) async throws -> YourNowPlaying {
        let userID = try currentUserID()
        let now = isoNow()

        _ = try await linkPlatform(platform)

        var row: [String: Any] = [
            "user_id": userID,
            "platform": platform.apiSlug,
            "title": title,
            "progress_ms": progressMs,
            "duration_ms": durationMs,
            "is_sharing": isSharing,
            "updated_at": now,
        ]
        if let subtitle, !subtitle.isEmpty { row["subtitle"] = subtitle }
        if let momentLabel, !momentLabel.isEmpty { row["moment_label"] = momentLabel }
        if let contentId, !contentId.isEmpty { row["content_id"] = contentId }

        let rows: [SupabaseNowPlayingRow] = try await rest.upsert(
            table: "now_playing_status",
            rows: [row],
            onConflict: "user_id,platform"
        )
        guard let saved = rows.first else {
            throw StreamingHubError.saveFailed
        }
        return saved.toModel()
    }

    func clearNowPlaying(_ platform: StreamingPlatform) async throws {
        let userID = try currentUserID()
        _ = try await rest.delete(
            table: "now_playing_status",
            filters: [
                "user_id": "eq.\(userID)",
                "platform": "eq.\(platform.apiSlug)",
            ]
        )
    }

    func momentRoomComments(roomKey: String) async throws -> [MomentComment] {
        let userID = try currentUserID()
        let rows: [SupabaseMomentCommentRow] = try await rest.select(
            table: "moment_room_comments",
            filters: [
                "room_key": "eq.\(roomKey)",
                "order": "created_at.asc",
                "limit": "50",
            ]
        )
        return await mapComments(rows, viewerID: userID)
    }

    func addMomentRoomComment(roomKey: String, body: String) async throws -> MomentComment {
        let userID = try currentUserID()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StreamingHubError.emptyComment }

        let rows: [SupabaseMomentCommentRow] = try await rest.insert(
            table: "moment_room_comments",
            rows: [[
                "room_key": roomKey,
                "author_id": userID,
                "body": trimmed,
            ]]
        )
        guard let saved = rows.first else { throw StreamingHubError.saveFailed }
        let mapped = await mapComments([saved], viewerID: userID)
        return mapped[0]
    }

    // MARK: - Private

    private func currentUserID() throws -> String {
        guard let id = AuthService.shared.currentUser?.id else {
            throw StreamingHubError.notAuthenticated
        }
        return id
    }

    private func fetchConnections() async throws -> [ConnectedAccount] {
        let userID = try currentUserID()
        let rows: [SupabaseStreamingConnection] = try await rest.select(
            table: "streaming_platform_connections",
            filters: ["user_id": "eq.\(userID)"]
        )
        return rows.map { $0.toModel() }
    }

    private func fetchMyNowPlaying() async throws -> [YourNowPlaying] {
        let userID = try currentUserID()
        let rows: [SupabaseNowPlayingRow] = try await rest.select(
            table: "now_playing_status",
            filters: [
                "user_id": "eq.\(userID)",
                "order": "updated_at.desc",
            ]
        )
        return rows.map { $0.toModel() }
    }

    private func fetchFriendsActivity() async throws -> [FriendActivity] {
        let following = await followService.followingIDs().filter { !$0.hasPrefix("user_") }
        guard !following.isEmpty else { return [] }

        let cutoff = isoCutoff()
        let idList = following.sorted().joined(separator: ",")
        let rows: [SupabaseNowPlayingRow] = try await rest.select(
            table: "now_playing_status",
            filters: [
                "user_id": "in.(\(idList))",
                "is_sharing": "eq.true",
                "updated_at": "gte.\(cutoff)",
                "order": "updated_at.desc",
                "limit": "20",
            ]
        )

        var activities: [FriendActivity] = []
        for row in rows {
            guard let profile = try await profileService.profileByID(row.userID) else { continue }
            let isLive = await fetchIsLive(userID: row.userID)
            activities.append(row.toFriendActivity(profile: profile, isLive: isLive))
        }
        return activities
    }

    private func fetchIsLive(userID: String) async -> Bool {
        struct PresenceRow: Decodable {
            let isOnline: Bool
            let lastSeenAt: String?

            enum CodingKeys: String, CodingKey {
                case isOnline = "is_online"
                case lastSeenAt = "last_seen_at"
            }
        }

        let rows: [PresenceRow] = (try? await rest.select(
            table: "user_presence",
            filters: [
                "user_id": "eq.\(userID)",
                "select": "is_online,last_seen_at",
                "limit": "1",
            ]
        )) ?? []

        guard let row = rows.first, row.isOnline, let lastSeenAt = row.lastSeenAt else {
            return false
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: lastSeenAt) ?? ISO8601DateFormatter().date(from: lastSeenAt) {
            return date.timeIntervalSinceNow > -70
        }
        return false
    }

    private func buildMomentRooms(
        mine: [YourNowPlaying],
        friends: [FriendActivity]
    ) async throws -> [MomentRoom] {
        let userID = try currentUserID()
        let following = await followService.followingIDs().filter { !$0.hasPrefix("user_") }
        let cutoff = isoCutoff()

        var filters = [
            "is_sharing": "eq.true",
            "updated_at": "gte.\(cutoff)",
            "order": "updated_at.desc",
        ] as [String: String]

        var orClause = "user_id.eq.\(userID)"
        if !following.isEmpty {
            let idList = following.sorted().joined(separator: ",")
            orClause += ",user_id.in.(\(idList))"
        }
        filters["or"] = "(\(orClause))"

        let rows: [SupabaseNowPlayingRow] = try await rest.select(
            table: "now_playing_status",
            filters: filters
        )

        struct RoomAgg {
            var roomKey: String
            var platform: String
            var showTitle: String
            var episodeLabel: String
            var timestampLabel: String
            var activeFriends: Int
        }

        var roomMap: [String: RoomAgg] = [:]
        for row in rows where row.isSharing {
            let built = StreamingHubRoomKey.build(
                platform: row.platform,
                title: row.title,
                subtitle: row.subtitle,
                progressMs: row.progressMs
            )
            if var existing = roomMap[built.roomKey] {
                existing.activeFriends += 1
                roomMap[built.roomKey] = existing
            } else {
                roomMap[built.roomKey] = RoomAgg(
                    roomKey: built.roomKey,
                    platform: row.platform,
                    showTitle: row.title,
                    episodeLabel: row.subtitle ?? "Now playing",
                    timestampLabel: built.timestampLabel,
                    activeFriends: 1
                )
            }
        }

        let sorted = roomMap.values.sorted { $0.activeFriends > $1.activeFriends }.prefix(12)
        var rooms: [MomentRoom] = []

        for agg in sorted {
            let commentRows: [SupabaseMomentCommentRow] = try await rest.select(
                table: "moment_room_comments",
                filters: [
                    "room_key": "eq.\(agg.roomKey)",
                    "order": "created_at.desc",
                    "limit": "3",
                ]
            )
            let comments = await mapComments(commentRows.reversed(), viewerID: userID)
            let heat = min(1.0, Double(agg.activeFriends) / 15.0 + Double(comments.count) / 10.0)
            let platform = StreamingPlatform.fromAPISlug(agg.platform) ?? .netflix
            rooms.append(MomentRoom(
                id: agg.roomKey,
                roomKey: agg.roomKey,
                platform: platform,
                showTitle: agg.showTitle,
                episodeLabel: agg.episodeLabel,
                timestamp: agg.timestampLabel,
                activeFriends: agg.activeFriends,
                previewComments: comments,
                heat: heat
            ))
        }

        return rooms
    }

    private func mapComments(_ rows: [SupabaseMomentCommentRow], viewerID: String) async -> [MomentComment] {
        var results: [MomentComment] = []
        for row in rows {
            let author: String
            if row.authorID == viewerID {
                author = "You"
            } else if let profile = try? await profileService.profileByID(row.authorID) {
                author = profile.displayName ?? profile.username ?? "Friend"
            } else {
                author = "Friend"
            }
            results.append(MomentComment(
                id: row.id,
                author: author,
                body: row.body,
                reactions: row.reactions
            ))
        }
        return results
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func isoCutoff() -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-nowPlayingTTL))
    }
}

struct ConnectedHubSnapshot {
    let accounts: [ConnectedAccount]
    let nowPlaying: [YourNowPlaying]
    let friends: [FriendActivity]
    let momentRooms: [MomentRoom]
}

enum StreamingHubError: LocalizedError {
    case notAuthenticated
    case saveFailed
    case emptyComment

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Please sign in again."
        case .saveFailed: "Could not save your streaming status."
        case .emptyComment: "Write a comment before sending."
        }
    }
}

enum StreamingHubRoomKey {
    static func build(platform: String, title: String, subtitle: String?, progressMs: Int) -> (roomKey: String, timestampLabel: String) {
        let bucketSizeMs = platform == "apple_music" ? 10_000 : 60_000
        let bucketMs = max(0, progressMs / bucketSizeMs) * bucketSizeMs
        let slug = { (value: String) in
            value.lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                .prefix(48)
        }
        let roomKey = "\(platform):\(slug(title)):\(slug(subtitle ?? "")):\(bucketMs)"
        return (String(roomKey), formatTimestamp(bucketMs))
    }

    static func formatTimestamp(_ progressMs: Int) -> String {
        let totalSec = max(0, progressMs / 1000)
        return String(format: "%d:%02d", totalSec / 60, totalSec % 60)
    }
}

// MARK: - Supabase REST

@MainActor
final class SupabaseRESTClient {
    static let shared = SupabaseRESTClient()

    private let baseURL = URL(string: "\(AppConfig.supabaseURL)/rest/v1")!
    private let decoder = JSONDecoder()

    private init() {}

    func select<T: Decodable>(table: String, filters: [String: String]) async throws -> [T] {
        try await request(method: "GET", path: table, queryItems: queryItems(from: filters))
    }

    func insert<T: Decodable>(table: String, rows: [[String: Any]]) async throws -> [T] {
        try await request(
            method: "POST",
            path: table,
            queryItems: [URLQueryItem(name: "select", value: "*")],
            body: rows,
            prefer: "return=representation"
        )
    }

    func upsert<T: Decodable>(table: String, rows: [[String: Any]], onConflict: String) async throws -> [T] {
        try await request(
            method: "POST",
            path: table,
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "on_conflict", value: onConflict),
            ],
            body: rows,
            prefer: "return=representation,resolution=merge-duplicates"
        )
    }

    func patch<T: Decodable>(table: String, filters: [String: String], body: [String: Any]) async throws -> [T] {
        var items = queryItems(from: filters)
        items.append(URLQueryItem(name: "select", value: "*"))
        return try await request(
            method: "PATCH",
            path: table,
            queryItems: items,
            body: body,
            prefer: "return=representation"
        )
    }

    func patchVoid(table: String, filters: [String: String], body: [String: Any]) async throws {
        try await requestVoid(
            method: "PATCH",
            path: table,
            queryItems: queryItems(from: filters),
            body: body
        )
    }

    func delete(table: String, filters: [String: String]) async throws {
        try await requestVoid(method: "DELETE", path: table, queryItems: queryItems(from: filters))
    }

    private func queryItems(from filters: [String: String]) -> [URLQueryItem] {
        filters
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Any? = nil,
        prefer: String? = nil
    ) async throws -> T {
        let data = try await perform(method: method, path: path, queryItems: queryItems, body: body, prefer: prefer)
        if data.isEmpty {
            return try decoder.decode(T.self, from: Data("[]".utf8))
        }
        return try decoder.decode(T.self, from: data)
    }

    private func requestVoid(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Any? = nil,
        prefer: String? = nil
    ) async throws {
        _ = try await perform(method: method, path: path, queryItems: queryItems, body: body, prefer: prefer)
    }

    private func perform(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Any?,
        prefer: String?
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw StreamingHubRESTError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }

        let token = try await AuthService.shared.ensureValidToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StreamingHubRESTError.network("No HTTP response.")
        }

        if http.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Request failed."
            throw StreamingHubRESTError.http(http.statusCode, message)
        }

        return data
    }
}

enum StreamingHubRESTError: LocalizedError {
    case invalidURL
    case network(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Supabase URL."
        case .network(let message): message
        case .http(let code, let message): "Supabase error \(code): \(message)"
        }
    }
}

// MARK: - Row models

private struct SupabaseStreamingConnection: Decodable {
    let platform: String
    let isLinked: Bool
    let sharingEnabled: Bool
    let linkedAt: String?

    enum CodingKeys: String, CodingKey {
        case platform
        case isLinked = "is_linked"
        case sharingEnabled = "sharing_enabled"
        case linkedAt = "linked_at"
    }

    func toModel() -> ConnectedAccount {
        let mapped = StreamingPlatform.fromAPISlug(platform) ?? .netflix
        return ConnectedAccount(
            id: mapped.rawValue,
            platform: mapped,
            isLinked: isLinked,
            sharingEnabled: sharingEnabled
        )
    }
}

private struct SupabaseNowPlayingRow: Decodable {
    let id: String
    let userID: String
    let platform: String
    let title: String
    let subtitle: String?
    let momentLabel: String?
    let progressMs: Int
    let durationMs: Int
    let isSharing: Bool
    let contentId: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, platform, title, subtitle
        case userID = "user_id"
        case momentLabel = "moment_label"
        case progressMs = "progress_ms"
        case durationMs = "duration_ms"
        case isSharing = "is_sharing"
        case contentId = "content_id"
        case updatedAt = "updated_at"
    }

    private var parsedUpdatedAt: Date {
        guard let updatedAt else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: updatedAt)
            ?? ISO8601DateFormatter().date(from: updatedAt)
            ?? Date()
    }

    func toModel() -> YourNowPlaying {
        let mapped = StreamingPlatform.fromAPISlug(platform) ?? .netflix
        let duration = max(durationMs, 1)
        let progress = min(1.0, max(0.0, Double(progressMs) / Double(duration)))
        return YourNowPlaying(
            id: id,
            platform: mapped,
            title: title,
            subtitle: subtitle ?? "",
            progressLabel: StreamingHubRoomKey.formatTimestamp(progressMs),
            progress: progress,
            isSharing: isSharing,
            momentLabel: momentLabel,
            contentId: contentId,
            progressMs: progressMs,
            durationMs: durationMs,
            updatedAt: parsedUpdatedAt
        )
    }

    func toFriendActivity(profile: Profile, isLive: Bool) -> FriendActivity {
        let mapped = StreamingPlatform.fromAPISlug(platform) ?? .netflix
        let stamp = StreamingHubRoomKey.formatTimestamp(progressMs)
        let detail = subtitle.map { "\($0) · \(stamp)" } ?? stamp
        return FriendActivity(
            id: userID,
            name: profile.displayName ?? profile.username ?? "Friend",
            avatarURL: profile.avatarURL,
            avatarSeed: userID,
            platform: mapped,
            title: title,
            subtitle: subtitle ?? "",
            detail: detail,
            isLive: isLive && isSharing,
            contentId: contentId,
            progressMs: progressMs,
            durationMs: durationMs,
            updatedAt: parsedUpdatedAt
        )
    }

}

private struct SupabaseMomentCommentRow: Decodable {
    let id: String
    let authorID: String
    let body: String
    let reactions: Int

    enum CodingKeys: String, CodingKey {
        case id, body, reactions
        case authorID = "author_id"
    }
}