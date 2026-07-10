import SwiftUI

struct PublicProfileView: View {
    @Environment(AppState.self) private var appState

    let username: String

    @State private var profile: Profile?
    @State private var posts: [CountryPost] = []
    @State private var followCounts = FollowCounts(followers: 0, following: 0)
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var isOwner: Bool {
        profile?.userID == appState.currentProfile?.userID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if isLoading {
                    ProgressView().tint(Theme.accentBright)
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                } else if let profile {
                    profileHeader(profile)
                    postsSection
                }
            }
            .padding(Theme.pagePadding)
        }
        .navigationTitle(profile?.displayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .task(id: username) { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func profileHeader(_ profile: Profile) -> some View {
        VStack(spacing: 14) {
            AvatarView(url: profile.avatarURL, seed: profile.userID, size: 92)
            Text(profile.displayName ?? profile.username ?? "Member")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
            if let username = profile.username {
                Text("@\(username)").foregroundStyle(Theme.inkMuted)
            }
            if !LivingChannelMarker.displayBio(from: profile.bio).isEmpty {
                Text(LivingChannelMarker.displayBio(from: profile.bio))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.inkSecondary)
            }
            if let country = profile.countryName {
                Label(country, systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentBright)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accentSoft, in: Capsule())
            }

            HStack(spacing: 28) {
                stat("Followers", followCounts.followers)
                stat("Following", followCounts.following)
            }

            if !isOwner {
                HStack(spacing: 12) {
                    if !profile.isDemoUser {
                        FollowButton(userID: profile.userID)
                    }
                    Button("Message") {
                        Task { await startConversation(profile.userID) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .premiumCard()
    }

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posts").sectionLabel()
            if posts.isEmpty {
                Text("No posts yet.")
                    .foregroundStyle(Theme.inkMuted)
                    .premiumCard()
            } else {
                ForEach(posts) { post in
                    FacebookPostCard(
                        post: post,
                        showsAuthorHeader: false,
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
            }
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack {
            Text("\(value)")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            profile = try await ProfileService.shared.profileByUsername(username)
            guard let profile else {
                errorMessage = "Profile not found."
                return
            }
            async let postsTask = PostsService.shared.listForAuthor(profile.userID, limit: 20)
            async let countsTask = FollowService.shared.counts(userID: profile.userID)
            posts = try await postsTask
            followCounts = await countsTask
        } catch {
            errorMessage = error.localizedDescription
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

    private func startConversation(_ targetID: String) async {
        do {
            let conversation = try await MessagesService.shared.startConversation(targetID: targetID)
            appState.pendingConversationID = conversation.id
            appState.selectedTab = .messages
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}