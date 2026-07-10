import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var pushEnabled = false
    @State private var isRequestingPush = false
    @State private var isSendingTest = false
    @State private var statusMessage: String?
    @State private var registrationSummary = ""

    var body: some View {
        List {
            Section("Account") {
                if let profile = appState.currentProfile {
                    LabeledContent("Name", value: profile.displayName ?? profile.username ?? "Member")
                    if let username = profile.username {
                        LabeledContent("Username", value: "@\(username)")
                    }
                    if let country = profile.countryName {
                        LabeledContent("Home country", value: country)
                    }
                }
                Button("Edit profile") {
                    appState.navigate(to: .editProfile)
                }
            }

            Section("Notifications") {
                Toggle("Incoming calls & alerts", isOn: $pushEnabled)
                    .onChange(of: pushEnabled) { _, enabled in
                        if enabled {
                            Task { await enablePush() }
                        }
                    }

                if isRequestingPush {
                    ProgressView("Requesting permission…")
                }

                if !registrationSummary.isEmpty {
                    Text(registrationSummary)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }

                Button(isSendingTest ? "Sending test…" : "Send test notification") {
                    Task { await sendTestPush() }
                }
                .disabled(isSendingTest || !pushEnabled)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }

            Section("Privacy") {
                NavigationLink("Blocked accounts") {
                    BlockedAccountsView()
                }
                NavigationLink("Data & privacy") {
                    PrivacyInfoView()
                }
            }

            Section("Support") {
                LabeledContent("App", value: "Matterya")
                LabeledContent("Version", value: appVersion)
                Link("Help center", destination: URL(string: "https://matterya.com")!)
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .task {
            await refreshPushStatus()
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func refreshPushStatus() async {
        pushEnabled = await PushNotificationService.shared.notificationsAuthorized()
        await PushNotificationService.shared.syncWithServer(force: true)
        registrationSummary = PushNotificationService.shared.registrationSummary
    }

    private func enablePush() async {
        isRequestingPush = true
        statusMessage = nil
        defer { isRequestingPush = false }
        await PushNotificationService.shared.requestAuthorizationAndRegister()
        await PushNotificationService.shared.syncWithServer(force: true)
        await refreshPushStatus()
        if pushEnabled {
            statusMessage = "Notifications enabled for calls and messages."
        } else {
            statusMessage = "Enable notifications in iOS Settings to receive calls while away."
        }
    }

    private func sendTestPush() async {
        isSendingTest = true
        defer { isSendingTest = false }
        statusMessage = await PushNotificationService.shared.sendTestNotification()
        await refreshPushStatus()
    }
}

private struct BlockedAccountsView: View {
    var body: some View {
        ContentUnavailableView(
            "No blocked accounts",
            systemImage: "hand.raised",
            description: Text("People you block will appear here.")
        )
        .navigationTitle("Blocked")
    }
}

private struct PrivacyInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your data")
                    .font(.headline)
                Text("Matterya stores your profile, posts, and messages on our servers so you can use the app across devices. We do not sell your personal data.")
                    .foregroundStyle(Theme.inkSecondary)
                Text("Calls")
                    .font(.headline)
                Text("Voice and video calls use encrypted real-time channels. Call activity may be logged in your conversation history.")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(Theme.pagePadding)
        }
        .navigationTitle("Privacy")
        .background(Theme.canvas)
    }
}