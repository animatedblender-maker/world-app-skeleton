import Foundation
import Observation
import UIKit
import UserNotifications

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
        let socialUnread = notifications.filter { !$0.isMessageType && $0.isUnread }.count
        if !notifications.isEmpty {
            return socialUnread
        }
        return notificationsUnreadCount
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
    /// Deep-link / feed → open this video on the Hubs tab (watch route).
    var pendingLivingVideoID: String?
    /// Full post when available so Hubs can open watch immediately without a re-fetch race.
    var pendingLivingVideo: CountryPost?
    var pendingPlayTab: YouTubeMainTab?
    var pendingPlayChannelAuthorID: String?
    var pendingPlayChannelUsername: String?

    // MARK: - Global hub continuous playback (survives tabs + minimize)
    /// Active long-form hubs video. Owned by `GlobalHubPlaybackLayer` (single AVPlayer).
    var hubPlaybackPost: CountryPost?
    /// `true` = full watch stage on Hubs; `false` = mini player above the tab bar (any tab).
    var hubPlaybackExpanded = false
    var hubPlaybackPlaying = true
    var hubPlaybackMuted = false
    /// When a conversation is open, mini player docks under the chat composer (not floating).
    var hubPlaybackDockInChat: Bool {
        guard hubPlaybackPost != nil, !hubPlaybackExpanded else { return false }
        return currentConversationIDOnPath() != nil
    }
    /// If set, minimize returns to this chat (opened/expanded from that conversation).
    private(set) var hubPlaybackReturnConversationID: String?
    var showAppMenu = false
    var floatingPosts: [CountryPost] = []
    var errorMessage: String?
    var toastMessage: String?
    var toastStyle: ToastBanner.ToastStyle = .info
    var sharePostSheet: CountryPost?
    var quotedSharePostID: String?
    var pendingSearchQuery: String?
    /// Bumped to scroll the home feed to the top (after post / share video).
    var feedScrollToTopToken: Int = 0

    /// Queued when a push / in-app notification is tapped before MainTabView is ready.
    private var pendingPushRoute: PendingPushRoute?

    private let auth = AuthService.shared
    private let profileService = ProfileService.shared
    private let notificationsService = NotificationsService.shared
    private let presenceService = PresenceService.shared
    private let followService = FollowService.shared
    private var pollTask: Task<Void, Never>?

    private struct PendingPushRoute: Equatable {
        var type: String
        var conversationID: String?
        var postID: String?
        var username: String?
    }

    func bootstrap() async {
        if ScreenshotMode.isActive {
            await applyScreenshotMode()
            return
        }

        await AppPermissionsService.shared.requestEssentialPermissionsOnLaunch()

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
        flushPendingPushRoute()
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
        // ── Fast path: paint feed from cache/demo in <1s. Never block on hubs/GraphQL. ──
        // Disk cache already restored by ContentCache.init.
        // Demo seed fills empty cache (small JSONL; actor work, not main-thread I/O).
        if AppConfig.useDemoDataset, ContentCache.shared.posts(for: .homeFeed) == nil {
            let sample = await DemoDatasetService.shared.sampleGlobalPosts(limit: 40)
            if !sample.isEmpty {
                ContentCache.shared.setPosts(sample, for: .homeFeed)
                ImageCache.shared.prefetchFeedMedia(Array(sample.prefix(12)), maxPixelSize: 360)
            }
            #if DEBUG
            print("[DemoDataset] warmup posts=\(sample.count)")
            #endif
        } else if let cached = ContentCache.shared.posts(for: .homeFeed) {
            ImageCache.shared.prefetchFeedMedia(Array(cached.prefix(12)), maxPixelSize: 360)
        }

        // Feed can paint now — secondary work is non-blocking.
        contentLoadGeneration += 1

        Task(priority: .utility) {
            await prepareSession()
            await refreshProfile()
            await refreshAllInBackground()
        }
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
            await PushNotificationService.shared.registerForRemoteNotificationsIfAuthorized()
            await VoIPPushService.shared.ensureToken()
            await PushNotificationService.shared.syncWithServer(force: true)
        }
    }

    func refreshAll() async {
        await refreshProfile()
        await refreshAllInBackground()
    }

    private func refreshAllInBackground() async {
        // Lightweight social state first — never await full hub seed (thousands of videos).
        async let statsTask: Void = { await refreshGlobalStats() }()
        async let followingTask: Void = { await refreshFollowingIDs() }()
        async let savedTask: Void = { await refreshSavedPosts() }()
        async let storiesTask: Void = { await refreshStories() }()
        async let notificationsTask: Void = { await refreshNotifications() }()
        // Soft network refresh only when home-feed cache is stale; never blocks UI.
        async let feedTask: Void = {
            _ = await PostsService.shared.loadHomeFeed(forceRefresh: false)
        }()
        _ = await (statsTask, followingTask, savedTask, storiesTask, notificationsTask, feedTask)
        startPresence()
        // Hubs catalog is on-demand (Hubs tab / play). Slug-capped sample only.
        Task(priority: .background) {
            _ = await PostsService.shared.loadLivingVideos(forceRefresh: false)
        }
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
        // Signing in reactivates a soft-deactivated account.
        Task { await reactivateIfNeeded() }
    }

    /// If the profile was deactivated, restore it on successful sign-in.
    func reactivateIfNeeded() async {
        do {
            let profile = try await profileService.meProfile()
            if profile?.isDeleted == true {
                showToast("This account was permanently deleted.", style: .error)
                logout()
                return
            }
            if profile?.isDeactivated == true {
                let result = try await profileService.reactivateAccount()
                if result.ok {
                    showToast(result.message ?? "Welcome back — account reactivated.", style: .success)
                    await refreshProfile()
                }
            }
        } catch {
            // Non-fatal: profile load may still succeed later.
        }
    }

    func deactivateAccount() async throws {
        let result = try await profileService.deactivateAccount()
        guard result.ok else {
            throw AuthError.server(result.message ?? "Could not deactivate account.")
        }
        showToast(result.message ?? "Account deactivated.", style: .info)
        logout()
    }

    func deleteAccount(confirmation: String) async throws {
        let result = try await profileService.deleteAccount(confirmation: confirmation)
        guard result.ok else {
            throw AuthError.server(result.message ?? "Could not delete account.")
        }
        showToast(result.message ?? "Account deleted.", style: .info)
        logout()
    }

    func logout() {
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
        clearPendingLivingVideo()
        clearPendingPlayRouting()
        stopHubPlayback()
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
        // Never surface GraphQL Yoga masked failures for engagement / missing seed rows.
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("unexpected error")
            || trimmed.caseInsensitiveCompare("Unexpected error") == .orderedSame {
            return
        }
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

    // MARK: - Letters (legacy destinations still linked from older UI)

    var letterComposePresented = false
    var letterFlightEvent: LetterFlightEvent?

    func presentLetterCompose() {
        letterComposePresented = true
        navigate(to: .letters)
    }

    func presentLetterFlight(_ event: LetterFlightEvent) {
        letterFlightEvent = event
    }

    func dismissLetterFlight() {
        letterFlightEvent = nil
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
        case .people, .ads, .editProfile, .settings, .premium, .search, .letters, .letterThread:
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
        // Cold start / still booting → queue and apply once the main UI is up.
        guard isAuthenticated, isSessionReady else {
            pendingPushRoute = PendingPushRoute(
                type: type,
                conversationID: conversationID,
                postID: postID,
                username: username
            )
            return
        }
        applyPushNavigation(
            type: type,
            conversationID: conversationID,
            postID: postID,
            username: username
        )
    }

    func flushPendingPushRoute() {
        guard let pending = pendingPushRoute else { return }
        guard isAuthenticated, isSessionReady else { return }
        pendingPushRoute = nil
        applyPushNavigation(
            type: pending.type,
            conversationID: pending.conversationID,
            postID: pending.postID,
            username: pending.username
        )
    }

    private func applyPushNavigation(
        type: String,
        conversationID: String?,
        postID: String?,
        username: String?
    ) {
        showAppMenu = false
        globePanel = nil
        reelsViewerContext = nil
        isPlayPresented = false
        let normalized = type.lowercased()

        if normalized == "message", let conversationID, !conversationID.isEmpty {
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

        // Like / comment / reply / comment_like → open the post immediately.
        if let postID, !postID.isEmpty {
            openNotificationPost(
                id: postID,
                preferComments: Self.notificationTypeOpensComments(normalized)
            )
            return
        }

        // No post id in the push — still surface the in-app list so the user isn't stranded.
        globePanel = .notifications
        Task { await refreshNotifications() }
    }

    private static func notificationTypeOpensComments(_ type: String) -> Bool {
        switch type {
        case "comment", "comment_like", "comment_reply", "reply":
            return true
        default:
            return false
        }
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
        // Keep Hubs audio going as mini while chatting (dock under composer).
        minimizeHubPlayback(returnToChat: false)
        // Prefer this chat as the minimize-return target while watching.
        if hubPlaybackPost != nil {
            hubPlaybackReturnConversationID = id
        }
        selectedTab = .messages
        navigationPath.removeAll { destination in
            if case .conversation = destination { return true }
            return false
        }
        navigationPath.append(.conversation(id))
        // Clear banners + unread for this chat as soon as we open it.
        Task { await clearNotifications(forConversation: id) }
    }

    /// Removes Notification Center banners and marks server message notifications read for a chat.
    func clearNotifications(forConversation conversationID: String) async {
        let trimmed = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await PushNotificationService.shared.clearDeliveredNotifications(forConversation: trimmed)

        // Mark DB rows (type=message, entity=conversation) so they don't linger unread.
        // Cap work: only scan recent notifications once when opening a chat (not per message).
        let all = await notificationsService.list(limit: 40)
        for item in all where item.isMessageType && item.isUnread && item.conversationID == trimmed {
            try? await notificationsService.markRead(item.id)
        }

        await refreshUnreadCounts()
        await syncAppIconBadge()
    }

    /// Keep the home-screen badge in sync after clearing chat notifications.
    func syncAppIconBadge() async {
        let total = messagesUnreadCount + effectiveNotificationsUnreadCount
        if #available(iOS 16.0, *) {
            try? await UNUserNotificationCenter.current().setBadgeCount(total)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = total
        }
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
        let trimmedID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        EngagementTracker.shared.profileOpened(userID: trimmedID, username: trimmedUsername)
        // Prefer stable userID for postsByAuthor — username resolution can lag or miss,
        // which left public profiles empty on cold Mac sessions while phone cache hid it.
        if !trimmedID.isEmpty {
            navigate(to: .publicProfileByUserID(trimmedID))
        } else if let trimmedUsername, !trimmedUsername.isEmpty {
            navigate(to: .publicProfile(username: trimmedUsername))
        }
    }

    func presentPlaySurface() {
        // Never use a full-screen cover that steals the tab bar — Hubs is a real tab.
        openPlay(tab: .home)
    }

    func dismissPlay() {
        isPlayPresented = false
        clearPendingLivingVideo()
        clearPendingPlayRouting()
    }

    /// Start / switch the single global hubs player. Stops feed audio first so nothing doubles.
    /// - Parameter expanded: full Hubs watch (player + comments). Elsewhere use mini.
    func startHubPlayback(_ post: CountryPost, expanded: Bool = true) {
        showAppMenu = false
        globePanel = nil
        reelsViewerContext = nil
        isPlayPresented = false
        clearPendingLivingVideo()

        if expanded {
            // Remember chat (if any), then open real Hubs watch — never overlay on chat.
            rememberHubPlaybackChatReturnIfNeeded()
            navigationPath.removeAll()
            selectedTab = .hubs
        }

        let switchingVideo = hubPlaybackPost?.id != post.id
        if switchingVideo {
            // Kill feed / previous hub audio only when the source changes.
            // Same post re-expand must NOT tear down the continuous AVPlayer.
            MediaPlaybackCoordinator.shared.stopAllPlayback()
            hubPlaybackPost = post
            hubPlaybackMuted = false
        } else {
            // Same post — still refresh the model if the new payload has a playable URL.
            if hubPlaybackPost?.playableVideoURL == nil, post.playableVideoURL != nil {
                hubPlaybackPost = post
            }
        }

        hubPlaybackPlaying = true
        if expanded {
            selectedTab = .hubs
            hubPlaybackExpanded = true
        } else {
            hubPlaybackExpanded = false
        }
        YouTubeCatalogService.shared.recordWatch(post.id)
        // Pre-resolve Archive CDN so first frame appears almost immediately.
        if let url = post.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) {
            ArchiveVideoPlayback.warmResolve(url)
        }
        ImageCache.shared.prefetchPostThumbnails([post], maxPixelSize: 720)
    }

    /// Collapse to mini.
    /// If this session started from a chat and user hasn't navigated elsewhere, restore that chat.
    /// Chat messages stay warm in `MessagesService` cache so re-open is instant.
    func minimizeHubPlayback(returnToChat: Bool = true) {
        guard hubPlaybackPost != nil else { return }
        hubPlaybackExpanded = false
        hubPlaybackPlaying = true

        // Drop return target if user already left that chat while minimized.
        syncHubPlaybackChatReturnWithPath()

        if returnToChat, let conversationID = hubPlaybackReturnConversationID {
            selectedTab = .messages
            navigationPath = [.conversation(conversationID)]
        }
    }

    /// Leaving Hubs always collapses to the mini player (keep watching elsewhere).
    /// Tab switches do not force a chat return — only explicit minimize does.
    func ensureHubPlaybackMinimizedIfNeeded() {
        guard hubPlaybackPost != nil, selectedTab != .hubs else { return }
        minimizeHubPlayback(returnToChat: false)
    }

    /// Tap miniplayer (from chat dock or floating bar) → full Hubs watch with comments.
    func expandHubPlayback() {
        guard hubPlaybackPost != nil else { return }
        rememberHubPlaybackChatReturnIfNeeded()
        // Always leave chat / other pushes so Hubs watch (player + comments) is the real screen.
        navigationPath.removeAll()
        selectedTab = .hubs
        hubPlaybackExpanded = true
        hubPlaybackPlaying = true
    }

    func stopHubPlayback() {
        hubPlaybackPost = nil
        hubPlaybackExpanded = false
        hubPlaybackPlaying = false
        hubPlaybackReturnConversationID = nil
        MediaPlaybackCoordinator.shared.stopAllPlayback()
    }

    /// Conversation id currently on the nav stack (if any).
    func currentConversationIDOnPath() -> String? {
        for destination in navigationPath.reversed() {
            if case .conversation(let id) = destination { return id }
        }
        return nil
    }

    /// Remember chat only when the user is currently inside that conversation.
    private func rememberHubPlaybackChatReturnIfNeeded() {
        if let id = currentConversationIDOnPath() {
            hubPlaybackReturnConversationID = id
        }
    }

    /// If the user navigated away from the pinned chat while mini, forget return-to-chat.
    func syncHubPlaybackChatReturnWithPath() {
        guard let returnID = hubPlaybackReturnConversationID else { return }
        // While expanded on Hubs, path is cleared — keep the pin until minimize.
        if hubPlaybackExpanded { return }
        if currentConversationIDOnPath() != returnID {
            hubPlaybackReturnConversationID = nil
        }
    }

    func openLivingVideo(postID: String, tab: YouTubeMainTab? = nil, post: CountryPost? = nil) {
        // Always open real Hubs watch (player + comments). Remember chat for minimize return.
        rememberHubPlaybackChatReturnIfNeeded()
        navigationPath.removeAll()
        showAppMenu = false
        globePanel = nil
        reelsViewerContext = nil
        isPlayPresented = false
        if let tab { pendingPlayTab = tab }

        if let post, post.id == postID, post.hasVideo {
            startHubPlayback(post, expanded: true)
            return
        }

        pendingLivingVideoID = postID
        pendingLivingVideo = (post?.id == postID) ? post : nil
        selectedTab = .hubs
        hubPlaybackExpanded = true
        // Stop feed audio even while Hubs resolves the id.
        MediaPlaybackCoordinator.shared.stopAllPlayback()
    }

    func clearPendingLivingVideo() {
        pendingLivingVideoID = nil
        pendingLivingVideo = nil
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
        } else if PlayPlatformBridge.isHubCatalogContent(post), post.hasVideo {
            // Only true Hubs content opens the Hubs watch surface.
            openLivingVideo(postID: post.id, tab: .home, post: post)
        } else {
            // Plain feed videos (no channel / no hub marker) → post detail only.
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
        // Fresh shuffle every open — different recommendations each time.
        let seed = UInt64.random(in: 1...UInt64.max) ^ UInt64(Date().timeIntervalSince1970 * 1_000)
        let sparks = await HubVideoSeedService.shared.sparkSeedVideos(limit: 40, shuffleSeed: seed)
        let network = await PostsService.shared.loadReelsFeed(
            viewerCountry: currentProfile?.countryCode,
            followingIDs: followingIDs
        )
        var seen = Set<String>()
        var reels: [CountryPost] = []
        for post in sparks + network {
            guard seen.insert(post.id).inserted else { continue }
            guard post.hasVideo, !post.isStory else { continue }
            reels.append(post)
        }
        guard let first = reels.first else {
            showToast("\(MatteryaCopy.noSparksYet) — publish one to get started.", style: .info)
            openPlay()
            return
        }
        // Pre-buffer first + next three before the viewer appears.
        SparkWarmPool.shared.prepare(posts: reels, around: 0, ahead: 3, behind: 0)
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

    /// Pending hubs composer after first-time channel setup (video vs spark).
    private var pendingHubCreateSheet: CreateContentSheet?

    /// Hub long-form: only users who want to upload to Hubs get a channel.
    /// No channel yet → Channel setup, then open the hub video composer.
    func presentHubVideoCreate() async {
        showCreateMenu = false
        if LivingChannelMarker.hasChannel(profile: currentProfile) {
            await presentCreateSheet(.hubVideo)
        } else {
            pendingHubCreateSheet = .hubVideo
            // Channel setup does not require home country first; posting after will.
            activeCreateSheet = .channelSetup
        }
    }

    /// Sparks on Hubs: same channel gate as long-form.
    func presentHubSparkCreate() async {
        showCreateMenu = false
        if LivingChannelMarker.hasChannel(profile: currentProfile) {
            await presentCreateSheet(.reel)
        } else {
            pendingHubCreateSheet = .reel
            activeCreateSheet = .channelSetup
        }
    }

    /// Called when ChannelSetupView finishes — continue to hubs composer.
    func completeChannelSetupAndContinue() async {
        let next = pendingHubCreateSheet ?? .hubVideo
        pendingHubCreateSheet = nil
        // Refresh profile so hasChannel is true for subsequent opens.
        if let me = currentProfile {
            if let fresh = try? await ProfileService.shared.profileByID(me.userID) {
                currentProfile = fresh
            }
        }
        await presentCreateSheet(next)
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

    func sharePostToCountryFeed(_ post: CountryPost, caption: String? = nil) async -> String {
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

        // Video shares: land on feed top with an uploading shadow first.
        var placeholderID: String?
        if post.hasVideo, !post.isReel {
            placeholderID = beginFeedVideoUpload(
                caption: caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? caption!
                    : (post.displayHeadline ?? post.displayBody),
                previewImage: nil,
                isHub: PlayPlatformBridge.isHubCatalogContent(post) || post.isHubSeedVideo
            )
            HomeFeedStore.shared.updateVideoUpload(
                id: placeholderID!,
                progress: 0.35,
                phaseLabel: "Sharing"
            )
        }

        do {
            let created = try await PostsService.shared.sharePostToCountryFeed(
                post: post,
                countryName: countryName,
                countryCode: countryCode,
                cityName: profile.cityName,
                caption: caption
            )
            if let placeholderID {
                finishFeedVideoUpload(placeholderID: placeholderID, post: created)
            } else {
                ContentCache.shared.invalidate(.homeFeed, .livingVideos)
                contentLoadGeneration += 1
                NotificationCenter.default.post(
                    name: .userPostsDidChange,
                    object: nil,
                    userInfo: ["post": created]
                )
                HomeFeedStore.shared.insertNewPost(created)
                goToFeedTop(scroll: true)
            }
            if let sourceCountry = post.countryName, sourceCountry != countryName {
                return "Shared from \(sourceCountry) to your \(countryName) feed."
            }
            return "Shared to your \(countryName) feed."
        } catch {
            if let placeholderID {
                failFeedVideoUpload(placeholderID: placeholderID, message: error.localizedDescription)
            }
            return error.localizedDescription
        }
    }

    func reloadContent() {
        ContentCache.shared.invalidateAllFeeds()
        contentLoadGeneration += 1
    }

    /// Jump to home feed top — used after posting/sharing a video so the new card is visible.
    func goToFeedTop(scroll: Bool = true) {
        showCreateMenu = false
        activeCreateSheet = nil
        showAppMenu = false
        globePanel = nil
        navigationPath.removeAll()
        selectedTab = .feed
        if scroll {
            feedScrollToTopToken += 1
        }
    }

    /// Register an uploading video shadow on the feed and navigate there immediately.
    @discardableResult
    func beginFeedVideoUpload(
        caption: String,
        previewImage: UIImage?,
        isHub: Bool
    ) -> String {
        let id = HomeFeedStore.shared.beginVideoUpload(
            caption: caption,
            previewImage: previewImage,
            isHub: isHub
        )
        goToFeedTop(scroll: true)
        return id
    }

    func finishFeedVideoUpload(placeholderID: String, post: CountryPost) {
        HomeFeedStore.shared.completeVideoUpload(id: placeholderID, post: post)
        ContentCache.shared.invalidate(.homeFeed, .livingVideos, .profilePosts)
        NotificationCenter.default.post(
            name: .userPostsDidChange,
            object: nil,
            userInfo: ["post": post]
        )
        goToFeedTop(scroll: true)
        showToast(
            HubChannelPostMarker.isMarked(post.body)
                ? "Published to \(MatteryaCopy.matteryaHubs)"
                : "Posted to your feed",
            style: .success
        )
    }

    func failFeedVideoUpload(placeholderID: String, message: String) {
        HomeFeedStore.shared.failVideoUpload(id: placeholderID, message: message)
        showToast(message, style: .error)
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

    private func sortStoryGroups() {
        let currentUserID = currentProfile?.userID
        storyGroups.sort { lhs, rhs in
            if lhs.authorID == currentUserID { return true }
            if rhs.authorID == currentUserID { return false }
            if lhs.hasUnviewed != rhs.hasUnviewed { return lhs.hasUnviewed }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var viewedStoryIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: viewedStoriesDefaultsKey) ?? [])
    }

    func markStoryViewed(_ postID: String) {
        var ids = viewedStoryIDs
        ids.insert(postID)
        UserDefaults.standard.set(Array(ids), forKey: viewedStoriesDefaultsKey)

        for index in storyGroups.indices {
            let group = storyGroups[index]
            guard group.stories.contains(where: { $0.id == postID }) else { continue }
            let hasUnviewed = group.stories.contains { !ids.contains($0.id) }
            guard group.hasUnviewed != hasUnviewed else { break }
            storyGroups[index] = StoryGroup(
                authorID: group.authorID,
                author: group.author,
                stories: group.stories,
                hasUnviewed: hasUnviewed
            )
            break
        }
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
        let id = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != currentProfile?.userID else { return }

        // Optimistic UI first so hub/fake Follow feels instant.
        let wasFollowing = followingIDs.contains(id)
        if wasFollowing {
            followingIDs.remove(id)
        } else {
            followingIDs.insert(id)
        }

        do {
            if wasFollowing {
                try await followService.unfollow(targetID: id)
            } else {
                try await followService.follow(targetID: id)
            }
            // Re-merge remote + local so server follows stay in sync.
            followingIDs = await followService.followingIDs()
            contentLoadGeneration += 1
            if FollowService.usesLocalFollow(userID: id) {
                showToast(wasFollowing ? "Unfollowed" : "Following", style: .info)
            }
        } catch {
            // Roll back optimistic update.
            if wasFollowing {
                followingIDs.insert(id)
            } else {
                followingIDs.remove(id)
            }
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
        do {
            try await notificationsService.markAllRead()
        } catch {
            showToast("Could not mark notifications read", style: .error)
            return
        }
        notifications = notifications.map { $0.markedAsRead() }
        notificationsUnreadCount = 0
        await refreshUnreadCounts()
    }

    func openNotification(_ notification: NotificationItem) async {
        // Navigate first (sync). Network mark-read happens after so a slow API
        // never blocks opening the like/comment target.
        applyLocalNotificationRead(notification)
        let type = notification.type.lowercased()
        let opened = routeNotificationDestination(notification, type: type)

        Task {
            try? await notificationsService.markRead(notification.id)
            await refreshUnreadCounts()
            await refreshNotifications()
        }

        if !opened {
            showToast("Couldn’t open that notification.", style: .error)
        }
    }

    /// Returns true if a concrete destination was opened.
    @discardableResult
    private func routeNotificationDestination(_ notification: NotificationItem, type: String) -> Bool {
        showAppMenu = false
        reelsViewerContext = nil
        isPlayPresented = false

        if let conversationID = notification.conversationID {
            globePanel = nil
            openConversation(id: conversationID)
            return true
        }

        if type == "follow", let actorID = notification.actorUserID {
            globePanel = nil
            openPublicProfile(username: notification.actor?.username, userID: actorID)
            return true
        }

        // Like / comment / reply → open the post immediately (PostDetailView loads it).
        if let postID = notification.resolvedPostID {
            openNotificationPost(id: postID)
            return true
        }

        if notification.entityType?.lowercased() == "post",
           let entityID = notification.entityID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !entityID.isEmpty
        {
            openNotificationPost(id: entityID)
            return true
        }

        // Last resort: any non-empty entity_id for social types is treated as a post id.
        if ["like", "comment", "comment_like", "comment_reply", "reply", "mention", "share"].contains(type),
           let entityID = notification.entityID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !entityID.isEmpty
        {
            openNotificationPost(id: entityID)
            return true
        }

        if let actorID = notification.actorUserID {
            globePanel = nil
            openPublicProfile(username: notification.actor?.username, userID: actorID)
            return true
        }

        globePanel = nil
        return false
    }

    /// Opens the post a social notification refers to (like / comment / reply).
    /// Always pushes PostDetailView — no network wait before navigating.
    func openNotificationPost(id: String, preferComments: Bool = false) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        showAppMenu = false
        globePanel = nil
        reelsViewerContext = nil
        isPlayPresented = false
        _ = preferComments

        let destination = AppDestination.post(trimmed)
        selectedTab = .feed
        // Tab roots stay mounted across switches — NavigationStack is always live.
        navigationPath = [destination]
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