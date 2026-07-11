import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var appState

    @State private var posts: [CountryPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var visibleLimit = 10

    private let pageSize = 12

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MatteryaTopBar(showsSearch: true) {
                    appState.navigate(to: .search)
                }

                Group {
                    if isLoading && posts.isEmpty {
                        ProgressView("Loading feed…")
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage, posts.isEmpty {
                        ContentUnavailableView(
                            "Feed unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else if posts.isEmpty {
                        ContentUnavailableView(
                            "Your feed is quiet",
                            systemImage: "newspaper",
                            description: Text("Posts from everywhere will show up here as people share.")
                        )
                    } else {
                        feedList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .screenBackground()

        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await refreshFeed(showSpinner: false, resetPagination: true)
        }
        .task {
            await refreshFeed(showSpinner: true, resetPagination: true)
            Task { await appState.refreshStories() }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                StoriesStripView()

                ForEach(displayedPosts) { post in
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
                    .onAppear {
                        loadMoreIfNeeded(for: post)
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private var displayedPosts: [CountryPost] {
        Array(posts.prefix(visibleLimit))
    }

    private func loadMoreIfNeeded(for post: CountryPost) {
        guard let index = displayedPosts.firstIndex(where: { $0.id == post.id }) else { return }
        guard index >= displayedPosts.count - 3 else { return }
        guard visibleLimit < posts.count else { return }
        visibleLimit = min(posts.count, visibleLimit + pageSize)
    }

    private func refreshFeed(showSpinner: Bool, resetPagination: Bool) async {
        if showSpinner && posts.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        defer { isLoading = false }

        let loaded = await PostsService.shared.loadHomeFeed()
        posts = loaded.filter { !$0.isStory && !$0.isReel }
        if resetPagination {
            visibleLimit = min(pageSize, posts.count)
        } else {
            visibleLimit = min(max(visibleLimit, pageSize), posts.count)
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
            errorMessage = error.localizedDescription
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