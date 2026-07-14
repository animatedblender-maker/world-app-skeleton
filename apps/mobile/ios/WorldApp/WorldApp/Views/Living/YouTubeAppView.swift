import SwiftUI

private enum YouTubeRoute: Equatable {
    case watch(CountryPost)
    case channel(YouTubeChannel)
}

private struct LibraryPlaybackRequest {
    let post: CountryPost
    let asSpark: Bool
    let sparkSeed: [CountryPost]
}

struct YouTubeAppView: View {
    @Environment(AppState.self) private var appState

    @State private var allVideos: [CountryPost] = []
    @State private var channels: [YouTubeChannel] = []
    @State private var channelProfiles: [String: Profile] = [:]
    @State private var followerCounts: [String: Int] = [:]
    @State private var homeFilter: YouTubeHomeFilter = .all
    @State private var librarySection: YouTubeLibrarySection = .history
    @State private var route: YouTubeRoute?
    @State private var miniPlayerPost: CountryPost?
    @State private var showSearch = false
    @State private var showLibrary = false
    @State private var pendingLibraryPlayback: LibraryPlaybackRequest?
    @State private var scrollToSubscriptions = false
    @State private var searchQuery = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private enum PlayScrollAnchor {
        static let subscriptions = "play-subscriptions"
    }

    private let catalog = YouTubeCatalogService.shared

    private var playReels: [CountryPost] { catalog.reels(from: allVideos) }

    private var continueWatching: [CountryPost] {
        Array(catalog.historyVideos(from: allVideos).filter { !$0.isReel }.prefix(8))
    }

    private var homeVideos: [CountryPost] {
        catalog.filterVideos(
            allVideos,
            homeFilter: homeFilter,
            followingIDs: appState.followingIDs,
            viewerCountry: appState.currentProfile?.countryCode
        )
    }

    private var discoverVideos: [CountryPost] {
        guard homeFilter == .all, !subscriptionVideos.isEmpty else { return homeVideos }
        let subscriptionIDs = Set(subscriptionVideos.map(\.id))
        return homeVideos.filter { !subscriptionIDs.contains($0.id) }
    }

    private var subscriptionVideos: [CountryPost] {
        catalog.subscriptionFeed(
            videos: allVideos,
            channels: channels,
            followingIDs: appState.followingIDs
        )
    }

    private var subscriptionChannels: [YouTubeChannel] {
        catalog.subscriptionChannels(channels, followingIDs: appState.followingIDs)
    }

