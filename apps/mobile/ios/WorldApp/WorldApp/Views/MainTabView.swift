import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var postToOpenAfterCreate: CountryPost?
    /// Chat mini video hole (global) — continuous hubs player docks here without remounting.
    @State private var hubContinuousDockSlotGlobal: CGRect?
    /// Expanded watch stage hole — continuous player locks to this so it never covers the title.
    @State private var hubWatchStageGlobal: CGRect?

    var body: some View {
        rootShell
            .modifier(MainTabLifecycleModifier(
                appState: appState,
                hubContinuousDockSlotGlobal: $hubContinuousDockSlotGlobal,
                hubWatchStageGlobal: $hubWatchStageGlobal,
                postToOpenAfterCreate: $postToOpenAfterCreate,
                hubsImmersiveFullscreen: hubsImmersiveFullscreen
            ))
    }

    /// Mini player lives OUTSIDE NavigationStack so chat / search / profile pushes
    /// cannot cover continuous Hubs playback.
    private var rootShell: some View {
        ZStack(alignment: .bottom) {
            mainNavigationStack
            miniInkPlateUnderlay
            // Order: plate → tab/mini hole → continuous film (110) → mini chrome (120).
            // Chrome must stay ABOVE the UIKit film and never rehost with morph.
            floatingMiniAndTabChrome
            continuousHubsPlayerLayer
            floatingMiniChromeAboveFilm
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(hubsImmersiveFullscreen ? Color.black : Color.clear)
    }

    private var mainNavigationStack: some View {
        NavigationStack(path: Binding(
            get: { appState.navigationPath },
            set: { appState.navigationPath = $0 }
        )) {
            ZStack(alignment: .bottom) {
                // Keep heavy tabs mounted — remounting Messages/Profile re-ran GraphQL +
                // rebuilt lists every hop (multi-hundred-ms lag). Globe still lazy (heavy 3D).
                persistentTab(.feed) { FeedView() }
                persistentTab(.hubs) { MatteryaHubsView() }
                persistentTab(.messages) { MessagesView() }
                persistentTab(.profile) { ProfileView() }

                if appState.selectedTab == .globe {
                    GlobeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaPadding(.bottom, tabContentBottomInset)
                        .zIndex(1)
                }
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaPadding(.bottom, miniPlayerContentInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Continuous player is in immersive fullscreen (notch + bottom must be black).
    /// Requires expanded watch — never hide mini chrome because a stale FS pull flag stuck.
    private var hubsImmersiveFullscreen: Bool {
        appState.hubPlaybackPost != nil
            && appState.hubPlaybackExpanded
            && appState.hubFullscreenPullProgress > 0.85
    }

    /// Floating mini above the tab bar (not docked into chat).
    private var showsFloatingMiniBar: Bool {
        appState.hubPlaybackPost != nil
            && !appState.hubPlaybackExpanded
            && !appState.hubPlaybackDockInChat
    }

    /// Mini: above bar plate (100) so film covers the hole.
    /// Expanded: above tab bar (100) so timeline isn’t buried under BottomTabBar overlay;
    /// still below mini chrome slot (120). FS: 200.
    private var continuousPlayerZIndex: Double {
        if hubsImmersiveFullscreen { return 200 }
        if appState.hubPlaybackExpanded { return 105 }
        return 115
    }

    /// Soft plate under the mini strip so paper never flashes through a clear hole.
    /// Must stay *below* continuous film. Includes home-indicator gap so plate aligns with film.
    @ViewBuilder
    private var miniInkPlateUnderlay: some View {
        if showsFloatingMiniBar {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Theme.ink
                    .frame(height: YouTubeMiniPlayerBar.barHeight)
                    .frame(maxWidth: .infinity)
                // Match BottomTabBar: content height + safe-area bed (home indicator).
                if appState.navigationPath.isEmpty {
                    Color.clear
                        .frame(height: Theme.tabBarHeight)
                        .padding(.bottom, 0)
                }
            }
            .safeAreaPadding(.bottom, 0)
            .allowsHitTesting(false)
            .zIndex(44)
        }
    }

    /// Single continuous AVPlayer — pass-through only claims the film rect.
    /// z 60: above ink (44), below mini chrome (100) so film shows through the clear hole.
    private var continuousHubsPlayerLayer: some View {
        GlobalHubPlaybackLayer(
            dockSlotGlobal: hubContinuousDockSlotGlobal,
            watchStageGlobal: hubWatchStageGlobal
        )
        .zIndex(continuousPlayerZIndex)
        .ignoresSafeArea(.all)
        // When mini mounts, dock preference may be nil for a frame — keep layer alive.
        .opacity(1)
        .allowsHitTesting(appState.hubPlaybackPost != nil)
    }

    /// Mini strip flush **above** the tab bar (never under it). Continuous film docks here.
    @ViewBuilder
    private var floatingMiniAndTabChrome: some View {
        // When hubs watch is expanded, keep tab bar but never stack it over the film timeline.
        // (Continuous z=105 sits above this z=100.)
        if !hubsImmersiveFullscreen, showsFloatingMiniBar || appState.navigationPath.isEmpty {
            VStack(spacing: 0) {
                if showsFloatingMiniBar, let post = appState.hubPlaybackPost {
                    YouTubeMiniPlayerBar(
                        post: post,
                        onExpand: { appState.expandHubPlayback() },
                        onClose: { appState.stopHubPlayback() },
                        embedsVideo: false,
                        // Buttons drawn in floatingMiniChromeAboveFilm (z 120).
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
                }
                if appState.navigationPath.isEmpty {
                    BottomTabBar()
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(.keyboard)
            .zIndex(100)
            .allowsHitTesting(!appState.hubPlaybackExpanded || showsFloatingMiniBar)
        }
    }

    /// Close / mute / play — always above continuous UIKit film, never inside morph rehost.
    @ViewBuilder
    private var floatingMiniChromeAboveFilm: some View {
        if showsFloatingMiniBar, appState.hubPlaybackPost != nil, !hubsImmersiveFullscreen {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HubMiniPlayerChrome(
                    isPlaying: Binding(
                        get: { appState.hubPlaybackPlaying },
                        set: { want in
                            appState.hubPlaybackPlaying = want
                            NotificationCenter.default.post(
                                name: .matteryaHubContinuousSetPlaying,
                                object: nil,
                                userInfo: ["playing": want]
                            )
                        }
                    ),
                    isMuted: Binding(
                        get: { appState.hubPlaybackMuted },
                        set: { muted in
                            appState.hubPlaybackMuted = muted
                            NotificationCenter.default.post(
                                name: .matteryaHubContinuousSetMuted,
                                object: nil,
                                userInfo: ["muted": muted]
                            )
                        }
                    ),
                    onClose: { appState.stopHubPlayback() }
                )
                .frame(height: YouTubeMiniPlayerBar.barHeight)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { appState.expandHubPlayback() }

                if appState.navigationPath.isEmpty {
                    Color.clear
                        .frame(height: Theme.tabBarHeight)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .zIndex(120)
        }
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

    static func frameMeaningfullyChanged(_ old: CGRect?, _ new: CGRect?) -> Bool {
        switch (old, new) {
        case (nil, nil): return false
        case (nil, _), (_, nil): return true
        case let (a?, b?):
            // Larger epsilon — sub-pixel preference spam was thrashing continuous layout.
            return abs(a.minX - b.minX) > 4
                || abs(a.minY - b.minY) > 4
                || abs(a.width - b.width) > 4
                || abs(a.height - b.height) > 4
        }
    }
}

/// Lifecycle / sheets extracted so MainTabView.body type-checks quickly.
private struct MainTabLifecycleModifier: ViewModifier {
    @Bindable var appState: AppState
    @Binding var hubContinuousDockSlotGlobal: CGRect?
    @Binding var hubWatchStageGlobal: CGRect?
    @Binding var postToOpenAfterCreate: CountryPost?
    var hubsImmersiveFullscreen: Bool

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(HubContinuousVideoSlotKey.self) { frame in
                // Mini only — ignore nil mid-morph; never keep an expanded-stage-sized dock.
                guard !appState.hubPlaybackExpanded else { return }
                guard let frame, frame.width > 20, frame.height > 20 else { return }
                // Reject absurdly tall “dock” (stale stage leaked into mini).
                let maxMini = YouTubeMiniPlayerBar.barHeight + 24
                guard frame.height <= maxMini else { return }
                if MainTabView.frameMeaningfullyChanged(hubContinuousDockSlotGlobal, frame) {
                    hubContinuousDockSlotGlobal = frame
                }
            }
            .onPreferenceChange(HubWatchStageFrameKey.self) { frame in
                guard appState.hubPlaybackExpanded else { return }
                guard let frame, frame.width > 40, frame.height > 40 else { return }
                if MainTabView.frameMeaningfullyChanged(hubWatchStageGlobal, frame) {
                    hubWatchStageGlobal = frame
                }
            }
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
                handleSelectedTabChange(from: oldTab, to: tab)
            }
            .onChange(of: appState.navigationPath.count) { _, count in
                handleNavigationCountChange(count)
            }
            .onChange(of: appState.navigationPath) { _, _ in
                appState.syncHubPlaybackChatReturnWithPath()
            }
            .onChange(of: appState.activeCreateSheet) { _, sheet in
                if sheet != nil { postToOpenAfterCreate = nil }
            }
            .sheet(
                item: Binding(
                    get: { appState.activeCreateSheet },
                    set: { appState.activeCreateSheet = $0 }
                ),
                onDismiss: {
                    guard let post = postToOpenAfterCreate else { return }
                    postToOpenAfterCreate = nil
                    appState.openPost(post)
                },
                content: createSheetContent
            )
            .fullScreenCover(
                item: Binding(
                    get: { appState.storyViewerContext },
                    set: { appState.storyViewerContext = $0 }
                )
            ) { context in
                StoriesViewerView(context: context)
                    .withAppState(appState)
            }
            .fullScreenCover(
                item: Binding(
                    get: { appState.reelsViewerContext },
                    set: { newValue in
                        handleReelsContextChange(newValue)
                    }
                )
            ) { context in
                ReelsScrollViewer(context: context)
                    .withAppState(appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all)
                    .statusBarHidden(true)
                    .persistentSystemOverlays(.hidden)
                    .presentationBackground(.black)
            }
            .onChange(of: appState.isPlayPresented) { _, presented in
                if presented {
                    appState.isPlayPresented = false
                    appState.openPlay(tab: .home)
                }
            }
    }

    private func handleSelectedTabChange(from oldTab: AppTab, to tab: AppTab) {
        if tab != .hubs, appState.hubPlaybackExpanded {
            // Morph to mini — never animated:false (that snapped + silenced mid-frame).
            appState.minimizeHubPlayback(returnToChat: false, animated: true)
        }
        if appState.hubPlaybackPost == nil {
            FeedVideoFocus.shared.resetAll()
            MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
        } else {
            // Continuous hubs owns AV — skip resetAll/silence (froze expand/minimize).
            appState.hubPlaybackPlaying = true
            MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                userMuted: appState.hubPlaybackMuted
            )
        }
        if tab != .hubs {
            EngagementTracker.shared.hubsLeft()
        } else {
            EngagementTracker.shared.hubsOpened()
        }
        EngagementTracker.shared.screenOpened(tab.rawValue)
        appState.noteSelectedTabChanged(from: oldTab, to: tab)
    }

    private func handleNavigationCountChange(_ count: Int) {
        if count > 0, appState.hubPlaybackExpanded {
            appState.minimizeHubPlayback(returnToChat: false, animated: true)
            appState.hubPlaybackPlaying = true
            MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                userMuted: appState.hubPlaybackMuted
            )
        }
        appState.syncHubPlaybackChatReturnWithPath()
        if appState.hubPlaybackPost == nil {
            FeedVideoFocus.shared.resetAll()
        }
        if count == 0, appState.hubPlaybackPost != nil, appState.hubPlaybackPlaying {
            MediaPlaybackCoordinator.shared.reassertContinuousHubsAudio(
                userMuted: appState.hubPlaybackMuted
            )
        }
    }

    private func handleReelsContextChange(_ newValue: ReelsViewerContext?) {
        if newValue == nil {
            MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
            SparkWarmPool.shared.silenceAllBuffered()
            FeedVideoFocus.shared.resetAll()
            if appState.hubPlaybackPost != nil {
                appState.hubPlaybackPlaying = true
                NotificationCenter.default.post(
                    name: .matteryaResumePlaybackAfterInterrupt,
                    object: nil
                )
            } else {
                NotificationCenter.default.post(
                    name: .feedVideoFocusDidChange,
                    object: nil
                )
            }
        }
        appState.reelsViewerContext = newValue
    }

    @ViewBuilder
    private func createSheetContent(_ sheet: CreateContentSheet) -> some View {
        Group {
            if sheet == .channelSetup {
                ChannelSetupView {
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
                    ReelComposerView(country: country, publishAsReel: false, publishToHubChannel: false) { _ in
                        appState.goToFeedTop(scroll: true)
                    }
                case .hubVideo:
                    ReelComposerView(country: country, publishAsReel: false, publishToHubChannel: true) { _ in
                        appState.goToFeedTop(scroll: true)
                    }
                case .channelSetup:
                    EmptyView()
                case .reel:
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
                    EmptyView()
                }
            }
        }
        .withAppState(appState)
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