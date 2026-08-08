import SwiftUI

private enum YouTubeRoute: Equatable {
    case watch(CountryPost)
    case channel(YouTubeChannel)
    /// In-app library (History / Sparks / Saved / Liked / Uploads) — not a modal sheet.
    case library
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
    @State private var showSearch = false
    @State private var scrollToSubscriptions = false
    @State private var searchQuery = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Shuffled Sparks rail — refreshed every Hubs open / tab return / catalog reload.
    @State private var sparksStrip: [CountryPost] = []
    /// Stable For you / shelf rows — rebuilt only when catalog or filter changes (not every frame).
    @State private var stableHomeVideos: [CountryPost] = []
    @State private var stableDiscoverVideos: [CountryPost] = []
    @State private var homeListEpoch: Int = 0

    private enum PlayScrollAnchor {
        static let subscriptions = "play-subscriptions"
    }

    private let catalog = YouTubeCatalogService.shared

    private var playReels: [CountryPost] { catalog.reels(from: allVideos) }

    private var continueWatching: [CountryPost] {
        Array(catalog.historyVideos(from: allVideos).filter { !$0.isReel }.prefix(8))
    }

    private var homeVideos: [CountryPost] {
        stableHomeVideos
    }

    private var discoverVideos: [CountryPost] {
        stableDiscoverVideos
    }