    private var searchResults: (videos: [CountryPost], channels: [YouTubeChannel]) {
        catalog.search(query: searchQuery, videos: allVideos, channels: channels)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if route == nil {
                    YouTubeAppHeader(
                        onSearch: { showSearch = true }
                    )
                }

                Group {
                    switch route {
                    case .watch(let post):
                        YouTubeWatchView(
                            post: post,
                            channel: catalog.channel(for: post.authorID, in: channels),
                            related: catalog.relatedVideos(to: post, from: allVideos),
                            subscriberCount: followerCounts[post.authorID],
                            onBack: { closeWatch(minimize: true) },
                            onOpenVideo: { openVideo($0) },
                            onOpenChannel: { openChannel($0) }
                        )
                    case .channel(let channel):
                        YouTubeChannelView(
                            channel: channel,
                            subscriberCount: followerCounts[channel.authorID],
                            onBack: { route = nil },
                            onOpenVideo: { openVideo($0) }
                        )
                    case nil:
                        mainContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let miniPlayerPost, route == nil {
                YouTubeMiniPlayerBar(
                    post: miniPlayerPost,
                    onExpand: { openVideo(miniPlayerPost) },
                    onClose: { self.miniPlayerPost = nil }
                )
                .padding(.bottom, Theme.tabBarHeight + 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: miniPlayerPost?.id)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await loadVideos(forceRefresh: true)
        }
        .task(id: appState.contentLoadGeneration) {
            await loadVideos(forceRefresh: false)
            await consumePendingRoutingIfNeeded()
        }
        .onChange(of: appState.pendingLivingVideoID) { _, newID in
            guard let newID else { return }
            Task { await openVideo(id: newID) }
        }
        .onChange(of: appState.pendingPlayTab) { _, tab in
            guard let tab else { return }
            applyPendingPlayTab(tab)
            appState.pendingPlayTab = nil
        }
        .onChange(of: appState.pendingPlayChannelAuthorID) { _, authorID in
            guard authorID != nil else { return }
            Task { await consumePendingChannelIfNeeded() }
        }
        .onChange(of: appState.pendingPlayChannelUsername) { _, username in
            guard username != nil else { return }
            Task { await consumePendingChannelIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPostsDidChange)) { notification in
            guard let created = notification.userInfo?["post"] as? CountryPost,
                  catalog.livingEligible(created),
                  !allVideos.contains(where: { $0.id == created.id })
            else { return }
            allVideos.insert(created, at: 0)
            rebuildChannels()
        }
        .sheet(isPresented: $showSearch) {
            YouTubeSearchSheet(
                query: $searchQuery,
                videos: searchResults.videos,
                channels: searchResults.channels,
                onSelectVideo: { post in
                    showSearch = false
                    openVideo(post)
                },
                onSelectChannel: { channel in
                    showSearch = false
                    openChannel(channel)
                }
            )
        }
        .sheet(isPresented: $showLibrary, onDismiss: consumePendingLibraryPlayback) {
            NavigationStack {
                libraryScreen
                    .navigationTitle("Library")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showLibrary = false }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading && allVideos.isEmpty {
            ProgressView(MatteryaCopy.loadingHubs)
                .tint(Theme.accentBright)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, allVideos.isEmpty {
            ContentUnavailableView(MatteryaCopy.hubsUnavailable, systemImage: "globe.americas", description: Text(errorMessage))
        } else {
            homeScreen
        }
    }

    private var homeScreen: some View {
        VStack(spacing: 0) {
            YouTubeFilterChips(selected: $homeFilter, onLibrary: { showLibrary = true })
            if homeScreenIsEmpty {
                ContentUnavailableView(
                    homeFilter == .all ? "No videos here yet" : "No videos in this category",
                    systemImage: "globe.americas",
                    description: Text(
                        homeFilter == .all
                            ? MatteryaCopy.hubsPublishHint
                            : "Try another category or check back later."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if homeFilter == .all {
                                if !playReels.isEmpty {
                                    homeReelsStrip
                                        .padding(.bottom, 20)
                                }
                                if !continueWatching.isEmpty {
                                    continueWatchingStrip
                                        .padding(.bottom, 20)
                                }
                                if !subscriptionChannels.isEmpty || !subscriptionVideos.isEmpty {
                                    followingSection
                                        .padding(.bottom, 8)
                                        .id(PlayScrollAnchor.subscriptions)
                                }
                            }
                            ForEach(discoverVideos) { post in
                                YouTubeVideoListRow(post: post) {
                                    openVideo(post)
                                }
                                .padding(.bottom, 18)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, miniPlayerPost == nil ? 12 : 72)
                    }
                    .onChange(of: scrollToSubscriptions) { _, shouldScroll in
                        guard shouldScroll else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(PlayScrollAnchor.subscriptions, anchor: .top)
                        }
                        scrollToSubscriptions = false
                    }
                }
            }
        }
    }

    private var homeScreenIsEmpty: Bool {
        if homeFilter == .all {
            return continueWatching.isEmpty
                && subscriptionVideos.isEmpty
                && playReels.isEmpty
                && discoverVideos.isEmpty
        }
        return homeVideos.isEmpty
    }

    private var followingPreviewVideos: [CountryPost] {
        Array(subscriptionVideos.prefix(3))
    }

    private var followingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            hubsSectionHeader("Following")

            if !subscriptionChannels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(subscriptionChannels) { channel in
                            Button {
                                openChannel(channel)
                            } label: {
                                VStack(spacing: 6) {
                                    AvatarView(url: channel.author?.avatarURL, seed: channel.authorID, size: 52)
                                    Text(channel.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
            }

            ForEach(followingPreviewVideos) { post in
                YouTubeVideoListRow(post: post) {
                    openVideo(post)
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func hubsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.inkMuted)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.pagePadding)
    }

    private var homeReelsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(MatteryaCopy.sparks)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .textCase(.uppercase)
                Spacer()
                Button(MatteryaCopy.watchAllSparks) {
                    openReelsPlayback(starting: playReels.first, seed: playReels)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentBright)
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(playReels.prefix(8)) { post in
                        PlayReelTile(post: post) {
                            openReelsPlayback(starting: post, seed: playReels)
                        }
                        .frame(width: 108)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    private var libraryScreen: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(YouTubeLibrarySection.allCases) { section in
                        Button {
                            librarySection = section
                        } label: {
                            Text(section.title)
                        }
                        .pillTab(isSelected: librarySection == section)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 12)
            }
            .overlay(alignment: .bottom) {
                Theme.divider.frame(height: 0.5)
            }

            if libraryVideos.isEmpty {
                libraryEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 22) {
                        if librarySection == .reels {
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                                spacing: 10
                            ) {
                                ForEach(libraryVideos) { post in
                                    PlayReelTile(post: post) {
                                        openFromLibrary(post)
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.pagePadding)
                        } else {
                            ForEach(libraryVideos) { post in
                                YouTubeVideoListRow(post: post) {
                                    openFromLibrary(post)
                                }
                            }
                        }
                    }
                    .padding(.bottom, miniPlayerPost == nil ? 12 : 72)
                }
            }
        }
    }

    @ViewBuilder
    private var libraryEmptyState: some View {
        switch librarySection {
        case .history:
            ContentUnavailableView(
                "Nothing in history yet",
                systemImage: "clock",
                description: Text("Videos you watch will appear here.")
            )
        case .reels:
            playLibraryEmptyState(
                title: "No saved \(MatteryaCopy.sparks.lowercased())",
                icon: "sparkles",
                message: MatteryaCopy.saveSparksHint,
                buttonTitle: MatteryaCopy.browseSparks
            ) {
                queueLibrarySparkPlayback(starting: playReels.first, seed: playReels)
            }
        case .watchLater:
            playLibraryEmptyState(
                title: "No saved videos",
                icon: "bookmark",
                message: "Tap Save on any video to watch later.",
                buttonTitle: MatteryaCopy.exploreHubs
            ) {
                showLibrary = false
            }
        case .liked:
            ContentUnavailableView(
                "No liked videos",
                systemImage: "hand.thumbsup",
                description: Text("Like videos while watching to collect them here.")
            )
        case .uploads:
            playLibraryEmptyState(
                title: "No uploads yet",
                icon: "film",
                message: "Publish a long-form video or \(MatteryaCopy.spark.lowercased()) from the create menu.",
                buttonTitle: "Create video"
            ) {
                Task { await appState.presentCreateSheet(.video) }
            }
        }
    }

    private func playLibraryEmptyState(
        title: String,
        icon: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView(title, systemImage: icon, description: Text(message))
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentBright)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.pagePadding)
    }

