import Foundation

@MainActor
final class MessagesService {
    static let shared = MessagesService()

    private let gql = GraphQLService.shared

    private init() {}

    func listConversations(limit: Int = 40) async throws -> [Conversation] {
        struct Response: Decodable {
            let conversations: [GraphQLConversation]
        }

        let query = """
        query Conversations($limit: Int) {
          conversations(limit: $limit) {
            id is_direct created_at updated_at last_message_at
            members {
              user_id display_name username avatar_url country_name country_code last_read_at
            }
            last_message {
              id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
              sender { user_id display_name username avatar_url country_name country_code }
            }
          }
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["limit": limit]
        )
        return result.conversations.map(\.toModel)
    }

    func listMessages(conversationID: String, limit: Int = 50) async throws -> [Message] {
        struct Response: Decodable {
            let messagesByConversation: [GraphQLMessage]
        }

        let query = """
        query MessagesByConversation($conversationId: ID!, $limit: Int) {
          messagesByConversation(conversation_id: $conversationId, limit: $limit) {
            id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
            sender { user_id display_name username avatar_url country_name country_code }
          }
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["conversationId": conversationID, "limit": limit]
        )
        var messages = result.messagesByConversation.map(\.toModel)
        await withTaskGroup(of: (Int, Message).self) { group in
            for index in messages.indices {
                let message = messages[index]
                group.addTask { [self] in
                    (index, await hydrateMedia(message))
                }
            }
            for await (index, hydrated) in group {
                messages[index] = hydrated
            }
        }
        return messages
    }

    func startConversation(targetID: String) async throws -> Conversation {
        struct Response: Decodable {
            let startConversation: GraphQLConversation
        }

        let mutation = """
        mutation StartConversation($targetId: ID!) {
          startConversation(target_id: $targetId) {
            id is_direct created_at updated_at last_message_at
            members {
              user_id display_name username avatar_url country_name country_code last_read_at
            }
            last_message {
              id conversation_id sender_id body media_type media_path media_name created_at updated_at
              sender { user_id display_name username avatar_url country_name country_code }
            }
          }
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["targetId": targetID]
        )
        return result.startConversation.toModel
    }

    func getConversationById(_ conversationID: String) async throws -> Conversation? {
        struct Response: Decodable {
            let conversationById: GraphQLConversation?
        }

        let query = """
        query ConversationById($conversationId: ID!) {
          conversationById(conversation_id: $conversationId) {
            id is_direct created_at updated_at last_message_at
            members {
              user_id display_name username avatar_url country_name country_code last_read_at
            }
            last_message {
              id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
              sender { user_id display_name username avatar_url country_name country_code }
            }
          }
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["conversationId": conversationID]
        )
        guard let row = result.conversationById else { return nil }
        var conversation = row.toModel
        if let last = conversation.lastMessage {
            conversation = Conversation(
                id: conversation.id,
                isDirect: conversation.isDirect,
                createdAt: conversation.createdAt,
                updatedAt: conversation.updatedAt,
                lastMessageAt: conversation.lastMessageAt,
                members: conversation.members,
                lastMessage: await hydrateMedia(last)
            )
        }
        return conversation
    }

    func messagesUnreadCount() async -> Int {
        struct Response: Decodable {
            let messagesUnreadCount: Int
        }

        let query = "query { messagesUnreadCount }"
        do {
            let result: Response = try await gql.authenticatedRequest(query: query)
            return result.messagesUnreadCount
        } catch {
            return 0
        }
    }

    func sendMessage(
        conversationID: String,
        body: String,
        mediaType: String? = nil,
        mediaPath: String? = nil,
        mediaName: String? = nil,
        mediaMime: String? = nil,
        mediaSize: Int? = nil
    ) async throws -> Message {
        struct Response: Decodable {
            let sendMessage: GraphQLMessage
        }

        let mutation = """
        mutation SendMessage($conversationId: ID!, $body: String!, $mediaType: String, $mediaPath: String, $mediaName: String, $mediaMime: String, $mediaSize: Int) {
          sendMessage(
            conversation_id: $conversationId
            body: $body
            media_type: $mediaType
            media_path: $mediaPath
            media_name: $mediaName
            media_mime: $mediaMime
            media_size: $mediaSize
          ) {
            id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
            sender { user_id display_name username avatar_url country_name country_code }
          }
        }
        """

        var vars: [String: Any] = ["conversationId": conversationID, "body": body]
        if let mediaType { vars["mediaType"] = mediaType }
        if let mediaPath { vars["mediaPath"] = mediaPath }
        if let mediaName { vars["mediaName"] = mediaName }
        if let mediaMime { vars["mediaMime"] = mediaMime }
        if let mediaSize { vars["mediaSize"] = mediaSize }

        let result: Response = try await gql.authenticatedRequest(query: mutation, variables: vars)
        return await hydrateMedia(result.sendMessage.toModel)
    }

    private func hydrateMedia(_ message: Message) async -> Message {
        guard let path = message.mediaPath, !path.isEmpty else { return message }
        guard let url = try? await MediaService.shared.signedMessageURL(path: path) else { return message }
        return Message(
            id: message.id,
            conversationID: message.conversationID,
            senderID: message.senderID,
            body: message.body,
            mediaType: message.mediaType,
            mediaPath: message.mediaPath,
            mediaURL: url,
            mediaName: message.mediaName,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt,
            sender: message.sender
        )
    }
}

private struct GraphQLConversation: Decodable {
    let id: String
    let isDirect: Bool
    let createdAt: String
    let updatedAt: String
    let lastMessageAt: String?
    let members: [GraphQLAuthor]
    let lastMessage: GraphQLMessage?

    enum CodingKeys: String, CodingKey {
        case id
        case isDirect = "is_direct"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessageAt = "last_message_at"
        case members
        case lastMessage = "last_message"
    }

    var toModel: Conversation {
        Conversation(
            id: id,
            isDirect: isDirect,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessageAt: lastMessageAt,
            members: members.map(\.toModel),
            lastMessage: lastMessage?.toModel
        )
    }
}

private struct GraphQLMessage: Decodable {
    let id: String
    let conversationID: String
    let senderID: String
    let body: String
    let mediaType: String?
    let mediaPath: String?
    let mediaName: String?
    let createdAt: String
    let updatedAt: String
    let sender: GraphQLAuthor?

    enum CodingKeys: String, CodingKey {
        case id, body, sender
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case mediaType = "media_type"
        case mediaPath = "media_path"
        case mediaName = "media_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var toModel: Message {
        Message(
            id: id,
            conversationID: conversationID,
            senderID: senderID,
            body: body,
            mediaType: mediaType,
            mediaPath: mediaPath,
            mediaURL: nil,
            mediaName: mediaName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sender: sender?.toModel
        )
    }
}