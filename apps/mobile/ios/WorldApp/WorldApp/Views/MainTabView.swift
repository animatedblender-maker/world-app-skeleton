import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var postToOpenAfterCreate: CountryPost?
    /// Chat mini video hole (global) — continuous hubs player docks here without remounting.
    @State private var hubContinuousDockSlotGlobal: CGRect?
    /// Expanded watch stage hole — continuous player locks to this so it never covers the title.
    @State private var hubWatchStageGlobal: CGRect?

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

            // Ink plate under the mini strip — if continuous video is mid-morph, never show
            // home paper (white placeholder) through the clear mini hole.
            if showsFloatingMiniBar {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Theme.ink
                        .frame(height: YouTubeMiniPlayerBar.barHeight)
                        .frame(maxWidth: .infinity)
                    if appState.navigationPath.isEmpty {
                        Color.clear.frame(height: Theme.tabBarHeight)
                    }
                }
                .allowsHitTesting(false)
                .zIndex(44)
            }

            // Continuous AVPlayer.
            // Expanded: above page content so the watch stage is visible.
            // Mini: *below* the mini-bar chrome (z70) so the **clear** hole reveals video;
            // Immersive FS: above tab bar, edge-to-edge black (notch + home indicator).
            GlobalHubPlaybackLayer(
                dockSlotGlobal: hubContinuousDockSlotGlobal,
                watchStageGlobal: hubWatchStageGlobal
            )
            // Mini must sit above feed paper (z45 was under opaque tab content on some paths → black hole).
            // Keep below mini chrome (70) so the clear video slot still reveals the continuous film.
            .zIndex(
                hubsImmersiveFullscreen
                    ? 200
                    : (appState.hubPlaybackExpanded ? 55 : 65)
            )
            .ignoresSafeArea(hubsImmersiveFullscreen ? .all : [])

            // One bottom stack: mini strip (if any) then tab bar — YouTube order, no overlap.
            // Hidden in immersive FS so white/paper never peeks under the black bed.
            if !hubsImmersiveFullscreen, showsFloatingMiniBar || appState.navigationPath.isEmpty {
                VStack(spacing: 0) {
                    if showsFloatingMiniBar, let post = appState.hubPlaybackPost {
                        YouTubeMiniPlayerBar(
                            post: post,
                            onExpand: {
                                // Expand immediately — no Task hop.
                                appState.expandHubPlayback()
                            },
                            onClose: { appState.stopHubPlayback() },
                            embedsVideo: false,
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
                    }
                    if appState.navigationPath.isEmpty {
                        BottomTabBar()
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .zIndex(70)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(hubsImmersiveFullscreen ? Color.black : Color.clear)
        .onPreferenceChange(HubContinuousVideoSlotKey.self) { frame in
            hubContinuousDockSlotGlobal = frame
        }
        .onPreferenceChange(HubWatchStageFrameKey.self) { frame in
            hubWatchStageGlobal = frame
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
        .onReceive(NotificationCenter.default.publisher(for: .userPostDidDelete)) { notification in
            guard let id = notification.userInfo?["postID"] as? String else { return }
            appState.applyPostDeleted(id: id)
        }
        .onChange(of: appState.selectedTab) { oldTab, tab in
            // Hard rule: leave a surface → no orphan audio from off-screen video.
            FeedVideoFocus.shared.resetAll()

            // Off Hubs while expanded → snap mini FIRST (no spring vs tab layout fight).
            // Animated morph + tab remount caused geometry hallucinations + audio drops.
            if tab != .hubs, appState.hubPlaybackExpanded {
                appState.minimizeHubPlayback(returnToChat: false, animated: false)
            }

            MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()

            // Continuous hubs mini must keep audio on EVERY tab (not only when entering Hubs).
            if appState.hubPlaybackPost != nil {
                appState.hubPlaybackPlaying = true
                MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                    userMuted: appState.hubPlaybackMuted
                )
                NotificationCenter.default.post(
                    name: .matteryaResumePlaybackAfterInterrupt,
                    object: nil
                )
            }

            if tab != .hubs {
                EngagementTracker.shared.hubsLeft()
            } else {
                EngagementTracker.shared.hubsOpened()
            }
            EngagementTracker.shared.screenOpened(tab.rawValue)
            // 3+ min off feed → new feed mix; Hubs open → new For you order.
            appState.noteSelectedTabChanged(from: oldTab, to: tab)
        }
        .onChange(of: appState.navigationPath.count) { _, count in
            // Opening chat (or any push) while expanded → snap mini, keep playing.
            // Instant (not spring) so nav push layout doesn't fight the morph.
            if count > 0, appState.hubPlaybackExpanded {
                appState.minimizeHubPlayback(returnToChat: false, animated: false)
                appState.hubPlaybackPlaying = true
                MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                    userMuted: appState.hubPlaybackMuted
                )
                NotificationCenter.default.post(
                    name: .matteryaResumePlaybackAfterInterrupt,
                    object: nil
                )
            }
            // Left the pinned chat while mini → never force-return there on next minimize.
            appState.syncHubPlaybackChatReturnWithPath()
            // Push/pop (e.g. public profile over feed) — re-elect autoplay on the live surface.
            FeedVideoFocus.shared.resetAll()
            // Nav change can silence feed; re-assert continuous mini if still running.
            if count == 0, appState.hubPlaybackPost != nil, appState.hubPlaybackPlaying {
                MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                    userMuted: appState.hubPlaybackMuted
                )
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
        .fullScreenCover(item: Binding(
            get: { appState.reelsViewerContext },
            set: { newValue in
                if newValue == nil {
                    // Dismiss Sparks → silence audio hard, but **do not** tear down feed
                    // AVPlayerItems (that caused feed “audio only / black video” on return).
                    MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
                    SparkWarmPool.shared.silenceAllBuffered()
                    FeedVideoFocus.shared.resetAll()
                    // Restore mini Hubs if it was paused for Sparks.
                    if appState.hubPlaybackPost != nil {
                        appState.hubPlaybackPlaying = true
                        NotificationCenter.default.post(
                            name: .matteryaResumePlaybackAfterInterrupt,
                            object: nil
                        )
                    } else {
                        // Let feed re-elect a winner and re-attach video+audio together.
                        NotificationCenter.default.post(
                            name: .feedVideoFocusDidChange,
                            object: nil
                        )
                    }
                }
                appState.reelsViewerContext = newValue
            }
        )) { context in
            ReelsScrollViewer(context: context)
                .withAppState(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
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

    /// Continuous player is in immersive fullscreen (notch + bottom must be black).
    private var hubsImmersiveFullscreen: Bool {
        appState.hubPlaybackPost != nil && appState.hubFullscreenPullProgress > 0.85
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