    private var continueWatchingStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            hubsSectionHeader("Continue watching")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(continueWatching) { post in
                        MatteryaHubVideoCard(post: post, width: 152, onTap: { openVideo(post) })
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    private var libraryVideos: [CountryPost] {
        switch librarySection {
        case .history:
            return catalog.historyVideos(from: allVideos)
        case .reels:
            var savedReels = appState.savedReelPosts
            let uploads = catalog.myUploads(allVideos, userID: appState.currentProfile?.userID).filter(\.isReel)
            for post in uploads where !savedReels.contains(where: { $0.id == post.id }) {
                savedReels.append(post)
            }
            return savedReels
        case .watchLater:
            return appState.savedVideoPosts
        case .liked:
            return catalog.likedVideos(allVideos)
        case .uploads:
            return catalog.myUploads(allVideos, userID: appState.currentProfile?.userID)
        }
    }

    private func loadVideos(forceRefresh: Bool) async {
        let hadCachedCatalog = !allVideos.isEmpty
        if allVideos.isEmpty, let cached = ContentCache.shared.posts(for: .livingVideos) {
            allVideos = BlockService.shared.filterPosts(cached)
            rebuildChannels()
            isLoading = false
        }
        if allVideos.isEmpty { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }

        var videos = await PostsService.shared.loadPlayCatalog(
            forceRefresh: forceRefresh,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs
        )
        if videos.isEmpty {
            videos = await PostsService.shared.loadPlayCatalog(
                forceRefresh: true,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs
            )
        }
        for saved in appState.savedVideoPosts + appState.savedReelPosts where !videos.contains(where: { $0.id == saved.id }) {
            videos.insert(saved, at: 0)
        }
        let filtered = BlockService.shared.filterPosts(videos)
        if filtered.isEmpty, !hadCachedCatalog, allVideos.isEmpty {
            errorMessage = MatteryaCopy.hubsLoadError
            return
        }
        if filtered.isEmpty {
            // Keep locally inserted uploads while the server catalog catches up.
        } else {
            let filteredIDs = Set(filtered.map(\.id))
            let localOnly = allVideos.filter { !filteredIDs.contains($0.id) }
            allVideos = localOnly + filtered
        }
        rebuildChannels()
        await loadChannelProfiles()
        await loadFollowerCounts()
    }

    private func rebuildChannels() {
        var profiles = channelProfiles
        if let me = appState.currentProfile {
            profiles[me.userID] = me
        }
        channels = catalog.buildChannels(from: allVideos, profiles: profiles)
    }

    private func loadChannelProfiles() async {
        var profiles = channelProfiles
        if let me = appState.currentProfile {
            profiles[me.userID] = me
        }

        let authorIDs = Array(Set(channels.map(\.authorID))).prefix(48)
        await withTaskGroup(of: (String, Profile?).self) { group in
            for authorID in authorIDs where profiles[authorID] == nil {
                group.addTask {
                    let profile = try? await ProfileService.shared.profileByID(authorID)
                    return (authorID, profile)
                }
            }
            for await (authorID, profile) in group {
                if let profile {
                    profiles[authorID] = profile
                }
            }
        }

        channelProfiles = profiles
        channels = catalog.buildChannels(from: allVideos, profiles: profiles)
    }

    private func loadFollowerCounts() async {
        var counts = followerCounts
        await withTaskGroup(of: (String, Int).self) { group in
            for channel in channels {
                group.addTask {
                    let result = await FollowService.shared.counts(userID: channel.authorID)
                    return (channel.authorID, result.followers)
                }
            }
            for await (authorID, count) in group {
                counts[authorID] = count
            }
        }
        followerCounts = counts
    }

    private func applyPendingPlayTab(_ tab: YouTubeMainTab) {
        switch tab {
        case .home:
            break
        case .subscriptions:
            scrollToSubscriptions = true
        case .library:
            librarySection = .history
            showLibrary = true
        }
    }

    private func consumePendingRoutingIfNeeded() async {
        if let tab = appState.pendingPlayTab {
            applyPendingPlayTab(tab)
            appState.pendingPlayTab = nil
        }
        if let id = appState.pendingLivingVideoID {
            await openVideo(id: id)
        }
        await consumePendingChannelIfNeeded()
    }

    private func consumePendingChannelIfNeeded() async {
        let authorID = appState.pendingPlayChannelAuthorID
        let username = appState.pendingPlayChannelUsername
        guard authorID != nil || username != nil else { return }

        if allVideos.isEmpty {
            await loadVideos(forceRefresh: false)
        }

        if let authorID {
            appState.pendingPlayChannelAuthorID = nil
            await openChannel(authorID: authorID)
            return
        }

        if let username {
            appState.pendingPlayChannelUsername = nil
            if let profile = try? await ProfileService.shared.profileByUsername(username) {
                await openChannel(authorID: profile.userID)
            } else {
                appState.showToast("Creator @\(username) wasn’t found.", style: .error)
            }
        }
    }

    private func openChannel(authorID: String) async {
        if let channel = catalog.channel(for: authorID, in: channels) {
            openChannel(channel)
            return
        }

        let posts = (try? await PostsService.shared.listForAuthor(authorID, limit: 40)) ?? []
        let eligible = posts.filter { catalog.livingEligible($0) }
        if let built = catalog.buildChannels(from: eligible).first(where: { $0.authorID == authorID }) {
            if !allVideos.contains(where: { $0.authorID == authorID }) {
                allVideos.insert(contentsOf: eligible, at: 0)
                rebuildChannels()
            }
            openChannel(built)
        } else {
            appState.showToast(MatteryaCopy.hubsNoChannelVideos, style: .info)
        }
    }

    private func openFromLibrary(_ post: CountryPost) {
        let section = librarySection
        let sectionVideos = libraryVideos
        let asSpark = shouldOpenAsSpark(post, in: section)
        let sparkSeed = librarySparkSeed(for: section, videos: sectionVideos)
        pendingLibraryPlayback = LibraryPlaybackRequest(
            post: post,
            asSpark: asSpark,
            sparkSeed: sparkSeed
        )
        showLibrary = false
    }

    private func queueLibrarySparkPlayback(starting post: CountryPost?, seed: [CountryPost]) {
        guard let post else { return }
        pendingLibraryPlayback = LibraryPlaybackRequest(
            post: post,
            asSpark: true,
            sparkSeed: seed
        )
        showLibrary = false
    }

    private func consumePendingLibraryPlayback() {
        guard let pending = pendingLibraryPlayback else { return }
        pendingLibraryPlayback = nil
        if pending.asSpark {
            openReelsPlayback(starting: pending.post, seed: pending.sparkSeed)
        } else {
            openVideo(pending.post)
        }
    }

    private func shouldOpenAsSpark(_ post: CountryPost, in section: YouTubeLibrarySection) -> Bool {
        switch section {
        case .reels:
            return true
        case .uploads:
            return post.isReel || appState.reelPresentationSavedIDs.contains(post.id)
        default:
            return post.isReel
        }
    }

    private func librarySparkSeed(for section: YouTubeLibrarySection, videos: [CountryPost]) -> [CountryPost] {
        switch section {
        case .reels:
            return videos
        case .uploads:
            return videos.filter {
                $0.isReel || appState.reelPresentationSavedIDs.contains($0.id)
            }
        default:
            return playReels
        }
    }

    private func openVideo(_ post: CountryPost) {
        if post.isReel {
            openReelsPlayback(starting: post, seed: playReels)
            return
        }
        miniPlayerPost = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            route = .watch(post)
        }
    }

