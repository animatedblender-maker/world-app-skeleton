import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var isAuthenticated = false
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

    private let reelSavedDefaultsKey = "saved_reel_presentation_ids"
    private let localSavedPostIDsKey = "local_saved_post_ids"
    private let viewedStoriesDefaultsKey = "viewed_story_post_ids"
    var navigationPath: [AppDestination] = []
    var pendingConversationID: String?
    var pendingLivingVideoID: String?
    var showAppMenu = false
    var floatingPosts: [CountryPost] = []
    var errorMessage: String?

    private let auth = AuthService.shared
    private let profileService = ProfileService.shared
    private let notificationsService = NotificationsService.shared
    private let presenceService = PresenceService.shared
    private let followService = FollowService.shared
    private var pollTask: Task<Void, Never>?

    func bootstrap() async {
        VoIPPushService.shared.bootstrap()
        reelPresentationSavedIDs = loadReelPresentationSavedIDs()
        isAuthenticated = auth.isAuthenticated
        guard isAuthenticated else { return }
        CallSessionManager.shared.bootstrap()
        await PushNotificationService.shared.requestAuthorizationAndRegister()
        await PushNotificationService.shared.syncWithServer(force: true)
        await refreshAll()
        startPolling()
    }

    func refreshAll() async {
        await refreshProfile()
        await refreshGlobalStats()
        await refreshFollowingIDs()
        await refreshSavedPosts()
        await refreshStories()
        await refreshNotifications()
        await refreshUnreadCounts()
        startPresence()
    }

    func refreshProfile() async {
        do {
            currentProfile = try await profileService.meProfile()
            needsProfileSetup = !(currentProfile?.isComplete ?? false)
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
        do {
            savedPosts = try await PostsService.shared.savedPosts(limit: 100)
            savedPostIDs = Set(savedPosts.map(\.id))
            persistLocalSavedPostIDs()
        } catch {
            await loadLocalSavedPosts()
        }
    }

    func isPostSaved(_ postID: String) -> Bool {
        savedPostIDs.contains(postID)
    }

    func toggleSavePost(_ post: CountryPost, reelPresentation: Bool = false) async {
        let wasSaved = savedPostIDs.contains(post.id)
        do {
            if wasSaved {
                _ = try await PostsService.shared.unsavePost(post.id)
            } else {
                _ = try await PostsService.shared.savePost(post.id)
            }
            applySavedState(for: post, saved: !wasSaved, reelPresentation: reelPresentation)
            persistLocalSavedPostIDs()
        } catch {
            applySavedState(for: post, saved: !wasSaved, reelPresentation: reelPresentation)
            persistLocalSavedPostIDs()
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

    private func loadLocalSavedPosts() async {
        let ids = Set(UserDefaults.standard.stringArray(forKey: localSavedPostIDsKey) ?? [])
        guard !ids.isEmpty else { return }

        savedPostIDs = ids
        var loaded: [CountryPost] = []
        for id in ids {
            if let cached = savedPosts.first(where: { $0.id == id }) {
                loaded.append(cached)
                continue
            }
            if let post = try? await PostsService.shared.getPostByID(id) {
                loaded.append(post)
            }
        }
        savedPosts = loaded
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
        CallSessionManager.shared.bootstrap()
        await PushNotificationService.shared.requestAuthorizationAndRegister()
        await PushNotificationService.shared.syncWithServer(force: true)
        await refreshAll()
        startPolling()
    }

    func logout() {
        stopPolling()
        CallSessionManager.shared.teardown()
        VoIPPushService.shared.teardown()
        CallSignalingService.shared.shutdown()
        Task { await presenceService.setOffline() }
        presenceService.stopHeartbeat()
        auth.logout()
        isAuthenticated = false
        needsProfileSetup = false
        currentProfile = nil
        selectedCountry = nil
        selectedTab = .feed
        globePanel = nil
        navigationPath = []
        pendingLivingVideoID = nil
        followingIDs = []
        savedPostIDs = []
        savedPosts = []
        notifications = []
        showAppMenu = false
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

    func navigateToHomeCountryFeed(openComposer: Bool = false) async {
        selectedTab = .feed
        navigationPath.removeAll()
        if openComposer {
            await presentCreateSheet(.post)
        }
    }

    func navigate(to destination: AppDestination) {
        navigationPath.append(destination)
    }

    func openLivingVideo(postID: String) {
        selectedTab = .globe
        navigationPath.removeAll()
        showAppMenu = false
        pendingLivingVideoID = postID
    }

    func clearPendingLivingVideo() {
        pendingLivingVideoID = nil
    }

    func openFromMenu(_ destination: AppDestination) {
        showAppMenu = false
        switch destination {
        case .people, .ads, .editProfile, .settings, .search:
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

    func openSavedFromMenu() {
        showAppMenu = false
        profileLibrarySection = .savedPosts
        selectedTab = .profile
        navigationPath.removeAll()
    }

    func openNotificationsFromMenu() {
        showAppMenu = false
        globePanel = .notifications
        Task { await refreshNotifications() }
    }

    func presentCreateSheet(_ sheet: CreateContentSheet) async {
        guard let home = await resolveHomeCountry() else {
            errorMessage = "Set your home country in profile before posting."
            return
        }
        composerCountry = home
        showCreateMenu = false
        activeCreateSheet = sheet
    }

    func refreshStories() async {
        storyGroups = await PostsService.shared.loadActiveStoryGroups(
            countryCode: currentProfile?.countryCode?.uppercased(),
            followingIDs: followingIDs,
            viewedStoryIDs: viewedStoryIDs,
            currentUserID: currentProfile?.userID
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
            errorMessage = error.localizedDescription
        }
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

        if type == "message", let conversationID = notification.conversationID {
            try? await notificationsService.markRead(notification.id)
            pendingConversationID = conversationID
            selectedTab = .messages
            navigationPath.removeAll()
            await refreshUnreadCounts()
            return
        }

        if type == "follow" {
            try? await notificationsService.markRead(notification.id)
            if let username = notification.actor?.username?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !username.isEmpty {
                selectedTab = .feed
                navigationPath.removeAll()
                navigate(to: .publicProfile(username: username))
            }
            await refreshNotifications()
            return
        }

        if let postID = notification.resolvedPostID {
            try? await notificationsService.markRead(notification.id)
            selectedTab = .feed
            navigationPath.removeAll()
            navigate(to: .post(postID))
            await refreshNotifications()
            return
        }

        try? await notificationsService.markRead(notification.id)
        await refreshNotifications()
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
}