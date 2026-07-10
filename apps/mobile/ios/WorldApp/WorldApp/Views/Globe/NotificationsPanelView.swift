import SwiftUI

struct NotificationsPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOTIFICATIONS")
                    .sectionLabel()
                Text("Unread: \(appState.notificationsUnreadCount)")
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
                                Task { await appState.openNotification(notification) }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    AvatarView(
                                        url: notification.actor?.avatarURL,
                                        seed: notification.actor?.userID ?? notification.id,
                                        size: 36
                                    )
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(notificationTitle(notification))
                                            .font(.subheadline.weight(notification.isUnread ? .bold : .regular))
                                            .foregroundStyle(Theme.ink)
                                            .multilineTextAlignment(.leading)
                                        Text(RelativeTime.format(notification.createdAt))
                                            .font(.caption2)
                                            .foregroundStyle(Theme.inkMuted)
                                    }
                                    Spacer()
                                    if notification.isUnread {
                                        Circle()
                                            .fill(Theme.accentBright)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(notification.isUnread ? Theme.accentSoft : Theme.surfaceMuted)
                                )
                            }
                            .buttonStyle(.plain)
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

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.surface)
            .shadow(color: Theme.ink.opacity(0.10), radius: 30, y: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
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
        case "comment_reply": return "\(actor) replied to your comment"
        default: return "\(actor) interacted with you"
        }
    }
}