    private func openReelsPlayback(starting post: CountryPost?, seed: [CountryPost]? = nil) {
        guard let post else { return }
        miniPlayerPost = nil
        route = nil
        appState.openReelsViewer(startingPost: post, seedPosts: seed ?? playReels)
    }

    private func openVideo(id: String) async {
        appState.clearPendingLivingVideo()
        if let cached = allVideos.first(where: { $0.id == id }) {
            openVideo(cached)
            return
        }
        if allVideos.isEmpty {
            await loadVideos(forceRefresh: false)
            if let cached = allVideos.first(where: { $0.id == id }) {
                openVideo(cached)
                return
            }
        }
        if let fetched = try? await PostsService.shared.getPostByID(id), fetched.hasVideo {
            if !allVideos.contains(where: { $0.id == fetched.id }) {
                allVideos.insert(fetched, at: 0)
                rebuildChannels()
            }
            openVideo(fetched)
        } else {
            appState.showToast(MatteryaCopy.hubsVideoUnavailable, style: .error)
        }
    }

    private func openChannel(_ channel: YouTubeChannel) {
        withAnimation(.easeInOut(duration: 0.2)) {
            route = .channel(channel)
        }
    }

    private func closeWatch(minimize: Bool) {
        if minimize, case .watch(let post) = route {
            miniPlayerPost = post
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            route = nil
        }
    }
}

