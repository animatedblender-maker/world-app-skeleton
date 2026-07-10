import SwiftUI

struct MessagesView: View {
    @Environment(AppState.self) private var appState

    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedConversation: Conversation?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading conversations…")
                        .tint(Theme.accentBright)
                } else if let errorMessage {
                    ContentUnavailableView("Messages unavailable", systemImage: "bubble.left.and.bubble.right", description: Text(errorMessage))
                } else if conversations.isEmpty {
                    ContentUnavailableView("No conversations", systemImage: "bubble.left.and.bubble.right", description: Text("Start chatting from a profile."))
                } else {
                    List(conversations) { conversation in
                        Button {
                            selectedConversation = conversation
                        } label: {
                            ConversationRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MenuToolbarButton()
                }
                ToolbarItem(placement: .principal) {
                    Text(appState.currentProfile?.username ?? "Messages")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.navigate(to: .people)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .refreshable { await loadConversations() }
            .navigationDestination(item: $selectedConversation) { conversation in
                ConversationView(conversation: conversation)
            }
        }
        .task {
            await loadConversations()
            if let conversationID = appState.pendingConversationID {
                await openPendingConversation(conversationID)
            }
        }
        .onChange(of: appState.pendingConversationID) { _, conversationID in
            guard let conversationID else { return }
            Task { await openPendingConversation(conversationID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .conversationMessagesDidChange)) { _ in
            Task { await loadConversations() }
        }
    }

    private func openPendingConversation(_ conversationID: String) async {
        if let existing = conversations.first(where: { $0.id == conversationID }) {
            selectedConversation = existing
            appState.pendingConversationID = nil
            return
        }

        do {
            if let fetched = try await MessagesService.shared.getConversationById(conversationID) {
                if !conversations.contains(where: { $0.id == fetched.id }) {
                    conversations.insert(fetched, at: 0)
                }
                selectedConversation = fetched
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        appState.pendingConversationID = nil
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    private var otherMember: PostAuthor? {
        guard let userID = AuthService.shared.currentUser?.id else { return nil }
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