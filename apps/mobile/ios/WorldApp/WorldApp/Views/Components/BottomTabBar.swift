import SwiftUI

struct BottomTabBar: View {
    @Environment(AppState.self) private var appState

    private let leftTabs: [AppTab] = [.feed, .anonymous]
    private let rightTabs: [AppTab] = [.hubs, .messages, .profile]

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(leftTabs) { tab in
                tabButton(tab)
                    .frame(maxWidth: .infinity)
            }

            createButton
                .frame(width: 56)
                .offset(y: -8)

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
                if appState.selectedTab == .anonymous {
                    // Reddit-style create for Masquerade Spaces / posts.
                    appState.showMasqueradeCreateMenu = true
                } else {
                    appState.showCreateMenu.toggle()
                }
            }
        } label: {
            HandDrawnPlusIcon(size: 34)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appState.selectedTab == .anonymous ? MatteryaCopy.anonymousCreateMenuTitle : "Create")
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

    /// Large equal marks — fills the bar so it doesn’t look sparse / “white gaps”.
    private static let tabIconSize: CGFloat = 34

    @ViewBuilder
    private func tabIcon(_ tab: AppTab) -> some View {
        let selected = appState.selectedTab == tab
        let size = Self.tabIconSize

        ZStack {
            switch tab {
            case .profile:
                ProfileTabAvatar(
                    profile: appState.currentProfile,
                    isSelected: selected,
                    size: size
                )
            case .hubs:
                MatteryaHubsLogoView(size: size)
                    .opacity(selected ? 1 : 0.92)
            case .anonymous:
                MatteryaMasqueradeLogoView(size: size)
                    .opacity(selected ? 1 : 0.92)
            default:
                // Resizable so SF Symbols fill the same H×W as canvas logos / avatar.
                Image(systemName: tab.systemImage)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(selected ? .semibold : .regular)
                    .symbolVariant(selected ? .fill : .none)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(width: size, height: size, alignment: .center)
        .overlay(alignment: .topTrailing) {
            if tab == .messages, appState.messagesUnreadCount > 0 {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: 9, height: 9)
                    .offset(x: 5, y: -2)
            }
        }
    }
}

struct ProfileTabAvatar: View {
    let profile: Profile?
    let isSelected: Bool
    /// Same diameter as every other tab icon.
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            AvatarView(
                url: profile?.avatarURL,
                seed: profile?.userID ?? "me",
                size: size
            )
            .opacity(isSelected ? 1 : 0.92)

            if isSelected {
                HandDrawnGlobeStoryRing(size: size, highlighted: true)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
    }
}