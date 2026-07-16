import SwiftUI

struct PostDetailView: View {
    @Environment(AppState.self) private var appState

    let postID: String

    @State private var post: CountryPost?
    @State private var didRouteToPlay = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView()
                        .tint(Theme.facebookBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                        .padding(Theme.pagePadding)
                } else if let currentPost = post {
                    if didRouteToPlay {
                        ProgressView(MatteryaCopy.openingHubs)
                            .tint(Theme.accentBright)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if PlayPlatformBridge.isLongFormVideo(currentPost) {
                        watchOnPlayBanner(for: currentPost)
                        postCard(for: currentPost)
                    } else {
                        if currentPost.isReel {
                            watchSparkBanner(for: currentPost)
                        }
                        postCard(for: currentPost)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let loaded = try await PostsService.shared.getPostByID(postID) else {
                errorMessage = "Post not found."
                return
            }
            post = loaded
            routeLongFormToPlayIfNeeded(loaded)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func routeLongFormToPlayIfNeeded(_ post: CountryPost) {
        guard !didRouteToPlay else { return }
        if PlayPlatformBridge.isLongFormVideo(post) {
            didRouteToPlay = true
            appState.openLivingVideo(postID: post.id)
        }
    }

    @ViewBuilder
    private func postCard(for currentPost: CountryPost) -> some View {
        FacebookPostCard(
            post: currentPost,
            showsAuthorHeader: false,
            showsAuthorInJournal: true,
            commentsInitiallyExpanded: true,
            onLikeToggle: { Task { await toggleLike(currentPost) } },
            onOpenPost: {},
            onOpenVideo: PlayPlatformBridge.isLongFormVideo(currentPost)
                ? { appState.openPost(currentPost) }
                : nil,
            onOpenReel: currentPost.isReel
                ? { appState.openReelsViewer(startingPost: currentPost) }
                : nil,
            onPostDeleted: { _ in handlePostDeleted() },
            onPostUpdated: { updated in handlePostUpdated(updated) },
            expandsCommentsInline: true
        )
        .padding(.horizontal, Theme.pagePadding)
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
                HandDrawnGlobeStoryRing(size: 28, highlighted: true)
                Text(MatteryaCopy.watchOnHubs)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .matteryaBrandLine(minScale: 0.85)
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
        do {
            if post.likedByMe {
                try await PostsService.shared.unlikePost(post.id)
            } else {
                try await PostsService.shared.likePost(post.id)
            }
            if let refreshed = try await PostsService.shared.getPostByID(postID) {
                self.post = refreshed
                PostsService.shared.publishPostChange(refreshed)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}