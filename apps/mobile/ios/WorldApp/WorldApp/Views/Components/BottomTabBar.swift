import SwiftUI

/// Quiet premium tab bar — compact glyphs + soft selected pill (Instagram / Linear calm).
struct BottomTabBar: View {
    @Environment(AppState.self) private var appState

    private let leftTabs: [AppTab] = [.feed, .anonymous]
    private let rightTabs: [AppTab] = [.hubs, .messages, .profile]

    /// Premium compact mark size (was 34 — felt oversized for a quiet shell).
    private static let tabIconSize: CGFloat = 22
    private static let createGlyphSize: CGFloat = 22
    private static let createHit: CGFloat = 40
    private static let pillPaddingH: CGFloat = 14
    private static let pillPaddingV: CGFloat = 8

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(leftTabs) { tab in
                tabButton(tab)
                    .frame(maxWidth: .infinity)
            }

            createButton
                .frame(width: 52)

            ForEach(rightTabs) { tab in
                tabButton(tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Theme.tabBarHeight)
        .frame(maxWidth: .infinity)
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
            withAnimation(.easeOut(duration: 0.2)) {
                appState.showAppMenu = false
                appState.globePanel = nil
                if appState.selectedTab == .anonymous {
                    appState.showMasqueradeCreateMenu = true
                } else {
                    appState.showCreateMenu.toggle()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.ink)
                    .frame(width: Self.createHit, height: Self.createHit)
                HandDrawnPlusIcon(size: Self.createGlyphSize, color: Theme.paper)
            }
            .frame(width: Self.createHit + 4, height: Theme.tabBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            appState.selectedTab == .anonymous
                ? MatteryaCopy.anonymousCreateMenuTitle
                : "Create"
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let selected = appState.selectedTab == tab
        return Button {
            if appState.selectedTab != tab {
                appState.navigationPath.removeAll()
            }
            withAnimation(.easeOut(duration: 0.16)) {
                appState.selectedTab = tab
            }
            appState.showAppMenu = false
            appState.globePanel = nil
        } label: {
            tabIcon(tab, selected: selected)
                .padding(.horizontal, Self.pillPaddingH)
                .padding(.vertical, Self.pillPaddingV)
                .background {
                    Capsule(style: .continuous)
                        .fill(selected ? Theme.matteDeep : Color.clear)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Theme.tabBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func tabIcon(_ tab: AppTab, selected: Bool) -> some View {
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
                    .opacity(selected ? 1 : 0.72)
            case .anonymous:
                MatteryaMasqueradeLogoView(size: size)
                    .opacity(selected ? 1 : 0.72)
            default:
                Image(systemName: tab.systemImage)
                    .font(.system(size: size * 0.92, weight: selected ? .semibold : .regular))
                    .symbolVariant(selected ? .fill : .none)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Theme.ink.opacity(selected ? 1 : 0.72))
            }
        }
        .frame(width: size, height: size, alignment: .center)
        .overlay(alignment: .topTrailing) {
            if tab == .messages, appState.messagesUnreadCount > 0 {
                UnreadDot(size: 7)
                    .offset(x: 4, y: -3)
            } else if tab == .anonymous, appState.masqueradeUnreadCount > 0 {
                UnreadDot(size: 7)
                    .offset(x: 4, y: -3)
            }
        }
    }
}

struct ProfileTabAvatar: View {
    let profile: Profile?
    let isSelected: Bool
    /// Same diameter as every other tab icon.
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            AvatarView(
                url: profile?.avatarURL,
                seed: profile?.userID ?? "me",
                size: size
            )
            .opacity(isSelected ? 1 : 0.85)

            if isSelected {
                HandDrawnGlobeStoryRing(size: size, highlighted: true)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
    }
}
