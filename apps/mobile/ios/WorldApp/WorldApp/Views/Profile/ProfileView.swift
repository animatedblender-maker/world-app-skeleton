import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState

    @State private var posts: [CountryPost] = []
    @State private var followCounts = FollowCounts(followers: 0, following: 0)
    @State private var isLoadingPosts = false
    @State private var lastPostsLoadAt: Date = .distantPast
    @State private var errorMessage: String?
    /// Real Hubs channel only — not feed re-shares of Hubs content.
    @State private var hasOwnHubsChannel = false

    private var profile: Profile? { appState.currentProfile }

    private var profileUserID: String? {
        profile?.userID ?? AuthService.shared.currentUser?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            MatteryaTopBar(showsSearch: true) {
                appState.navigate(to: .search)
            }

            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    librarySectionPicker
                    librarySection
                }
                .padding(.bottom, 24)
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await appState.refreshProfile()
            await appState.refreshSavedPosts()
            await loadPosts()
            await loadCounts()
        }
        .task(id: ProfileLoadToken(userID: profileUserID, generation: appState.contentLoadGeneration)) {
            // Instant paint from cache, then parallel network — never sequential waterfall.
            PerformanceTelemetry.mark("profile_task_start")
            paintProfileFromCache()
            PerformanceTelemetry.milestone(
                "profile_interactive",
                surface: "profile",
                from: "profile_task_start",
                meta: ["source": "cache_paint"]
            )
            async let profile: Void = appState.refreshProfile()
            async let saved: Void = appState.refreshSavedPosts()
            async let postsTask: Void = loadPosts()
            async let countsTask: Void = loadCounts()
            _ = await (profile, saved, postsTask, countsTask)
        }
        .onChange(of: appState.selectedTab) { _, tab in
            guard tab == .profile else { return }
            // Soft re-elect only — hard reset was silencing + re-warming every video on tab hop.
            FeedVideoFocus.shared.resetAll()
            // Instant cache paint; network only if empty or >45s stale.
            paintProfileFromCache()
            let stale = Date().timeIntervalSince(lastPostsLoadAt) > 45
            guard posts.isEmpty || stale else { return }
            Task {
                async let postsTask: Void = loadPosts()
                async let countsTask: Void = loadCounts()
                _ = await (postsTask, countsTask)
            }
        }
        .onChange(of: appState.profileLibrarySection) { _, _ in
            // Posts ↔ Saved swaps the visible video list — clear so the new ≥50% winner can play.
            FeedVideoFocus.shared.resetAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPostsDidChange)) { notification in
            // Include Sparks — previously `!created.isSpark` dropped every new reel from the profile.
            if let created = notification.userInfo?["post"] as? CountryPost,
               created.authorID == profileUserID,
               !created.isStory {
                posts.removeAll { $0.id == created.id }
                posts.insert(created, at: 0)
            } else {
                Task { await loadPosts() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPostDidDelete)) { notification in
            guard let id = notification.userInfo?["postID"] as? String else { return }
            posts.removeAll { $0.id == id || $0.sharedPostID == id }
            appState.savedPosts.removeAll { $0.id == id || $0.sharedPostID == id }
            appState.savedPostIDs.remove(id)
            appState.reelPresentationSavedIDs.remove(id)
            if var cached = ContentCache.shared.posts(for: .profilePosts) {
                cached.removeAll { $0.id == id || $0.sharedPostID == id }
                ContentCache.shared.setPosts(cached, for: .profilePosts)
            }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 22) {
                ExpandableProfileAvatar(
                    url: profile?.avatarURL,
                    seed: profile?.userID ?? "me",
                    size: 78,
                    displayName: profile?.displayName ?? profile?.username
                )
                .overlay {
                    Circle()
                        .stroke(Theme.border, lineWidth: 0.5)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if let name = profile?.displayName, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 26, weight: .regular, design: .serif))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }

                    if let username = profile?.username {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                    } else if profile?.displayName?.isEmpty != false {
                        Text("Member")
                            .font(.system(size: 26, weight: .regular, design: .serif))
                            .foregroundStyle(Theme.ink)
                    }

                    HStack(spacing: 18) {
                        statBlock("Posts", value: posts.count)
                        statBlock("Followers", value: followCounts.followers)
                        statBlock("Following", value: followCounts.following)
                    }
                }
            }

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

            VStack(alignment: .leading, spacing: 8) {
                if let bio = profile?.bio,
                   !LivingChannelMarker.displayBio(from: bio).isEmpty {
                    Text(LivingChannelMarker.displayBio(from: bio))
                        .font(.body)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineSpacing(3)
                }
                if let country = profile?.countryName, country != "Unknown" {
                    Label(country, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
            }

            // Only show Hubs channel entry when a real channel exists (not re-shares).
            if hasOwnHubsChannel, let userID = profileUserID {
                Button {
                    appState.openPlayChannel(authorID: userID, username: profile?.username)
                } label: {
                    Label(MatteryaCopy.yourChannelOnHubs, systemImage: "play.rectangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private var librarySectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProfileLibrarySection.allCases) { section in
                    Button(section.title) {
                        appState.profileLibrarySection = section
                    }
                    .pillTab(isSelected: appState.profileLibrarySection == section)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        switch appState.profileLibrarySection {
        case .posts:
            postsSection
        case .savedPosts:
            savedSection(
                title: "Saved posts",
                subtitle: "Bookmarks from your feed",
                posts: appState.savedJournalPosts,
                emptyIcon: "bookmark",
                emptyMessage: "Save posts from the feed to revisit them here."
            )
        case .savedVideos:
            savedSection(
                title: "Saved videos",
                subtitle: "Videos you bookmarked",
                posts: appState.savedVideoPosts,
                emptyIcon: "film",
                emptyMessage: "Save videos from the feed to watch them later."
            )
        case .savedReels:
            savedSection(
                title: MatteryaCopy.savedSparks,
                subtitle: MatteryaCopy.savedSparksSubtitle,
                posts: appState.savedReelPosts,
                emptyIcon: "sparkles",
                emptyMessage: "Save \(MatteryaCopy.sparks.lowercased()) from Play or your feed to keep them here."
            )
        }
    }

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Posts", subtitle: "Everything you've shared")

            if isLoadingPosts {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, Theme.pagePadding)
            } else if posts.isEmpty {
                emptyPosts
            } else {
                postCards(posts, showsAuthorInJournal: true)
            }
        }
    }

    private func savedSection(
        title: String,
        subtitle: String,
        posts: [CountryPost],
        emptyIcon: String,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title, subtitle: subtitle)

            if posts.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: emptyIcon)
                        .font(.system(size: 34, weight: .ultraLight))
                        .foregroundStyle(Theme.inkMuted)
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(36)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.pagePadding)
            } else {
                // Posts + Saved Sparks both show Spark cards (own Sparks belong on profile).
                postCards(posts, showsAuthorInJournal: true, allowSparks: true)
            }
        }
    }

    private func sectionHeader(_ label: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .tracking(2)
                .foregroundStyle(Theme.inkMuted)
            Text(subtitle)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private func postCards(
        _ items: [CountryPost],
        showsAuthorInJournal: Bool,
        allowSparks: Bool = true
    ) -> some View {
        // Match home feed: edge-to-edge cards. Own Sparks always visible on profile.
        let visible: [CountryPost] = items.forProfileFeedGrid()
        return LazyVStack(spacing: 0) {
            ForEach(visible) { post in
                FacebookPostCard(
                    post: post,
                    edgeToEdge: true,
                    showsAuthorHeader: false,
                    showsAuthorInJournal: showsAuthorInJournal,
                    mediaContext: .feed,
                    autoplaySurface: .profile,
                    onLikeToggle: {
                        Task {
                            await toggleLike(
                                post,
                                updatePosts: appState.profileLibrarySection == .posts
                            )
                        }
                    },
                    onOpenPost: { appState.navigate(to: .post(post.id)) },
                    onOpenVideo: {
                        appState.openPost(post)
                    },
                    onOpenReel: {
                        var sparks = items.filter {
                            $0.isReel || $0.isSparkFeedShare || AppState.belongsInSavedSparks($0)
                                || PlayPlatformBridge.isSparkFeedCard($0)
                        }
                        if !sparks.contains(where: { $0.id == post.id }) {
                            sparks.insert(post, at: 0)
                        }
                        appState.openReelsViewer(startingPost: post, seedPosts: sparks)
                    },
                    onPostDeleted: { id in
                        posts.removeAll { $0.id == id }
                        appState.savedPosts.removeAll { $0.id == id }
                        appState.savedPostIDs.remove(id)
                        appState.reelPresentationSavedIDs.remove(id)
                    },
                    onPostUpdated: { updated in
                        if let index = posts.firstIndex(where: { $0.id == updated.id }) {
                            posts[index] = updated
                        }
                        if let index = appState.savedPosts.firstIndex(where: { $0.id == updated.id }) {
                            appState.savedPosts[index] = updated
                        }
                    }
                )
                .onAppear {
                    EngagementTracker.shared.feedPostAppeared(post, surface: "profile")
                }
                .onDisappear {
                    EngagementTracker.shared.feedPostDisappeared(post)
                }
            }
        }
    }

    private var emptyPosts: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(Theme.inkMuted)
            Text("No posts yet")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("Posts you publish from your home country appear here.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)

            Button {
                Task { await appState.navigateToHomeCountryFeed(openComposer: true) }
            } label: {
                Text("Write a post")
                    .elegantButton()
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .padding(.horizontal, Theme.pagePadding)
    }

    private func statBlock(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.medium))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption2)
                .tracking(0.4)
                .foregroundStyle(Theme.inkMuted)
        }
    }

    /// Paint posts / channel flag from disk cache so Profile never waits on GraphQL.
    private func paintProfileFromCache() {
        if posts.isEmpty, let cached = ContentCache.shared.posts(for: .profilePosts), !cached.isEmpty {
            posts = cached.forProfileFeedGrid()
        }
        if let userID = profileUserID {
            hasOwnHubsChannel = LivingChannelMarker.hasChannel(profile: profile)
                || posts.contains { !$0.isReel && PlayPlatformBridge.isHubChannelUpload($0) }
            // Local follow cache if available.
            if let cached = FollowService.shared.cachedCounts(userID: userID) {
                followCounts = cached
            }
        }
    }

    private func loadPosts() async {
        guard let userID = profileUserID, !userID.isEmpty else { return }
        let showSpinner = posts.isEmpty
        if showSpinner { isLoadingPosts = true }
        errorMessage = nil
        defer {
            if showSpinner { isLoadingPosts = false }
        }
        do {
            // First page is enough for snappy open; grid is lazy.
            let loaded = try await PostsService.shared.listForAuthor(userID, limit: 40)
                .forProfileFeedGrid()
            posts = loaded
            lastPostsLoadAt = Date()
            ContentCache.shared.setPosts(loaded, for: .profilePosts)
        } catch {
            if posts.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        // Channel resolve is secondary — don't block first paint.
        hasOwnHubsChannel = await resolveHasOwnHubsChannel(userID: userID)
    }

    private func resolveHasOwnHubsChannel(userID: String) async -> Bool {
        if LivingChannelMarker.hasChannel(profile: profile) { return true }
        // Prefer local posts before network channel lookup.
        if posts.contains(where: { !$0.isReel && PlayPlatformBridge.isHubChannelUpload($0) }) {
            return true
        }
        if let channel = try? await ChannelsService.shared.channelByOwner(userID: userID),
           !channel.id.isEmpty {
            return true
        }
        return false
    }

    private func loadCounts() async {
        guard let userID = profile?.userID ?? profileUserID else { return }
        followCounts = await FollowService.shared.counts(userID: userID)
    }

    private func toggleLike(_ post: CountryPost, updatePosts: Bool) async {
        if updatePosts, let index = posts.firstIndex(where: { $0.id == post.id }) {
            await applyLikeToggle(post: post) { updated in posts[index] = updated }
        } else {
            await applyLikeToggle(post: post) { _ in }
        }
    }

    private func applyLikeToggle(post: CountryPost, update: (CountryPost) -> Void) async {
        do {
            if post.likedByMe {
                try await PostsService.shared.unlikePost(post.id)
                update(copyPost(post, likedByMe: false, likeCount: max(0, post.likeCount - 1)))
            } else {
                try await PostsService.shared.likePost(post.id)
                update(copyPost(post, likedByMe: true, likeCount: post.likeCount + 1))
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

private struct ProfileLoadToken: Hashable {
    let userID: String?
    let generation: Int
}