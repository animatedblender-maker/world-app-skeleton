import SwiftUI

enum AnonymousShellTab: String, CaseIterable, Identifiable {
    case feed, spaces, search, inbox, notifications, me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: "Feed"
        case .spaces: "Spaces"
        case .search: "Search"
        case .inbox: "Inbox"
        case .notifications: "Notifications"
        case .me: "Me"
        }
    }

    /// Tabs shown in the shell chip row (bell / search / + live in the header).
    static var chipTabs: [AnonymousShellTab] { [.feed, .spaces, .inbox, .me] }
}

struct AnonymousRootView: View {
    @Environment(AppState.self) private var appState
    @State private var store = AnonymousStore.shared
    /// Feed is the primary Masquerade surface.
    @State private var shellTab: AnonymousShellTab = .feed
    @State private var showCreateSpace = false
    /// Matterya dropdown anchored under the header + button.
    @State private var showHeaderCreateMenu = false
    /// Bell dropdown — Masquerade notifications only (same pattern as main NotificationsOverlay).
    @State private var showNotificationsMenu = false
    /// Always-visible search field under brand/icons (not a chip, never replaces the header).
    @State private var searchQuery = ""
    @State private var tabBeforeSearch: AnonymousShellTab = .feed
    @FocusState private var searchFieldFocused: Bool

    /// True while a Space or thread is pushed — collapse Masquerade shell chrome only.
    private var isPushed: Bool { !store.navigationPath.isEmpty }

    private var masqueradeUnreadCount: Int {
        store.inbox.filter(\.isUnread).count
    }

    var body: some View {
        phaseBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .task {
                syncMasqueradeTabBar()
                await store.bootstrap()
            }
            .onChange(of: store.lastError) { _, _ in
                if let msg = store.consumeError(), store.shouldToastLastError {
                    appState.showToast(msg, style: .error)
                }
            }
            .onChange(of: store.navigationPath.count) { _, count in
                syncMasqueradeTabBar()
                if count == 0 {
                    showHeaderCreateMenu = false
                } else {
                    searchFieldFocused = false
                    showNotificationsMenu = false
                    showHeaderCreateMenu = false
                }
            }
            .onChange(of: appState.selectedTab) { _, tab in
                // Persistent shell: leaving Masquerade only clears the push stack + tab-bar flag.
                // Do not tear down session/feed — that remount freeze is gone.
                if tab != .anonymous {
                    store.resetNavigation()
                    appState.masqueradeHidesTabBar = false
                    appState.masqueradeChatChrome = false
                    showHeaderCreateMenu = false
                    showNotificationsMenu = false
                    searchFieldFocused = false
                } else {
                    syncMasqueradeTabBar()
                    // Re-entry only — first paint is owned by `.task` on mount.
                    if store.phase == .ready {
                        Task { await store.bootstrap() }
                    }
                }
            }
            .onChange(of: searchQuery) { _, query in
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if shellTab != .search {
                        tabBeforeSearch = shellTab == .search ? .feed : shellTab
                    }
                    if shellTab != .search {
                        withAnimation(MatteryaMotion.snappy) {
                            store.resetNavigation()
                            shellTab = .search
                        }
                    }
                }
            }
            .task(id: store.phase) {
                if store.phase == .ready {
                    await store.loadInbox()
                }
            }
            .onDisappear {
                // Only when the shell is truly torn down (logout / rare unmount).
                appState.masqueradeHidesTabBar = false
            }
            .sheet(isPresented: $showCreateSpace) {
                AnonymousCreateSpaceView()
                    .environment(appState)
            }
            .sheet(isPresented: Binding(
                get: { appState.showMasqueradeCreateSpace },
                set: { appState.showMasqueradeCreateSpace = $0 }
            )) {
                AnonymousCreateSpaceView()
                    .environment(appState)
            }
            .sheet(isPresented: Binding(
                get: { appState.showMasqueradeCreatePost },
                set: { appState.showMasqueradeCreatePost = $0 }
            )) {
                AnonymousPostSpacePickerView()
                    .environment(appState)
            }
            .onChange(of: appState.showMasqueradeCreateSpace) { _, open in
                if open {
                    showCreateSpace = false
                    showHeaderCreateMenu = false
                }
            }
            .onChange(of: appState.showMasqueradeCreatePost) { _, open in
                if open { showHeaderCreateMenu = false }
            }
            .overlay(alignment: .topTrailing) {
                if showHeaderCreateMenu, store.phase == .ready, !isPushed {
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    showHeaderCreateMenu = false
                                }
                            }

