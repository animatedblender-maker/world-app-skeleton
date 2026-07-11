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
                        Image(systemName: appState.effectiveNotificationsUnreadCount > 0 ? "bell.badge.fill" : "bell")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Theme.ink)
                            .symbolRenderingMode(.monochrome)
                        if appState.effectiveNotificationsUnreadCount > 0 {
                            UnreadBadge(count: appState.effectiveNotificationsUnreadCount, size: 17)
                                .offset(x: 7, y: -7)
                        }
                    }
                    .frame(width: 36, height: 36)
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