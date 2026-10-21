import SwiftUI

struct AnonymousInboxView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 18) {
            AnonymousEmptyState(
                title: MatteryaCopy.anonymousInboxTitle,
                message: MatteryaCopy.anonymousInboxBody,
                systemImage: "tray",
                actionTitle: "Open Matterya notifications"
            ) {
                appState.globePanel = .notifications
                Task { await appState.refreshNotifications() }
            }

            Text(MatteryaCopy.anonymousInboxPrivacyNote)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
        }
    }
}
