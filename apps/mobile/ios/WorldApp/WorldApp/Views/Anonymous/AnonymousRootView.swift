import SwiftUI

enum AnonymousShellTab: String, CaseIterable, Identifiable {
    case spaces, feed, search, inbox, me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spaces: "Spaces"
        case .feed: "Feed"
        case .search: "Search"
        case .inbox: "Inbox"
        case .me: "Me"
        }
    }
}

struct AnonymousRootView: View {
    @Environment(AppState.self) private var appState
    @State private var store = AnonymousStore.shared
    @State private var shellTab: AnonymousShellTab = .spaces
    @State private var showCreateSpace = false

    var body: some View {
        VStack(spacing: 0) {
            header
            phaseBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .task {
            await store.bootstrap()
        }
        .onChange(of: store.lastError) { _, _ in
            if let msg = store.consumeError() {
                appState.showToast(msg, style: .error)
            }
        }
        .sheet(isPresented: $showCreateSpace) {
            AnonymousCreateSpaceView()
                .environment(appState)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MatteryaCopy.anonymous)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text(MatteryaCopy.anonymousModeChip)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.matteDeep, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                }

                Spacer()

                Button {
                    if appState.globePanel == .notifications {
                        appState.globePanel = nil
                    } else {
                        appState.globePanel = .notifications
                        Task { await appState.refreshNotifications() }
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Theme.ink)
                        if appState.effectiveNotificationsUnreadCount > 0 {
                            Circle()
                                .fill(Theme.danger)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -2)
                        }
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if store.phase == .ready {
                shellTabs
            }
        }
        .background(Theme.surface.opacity(0.92))
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }

    private var shellTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(AnonymousShellTab.allCases) { tab in
                    Button {
                        withAnimation(MatteryaMotion.snappy) { shellTab = tab }
                    } label: {
                        Text(tab.title)
                            .pillTab(isSelected: shellTab == tab)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var phaseBody: some View {
        switch store.phase {
        case .loading:
            AnonymousLoadingSkeleton()
        case .gatedUnder18:
            AnonymousAgeGateView(mode: .under18)
        case .needAttest:
            AnonymousAgeGateView(mode: .attest)
        case .needUsername:
            AnonymousUsernameClaimView()
        case .suspended:
            AnonymousEmptyState(
                title: MatteryaCopy.anonymousSuspendedTitle,
                message: MatteryaCopy.anonymousSuspendedBody,
                systemImage: "exclamationmark.shield"
            )
        case .offline:
            AnonymousEmptyState(
                title: MatteryaCopy.anonymousOfflineTitle,
                message: MatteryaCopy.anonymousOfflineBody,
                systemImage: "wifi.slash",
                actionTitle: "Try again"
            ) {
                Task { await store.refreshSession() }
            }
        case .ready:
            readyBody
        }
    }

    @ViewBuilder
    private var readyBody: some View {
        switch shellTab {
        case .spaces:
            AnonymousSpacesDirectoryView(onCreate: { showCreateSpace = true })
        case .feed:
            AnonymousFeedView()
        case .search:
            AnonymousSearchView()
        case .inbox:
            AnonymousInboxView()
        case .me:
            AnonymousMeView()
        }
    }
}

struct AnonymousLoadingSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.surface)
                        .frame(height: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .stroke(Theme.border.opacity(0.7), lineWidth: 0.5)
                        )
                        .redacted(reason: .placeholder)
                }
            }
            .padding(Theme.pagePadding)
        }
    }
}

struct AnonymousEmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "theatermasks"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.inkMuted)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .elegantButton()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 48)
                .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
