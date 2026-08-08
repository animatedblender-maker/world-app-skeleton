import SwiftUI

/// Tracks which conversation chat screen is currently visible (suppresses push banners for that chat).
@MainActor
enum ActiveConversationFocus {
    private static var currentID: String?

    static func set(_ conversationID: String?) {
        currentID = conversationID
    }

    static func isViewing(_ conversationID: String) -> Bool {
        currentID == conversationID
    }

    static var current: String? { currentID }
}

/// Opens a chat **instantly** from cache/seed — never full-screen "Opening chat…" that kills the mini player.
struct ConversationRouteView: View {
    @Environment(AppState.self) private var appState

    let conversationID: String

    @State private var conversation: Conversation
    @State private var hardError: String?

    init(conversationID: String) {
        self.conversationID = conversationID
        // Paint immediately: warm cache → placeholder. Network only upgrades metadata.
        let seed = MessagesService.shared.cachedConversation(id: conversationID)
            ?? MessagesService.shared.placeholderConversation(id: conversationID)
        _conversation = State(initialValue: seed)
    }

    var body: some View {
        Group {
            if let hardError {
                ContentUnavailableView(
                    "Chat unavailable",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(hardError)
                )
            } else {
                // Always show the real chat chrome (messages paint from their own cache).
                ConversationView(conversation: conversation)
            }
        }
        .screenBackground()
        .task(id: conversationID) {
            // Focus first so in-flight pushes for this chat never show a banner.
            ActiveConversationFocus.set(conversationID)
            // Non-blocking: clear banners + soft-refresh conversation metadata in parallel.
            async let clear: Void = appState.clearNotifications(forConversation: conversationID)
            async let refresh: Void = softRefreshConversation()
            _ = await (clear, refresh)
            await appState.refreshUnreadCounts()
            await appState.syncAppIconBadge()
        }
        .onAppear {
            ActiveConversationFocus.set(conversationID)
            // Keep hubs mini alive while chatting — never pause for navigation.
            if appState.hubPlaybackPost != nil {
                appState.hubPlaybackPlaying = true
            }
            Task {
                await appState.clearNotifications(forConversation: conversationID)
            }
        }
        .onDisappear {
            if ActiveConversationFocus.isViewing(conversationID) {
                ActiveConversationFocus.set(nil)
            }
        }
    }

    /// Upgrade placeholder / stale cache without blocking the UI.
    private func softRefreshConversation() async {
        hardError = nil
        do {
            if let fetched = try await MessagesService.shared.getConversationById(conversationID) {
                conversation = fetched
            } else if conversation.members.isEmpty, conversation.createdAt.isEmpty {
                // Only fail hard if we never had real metadata.
                hardError = "Conversation not found."
            }
        } catch {
            // Keep the already-visible chat; only surface error when we had nothing real.
            if conversation.members.isEmpty, conversation.createdAt.isEmpty {
                hardError = error.localizedDescription
            }
        }
    }
}
