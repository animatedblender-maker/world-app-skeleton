import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

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
                        LivingView()
                    case .reels:
                        ReelsTabView()
                    case .messages:
                        MessagesView()
                    case .profile:
                        ProfileView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(appState.selectedTab)
                .safeAreaPadding(.bottom, appState.selectedTab == .reels ? 0 : Theme.tabBarHeight)

                BottomTabBar()
            }
            .overlay {
                AppMenuOverlay()
                NotificationsOverlay()
                CreateMenuOverlay()
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
                    ReelsView(country: country)
                case .countryFeed(let country):
                    CountryFeedView(country: country).screenBackground()
                case .search:
                    SearchView().screenBackground()
                case .publicProfile(let username):
                    PublicProfileView(username: username).screenBackground()
                case .people:
                    PeopleView().screenBackground()
                case .ads:
                    AdsView().screenBackground()
                case .editProfile:
                    EditProfileView().screenBackground()
                case .settings:
                    SettingsView().screenBackground()
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .sheet(item: Binding(
            get: { appState.activeCreateSheet },
            set: { appState.activeCreateSheet = $0 }
        )) { sheet in
            if let country = appState.composerCountry {
                switch sheet {
                case .post:
                    PostComposerView(country: country) { post in
                        NotificationCenter.default.post(
                            name: .userPostsDidChange,
                            object: nil,
                            userInfo: ["post": post]
                        )
                        Task { await appState.refreshStories() }
                    }
                case .video:
                    ReelComposerView(country: country, publishAsReel: false) { post in
                        NotificationCenter.default.post(
                            name: .userPostsDidChange,
                            object: nil,
                            userInfo: ["post": post]
                        )
                        appState.openLivingVideo(postID: post.id)
                    }
                case .reel:
                    ReelComposerView(country: country) { post in
                        NotificationCenter.default.post(
                            name: .userPostsDidChange,
                            object: nil,
                            userInfo: ["post": post]
                        )
                        appState.selectedTab = .reels
                    }
                case .story:
                    StoryComposerView(country: country) { post in
                        NotificationCenter.default.post(
                            name: .userPostsDidChange,
                            object: nil,
                            userInfo: ["post": post]
                        )
                        Task { await appState.refreshStories() }
                    }
                }
            }
        }
        .fullScreenCover(item: Binding(
            get: { appState.storyViewerContext },
            set: { appState.storyViewerContext = $0 }
        )) { context in
            StoriesViewerView(context: context)
        }
    }
}