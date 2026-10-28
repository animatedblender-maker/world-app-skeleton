import Foundation

@MainActor
final class MessagesService {
    static let shared = MessagesService()

    private let gql = GraphQLService.shared
    private var cachedConversations: [Conversation] = []
    private var cacheUserID: String?
    /// Skip network thrash when inbox was just fetched (tab hop / call-log spam).
    private var lastConversationsFetchAt: Date = .distantPast
    /// Memory is fresh for 60s; disk paints cold open instantly (stale-while-revalidate).
    private let conversationsFreshTTL: TimeInterval = 60
    private var didRestoreDiskCache = false
    private var backgroundInboxRefreshTask: Task<Void, Never>?
    /// Keeps chat threads warm so re-opening a conversation paints instantly.
    private var cachedMessagesByConversation: [String: [Message]] = [:]
    private var cachedPeerReadByConversation: [String: String] = [:]

    private init() {
        restoreDiskCacheIfNeeded()
    }

    private struct InboxDiskPayload: Codable {
        let userID: String
        let savedAt: Date
        let conversations: [Conversation]
    }

    private var inboxDiskURL: URL? {
        guard let userID = AuthService.shared.currentUser?.id ?? cacheUserID,
              !userID.isEmpty
        else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("MatteryaInboxCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(userID).v1.json")
    }

    /// Load last inbox from disk once — cold open must not wait on GraphQL.
    func restoreDiskCacheIfNeeded() {
        guard !didRestoreDiskCache else { return }
        didRestoreDiskCache = true
        guard cachedConversations.isEmpty else { return }
        guard let url = inboxDiskURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(InboxDiskPayload.self, from: data)
        else { return }
        if let userID = AuthService.shared.currentUser?.id, payload.userID != userID {
            return
        }
        cachedConversations = payload.conversations
        cacheUserID = payload.userID
        // Treat disk as stale so first soft-refresh still hits network after paint.
        lastConversationsFetchAt = payload.savedAt
        #if DEBUG
        print("[Messages] disk inbox restore count=\(payload.conversations.count) age=\(Int(Date().timeIntervalSince(payload.savedAt)))s")
        #endif
    }

