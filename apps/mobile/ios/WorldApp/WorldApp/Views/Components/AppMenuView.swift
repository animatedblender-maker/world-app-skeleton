import SwiftUI

struct AppMenuOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .leading) {
            if appState.showAppMenu {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }

                AppMenuPanel()
                    .frame(width: min(320, UIScreen.main.bounds.width * 0.84))
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: appState.showAppMenu)
        .allowsHitTesting(appState.showAppMenu)
        // Dark scheme → white notch clock / battery over the menu scrim.
        .preferredColorScheme(appState.showAppMenu ? .dark : nil)
        .zIndex(200)
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.22)) {
            appState.showAppMenu = false
        }
    }
}

private struct AppMenuPanel: View {
    @Environment(AppState.self) private var appState
    @State private var hasOwnHubsChannel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Menu")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { closeMenu() } label: {
                    Text("Close")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.matte, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 20)
            .padding(.bottom, 14)

            if let profile = appState.currentProfile {
                Button {
                    appState.openProfileFromMenu()
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: profile.avatarURL, seed: profile.userID, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.displayName ?? profile.username ?? "You")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            if let username = profile.username {
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.inkMuted)
                                    .lineLimit(1)
                            }
                            Text("View profile")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .underline(true, color: Theme.ink.opacity(0.35))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 18)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    menuRow(hubsMenuTitle) {
                        appState.openPlayFromMenu()
                    }
                    menuRow("Discover people") {
                        appState.openFromMenu(.people)
                    }
                    menuRow("Ads Manager") {
                        appState.openFromMenu(.ads)
                    }
                    menuRow("Invite friends") {
                        appState.inviteFriendsFromMenu()
                    }
                    menuRow("Saved") {
                        appState.openSavedFromMenu()
                    }
                    menuRow("Settings") {
                        appState.openFromMenu(.settings)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            Button {
                closeMenu()
                appState.logout()
            } label: {
                Text("Log out")
            }
            .buttonStyle(MatteryaSettingsRowButtonStyle(destructive: true))
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 20)
            .padding(.top, 8)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.canvas)
        .shadow(color: .black.opacity(0.12), radius: 24, x: 8)
        .onAppear {
            refreshChannelFlag()
        }
        .onChange(of: appState.showAppMenu) { _, isOpen in
            if isOpen {
                refreshChannelFlag()
                Task { await appState.refreshUnreadCounts() }
            }
        }
        .onChange(of: appState.currentProfile?.bio) { _, _ in
            refreshChannelFlag()
        }
    }

    /// Channel name when you own a Hubs channel; otherwise Matterya Hubs browse entry.
    private var hubsMenuTitle: String {
        let profile = appState.currentProfile
        if hasOwnHubsChannel || LivingChannelMarker.hasChannel(profile: profile) {
            if let channelName = LivingChannelMarker.parse(from: profile?.bio)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !channelName.isEmpty {
                return channelName
            }
            return MatteryaCopy.personsHubTitle(
                displayName: profile?.displayName,
                username: profile?.username
            )
        }
        return MatteryaCopy.matteryaHubs
    }

    private func menuRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .buttonStyle(MatteryaSettingsRowButtonStyle())
    }

    private func refreshChannelFlag() {
        hasOwnHubsChannel = LivingChannelMarker.hasChannel(profile: appState.currentProfile)
        guard let userID = appState.currentProfile?.userID, !userID.isEmpty else { return }
        Task { @MainActor in
            if LivingChannelMarker.hasChannel(profile: appState.currentProfile) {
                hasOwnHubsChannel = true
                return
            }
            if let channel = try? await ChannelsService.shared.channelByOwner(userID: userID),
               !channel.id.isEmpty {
                hasOwnHubsChannel = true
            }
        }
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.22)) {
            appState.showAppMenu = false
        }
    }
}

struct MenuToolbarButton: View {
    @Environment(AppState.self) private var appState
    var tint: Color = Theme.ink

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.22)) {
                appState.showAppMenu = true
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(tint)
        }
        .accessibilityLabel("Menu")
    }
}
