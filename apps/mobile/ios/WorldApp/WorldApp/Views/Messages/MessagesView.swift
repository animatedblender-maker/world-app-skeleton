import SwiftUI

private struct MessagesLoadToken: Equatable {
    let generation: Int
    let isReady: Bool
    let isAuthenticated: Bool
}

struct MessagesView: View {
    @Environment(AppState.self) private var appState

    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            messagesTopBar

            Group {
                if isLoading {
                    ProgressView("Loading conversations…")
                        .tint(Theme.accentBright)
                        .frame(maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("Messages unavailable", systemImage: "bubble.left.and.bubble.right", description: Text(errorMessage))
                } else if conversations.isEmpty {
                    ContentUnavailableView("No conversations", systemImage: "bubble.left.and.bubble.right", description: Text("Start chatting from a profile."))
                } else {
                    List {
                        ForEach(conversations) { conversation in
                            ConversationRow(conversation: conversation)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    appState.openConversation(id: conversation.id)
                                }
                                .listRowBackground(Theme.surface)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await deleteConversation(conversation) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        Task { await archiveConversation(conversation) }
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                    .tint(Theme.accentBright)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await loadConversations() }
        .task(id: MessagesLoadToken(
            generation: appState.contentLoadGeneration,
            isReady: appState.isSessionReady,
            isAuthenticated: appState.isAuthenticated
        )) {
            guard appState.isAuthenticated, appState.isSessionReady else { return }
            await loadConversations()
            if let conversationID = appState.pendingConversationID {
                await openPendingConversation(conversationID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .authTokenDidRefresh)) { _ in
            Task { await loadConversations() }
        }
        .onChange(of: appState.pendingConversationID) { _, conversationID in
            guard let conversationID else { return }
            Task { await openPendingConversation(conversationID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .conversationMessagesDidChange)) { _ in
            Task { await loadConversations() }
        }
    }

    private var messagesTopBar: some View {
        HStack(spacing: 12) {
            MenuToolbarButton()

            Spacer()

            Text("Messages")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Button {
                appState.navigate(to: .people)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Theme.surface)
    }

    private func archiveConversation(_ conversation: Conversation) async {
        appState.closeConversation(id: conversation.id)
        conversations.removeAll { $0.id == conversation.id }

        appState.showToast("Chat archived", style: .info)

        do {
            _ = try await MessagesService.shared.archiveConversation(conversation.id)
            ConversationInboxStore.clear(conversation.id)
            await appState.refreshUnreadCounts()
        } catch {
            ConversationInboxStore.markArchived(conversation.id)
            await appState.refreshUnreadCounts()
        }
    }

    private func deleteConversation(_ conversation: Conversation) async {
        appState.closeConversation(id: conversation.id)
        conversations.removeAll { $0.id == conversation.id }

        appState.showToast("Chat removed", style: .info)

        do {
            _ = try await MessagesService.shared.deleteConversation(conversation.id)
            ConversationInboxStore.clear(conversation.id)
            await appState.refreshUnreadCounts()
        } catch {
            ConversationInboxStore.markDeleted(conversation.id)
            await appState.refreshUnreadCounts()
        }
    }

    private func openPendingConversation(_ conversationID: String) async {
        if conversations.contains(where: { $0.id == conversationID }) {
            appState.openConversation(id: conversationID)
            return
        }

        do {
            if let fetched = try await MessagesService.shared.getConversationById(conversationID) {
                if !conversations.contains(where: { $0.id == fetched.id }) {
                    conversations.insert(fetched, at: 0)
                }
                appState.openConversation(id: conversationID)
            } else {
                appState.showToast("Conversation not found.", style: .error)
                appState.pendingConversationID = nil
            }
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
        }
    }

    private func loadConversations() async {
        let showSpinner = conversations.isEmpty
        if showSpinner {
            isLoading = true
        }
        errorMessage = nil
        defer {
            if showSpinner {
                isLoading = false
            }
        }

        do {
            conversations = try await MessagesService.shared.listConversations()
                .filter { !ConversationInboxStore.isHidden($0.id) }
            if let pendingID = appState.pendingConversationID {
                await openPendingConversation(pendingID)
            }
        } catch {
            if conversations.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                appState.showToast("Couldn't refresh messages. Showing your latest chats.", style: .info)
            }
        }
    }
}

@MainActor
private enum ConversationInboxStore {
    private static var storagePrefix: String {
        "conversation.inbox.\(AuthService.shared.currentUser?.id ?? "anonymous")"
    }

    static func isHidden(_ conversationID: String) -> Bool {
        archivedIDs.contains(conversationID) || deletedIDs.contains(conversationID)
    }

    static func markArchived(_ conversationID: String) {
        var archived = archivedIDs
        var deleted = deletedIDs
        archived.insert(conversationID)
        deleted.remove(conversationID)
        persist(archived: archived, deleted: deleted)
    }

    static func markDeleted(_ conversationID: String) {
        var archived = archivedIDs
        var deleted = deletedIDs
        deleted.insert(conversationID)
        archived.remove(conversationID)
        persist(archived: archived, deleted: deleted)
    }

    static func clear(_ conversationID: String) {
        var archived = archivedIDs
        var deleted = deletedIDs
        archived.remove(conversationID)
        deleted.remove(conversationID)
        persist(archived: archived, deleted: deleted)
    }

    private static var archivedIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "\(storagePrefix).archived") ?? [])
    }

    private static var deletedIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "\(storagePrefix).deleted") ?? [])
    }

    private static func persist(archived: Set<String>, deleted: Set<String>) {
        UserDefaults.standard.set(Array(archived), forKey: "\(storagePrefix).archived")
        UserDefaults.standard.set(Array(deleted), forKey: "\(storagePrefix).deleted")
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    private var otherMember: PostAuthor? {
        let userID = ScreenshotMode.isActive
            ? ScreenshotMode.demoProfile.userID
            : AuthService.shared.currentUser?.id
        guard let userID else { return nil }
        return conversation.otherMember(currentUserID: userID)
    }

    private var title: String {
        if let other = otherMember {
            return other.displayName ?? other.username ?? "User"
        }
        return "Conversation"
    }

    private var preview: String {
        conversation.lastMessage?.previewText ?? "No messages yet"
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                url: otherMember?.avatarURL,
                seed: otherMember?.username ?? otherMember?.userID ?? conversation.id,
                size: 48
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
            }
            Spacer()
            if let createdAt = conversation.lastMessageAt ?? conversation.lastMessage?.createdAt {
                Text(RelativeTime.format(createdAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.vertical, 4)
    }
}