                        MasqueradeHeaderCreateMenu(
                            onCreateSpace: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    showHeaderCreateMenu = false
                                }
                                showCreateSpace = true
                            },
                            onCreatePost: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    showHeaderCreateMenu = false
                                }
                                appState.selectedTab = .anonymous
                                appState.showMasqueradeCreatePost = true
                            }
                        )
                        .padding(.top, 56)
                        .padding(.trailing, Theme.pagePadding)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                    }
                }
            }
            .overlay {
                if showNotificationsMenu, store.phase == .ready, !isPushed {
                    ZStack(alignment: .topTrailing) {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    showNotificationsMenu = false
                                }
                            }

                        MasqueradeNotificationsPanel(
                            onClose: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    showNotificationsMenu = false
                                }
                            },
                            onSelect: { item in
                                withAnimation(.easeOut(duration: 0.18)) {
                                    showNotificationsMenu = false
                                }
                                openMasqueradeNotification(item)
                            }
                        )
                        .padding(.trailing, Theme.pagePadding)
                        .padding(.top, 52)
                        .padding(.leading, Theme.pagePadding)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: showHeaderCreateMenu)
            .animation(.easeOut(duration: 0.18), value: showNotificationsMenu)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                MasqueradeBrandMark(compact: true, ringSize: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(-1)

                if store.phase == .ready {
                    Button {
                        showHeaderCreateMenu = false
                        withAnimation(.easeOut(duration: 0.18)) {
                            showNotificationsMenu.toggle()
                        }
                        if showNotificationsMenu {
                            Task { await store.loadInbox(force: true) }
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(showNotificationsMenu ? Theme.ink : Theme.inkMuted)
                            if masqueradeUnreadCount > 0 {
                                Circle()
                                    .fill(Theme.danger)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 4, y: -2)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Masquerade notifications")

                    Button {
                        showNotificationsMenu = false
                        withAnimation(.easeOut(duration: 0.18)) {
                            showHeaderCreateMenu.toggle()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MatteryaCopy.anonymousCreateMenuTitle)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 8)

            // Persistent search — under brand + icons, never replaces them.
            if store.phase == .ready {
                persistentSearchField
            }

            if store.showWildeEpigraph, store.phase == .needAttest || store.phase == .needUsername {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MatteryaCopy.anonymousWildeQuote)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.inkSecondary)
                        .italic()
                    Text(MatteryaCopy.anonymousWildeAttribution)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 10)
            }

            if store.phase == .ready {
                shellTabs
            }
        }
        .background(Theme.surface.opacity(0.92))
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }

    private var persistentSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
            TextField("Search people, spaces, posts", text: $searchQuery)
                .focused($searchFieldFocused)
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    showNotificationsMenu = false
                    showHeaderCreateMenu = false
                    let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !q.isEmpty {
                        // Record only on Return — never while typing.
                        SearchHistoryStore.record(q, surface: .masquerade)
                    }
                    activateSearchTab()
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchFieldFocused = false
                    if shellTab == .search {
                        withAnimation(MatteryaMotion.snappy) {
                            shellTab = tabBeforeSearch == .search ? .feed : tabBeforeSearch
                        }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 8)
        .onTapGesture {
            showNotificationsMenu = false
            showHeaderCreateMenu = false
        }
        .onChange(of: searchFieldFocused) { _, focused in
            if focused {
                showNotificationsMenu = false
                showHeaderCreateMenu = false
                activateSearchTab()
            }
        }
    }

    private func activateSearchTab() {
        if shellTab != .search {
            tabBeforeSearch = shellTab == .notifications ? .feed : shellTab
            withAnimation(MatteryaMotion.snappy) {
                store.resetNavigation()
                shellTab = .search
            }
        }
    }

    private func openMasqueradeNotification(_ item: AnonymousNotification) {
        if let postId = item.postId, !postId.isEmpty {
            store.pushPostId(postId)
            return
        }
        if let spaceId = item.spaceId, !spaceId.isEmpty {
            // Prefer slug from title/cache; fall back to directory open by id via spaces list.
            if let space = store.spacesByFilter.values.flatMap({ $0 }).first(where: { $0.id == spaceId }) {
                store.pushSpace(slug: space.slug)
            }
        }
    }

    private var shellTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(AnonymousShellTab.chipTabs) { tab in
                    Button {
                        searchFieldFocused = false
                        showNotificationsMenu = false
                        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Keep field visible; leave query alone if user is mid-search on Search tab.
                        }
                        withAnimation(MatteryaMotion.snappy) {
                            store.resetNavigation()
                            shellTab = tab
                        }
                    } label: {
                        Text(tab.title)
                            .pillTab(isSelected: shellTab == tab && !searchFieldFocused)
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
        case .welcomeLetter:
            AnonymousWelcomeLetterView()
        case .pickSpaces:
            AnonymousSpacesOnboardingView()
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
                systemImage: "theatermasks",
                actionTitle: "Try again"
            ) {
                Task { await store.refreshSession() }
            }
        case .ready:
            AnonymousReadyStack(
                shellTab: $shellTab,
                searchQuery: $searchQuery,
                onCreateSpace: { showCreateSpace = true },
                header: { header },
                syncMasqueradeTabBar: syncMasqueradeTabBar
            )
        }
    }

    /// Shell Feed/Spaces keep the tab bar; pushed Space/post hide it for composers.
    private func syncMasqueradeTabBar() {
        let hide = appState.selectedTab == .anonymous && !store.navigationPath.isEmpty
        appState.masqueradeHidesTabBar = hide
    }
}

