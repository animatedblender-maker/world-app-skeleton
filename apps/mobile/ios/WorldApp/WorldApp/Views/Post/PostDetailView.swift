import SwiftUI

struct PostDetailView: View {
    let postID: String

    @State private var post: CountryPost?
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
                    FacebookPostCard(
                        post: currentPost,
                        showsAuthorHeader: false,
                        showsAuthorInJournal: true,
                        commentsInitiallyExpanded: true,
                        onLikeToggle: { Task { await toggleLike(currentPost) } },
                        onOpenPost: {},
                        onPostDeleted: { _ in handlePostDeleted() },
                        onPostUpdated: { updated in handlePostUpdated(updated) }
                    )
                    .padding(.horizontal, Theme.pagePadding)
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
            post = try await PostsService.shared.getPostByID(postID)
        } catch {
            errorMessage = error.localizedDescription
        }
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
            self.post = try await PostsService.shared.getPostByID(postID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}