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
    /// Shuffled Sparks rail — pure random every Hubs visit.
    @State private var sparksStrip: [CountryPost] = []
    /// For you / shelf rows — discovery-ranked (unviewed + following first).
    @State private var stableHomeVideos: [CountryPost] = []
    @State private var stableDiscoverVideos: [CountryPost] = []
    /// Full ranked For you pool (endless scroll grows the display window from this).
    @State private var hubsForYouPool: [CountryPost] = []
    /// How many ranked rows LazyVStack may show (grows on scroll — never ends).
    @State private var hubsDisplayLimit: Int = 28
    @State private var isLoadingMoreHubs = false
    @State private var hubsLoadMoreQueued = false
    /// Session seed for For you mix (new every open / pull / filter).
    @State private var hubsSessionSeed: UInt64 = UInt64.random(in: 1...UInt64.max)
    /// Continue-watching strip order (shuffled subset of history).
    @State private var stableContinueWatching: [CountryPost] = []
    /// Following preview videos (shuffled).
    @State private var stableFollowingVideos: [CountryPost] = []
    @State private var stableFollowingChannels: [YouTubeChannel] = []
    @State private var homeListEpoch: Int = 0
    /// Bumps whenever we intentionally re-roll Hubs surfaces (tab enter / home return).
    @State private var hubsVisitEpoch: Int = 0

    /// First paint window — small LazyVStack; grows on scroll (endless).
    private static let hubsFirstWindow = 20
    private static let hubsGrowBy = 18
    /// Soft memory ceiling — slug pages only; never keep thousands of posts on MainActor.
    private static let hubsCatalogMemoryCap = 240
    /// How many times we re-cycle the ranked pool after the full catalog is shown (endless scroll).
    @State private var hubsEndlessCycle: Int = 0

    private enum PlayScrollAnchor {
        static let subscriptions = "play-subscriptions"
    }

    private let catalog = YouTubeCatalogService.shared

    private var playReels: [CountryPost] { catalog.reels(from: allVideos) }

    private var continueWatching: [CountryPost] {
        if !stableContinueWatching.isEmpty { return stableContinueWatching }
        return Array(catalog.historyVideos(from: allVideos).filter { !$0.isReel }.prefix(8))
    }

    private var homeVideos: [CountryPost] {
        stableHomeVideos
    }

    private var discoverVideos: [CountryPost] {
        stableDiscoverVideos
    }

    /// Pure random for strips only (Continue / Following previews) — not For you.
    private static func pureShuffle<T>(_ items: [T]) -> [T] {
        guard items.count > 1 else { return items }
        var copy = items
        var rng = SystemRandomNumberGenerator()
        copy.shuffle(using: &rng)
        return copy
    }

    /// Rebuild **all** Hubs home surfaces with a fresh discovery mix.
    /// Call on every navigate-to-Hubs / return-to-home / pull-to-refresh.
    private func refreshHubsVisitShuffle(remountList: Bool = true) {
        hubsVisitEpoch &+= 1
        hubsSessionSeed = UInt64.random(in: 1...UInt64.max)
            ^ UInt64(Date().timeIntervalSince1970 * 1_000_000)
        rebuildStableHomeLists(shuffle: true, remountList: remountList)
        rebuildContinueAndFollowingShuffled()
        // Sparks strip is async (network top-up) — fire and forget.
        Task { await reshuffleSparksStrip() }
    }

    /// Build home/discover lists with **slug-shelf algorithm** (YouTube-light).
    /// Ranking runs **off MainActor** so Hubs scroll never freezes on open/chip change.
    private func rebuildStableHomeLists(shuffle: Bool = true, remountList: Bool = true) {
        // Strict long-form only — Sparks live on the Sparks strip, never For you / chips.
        var home = catalog.filterVideos(
            allVideos,
            homeFilter: homeFilter,
            followingIDs: appState.followingIDs,
            viewerCountry: appState.currentProfile?.countryCode
        ).filter { PlayPlatformBridge.isHubsForYouLongForm($0) }

        if home.isEmpty {
            home = allVideos.filter { PlayPlatformBridge.isHubsForYouLongForm($0) }
        }

        if shuffle {
            hubsSessionSeed = UInt64.random(in: 1...UInt64.max)
                ^ UInt64(Date().timeIntervalSince1970 * 1_000)
        }

        // Small cap — UI only needs a window; endless scroll pages more later.
        let rankInput = home.count > 64 ? Array(home.prefix(64)) : home
        let following = appState.followingIDs
        let myID = appState.currentProfile?.userID ?? AuthService.shared.currentUser?.id
        let seed = hubsSessionSeed
        let focus = homeFilter.hubSlug
        let displayLimit = hubsDisplayLimit
        let firstWindow = Self.hubsFirstWindow

        // Fast path for tiny lists (no Task hop).
        if rankInput.count <= 12 {
            let ranked = catalog.rankForYouBySlugs(
                rankInput,
                followingIDs: following,
                myUserID: myID,
                sessionSeed: seed,
                focusSlug: focus
            )
            applyRankedHome(ranked, shuffle: shuffle, remountList: remountList, displayLimit: displayLimit, firstWindow: firstWindow)
            return
        }

        Task { @MainActor in
            let ranked = await Task.detached(priority: .userInitiated) {
                // Catalog service is MainActor — call parentHubSlug-free path via pure copy rank.
                // Use a local pure rank on Sendable posts to avoid MainActor hop inside detach.
                return YouTubeCatalogService.rankForYouBySlugsPure(
                    rankInput,
                    followingIDs: following,
                    myUserID: myID,
                    sessionSeed: seed,
                    focusSlug: focus
                )
            }.value
            applyRankedHome(ranked, shuffle: shuffle, remountList: remountList, displayLimit: displayLimit, firstWindow: firstWindow)
        }
    }

    private func applyRankedHome(
        _ ranked: [CountryPost],
        shuffle: Bool,
        remountList: Bool,
        displayLimit: Int,
        firstWindow: Int
    ) {
        hubsForYouPool = ranked
        var limit = displayLimit
        if shuffle || limit < firstWindow {
            limit = min(firstWindow, max(ranked.count, 0))
        } else {
            limit = min(max(limit, firstWindow), ranked.count)
        }
        hubsDisplayLimit = limit
        let window = Array(ranked.prefix(limit))
        var txn = Transaction()
        txn.disablesAnimations = true
        withTransaction(txn) {
            stableHomeVideos = window
            stableDiscoverVideos = window
        }
        if remountList {
            homeListEpoch &+= 1
        }
    }

    /// Endless For you: grow window, then fetch **next slug page** (never full catalog dump).
    private func ensureMoreForYou(around index: Int) {
        ScrollBudget.noteCellAppear()
        let fling = ScrollBudget.isFlinging
        let growWhenWithin = fling ? 12 : 8
        let growBy = fling ? Self.hubsGrowBy * 2 : Self.hubsGrowBy
        let threshold = max(0, stableDiscoverVideos.count - growWhenWithin)
        guard index >= threshold else { return }

        // 1) Reveal more of the ranked pool (instant).
        if hubsDisplayLimit < hubsForYouPool.count {
            growForYouDisplay(by: growBy, warmThumbs: !fling)
            return
        }

        // 2) Pool exhausted → next slug shelf page (never mid-fling network).
        guard !fling else {
            scheduleSettledHubsTopUp()
            return
        }
        Task { @MainActor in
            await loadMoreActiveShelf()
            // If shelf API empty, fall back to legacy modest top-up once.
            if hubsDisplayLimit >= hubsForYouPool.count {
                requestMoreHubsLongForm()
            }
        }
    }

    private func growForYouDisplay(by growBy: Int, warmThumbs: Bool) {
        hubsDisplayLimit = min(
            hubsForYouPool.count,
            hubsDisplayLimit + max(growBy, Self.hubsGrowBy)
        )
        let window = Array(hubsForYouPool.prefix(hubsDisplayLimit))
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            stableHomeVideos = window
            stableDiscoverVideos = window
        }
        if warmThumbs {
            ImageCache.shared.prefetchPostThumbnails(
                Array(window.suffix(Self.hubsGrowBy)),
                maxPixelSize: YouTubeMediaLayout.hubsListThumbMaxPixel,
                aggressive: false
            )
        }
    }

    private func scheduleSettledHubsTopUp() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !ScrollBudget.isFlinging else { return }
            guard hubsDisplayLimit >= hubsForYouPool.count else { return }
            requestMoreHubsLongForm()
        }
    }

    private func requestMoreHubsLongForm() {
        if isLoadingMoreHubs {
            hubsLoadMoreQueued = true
            return
        }
        Task { await loadMoreHubsLongForm() }
    }

    private func loadMoreHubsLongForm() async {
        if isLoadingMoreHubs {
            hubsLoadMoreQueued = true
            return
        }
        isLoadingMoreHubs = true
        defer {
            isLoadingMoreHubs = false
            if hubsLoadMoreQueued {
                hubsLoadMoreQueued = false
                Task { await loadMoreHubsLongForm() }
            }
        }

        let beforeLong = allVideos.filter { PlayPlatformBridge.isHubsForYouLongForm($0) }.count
        var added = 0

        // A) Next slug shelf page (primary — light).
        let page: SlugShelfStore.Page
        if let slug = homeFilter.hubSlug {
            page = await SlugShelfStore.shared.loadMoreShelf(slug)
        } else {
            page = await SlugShelfStore.shared.loadMoreForYou()
        }
        if !page.items.isEmpty {
            let existing = Set(allVideos.map(\.id))
            let fresh = page.items.filter {
                existing.contains($0.id) == false
                    && (PlayPlatformBridge.isHubsForYouLongForm($0) || $0.hasVideo)
            }
            if !fresh.isEmpty {
                softMergeHubCatalog(fresh)
                added += fresh.count
            }
        }

        // B) Still empty → one modest legacy page (never 500×channels).
        if added == 0 {
            let more = await PostsService.shared.loadPlayCatalog(
                globalLimit: 40,
                forceRefresh: false,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs,
                fast: true
            )
            if !more.isEmpty {
                let existing = Set(allVideos.map(\.id))
                let fresh = more.filter {
                    existing.contains($0.id) == false
                        && PlayPlatformBridge.isHubsForYouLongForm($0)
                }
                if !fresh.isEmpty {
                    softMergeHubCatalog(Array(fresh.prefix(24)))
                    added += min(fresh.count, 24)
                }
            }
        }

        // C) Still nothing new → recycle ranked pool so scroll is endless.
        if added == 0, hubsDisplayLimit >= hubsForYouPool.count {
            appendEndlessRecyclePage()
        } else if hubsDisplayLimit < hubsForYouPool.count {
            growForYouDisplay(by: Self.hubsGrowBy, warmThumbs: true)
        }

        #if DEBUG
        let afterLong = allVideos.filter { PlayPlatformBridge.isHubsForYouLongForm($0) }.count
        print("[Hubs] loadMore before=\(beforeLong) after=\(afterLong) pool=\(hubsForYouPool.count) display=\(hubsDisplayLimit) +\(added)")
        #endif
    }

    /// Re-queue the full ranked catalog under a new seed so For you never ends.
    private func appendEndlessRecyclePage() {
        hubsEndlessCycle += 1
        let home = allVideos.filter { PlayPlatformBridge.isHubsForYouLongForm($0) }
        guard !home.isEmpty else { return }
        let recycled = catalog.rankForYouBySlugs(
            home,
            followingIDs: appState.followingIDs,
            myUserID: appState.currentProfile?.userID ?? AuthService.shared.currentUser?.id,
            sessionSeed: hubsSessionSeed &+ UInt64(hubsEndlessCycle) &* 0x9E3779B97F4A7C15,
            focusSlug: homeFilter.hubSlug
        )
        guard !recycled.isEmpty else { return }
        hubsForYouPool.append(contentsOf: recycled)
        growForYouDisplay(by: Self.hubsGrowBy * 2, warmThumbs: true)
        #if DEBUG
        print("[Hubs] endless recycle cycle=\(hubsEndlessCycle) pool=\(hubsForYouPool.count)")
        #endif
    }

    private func rebuildContinueAndFollowingShuffled() {
        let history = catalog.historyVideos(from: allVideos).filter { !$0.isReel }
        stableContinueWatching = Array(Self.pureShuffle(history).prefix(8))

        let following = catalog.subscriptionFeed(
            videos: allVideos,
            channels: channels,
            followingIDs: appState.followingIDs
        ).filter { PlayPlatformBridge.isHubsForYouLongForm($0) }
        stableFollowingVideos = Array(Self.pureShuffle(following).prefix(6))

        let ch = catalog.subscriptionChannels(channels, followingIDs: appState.followingIDs)
        stableFollowingChannels = Self.pureShuffle(ch)
    }

    private var subscriptionVideos: [CountryPost] {
        if !stableFollowingVideos.isEmpty { return stableFollowingVideos }
        return catalog.subscriptionFeed(
            videos: allVideos,
            channels: channels,
            followingIDs: appState.followingIDs
        )
        .filter { PlayPlatformBridge.isHubsForYouLongForm($0) }
    }

    private var subscriptionChannels: [YouTubeChannel] {
        if !stableFollowingChannels.isEmpty { return stableFollowingChannels }
        return catalog.subscriptionChannels(channels, followingIDs: appState.followingIDs)
    }

    private var searchResults: (videos: [CountryPost], channels: [YouTubeChannel]) {
        catalog.search(query: searchQuery, videos: allVideos, channels: channels)
    }

    /// Mini session is owned by `GlobalHubPlaybackLayer` (any tab).
    private var isMiniPlayback: Bool {
        appState.hubPlaybackPost != nil && !appState.hubPlaybackExpanded
    }

    /// Watch chrome covers home only while fully expanded (not mid-pull, not mini).
    private var watchFullyCoveringHome: Bool {
        guard case .watch = route else { return false }
        guard appState.hubPlaybackExpanded else { return false }
        // Pull progress fades chrome; keep home under once pull starts.
        return appState.hubPlaybackPullProgress < 0.08
    }

    /// Watch overlay opacity — never zero when expanded with pull cleared.
    private var watchOverlayOpacity: Double {
        guard appState.hubPlaybackExpanded else { return 0 }
        return max(0, min(1, 1 - Double(appState.hubPlaybackPullProgress)))
    }

    /// Content under the watch overlay — always kept alive so mini never leaves a white hole.
    @ViewBuilder
    private var underWatchContent: some View {
        switch route {
        case .channel(let channel):
            YouTubeChannelView(
                channel: channel,
                subscriberCount: followerCounts[channel.authorID],
                onBack: { route = nil },
                onOpenVideo: { openVideo($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .library:
            libraryScreen
        case .watch, nil:
            // Home stays mounted even while watching.
            mainContent
        }
    }

    var body: some View {
        GeometryReader { geo in
            // Home always painted under watch. Cover only while fully expanded.
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if !watchFullyCoveringHome {
                        YouTubeAppHeader(onSearch: { showSearch = true })
                    }
                    underWatchContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Hide home only when watch fully covers — never when mini/pulling.
                .opacity(watchFullyCoveringHome ? 0 : 1)
                .allowsHitTesting(!watchFullyCoveringHome)

                if case .watch(let post) = route, appState.hubPlaybackExpanded {
                    let watchPost = PlayPlatformBridge.hubWatchPresentation(for: post)
                    YouTubeWatchView(
                        post: watchPost,
                        channel: channelForWatch(watchPost),
                        related: catalog.relatedVideos(to: watchPost, from: allVideos, limit: 24),
                        subscriberCount: followerCounts[watchPost.authorID],
                        embedsPlayer: false,
                        onBack: { closeWatch(minimize: true) },
                        onOpenVideo: { openVideo($0) },
                        onOpenChannel: { openChannel($0) }
                    )
                    .id("hub-watch-\(watchPost.id)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(watchOverlayOpacity)
                    .allowsHitTesting(watchOverlayOpacity > 0.4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(
                width: geo.size.width > 0 ? geo.size.width : nil,
                height: geo.size.height > 0 ? geo.size.height : nil
            )
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await loadVideos(forceRefresh: true, mode: .full)
            refreshHubsVisitShuffle(remountList: true)
        }
        .task(id: appState.contentLoadGeneration) {
            PerformanceTelemetry.markIfAbsent("hubs_task_start")
            await consumePendingLivingVideoIfNeeded()
            // 1) Instant paint (session / disk) — never blocks.
            paintInstantHubsIfPossible()
            if !allVideos.isEmpty {
                PerformanceTelemetry.milestone(
                    "hubs_first_useful",
                    surface: "hubs",
                    from: "hubs_task_start",
                    meta: ["source": "session_or_cache"]
                )
            }
            // Never remount LazyVStack on every content generation — that froze Hubs scroll.
            // Soft re-window only; pull-to-refresh / hubsFreshSessionToken still remount.
            if !allVideos.isEmpty, stableDiscoverVideos.isEmpty {
                rebuildStableHomeLists(shuffle: false, remountList: false)
            }
            // 2) Fast network only if still thin — keeps open snappy.
            let longForm = allVideos.filter { !$0.isReel }.count
            if longForm < 8 {
                await loadVideos(forceRefresh: false, mode: .fast)
                rebuildStableHomeLists(shuffle: false, remountList: false)
            } else {
                isLoading = false
            }
            PerformanceTelemetry.milestone(
                "hubs_interactive",
                surface: "hubs",
                from: "hubs_task_start",
                meta: ["longForm": "\(allVideos.filter { !$0.isReel }.count)"]
            )
            await consumePendingRoutingIfNeeded()
            // 3) Light warm only — never full-catalog rank on open.
            scheduleDeferredFullCatalogWarm()
        }
        .onAppear {
            paintInstantHubsIfPossible()
            syncRouteFromHubSession()
            Task { await consumePendingLivingVideoIfNeeded() }
            if appState.selectedTab == .hubs {
                EngagementTracker.shared.hubsOpened()
                // Soft-warm only — remounting LazyVStack on every appear was multi-second lag.
                if allVideos.filter({ !$0.isReel }).count < 8 {
                    Task {
                        await loadVideos(forceRefresh: false, mode: .fast)
                        // Soft update window without remounting the list.
                        refreshHubsVisitShuffle(remountList: false)
                    }
                } else {
                    butterWarmHubCatalog(allVideos)
                }
            }
        }
        .onChange(of: appState.selectedTab) { _, tab in
            guard tab == .hubs else { return }
            EngagementTracker.shared.hubsOpened()
            paintInstantHubsIfPossible()
            isLoading = false
            // Maximize / mini handoff: never reshuffle (that lagged tab switches + expand).
            if appState.hubPlaybackPost != nil {
                syncRouteFromHubSession()
                return
            }
            // Do NOT remount For you on every tab visit — only soft-fill if thin.
            // Intentional reshuffles: pull-to-refresh + hubsFreshSessionToken + content gen.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard appState.selectedTab == .hubs, appState.hubPlaybackPost == nil else { return }
                if allVideos.filter({ !$0.isReel }).count < 8 {
                    await loadVideos(forceRefresh: false, mode: .fast)
                    refreshHubsVisitShuffle(remountList: false)
                } else {
                    butterWarmHubCatalog(allVideos)
                }
            }
        }
        .onChange(of: appState.hubsFreshSessionToken) { _, token in
            guard token > 0 else { return }
            if !allVideos.isEmpty {
                refreshHubsVisitShuffle(remountList: true)
            }
        }
        .onChange(of: homeFilter) { _, filter in
            // Chip change = load **that slug page only** (not re-filter a fat catalog).
            EngagementTracker.shared.hubShelfSelected(filter.rawValue)
            Task { @MainActor in
                isLoading = allVideos.isEmpty
                let page: SlugShelfStore.Page
                if let slug = filter.hubSlug {
                    page = await SlugShelfStore.shared.loadShelf(slug, force: false)
                } else {
                    page = await SlugShelfStore.shared.loadForYou(force: false)
                }
                if !page.items.isEmpty {
                    let filtered = BlockService.shared.filterPosts(page.items)
                    applyHubCatalog(
                        filtered,
                        shuffle: true,
                        persist: true,
                        remountList: true
                    )
                    butterWarmHubCatalog(filtered)
                    SlugShelfStore.shared.warmNeighbor(of: filter.hubSlug ?? page.slugsUsed.first)
                } else {
                    // Offline / empty shelf — rank whatever we already hold for this slug.
                    rebuildStableHomeLists(shuffle: true, remountList: true)
                }
                isLoading = false
            }
        }
        .onChange(of: route) { oldRoute, newRoute in
            // Reshuffle only when intentionally leaving channel/library → home.
            // Minimize (watch → nil) must NOT remount For you — that was the white lag.
            guard newRoute == nil, let oldRoute, appState.selectedTab == .hubs else { return }
            switch oldRoute {
            case .watch:
                return
            case .channel, .library:
                if !allVideos.isEmpty {
                    refreshHubsVisitShuffle(remountList: true)
                }
            }
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
                                    ScrollBudget.noteCellAppear()
                                    // Thumbs only — never warm AVPlayers mid-scroll (that froze Hubs).
                                    // Full warm happens on openVideo.
                                    if !ScrollBudget.isFlinging, index % 3 == 0 {
                                        ImageCache.shared.prefetchHubsWindow(
                                            posts: stableDiscoverVideos,
                                            around: index,
                                            behind: 0,
                                            ahead: 2,
                                            maxPixelSize: YouTubeMediaLayout.hubsListThumbMaxPixel
                                        )
                                    }
                                    // Endless For you — grow window; network only when settled.
                                    ensureMoreForYou(around: index)
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

    /// Sparks rail: pure shuffle every call — no sticky discovery rank until algorithm lands.
    private func reshuffleSparksStrip() async {
        var seen = Set<String>()
        var pool: [CountryPost] = []

        func take(_ posts: [CountryPost], cap: Int) {
            for post in Self.pureShuffle(posts) {
                guard post.playableVideoURL != nil else { continue }
                guard seen.insert(post.id).inserted else { continue }
                pool.append(post)
                if pool.count >= cap { return }
            }
        }

        // 1) Catalog sparks (shuffled).
        take(playReels, cap: 48)

        // 2) Channel sparks top-up.
        if pool.count < 24 {
            let channelSparks = await PostsService.shared.fetchFocusMarketHubSparks(limitPerAuthor: 80)
            take(channelSparks, cap: 48)
        }

        // 3) General reels feed top-up.
        if pool.count < 16 {
            let network = await PostsService.shared.loadReelsFeed(
                globalLimit: 64,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs
            )
            take(network, cap: 48)
        }

        if pool.count < 8 {
            let seed = UInt64.random(in: 1...UInt64.max)
                ^ UInt64(Date().timeIntervalSince1970 * 1_000)
            let seeds = await HubVideoSeedService.shared.sparkSeedVideos(limit: 40, shuffleSeed: seed)
            take(seeds, cap: 48)
        }

        // Final pure shuffle of the assembled pool (different order every visit).
        let next = Self.pureShuffle(pool)
        await MainActor.run {
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
        let capped = Self.slugCappedFirstPaint(filtered, perSlug: 6)
        guard !capped.isEmpty else { return }
        applyHubCatalog(capped, shuffle: true, persist: false)
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
        shuffle: Bool,
        persist: Bool,
        remountList: Bool = true
    ) {
        allVideos = videos
        if persist, !videos.isEmpty {
            ContentCache.shared.setPosts(
                Array(videos.prefix(ContentCache.maxCachedPosts)),
                for: .livingVideos
            )
        }
        rebuildChannels()
        if shuffle {
            refreshHubsVisitShuffle(remountList: remountList)
        } else {
            rebuildStableHomeLists(shuffle: false, remountList: remountList)
        }
    }

    /// Soft-merge catalog into session without nuking the visible list.
    /// Keeps **all** long-form (endless For you). Only sparks are lightly capped.
    private func softMergeHubCatalog(_ videos: [CountryPost]) {
        guard !videos.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: allVideos.map { ($0.id, $0) })
        var added = 0
        for post in videos {
            if byID[post.id] == nil { added += 1 }
            byID[post.id] = post
        }
        let all = Array(byID.values)
        var longForm = all.filter { PlayPlatformBridge.isHubsForYouLongForm($0) }
        // Prefer newer first if we ever hit the extreme memory ceiling.
        if longForm.count > Self.hubsCatalogMemoryCap {
            longForm.sort { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            longForm = Array(longForm.prefix(Self.hubsCatalogMemoryCap))
        }
        let sparks = Array(all.filter(\.isReel).prefix(80))
        var seen = Set(longForm.map(\.id))
        var merged = longForm
        for s in sparks where seen.insert(s.id).inserted {
            merged.append(s)
        }
        allVideos = merged
        PostsService.shared.rememberHubsSessionCatalog(merged)
        ContentCache.shared.setPosts(
            Array(merged.prefix(ContentCache.maxCachedPosts)),
            for: .livingVideos
        )
        rebuildChannels()
        if added > 0 {
            if ScrollBudget.isFlinging {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    guard !ScrollBudget.isFlinging else { return }
                    applySoftMergeDisplayGrowth(added: added)
                }
            } else {
                applySoftMergeDisplayGrowth(added: added)
            }
        }
        #if DEBUG
        print("[Hubs] soft-merge +\(added) total=\(merged.count) longForm=\(longForm.count) pool=\(hubsForYouPool.count) display=\(stableDiscoverVideos.count)")
        #endif
    }

    private func applySoftMergeDisplayGrowth(added: Int) {
        rebuildStableHomeLists(shuffle: false, remountList: false)
        if hubsDisplayLimit < hubsForYouPool.count {
            hubsDisplayLimit = min(
                hubsForYouPool.count,
                max(hubsDisplayLimit, Self.hubsFirstWindow) + (added > 8 ? Self.hubsGrowBy : 0)
            )
            let window = Array(hubsForYouPool.prefix(hubsDisplayLimit))
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                stableHomeVideos = window
                stableDiscoverVideos = window
            }
        }
    }

    private func warmSlugShelvesInBackground() {
        let videos = allVideos
        guard !videos.isEmpty else { return }
        let thumbPx = YouTubeMediaLayout.hubsListThumbMaxPixel
        // Only warm the first few shelves — full hubOrder × 24 was a download storm.
        Task.detached(priority: .background) {
            for slug in HubVideoSeedService.hubOrder.prefix(3) {
                ImageCache.shared.prefetchHubSlug(slug, from: videos, limit: 10, maxPixelSize: thumbPx)
            }
        }
    }

    /// Idle top-up — warm **neighbor slug only** (never download full catalog).
    private func scheduleDeferredFullCatalogWarm() {
        Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard appState.selectedTab == .hubs else { return }
            // Skip heavy warm while a hubs video is open/minimized — keeps morph smooth.
            guard appState.hubPlaybackPost == nil else { return }
            let active = homeFilter.hubSlug
            SlugShelfStore.shared.warmNeighbor(of: active)
            let longForm = allVideos.filter { PlayPlatformBridge.isHubsForYouLongForm($0) }.count
            if longForm < 12 {
                await loadMoreActiveShelf()
            }
        }
    }

    /// Load active surface via slug shelves (thin pages). Falls back to legacy catalog once.
    private func loadVideos(forceRefresh: Bool, mode: HubsLoadMode = .full) async {
        // Never blank an already-painted catalog with a full-screen spinner.
        if allVideos.isEmpty { isLoading = true }
        errorMessage = nil

        let longFormNow = allVideos.filter { !$0.isReel }.count
        let hadPaint = !allVideos.isEmpty

        // Warm UI: slug page already painted — skip network.
        if !forceRefresh, mode == .fast, longFormNow >= 8 {
            isLoading = false
            butterWarmHubCatalog(allVideos)
            #if DEBUG
            print("[Hubs] skip FAST — \(longFormNow) longform (slug cache)")
            #endif
            return
        }

        if forceRefresh {
            SlugShelfStore.shared.newSession()
        }

        // ── Slug-first path (light) ──────────────────────────────────────────
        let key = SlugShelfStore.key(for: homeFilter)
        let page: SlugShelfStore.Page
        if let slug = homeFilter.hubSlug {
            page = await SlugShelfStore.shared.loadShelf(slug, force: forceRefresh)
        } else {
            page = await SlugShelfStore.shared.loadForYou(force: forceRefresh)
        }

        if !page.items.isEmpty {
            let filtered = BlockService.shared.filterPosts(page.items)
                .filter { PlayPlatformBridge.isHubsForYouLongForm($0) || $0.hasVideo }
            if !filtered.isEmpty {
                if hadPaint, !forceRefresh, mode == .full {
                    softMergeHubCatalog(filtered)
                } else {
                    applyHubCatalog(
                        filtered,
                        shuffle: forceRefresh || !hadPaint,
                        persist: true,
                        remountList: !hadPaint || forceRefresh
                    )
                    // Session holds only the active window — not thousands of rows.
                    PostsService.shared.rememberHubsSessionCatalog(
                        Array((filtered + allVideos).prefix(SlugShelfStore.maxPerShelf * 2))
                    )
                }
                isLoading = false
                butterWarmHubCatalog(allVideos)
                if let slug = homeFilter.hubSlug {
                    SlugShelfStore.shared.warmNeighbor(of: slug)
                } else if let first = page.slugsUsed.first {
                    SlugShelfStore.shared.warmNeighbor(of: first)
                }
                #if DEBUG
                print("[Hubs] slug path key=\(key) items=\(filtered.count) force=\(forceRefresh)")
                #endif
                if forceRefresh {
                    Task(priority: .utility) {
                        await loadChannelProfiles()
                        await loadFollowerCounts()
                    }
                }
                return
            }
        }

        // ── Legacy fallback (once) if shelves empty / API down ───────────────
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

        // Cap legacy pull — never 500×N channels for first paint.
        let network = await PostsService.shared.loadPlayCatalog(
            globalLimit: forceRefresh ? 80 : (mode == .fast ? 36 : 60),
            forceRefresh: forceRefresh,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            fast: true
        )
        for post in network {
            if PlayPlatformBridge.isFeedOnlyShare(post),
               !PlayPlatformBridge.isHubOriginShare(post) {
                continue
            }
            guard PlayPlatformBridge.belongsInHubsCatalog(post)
                || PlayPlatformBridge.isHubChannelUpload(post)
                || PlayPlatformBridge.isHubOriginShare(post)
                || PlayPlatformBridge.isHubsForYouLongForm(post)
            else { continue }
            byID[post.id] = post
        }

        var videos = BlockService.shared.filterPosts(Array(byID.values))
        if !AppConfig.archiveContentEnabled {
            videos = videos.excludingArchiveContent()
        }
        // Memory cap even on fallback.
        if videos.count > 120 {
            videos = Array(Self.slugCappedFirstPaint(videos, perSlug: 8).prefix(120))
        }

        isLoading = false

        if videos.isEmpty, allVideos.isEmpty {
            errorMessage = MatteryaCopy.hubsLoadError
            return
        }

        if !videos.isEmpty {
            if hadPaint, mode == .full, !forceRefresh {
                softMergeHubCatalog(videos)
            } else {
                let painted = Self.slugCappedFirstPaint(videos, perSlug: 8)
                applyHubCatalog(
                    painted,
                    shuffle: forceRefresh || !hadPaint,
                    persist: true,
                    remountList: !hadPaint || forceRefresh
                )
                PostsService.shared.rememberHubsSessionCatalog(painted)
            }
        }

        #if DEBUG
        let longForm = allVideos.filter { !$0.isReel }.count
        print("[Hubs] legacy fallback mode=\(mode) longForm=\(longForm) force=\(forceRefresh)")
        #endif
        if !hadPaint || forceRefresh {
            butterWarmHubCatalog(allVideos)
        }

        if forceRefresh {
            Task(priority: .utility) {
                await loadChannelProfiles()
                await loadFollowerCounts()
            }
        }
    }

    /// Next page of the active slug / For you stream.
    private func loadMoreActiveShelf() async {
        let page: SlugShelfStore.Page
        if let slug = homeFilter.hubSlug {
            page = await SlugShelfStore.shared.loadMoreShelf(slug)
        } else {
            page = await SlugShelfStore.shared.loadMoreForYou()
        }
        guard !page.items.isEmpty else { return }
        let filtered = BlockService.shared.filterPosts(page.items)
            .filter { PlayPlatformBridge.isHubsForYouLongForm($0) || $0.hasVideo }
        softMergeHubCatalog(filtered)
        // Grow display from the merged pool without re-ranking thousands.
        if hubsDisplayLimit < hubsForYouPool.count {
            growForYouDisplay(by: Self.hubsGrowBy, warmThumbs: true)
        } else {
            rebuildStableHomeLists(shuffle: false, remountList: false)
            growForYouDisplay(by: Self.hubsGrowBy, warmThumbs: true)
        }
    }

    /// Prefetch posters only — keep this light so it never competes with first paint.
    private func butterWarmHubCatalog(_ videos: [CountryPost]) {
        let thumbPx = YouTubeMediaLayout.hubsListThumbMaxPixel
        let head = stableDiscoverVideos.isEmpty
            ? videos.filter { !$0.isReel && $0.playableVideoURL != nil }
            : stableDiscoverVideos
        // First screen only — never warm AVPlayers here.
        ImageCache.shared.prefetchPostThumbnails(
            Array(head.prefix(6)),
            maxPixelSize: thumbPx,
            aggressive: false
        )
        // Sparks strip thumbs later — never compete with For you.
        Task(priority: .background) {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard appState.selectedTab == .hubs, appState.hubPlaybackPost == nil else { return }
            let sparks = videos.filter(\.isReel)
            if !sparks.isEmpty {
                ImageCache.shared.prefetchPostThumbnails(
                    Array(sparks.prefix(6)),
                    maxPixelSize: 240,
                    aggressive: false
                )
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
            // No tree animation — home is already under the overlay.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                route = .watch(watchPost)
            }
        } else if case .watch = route {
            // Instant clear — home is already painted underneath (no white, no remount).
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
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

    /// Opens the **Hubs long-form player** only.
    /// Sparks player is only via `openReelsPlayback` (Sparks strip / library Sparks).
    private func openVideo(_ post: CountryPost) {
        // Instant open — no await before first paint/play (resolve upgrades in background).
        var watchPost = PlayPlatformBridge.hubWatchPresentation(for: post)
        if watchPost.isReel || watchPost.isSpark || ReelsRankingEngine.isSparkEligible(watchPost) {
            watchPost = post
        }
        EngagementTracker.shared.hubVideoOpened(watchPost)
        // Warm AV **before** route/player remount so claim hits a buffered slot.
        if let url = watchPost.playableVideoURL {
            SparkWarmPool.shared.warmSingle(postID: watchPost.id, url: url)
        }
        appState.startHubPlayback(watchPost, expanded: true)
        // No easeInOut on the whole hubs tree — that lagged related taps + minimize.
        // .id(watchPost.id) on YouTubeWatchView resets scroll to title/comments (not related).
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            route = .watch(watchPost)
        }
        // Optional catalog upgrade (channel name / better media) without blocking start.
        Task { @MainActor in
            let resolved = await PlayPlatformBridge.resolveHubWatchPresentation(for: post)
            guard !resolved.isReel, !ReelsRankingEngine.isSparkEligible(resolved) else { return }
            if case .watch(let current) = route, current.id == post.id || current.id == watchPost.id {
                if resolved.authorID != current.authorID {
                    var u = Transaction()
                    u.disablesAnimations = true
                    withTransaction(u) { route = .watch(resolved) }
                }
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
            // Pull-down / close → mini morph; home is already under the overlay.
            appState.minimizeHubPlayback(returnToChat: true)
        } else {
            appState.stopHubPlayback()
        }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { route = nil }
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