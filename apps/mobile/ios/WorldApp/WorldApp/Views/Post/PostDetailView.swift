import SwiftUI

struct PostDetailView: View {
    @Environment(AppState.self) private var appState

    let postID: String

    @State private var post: CountryPost?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading, post == nil {
                    ProgressView()
                        .tint(Theme.facebookBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let errorMessage, post == nil {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                        .padding(Theme.pagePadding)
                } else if let currentPost = post {
                    // Only true hub long-form gets the “open in Hubs” banner.
                    if PlayPlatformBridge.isHubFeedCardVideo(currentPost) {
                        watchOnPlayBanner(for: currentPost)
                    } else if currentPost.isReel {
                        watchSparkBanner(for: currentPost)
                    }
                    // Full-bleed feed card — same width/style as home feed.
                    postCard(for: currentPost)
                } else {
                    Text("Post not found.")
                        .foregroundStyle(Theme.inkMuted)
                        .padding(Theme.pagePadding)
                }
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .task(id: postID) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil

        // Instant paint from cache if the post was already in feed/hubs/profile.
        if let cached = PostsService.shared.cachedPostForDetail(id: postID) {
            post = cached
            isLoading = false
        }

        // Network / hub fetch with a hard timeout so we never spin forever.
        let fetched: CountryPost? = await withTimeout(seconds: 12) {
            try? await PostsService.shared.getPostByID(postID)
        }

        if let fetched {
            post = fetched
            errorMessage = nil
        } else if post == nil {
            errorMessage = "Post not found or couldn’t be loaded. Pull back and try again."
        }
        isLoading = false
    }

    /// Race `operation` against a timeout; returns nil on timeout (or if the fetch failed).
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: (isOperation: Bool, value: T?).self) { group in
            group.addTask {
                (true, await operation())
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return (false, nil)
            }
            while let result = await group.next() {
                if result.isOperation {
                    group.cancelAll()
                    return result.value
                }
                // Timeout won — stop waiting on a hung request.
                group.cancelAll()
                return nil
            }
            return nil
        }
    }

    @ViewBuilder
    private func postCard(for currentPost: CountryPost) -> some View {
        FacebookPostCard(
            post: currentPost,
            edgeToEdge: true,
            showsAuthorHeader: false,
            showsAuthorInJournal: true,
            commentsInitiallyExpanded: true,
            onLikeToggle: { Task { await toggleLike(currentPost) } },
            onOpenPost: {},
            onOpenVideo: currentPost.hasVideo && !currentPost.isReel
                ? { appState.openPost(currentPost) }
                : nil,
            onOpenReel: currentPost.isReel
                ? { appState.openReelsViewer(startingPost: currentPost) }
                : nil,
            onPostDeleted: { _ in handlePostDeleted() },
            onPostUpdated: { updated in handlePostUpdated(updated) },
            expandsCommentsInline: true
        )
    }

    private func watchSparkBanner(for post: CountryPost) -> some View {
        Button {
            appState.openReelsViewer(startingPost: post)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Theme.accentBright)
                Text("Play \(MatteryaCopy.spark)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
    }

    private func watchOnPlayBanner(for post: CountryPost) -> some View {
        Button {
            appState.openPost(post)
        } label: {
            HStack(spacing: 10) {
                HubsOriginBadge()
                VStack(alignment: .leading, spacing: 2) {
                    Text(MatteryaCopy.watchOnHubs)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .matteryaBrandLine(minScale: 0.85)
                    Text("Open in the Hubs player with more like this")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
    }

    private func handlePostDeleted() {
        post = nil
        errorMessage = "This post was deleted."
    }

    private func handlePostUpdated(_ updated: CountryPost) {
        post = updated
    }

    private func toggleLike(_ post: CountryPost) async {
        // Optimistic UI first — never wipe the screen with GraphQL "Unexpected error".
        let nextLiked = !post.likedByMe
        let nextCount = nextLiked ? post.likeCount + 1 : max(0, post.likeCount - 1)
        let optimistic = post.withEngagement(
            likedByMe: nextLiked,
            likeCount: nextCount,
            commentCount: post.commentCount
        )
        self.post = optimistic
        errorMessage = nil

        if post.likedByMe {
            try? await PostsService.shared.unlikePost(post.id, baseLikeCount: post.likeCount)
        } else {
            try? await PostsService.shared.likePost(post.id, baseLikeCount: post.likeCount)
        }

        if let refreshed = try? await PostsService.shared.getPostByID(postID) {
            self.post = refreshed.withEngagement(
                likedByMe: nextLiked || refreshed.likedByMe,
                likeCount: max(nextCount, refreshed.likeCount),
                commentCount: refreshed.commentCount
            )
        }
        if let current = self.post {
            PostsService.shared.publishPostChange(current)
        }
    }
}
