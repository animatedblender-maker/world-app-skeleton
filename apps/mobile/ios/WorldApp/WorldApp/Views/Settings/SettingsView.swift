import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var pushEnabled = false
    @State private var isRequestingPush = false
    @State private var notificationsHint: String?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsSection(title: "Account") {
                    if let profile = appState.currentProfile {
                        settingsInfoRow("Name", profile.displayName ?? profile.username ?? "Member")
                        if let username = profile.username {
                            settingsInfoRow("Username", "@\(username)")
                        }
                        if let country = profile.countryName {
                            settingsInfoRow("Home country", country)
                        }
                    }
                    Button {
                        appState.navigate(to: .editProfile)
                    } label: {
                        settingsActionLabel("Edit profile", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle())

                    Button {
                        appState.logout()
                    } label: {
                        settingsActionLabel("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle(destructive: true))
                }

                settingsSection(
                    title: "Account control",
                    footer: "Deactivate is temporary. Delete removes your Matterya identity and content for good."
                ) {
                    Button {
                        accountActionError = nil
                        accountSheet = .deactivate
                    } label: {
                        settingsMultiLineLabel(
                            title: "Deactivate account",
                            subtitle: "Hide your profile and pause activity. You can sign in again anytime to reactivate."
                        )
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle())
                    .disabled(accountActionBusy)

                    Button {
                        deleteConfirmationText = ""
                        accountActionError = nil
                        accountSheet = .delete
                    } label: {
                        settingsMultiLineLabel(
                            title: "Delete account",
                            subtitle: "Permanently delete your account, profile, and posts. This cannot be undone.",
                            destructive: true
                        )
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle(destructive: true))
                    .disabled(accountActionBusy)

                    if let accountActionError {
                        Text(accountActionError)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 4)
                    }
                }

                settingsSection(
                    title: "Notifications",
                    footer: "Used for messages, calls, and activity. Turn delivery off in iOS Settings if you change your mind."
                ) {
                    settingsCard {
                        HStack {
                            Text("Notifications")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            MatteryaSwitch(isOn: $pushEnabled)
                                .onChange(of: pushEnabled) { _, enabled in
                                    if enabled {
                                        Task { await enablePush() }
                                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                        }

                        if isRequestingPush {
                            ProgressView("Requesting permission…")
                                .tint(Theme.ink)
                        }

                        if let notificationsHint {
                            Text(notificationsHint)
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        settingsActionLabel("Open iOS Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle())
                }

                settingsSection(
                    title: "Privacy",
                    footer: "Control who can message you. Non-followers can be sent to Message Requests or blocked entirely."
                ) {
                    NavigationLink {
                        MessagePrivacySettingsView()
                    } label: {
                        settingsActionLabel("Message requests", systemImage: "envelope.badge", showsChevron: true)
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle())

                    NavigationLink {
                        BlockedAccountsView()
                    } label: {
                        settingsActionLabel("Blocked accounts", systemImage: "hand.raised", showsChevron: true)
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle())

                    NavigationLink {
                        PrivacyInfoView()
                    } label: {
                        settingsActionLabel("Data & privacy", systemImage: "lock.shield", showsChevron: true)
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle())
                }

                settingsSection(title: "Support") {
                    settingsInfoRow("App", "Matterya")
                    settingsInfoRow("Version", appVersion)
                    Link(destination: URL(string: "https://matterya.com")!) {
                        settingsActionLabel("Help center", systemImage: "questionmark.circle", showsChevron: true)
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle())
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 18)
        }
        .navigationTitle("Settings")
        .background(Theme.canvas)
        .task {
            pushEnabled = await PushNotificationService.shared.notificationsAuthorized()
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
                        Button {
                            accountSheet = nil
                            accountActionError = nil
                        } label: {
                            Text("Cancel")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.matte, in: Capsule(style: .continuous))
                                .overlay(Capsule(style: .continuous).stroke(Theme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(accountActionBusy)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Matterya settings chrome (not UIKit List)

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            VStack(spacing: 8) {
                content()
            }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
        )
    }

    private func settingsInfoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
        )
    }

    private func settingsActionLabel(
        _ title: String,
        systemImage: String,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 22)
            Text(title)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func settingsMultiLineLabel(
        title: String,
        subtitle: String,
        destructive: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(destructive ? Theme.danger : Theme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 2)
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
                    if accountActionBusy { ProgressView().tint(Theme.paper) }
                    Text(accountActionBusy ? "Deactivating…" : "Deactivate")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(accountActionBusy)
        }
        .padding(20)
        .navigationTitle("Deactivate")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.canvas)
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
                .background(Theme.matteDeep, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    if accountActionBusy { ProgressView().tint(Theme.paper) }
                    Text(accountActionBusy ? "Deleting…" : "Delete forever")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 12)
                .foregroundStyle(Theme.paper)
                .background(Theme.danger, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(accountActionBusy || deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .navigationTitle("Delete")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.canvas)
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

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func enablePush() async {
        isRequestingPush = true
        notificationsHint = nil
        defer { isRequestingPush = false }
        await PushNotificationService.shared.requestAuthorizationAndRegister()
        await PushNotificationService.shared.syncWithServer(force: true)
        pushEnabled = await PushNotificationService.shared.notificationsAuthorized()
        if pushEnabled {
            notificationsHint = "Notifications are on for messages, calls, and activity."
        } else {
            notificationsHint = "Permission was not granted. You can enable it in iOS Settings."
        }
    }
}

private struct MessagePrivacySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selected: MessagePrivacy = .everyone
    @State private var isSaving = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Who can message you")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                ForEach(MessagePrivacy.allCases, id: \.self) { option in
                    Button {
                        Task { await save(option) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .foregroundStyle(Theme.ink)
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if selected == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                    .buttonStyle(MatteryaSettingsRowButtonStyle())
                    .disabled(isSaving)
                }

                Text("People you already follow always reach your primary inbox. Blocked accounts never can.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 4)
                }
            }
            .padding(Theme.pagePadding)
        }
        .navigationTitle("Message requests")
        .background(Theme.canvas)
        .task {
            selected = appState.currentProfile?.resolvedMessagePrivacy ?? .everyone
            if let profile = try? await ProfileService.shared.meProfile() {
                appState.currentProfile = profile
                selected = profile.resolvedMessagePrivacy
            }
        }
    }

    private func save(_ option: MessagePrivacy) async {
        guard option != selected else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await ProfileService.shared.updateProfile(messagePrivacy: option.rawValue)
            appState.currentProfile = updated
            ContentCache.shared.setProfile(updated)
            selected = option
            statusMessage = "Saved — \(option.title)."
            appState.showToast("Message privacy updated", style: .success)
        } catch {
            statusMessage = error.localizedDescription
            appState.showToast(error.localizedDescription, style: .error)
        }
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
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(blocked) { account in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(account.label)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Theme.ink)
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
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.matteDeep, in: Capsule(style: .continuous))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(Theme.pagePadding)
                }
            }
        }
        .navigationTitle("Blocked")
        .background(Theme.canvas)
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
                    .foregroundStyle(Theme.ink)
                Text("Matterya stores your profile, posts, and messages on our servers so you can use the app across devices. We do not sell your personal data.")
                    .foregroundStyle(Theme.inkSecondary)
                Text("Calls")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("Voice and video calls use encrypted real-time channels. Call activity may be logged in your conversation history.")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(Theme.pagePadding)
        }
        .navigationTitle("Privacy")
        .background(Theme.canvas)
    }
}
