import SwiftUI

struct NotificationsPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOTIFICATIONS")
                    .sectionLabel()
                Text(notificationSummary)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }

            HStack {
                Button("Mark all read") {
                    Task { await appState.markAllNotificationsRead() }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accentBright)
                Spacer()
                Button("Close") {
                    appState.globePanel = nil
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accentBright)
            }

            if appState.notifications.isEmpty {
                Text("No notifications yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.notifications) { notification in
                            Button {
                                // Open destination on the main actor immediately.
                                Task { @MainActor in
                                    await appState.openNotification(notification)
                                }
                            } label: {
                                notificationRow(notification)
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
        .task {
            await appState.refreshNotifications()
        }
    }

    @ViewBuilder
    private func notificationRow(_ notification: NotificationItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(notification.isUnread ? Theme.danger : Color.clear)
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    AvatarView(
                        url: notification.actor?.avatarURL,
                        seed: notification.actor?.userID ?? notification.id,
                        size: 36
                    )
                    if notification.isUnread {
                        Circle()
                            .fill(Theme.danger)
                            .frame(width: 11, height: 11)
                            .overlay(
                                Circle()
                                    .stroke(Theme.surface, lineWidth: 2)
                            )
                            .offset(x: 3, y: -3)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(notificationTitle(notification))
                        .font(.subheadline.weight(notification.isUnread ? .bold : .regular))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Text(RelativeTime.format(notification.createdAt))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer(minLength: 0)

                if notification.isUnread {
                    Text("NEW")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Theme.danger, in: Capsule())
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(notification.isUnread ? Theme.danger.opacity(0.10) : Theme.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(notification.isUnread ? Theme.danger.opacity(0.35) : Theme.border, lineWidth: 0.5)
        )
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

    private var notificationSummary: String {
        var parts: [String] = []
        let social = appState.effectiveNotificationsUnreadCount
        if social > 0 {
            parts.append("Unread: \(social)")
        } else {
            parts.append("All caught up")
        }
        if appState.messagesUnreadCount > 0 {
            parts.append("\(appState.messagesUnreadCount) in Messages")
        }
        return parts.joined(separator: " · ")
    }

    private func notificationTitle(_ n: NotificationItem) -> String {
        let actor = ContentSanitizer.displayName(
            displayName: n.actor?.displayName,
            username: n.actor?.username,
            fallback: "Someone"
        )
        switch n.type.lowercased() {
        case "follow": return "\(actor) followed you"
        case "like": return "\(actor) liked your post"
        case "comment": return "\(actor) commented on your post"
        case "comment_like": return "\(actor) liked your comment"
        case "comment_reply", "reply": return "\(actor) replied to your comment"
        case "message": return "\(actor) sent you a message"
        default: return "\(actor) interacted with you"
        }
    }
}