import SwiftUI
import UIKit

struct PublicProfileView: View {
    @Environment(AppState.self) private var appState

    let username: String?
    let userID: String?

    @State private var profile: Profile?
    @State private var posts: [CountryPost] = []
    @State private var followCounts = FollowCounts(followers: 0, following: 0)
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var postsErrorMessage: String?

    init(username: String) {
        self.username = username
        self.userID = nil
    }

    init(userID: String) {
        self.username = nil
        self.userID = userID
    }

    private var loadKey: String {
        if let username, !username.isEmpty { return "u:\(username)" }
        if let userID, !userID.isEmpty { return "id:\(userID)" }
        return "missing"
    }

    private var isOwner: Bool {
        profile?.userID == appState.currentProfile?.userID
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Theme.accentBright)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Profile unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        profileHeader(profile)
                        postsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .task(id: loadKey) { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func profileHeader(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                ExpandableProfileAvatar(
                    url: profile.avatarURL,
                    seed: profile.userID,
                    size: 78,
                    displayName: profile.displayName ?? profile.username
                )
                .overlay {
                    Circle()
                        .stroke(Theme.border, lineWidth: 0.5)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        if let name = profile.displayName, !name.isEmpty {
                            Text(name)
                                .font(.system(size: 24, weight: .regular, design: .serif))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        } else if profile.displayName?.isEmpty != false {
                            Text("Member")
                                .font(.system(size: 24, weight: .regular, design: .serif))
                                .foregroundStyle(Theme.ink)
                        }

                        if !isOwner, !profile.isDemoUser {
                            FollowButton(userID: profile.userID)
                        }
                    }

                    if let username = profile.username {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                    }

                    HStack(spacing: 18) {
                        stat("Posts", posts.count)
                        stat("Followers", followCounts.followers)
                        stat("Following", followCounts.following)
                    }
                }
            }

            if !LivingChannelMarker.displayBio(from: profile.bio).isEmpty {
                Text(LivingChannelMarker.displayBio(from: profile.bio))
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let country = profile.countryName, country != "Unknown" {
                Label(country, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }

            if hasPlayChannel(profile) {
                Button {
                    appState.openPlayChannel(
                        authorID: profile.userID,
                        username: profile.username
                    )
                } label: {
                    Label(MatteryaCopy.watchOnHubs, systemImage: "globe.americas")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if isOwner {
                HStack(spacing: 10) {
                    Button {
                        appState.navigate(to: .editProfile)
                    } label: {
                        Label("Edit profile", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        appState.navigate(to: .settings)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                profileActions(profile)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func profileActions(_ profile: Profile) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await appState.openDirectMessage(with: profile.userID) }
            } label: {
                Label("Message", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Menu {
                Button {
                    shareProfile(profile)
                } label: {
                    Label("Share profile", systemImage: "square.and.arrow.up")
                }

                if BlockService.shared.isBlocked(profile.userID) {
                    Button("Unblock user") {
                        appState.unblockUser(profile.userID)
                    }
                } else {
                    Button("Block user", role: .destructive) {
                        appState.blockUser(
                            profile.userID,
                            username: profile.username,
                            displayName: profile.displayName
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posts")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            if let postsErrorMessage {
                Text(postsErrorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(Theme.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }

            if posts.isEmpty && postsErrorMessage == nil {
                Text("No posts yet.")
                    .foregroundStyle(Theme.inkMuted)
                    .padding(Theme.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            } else {
                LazyVStack(spacing: 18) {
                    ForEach(posts) { post in
                        FacebookPostCard(
                            post: post,
                            showsAuthorHeader: false,
                            showsAuthorInJournal: true,
                            onLikeToggle: { Task { await toggleLike(post) } },
                            onOpenPost: { appState.navigate(to: .post(post.id)) },
                            onOpenVideo: PlayPlatformBridge.isLongFormVideo(post)
                                ? { appState.openPost(post) }
                                : nil,
                            onOpenReel: {
                                var sparks = posts.filter(\.isReel)
                                if !sparks.contains(where: { $0.id == post.id }) {
                                    sparks.insert(post, at: 0)
                                }
                                appState.openReelsViewer(startingPost: post, seedPosts: sparks)
                            },
                            onPostDeleted: { id in posts.removeAll { $0.id == id } },
                            onPostUpdated: { updated in
                                if let index = posts.firstIndex(where: { $0.id == updated.id }) {
                                    posts[index] = updated
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    private func hasPlayChannel(_ profile: Profile) -> Bool {
        posts.contains { PlayPlatformBridge.isPlayEligible($0) }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
        postsErrorMessage = nil
        defer { isLoading = false }

        do {
            profile = try await resolveProfile()
            guard let profile else {
                errorMessage = "Profile not found."
                return
            }

            followCounts = await FollowService.shared.counts(userID: profile.userID)

            do {
                posts = try await PostsService.shared.listForAuthor(profile.userID, limit: 20).excludingSparks()
            } catch {
                posts = []
                postsErrorMessage = "Couldn't load posts."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveProfile() async throws -> Profile? {
        if let username = normalizedUsername {
            if let profile = try await ProfileService.shared.profileByUsername(username) {
                return profile
            }
            if UUID(uuidString: username) != nil,
               let profile = try await ProfileService.shared.profileByID(username) {
                return profile
            }
        }

        if let userID, !userID.isEmpty {
            return try await ProfileService.shared.profileByID(userID)
        }

        return nil
    }

    private var normalizedUsername: String? {
        guard let raw = username?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw.replacingOccurrences(of: "^@+", with: "", options: .regularExpression)
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

    private func shareProfile(_ profile: Profile) {
        let items = ShareService.shared.activityItems(for: .profile(profile))
        guard let root = UIApplication.shared.firstKeyWindow?.rootViewController else { return }
        root.topMostViewController().presentShareSheet(items: items)
    }

}