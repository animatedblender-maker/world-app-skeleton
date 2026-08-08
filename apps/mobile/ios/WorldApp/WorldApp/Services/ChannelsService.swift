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