private struct YouTubeSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var query: String
    let videos: [CountryPost]
    let channels: [YouTubeChannel]
    let onSelectVideo: (CountryPost) -> Void
    let onSelectChannel: (YouTubeChannel) -> Void

    @State private var remoteVideos: [CountryPost] = []
    @State private var remoteChannels: [YouTubeChannel] = []
    @State private var isSearchingRemote = false

    private var displayVideos: [CountryPost] {
        videos.isEmpty ? remoteVideos : videos
    }

    private var displayChannels: [YouTubeChannel] {
        channels.isEmpty ? remoteChannels : channels
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearchingRemote {
                    HStack {
                        Spacer()
                        ProgressView().tint(Theme.accentBright)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                if !displayChannels.isEmpty {
                    Section(MatteryaCopy.creators) {
                        ForEach(displayChannels) { channel in
                            Button {
                                onSelectChannel(channel)
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(url: channel.author?.avatarURL, seed: channel.authorID, size: 48)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(channel.title)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text(channel.handle ?? "\(channel.videoCount) videos")
                                            .font(.caption)
                                            .foregroundStyle(Theme.inkMuted)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !displayVideos.isEmpty {
                    Section("Videos") {
                        ForEach(displayVideos) { post in
                            Button {
                                onSelectVideo(post)
                            } label: {
                                YouTubeVideoMetadataRow(post: post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(MatteryaCopy.searchHubs, systemImage: "magnifyingglass", description: Text(MatteryaCopy.searchHubsHint))
                } else if displayChannels.isEmpty && displayVideos.isEmpty, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSearchingRemote {
                    ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Try another search term."))
                }
            }
            .searchable(text: $query, prompt: MatteryaCopy.searchHubs)
            .navigationTitle("Search")
            .task(id: query) {
                await searchRemoteIfNeeded()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func searchRemoteIfNeeded() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, videos.isEmpty, channels.isEmpty else {
            remoteVideos = []
            remoteChannels = []
            isSearchingRemote = false
            return
        }

        isSearchingRemote = true
        defer { isSearchingRemote = false }

        let posts = (try? await PostsService.shared.searchPosts(trimmed, limit: 24)) ?? []
        let eligible = posts.filter { YouTubeCatalogService.shared.livingEligible($0) }
        remoteVideos = eligible.filter { !$0.isReel }
        remoteChannels = YouTubeCatalogService.shared.buildChannels(from: eligible)
    }
}