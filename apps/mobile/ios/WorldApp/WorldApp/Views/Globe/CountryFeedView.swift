import SwiftUI

struct CountryFeedView: View {
    @Environment(AppState.self) private var appState

    let country: Country

    @State private var posts: [CountryPost] = []
    @State private var followingPosts: [CountryPost] = []
    @State private var newsItems: [ExternalNewsItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var newsError: String?
    @State private var actionError: String?
    @State private var showComposer = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                tabBar
                content
            }
        }
        .navigationTitle(country.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    appState.navigate(to: .reels(country))
                } label: {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(Theme.accentBright)
                }
                Text(country.iso)
                    .font(.caption.weight(.black))
                    .tracking(1)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .sheet(isPresented: $showComposer) {
            PostComposerView(country: country) { post in
                posts.insert(post, at: 0)
            }
        }
        .task {
            await loadCurrentTab()
            openComposerIfRequested()
        }
        .onChange(of: appState.countryTab) { _, _ in
            Task { await loadCurrentTab() }
        }
        .onChange(of: appState.openComposerOnCountryFeed) { _, _ in
            openComposerIfRequested()
        }
        .onDisappear {
            if appState.selectedCountry?.id == country.id {
                appState.clearCountry()
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CountryTab.allCases) { tab in
                    Button(tab.title) {
                        appState.countryTab = tab
                    }
                    .pillTab(isSelected: appState.countryTab == tab)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
        }
        .background(Theme.canvas)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading \(country.name)…")
                .tint(Theme.accentBright)
                .frame(maxHeight: .infinity)
        } else if let loadError, appState.countryTab != .news {
            ContentUnavailableView("Unavailable", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else {
            switch appState.countryTab {
            case .posts: postsTab
            case .following: followingTab
            case .media: mediaTab
            case .stats: statsTab
            case .news: newsTab
            }
        }
    }

    private var postsTab: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                composerBar
                    .padding(.vertical, 4)
                ForEach(posts) { post in
                    postCard(post)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
        }
    }

    private var followingTab: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if followingPosts.isEmpty {
                    emptyState("Follow people to see their posts here.")
                }
                ForEach(followingPosts) { post in
                    followingPostCard(post)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
        }
    }

    private var mediaTab: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(posts.filter(\.hasMedia)) { post in
                    postCard(post)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
        }
    }

    private var statsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let stats = appState.countryStats {
                    statRow("Total users", "\(stats.totalUsers)")
                    statRow("Online now", "\(stats.onlineUsers)")
                }
                if let global = appState.globalStats {
                    statRow("Global users", "\(global.totalUsers)")
                    statRow("Global online", "\(global.onlineUsers)")
                }
            }
            .padding(Theme.pagePadding)
        }
    }

    private var newsTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let newsError, newsItems.isEmpty {
                    emptyState(newsError)
                } else if newsItems.isEmpty {
                    emptyState("No news updates for this country right now.")
                }
                ForEach(newsItems) { item in
                    Button {
                        appState.navigate(to: .news(item.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.sourceName ?? "News")
                                .sectionLabel()
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            if let snippet = item.snippet {
                                Text(snippet)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkMuted)
                                    .lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .premiumCard(inset: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.pagePadding)
        }
    }

    private var composerBar: some View {
        Group {
            if canPostHere {
                Button {
                    showComposer = true
                } label: {
                    HStack(spacing: 14) {
                        AvatarView(
                            url: appState.currentProfile?.avatarURL,
                            seed: appState.currentProfile?.userID ?? "me",
                            size: 40
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create a post")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Share something from \(country.name)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accentBright)
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
                    .shadow(color: Theme.ink.opacity(0.05), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await appState.navigateToHomeCountryFeed(openComposer: true) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title3)
                            .foregroundStyle(Theme.accentBright)
                            .frame(width: 40, height: 40)
                            .background(Theme.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Post from your country")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Go to \(homeCountryLabel) to share — you can only post in your home feed.")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accentBright)
                    }
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [Theme.surface, Theme.accentSoft.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .stroke(Theme.accent.opacity(0.25), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var homeCountryLabel: String {
        appState.currentProfile?.countryName ?? "your country"
    }

    private func openComposerIfRequested() {
        guard appState.openComposerOnCountryFeed, canPostHere else { return }
        showComposer = true
        appState.openComposerOnCountryFeed = false
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity)
            .premiumCard()
    }

    private var canPostHere: Bool {
        guard let code = appState.currentProfile?.countryCode?.uppercased() else { return false }
        return code == country.iso.uppercased()
    }

    private func postCard(_ post: CountryPost) -> some View {
        FacebookPostCard(
            post: post,
            showsAuthorHeader: false,
            showsAuthorInJournal: true,
            onLikeToggle: { Task { await toggleLike(post) } },
            onOpenPost: { appState.navigate(to: .post(post.id)) },
            onOpenVideo: post.hasVideo && !post.isReel
                ? { appState.openLivingVideo(postID: post.id) }
                : nil,
            onPostDeleted: { id in posts.removeAll { $0.id == id } },
            onPostUpdated: { updated in
                if let index = posts.firstIndex(where: { $0.id == updated.id }) {
                    posts[index] = updated
                }
            }
        )
    }

    private func followingPostCard(_ post: CountryPost) -> some View {
        FacebookPostCard(
            post: post,
            showsAuthorHeader: false,
            showsAuthorInJournal: true,
            onLikeToggle: { Task { await toggleFollowingLike(post) } },
            onOpenPost: { appState.navigate(to: .post(post.id)) },
            onOpenVideo: post.hasVideo && !post.isReel
                ? { appState.openLivingVideo(postID: post.id) }
                : nil,
            onPostDeleted: { id in followingPosts.removeAll { $0.id == id } },
            onPostUpdated: { updated in
                if let index = followingPosts.firstIndex(where: { $0.id == updated.id }) {
                    followingPosts[index] = updated
                }
            }
        )
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundStyle(Theme.ink)
        }
        .premiumCard(inset: 16)
    }

    private func loadCurrentTab() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        switch appState.countryTab {
        case .posts, .media:
            do {
                posts = try await PostsService.shared.listByCountry(country.iso, limit: 30)
            } catch {
                posts = []
                loadError = error.localizedDescription
            }
        case .following:
            followingPosts = await PostsService.shared.loadFollowingFeed()
        case .news:
            newsError = nil
            do {
                newsItems = try await NewsService.shared.countryConflictUpdates(country.iso, limit: 15)
            } catch {
                newsItems = []
                newsError = error.localizedDescription
            }
        case .stats:
            await appState.refreshCountryStats(for: country)
            await appState.refreshGlobalStats()
        }
    }

    private func toggleLike(_ post: CountryPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        do {
            if post.likedByMe {
                try await PostsService.shared.unlikePost(post.id)
                posts[index] = copyPost(post, likedByMe: false, likeCount: max(0, post.likeCount - 1))
            } else {
                try await PostsService.shared.likePost(post.id)
                posts[index] = copyPost(post, likedByMe: true, likeCount: post.likeCount + 1)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleFollowingLike(_ post: CountryPost) async {
        guard let index = followingPosts.firstIndex(where: { $0.id == post.id }) else { return }
        do {
            if post.likedByMe {
                try await PostsService.shared.unlikePost(post.id)
                followingPosts[index] = copyPost(post, likedByMe: false, likeCount: max(0, post.likeCount - 1))
            } else {
                try await PostsService.shared.likePost(post.id)
                followingPosts[index] = copyPost(post, likedByMe: true, likeCount: post.likeCount + 1)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func copyPost(_ post: CountryPost, likedByMe: Bool, likeCount: Int) -> CountryPost {
        CountryPost(
            id: post.id, title: post.title, body: post.body,
            mediaType: post.mediaType, mediaURL: post.mediaURL, thumbURL: post.thumbURL,
            mediaCaption: post.mediaCaption, sharedPostID: post.sharedPostID,
            visibility: post.visibility, likeCount: likeCount, commentCount: post.commentCount,
            viewCount: post.viewCount, likedByMe: likedByMe, savedByMe: post.savedByMe,
            createdAt: post.createdAt, updatedAt: post.updatedAt,
            authorID: post.authorID, countryName: post.countryName,
            countryCode: post.countryCode, cityName: post.cityName, author: post.author
        )
    }
}