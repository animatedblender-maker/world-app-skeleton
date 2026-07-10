import Foundation

@MainActor
final class NotificationsService {
    static let shared = NotificationsService()

    private let gql = GraphQLService.shared
    private init() {}

    func list(limit: Int = 40) async -> [NotificationItem] {
        struct Response: Decodable { let notifications: [GraphQLNotification] }
        let query = """
        query Notifications($limit: Int) {
          notifications(limit: $limit) {
            id user_id actor_id type entity_type entity_id read_at created_at
            actor { user_id display_name username avatar_url }
          }
        }
        """
        do {
            let result: Response = try await gql.authenticatedRequest(query: query, variables: ["limit": limit])
            return result.notifications.map(\.toModel)
        } catch {
            return []
        }
    }

    func unreadCount() async -> Int {
        struct Response: Decodable { let notificationsUnreadCount: Int }
        let query = "query { notificationsUnreadCount }"
        do {
            let result: Response = try await gql.authenticatedRequest(query: query)
            return result.notificationsUnreadCount
        } catch {
            return 0
        }
    }

    func markRead(_ id: String) async throws {
        let mutation = "mutation($id: ID!) { markNotificationRead(id: $id) }"
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation, variables: ["id": id])
    }

    func markAllRead() async throws {
        let mutation = "mutation { markAllNotificationsRead }"
        let _: EmptyMutation = try await gql.authenticatedRequest(query: mutation)
    }
}

private struct GraphQLNotification: Decodable {
    let id: String
    let userID: String
    let actorID: String?
    let type: String
    let entityType: String?
    let entityID: String?
    let readAt: String?
    let createdAt: String
    let actor: GraphQLNotificationActor?

    enum CodingKeys: String, CodingKey {
        case id, type, actor
        case userID = "user_id"
        case actorID = "actor_id"
        case entityType = "entity_type"
        case entityID = "entity_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    var toModel: NotificationItem {
        NotificationItem(
            id: id,
            userID: userID,
            actorID: actorID,
            type: type,
            entityType: entityType,
            entityID: entityID,
            readAt: readAt,
            createdAt: createdAt,
            actor: actor?.toModel
        )
    }
}

private struct GraphQLNotificationActor: Decodable {
    let userID: String
    let displayName: String?
    let username: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case username
        case avatarURL = "avatar_url"
    }

    var toModel: PostAuthor {
        PostAuthor(
            userID: userID,
            displayName: displayName,
            username: username,
            avatarURL: avatarURL,
            countryName: nil,
            countryCode: nil,
            lastReadAt: nil
        )
    }
}