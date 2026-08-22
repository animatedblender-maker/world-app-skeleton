import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var postToOpenAfterCreate: CountryPost?
    /// Chat mini video hole (global) — continuous hubs player docks here without remounting.
    @State private var hubContinuousDockSlotGlobal: CGRect?

    var body: some View {
        // Mini player lives OUTSIDE NavigationStack so chat / search / profile pushes
        // cannot cover continuous Hubs playback.
        ZStack(alignment: .bottom) {
            NavigationStack(path: Binding(
                get: { appState.navigationPath },
                set: { appState.navigationPath = $0 }
            )) {
                ZStack(alignment: .bottom) {
                    // Feed + Hubs stay mounted so strips / continuous watch survive tab switches.
                    persistentTab(.feed) { FeedView() }
                    persistentTab(.hubs) { MatteryaHubsView() }

                    // Other tabs remount (lighter than keeping globe live off-screen).
                    if appState.selectedTab != .feed && appState.selectedTab != .hubs {
                        Group {
                            switch appState.selectedTab {
                            case .globe:
                                GlobeView()
                            case .messages:
                                MessagesView()
                            case .profile:
                                ProfileView()
                            default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaPadding(.bottom, tabContentBottomInset)
                        .zIndex(1)
                        .id(appState.selectedTab.rawValue)
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
                    if appState.navigationPath.isEmpty {
                        Color.clear
                            .frame(height: Theme.tabBarHeight)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)
                .zIndex(50)
            }

            // Continuous AVPlayer + mini chrome overlay (chips live on the film layer).
            GlobalHubPlaybackLayer(dockSlotGlobal: hubContinuousDockSlotGlobal)
                .zIndex(55)

            // Tab bar pinned to the physical bottom of the ZStack.
            if appState.navigationPath.isEmpty {
                BottomTabBar()
                    .frame(maxWidth: .infinity)
                    .zIndex(70)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(HubContinuousVideoSlotKey.self) { frame in
            hubContinuousDockSlotGlobal = frame
        }
        // Keyboard dismiss is window-level (cancelsTouchesInView = false).
        // Root dismissKeyboardOnTap() blocked Settings List taps.
        .onAppear {
            Keyboard.installDismissOnOutsideTap()
            appState.ensureHubPlaybackMinimizedIfNeeded()
            EngagementTracker.shared.screenOpened(appState.selectedTab.rawValue)
            if appState.selectedTab == .hubs {
                EngagementTracker.shared.hubsOpened()
            }
        }
        .onChange(of: appState.selectedTab) { oldTab, tab in
            // Off Hubs → mini player; do not force-return to a chat (only pull-down / minimize does).
            if tab != .hubs {
                appState.minimizeHubPlayback(returnToChat: false)
                EngagementTracker.shared.hubsLeft()
            } else {
                EngagementTracker.shared.hubsOpened()
            }
            EngagementTracker.shared.screenOpened(tab.rawValue)
            // Feed stays mounted under Profile — clear focus so profile can elect its own winner.
            FeedVideoFocus.shared.resetAll()
            // 3+ min off feed → new feed mix; Hubs open → new For you order.
            appState.noteSelectedTabChanged(from: oldTab, to: tab)
        }
        .onChange(of: appState.navigationPath.count) { _, count in
            // Opening chat (or any push) while expanded → collapse to mini, keep playing.
            // returnToChat: false — path already has the destination (including chat).
            if count > 0, appState.hubPlaybackExpanded {
                appState.minimizeHubPlayback(returnToChat: false)
            }
            // Left the pinned chat while mini → never force-return there on next minimize.
            appState.syncHubPlaybackChatReturnWithPath()
            // Push/pop (e.g. public profile over feed) — re-elect autoplay on the live surface.
            FeedVideoFocus.shared.resetAll()
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
        .fullScreenCover(item: Binding(
            get: { appState.reelsViewerContext },
            set: { newValue in
                if newValue == nil {
                    // Dismiss Sparks → kill Spark players only; keep hubs mini AVPlayer + item.
                    let keep = MediaPlaybackCoordinator.shared.continuousHubPlayer
                    MediaPlaybackCoordinator.shared.stopAllPlayback(except: keep)
                    SparkWarmPool.shared.silenceAllBuffered()
                    appState.resumeHubPlaybackAfterSparks()
                }
                appState.reelsViewerContext = newValue
            }
        )) { context in
            ReelsScrollViewer(context: context)
                .withAppState(appState)
                // Edge-to-edge film; status bar stays visible (time / battery / Wi‑Fi).
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .statusBarHidden(false)
                .preferredColorScheme(.dark) // light status-bar glyphs on black film
                .persistentSystemOverlays(.hidden) // home indicator may auto-hide; clock stays
                .presentationBackground(.black)
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
    private var showsFloatingMiniBar: Bool {
        appState.hubPlaybackPost != nil
            && !appState.hubPlaybackExpanded
            && !appState.hubPlaybackDockInChat
    }

    private var tabContentBottomInset: CGFloat {
        // Tab bar + mini strip flush on top of it (no gap).
        Theme.tabBarHeight + (showsFloatingMiniBar ? YouTubeMiniPlayerBar.barHeight : 0)
    }

    /// Extra bottom space on pushed screens. Chat docks mini under its own composer — no float inset.
    private var miniPlayerContentInset: CGFloat {
        guard showsFloatingMiniBar else { return 0 }
        // No tab bar on pushed routes — mini sits at the bottom of the stack.
        return YouTubeMiniPlayerBar.barHeight
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