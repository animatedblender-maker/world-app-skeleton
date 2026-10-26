import SwiftUI

/// Masquerade notifications dropdown — same pattern as main `NotificationsPanelView`,
/// scoped to Masquerade alerts only (never Matterya social notifications).
struct MasqueradeNotificationsPanel: View {
    @State private var store = AnonymousStore.shared
    var onClose: () -> Void
    var onSelect: (AnonymousNotification) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MASQUERADE")
                    .sectionLabel()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }

            HStack {
                if store.inbox.contains(where: \.isUnread) {
                    Button("Mark all read") {
                        Task { await store.markAllNotificationsRead() }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Button("Close") { onClose() }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accentBright)
            }

            if store.inboxLoading && store.inbox.isEmpty {
                ProgressView()
                    .tint(Theme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if store.inbox.isEmpty {
                Text(MatteryaCopy.anonymousNotificationsTitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.inbox) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                notificationRow(item)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .frame(maxHeight: min(420, UIScreen.main.bounds.height * 0.45))
            }
        }
        .padding(16)
        .frame(width: min(320, UIScreen.main.bounds.width - 32))
        .background(panelBackground)
        .task { await store.loadInbox(force: true) }
    }

    private var summary: String {
        let unread = store.inbox.filter(\.isUnread).count
        if unread > 0 { return "Unread: \(unread)" }
        return "All caught up"
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.surface)
            .shadow(color: Theme.ink.opacity(0.10), radius: 30, y: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }

    private func notificationRow(_ item: AnonymousNotification) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.isUnread ? Theme.danger : Color.clear)
                .frame(width: 4)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(item.isUnread ? .bold : .regular))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(item.displayBody)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
                if let created = item.createdAt {
                    Text(RelativeTime.format(created))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.isUnread {
                Text("NEW")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Theme.danger, in: Capsule())
                    .padding(.trailing, 10)
                    .padding(.top, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item.isUnread ? Theme.danger.opacity(0.10) : Theme.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.isUnread ? Theme.danger.opacity(0.35) : Theme.border, lineWidth: 0.5)
        )
    }
}

/// Masquerade **Inbox** — anonymous-only. For now: official Matterya team thread only
/// (never normal Matterya DMs). User↔user Masquerade chat comes later.
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
                                // Stay in Masquerade — Back returns to this Inbox (not Messages tab).
                                appState.masqueradeChatChrome = true
                                AnonymousStore.shared.pushConversation(
                                    id: conversation.id,
                                    seed: conversation
                                )
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
        let title = other?.displayName ?? other?.username ?? "Matterya"
        let preview = conversation.lastMessage?.previewText ?? "No messages yet"

        let me = userID ?? ""
        let unread = !me.isEmpty && conversation.hasUnread(for: me)

        return HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AvatarView(
                    url: other?.avatarURL,
                    seed: other?.username ?? other?.userID ?? conversation.id,
                    size: 48
                )
                if unread {
                    UnreadDot(size: 10)
                        .offset(x: 2, y: -2)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(unread ? .bold : .semibold))
                        .foregroundStyle(Theme.ink)
                    if other?.showsVerifiedBadge == true {
                        MatteryaVerifiedBadge(size: 15)
                    }
                }
                Text(preview)
                    .font(.caption.weight(unread ? .semibold : .regular))
                    .foregroundStyle(unread ? Theme.inkSecondary : Theme.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let createdAt = conversation.lastMessageAt ?? conversation.lastMessage?.createdAt {
                    Text(RelativeTime.format(createdAt))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }
                if unread {
                    UnreadDot(size: 8)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (unread ? Theme.danger.opacity(0.06) : Theme.surface),
            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(unread ? Theme.danger.opacity(0.28) : Theme.border, lineWidth: 0.5)
        )
    }

    private func reload() async {
        isLoading = conversations.isEmpty
        defer { isLoading = false }
        do {
            // Masquerade-surface threads only — never the normal Messages welcome DM.
            let page = try await MessagesService.shared.listConversations(
                limit: 40,
                forceNetwork: true,
                inbox: "masquerade"
            )
            let me = AuthService.shared.currentUser?.id
            conversations = page.filter { conversation in
                guard !ConversationInboxStore.isHidden(conversation.id) else { return false }
                guard let me else { return false }
                guard let other = conversation.otherMember(currentUserID: me) else { return false }
                return Self.isMasqueradeOfficialPeer(other)
            }
            errorMessage = nil
        } catch {
            if conversations.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Official Matterya account only (verified / @matterya).
    private static func isMasqueradeOfficialPeer(_ other: PostAuthor) -> Bool {
        if other.showsVerifiedBadge { return true }
        let handle = (other.username ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return handle == "matterya"
    }
}

/// Matterya verified badge — scalloped seal + white check.
/// Default warm bronze `#96713F`, size 20.
struct MatteryaVerifiedBadge: View {
    var size: CGFloat = 20
    var color: Color = Theme.verifiedMark

    var body: some View {
        ZStack {
            MatteryaVerifiedScallopShape()
                .fill(color)
            MatteryaVerifiedCheckShape()
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: size * (2.6 / 24),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verified account")
    }
}

/// Scalloped badge outline in a 24×24 design space (same path as the Angular SVG).
private struct MatteryaVerifiedScallopShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: o.x + x * s, y: o.y + y * s)
        }
        var path = Path()
        path.move(to: p(12, 1.5))
        path.addLine(to: p(14.8, 3.1))
        path.addLine(to: p(18, 3.4))
        path.addLine(to: p(19, 6.5))
        path.addLine(to: p(21.7, 8.3))
        path.addLine(to: p(21, 11.5))
        path.addLine(to: p(21.7, 14.7))
        path.addLine(to: p(19, 16.5))
        path.addLine(to: p(18, 19.6))
        path.addLine(to: p(14.8, 19.9))
        path.addLine(to: p(12, 22.5))
        path.addLine(to: p(9.2, 20.9))
        path.addLine(to: p(6, 20.6))
        path.addLine(to: p(5, 17.5))
        path.addLine(to: p(2.3, 15.7))
        path.addLine(to: p(3, 12.5))
        path.addLine(to: p(2.3, 9.3))
        path.addLine(to: p(5, 6.5))
        path.addLine(to: p(6, 3.4))
        path.addLine(to: p(9.2, 3.1))
        path.closeSubpath()
        return path
    }
}

/// White check stroke in a 24×24 design space.
private struct MatteryaVerifiedCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: o.x + x * s, y: o.y + y * s)
        }
        var path = Path()
        path.move(to: p(7.3, 12.1))
        path.addLine(to: p(10.4, 15.1))
        path.addLine(to: p(16.8, 8.5))
        return path
    }
}