    /// Build home/discover lists once per catalog or chip change. Never reshuffle mid-scroll.
    private func rebuildStableHomeLists(shuffleForYou: Bool = true) {
        let filtered = catalog.filterVideos(
            allVideos,
            homeFilter: homeFilter,
            followingIDs: appState.followingIDs,
            viewerCountry: appState.currentProfile?.countryCode
        )
        var home = filtered
        // Always prefer long-form for the main list (Sparks stay on the Sparks strip).
        if homeFilter == .all {
            let longForm = allVideos.filter {
                !$0.isReel && !$0.isStory
                    && ($0.hasVideo || $0.playableVideoURL != nil)
                    && (PlayPlatformBridge.belongsInHubsCatalog($0)
                        || PlayPlatformBridge.isHubChannelUpload($0)
                        || PlayPlatformBridge.isHubOriginShare($0))
            }
            if longForm.count > home.filter({ !$0.isReel }).count {
                home = longForm
            } else if home.isEmpty {
                home = longForm
            } else {
                // Drop reels from For you grid — they already have a strip.
                let onlyLong = home.filter { !$0.isReel }
                if !onlyLong.isEmpty { home = onlyLong }
            }
        }
        if homeFilter == .all, shuffleForYou, home.count > 1 {
            home = home.shuffled()
        }
        stableHomeVideos = home

        if homeFilter == .all, !subscriptionVideos.isEmpty {
            let subscriptionIDs = Set(subscriptionVideos.map(\.id))
            let rest = home.filter { !subscriptionIDs.contains($0.id) }
            stableDiscoverVideos = rest.count >= 12 ? rest : home
        } else {
            stableDiscoverVideos = home
        }
        homeListEpoch &+= 1
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

    /// Mini session is owned by `GlobalHubPlaybackLayer` (any tab).
    private var isMiniPlayback: Bool {
        appState.hubPlaybackPost != nil && !appState.hubPlaybackExpanded
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if route == nil {
                    YouTubeAppHeader(
                        onSearch: { showSearch = true }
                    )
                }

                Group {
                    switch route {
                    case .watch(let post):
                        // Video is drawn by GlobalHubPlaybackLayer — reserve stage + meta only.
                        // Origin shares present the original channel, never the feed sharer.
                        // hubPlaybackPost is already catalog-resolved when opened from feed share.
                        let watchPost = PlayPlatformBridge.hubWatchPresentation(for: post)
                        YouTubeWatchView(
                            post: watchPost,
                            channel: channelForWatch(watchPost),
                            related: catalog.relatedVideos(to: watchPost, from: allVideos, limit: 400),
                            // Raw base — views resolve live via AppState.followFollowerDeltas.
                            subscriberCount: followerCounts[watchPost.authorID],
                            embedsPlayer: false,
                            onBack: { closeWatch(minimize: true) },
                            onOpenVideo: { openVideo($0) },
                            onOpenChannel: { openChannel($0) }
                        )
                    case .channel(let channel):
                        YouTubeChannelView(
                            channel: channel,
                            // Raw base — channel resolves live so Follow updates the count.
                            subscriberCount: followerCounts[channel.authorID],
                            onBack: { route = nil },
                            onOpenVideo: { openVideo($0) }
                        )
                        // Fill width inside GeometryReader so channel chrome isn't side-cropped.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    case .library:
                        libraryScreen
                    case nil:
                        mainContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Use max frame, not rigid geo size — rigid width was cropping channel chrome L/R.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: geo.size.width > 0 ? geo.size.width : nil,
                   height: geo.size.height > 0 ? geo.size.height : nil)
        }
        .animation(.easeInOut(duration: 0.2), value: appState.hubPlaybackPost?.id)
        .animation(.easeInOut(duration: 0.2), value: appState.hubPlaybackExpanded)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await loadVideos(forceRefresh: true, mode: .full)
            await reshuffleSparksStrip()
        }
        .task(id: appState.contentLoadGeneration) {
            await consumePendingLivingVideoIfNeeded()
            // 1) Instant paint (session / disk) — never blocks.
            paintInstantHubsIfPossible()
            // 2) Fast network only if still thin (never blocks a warm session).
            if allVideos.filter({ !$0.isReel }).count < 8 {
                await loadVideos(forceRefresh: false, mode: .fast)
            } else {
                isLoading = false
            }
            await reshuffleSparksStrip()
            await consumePendingRoutingIfNeeded()
            // 3) ALWAYS load full channel catalogs (all longform + sparks) in background.
            Task(priority: .utility) {
                await loadVideos(forceRefresh: false, mode: .full)
                await reshuffleSparksStrip()
            }
        }
        .onAppear {
            paintInstantHubsIfPossible()
            syncRouteFromHubSession()
            Task { await consumePendingLivingVideoIfNeeded() }
            if appState.selectedTab == .hubs {
                EngagementTracker.shared.hubsOpened()
                Task {
                    if allVideos.isEmpty {
                        await loadVideos(forceRefresh: false, mode: .fast)
                    }
                    await reshuffleSparksStrip()
                    warmSlugShelvesInBackground()
                }
            }
        }
        .onChange(of: appState.selectedTab) { _, tab in
            guard tab == .hubs else { return }
            EngagementTracker.shared.hubsOpened()
            paintInstantHubsIfPossible()
            isLoading = false
            Task {
                // Re-open: session/memory only — skip network if warm.
                if allVideos.filter({ !$0.isReel }).count < 8 {
                    await loadVideos(forceRefresh: false, mode: .fast)
                }
                await reshuffleSparksStrip()
                warmSlugShelvesInBackground()
            }
        }
        .onChange(of: homeFilter) { _, filter in
            // Rebuild once per chip — shuffle only when returning to For you.
            rebuildStableHomeLists(shuffleForYou: filter == .all)
            // Prefetch the whole slug shelf so category chips feel instant.
            let thumbPx = YouTubeMediaLayout.hubsListThumbMaxPixel
            if let slug = filter.hubSlug {
                ImageCache.shared.prefetchHubSlug(slug, from: allVideos, limit: 60, maxPixelSize: thumbPx)
            } else if filter == .all {
                ImageCache.shared.prefetchPostThumbnails(
                    Array(stableDiscoverVideos.prefix(80)),
                    maxPixelSize: thumbPx,
                    aggressive: true
                )
            }
            EngagementTracker.shared.hubShelfSelected(filter.rawValue)
        }
        .onChange(of: appState.hubPlaybackPost?.id) { _, _ in
            syncRouteFromHubSession()
        }
        .onChange(of: appState.hubPlaybackExpanded) { _, _ in
            syncRouteFromHubSession()
        }
        .onChange(of: appState.pendingLivingVideoID) { _, newID in
            guard newID != nil else { return }
            Task { await consumePendingLivingVideoIfNeeded() }
        }
        .onChange(of: appState.pendingLivingVideo?.id) { _, newID in
            guard newID != nil else { return }
            Task { await consumePendingLivingVideoIfNeeded() }
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
            // Only intentional Hubs channel publishes join the Hubs catalog.
            // Feed shares of Archive/Sparks must never land in For you.
            guard let created = notification.userInfo?["post"] as? CountryPost,
                  catalog.livingEligible(created),
                  PlayPlatformBridge.belongsInHubsCatalog(created),
                  PlayPlatformBridge.isHubChannelUpload(created) || created.isHubSeedVideo,
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
            YouTubeFilterChips(selected: $homeFilter, onLibrary: { openLibrary() })
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
                            ForEach(Array(stableDiscoverVideos.enumerated()), id: \.element.id) { index, post in
                                YouTubeVideoListRow(post: post, onTap: {
                                    openVideo(post)
                                }, onAppearRow: {
                                    // Same maxPixelSize as YouTubeVideoListRow so prefetch hits memory.
                                    ImageCache.shared.prefetchHubsWindow(
                                        posts: stableDiscoverVideos,
                                        around: index,
                                        behind: 8,
                                        ahead: 28,
                                        maxPixelSize: YouTubeMediaLayout.hubsListThumbMaxPixel
                                    )
                                })
                                .padding(.bottom, 18)
                            }
                        }
                        .id(homeListEpoch)
                        .padding(.top, 8)
                        .padding(.bottom, isMiniPlayback ? YouTubeMiniPlayerBar.contentBottomInset : 12)
                    }
                    .scrollDismissesKeyboard(.immediately)
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
        // Full Sparks rail from catalog + strip — not a 10-item toy list.
        let fromCatalog = playReels
        let rail: [CountryPost] = {
            if !sparksStrip.isEmpty { return sparksStrip }
            return Array(fromCatalog.prefix(36))
        }()
        return SparksHorizontalStrip(
            posts: rail,
            onOpen: { post in
                openReelsPlayback(starting: post, seed: rail + fromCatalog)
            },
            onBrandTap: {
                openReelsPlayback(starting: rail.first ?? fromCatalog.first, seed: rail + fromCatalog)
            }
        )
        .id(rail.map(\.id).joined(separator: "|"))
        .onAppear {
            for post in rail.prefix(6) {
                if let url = post.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) {
                    ArchiveVideoPlayback.warmResolve(url)
                }
            }
        }
    }

    /// Sparks rail: prefer channel-owned R2 sparks already in catalog, then network top-up.
    private func reshuffleSparksStrip() async {
        var seen = Set<String>()
        var next: [CountryPost] = []

        // 1) Everything already in the Hubs catalog (channel sparks).
        for post in ReelsRankingEngine.sessionFreshOrder(playReels) {
            guard post.playableVideoURL != nil else { continue }
            guard seen.insert(post.id).inserted else { continue }
            next.append(post)
            if next.count >= 48 { break }
        }

        // 2) Dedicated channel sparks pull if still thin.
        if next.count < 24 {
            let channelSparks = await PostsService.shared.fetchFocusMarketHubSparks(limitPerAuthor: 80)
            for post in ReelsRankingEngine.sessionFreshOrder(channelSparks) {
                guard post.playableVideoURL != nil else { continue }
                guard seen.insert(post.id).inserted else { continue }
                next.append(post)
                if next.count >= 48 { break }
            }
        }

        // 3) General reels feed top-up.
        if next.count < 16 {
            let network = await PostsService.shared.loadReelsFeed(
                globalLimit: 64,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs
            )
            for post in ReelsRankingEngine.sessionFreshOrder(network) {
                guard post.playableVideoURL != nil else { continue }
                guard seen.insert(post.id).inserted else { continue }
                next.append(post)
                if next.count >= 48 { break }
            }
        }

        if next.count < 8 {
            let seed = UInt64.random(in: 1...UInt64.max)
                ^ UInt64(Date().timeIntervalSince1970 * 1_000)
            let seeds = await HubVideoSeedService.shared.sparkSeedVideos(limit: 40, shuffleSeed: seed)
            for post in ReelsRankingEngine.sessionFreshOrder(seeds) where post.playableVideoURL != nil && seen.insert(post.id).inserted {
                next.append(post)
                if next.count >= 48 { break }
            }
        }
        if next.count < 6 {
            let seed = UInt64.random(in: 1...UInt64.max)
            let local = HubCategoryClassifier.shuffled(playReels, seed: seed &+ 9)
            for post in local where post.playableVideoURL != nil && seen.insert(post.id).inserted {
                next.append(post)
                if next.count >= 48 { break }
            }
        }
        next.shuffle()
        await MainActor.run {
            // Merge strip sparks into the main catalog so full-screen Sparks has the rest.
            if !next.isEmpty {
                var byID = Dictionary(uniqueKeysWithValues: allVideos.map { ($0.id, $0) })
                for post in next { byID[post.id] = post }
                let merged = Array(byID.values)
                allVideos = merged
                PostsService.shared.rememberHubsSessionCatalog(merged)
                rebuildChannels()
            }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { sparksStrip = next }
            ImageCache.shared.prefetchFeedMedia(Array(next.prefix(16)), maxPixelSize: 320)
            SparkWarmPool.shared.prepare(posts: Array(next.prefix(12)), around: 0, ahead: 3, behind: 0)
        }
    }

    /// Full-screen library inside Hubs (same pattern as channel / watch — not a bottom sheet).
    private var libraryScreen: some View {
        VStack(spacing: 0) {
            libraryTopBar

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(YouTubeLibrarySection.allCases) { section in
                        Button {
                            librarySection = section
                        } label: {
                            // Text-only chips — fixed height so selection never resizes the bar.
                            Text(section.title)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .pillTab(isSelected: librarySection == section)
                    }
                }
                .frame(height: 40)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 4)
            }
            .frame(height: 48)
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
                            // 3 equal columns, each cell locked to 9:16 — no size jitter.
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(minimum: 0), spacing: 8),
                                    count: 3
                                ),
                                alignment: .center,
                                spacing: 8
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
                    .padding(.top, 8)
                    .padding(.bottom, isMiniPlayback ? YouTubeMiniPlayerBar.contentBottomInset : 12)
                }
            }
        }
        .background(Theme.canvas)
    }

    private var libraryTopBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    route = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface.opacity(0.94), in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Library")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
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
                if let first = playReels.first {
                    openReelsPlayback(starting: first, seed: playReels)
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) { route = nil }
                }
            }
        case .watchLater:
            playLibraryEmptyState(
                title: "No saved videos",
                icon: "bookmark",
                message: "Tap Save on any video to watch later.",
                buttonTitle: MatteryaCopy.exploreHubs
            ) {
                withAnimation(.easeInOut(duration: 0.18)) { route = nil }
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
                HStack(alignment: .top, spacing: 12) {
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

    // MARK: - Instant first paint (slug shelves)

    private enum HubsLoadMode {
        /// 4 longform channels only — first paint network path.
        case fast
        /// Sparks + deeper longform — background / pull-to-refresh.
        case full
    }

    /// Synchronous paint from session memory or ContentCache — never waits on network.
    private func paintInstantHubsIfPossible() {
        guard allVideos.isEmpty else {
            isLoading = false
            return
        }

        // 1) Session memory (same launch, re-open Hubs tab).
        var source = PostsService.shared.hubsSessionCatalog
        // 2) Disk/memory cache (stale OK).
        if source.isEmpty {
            source = ContentCache.shared.posts(for: .livingVideos) ?? []
        }
        guard !source.isEmpty else { return }

        let filtered = BlockService.shared.filterPosts(source).filter { post in
            if !AppConfig.archiveContentEnabled, post.isHubSeedVideo { return false }
            return post.hasVideo || post.playableVideoURL != nil
        }
        let capped = Self.slugCappedFirstPaint(filtered, perSlug: 14)
        guard !capped.isEmpty else { return }
        applyHubCatalog(capped, shuffleForYou: true, persist: false)
        isLoading = false
        errorMessage = nil
        butterWarmHubCatalog(capped)
        #if DEBUG
        print("[Hubs] instant paint count=\(capped.count) session=\(PostsService.shared.hubsSessionIsWarm())")
        #endif
    }

    /// Interleave long-form by hub_slug / parent category so every chip has content on first paint.
    /// Uses the same slug set as TF shelves: social, travel, nature, music, …
    private static func slugCappedFirstPaint(_ posts: [CountryPost], perSlug: Int = 12) -> [CountryPost] {
        let order = HubVideoSeedService.hubOrder
        var buckets: [String: [CountryPost]] = [:]
        var sparks: [CountryPost] = []
        for post in posts {
            if post.isReel {
                if sparks.count < 28 { sparks.append(post) }
                continue
            }
            guard post.hasVideo || post.playableVideoURL != nil else { continue }
            let parent = resolvedHubParentSlug(for: post)
            guard (buckets[parent]?.count ?? 0) < perSlug else { continue }
            buckets[parent, default: []].append(post)
        }

        // Round-robin across hubOrder so For you is diverse and chips aren't empty.
        var out: [CountryPost] = []
        var seen = Set<String>()
        var depth = 0
        var progressed = true
        while progressed && depth < perSlug {
            progressed = false
            for slug in order {
                let list = buckets[slug] ?? []
                guard depth < list.count else { continue }
                let post = list[depth]
                if seen.insert(post.id).inserted {
                    out.append(post)
                    progressed = true
                }
            }
            depth += 1
        }
        // Leftovers (unknown slugs / overflow).
        for slug in order {
            for post in buckets[slug] ?? [] where seen.insert(post.id).inserted {
                out.append(post)
            }
        }
        for (slug, list) in buckets where !order.contains(slug) {
            for post in list where seen.insert(post.id).inserted {
                out.append(post)
            }
        }
        out.append(contentsOf: sparks.filter { seen.insert($0.id).inserted })
        return out
    }

    /// Resolve shelf slug: explicit hub_slug / externalRefID, else classify title/body.
    private static func resolvedHubParentSlug(for post: CountryPost) -> String {
        if let raw = (post.hubSlug ?? post.externalRefID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !raw.isEmpty {
            return HubCategoryClassifier.parentCategory(of: raw)
        }
        return HubCategoryClassifier.classify(
            title: post.title,
            body: post.body,
            tags: [],
            creator: post.author?.displayName,
            seedSlug: nil
        )
    }

    private func applyHubCatalog(
        _ videos: [CountryPost],
        shuffleForYou: Bool,
        persist: Bool
    ) {
        allVideos = videos
        if persist, !videos.isEmpty {
            ContentCache.shared.setPosts(
                Array(videos.prefix(ContentCache.maxCachedPosts)),
                for: .livingVideos
            )
        }
        rebuildChannels()
        rebuildStableHomeLists(shuffleForYou: shuffleForYou)
    }

    private func warmSlugShelvesInBackground() {
        let videos = allVideos
        guard !videos.isEmpty else { return }
        let thumbPx = YouTubeMediaLayout.hubsListThumbMaxPixel
        Task.detached(priority: .utility) {
            for slug in HubVideoSeedService.hubOrder {
                ImageCache.shared.prefetchHubSlug(slug, from: videos, limit: 24, maxPixelSize: thumbPx)
            }
        }
    }

    private func loadVideos(forceRefresh: Bool, mode: HubsLoadMode = .full) async {
        // Never blank an already-painted catalog with a full-screen spinner.
        if allVideos.isEmpty { isLoading = true }
        errorMessage = nil

        let longFormNow = allVideos.filter { !$0.isReel }.count
        let sparksNow = allVideos.filter(\.isReel).count
        // Warm UI: skip network when we already have enough for this mode.
        if !forceRefresh {
            if mode == .fast, longFormNow >= 8 {
                isLoading = false
                butterWarmHubCatalog(allVideos)
                #if DEBUG
                print("[Hubs] skip FAST network — \(longFormNow) longform")
                #endif
                return
            }
            // Full catalog only skip when we already have a rich R2 session.
            if mode == .full, longFormNow >= 200, sparksNow >= 24 {
                isLoading = false
                butterWarmHubCatalog(allVideos)
                warmSlugShelvesInBackground()
                Task(priority: .utility) {
                    await loadChannelProfiles()
                    await loadFollowerCounts()
                }
                #if DEBUG
                print("[Hubs] skip FULL network — \(longFormNow) longform \(sparksNow) sparks")
                #endif
                return
            }
        }
        if !forceRefresh,
           PostsService.shared.hubsSessionIsWarm(),
           allVideos.isEmpty {
            paintInstantHubsIfPossible()
            if !allVideos.isEmpty {
                isLoading = false
                if mode == .fast { return }
            }
        }

        var byID: [String: CountryPost] = Dictionary(
            uniqueKeysWithValues: allVideos.map { ($0.id, $0) }
        )

        // Network: FAST = longform only; FULL = every R2 longform + channel sparks.
        let network = await PostsService.shared.loadPlayCatalog(
            globalLimit: forceRefresh ? 500 : (mode == .fast ? 32 : 500),
            forceRefresh: forceRefresh,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            fast: mode == .fast && !forceRefresh
        )
        for post in network {
            if PlayPlatformBridge.isFeedOnlyShare(post),
               !PlayPlatformBridge.isHubOriginShare(post) {
                continue
            }
            guard PlayPlatformBridge.belongsInHubsCatalog(post)
                || PlayPlatformBridge.isHubChannelUpload(post)
                || PlayPlatformBridge.isHubOriginShare(post)
            else { continue }
            byID[post.id] = post
        }

        if mode == .full || forceRefresh {
            for saved in appState.savedVideoPosts + appState.savedReelPosts {
                if PlayPlatformBridge.isFeedOnlyShare(saved) { continue }
                if PlayPlatformBridge.belongsInHubsCatalog(saved), byID[saved.id] == nil {
                    byID[saved.id] = saved
                }
            }
        }

        var videos = BlockService.shared.filterPosts(Array(byID.values))
        if !AppConfig.archiveContentEnabled {
            videos = videos.excludingArchiveContent()
        }

        // Never do a second heavy longform pull on the fast path — that was the multi-second hang.
        isLoading = false

        if videos.isEmpty, allVideos.isEmpty {
            errorMessage = MatteryaCopy.hubsLoadError
            return
        }

        if !videos.isEmpty {
            let painted = Self.slugCappedFirstPaint(videos, perSlug: mode == .fast ? 12 : 20)
            var ordered = painted
            var seen = Set(painted.map(\.id))
            for post in videos where seen.insert(post.id).inserted {
                ordered.append(post)
            }
            let shouldShuffle = homeFilter == .all && (forceRefresh || allVideos.isEmpty)
            applyHubCatalog(ordered, shuffleForYou: shouldShuffle, persist: true)
            PostsService.shared.rememberHubsSessionCatalog(ordered)
        }

        #if DEBUG
        let longForm = allVideos.filter { !$0.isReel }.count
        print("[Hubs] applied mode=\(mode) longForm=\(longForm) total=\(allVideos.count) force=\(forceRefresh)")
        #endif
        butterWarmHubCatalog(allVideos)

        if mode == .full || forceRefresh {
            Task(priority: .utility) {
                await loadChannelProfiles()
                await loadFollowerCounts()
            }
        }
    }

    /// Prefetch posters only — keep this light so it never competes with first paint.
    private func butterWarmHubCatalog(_ videos: [CountryPost]) {
        let thumbPx = YouTubeMediaLayout.hubsListThumbMaxPixel
        let head = stableDiscoverVideos.isEmpty
            ? videos.filter { !$0.isReel && $0.playableVideoURL != nil }
            : stableDiscoverVideos
        // First screen only (~12 rows) — was 120 and flooded the network.
        ImageCache.shared.prefetchPostThumbnails(
            Array(head.prefix(16)),
            maxPixelSize: thumbPx,
            aggressive: true
        )
        ImageCache.shared.prefetchPostThumbnails(
            Array(catalog.historyVideos(from: videos).prefix(6)),
            maxPixelSize: thumbPx,
            aggressive: true
        )
        // Defer slug shelf + sparks warm so For you paints first.
        Task(priority: .utility) {
            for slug in HubVideoSeedService.hubOrder.prefix(4) {
                ImageCache.shared.prefetchHubSlug(slug, from: videos, limit: 8, maxPixelSize: thumbPx)
            }
            let sparks = videos.filter(\.isReel)
            if !sparks.isEmpty {
                SparkWarmPool.shared.prepare(posts: Array(sparks.prefix(6)), around: 0, ahead: 2, behind: 0)
            }
        }
    }

    private func rebuildChannels() {
        var profiles = channelProfiles
        if let me = appState.currentProfile {
            profiles[me.userID] = me
        }
        // Strip feed-only shares only — NEVER drop ia_* / Archive seed rows.
        allVideos = allVideos.filter { post in
            let id = post.id.lowercased()
            if post.isHubSeedVideo
                || HubVideoSeedService.isArchiveChannelAuthor(post.authorID)
                || id.hasPrefix("ia_")
                || id.hasPrefix("hub_spark_") {
                return true
            }
            return PlayPlatformBridge.belongsInHubsCatalog(post)
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
        var loadedIDs: [String] = []
        await withTaskGroup(of: (String, Int).self) { group in
            for channel in channels {
                group.addTask {
                    let result = await FollowService.shared.counts(userID: channel.authorID)
                    return (channel.authorID, result.followers)
                }
            }
            for await (authorID, count) in group {
                counts[authorID] = count
                loadedIDs.append(authorID)
            }
        }
        followerCounts = counts
        // Fresh bases — drop optimistic deltas so we don't double-count.
        appState.clearFollowerCountDeltas(for: loadedIDs)
    }

    private func applyPendingPlayTab(_ tab: YouTubeMainTab) {
        switch tab {
        case .home:
            break
        case .subscriptions:
            scrollToSubscriptions = true
        case .library:
            openLibrary(section: .history)
        }
    }

    private func openLibrary(section: YouTubeLibrarySection = .history) {
        librarySection = section
        withAnimation(.easeInOut(duration: 0.18)) {
            route = .library
        }
    }

    private func consumePendingRoutingIfNeeded() async {
        if let tab = appState.pendingPlayTab {
            applyPendingPlayTab(tab)
            appState.pendingPlayTab = nil
        }
        await consumePendingLivingVideoIfNeeded()
        await consumePendingChannelIfNeeded()
    }

    /// Opens the pending watch target from feed / notifications.
    /// Prefer the full `pendingLivingVideo` so hub seeds open even before catalog load.
    private func consumePendingLivingVideoIfNeeded() async {
        if let post = appState.pendingLivingVideo {
            appState.clearPendingLivingVideo()
            openVideo(post)
            return
        }
        guard let id = appState.pendingLivingVideoID else { return }
        await openVideo(id: id)
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
        // The Archive (and legacy hub_* seed authors): full catalog as one channel.
        if HubVideoSeedService.isArchiveChannelAuthor(authorID) {
            let allHub = await HubVideoSeedService.shared.allVideos()
            let eligible = allHub.filter(catalog.livingEligible)
            if let built = catalog.buildChannels(from: eligible)
                .first(where: { HubVideoSeedService.isArchiveChannelAuthor($0.authorID) })
                ?? catalog.buildChannels(from: eligible).first
            {
                // Force display name in case mixed legacy ids remain in memory.
                let archive = YouTubeChannel(
                    id: HubVideoSeedService.archiveChannelAuthorID,
                    authorID: HubVideoSeedService.archiveChannelAuthorID,
                    title: HubVideoSeedService.archiveChannelDisplayName,
                    handle: "@\(HubVideoSeedService.archiveChannelUsername)",
                    author: PostAuthor(
                        userID: HubVideoSeedService.archiveChannelAuthorID,
                        displayName: HubVideoSeedService.archiveChannelDisplayName,
                        username: HubVideoSeedService.archiveChannelUsername,
                        avatarURL: nil,
                        countryName: nil,
                        countryCode: nil,
                        lastReadAt: nil
                    ),
                    videos: built.videos,
                    reels: built.reels,
                    hasCustomChannelName: true
                )
                openChannel(archive)
                return
            }
        }

        if let channel = catalog.channel(for: authorID, in: channels),
           !channel.videos.isEmpty || !channel.reels.isEmpty {
            openChannel(channel)
            return
        }

        // Only intentional Hubs channel publishes — feed shares / Archive re-hosts never open a personal channel.
        let posts = (try? await PostsService.shared.listForAuthor(authorID, limit: 40)) ?? []
        let eligible = posts.filter {
            catalog.livingEligible($0)
                && PlayPlatformBridge.isHubChannelUpload($0)
                && !PlayPlatformBridge.isHubFeedReshare($0)
                && !PlayPlatformBridge.isArchiveCatalogMedia($0)
        }
        if let built = catalog.buildChannels(from: eligible).first(where: { $0.authorID == authorID }) {
            if !allVideos.contains(where: {
                $0.authorID == authorID && PlayPlatformBridge.isHubChannelUpload($0)
            }) {
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
        if shouldOpenAsSpark(post, in: section) {
            let seed = librarySparkSeed(for: section, videos: sectionVideos)
            openReelsPlayback(starting: post, seed: seed)
        } else {
            openVideo(post)
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

    /// Keep watch route in sync with the global continuous player session.
    private func syncRouteFromHubSession() {
        if appState.hubPlaybackExpanded, let post = appState.hubPlaybackPost {
            let watchPost = PlayPlatformBridge.hubWatchPresentation(for: post)
            if case .watch(let existing) = route, existing.id == watchPost.id { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                route = .watch(watchPost)
            }
        } else if case .watch = route {
            // Collapse watch → stay in library if we came from there; otherwise home.
            withAnimation(.easeInOut(duration: 0.18)) {
                route = nil
            }
        }
    }

    /// Channel row for watch: catalog match, else synthetic from the post's author
    /// (critical for origin shares so the sharer never appears as the channel).
    private func channelForWatch(_ post: CountryPost) -> YouTubeChannel? {
        // Catalog / Archive clips always show The Archive.
        if post.isHubSeedVideo || HubVideoSeedService.isArchiveChannelAuthor(post.authorID) {
            if let existing = catalog.channel(for: HubVideoSeedService.archiveChannelAuthorID, in: channels)
                ?? catalog.channel(for: post.authorID, in: channels)
            {
                return YouTubeChannel(
                    id: HubVideoSeedService.archiveChannelAuthorID,
                    authorID: HubVideoSeedService.archiveChannelAuthorID,
                    title: HubVideoSeedService.archiveChannelDisplayName,
                    handle: "@\(HubVideoSeedService.archiveChannelUsername)",
                    author: existing.author,
                    videos: existing.videos,
                    reels: existing.reels,
                    hasCustomChannelName: true
                )
            }
            return YouTubeChannel(
                id: HubVideoSeedService.archiveChannelAuthorID,
                authorID: HubVideoSeedService.archiveChannelAuthorID,
                title: HubVideoSeedService.archiveChannelDisplayName,
                handle: "@\(HubVideoSeedService.archiveChannelUsername)",
                author: PostAuthor(
                    userID: HubVideoSeedService.archiveChannelAuthorID,
                    displayName: HubVideoSeedService.archiveChannelDisplayName,
                    username: HubVideoSeedService.archiveChannelUsername,
                    avatarURL: nil,
                    countryName: nil,
                    countryCode: nil,
                    lastReadAt: nil
                ),
                videos: post.isReel ? [] : [post],
                reels: post.isReel ? [post] : [],
                hasCustomChannelName: true
            )
        }
        if let existing = catalog.channel(for: post.authorID, in: channels) {
            return existing
        }
        let title = post.author?.displayName
            ?? post.authorDisplayName
        return YouTubeChannel(
            id: post.authorID,
            authorID: post.authorID,
            title: title,
            handle: post.author?.username.map { "@\($0)" },
            author: post.author,
            videos: [post],
            reels: [],
            hasCustomChannelName: false
        )
    }

    private func openVideo(_ post: CountryPost) {
        Task { @MainActor in
            let watchPost = await PlayPlatformBridge.resolveHubWatchPresentation(for: post)
            EngagementTracker.shared.hubVideoOpened(watchPost)
            if watchPost.isReel {
                openReelsPlayback(starting: watchPost, seed: playReels)
                return
            }
            appState.startHubPlayback(watchPost, expanded: true)
            withAnimation(.easeInOut(duration: 0.2)) {
                route = .watch(watchPost)
            }
        }
    }

    private func openReelsPlayback(starting post: CountryPost?, seed: [CountryPost]? = nil) {
        guard let post else { return }
        appState.stopHubPlayback()
        route = nil
        appState.openReelsViewer(startingPost: post, seedPosts: seed ?? playReels)
    }

    private func openVideo(id: String) async {
        // Resolve first; only clear pending once we actually open (or definitively fail).
        if let cached = allVideos.first(where: { $0.id == id }) {
            appState.clearPendingLivingVideo()
            openVideo(cached)
            return
        }
        // Hub seed / cache without waiting for the full hubs catalog.
        if let hub = await HubVideoSeedService.shared.post(id: id), hub.hasVideo {
            appState.clearPendingLivingVideo()
            if !allVideos.contains(where: { $0.id == hub.id }) {
                allVideos.insert(hub, at: 0)
                rebuildChannels()
            }
            openVideo(hub)
            return
        }
        if let cached = PostsService.shared.cachedPostForDetail(id: id), cached.hasVideo {
            appState.clearPendingLivingVideo()
            openVideo(cached)
            return
        }
        if allVideos.isEmpty {
            await loadVideos(forceRefresh: false)
            if let cached = allVideos.first(where: { $0.id == id }) {
                appState.clearPendingLivingVideo()
                openVideo(cached)
                return
            }
        }
        if let fetched = try? await PostsService.shared.getPostByID(id), fetched.hasVideo {
            appState.clearPendingLivingVideo()
            if !allVideos.contains(where: { $0.id == fetched.id }) {
                allVideos.insert(fetched, at: 0)
                rebuildChannels()
            }
            openVideo(fetched)
        } else {
            appState.clearPendingLivingVideo()
            appState.showToast(MatteryaCopy.hubsVideoUnavailable, style: .error)
        }
    }

    private func openChannel(_ channel: YouTubeChannel) {
        // Leaving watch chrome → keep audio as mini, free the screen for the channel.
        appState.minimizeHubPlayback(returnToChat: false)
        withAnimation(.easeInOut(duration: 0.2)) {
            route = .channel(channel)
        }
    }

    private func closeWatch(minimize: Bool) {
        if minimize {
            // Pull-down / close → if we opened from chat, restore that conversation + dock.
            appState.minimizeHubPlayback(returnToChat: true)
        } else {
            appState.stopHubPlayback()
        }
        withAnimation(.easeInOut(duration: 0.22)) {
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