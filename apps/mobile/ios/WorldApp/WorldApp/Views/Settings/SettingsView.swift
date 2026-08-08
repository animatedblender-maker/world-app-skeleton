import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var pushEnabled = false
    @State private var isRequestingPush = false
    @State private var isSendingTest = false
    @State private var isRefreshingPush = false
    @State private var statusMessage: String?
    @State private var registrationSummary = ""
    @State private var alertTokenStatus = "Checking…"
    @State private var alertServerStatus = "Checking…"
    @State private var serverApnsStatus = "Checking…"
    @State private var serverPushRoutesStatus = "Checking…"
    @State private var serverTokenSummary = ""
    @State private var callingSummary = ""
    @State private var voipTokenStatus = "Checking…"
    @State private var voipServerStatus = "Checking…"
    @State private var signalingStatus = "Checking…"
    @State private var incomingCallsReady = false
    @State private var pushEnvironmentLabel = ""
    @State private var isRefreshingCalling = false

    /// Sheet-based account actions (confirmationDialog inside List often fails to present).
    @State private var accountSheet: AccountSheet?
    @State private var deleteConfirmationText = ""
    @State private var accountActionBusy = false
    @State private var accountActionError: String?

    private enum AccountSheet: String, Identifiable {
        case deactivate
        case delete
        var id: String { rawValue }
    }

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

            Section {
                Button {
                    accountActionError = nil
                    accountSheet = .deactivate
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Deactivate account")
                                .foregroundStyle(Theme.ink)
                            Text("Hide your profile and pause activity. You can sign in again anytime to reactivate.")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                .disabled(accountActionBusy)

                Button(role: .destructive) {
                    deleteConfirmationText = ""
                    accountActionError = nil
                    accountSheet = .delete
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Delete account")
                            Text("Permanently delete your account, profile, and posts. This cannot be undone.")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                .disabled(accountActionBusy)

                if let accountActionError {
                    Text(accountActionError)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            } header: {
                Text("Account control")
            } footer: {
                Text("Deactivate is temporary. Delete removes your Matterya identity and content for good.")
            }

            Section {
                Toggle("Incoming calls & alerts", isOn: $pushEnabled)
                    .onChange(of: pushEnabled) { _, enabled in
                        if enabled {
                            Task { await enablePush() }
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }

                if isRequestingPush {
                    ProgressView("Requesting permission…")
                }

                LabeledContent("Alert token") {
                    statusLabel(alertTokenStatus, positive: alertTokenStatus == "Received")
                }
                LabeledContent("Server registration") {
                    statusLabel(alertServerStatus, positive: alertServerStatus == "Registered")
                }
                LabeledContent("Push API routes") {
                    statusLabel(serverPushRoutesStatus, positive: serverPushRoutesStatus == "Deployed")
                }
                LabeledContent("Server APNs") {
                    statusLabel(serverApnsStatus, positive: serverApnsStatus == "Configured")
                }
                if !serverTokenSummary.isEmpty {
                    LabeledContent("Devices on server") {
                        Text(serverTokenSummary)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                    }
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

                Button(isRefreshingPush ? "Refreshing…" : "Refresh push status") {
                    Task { await refreshPushStatus() }
                }
                .disabled(isRefreshingPush)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Browser notifications use Web Push (VAPID). iOS uses Apple Push (APNS) — a separate Render env setup. You need APNS_TEAM_ID, APNS_KEY_ID, and APNS_PRIVATE_KEY on Render, plus a registered device token here.")
            }

            Section {
                LabeledContent("VoIP token") {
                    statusLabel(voipTokenStatus, positive: voipTokenStatus == "Received")
                }
                LabeledContent("Server registration") {
                    statusLabel(voipServerStatus, positive: voipServerStatus == "Registered")
                }
                LabeledContent("Call signaling") {
                    statusLabel(signalingStatus, positive: signalingStatus == "Connected")
                }
                LabeledContent("Incoming calls") {
                    statusLabel(
                        incomingCallsReady ? "Ready" : "Not ready",
                        positive: incomingCallsReady
                    )
                }
                LabeledContent("Push environment") {
                    Text(pushEnvironmentLabel)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }

                if !callingSummary.isEmpty {
                    Text(callingSummary)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }

                Button(isRefreshingCalling ? "Refreshing…" : "Refresh calling status") {
                    Task { await refreshCallingStatus() }
                }
                .disabled(isRefreshingCalling)
            } header: {
                Text("Calling")
            } footer: {
                Text("Incoming calls when Matterya is closed require VoIP registration, a real iPhone (not Simulator), and APNs credentials on the Matterya API server. If Server registration stays red, calls cannot ring off-app.")
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
            await refreshCallingStatus()
        }
        .sheet(item: $accountSheet) { sheet in
            NavigationStack {
                Group {
                    switch sheet {
                    case .deactivate:
                        deactivateSheet
                    case .delete:
                        deleteSheet
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            accountSheet = nil
                            accountActionError = nil
                        }
                        .disabled(accountActionBusy)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var deactivateSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deactivate account?")
                .font(.title3.weight(.bold))
            Text("Your profile will be hidden and you will be signed out. Sign in again anytime to reactivate.")
                .foregroundStyle(Theme.inkSecondary)
            if let accountActionError {
                Text(accountActionError)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
            Spacer()
            Button {
                Task { await performDeactivate() }
            } label: {
                HStack {
                    Spacer()
                    if accountActionBusy { ProgressView().tint(.white) }
                    Text(accountActionBusy ? "Deactivating…" : "Deactivate")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Theme.danger, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(accountActionBusy)
        }
        .padding(20)
        .navigationTitle("Deactivate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var deleteSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete account permanently?")
                .font(.title3.weight(.bold))
            Text("This cannot be undone. Posts, profile, and login will be removed.")
                .foregroundStyle(Theme.inkSecondary)
            let handle = appState.currentProfile?.username.map { "@\($0)" } ?? "your username"
            Text("Type DELETE or \(handle) to confirm.")
                .font(.footnote)
                .foregroundStyle(Theme.inkMuted)
            TextField("DELETE or username", text: $deleteConfirmationText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))
            if let accountActionError {
                Text(accountActionError)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
            Spacer()
            Button {
                Task { await performDelete() }
            } label: {
                HStack {
                    Spacer()
                    if accountActionBusy { ProgressView().tint(.white) }
                    Text(accountActionBusy ? "Deleting…" : "Delete forever")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Theme.danger, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(accountActionBusy || deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .navigationTitle("Delete")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func performDeactivate() async {
        accountActionBusy = true
        accountActionError = nil
        defer { accountActionBusy = false }
        do {
            try await appState.deactivateAccount()
            accountSheet = nil
        } catch {
            accountActionError = error.localizedDescription
        }
    }

    private func performDelete() async {
        let confirmation = deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !confirmation.isEmpty else {
            accountActionError = "Enter DELETE or your username to confirm."
            return
        }
        accountActionBusy = true
        accountActionError = nil
        defer { accountActionBusy = false }
        do {
            try await appState.deleteAccount(confirmation: confirmation)
            accountSheet = nil
        } catch {
            accountActionError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func statusLabel(_ text: String, positive: Bool) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(positive ? Theme.success : Theme.inkMuted)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func refreshPushStatus() async {
        isRefreshingPush = true
        defer { isRefreshingPush = false }

        pushEnabled = await PushNotificationService.shared.notificationsAuthorized()
        VoIPPushService.shared.bootstrap()
        await PushNotificationService.shared.syncWithServer(force: true)

        let push = PushNotificationService.shared
        registrationSummary = push.registrationSummary
        alertTokenStatus = push.hasAlertToken ? "Received" : "Waiting"
        alertServerStatus = push.serverRegistrationSucceeded ? "Registered" : "Not registered"

        if let serverStatus = await push.fetchServerPushStatus() {
            serverPushRoutesStatus = serverStatus.endpointsAvailable ? "Deployed" : "Missing"
            serverApnsStatus = serverStatus.apnsConfigured ? "Configured" : "Not configured"
            if let statusMessage = serverStatus.statusMessage {
                serverTokenSummary = statusMessage
            } else {
                var parts = ["\(serverStatus.alertTokenCount) alert"]
                if serverStatus.voipTokenCount > 0 {
                    parts.append("\(serverStatus.voipTokenCount) VoIP")
                }
                if !serverStatus.environments.isEmpty {
                    parts.append(serverStatus.environments.joined(separator: ", "))
                }
                serverTokenSummary = parts.joined(separator: " · ")
            }
        } else {
            let capabilities = await push.fetchServerCapabilities()
            serverPushRoutesStatus = capabilities.iosPushRoutes ? "Deployed" : "Missing"
            serverApnsStatus = capabilities.apnsConfigured ? "Configured" : "Unknown"
            serverTokenSummary = capabilities.iosPushRoutes
                ? "Could not load per-account push status. Sign in and refresh again."
                : "api.matterya.com is running an old API build without /push/ios routes."
        }
    }

    private func refreshCallingStatus() async {
        isRefreshingCalling = true
        defer { isRefreshingCalling = false }

        VoIPPushService.shared.bootstrap()
        CallSessionManager.shared.bootstrap()
        _ = await CallSignalingService.shared.ensureConnected()
        await VoIPPushService.shared.ensureToken()
        await PushNotificationService.shared.syncWithServer(force: true)

        let push = PushNotificationService.shared
        if !VoIPPushService.shared.isSupportedOnThisDevice {
            voipTokenStatus = "Unavailable"
        } else if push.hasVoIPToken {
            voipTokenStatus = "Received"
        } else if VoIPPushService.shared.isRegistryActive {
            voipTokenStatus = "Waiting"
        } else {
            voipTokenStatus = "Registry off"
        }
        voipServerStatus = push.voipServerRegistrationSucceeded ? "Registered" : "Not registered"
        signalingStatus = CallSignalingService.shared.isConnected ? "Connected" : "Offline"
        incomingCallsReady = push.isReadyForIncomingCalls
        pushEnvironmentLabel = push.pushEnvironmentLabel
        #if targetEnvironment(simulator)
        callingSummary = "Simulator cannot receive VoIP calls. Install on a real iPhone to test ringing when Matterya is closed."
        #else
        callingSummary = push.callingRegistrationSummary
        #endif
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
        await refreshCallingStatus()
    }

    private func sendTestPush() async {
        isSendingTest = true
        defer { isSendingTest = false }
        statusMessage = await PushNotificationService.shared.sendTestNotification()
        await refreshPushStatus()
    }
}

private struct BlockedAccountsView: View {
    @Environment(AppState.self) private var appState
    @State private var blocked = BlockService.shared.blocked

    var body: some View {
        Group {
            if blocked.isEmpty {
                ContentUnavailableView(
                    "No blocked accounts",
                    systemImage: "hand.raised",
                    description: Text("People you block won't appear in your feed. Block someone from their post menu or profile.")
                )
            } else {
                List(blocked) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.label)
                                .font(.body.weight(.medium))
                            if let username = account.username {
                                Text("@\(username)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                        }
                        Spacer()
                        Button("Unblock") {
                            appState.unblockUser(account.userID)
                            blocked = BlockService.shared.blocked
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .navigationTitle("Blocked")
        .onAppear {
            blocked = BlockService.shared.blocked
        }
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
