import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppState {
    var isAuthenticated = false
    var isSessionReady = false
    var contentLoadGeneration = 0
    var needsProfileSetup = false
    var currentProfile: Profile?
    var selectedTab: AppTab = .feed
    var selectedCountry: Country?
    var countryTab: CountryTab = .posts
    var globePanel: GlobePanel?
    var globalStats: GlobalStats?
    var countryStats: CountryStats?
    var messagesUnreadCount = 0
    var notificationsUnreadCount = 0
    var notifications: [NotificationItem] = []

    var effectiveNotificationsUnreadCount: Int {
        max(notificationsUnreadCount, notifications.filter(\.isUnread).count)
    }
    var followingIDs: Set<String> = []
    var savedPostIDs: Set<String> = []
    var savedPosts: [CountryPost] = []
    var reelPresentationSavedIDs: Set<String> = []
    var profileLibrarySection: ProfileLibrarySection = .posts
    var searchPrefersCountries = false
    var openComposerOnCountryFeed = false
    var showCreateMenu = false
    var activeCreateSheet: CreateContentSheet?
    var composerCountry: Country?
    var storyGroups: [StoryGroup] = []
    var storyViewerContext: StoryViewerContext?
    var reelsViewerContext: ReelsViewerContext?

    private let reelSavedDefaultsKey = "saved_reel_presentation_ids"
    private let localSavedPostIDsKey = "local_saved_post_ids"
    private let viewedStoriesDefaultsKey = "viewed_story_post_ids"
    var navigationPath: [AppDestination] = []
    var pendingConversationID: String?
    var isPlayPresented = false
    var pendingLivingVideoID: String?
    var pendingPlayTab: YouTubeMainTab?
    var pendingPlayChannelAuthorID: String?
    var pendingPlayChannelUsername: String?
    var showAppMenu = false
    var floatingPosts: [CountryPost] = []
    var errorMessage: String?
    var toastMessage: String?
    var toastStyle: ToastBanner.ToastStyle = .info
    var sharePostSheet: CountryPost?
    var quotedSharePostID: String?
    var pendingSearchQuery: String?

    private let auth = AuthService.shared
    private let profileService = ProfileService.shared
    private let notificationsService = NotificationsService.shared
    private let presenceService = PresenceService.shared
    private let followService = FollowService.shared
    private var pollTask: Task<Void, Never>?
    private var postEventsObservers: [NSObjectProtocol] = []

    func bootstrap() async {
        if ScreenshotMode.isActive {
            await applyScreenshotMode()
            return
        }

        VoIPPushService.shared.bootstrap()
        reelPresentationSavedIDs = loadReelPresentationSavedIDs()
        isAuthenticated = auth.isAuthenticated
        guard isAuthenticated else {
            isSessionReady = true
            return
        }

        restoreCachedProfile()
        markSessionReady()
        CallSessionManager.shared.bootstrap()
        startPolling()
        registerPushInBackground()
        Task { await finishSessionWarmup() }
    }

    func handleBecameActive() async {
        guard isAuthenticated else { return }
        if !isSessionReady {
            restoreCachedProfile()
            markSessionReady()
            Task { await finishSessionWarmup() }
            return
        }
        await prepareSession()
    }

    private func restoreCachedProfile() {
        guard currentProfile == nil, let cached = ContentCache.shared.cachedProfile() else { return }
        currentProfile = cached
        needsProfileSetup = !cached.isComplete
    }

    private func markSessionReady() {
        guard !isSessionReady else { return }
        isSessionReady = true
    }

    private func finishSessionWarmup() async {
        await prepareSession()
        await refreshProfile()
        await refreshAllInBackground()
        contentLoadGeneration += 1
        startPostRealtime()
    }

    private func prepareSession() async {
        await withTimeout(seconds: 10) {
            _ = try? await self.auth.ensureValidToken()
        }
    }

    private func withTimeout(seconds: TimeInterval, operation: @escaping () async -> Void) async {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await operation()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func registerPushInBackground() {
        Task {
            VoIPPushService.shared.bootstrap()
            await VoIPPushService.shared.ensureToken()
            await PushNotificationService.shared.syncWithServer(force: true)
            await PushNotificationService.shared.requestAuthorizationAndRegister()
            await VoIPPushService.shared.ensureToken()
            await PushNotificationService.shared.syncWithServer(force: true)
        }
    }

    func refreshAll() async {
        await refreshProfile()
        await refreshAllInBackground()
    }

    private func refreshAllInBackground() async {
        async let statsTask: Void = { await refreshGlobalStats() }()
        async let followingTask: Void = { await refreshFollowingIDs() }()
        async let savedTask: Void = { await refreshSavedPosts() }()
        async let storiesTask: Void = { await refreshStories() }()
        async let notificationsTask: Void = { await refreshNotifications() }()
        async let feedTask: Void = { _ = await PostsService.shared.loadHomeFeed() }()
        async let livingTask: Void = { _ = await PostsService.shared.loadLivingVideos() }()
        _ = await (statsTask, followingTask, savedTask, storiesTask, notificationsTask, feedTask, livingTask)
        startPresence()
    }

    func refreshProfile() async {
        let previousCountry = ContentCache.shared.profileCountryCode()
        do {
            currentProfile = try await profileService.meProfile()
            ContentCache.shared.setProfile(currentProfile)
            needsProfileSetup = !(currentProfile?.isComplete ?? false)
            let newCountry = currentProfile?.countryCode?.uppercased()
            if newCountry != previousCountry, newCountry != nil {
                ContentCache.shared.invalidate(.homeFeed, .livingVideos)
                contentLoadGeneration += 1
            }
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("authentication required") || message.contains("unauthenticated") {
                logout()
                return
            }
            if currentProfile?.isComplete == true {
                needsProfileSetup = false
            } else {
                needsProfileSetup = true
            }
        }
    }

    func refreshGlobalStats() async {
        globalStats = try? await profileService.globalStats()
    }

    func refreshCountryStats(for country: Country) async {
        countryStats = try? await profileService.countryStats(country.iso)
    }

    func refreshFollowingIDs() async {
        followingIDs = await followService.followingIDs()
    }

    func refreshSavedPosts() async {
        if savedPostIDs.isEmpty {
            savedPostIDs = Set(UserDefaults.standard.stringArray(forKey: localSavedPostIDsKey) ?? [])
        }
        if savedPosts.isEmpty, let cached = ContentCache.shared.posts(for: .savedPosts) {
            savedPosts = cached
            savedPostIDs = Set(cached.map(\.id))
        }
        let loaded = await PostsService.shared.loadBookmarkedPosts(localIDs: savedPostIDs, limit: 100)
        if !loaded.isEmpty || PostsService.usesLocalBookmarksOnly {
            savedPosts = loaded
            savedPostIDs = Set(loaded.map(\.id))
            ContentCache.shared.setPosts(savedPosts, for: .savedPosts)
            persistLocalSavedPostIDs()
        } else if savedPosts.isEmpty {
            await loadLocalSavedPosts(resolvePosts: true)
        }
    }

    func isPostSaved(_ postID: String) -> Bool {
        savedPostIDs.contains(postID)
    }

    @discardableResult
    func toggleSavePost(_ post: CountryPost, reelPresentation: Bool = false) async -> String? {
        let wasSaved = savedPostIDs.contains(post.id)
        let targetSaved = !wasSaved
        applySavedState(for: post, saved: targetSaved, reelPresentation: reelPresentation)
        do {
            let updated = try await PostsService.shared.toggleBookmark(for: post, saved: targetSaved)
            applySavedState(for: updated, saved: targetSaved, reelPresentation: reelPresentation)
            persistLocalSavedPostIDs()
            ContentCache.shared.setPosts(savedPosts, for: .savedPosts)
            return nil
        } catch {
            applySavedState(for: post, saved: wasSaved, reelPresentation: reelPresentation)
            return error.localizedDescription
        }
    }

    private func applySavedState(for post: CountryPost, saved: Bool, reelPresentation: Bool) {
        if saved {
            savedPostIDs.insert(post.id)
            savedPosts.removeAll { $0.id == post.id }
            savedPosts.insert(post, at: 0)
            if reelPresentation || post.isReel {
                reelPresentationSavedIDs.insert(post.id)
                persistReelPresentationSavedIDs()
            }
        } else {
            savedPostIDs.remove(post.id)
            savedPosts.removeAll { $0.id == post.id }
            reelPresentationSavedIDs.remove(post.id)
            persistReelPresentationSavedIDs()
        }
    }

    private func loadLocalSavedPosts(resolvePosts: Bool = false) async {
        let ids = Set(UserDefaults.standard.stringArray(forKey: localSavedPostIDsKey) ?? [])
        guard !ids.isEmpty else { return }

        savedPostIDs = ids
        if let cached = ContentCache.shared.posts(for: .savedPosts), !cached.isEmpty {
            savedPosts = cached.filter { ids.contains($0.id) }
            if !savedPosts.isEmpty { return }
        }
        guard resolvePosts else { return }
        savedPosts = await PostsService.shared.loadBookmarkedPosts(localIDs: ids, limit: 100)
        ContentCache.shared.setPosts(savedPosts, for: .savedPosts)
    }

    private func persistLocalSavedPostIDs() {
        UserDefaults.standard.set(Array(savedPostIDs), forKey: localSavedPostIDsKey)
    }

    var savedJournalPosts: [CountryPost] {
        savedPosts.filter { !$0.hasVideo }
    }

    var savedVideoPosts: [CountryPost] {
        savedPosts.filter {
            $0.hasVideo && !$0.isReel && !reelPresentationSavedIDs.contains($0.id)
        }
    }

    var savedReelPosts: [CountryPost] {
        savedPosts.filter {
            $0.hasVideo && ($0.isReel || reelPresentationSavedIDs.contains($0.id))
        }
    }

    private func loadReelPresentationSavedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: reelSavedDefaultsKey) ?? [])
    }

    private func persistReelPresentationSavedIDs() {
        UserDefaults.standard.set(Array(reelPresentationSavedIDs), forKey: reelSavedDefaultsKey)
    }

    func refreshNotifications() async {
        async let listTask = notificationsService.list(limit: 80)
        async let notifCountTask = notificationsService.unreadCount()
        async let messagesCountTask = MessagesService.shared.messagesUnreadCount()

        let all = await listTask
        notifications = all.filter { !$0.isMessageType }
        notificationsUnreadCount = await notifCountTask
        messagesUnreadCount = await messagesCountTask
    }

    func refreshUnreadCounts() async {
        async let notificationsCount = notificationsService.unreadCount()
        async let messagesCount = MessagesService.shared.messagesUnreadCount()
        notificationsUnreadCount = await notificationsCount
        messagesUnreadCount = await messagesCount
    }

    func loadFloatingPosts() async {
        floatingPosts = await PostsService.shared.sampleGlobalPosts(limit: 10)
    }

    func onAuthenticated() async {
        isAuthenticated = true
        restoreCachedProfile()
        markSessionReady()
        CallSessionManager.shared.bootstrap()
        startPolling()
        registerPushInBackground()
        Task { await finishSessionWarmup() }
    }

    func logout() {
        stopPostRealtime()
        stopPolling()
        Task { await PushNotificationService.shared.unregisterFromServer() }
        CallSessionManager.shared.teardown()
        CallSignalingService.shared.shutdown()
        Task { await presenceService.setOffline() }
        presenceService.stopHeartbeat()
        auth.logout()
        isAuthenticated = false
        isSessionReady = true
        contentLoadGeneration = 0
        needsProfileSetup = false
        currentProfile = nil
        selectedCountry = nil
        selectedTab = .feed
        globePanel = nil
        navigationPath = []
        isPlayPresented = false
        pendingConversationID = nil
        pendingLivingVideoID = nil
        clearPendingPlayRouting()
        followingIDs = []
        savedPostIDs = []
        savedPosts = []
        notifications = []
        showAppMenu = false
        toastMessage = nil
        sharePostSheet = nil
        quotedSharePostID = nil
        reelsViewerContext = nil
        storyGroups = []
        storyViewerContext = nil
    }

    func showToast(_ message: String, style: ToastBanner.ToastStyle = .success) {
        toastMessage = message
        toastStyle = style
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    func presentShareSheet(for post: CountryPost) {
        guard !post.isStory else {
            showToast("Moments live in Globe — they aren't shared as feed posts.", style: .info)
            return
        }
        sharePostSheet = post
    }

    func handleDeepLink(_ url: URL) {
        if handleInternalDeepLink(url) { return }

        guard let destination = ShareService.shared.parseDeepLink(url) else { return }
        showAppMenu = false
        globePanel = nil
        switch destination {
        case .playWatch(let id):
            Task { await openPlayVideo(id: id) }
        case .playChannel(let username):
            openPlayChannel(username: username)
        case .playChannelID(let authorID):
            openPlayChannel(authorID: authorID)
        case .people, .ads, .editProfile, .settings, .premium, .search:
            selectedTab = .feed
            navigationPath.removeAll()
            navigationPath.append(destination)
        case .post(let id):
            Task { await openPost(id: id) }
        case .news, .publicProfile, .publicProfileByUserID, .reels, .countryFeed:
            selectedTab = .feed
            navigationPath.removeAll()
            navigationPath.append(destination)
        case .conversation(let id):
            openConversation(id: id)
        }
    }

    func handlePushNavigation(type: String, conversationID: String?, postID: String?, username: String?) {
        showAppMenu = false
        globePanel = nil
        let normalized = type.lowercased()

        if normalized == "message", let conversationID {
            openConversation(id: conversationID)
            return
        }

        if normalized == "call" || normalized == "incoming_call" {
            selectedTab = .messages
            navigationPath.removeAll()
            if CallSessionManager.shared.isIncoming {
                CallSessionManager.shared.presentInAppIncomingUI()
            }
            return
        }

        if normalized == "follow" {
            selectedTab = .feed
            navigationPath.removeAll()
            if let username, !username.isEmpty {
                openPublicProfile(username: username, userID: username)
            }
            return
        }

        if let postID, !postID.isEmpty {
            openNotificationPost(id: postID)
            return
        }

        globePanel = .notifications
        Task { await refreshNotifications() }
    }

    func selectCountry(_ country: Country) {
        selectedCountry = country
        countryTab = .posts
        Task {
            await refreshCountryStats(for: country)
            presenceService.startHeartbeat(viewingISO: country.iso)
        }
    }

    func clearCountry() {
        selectedCountry = nil
        countryStats = nil
        countryTab = .posts
        startPresence()
    }

    func resolveHomeCountry() async -> Country? {
        guard let code = currentProfile?.countryCode?.uppercased(), !code.isEmpty else { return nil }
        let countries = (try? await profileService.countries()) ?? []
        if let match = countries.first(where: { $0.iso.uppercased() == code }) {
            return match
        }
        let name = currentProfile?.countryName ?? code
        return Country(id: code, name: name, iso: code, continent: nil, centerLat: nil, centerLng: nil)
    }

    var homeCountryISO: String? {
        let code = currentProfile?.countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code?.isEmpty == false ? code : nil
    }

    func canPostToCountry(_ country: Country) -> Bool {
        guard let home = homeCountryISO else { return false }
        return home == country.iso.uppercased()
    }

    func navigateToHomeCountryFeed(openComposer: Bool = false) async {
        guard let home = await resolveHomeCountry() else {
            showToast("Set your home country in profile before posting.", style: .error)
            return
        }
        globePanel = nil
        showAppMenu = false
        navigationPath.removeAll()
        selectCountry(home)
        navigate(to: .countryFeed(home))
        if openComposer {
            openComposerOnCountryFeed = true
        }
    }

    func navigate(to destination: AppDestination) {
        navigationPath.append(destination)
    }

    func openConversation(id: String) {
        pendingConversationID = nil
        selectedTab = .messages
        navigationPath.removeAll { destination in
            if case .conversation = destination { return true }
            return false
        }
        navigationPath.append(.conversation(id))
    }

    func closeConversation(id: String) {
        navigationPath.removeAll { destination in
            if case .conversation(let conversationID) = destination {
                return conversationID == id
            }
            return false
        }
    }

    func openDirectMessage(with userID: String) async {
        globePanel = nil
        showAppMenu = false
        do {
            let conversation = try await MessagesService.shared.startConversation(targetID: userID)
            openConversation(id: conversation.id)
        } catch {
            showToast(error.localizedDescription, style: .error)
        }
    }

    func openPublicProfile(username: String?, userID: String) {
        globePanel = nil
        showAppMenu = false
        selectedTab = .feed
        navigationPath.removeAll()
        let trimmedUsername = username?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@+", with: "", options: .regularExpression)
        if let trimmedUsername, !trimmedUsername.isEmpty {
            navigate(to: .publicProfile(username: trimmedUsername))
        } else if !userID.isEmpty {
            navigate(to: .publicProfileByUserID(userID))
        }
    }

    func presentPlaySurface() {
        showAppMenu = false
        globePanel = nil
        isPlayPresented = true
    }

    func dismissPlay() {
        isPlayPresented = false
        pendingLivingVideoID = nil
        clearPendingPlayRouting()
    }

    func openLivingVideo(postID: String, tab: YouTubeMainTab? = nil) {
        navigationPath.removeAll()
        showAppMenu = false
        globePanel = nil
        isPlayPresented = false
        if let tab { pendingPlayTab = tab }
        pendingLivingVideoID = postID
        selectedTab = .hubs
    }

    func clearPendingLivingVideo() {
        pendingLivingVideoID = nil
    }

    func clearPendingPlayRouting() {
        pendingPlayTab = nil
        pendingPlayChannelAuthorID = nil
        pendingPlayChannelUsername = nil
    }

    func openPlay(tab: YouTubeMainTab = .home) {
        navigationPath.removeAll()
        showAppMenu = false
        globePanel = nil
        isPlayPresented = false
        pendingPlayTab = tab
        selectedTab = .hubs
    }

    func openPlayFromMenu(tab: YouTubeMainTab = .home) {
        openPlay(tab: tab)
    }

    func openPlayChannel(authorID: String, username: String? = nil) {
        navigationPath.removeAll()
        showAppMenu = false
        globePanel = nil
        isPlayPresented = false
        pendingPlayChannelAuthorID = authorID
        pendingPlayChannelUsername = username
        selectedTab = .hubs
    }

    func openPlayChannel(username: String) {
        navigationPath.removeAll()
        showAppMenu = false
        globePanel = nil
        isPlayPresented = false
        pendingPlayChannelUsername = username
        selectedTab = .hubs
    }

    func openPost(_ post: CountryPost) {
        if post.isReel {
            openReelsViewer(startingPost: post)
        } else if PlayPlatformBridge.isLongFormVideo(post) {
            openLivingVideo(postID: post.id, tab: .home)
        } else {
            selectedTab = .feed
            navigationPath.removeAll()
            navigate(to: .post(post.id))
        }
    }

    func openPost(id: String) async {
        if let post = try? await PostsService.shared.getPostByID(id) {
            openPost(post)
        } else {
            selectedTab = .feed
            navigationPath.removeAll()
            navigate(to: .post(id))
        }
    }

    func openPlayVideo(id: String) async {
        if let post = try? await PostsService.shared.getPostByID(id) {
            openPost(post)
        } else {
            openLivingVideo(postID: id)
        }
    }

    func openPostInFeed(postID: String) {
        selectedTab = .feed
        navigationPath.removeAll()
        navigate(to: .post(postID))
    }

    func openReelsViewer(startingPost: CountryPost, seedPosts: [CountryPost] = []) {
        reelsViewerContext = ReelsViewerContext(
            startingPost: startingPost,
            seedPosts: seedPosts
        )
    }

    func openReelsFromMenu() async {
        let reels = await PostsService.shared.loadReelsFeed(
            viewerCountry: currentProfile?.countryCode,
            followingIDs: followingIDs
        )
        guard let first = reels.first else {
            showToast("\(MatteryaCopy.noSparksYet) — publish one to get started.", style: .info)
            openPlay()
            return
        }
        openReelsViewer(startingPost: first, seedPosts: reels)
    }

    func openCountryReels(_ country: Country) {
        Task {
            let posts = (try? await PostsService.shared.videoPosts(for: country)) ?? []
            let reels = posts.filter { $0.isReel && $0.playableVideoURL != nil }
            guard let first = reels.first else {
                showToast("\(MatteryaCopy.noSparksForCountry) \(country.name) yet.", style: .info)
                openPlay()
                return
            }
            openReelsViewer(startingPost: first, seedPosts: reels)
        }
    }

    func openFromMenu(_ destination: AppDestination) {
        showAppMenu = false
        switch destination {
        case .people, .ads, .editProfile, .settings, .premium, .search:
            selectedTab = .feed
            navigationPath.removeAll()
            navigationPath.append(destination)
        default:
            navigate(to: destination)
        }
    }

    func openProfileFromMenu() {
        showAppMenu = false
        selectedTab = .profile
        navigationPath.removeAll()
    }

    func openSavedFromMenu(section: ProfileLibrarySection = .savedPosts) {
        showAppMenu = false
        profileLibrarySection = section
        selectedTab = .profile
        navigationPath.removeAll()
    }

    func inviteFriendsFromMenu() {
        showAppMenu = false
        shareAppInvite()
    }

    func shareAppInvite() {
        let items = ShareService.shared.activityItems(for: .appInvite)
        guard let root = UIApplication.shared.firstKeyWindow?.rootViewController else { return }
        root.topMostViewController().presentShareSheet(items: items)
    }

    func openNotificationsFromMenu() {
        showAppMenu = false
        globePanel = .notifications
        Task { await refreshNotifications() }
    }

    func presentCreateSheet(_ sheet: CreateContentSheet) async {
        guard let home = await resolveHomeCountry() else {
            showToast("Set your home country in profile before posting.", style: .error)
            return
        }
        composerCountry = home
        showCreateMenu = false
        activeCreateSheet = sheet
    }

    func needsRepeatShareWarning(for post: CountryPost) -> Bool {
        guard let profile = currentProfile,
              let countryCode = homeCountryISO?.uppercased()
        else { return false }

        let originalID = post.sharedPostID ?? post.id

        if let postCountry = post.countryCode?.uppercased(),
           postCountry == countryCode,
           post.authorID == profile.userID,
           post.sharedPostID == nil {
            return true
        }

        let cachedPosts =
            (ContentCache.shared.posts(for: .homeFeed) ?? [])
            + (ContentCache.shared.posts(for: .profilePosts) ?? [])

        return cachedPosts.contains { item in
            item.authorID == profile.userID && item.sharedPostID == originalID
        }
    }

    func sharePostToCountryFeed(_ post: CountryPost) async -> String {
        guard isAuthenticated else { return "Sign in to share." }
        guard !post.isStory else {
            return "Moments live in Globe — they can't be shared as feed posts."
        }
        if let shared = post.sharedPost, shared.asCountryPost.isStory {
            return "Moments live in Globe — they can't be shared as feed posts."
        }
        guard let profile = currentProfile,
              let countryCode = homeCountryISO,
              let countryName = profile.countryName, !countryName.isEmpty
        else {
            return "Set your home country to share."
        }

        do {
            _ = try await PostsService.shared.sharePostToCountryFeed(
                post: post,
                countryName: countryName,
                countryCode: countryCode,
                cityName: profile.cityName
            )
            ContentCache.shared.invalidate(.homeFeed, .livingVideos)
            contentLoadGeneration += 1
            NotificationCenter.default.post(name: .userPostsDidChange, object: nil)
            if let sourceCountry = post.countryName, sourceCountry != countryName {
                return "Shared from \(sourceCountry) to your \(countryName) feed."
            }
            return "Shared to your \(countryName) feed."
        } catch {
            return error.localizedDescription
        }
    }

    func reloadContent() {
        ContentCache.shared.invalidateAllFeeds()
        contentLoadGeneration += 1
    }

    func refreshStories() async {
        storyGroups = await PostsService.shared.loadActiveStoryGroups(
            countryCode: currentProfile?.countryCode?.uppercased(),
            followingIDs: followingIDs,
            viewedStoryIDs: viewedStoryIDs,
            currentUserID: currentProfile?.userID
        )
    }

    func mergeStoryPost(_ post: CountryPost) {
        guard post.isStory, post.isStoryActive else { return }
        guard !BlockService.shared.isBlocked(post.authorID) else { return }
        guard storyRelevant(post) else { return }
        guard !storyGroups.contains(where: { $0.stories.contains(where: { $0.id == post.id }) }) else { return }

        if let index = storyGroups.firstIndex(where: { $0.authorID == post.authorID }) {
            let current = storyGroups[index]
            var stories = current.stories
            stories.append(post)
            stories.sort { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            let hasUnviewed = stories.contains { !viewedStoryIDs.contains($0.id) }
            storyGroups[index] = StoryGroup(
                authorID: current.authorID,
                author: current.author ?? post.author,
                stories: stories,
                hasUnviewed: hasUnviewed
            )
        } else {
            let hasUnviewed = !viewedStoryIDs.contains(post.id)
            storyGroups.append(
                StoryGroup(
                    authorID: post.authorID,
                    author: post.author,
                    stories: [post],
                    hasUnviewed: hasUnviewed
                )
            )
        }
        sortStoryGroups()
    }

    func removeStoryPost(id: String) {
        var changed = false
        storyGroups = storyGroups.compactMap { group in
            let remaining = group.stories.filter { $0.id != id }
            guard remaining.count != group.stories.count else { return group }
            changed = true
            guard !remaining.isEmpty else { return nil }
            return StoryGroup(
                authorID: group.authorID,
                author: group.author,
                stories: remaining,
                hasUnviewed: remaining.contains { !viewedStoryIDs.contains($0.id) }
            )
        }
        guard changed else { return }
        sortStoryGroups()
    }

    private func storyRelevant(_ post: CountryPost) -> Bool {
        if post.authorID == currentProfile?.userID { return true }
        let viewerCountry = currentProfile?.countryCode?.uppercased()
        let postCountry = post.countryCode?.uppercased()
        if let viewerCountry, let postCountry, viewerCountry == postCountry {
            return true
        }
        return followingIDs.contains(post.authorID)
    }

    private func storyRelevant(authorID: String?, countryCode: String?) -> Bool {
        guard let authorID, !authorID.isEmpty else { return false }
        if authorID == currentProfile?.userID { return true }
        let viewerCountry = currentProfile?.countryCode?.uppercased()
        let eventCountry = countryCode?.uppercased()
        if let viewerCountry, let eventCountry, viewerCountry == eventCountry {
            return true
        }
        return followingIDs.contains(authorID)
    }

    private func sortStoryGroups() {
        let currentUserID = currentProfile?.userID
        storyGroups.sort { lhs, rhs in
            if lhs.authorID == currentUserID { return true }
            if rhs.authorID == currentUserID { return false }
            if lhs.hasUnviewed != rhs.hasUnviewed { return lhs.hasUnviewed }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func startPostRealtime() {
        installPostRealtimeObserversIfNeeded()
        PostEventsService.shared.start()
    }

    private func stopPostRealtime() {
        PostEventsService.shared.stop()
        for observer in postEventsObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        postEventsObservers.removeAll()
    }

    private func installPostRealtimeObserversIfNeeded() {
        guard postEventsObservers.isEmpty else { return }

        postEventsObservers.append(
            NotificationCenter.default.addObserver(
                forName: .postRealtimeInsert,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let event = Self.parseRealtimeInsert(notification.userInfo)
                else { return }
                Task { await self.handlePostRealtimeInsert(event) }
            }
        )

        postEventsObservers.append(
            NotificationCenter.default.addObserver(
                forName: .postRealtimeDelete,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let event = Self.parseRealtimeDelete(notification.userInfo)
                else { return }
                Task { await self.handlePostRealtimeDelete(event) }
            }
        )
    }

    private func handlePostRealtimeInsert(_ event: PostRealtimeInsert) async {
        guard isAuthenticated else { return }
        guard let authorID = event.authorID, !authorID.isEmpty else { return }
        guard authorID != currentProfile?.userID else { return }
        guard storyRelevant(authorID: authorID, countryCode: event.countryCode) else { return }
        guard !BlockService.shared.isBlocked(authorID) else { return }
        guard let post = try? await PostsService.shared.getPostByID(event.id) else { return }
        mergeStoryPost(post)
    }

    private func handlePostRealtimeDelete(_ event: PostRealtimeDelete) async {
        guard isAuthenticated else { return }
        removeStoryPost(id: event.id)
    }

    private static func parseRealtimeInsert(_ userInfo: [AnyHashable: Any]?) -> PostRealtimeInsert? {
        guard let userInfo,
              let id = userInfo["id"] as? String,
              !id.isEmpty
        else { return nil }
        return PostRealtimeInsert(
            id: id,
            countryCode: userInfo["countryCode"] as? String,
            authorID: userInfo["authorID"] as? String
        )
    }

    private static func parseRealtimeDelete(_ userInfo: [AnyHashable: Any]?) -> PostRealtimeDelete? {
        guard let userInfo,
              let id = userInfo["id"] as? String,
              !id.isEmpty
        else { return nil }
        return PostRealtimeDelete(
            id: id,
            countryCode: userInfo["countryCode"] as? String,
            authorID: userInfo["authorID"] as? String
        )
    }

    var viewedStoryIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: viewedStoriesDefaultsKey) ?? [])
    }

    func markStoryViewed(_ postID: String) {
        var ids = viewedStoryIDs
        ids.insert(postID)
        UserDefaults.standard.set(Array(ids), forKey: viewedStoriesDefaultsKey)
        Task { await refreshStories() }
    }

    func openStoryViewer(group: StoryGroup) {
        guard let index = storyGroups.firstIndex(where: { $0.id == group.id }) else { return }
        storyViewerContext = StoryViewerContext(groups: storyGroups, groupIndex: index, storyIndex: 0)
    }

    func openStoryComposerOrViewer() async {
        if let mine = storyGroups.first(where: { $0.authorID == currentProfile?.userID }), !mine.stories.isEmpty {
            openStoryViewer(group: mine)
        } else {
            await presentCreateSheet(.story)
        }
    }

    func isFollowing(_ userID: String) -> Bool {
        followingIDs.contains(userID)
    }

    func toggleFollow(_ userID: String) async {
        guard !userID.hasPrefix("user_"), userID != currentProfile?.userID else { return }
        do {
            if followingIDs.contains(userID) {
                try await followService.unfollow(targetID: userID)
                followingIDs.remove(userID)
            } else {
                try await followService.follow(targetID: userID)
                followingIDs.insert(userID)
            }
        } catch {
            showToast(error.localizedDescription, style: .error)
        }
    }

    func blockUser(_ userID: String, username: String? = nil, displayName: String? = nil) {
        BlockService.shared.block(userID: userID, username: username, displayName: displayName)
        if followingIDs.contains(userID) {
            followingIDs.remove(userID)
        }
        reloadContent()
        showToast("Account blocked")
    }

    func unblockUser(_ userID: String) {
        BlockService.shared.unblock(userID)
        showToast("Account unblocked")
    }

    func markNotificationRead(_ notification: NotificationItem) async {
        applyLocalNotificationRead(notification)
        try? await notificationsService.markRead(notification.id)
        await refreshUnreadCounts()
    }

    func markAllNotificationsRead() async {
        notifications = notifications.map { $0.markedAsRead() }
        notificationsUnreadCount = 0
        try? await notificationsService.markAllRead()
        await refreshNotifications()
    }

    func openNotification(_ notification: NotificationItem) async {
        globePanel = nil
        showAppMenu = false
        applyLocalNotificationRead(notification)

        let type = notification.type.lowercased()

        if let conversationID = notification.conversationID {
            try? await notificationsService.markRead(notification.id)
            openConversation(id: conversationID)
            await refreshUnreadCounts()
            await refreshNotifications()
            return
        }

        if type == "follow", let actorID = notification.actorUserID {
            try? await notificationsService.markRead(notification.id)
            selectedTab = .feed
            navigationPath.removeAll()
            openPublicProfile(username: notification.actor?.username, userID: actorID)
            await refreshNotifications()
            return
        }

        if let postID = notification.resolvedPostID {
            try? await notificationsService.markRead(notification.id)
            openNotificationPost(id: postID)
            await refreshNotifications()
            return
        }

        if let actorID = notification.actorUserID {
            try? await notificationsService.markRead(notification.id)
            selectedTab = .feed
            navigationPath.removeAll()
            openPublicProfile(username: notification.actor?.username, userID: actorID)
            await refreshNotifications()
            return
        }

        try? await notificationsService.markRead(notification.id)
        await refreshNotifications()
    }

    func openNotificationPost(id: String) {
        selectedTab = .feed
        navigationPath.removeAll()
        navigate(to: .post(id))
    }

    private func applyLocalNotificationRead(_ notification: NotificationItem) {
        guard notification.isUnread else { return }
        notifications = notifications.map { item in
            item.id == notification.id ? item.markedAsRead() : item
        }
        notificationsUnreadCount = max(0, notificationsUnreadCount - 1)
    }

    private func startPresence() {
        presenceService.startHeartbeat(viewingISO: selectedCountry?.iso ?? currentProfile?.countryCode)
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                await refreshUnreadCounts()
                await refreshNotifications()
                try? await Task.sleep(nanoseconds: 45_000_000_000)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func handleInternalDeepLink(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "matterya" || scheme == "worldapp" else { return false }

        let host = (url.host ?? "").lowercased()
        let pathParts = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .map(String.init)

        if host == "tab" {
            let tabName = pathParts.first?.lowercased() ?? ""
            guard let tab = AppTab(rawValue: tabName) else { return false }
            showAppMenu = false
            globePanel = nil
            navigationPath.removeAll()
            selectedTab = tab
            return true
        }

        if host == "search" {
            showAppMenu = false
            globePanel = nil
            selectedTab = .feed
            navigationPath = [.search]
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            pendingSearchQuery = components?
                .queryItems?
                .first(where: { $0.name == "q" })?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if pendingSearchQuery?.isEmpty == true {
                pendingSearchQuery = pathParts.first
            }
            return true
        }

        return false
    }

    private func applyScreenshotMode() async {
        isAuthenticated = true
        needsProfileSetup = false
        currentProfile = ScreenshotMode.demoProfile
        ContentCache.shared.setProfile(ScreenshotMode.demoProfile)

        let demoPosts = await DemoDatasetService.shared.sampleGlobalPosts(limit: 40)
        let feedPosts = Array(demoPosts.filter { !$0.isStory }.excludingSparks().prefix(24))
        let hubPosts = demoPosts.filter { $0.hasVideo && !$0.isStory }
        let profilePosts = Array(feedPosts.prefix(6))

        if !feedPosts.isEmpty {
            ContentCache.shared.setPosts(feedPosts, for: .homeFeed)
        }
        if !hubPosts.isEmpty {
            ContentCache.shared.setPosts(hubPosts, for: .livingVideos)
        }
        if !profilePosts.isEmpty {
            ContentCache.shared.setPosts(profilePosts, for: .profilePosts)
        }

        isSessionReady = true
        contentLoadGeneration += 1

        if let tab = ScreenshotMode.tab {
            selectedTab = tab
        }

        navigationPath.removeAll()
        if let route = ScreenshotMode.route {
            navigationPath.append(route)
            if case .search = route {
                pendingSearchQuery = ScreenshotMode.searchQuery
            }
        }
    }
}