import SwiftUI

struct MatteryaTopBar: View {
    @Environment(AppState.self) private var appState

    var showsSearch: Bool = false
    var onSearch: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            MenuToolbarButton()
                .frame(width: 44, height: 44)

            Spacer()

            Text(AppConfig.appName)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .tracking(0.5)

            Spacer()

            HStack(spacing: 18) {
                if showsSearch {
                    Button {
                        onSearch?()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    toggleNotifications()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Theme.ink)
                        if appState.notificationsUnreadCount > 0 {
                            Circle()
                                .fill(Theme.danger)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -2)
                        }
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    appState.globePanel = nil
                    appState.selectedTab = .profile
                } label: {
                    ProfileTabAvatar(
                        profile: appState.currentProfile,
                        isSelected: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.surface.opacity(0.92))
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }

    private func toggleNotifications() {
        if appState.globePanel == .notifications {
            appState.globePanel = nil
        } else {
            appState.globePanel = .notifications
            Task { await appState.refreshNotifications() }
        }
    }
}

struct ProfileTabTopBar: View {
    let title: String
    var onEdit: () -> Void
    var onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            MenuToolbarButton()
                .frame(width: 44, height: 44)

            Spacer()

            Text(title)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            HStack(spacing: 16) {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")

                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit profile")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.surface.opacity(0.92))
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }
}

struct NotificationsOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.globePanel == .notifications {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { appState.globePanel = nil }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    NotificationsPanelView()
                        .padding(.trailing, Theme.pagePadding)
                }
                .padding(.top, 52)
                Spacer()
            }
        }
    }
}