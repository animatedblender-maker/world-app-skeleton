import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var postToOpenAfterCreate: CountryPost?

    var body: some View {
        NavigationStack(path: Binding(
            get: { appState.navigationPath },
            set: { appState.navigationPath = $0 }
        )) {
            ZStack(alignment: .bottom) {
                Group {
                    switch appState.selectedTab {
                    case .feed:
                        FeedView()
                    case .globe:
                        GlobeView()
                    case .hubs:
                        MatteryaHubsView()
                    case .messages:
                        MessagesView()
                    case .profile:
                        ProfileView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(appState.selectedTab.rawValue)
                .safeAreaPadding(.bottom, Theme.tabBarHeight)

                BottomTabBar()
            }
            .sharePostSheet(appState: appState)
            .overlay {
                AppMenuOverlay()
                NotificationsOverlay()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(appState.navigationPath.isEmpty ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: AppDestination.self) { destination in
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
                }
            }
        }
        .ignoresSafeArea(.keyboard)
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
            if let country = appState.composerCountry {
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
                    ReelComposerView(country: country, publishAsReel: false) { post in
                        NotificationCenter.default.post(
                            name: .userPostsDidChange,
                            object: nil,
                            userInfo: ["post": post]
                        )
                        appState.reloadContent()
                        postToOpenAfterCreate = post
                    }
                case .reel:
                    ReelComposerView(country: country) { post in
                        NotificationCenter.default.post(
                            name: .userPostsDidChange,
                            object: nil,
                            userInfo: ["post": post]
                        )
                        appState.reloadContent()
                        postToOpenAfterCreate = post
                    }
                case .story:
                    StoryComposerView(country: country) { post in
                        NotificationCenter.default.post(
                            name: .userPostsDidChange,
                            object: nil,
                            userInfo: ["post": post]
                        )
                        appState.reloadContent()
                        Task { await appState.refreshStories() }
                    }
                }
            }
            }
            .withAppState(appState)
        }
        .fullScreenCover(item: Binding(
            get: { appState.storyViewerContext },
            set: { appState.storyViewerContext = $0 }
        )) { context in
            StoriesViewerView(context: context)
                .withAppState(appState)
        }
        .fullScreenCover(item: Binding(
            get: { appState.reelsViewerContext },
            set: { appState.reelsViewerContext = $0 }
        )) { context in
            ReelsScrollViewer(context: context)
                .withAppState(appState)
        }
        .fullScreenCover(isPresented: Binding(
            get: { appState.isPlayPresented },
            set: { presented in
                if !presented {
                    appState.dismissPlay()
                } else {
                    appState.isPlayPresented = true
                }
            }
        )) {
            LivingView(hostsShareSheet: true)
                .withAppState(appState)
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