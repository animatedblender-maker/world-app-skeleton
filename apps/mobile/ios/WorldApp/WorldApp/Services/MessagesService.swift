import Foundation

@MainActor
final class MessagesService {
    static let shared = MessagesService()

    private let gql = GraphQLService.shared
    private var cachedConversations: [Conversation] = []
    private var cacheUserID: String?
    /// Keeps chat threads warm so re-opening a conversation paints instantly.
    private var cachedMessagesByConversation: [String: [Message]] = [:]
    private var cachedPeerReadByConversation: [String: String] = [:]

    private init() {}

    func cachedMessages(for conversationID: String) -> [Message]? {
        let id = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return cachedMessagesByConversation[id]
    }

    func cachedPeerRead(for conversationID: String) -> String? {
        let id = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return cachedPeerReadByConversation[id]
    }

    /// Instant chat open — conversation row / previous fetch without waiting on network.
    func cachedConversation(id conversationID: String) -> Conversation? {
        let id = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return cachedConversations.first { $0.id == id }
    }

    /// Seed / update a single conversation so `ConversationRouteView` can paint immediately.
    func storeConversation(_ conversation: Conversation) {
        let id = conversation.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if let idx = cachedConversations.firstIndex(where: { $0.id == id }) {
            cachedConversations[idx] = conversation
        } else {
            cachedConversations.insert(conversation, at: 0)
        }
        if let userID = AuthService.shared.currentUser?.id {
            cacheUserID = userID
        }
    }

    /// Lightweight placeholder so chat UI can appear before network metadata returns.
    func placeholderConversation(id conversationID: String) -> Conversation {
        let id = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        return Conversation(
            id: id,
            isDirect: true,
            createdAt: "",
            updatedAt: "",
            lastMessageAt: nil,
            members: [],
            lastMessage: nil
        )
    }

    func storeMessages(_ messages: [Message], peerReadAt: String? = nil, for conversationID: String) {
        let id = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        cachedMessagesByConversation[id] = messages
        if let peerReadAt, !peerReadAt.isEmpty {
            cachedPeerReadByConversation[id] = peerReadAt
        }
        // Bound memory — keep the most recently touched ~12 threads.
        if cachedMessagesByConversation.count > 12 {
            let overflow = cachedMessagesByConversation.count - 12
            for key in cachedMessagesByConversation.keys.prefix(overflow) {
                if key != id {
                    cachedMessagesByConversation.removeValue(forKey: key)
                    cachedPeerReadByConversation.removeValue(forKey: key)
                }
            }
        }
    }

    /// Warm the first few threads so tapping a chat is instant (messages already local).
    func prefetchRecentThreads(limit: Int = 4) {
        let ids = cachedConversations.prefix(limit).map(\.id)
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            for id in ids {
                if cachedMessages(for: id) != nil { continue }
                _ = try? await listMessages(conversationID: id, limit: 40)
            }
        }
    }

    func listConversations(limit: Int = 40) async throws -> [Conversation] {
        if ScreenshotMode.isActive {
            return Array(ScreenshotMode.demoConversations.prefix(limit))
        }

        _ = try await AuthService.shared.ensureValidToken()

        do {
            let conversations = try await fetchConversations(limit: limit, retryingAuth: true)
            if let userID = AuthService.shared.currentUser?.id {
                cacheUserID = userID
                cachedConversations = conversations
            }
            // Warm top threads in the background — open chat without "Opening chat…".
            prefetchRecentThreads(limit: 4)
            return conversations
        } catch {
            if let userID = AuthService.shared.currentUser?.id,
               cacheUserID == userID,
               !cachedConversations.isEmpty {
                return cachedConversations
            }
            throw error
        }
    }

    private func fetchConversations(limit: Int, retryingAuth: Bool) async throws -> [Conversation] {
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

        do {
            let result: Response = try await gql.authenticatedRequest(
                query: query,
                variables: ["limit": limit]
            )
            return result.conversations.map(\.toModel)
        } catch {
            let message = error.localizedDescription.lowercased()
            let authFailure = message.contains("auth")
                || message.contains("unauthenticated")
                || message.contains("jwt")
                || message.contains("token")
            if retryingAuth, authFailure {
                _ = try? await Task { @MainActor in
                    try await AuthService.shared.ensureValidToken()
                }.value
                return try await fetchConversations(limit: limit, retryingAuth: false)
            }
            throw error
        }
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
        storeMessages(messages, for: conversationID)
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
        let conversation = result.startConversation.toModel
        storeConversation(conversation)
        return conversation
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
        storeConversation(conversation)
        return conversation
    }

    func archiveConversation(_ conversationID: String) async throws -> Bool {
        struct Response: Decodable {
            let archiveConversation: Bool
        }

        let mutation = """
        mutation ArchiveConversation($conversationId: ID!) {
          archiveConversation(conversation_id: $conversationId)
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["conversationId": conversationID]
        )
        return result.archiveConversation
    }

    func deleteConversation(_ conversationID: String) async throws -> Bool {
        struct Response: Decodable {
            let deleteConversation: Bool
        }

        let mutation = """
        mutation DeleteConversation($conversationId: ID!) {
          deleteConversation(conversation_id: $conversationId)
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["conversationId": conversationID]
        )
        return result.deleteConversation
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

    func deleteMessage(_ messageID: String) async throws -> Bool {
        struct Response: Decodable {
            let deleteMessage: Bool
        }

        let mutation = """
        mutation DeleteMessage($messageId: ID!) {
          deleteMessage(message_id: $messageId)
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["messageId": messageID]
        )
        return result.deleteMessage
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
            members: members.compactMap(\.toModelIfValid),
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
    let updatedAt: String?
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationID = try container.decode(String.self, forKey: .conversationID)
        senderID = try container.decode(String.self, forKey: .senderID)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        mediaPath = try container.decodeIfPresent(String.self, forKey: .mediaPath)
        mediaName = try container.decodeIfPresent(String.self, forKey: .mediaName)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        sender = try container.decodeIfPresent(GraphQLAuthor.self, forKey: .sender)
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
            updatedAt: updatedAt ?? createdAt,
            sender: sender?.toModelIfValid
        )
    }
}