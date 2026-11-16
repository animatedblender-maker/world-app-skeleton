import Foundation

/// GraphQL client for first-class Hubs channels + admin membership.
@MainActor
final class ChannelsService {
    static let shared = ChannelsService()

    private let gql = GraphQLService.shared

    private init() {}

    private static let channelFields = """
    id owner_user_id name handle about avatar_url cover_url created_at updated_at
    my_role video_count
    owner { user_id display_name username avatar_url country_name country_code }
    """

    private static let memberFields = """
    channel_id user_id role invited_by created_at
    profile { user_id display_name username avatar_url country_name country_code }
    """

    // MARK: - Queries

    func myChannel() async throws -> HubChannel? {
        struct Response: Decodable {
            let myChannel: GQLChannel?
        }
        let query = """
        query {
          myChannel { \(Self.channelFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query)
        return result.myChannel?.toModel
    }

    func channel(id: String) async throws -> HubChannel? {
        struct Response: Decodable {
            let channel: GQLChannel?
        }
        let query = """
        query($id: ID!) {
          channel(id: $id) { \(Self.channelFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["id": id]
        )
        return result.channel?.toModel
    }

    func channelByOwner(userID: String) async throws -> HubChannel? {
        struct Response: Decodable {
            let channelByOwner: GQLChannel?
        }
        let query = """
        query($userId: ID!) {
          channelByOwner(user_id: $userId) { \(Self.channelFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["userId": userID]
        )
        return result.channelByOwner?.toModel
    }

    func members(channelID: String) async throws -> [ChannelMember] {
        struct Response: Decodable {
            let channelMembers: [GQLChannelMember]
        }
        let query = """
        query($channelId: ID!) {
          channelMembers(channel_id: $channelId) { \(Self.memberFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["channelId": channelID]
        )
        return result.channelMembers.map(\.toModel)
    }

    func channelsIAdmin() async throws -> [HubChannel] {
        struct Response: Decodable {
            let channelsIAdmin: [GQLChannel]
        }
        let query = """
        query {
          channelsIAdmin { \(Self.channelFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query)
        return result.channelsIAdmin.map(\.toModel)
    }

    // MARK: - Channel Subscribe (REST — not profile Follow)

    struct ChannelSubscriptionStatus: Equatable {
        var channelId: String
        var subscribed: Bool
        var subscriberCount: Int
    }

    func subscriptionStatus(channelID: String? = nil, ownerUserID: String? = nil) async throws -> ChannelSubscriptionStatus {
        var query: [String: String] = [:]
        if let channelID, !channelID.isEmpty { query["channel_id"] = channelID }
        if let ownerUserID, !ownerUserID.isEmpty { query["owner_user_id"] = ownerUserID }
        let json = try await restJSON(method: "GET", path: "/v1/channels/subscription", query: query, body: nil)
        return parseSubscription(json)
    }

    func subscribe(channelID: String? = nil, ownerUserID: String? = nil) async throws -> ChannelSubscriptionStatus {
        var body: [String: Any] = [:]
        if let channelID, !channelID.isEmpty { body["channel_id"] = channelID }
        if let ownerUserID, !ownerUserID.isEmpty { body["owner_user_id"] = ownerUserID }
        let json = try await restJSON(method: "POST", path: "/v1/channels/subscribe", query: [:], body: body)
        return parseSubscription(json)
    }

    func unsubscribe(channelID: String? = nil, ownerUserID: String? = nil) async throws -> ChannelSubscriptionStatus {
        var body: [String: Any] = [:]
        if let channelID, !channelID.isEmpty { body["channel_id"] = channelID }
        if let ownerUserID, !ownerUserID.isEmpty { body["owner_user_id"] = ownerUserID }
        let json = try await restJSON(method: "POST", path: "/v1/channels/unsubscribe", query: [:], body: body)
        return parseSubscription(json)
    }

    func toggleSubscribe(channelID: String? = nil, ownerUserID: String? = nil) async throws -> ChannelSubscriptionStatus {
        let status = try await subscriptionStatus(channelID: channelID, ownerUserID: ownerUserID)
        if status.subscribed {
            return try await unsubscribe(channelID: channelID ?? status.channelId, ownerUserID: ownerUserID)
        }
        return try await subscribe(channelID: channelID ?? status.channelId, ownerUserID: ownerUserID)
    }

    private func parseSubscription(_ json: [String: Any]) -> ChannelSubscriptionStatus {
        ChannelSubscriptionStatus(
            channelId: String(json["channelId"] as? String ?? json["channel_id"] as? String ?? ""),
            subscribed: (json["subscribed"] as? Bool) ?? false,
            subscriberCount: Int(json["subscriberCount"] as? Int ?? json["subscriber_count"] as? Int ?? 0)
        )
    }

    private func restJSON(
        method: String,
        path: String,
        query: [String: String],
        body: [String: Any]?
    ) async throws -> [String: Any] {
        guard let token = try? await AuthService.shared.ensureValidToken(), !token.isEmpty else {
            throw ChannelsRESTError.unauthenticated
        }
        var comps = URLComponents(string: "\(AppConfig.apiBaseURL)\(path)")
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { throw ChannelsRESTError.message("Invalid URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        if method == "POST" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body ?? [:])
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = http?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let err = String(json["error"] as? String ?? "Request failed (\(status))")
            if status == 401 { throw ChannelsRESTError.unauthenticated }
            if err == "channel_not_found" { throw ChannelsRESTError.channelNotFound }
            throw ChannelsRESTError.message(err)
        }
        return json
    }

    // MARK: - Mutations

    func createChannel(
        name: String,
        about: String? = nil,
        avatarURL: String? = nil,
        coverURL: String? = nil,
        handle: String? = nil
    ) async throws -> HubChannel {
        struct Response: Decodable {
            let createChannel: GQLChannel
        }
        let mutation = """
        mutation($input: CreateChannelInput!) {
          createChannel(input: $input) { \(Self.channelFields) }
        }
        """
        var input: [String: Any] = ["name": name]
        if let about, !about.isEmpty { input["about"] = about }
        if let avatarURL, !avatarURL.isEmpty { input["avatar_url"] = avatarURL }
        if let coverURL, !coverURL.isEmpty { input["cover_url"] = coverURL }
        if let handle, !handle.isEmpty { input["handle"] = handle }

        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["input": input]
        )
        return result.createChannel.toModel
    }

    func updateChannel(
        id: String,
        name: String? = nil,
        about: String? = nil,
        avatarURL: String? = nil,
        coverURL: String? = nil,
        handle: String? = nil
    ) async throws -> HubChannel {
        struct Response: Decodable {
            let updateChannel: GQLChannel
        }
        let mutation = """
        mutation($id: ID!, $input: UpdateChannelInput!) {
          updateChannel(id: $id, input: $input) { \(Self.channelFields) }
        }
        """
        var input: [String: Any] = [:]
        if let name { input["name"] = name }
        if let about { input["about"] = about }
        if let avatarURL { input["avatar_url"] = avatarURL }
        if let coverURL { input["cover_url"] = coverURL }
        if let handle { input["handle"] = handle }

        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["id": id, "input": input]
        )
        return result.updateChannel.toModel
    }

    func addAdmin(channelID: String, userID: String) async throws -> ChannelMember {
        struct Response: Decodable {
            let addChannelAdmin: GQLChannelMember
        }
        let mutation = """
        mutation($channelId: ID!, $userId: ID!) {
          addChannelAdmin(channel_id: $channelId, user_id: $userId) { \(Self.memberFields) }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["channelId": channelID, "userId": userID]
        )
        return result.addChannelAdmin.toModel
    }

    func removeAdmin(channelID: String, userID: String) async throws -> Bool {
        struct Response: Decodable {
            let removeChannelAdmin: Bool
        }
        let mutation = """
        mutation($channelId: ID!, $userId: ID!) {
          removeChannelAdmin(channel_id: $channelId, user_id: $userId)
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["channelId": channelID, "userId": userID]
        )
        return result.removeChannelAdmin
    }

    func transferOwnership(channelID: String, newOwnerUserID: String) async throws -> HubChannel {
        struct Response: Decodable {
            let transferChannelOwnership: GQLChannel
        }
        let mutation = """
        mutation($channelId: ID!, $newOwner: ID!) {
          transferChannelOwnership(channel_id: $channelId, new_owner_user_id: $newOwner) {
            \(Self.channelFields)
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["channelId": channelID, "newOwner": newOwnerUserID]
        )
        return result.transferChannelOwnership.toModel
    }

    func setPostHidden(postID: String, hidden: Bool) async throws -> Bool {
        struct Response: Decodable {
            let setChannelPostHidden: Bool
        }
        let mutation = """
        mutation($postId: ID!, $hidden: Boolean!) {
          setChannelPostHidden(post_id: $postId, hidden: $hidden)
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["postId": postID, "hidden": hidden]
        )
        return result.setChannelPostHidden
    }

    func deleteComment(commentID: String) async throws -> Bool {
        struct Response: Decodable {
            let deleteChannelComment: Bool
        }
        let mutation = """
        mutation($commentId: ID!) {
          deleteChannelComment(comment_id: $commentId)
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["commentId": commentID]
        )
        return result.deleteChannelComment
    }
}

enum ChannelsRESTError: LocalizedError {
    case unauthenticated
    case channelNotFound
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated: return "Sign in to subscribe."
        case .channelNotFound: return "Channel not found."
        case .message(let s): return s
        }
    }
}

// MARK: - GraphQL DTOs

private struct GQLChannel: Decodable {
    let id: String
    let ownerUserID: String
    let name: String
    let handle: String?
    let about: String?
    let avatarURL: String?
    let coverURL: String?
    let createdAt: String
    let updatedAt: String
    let owner: GQLPostAuthor?
    let myRole: String?
    let videoCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case name, handle, about
        case avatarURL = "avatar_url"
        case coverURL = "cover_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case owner
        case myRole = "my_role"
        case videoCount = "video_count"
    }

    var toModel: HubChannel {
        HubChannel(
            id: id,
            ownerUserID: ownerUserID,
            name: name,
            handle: handle,
            about: about,
            avatarURL: avatarURL,
            coverURL: coverURL,
            createdAt: createdAt,
            updatedAt: updatedAt,
            owner: owner?.toModel,
            myRole: myRole.flatMap(ChannelMemberRole.init(rawValue:)),
            videoCount: videoCount ?? 0
        )
    }
}

private struct GQLChannelMember: Decodable {
    let channelID: String
    let userID: String
    let role: String
    let invitedBy: String?
    let createdAt: String
    let profile: GQLPostAuthor?

    enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
        case userID = "user_id"
        case role
        case invitedBy = "invited_by"
        case createdAt = "created_at"
        case profile
    }

    var toModel: ChannelMember {
        ChannelMember(
            channelID: channelID,
            userID: userID,
            role: ChannelMemberRole(rawValue: role) ?? .admin,
            invitedBy: invitedBy,
            createdAt: createdAt,
            profile: profile?.toModel
        )
    }
}

private struct GQLPostAuthor: Decodable {
    let userID: String
    let displayName: String?
    let username: String?
    let avatarURL: String?
    let countryName: String?
    let countryCode: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case username
        case avatarURL = "avatar_url"
        case countryName = "country_name"
        case countryCode = "country_code"
    }

    var toModel: PostAuthor {
        PostAuthor(
            userID: userID,
            displayName: displayName,
            username: username,
            avatarURL: avatarURL,
            countryName: countryName,
            countryCode: countryCode,
            lastReadAt: nil
        )
    }
}
