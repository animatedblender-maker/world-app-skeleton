import SwiftUI

/// Masquerade **Notifications** (bell) — replies, mentions, Space alerts.
/// Kept separate from Inbox (messages).
struct AnonymousNotificationsView: View {
    @State private var store = AnonymousStore.shared

    var body: some View {
        Group {
            if store.inboxLoading && store.inbox.isEmpty {
                AnonymousLoadingSkeleton()
            } else if store.inbox.isEmpty {
                VStack(spacing: 18) {
                    AnonymousEmptyState(
                        title: MatteryaCopy.anonymousNotificationsTitle,
                        message: MatteryaCopy.anonymousNotificationsBody,
                        systemImage: "bell"
                    )
                    Text(MatteryaCopy.anonymousInboxPrivacyNote)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 40)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.inbox) { item in
                            notificationRow(item)
                        }
                    }
                    .padding(Theme.pagePadding)
                    .padding(.bottom, 28)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refreshInbox() }
        .task { await store.loadInbox() }
    }

    private func notificationRow(_ item: AnonymousNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.isUnread ? Theme.ink : Theme.matteDeep)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(item.displayBody)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(3)
                if let space = item.spaceTitle, !space.isEmpty {
                    Text(space)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }
}

/// Masquerade **Inbox** — real Matterya messages (including the official Matterya welcome).
struct AnonymousMessagesInboxView: View {
    @Environment(AppState.self) private var appState
    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && conversations.isEmpty {
                AnonymousLoadingSkeleton()
            } else if let errorMessage, conversations.isEmpty {
                AnonymousEmptyState(
                    title: "Inbox unavailable",
                    message: errorMessage,
                    systemImage: "tray"
                )
            } else if conversations.isEmpty {
                AnonymousEmptyState(
                    title: MatteryaCopy.anonymousMessagesInboxTitle,
                    message: MatteryaCopy.anonymousMessagesInboxBody,
                    systemImage: "tray"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(conversations) { conversation in
                            Button {
                                appState.openConversation(id: conversation.id, seed: conversation)
                            } label: {
                                masqueradeConversationRow(conversation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.pagePadding)
                    .padding(.bottom, 28)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func masqueradeConversationRow(_ conversation: Conversation) -> some View {
        let userID = AuthService.shared.currentUser?.id
        let other = userID.flatMap { conversation.otherMember(currentUserID: $0) }
        let title = other?.displayName ?? other?.username ?? "Chat"
        let preview = conversation.lastMessage?.previewText ?? "No messages yet"
        let verified = other?.isVerified == true || other?.username?.lowercased() == "matterya"

        return HStack(spacing: 12) {
            AvatarView(
                url: other?.avatarURL,
                seed: other?.username ?? other?.userID ?? conversation.id,
                size: 48
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if verified {
                        MatteryaVerifiedBadge(size: 14)
                    }
                }
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let createdAt = conversation.lastMessageAt ?? conversation.lastMessage?.createdAt {
                Text(RelativeTime.format(createdAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func reload() async {
        isLoading = conversations.isEmpty
        defer { isLoading = false }
        do {
            let page = try await MessagesService.shared.listConversations(
                limit: 40,
                forceNetwork: true,
                inbox: "primary"
            )
            conversations = page.filter { !ConversationInboxStore.isHidden($0.id) }
            errorMessage = nil
        } catch {
            if conversations.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Off-white verified seal (Matterya official).
struct MatteryaVerifiedBadge: View {
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.ink)
                .frame(width: size, height: size)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size * 0.92))
                .foregroundStyle(Theme.matte)
        }
        .accessibilityLabel("Verified")
    }
}
