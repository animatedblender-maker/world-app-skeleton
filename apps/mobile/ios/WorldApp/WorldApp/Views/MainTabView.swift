import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var postToOpenAfterCreate: CountryPost?
    /// Chat mini video hole (global) — continuous hubs player docks here without remounting.
    @State private var hubContinuousDockSlotGlobal: CGRect?
    /// Hubs catalog kept mounted briefly after leave so teardown doesn't hitch the mini morph.
    @State private var hubsShellMounted = false
    @State private var hubsDismountTask: Task<Void, Never>?
    /// Masquerade stays mounted after first visit — remount + bootstrap on every hop froze the UI.
    @State private var anonymousShellMounted = false
    /// Messages stays mounted after first visit — remount re-waited GraphQL every hop.
    @State private var messagesShellMounted = false

    var body: some View {
        // Mini player lives OUTSIDE NavigationStack so chat / search / profile pushes
        // cannot cover continuous Hubs playback.
        ZStack(alignment: .bottom) {
            NavigationStack(path: Binding(
                get: { appState.navigationPath },
                set: { appState.navigationPath = $0 }
            )) {
                ZStack(alignment: .bottom) {
                    // Feed always mounted. Hubs catalog: mount on Hubs tab; **defer dismount**
                    // after leave so catalog dealloc doesn't hitch the mini (IG/YouTube pattern:
                    // player stays, heavy UI tears down on the next beat).
                    persistentTab(.feed) { FeedView() }
                    if hubsShellMounted || appState.selectedTab == .hubs {
                        persistentTab(.hubs) { MatteryaHubsView() }
                    }
                    if anonymousShellMounted || appState.selectedTab == .anonymous {
                        persistentTab(.anonymous) { AnonymousRootView() }
                    }
                    if messagesShellMounted || appState.selectedTab == .messages {
                        persistentTab(.messages) { MessagesView() }
                    }

                    // Profile remounts (lighter than keeping it live off-screen).
                    if appState.selectedTab == .profile {
                        ProfileView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .safeAreaPadding(.bottom, tabContentBottomInset)
                            .zIndex(1)
                            .id(AppTab.profile.rawValue)
                    }

                    // Tab bar is drawn in the OUTER ZStack (below) so the mini player
                    // can sit above it without covering the menu icons.
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sharePostSheet(appState: appState)
                .overlay {
                    ZStack {
                        AppMenuOverlay()
                        NotificationsOverlay()
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(appState.navigationPath.isEmpty ? .hidden : .visible, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(destination)
                        // Explicit size so pushed screens (public profiles, chat) fill the
                        // window on My Mac (Designed for iPad) — root ZStack tabs underneath
                        // otherwise steal layout and cards can measure as zero height.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Leave room for the floating mini player above the home indicator.
                        .safeAreaPadding(.bottom, miniPlayerContentInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Mini video hole only (flush above tab bar). Chrome sits ABOVE the film.
            if showsFloatingMiniBar || appState.navigationPath.isEmpty {
                VStack(spacing: 0) {
                    if showsFloatingMiniBar, let post = appState.hubPlaybackPost {
                        YouTubeMiniPlayerBar(
                            post: post,
                            onExpand: { appState.expandHubPlayback() },
                            onClose: { appState.stopHubPlayback() },
                            embedsVideo: false,
                            showsChrome: false,
                            isPlaying: Binding(
                                get: { appState.hubPlaybackPlaying },
                                set: { appState.hubPlaybackPlaying = $0 }
                            ),
                            isMuted: Binding(
                                get: { appState.hubPlaybackMuted },
                                set: { appState.hubPlaybackMuted = $0 }
                            )
                        )
                        .frame(height: YouTubeMiniPlayerBar.barHeight)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)
                    }
                    // Spacer matching tab bar height so mini stays flush above it when tab is shown.
                    // Skip while Masquerade hides the tab bar (Space/post) — otherwise a dead gap
                    // sits under the thread comment composer.
                    if appState.navigationPath.isEmpty, !appState.masqueradeHidesTabBar {
                        Color.clear
                            .frame(height: Theme.tabBarHeight)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)
                .zIndex(50)
            }

            // Continuous AVPlayer + mini chrome overlay (chips live on the film layer).
            // Landscape FS: above tab bar so film owns the whole window (YouTube).
            GlobalHubPlaybackLayer(dockSlotGlobal: hubContinuousDockSlotGlobal)
                .zIndex(appState.hubPlaybackLandscapeFullscreen ? 280 : 55)

            // Tab bar pinned to the physical bottom of the ZStack.
            // Hide while the in-app share sheet is open — otherwise the custom tab
            // paints over the sheet and covers the last rows (e.g. Copy link).
            // Masquerade hides this on Space/post pushes so thread composers are not covered
            // (Back is explicit on those screens; shell Feed keeps the bar).
            if appState.navigationPath.isEmpty,
               !appState.masqueradeHidesTabBar,
               !appState.hubPlaybackLandscapeFullscreen,
               appState.sharePostSheet == nil {
                BottomTabBar()
                    .frame(maxWidth: .infinity)
                    .zIndex(70)
            }

            // Sparks: instant overlay (not fullScreenCover) — same frame as hubs expand.
            if let context = appState.reelsViewerContext {
                ReelsScrollViewer(context: context)
                    .withAppState(appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all)
                    .statusBarHidden(false)
                    // Dark scheme → light/off-white notch clock + battery on black film.
                    .preferredColorScheme(.dark)
                    .persistentSystemOverlays(.hidden)
                    .background(Color.black.ignoresSafeArea(.all))
                    .transition(.identity)
                    .zIndex(300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appState.reelsViewerContext?.id) { _, _ in
            syncStatusBarLightContent()
        }
        .onChange(of: appState.showAppMenu) { _, _ in
            syncStatusBarLightContent()
        }
        .onChange(of: appState.hubPlaybackLandscapeFullscreen) { _, _ in
            syncStatusBarLightContent()
        }
        .onPreferenceChange(HubContinuousVideoSlotKey.self) { frame in
            hubContinuousDockSlotGlobal = frame
        }
        // Keyboard dismiss is window-level (cancelsTouchesInView = false).
        // Root dismissKeyboardOnTap() blocked Settings List taps.
        .onAppear {
            syncStatusBarLightContent()
            Keyboard.installDismissOnOutsideTap()
            appState.ensureHubPlaybackMinimizedIfNeeded()
            EngagementTracker.shared.screenOpened(appState.selectedTab.rawValue)
            if appState.selectedTab == .hubs {
                hubsShellMounted = true
                EngagementTracker.shared.hubsOpened()
            }
            if appState.selectedTab == .messages {
                messagesShellMounted = true
            }
            // Pre-mount Hubs shell after Feed settles — first tap is opacity-only, not a remount.
            // YouTubeAppView .task/.onAppear no-op until selectedTab == .hubs (no thumb storm).
            if !hubsShellMounted {
                Task(priority: .utility) { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    guard !hubsShellMounted else { return }
                    hubsShellMounted = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .masqueradeUnreadDidChange)) { note in
            let count = (note.userInfo?["count"] as? Int) ?? 0
            appState.applyMasqueradeUnreadCount(count)
        }
        .onChange(of: appState.selectedTab) { oldTab, tab in
            if tab == .hubs {
                hubsDismountTask?.cancel()
                hubsDismountTask = nil
                hubsShellMounted = true
            } else if oldTab == .hubs {
                // YouTube-style: smooth morph to mini on leave.
                if appState.hubPlaybackPost != nil,
                   appState.hubPlaybackExpanded || appState.hubPlaybackLandscapeFullscreen {
                    appState.minimizeHubPlayback(returnToChat: false, animated: true)
                }
                // Keep Hubs mounted like Masquerade — remounting the catalog on every
                // tab hop froze both leave and return (gesture gate + reshuffle).
                hubsDismountTask?.cancel()
                hubsDismountTask = nil
            }
            if tab == .anonymous {
                anonymousShellMounted = true
            }
            if tab == .messages {
                messagesShellMounted = true
            }
            // Clear election now; silence feed/Sparks on the next beat so the tab morph
            // stays light. Continuous Hubs mini is spared. (clearElectionOnly alone left
            // feed audio playing under other tabs / Search.)
            FeedVideoFocus.shared.clearElectionOnly()
            // Closed or still-open Sparks must not keep talking under Masquerade / other tabs.
            if tab != .feed, appState.reelsViewerContext != nil {
                appState.closeReelsViewer()
            }
            let leftFeed = oldTab == .feed && tab != .feed
            let leftHubs = oldTab == .hubs
            let openedHubs = tab == .hubs
            let openedMasquerade = tab == .anonymous
            if leftFeed || tab != .feed || openedMasquerade {
                MediaPlaybackCoordinator.shared.silenceFeedSparksAudioPreservingHubsMini()
            }
            Task(priority: .utility) { @MainActor in
                if leftFeed || tab != .feed || openedMasquerade {
                    // Second pass after close/cover teardown — catch late warm-pool claims.
                    MediaPlaybackCoordinator.shared.silenceFeedSparksAudioPreservingHubsMini()
                }
                if leftHubs { EngagementTracker.shared.hubsLeft() }
                if openedHubs { EngagementTracker.shared.hubsOpened() }
                EngagementTracker.shared.screenOpened(tab.rawValue)
                appState.noteSelectedTabChanged(from: oldTab, to: tab)
            }
        }
        .onDisappear {
            hubsDismountTask?.cancel()
            hubsDismountTask = nil
        }
        .onChange(of: appState.navigationPath.count) { _, count in
            // Opening chat (or any push) while expanded → collapse to mini, keep playing.
            // returnToChat: false — path already has the destination (including chat).
            if count > 0, appState.hubPlaybackExpanded || appState.hubPlaybackLandscapeFullscreen {
                appState.minimizeHubPlayback(returnToChat: false)
            }
            // Left the pinned chat while mini → never force-return there on next minimize.
            appState.syncHubPlaybackChatReturnWithPath()
            // Push (Search / post / profile): kill feed/Sparks audio. Hubs mini stays.
            // Pop back to root: election clears; feed cards re-report when live.
            FeedVideoFocus.shared.clearElectionOnly()
            if count > 0 {
                MediaPlaybackCoordinator.shared.silenceFeedSparksAudioPreservingHubsMini()
            }
        }
        .onChange(of: appState.navigationPath) { _, _ in
            appState.syncHubPlaybackChatReturnWithPath()
        }
        .onChange(of: appState.activeCreateSheet) { _, sheet in
            if sheet != nil {
                postToOpenAfterCreate = nil
            }
        }
        .sheet(item: Binding(
            get: { appState.activeCreateSheet },
            set: { appState.activeCreateSheet = $0 }
        ), onDismiss: {
            guard let post = postToOpenAfterCreate else { return }
            postToOpenAfterCreate = nil
            appState.openPost(post)
        }) { sheet in
            Group {
            if sheet == .channelSetup {
                ChannelSetupView {
                    // After first channel create → hubs video or spark composer.
                    Task { await appState.completeChannelSetupAndContinue() }
                }
            } else if let country = appState.composerCountry {
                switch sheet {
                case .post:
                    PostComposerView(country: country) { post in
                        NotificationCenter.default.post(
                            name: .userPostsDidChange,
                            object: nil,
                            userInfo: ["post": post]
                        )
                        appState.reloadContent()
                        Task { await appState.refreshStories() }
                    }
                case .video:
                    // Feed video: composer dismisses early; shadow card + feed top handled inside.
                    ReelComposerView(country: country, publishAsReel: false, publishToHubChannel: false) { _ in
                        appState.goToFeedTop(scroll: true)
                    }
                case .hubVideo:
                    // Hubs long-form also lands on feed with shadow card (channel video as post).
                    ReelComposerView(country: country, publishAsReel: false, publishToHubChannel: true) { _ in
                        appState.goToFeedTop(scroll: true)
                    }
                case .channelSetup:
                    EmptyView()
                case .reel:
                    // Sparks from + menu are always Hubs-bound (channel already gated).
                    ReelComposerView(country: country, publishAsReel: true, publishToHubChannel: true) { post in
                        NotificationCenter.default.post(
                            name: .userPostsDidChange,
                            object: nil,
                            userInfo: ["post": post]
                        )
                        appState.reloadContent()
                        postToOpenAfterCreate = post
                    }
                case .story:
                    // Moments removed from product — keep sheet case for legacy data only.
                    EmptyView()
                }
            }
            }
            .withAppState(appState)
        }
        .fullScreenCover(item: Binding(
            get: { appState.storyViewerContext },
            set: { appState.storyViewerContext = $0 }
        )) { context in
            // Moments viewer kept for legacy data but not linked from feed.
            StoriesViewerView(context: context)
                .withAppState(appState)
        }
        // Hubs is a real tab — never present it as a fullScreenCover (that hid the tab bar).
        .onChange(of: appState.isPlayPresented) { _, presented in
            if presented {
                appState.isPlayPresented = false
                appState.openPlay(tab: .home)
            }
        }
    }

    /// Floating mini above the tab bar (not docked into chat).
    /// Mount only after the session is actually mini. Mounting at pull ≥ 0.5
    /// (old path) reflowed tab safe-area + PreferenceKey dock mid-morph while the
    /// film was still on the top-half watch stage — that was the fixed-place lag.
    private var showsFloatingMiniBar: Bool {
        guard appState.hubPlaybackPost != nil, !appState.hubPlaybackDockInChat else { return false }
        return !appState.hubPlaybackExpanded
    }

    private var tabContentBottomInset: CGFloat {
        // Tab bar + mini strip flush on top of it (no gap).
        // Masquerade Space/post hide the tab bar — drop that reservation so the comment
        // composer sits flush (no empty band under "Add a comment").
        let tab = appState.masqueradeHidesTabBar ? 0 : Theme.tabBarHeight
        return tab + (showsFloatingMiniBar ? YouTubeMiniPlayerBar.barHeight : 0)
    }

    /// Extra bottom space on pushed screens. Chat docks mini under its own composer — no float inset.
    private var miniPlayerContentInset: CGFloat {
        guard showsFloatingMiniBar else { return 0 }
        // No tab bar on pushed routes — mini sits at the bottom of the stack.
        return YouTubeMiniPlayerBar.barHeight
    }

    /// White notch clock / battery over dark overlays (side menu scrim, Sparks film).
    private func syncStatusBarLightContent() {
        MatteryaStatusBar.setLightContent(
            appState.showAppMenu
                || appState.reelsViewerContext != nil
                || appState.hubPlaybackLandscapeFullscreen
        )
    }

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .post(let id):
            PostDetailView(postID: id).screenBackground()
        case .news(let id):
            NewsDetailView(newsID: id).screenBackground()
        case .reels(let country):
            NavigationRedirectView {
                appState.openCountryReels(country)
            }
        case .countryFeed(let country):
            CountryFeedView(country: country).screenBackground()
        case .search:
            SearchView().screenBackground()
        case .publicProfile(let username):
            PublicProfileView(username: username).screenBackground()
        case .publicProfileByUserID(let userID):
            PublicProfileView(userID: userID).screenBackground()
        case .conversation(let id):
            ConversationRouteView(conversationID: id)
        case .people:
            PeopleView().screenBackground()
        case .ads:
            AdsView().screenBackground()
        case .editProfile:
            EditProfileView().screenBackground()
        case .settings:
            SettingsView().screenBackground()
        case .premium:
            SettingsView().screenBackground()
        case .playWatch(let id):
            NavigationRedirectView {
                Task { await appState.openPlayVideo(id: id) }
            }
        case .playChannel(let username):
            NavigationRedirectView {
                appState.openPlayChannel(username: username)
            }
        case .playChannelID(let authorID):
            NavigationRedirectView {
                appState.openPlayChannel(authorID: authorID)
            }
        case .letters:
            LettersHomeView().screenBackground()
        case .letterThread(let id):
            LetterThreadView(threadID: id).screenBackground()
        }
    }

    @ViewBuilder
    private func persistentTab<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let selected = appState.selectedTab == tab
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.bottom, tabContentBottomInset)
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
            .zIndex(selected ? 1 : 0)
            // Frozen off-tab trees skip layout/animation work while Feed+Hubs stay mounted
            // for continuous mini playback.
            .transaction { txn in
                if !selected { txn.disablesAnimations = true }
            }
    }
}

/// Pops itself after running a redirect action so ghost destinations never linger on the stack.
private struct NavigationRedirectView: View {
    @Environment(AppState.self) private var appState
    let action: () -> Void

    var body: some View {
        Color.clear
            .onAppear {
                action()
                if !appState.navigationPath.isEmpty {
                    appState.navigationPath.removeLast()
                }
            }
    }
}