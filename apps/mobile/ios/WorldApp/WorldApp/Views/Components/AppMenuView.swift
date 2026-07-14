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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Menu")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { closeMenu() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if let profile = appState.currentProfile {
                Button {
                    appState.openProfileFromMenu()
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: profile.avatarURL, seed: profile.userID, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName ?? profile.username ?? "You")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            if let username = profile.username {
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Theme.divider.frame(height: 0.5)

            VStack(spacing: 0) {
                menuRow(
                    "Notifications",
                    icon: "bell",
                    showsUnreadDot: appState.effectiveNotificationsUnreadCount > 0
                ) {
                    appState.openNotificationsFromMenu()
                }
                menuRow(MatteryaCopy.matteryaHubs, icon: "square.grid.2x2") {
                    appState.openPlayFromMenu()
                }
                menuRow("Discover People", icon: "person.2") {
                    appState.openFromMenu(.people)
                }
                menuRow("Ads Manager", icon: "megaphone") {
                    appState.openFromMenu(.ads)
                }
                menuRow("Invite friends", icon: "person.badge.plus") {
                    appState.inviteFriendsFromMenu()
                }
                menuRow("Saved", icon: "bookmark") {
                    appState.openSavedFromMenu()
                }
                menuRow("Settings", icon: "gearshape") {
                    appState.openFromMenu(.settings)
                }
            }
            .padding(.vertical, 8)

            Spacer()

            Theme.divider.frame(height: 0.5)

            Button {
                closeMenu()
                appState.logout()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 20))
                        .frame(width: 24)
                    Text("Log Out")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(Theme.danger)
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
        .shadow(color: .black.opacity(0.12), radius: 24, x: 8)
        .onChange(of: appState.showAppMenu) { _, isOpen in
            if isOpen {
                Task { await appState.refreshUnreadCounts() }
            }
        }
    }

    private func menuRow(
        _ title: String,
        icon: String,
        showsUnreadDot: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 24)
                Text(title)
                    .font(.body.weight(.regular))
                Spacer()
                if showsUnreadDot {
                    UnreadDot(size: 9)
                }
            }
            .foregroundStyle(Theme.ink)
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
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