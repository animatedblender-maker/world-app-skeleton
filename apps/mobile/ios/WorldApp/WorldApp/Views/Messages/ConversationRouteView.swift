import SwiftUI

struct ConversationRouteView: View {
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
            await loadConversation()
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