/// Masquerade shell + pushed Space/post.
/// Uses an overlay with an explicit Back chrome — nested `NavigationStack` inside
/// MainTabView crashed on post tap, and system toolbars often stay hidden so users
/// get a dead end (no Back, tab bar already hidden).
private struct AnonymousReadyStack<Header: View>: View {
    @Environment(AppState.self) private var appState
    private var store: AnonymousStore { AnonymousStore.shared }
    @Binding var shellTab: AnonymousShellTab
    @Binding var searchQuery: String
    var onCreateSpace: () -> Void
    @ViewBuilder var header: () -> Header
    var syncMasqueradeTabBar: () -> Void

    var body: some View {
        let path = store.navigationPath
        ZStack {
            VStack(spacing: 0) {
                header()
                readyBody
            }
            .toolbar(.hidden, for: .navigationBar)
            .allowsHitTesting(path.isEmpty)

            if let route = path.last {
                VStack(spacing: 0) {
                    MasqueradePushChrome(
                        title: chromeTitle(for: route),
                        showsCallActions: {
                            if case .conversation = route { return true }
                            return false
                        }(),
                        conversationID: {
                            if case .conversation(let id) = route { return id }
                            return nil
                        }(),
                        peer: conversationPeer(for: route),
                        onBack: {
                            if case .conversation = route {
                                appState.masqueradeChatChrome = false
                            }
                            store.popNavigation()
                        }
                    )
                    Group {
                        switch route {
                        case .space(let slug):
                            AnonymousSpaceDetailView(slug: slug)
                        case .post(let id):
                            AnonymousPostRouteView(postId: id)
                        case .profile(let username):
                            AnonymousPublicProfileView(username: username)
                        case .conversation(let id):
                            // Embedded chat — system Messages tab stays out of the way.
                            ConversationRouteView(conversationID: id)
                                .toolbar(.hidden, for: .navigationBar)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(2)
                // Leading-edge swipe dismiss — overlay has no system interactive pop.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24, coordinateSpace: .local)
                        .onEnded { value in
                            guard value.startLocation.x < 28,
                                  value.translation.width > 80,
                                  abs(value.translation.height) < 80 else { return }
                            if case .conversation = route {
                                appState.masqueradeChatChrome = false
                            }
                            store.popNavigation()
                        }
                )
            }
        }
        .animation(.easeOut(duration: 0.2), value: path.count)
        .onChange(of: store.navigationPath) { _, _ in
            syncMasqueradeTabBar()
        }
    }

    private func chromeTitle(for route: AnonymousRoute) -> String {
        switch route {
        case .space(let slug):
            if let title = store.currentSpace?.title, store.currentSpace?.slug == slug, !title.isEmpty {
                return title
            }
            return slug
        case .post:
            return "Post"
        case .profile(let username):
            let handle = username
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            return handle.isEmpty ? "Profile" : "@\(handle)"
        case .conversation(let id):
            let me = AuthService.shared.currentUser?.id
            let conv = MessagesService.shared.cachedConversation(id: id)
            let other = me.flatMap { conv?.otherMember(currentUserID: $0) }
            let handle = (other?.username ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if handle.lowercased() == "matterya" {
                return other?.displayName ?? "Matterya"
            }
            if !handle.isEmpty { return "@\(handle)" }
            return other?.displayName ?? "Chat"
        }
    }

    private func conversationPeer(for route: AnonymousRoute) -> PostAuthor? {
        guard case .conversation(let id) = route else { return nil }
        let me = AuthService.shared.currentUser?.id
        let conv = MessagesService.shared.cachedConversation(id: id)
        return me.flatMap { conv?.otherMember(currentUserID: $0) }
    }

    @ViewBuilder
    private var readyBody: some View {
        switch shellTab {
        case .feed:
            AnonymousFeedView()
        case .spaces:
            AnonymousSpacesDirectoryView(onCreate: onCreateSpace)
        case .search:
            AnonymousSearchView(query: $searchQuery, showsSearchField: false)
        case .inbox:
            AnonymousMessagesInboxView()
        case .notifications:
            // Bell opens a dropdown now — keep Feed if this case is ever selected.
            AnonymousFeedView()
        case .me:
            AnonymousMeView()
        }
    }
}

/// Always-visible Back row for Masquerade Space/post/chat overlays (Matterya paper chrome).
private struct MasqueradePushChrome: View {
    let title: String
    var showsCallActions: Bool = false
    var conversationID: String? = nil
    var peer: PostAuthor? = nil
    var onBack: () -> Void

    @Bindable private var callManager = CallSessionManager.shared

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, showsCallActions ? 96 : 72)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Back")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, 10)
                    .padding(.trailing, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 0)

                if showsCallActions, let conversationID {
                    HStack(spacing: 14) {
                        Button {
                            Task {
                                await callManager.startCall(
                                    conversationID: conversationID,
                                    kind: .audio,
                                    peer: peer
                                )
                            }
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(callManager.canStartCall ? Theme.ink : Theme.inkMuted)
                        }
                        .disabled(!callManager.canStartCall)
                        .accessibilityLabel("Audio call")

                        Button {
                            Task {
                                await callManager.startCall(
                                    conversationID: conversationID,
                                    kind: .video,
                                    peer: peer
                                )
                            }
                        } label: {
                            Image(systemName: "video.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(callManager.canStartCall ? Theme.ink : Theme.inkMuted)
                        }
                        .disabled(!callManager.canStartCall)
                        .accessibilityLabel("Video call")
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 4)
        .background(Theme.surface.opacity(0.96))
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }
}

/// Resolves a Masquerade post for NavigationStack (id-only routes).
private struct AnonymousPostRouteView: View {
    let postId: String
    @State private var fetched: AnonymousPost?
    @State private var loadFailed = false

    /// Avoid a `private` stored property — that made the memberwise init inaccessible to the stack.
    private var store: AnonymousStore { AnonymousStore.shared }

    var body: some View {
        Group {
            if let post = fetched ?? store.post(forId: postId) {
                AnonymousPostDetailView(post: post)
            } else if loadFailed {
                AnonymousEmptyState(
                    title: "Post unavailable",
                    message: "This thread couldn’t be opened. Go back and try again.",
                    systemImage: "text.bubble",
                    actionTitle: "Back"
                ) {
                    store.popNavigation()
                }
            } else {
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: postId) {
            AnonymousCommentsWarmCache.shared.warm(postId)
            if let cached = store.post(forId: postId) {
                fetched = cached
                return
            }
            do {
                let remote = try await AnonymousService.getPost(id: postId)
                store.rememberPost(remote)
                fetched = store.post(forId: remote.id) ?? remote
            } catch {
                loadFailed = true
            }
        }
    }
}

/// Matterya paper dropdown anchored under the Masquerade header + button.
struct MasqueradeHeaderCreateMenu: View {
    var onCreateSpace: () -> Void
    var onCreatePost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(MatteryaCopy.anonymousCreateMenuTitle)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Theme.divider.frame(height: 0.5)

            menuRow(
                title: MatteryaCopy.anonymousCreateSpace,
                subtitle: "Start a community Space",
                action: onCreateSpace
            )
            menuRow(
                title: MatteryaCopy.anonymousCreatePost,
                subtitle: "Pick a Space and write",
                action: onCreatePost
            )
        }
        .frame(width: 236)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.12), radius: 14, y: 6)
    }

    private func menuRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
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