    private func persistInboxToDisk() {
        guard let userID = AuthService.shared.currentUser?.id ?? cacheUserID,
              !userID.isEmpty,
              !cachedConversations.isEmpty,
              let url = inboxDiskURL
        else { return }
        let payload = InboxDiskPayload(
            userID: userID,
            savedAt: Date(),
            conversations: Array(cachedConversations.prefix(60))
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    /// Warm primary inbox after session ready — Messages tab paints from memory.
    func warmPrimaryInboxIfNeeded() {
        restoreDiskCacheIfNeeded()
        Task(priority: .utility) { @MainActor in
            _ = try? await listConversations(limit: 40, forceNetwork: false, inbox: "primary")
        }
    }

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

    /// Inbox paint-first (profile-style): return memory/disk cache without touching the network.
    func cachedConversationsSnapshot() -> [Conversation] {
        restoreDiskCacheIfNeeded()
        if let userID = AuthService.shared.currentUser?.id {
            if cacheUserID == nil || cacheUserID == userID {
                return cachedConversations
            }
            return []
        }
        return cachedConversations
    }

    /// Immediate call-log row after hangup / miss — UI updates before GraphQL round-trip.
    @discardableResult
    func appendOptimisticCallLog(conversationID: String, body: String) -> Message {
        let id = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = ISO8601DateFormatter().string(from: Date())
        let me = AuthService.shared.currentUser
        let profile = ContentCache.shared.cachedProfile()
        let sender: PostAuthor? = {
            guard let me else { return nil }
            return PostAuthor(
                userID: me.id,
                displayName: profile?.displayName,
                username: profile?.username,
                avatarURL: profile?.avatarURL,
                countryName: profile?.countryName,
                countryCode: profile?.countryCode,
                lastReadAt: nil
            )
        }()
        let message = Message(
            id: "local-call-\(UUID().uuidString)",
            conversationID: id,
            senderID: me?.id ?? "",
            body: body,
            mediaType: nil,
            mediaPath: nil,
            mediaURL: nil,
            mediaName: nil,
            createdAt: now,
            updatedAt: now,
            sender: sender
        )
        var msgs = cachedMessagesByConversation[id] ?? []
        // Avoid stacking duplicates if hangup fires twice.
        if !msgs.contains(where: { $0.body == body && $0.id.hasPrefix("local-call-") }) {
            msgs.append(message)
            storeMessages(msgs, for: id)
        }
        // Bump conversation preview so the inbox row updates instantly.
        if let idx = cachedConversations.firstIndex(where: { $0.id == id }) {
            let prev = cachedConversations[idx]
            cachedConversations[idx] = Conversation(
                id: prev.id,
                isDirect: prev.isDirect,
                createdAt: prev.createdAt,
                updatedAt: now,
                lastMessageAt: now,
                isRequest: prev.isRequest,
                requestStatus: prev.requestStatus,
                surface: prev.surface,
                members: prev.members,
                lastMessage: message
            )
            // Newest activity to top.
            let bumped = cachedConversations.remove(at: idx)
            cachedConversations.insert(bumped, at: 0)
        }
        return message
    }

    /// Swap local-call-* / pending-* with the server-confirmed message.
    func replaceLocalMessage(id localID: String, with server: Message, conversationID: String) {
        let cid = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var msgs = cachedMessagesByConversation[cid] else {
            storeMessages([server], for: cid)
            return
        }
        if let idx = msgs.firstIndex(where: { $0.id == localID }) {
            msgs[idx] = server
        } else if !msgs.contains(where: { $0.id == server.id }) {
            msgs.append(server)
        }
        // Drop any other local twin with same call body.
        msgs.removeAll { $0.id.hasPrefix("local-call-") && $0.body == server.body && $0.id != server.id }
        storeMessages(msgs, for: cid)
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
            isRequest: false,
            requestStatus: nil,
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
    func prefetchRecentThreads(limit: Int = 2) {
        let ids = cachedConversations.prefix(limit).map(\.id)
        guard !ids.isEmpty else { return }
        Task(priority: .utility) { @MainActor in
            for id in ids {
                if cachedMessages(for: id) != nil { continue }
                // Thin hydrate — enough for open, not a full thread dump on inbox paint.
                _ = try? await listMessages(conversationID: id, limit: 24)
            }
        }
    }

    /// inbox: primary | requests | all | masquerade
    func listConversations(
        limit: Int = 40,
        forceNetwork: Bool = false,
        inbox: String = "primary"
    ) async throws -> [Conversation] {
        if ScreenshotMode.isActive {
            return Array(ScreenshotMode.demoConversations.prefix(limit))
        }

        let folder = inbox.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let usePrimaryCache = folder == "primary" || folder.isEmpty
        restoreDiskCacheIfNeeded()

        // Stale-while-revalidate: paint memory/disk instantly; refresh behind when stale.
        if usePrimaryCache,
           !forceNetwork,
           let userID = AuthService.shared.currentUser?.id,
           (cacheUserID == nil || cacheUserID == userID),
           !cachedConversations.isEmpty {
            cacheUserID = userID
            let age = Date().timeIntervalSince(lastConversationsFetchAt)
            if age < conversationsFreshTTL {
                return cachedConversations
            }
            scheduleBackgroundInboxRefresh(limit: limit, inbox: folder.isEmpty ? "primary" : folder)
            return cachedConversations
        }

        return try await fetchAndStoreConversations(
            limit: limit,
            inbox: folder.isEmpty ? "primary" : folder,
            usePrimaryCache: usePrimaryCache
        )
    }

    private func scheduleBackgroundInboxRefresh(limit: Int, inbox: String) {
        backgroundInboxRefreshTask?.cancel()
        backgroundInboxRefreshTask = Task(priority: .utility) { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await fetchAndStoreConversations(
                limit: limit,
                inbox: inbox,
                usePrimaryCache: true
            )
            NotificationCenter.default.post(name: .conversationMessagesDidChange, object: nil)
        }
    }

    private func fetchAndStoreConversations(
        limit: Int,
        inbox: String,
        usePrimaryCache: Bool
    ) async throws -> [Conversation] {
        _ = try await AuthService.shared.ensureValidToken()

        do {
            let conversations = try await fetchConversations(
                limit: limit,
                inbox: inbox,
                retryingAuth: true
            )
            if usePrimaryCache, let userID = AuthService.shared.currentUser?.id {
                cacheUserID = userID
                cachedConversations = conversations
                lastConversationsFetchAt = Date()
                persistInboxToDisk()
                prefetchRecentThreads(limit: 2)
            }
            return conversations
        } catch {
            if usePrimaryCache,
               let userID = AuthService.shared.currentUser?.id,
               cacheUserID == userID,
               !cachedConversations.isEmpty {
                return cachedConversations
            }
            throw error
        }
    }

    func acceptMessageRequest(conversationID: String) async throws -> Conversation {
        struct Response: Decodable {
            let acceptMessageRequest: GraphQLConversation
        }
        let mutation = """
        mutation AcceptMessageRequest($conversationId: ID!) {
          acceptMessageRequest(conversation_id: $conversationId) {
            id is_direct created_at updated_at last_message_at
            is_request request_status
            members {
              user_id display_name username avatar_url country_name country_code last_read_at is_verified
            }
            last_message {
              id conversation_id sender_id body media_type media_path media_name created_at updated_at
              sender { user_id display_name username avatar_url country_name country_code is_verified }
            }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["conversationId": conversationID]
        )
        let conversation = result.acceptMessageRequest.toModel
        storeConversation(conversation)
        return conversation
    }

    func declineMessageRequest(conversationID: String) async throws -> Bool {
        struct Response: Decodable {
            let declineMessageRequest: Bool
        }
        let mutation = """
        mutation DeclineMessageRequest($conversationId: ID!) {
          declineMessageRequest(conversation_id: $conversationId)
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["conversationId": conversationID]
        )
        cachedConversations.removeAll { $0.id == conversationID }
        return result.declineMessageRequest
    }

    private func fetchConversations(
        limit: Int,
        inbox: String,
        retryingAuth: Bool
    ) async throws -> [Conversation] {
        struct Response: Decodable {
            let conversations: [GraphQLConversation]
        }

        let query = """
        query Conversations($limit: Int, $inbox: String) {
          conversations(limit: $limit, inbox: $inbox) {
            id is_direct created_at updated_at last_message_at
            is_request request_status surface
            members {
              user_id display_name username avatar_url country_name country_code last_read_at is_verified
            }
            last_message {
              id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
              sender { user_id display_name username avatar_url country_name country_code is_verified }
            }
          }
        }
        """

        do {
            let result: Response = try await gql.authenticatedRequest(
                query: query,
                variables: ["limit": limit, "inbox": inbox]
            )
            return Self.filterConversations(result.conversations.map(\.toModel), inbox: inbox)
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
                return try await fetchConversations(limit: limit, inbox: inbox, retryingAuth: false)
            }
            // Older API without `surface` / inbox — retry without surface, then legacy.
            if message.contains("surface") {
                return try await fetchConversationsWithoutSurface(
                    limit: limit,
                    inbox: inbox,
                    retryingAuth: false
                )
            }
            if message.contains("inbox") || message.contains("unknown") {
                return try await fetchConversationsLegacy(limit: limit, inbox: inbox)
            }
            throw error
        }
    }

    /// Client belt-and-suspenders: Messages never shows masquerade threads, and vice versa.
    private static func filterConversations(_ list: [Conversation], inbox: String) -> [Conversation] {
        let folder = inbox.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if folder == "masquerade" {
            return list.filter(\.isMasqueradeSurface)
        }
        // primary / requests / all / empty
        return list.filter { !$0.isMasqueradeSurface }
    }

    private func fetchConversationsWithoutSurface(
        limit: Int,
        inbox: String,
        retryingAuth: Bool
    ) async throws -> [Conversation] {
        struct Response: Decodable {
            let conversations: [GraphQLConversation]
        }
        let query = """
        query Conversations($limit: Int, $inbox: String) {
          conversations(limit: $limit, inbox: $inbox) {
            id is_direct created_at updated_at last_message_at
            is_request request_status
            members {
              user_id display_name username avatar_url country_name country_code last_read_at is_verified
            }
            last_message {
              id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
              sender { user_id display_name username avatar_url country_name country_code is_verified }
            }
          }
        }
        """
        do {
            let result: Response = try await gql.authenticatedRequest(
                query: query,
                variables: ["limit": limit, "inbox": inbox]
            )
            // Without surface field, keep primary lists only — never invent masquerade threads.
            let models = result.conversations.map(\.toModel)
            let folder = inbox.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if folder == "masquerade" { return [] }
            return models
        } catch {
            if messageContainsInboxOrUnknown(error), retryingAuth {
                return try await fetchConversationsLegacy(limit: limit, inbox: inbox)
            }
            throw error
        }
    }

    private func messageContainsInboxOrUnknown(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("inbox") || message.contains("unknown")
    }

    private func fetchConversationsLegacy(limit: Int, inbox: String = "primary") async throws -> [Conversation] {
        struct Response: Decodable {
            let conversations: [GraphQLConversation]
        }
        let query = """
        query Conversations($limit: Int) {
          conversations(limit: $limit) {
            id is_direct created_at updated_at last_message_at
            members {
              user_id display_name username avatar_url country_name country_code last_read_at is_verified
            }
            last_message {
              id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
              sender { user_id display_name username avatar_url country_name country_code is_verified }
            }
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["limit": limit]
        )
        return Self.filterConversations(result.conversations.map(\.toModel), inbox: inbox)
    }

    func listMessages(conversationID: String, limit: Int = 50) async throws -> [Message] {
        struct Response: Decodable {
            let messagesByConversation: [GraphQLMessage]
        }

        let query = """
        query MessagesByConversation($conversationId: ID!, $limit: Int) {
          messagesByConversation(conversation_id: $conversationId, limit: $limit) {
            id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
            sender { user_id display_name username avatar_url country_name country_code is_verified }
          }
        }
        """

        let result: Response = try await gql.authenticatedRequest(
            query: query,
            variables: ["conversationId": conversationID, "limit": limit]
        )
        var messages = result.messagesByConversation.map(\.toModel)
        // Only hydrate media rows (images/video) — text/call logs need no signed URL work.
        // Cap concurrency so opening a chat never fires 50 parallel GraphQL media signs.
        let mediaIndices = messages.indices.filter { idx in
            let m = messages[idx]
            return m.mediaPath != nil && !(m.mediaPath ?? "").isEmpty
        }
        if !mediaIndices.isEmpty {
            await withTaskGroup(of: (Int, Message).self) { group in
                var inFlight = 0
                var next = 0
                let maxConcurrent = 4
                while next < mediaIndices.count || inFlight > 0 {
                    while inFlight < maxConcurrent, next < mediaIndices.count {
                        let index = mediaIndices[next]
                        next += 1
                        inFlight += 1
                        let message = messages[index]
                        group.addTask { [self] in
                            (index, await hydrateMedia(message))
                        }
                    }
                    if let (index, hydrated) = await group.next() {
                        inFlight -= 1
                        messages[index] = hydrated
                    }
                }
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
            is_request request_status
            members {
              user_id display_name username avatar_url country_name country_code last_read_at is_verified
            }
            last_message {
              id conversation_id sender_id body media_type media_path media_name created_at updated_at
              sender { user_id display_name username avatar_url country_name country_code is_verified }
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
            is_request request_status
            members {
              user_id display_name username avatar_url country_name country_code last_read_at is_verified
            }
            last_message {
              id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
              sender { user_id display_name username avatar_url country_name country_code is_verified }
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
                isRequest: conversation.isRequest,
                requestStatus: conversation.requestStatus,
                surface: conversation.surface,
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
            sender { user_id display_name username avatar_url country_name country_code is_verified }
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
    let isRequest: Bool?
    let requestStatus: String?
    let surface: String?
    let members: [GraphQLAuthor]
    let lastMessage: GraphQLMessage?

    enum CodingKeys: String, CodingKey {
        case id
        case isDirect = "is_direct"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessageAt = "last_message_at"
        case isRequest = "is_request"
        case requestStatus = "request_status"
        case surface
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
            isRequest: isRequest ?? false,
            requestStatus: requestStatus,
            surface: surface ?? "primary",
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