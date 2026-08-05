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

struct ConversationRouteView: View {
    @Environment(AppState.self) private var appState

    let conversationID: String

    @State private var conversation: Conversation?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let conversation {
                ConversationView(conversation: conversation)
            } else if isLoading {
                ProgressView("Opening chat…")
                    .tint(Theme.accentBright)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Chat unavailable",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(errorMessage ?? "This conversation could not be opened.")
                )
            }
        }
        .screenBackground()
        .task(id: conversationID) {
            // Focus first so in-flight pushes for this chat never show a banner.
            ActiveConversationFocus.set(conversationID)
            await appState.clearNotifications(forConversation: conversationID)
            await loadConversation()
            // Opening messages marks last_read_at on the server — refresh badge after load.
            await appState.refreshUnreadCounts()
            await appState.syncAppIconBadge()
        }
        .onAppear {
            ActiveConversationFocus.set(conversationID)
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

    private func loadConversation() async {
        isLoading = conversation == nil
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let fetched = try await MessagesService.shared.getConversationById(conversationID) {
                conversation = fetched
            } else {
                errorMessage = "Conversation not found."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}