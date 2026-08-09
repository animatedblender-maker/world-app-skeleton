import SwiftUI

struct BottomTabBar: View {
    @Environment(AppState.self) private var appState

    private let leftTabs: [AppTab] = [.feed, .globe]
    private let rightTabs: [AppTab] = [.hubs, .messages, .profile]

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(leftTabs) { tab in
                tabButton(tab)
                    .frame(maxWidth: .infinity)
            }

            createButton
                .frame(width: 52)
                .offset(y: -10)

            ForEach(rightTabs) { tab in
                tabButton(tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Theme.tabBarHeight)
        .frame(maxWidth: .infinity)
        // Keep icons in the bar; extend surface into the home-indicator so nothing
        // white peeks under the tab bar mid-screen.
        .padding(.bottom, 0)
        .background {
            Theme.surface.opacity(0.96)
                .overlay(alignment: .top) {
                    Theme.divider.frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
    }

    private var createButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.24)) {
                appState.showAppMenu = false
                appState.globePanel = nil
                appState.showCreateMenu.toggle()
            }
        } label: {
            HandDrawnPlusIcon(size: 30)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create")
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            if appState.selectedTab != tab {
                appState.navigationPath.removeAll()
            }
            appState.selectedTab = tab
            appState.showAppMenu = false
            appState.globePanel = nil
        } label: {
            tabIcon(tab)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.tabBarHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private func tabIconSize(_ tab: AppTab) -> CGFloat {
        switch tab {
        case .feed: 26
        case .hubs, .messages: 22
        default: 24
        }
    }

    @ViewBuilder
    private func tabIcon(_ tab: AppTab) -> some View {
        let selected = appState.selectedTab == tab

        switch tab {
        case .profile:
            ProfileTabAvatar(
                profile: appState.currentProfile,
                isSelected: selected
            )
        default:
            ZStack(alignment: .topTrailing) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: tabIconSize(tab), weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink)
                    .symbolVariant(selected ? .fill : .none)

                if tab == .messages, appState.messagesUnreadCount > 0 {
                    Circle()
                        .fill(Theme.danger)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -2)
                }
            }
        }
    }
}

struct ProfileTabAvatar: View {
    let profile: Profile?
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                HandDrawnGlobeStoryRing(size: 30, highlighted: true)
            }

            AvatarView(
                url: profile?.avatarURL,
                seed: profile?.userID ?? "me",
                size: isSelected ? 26 : 28
            )
            .opacity(isSelected ? 1 : 0.92)
        }
    }
}