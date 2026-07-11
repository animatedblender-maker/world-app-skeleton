import SwiftUI

struct BottomTabBar: View {
    @Environment(AppState.self) private var appState

    private let leftTabs: [AppTab] = [.feed, .globe]
    private let rightTabs: [AppTab] = [.reels, .messages, .profile]

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
        .background {
            Theme.surface.opacity(0.96)
                .overlay(alignment: .top) {
                    Theme.divider.frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var createButton: some View {
        Button {
            appState.showCreateMenu = true
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
            appState.selectedTab = tab
            appState.showAppMenu = false
            if tab == .globe {
                appState.navigationPath.removeAll()
            }
        } label: {
            tabIcon(tab)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.tabBarHeight)
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: tab == .feed ? 26 : 24, weight: selected ? .semibold : .regular))
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