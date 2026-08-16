import Foundation
import Observation
import SwiftUI
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
    /// Bumped when feed should reshuffle strips (app open / 3+ min away).
    var feedFreshSessionToken: Int = 0
    /// Bumped when Hubs For you should reshuffle (app open / open Hubs tab).
    var hubsFreshSessionToken: Int = 0
    /// When user left the feed tab (nil = currently on feed or never left).
    private var feedLeftAt: Date?
    /// Away from feed longer than this → reload a new mix on return.
    private let feedStaleAwayInterval: TimeInterval = 3 * 60
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
    /// Optimistic follower-count deltas (authorID → ±n) so Hubs channel counts update instantly on Follow.
    /// Cleared for an author when a fresh server/local count is loaded for them.
    var followFollowerDeltas: [String: Int] = [:]
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
    /// 0…1 while user is pulling the continuous player down to mini.
    /// Watch page chrome (title, comments, related) hides instantly when > 0.
    var hubPlaybackPullProgress: CGFloat = 0
    /// Bumped to request landscape fullscreen on the continuous Hubs player
    /// (meta drag-below-video, external chrome). GlobalHubPlaybackLayer observes.
    var hubPlaybackFullscreenToken: Int = 0
    /// 0…1 YouTube-style collapse while scrolling meta/comments under the video.
    /// 0 = full stage; 1 = sticky compact height at the top.
    var hubWatchScrollCollapse: CGFloat = 0
    /// Active hubs clip aspect as **width / height** (default 16:9).
    /// Stage height = width / aspect so the picture is never cropped (aspectFit).
    var hubPlaybackVideoAspect: CGFloat = 16.0 / 9.0
    /// Shared mute for **all** in-feed videos (hub cards, spark cards, autoplay).
    /// Muting one video mutes every feed video; unmuting one unmutes all.
    var feedVideosMuted = false
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

        // NEVER request mic/camera/location/push before login — that freezes the auth screen.
        reelPresentationSavedIDs = loadReelPresentationSavedIDs()
        isAuthenticated = auth.isAuthenticated
        guard isAuthenticated else {
            isSessionReady = true
            return
        }

        restoreCachedProfile()
        markSessionReady()
        // Permissions + VoIP only after we know who the user is.
        Task(priority: .utility) {
            await AppPermissionsService.shared.requestEssentialPermissionsOnLaunch()
        }
        VoIPPushService.shared.bootstrap()
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
        // Returning from background after 3+ min off feed → new mix.
        if selectedTab != .feed, let left = feedLeftAt,
           Date().timeIntervalSince(left) >= feedStaleAwayInterval {
            // Still away; keep timer. When they return to feed, noteSelectedTabChanged reloads.
        } else if selectedTab == .feed, let left = feedLeftAt,
                  Date().timeIntervalSince(left) >= feedStaleAwayInterval {
            requestFreshFeedSession(reason: "foreground_after_away")
            feedLeftAt = nil
        }
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

        // Every app open: FeedView reloads a new mix via contentLoadGeneration;
        // Hubs For you reshuffles via hubsFreshSessionToken.
        hubsFreshSessionToken += 1

        // Feed can paint now — secondary work is non-blocking.
        contentLoadGeneration += 1

        Task(priority: .utility) {
            await prepareSession()
            await refreshProfile()
            await refreshAllInBackground()
        }
    }

    /// Call from MainTabView when the selected tab changes.
    /// Leave feed / return after 3+ minutes → new feed session.
    func noteSelectedTabChanged(from old: AppTab, to new: AppTab) {
        if old == .feed, new != .feed {
            feedLeftAt = Date()
            return
        }
        if new == .feed, old != .feed {
            if let left = feedLeftAt, Date().timeIntervalSince(left) >= feedStaleAwayInterval {
                #if DEBUG
                print("[Feed] away \(Int(Date().timeIntervalSince(left)))s ≥ 3m → fresh session")
                #endif
                requestFreshFeedSession(reason: "away_3m")
            }
            feedLeftAt = nil
        }
        if new == .hubs, old != .hubs {
            // Fresh For you shuffle every time user opens Hubs.
            hubsFreshSessionToken += 1
        }
    }

    /// Reshuffle feed posts + strips (3+ min off feed). App open uses contentLoadGeneration.
    func requestFreshFeedSession(reason: String) {
        feedLeftAt = nil
        feedFreshSessionToken += 1
        // Force Sparks rail / player to re-pull + re-rank — not the same 8 IDs.
        SparkDiscoveryEngine.resetSession()
        PostsService.shared.invalidateSparksDiscoveryCatalog()
        #if DEBUG
        print("[Feed] requestFreshFeedSession reason=\(reason) token=\(feedFreshSessionToken)")
        #endif
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
        // Social chrome only — feed owns its own first-paint via HomeFeedStore.
        // Never loadHomeFeed / loadLivingVideos / loadPlayCatalog here (that froze sign-in).
        async let followingTask: Void = { await refreshFollowingIDs() }()
        async let notificationsTask: Void = { await refreshNotifications() }()
        _ = await (followingTask, notificationsTask)
        startPresence()
        // Everything else deferred + low priority so sign-in stays snappy.
        Task(priority: .background) {
            async let stats: Void = { await refreshGlobalStats() }()
            async let saved: Void = { await refreshSavedPosts() }()
            async let stories: Void = { await refreshStories() }()
            _ = await (stats, saved, stories)
        }
        // Warm a *light* Hubs catalog after open — never pull the full Archive corpus on launch
        // (that competed with feed first paint and made open feel heavy).
        Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard currentProfile != nil else { return }
            if PostsService.shared.hubsSessionIsWarm(minLongForm: 12) { return }
            if ContentCache.shared.isFresh(.livingVideos),
               let cached = ContentCache.shared.posts(for: .livingVideos),
               cached.filter({ !$0.isReel }).count >= 8 {
                PostsService.shared.rememberHubsSessionCatalog(cached)
                return
            }
            _ = await PostsService.shared.loadPlayCatalog(
                globalLimit: 24,
                forceRefresh: false,
                viewerCountry: currentProfile?.countryCode,
                followingIDs: followingIDs,
                fast: true
            )
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
        // Always restore ID sets first — never let a thin server list erase local Sparks.
        let diskIDs = Set(UserDefaults.standard.stringArray(forKey: localSavedPostIDsKey) ?? [])
        savedPostIDs.formUnion(diskIDs)
        let diskReelIDs = loadReelPresentationSavedIDs()
        reelPresentationSavedIDs.formUnion(diskReelIDs)

        let previousLocal = savedPosts
        let cachedLocal = ContentCache.shared.posts(for: .savedPosts) ?? []
        if savedPosts.isEmpty, !cachedLocal.isEmpty {
            savedPosts = cachedLocal
            savedPostIDs.formUnion(cachedLocal.map(\.id))
        }

        let knownIDs = savedPostIDs
        let loaded = await PostsService.shared.loadBookmarkedPosts(localIDs: knownIDs, limit: 100)

        // Preserve every previously known save — server lists omit seed/catalog Sparks.
        let keepRows = previousLocal + cachedLocal + savedPosts
        var merged = Self.mergeSavedLists(
            serverOrResolved: loaded,
            localKeep: keepRows,
            savedIDs: knownIDs.union(Set(loaded.map(\.id))).union(Set(keepRows.map(\.id)))
        )

        // Rows we still "own" by ID but failed to re-hydrate — keep last known copy.
        let mergedIDs = Set(merged.map(\.id))
        for post in keepRows where knownIDs.contains(post.id) && !mergedIDs.contains(post.id) {
            merged.append(post.withSavedByMe(true))
        }

        var fixed: [CountryPost] = []
        for post in merged {
            let asSpark = reelPresentationSavedIDs.contains(post.id) || Self.belongsInSavedSparks(post)
            if asSpark {
                fixed.append(post.withSavedByMe(true))
                reelPresentationSavedIDs.insert(post.id)
            } else {
                fixed.append(await Self.preparePostForSave(post, asSpark: false).withSavedByMe(true))
            }
        }
        savedPosts = fixed.sorted { $0.createdAt > $1.createdAt }

        // Re-tag Spark-shaped rows so they never land in Saved Videos.
        for post in savedPosts where Self.belongsInSavedSparks(post) {
            reelPresentationSavedIDs.insert(post.id)
        }

        // Never shrink the ID set on refresh — only unsave removes IDs.
        savedPostIDs.formUnion(Set(savedPosts.map(\.id)))
        savedPostIDs.formUnion(knownIDs)
        if !savedPosts.isEmpty {
            ContentCache.shared.setPosts(savedPosts, for: .savedPosts)
        }
        persistLocalSavedPostIDs()
        persistReelPresentationSavedIDs()
    }

    func isPostSaved(_ postID: String) -> Bool {
        savedPostIDs.contains(postID)
    }

    /// Sparks (original, feed share, or opened from Sparks player) — never Saved Videos.
    static func belongsInSavedSparks(_ post: CountryPost) -> Bool {
        if post.isStory { return false }
        if post.isReel || post.isSpark { return true }
        if post.isSparkFeedShare { return true }
        if PlayPlatformBridge.isSparkFeedCard(post) { return true }
        // Do NOT use ReelsRankingEngine here — it gates Archive off and was hiding valid saves.
        if post.isHubSeedVideo, post.hasVideo {
            let type = (post.mediaType ?? "").lowercased()
            if type == "reel" || type == "spark" { return true }
            // Short catalog clips often store as video but are Sparks in the player.
            if type == "video" || type.isEmpty {
                let media = (post.mediaURL ?? "").lowercased()
                if media.contains("spark") || media.contains("/reel") { return true }
            }
        }
        // R2 short-form pack paths even if media_type was stored as plain "video".
        if post.isR2HostedMedia, post.hasVideo, !PlayPlatformBridge.isHubCatalogContent(post) {
            let media = (post.mediaURL ?? "").lowercased()
            if media.contains("spark") || media.contains("/reels") || media.contains("\"reel\"") {
                return true
            }
        }
        if post.isArchiveSparkSource { return true }
        return false
    }

    @discardableResult
    func toggleSavePost(_ post: CountryPost, reelPresentation: Bool = false) async -> String? {
        let wasSaved = savedPostIDs.contains(post.id)
        let targetSaved = !wasSaved
        // Sparks player Keep always goes to Saved Sparks (never Saved Videos).
        let asSpark = reelPresentation || Self.belongsInSavedSparks(post)
        // Store channel identity for Hubs videos — never the re-sharer's face/name.
        // Stamp reel media_type when Keep is from Sparks player so profile filters keep it.
        var prepared = await Self.preparePostForSave(post, asSpark: asSpark)
            .withSavedByMe(targetSaved)
        if asSpark, prepared.mediaType?.lowercased() != "reel", prepared.mediaType?.lowercased() != "spark" {
            prepared = prepared.withMediaTypeForSave("reel")
        }
        // Optimistic UI — always keep the rich local post (server rows often strip spark markers).
        applySavedState(for: prepared, saved: targetSaved, asSpark: asSpark)
        persistLocalSavedPostIDs()
        persistReelPresentationSavedIDs()
        if !savedPosts.isEmpty {
            ContentCache.shared.setPosts(savedPosts, for: .savedPosts)
        } else if !targetSaved {
            ContentCache.shared.invalidate(.savedPosts)
        }
        do {
            let updated = try await PostsService.shared.toggleBookmark(for: post, saved: targetSaved)
            // Always prefer rich local Spark (media + reel typing) over server shell.
            let stored = Self.preferredSavedPost(local: prepared, server: updated, asSpark: asSpark)
            let fixed = await Self.preparePostForSave(stored, asSpark: asSpark)
                .withSavedByMe(targetSaved)
            applySavedState(for: fixed, saved: targetSaved, asSpark: asSpark)
            persistLocalSavedPostIDs()
            if !savedPosts.isEmpty {
                ContentCache.shared.setPosts(savedPosts, for: .savedPosts)
            }
            return nil
        } catch {
            // Sparks (player or catalog) always succeed on-device — never roll back Keep.
            if asSpark || PostsService.mustBookmarkLocally(post) {
                applySavedState(for: prepared, saved: targetSaved, asSpark: asSpark)
                persistLocalSavedPostIDs()
                if !savedPosts.isEmpty {
                    ContentCache.shared.setPosts(savedPosts, for: .savedPosts)
                }
                return nil
            }
            applySavedState(for: post, saved: wasSaved, asSpark: asSpark)
            persistLocalSavedPostIDs()
            return error.localizedDescription
        }
    }

    /// For long-form Hubs saves: rewrite author to the **channel**, keep bookmark id.
    private static func preparePostForSave(_ post: CountryPost, asSpark: Bool) async -> CountryPost {
        if asSpark { return post }
        let needsChannel = PlayPlatformBridge.isHubOriginShare(post)
            || PlayPlatformBridge.isHubCatalogContent(post)
            || PlayPlatformBridge.isArchiveCatalogMedia(post)
            || HubOriginShareMarker.isMarked(post.body)
            || PlayPlatformBridge.isFeedOnlyShare(post)
        guard needsChannel else { return post }
        let channel = await PlayPlatformBridge.resolveHubWatchPresentation(for: post)
        // If resolve only returned the same share row with the sharer as author, still apply origin stamp.
        if let origin = HubOriginShareMarker.originPresentation(from: post) {
            return PlayPlatformBridge.withChannelIdentity(post, from: origin)
        }
        if channel.authorID != post.authorID || channel.authorID.hasPrefix("hub_") {
            return PlayPlatformBridge.withChannelIdentity(post, from: channel)
        }
        if PlayPlatformBridge.isArchiveCatalogMedia(post) {
            let archive = CountryPost(
                id: post.id,
                title: post.title,
                body: post.body,
                mediaType: post.mediaType,
                mediaURL: post.mediaURL,
                thumbURL: post.thumbURL,
                mediaCaption: post.mediaCaption,
                sharedPostID: post.sharedPostID,
                sharedPost: post.sharedPost,
                visibility: post.visibility,
                likeCount: post.likeCount,
                commentCount: post.commentCount,
                viewCount: post.viewCount,
                likedByMe: post.likedByMe,
                savedByMe: post.savedByMe,
                createdAt: post.createdAt,
                updatedAt: post.updatedAt,
                authorID: HubVideoSeedService.archiveChannelAuthorID,
                countryName: post.countryName,
                countryCode: post.countryCode,
                cityName: post.cityName,
                author: PostAuthor(
                    userID: HubVideoSeedService.archiveChannelAuthorID,
                    displayName: HubVideoSeedService.archiveChannelDisplayName,
                    username: HubVideoSeedService.archiveChannelUsername,
                    avatarURL: nil,
                    countryName: nil,
                    countryCode: nil,
                    lastReadAt: nil
                ),
                linkURL: post.linkURL,
                linkTitle: post.linkTitle,
                externalRefType: post.externalRefType,
                externalRefID: post.externalRefID
            )
            return archive
        }
        return post
    }

    private func applySavedState(for post: CountryPost, saved: Bool, asSpark: Bool) {
        if saved {
            savedPostIDs.insert(post.id)
            savedPosts.removeAll { $0.id == post.id }
            savedPosts.insert(post, at: 0)
            if asSpark || Self.belongsInSavedSparks(post) {
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

    /// Prefer the on-device Spark metadata when the server bookmark row is thin / mis-typed.
    private static func preferredSavedPost(local: CountryPost, server: CountryPost, asSpark: Bool) -> CountryPost {
        let serverHasPlayable = server.playableVideoURL != nil
            || !(server.mediaURL ?? "").isEmpty
        let localHasPlayable = local.playableVideoURL != nil
            || !(local.mediaURL ?? "").isEmpty

        // Server row missing media — keep the rich local Spark.
        if !serverHasPlayable, localHasPlayable {
            return local
        }
        // Local is a Spark, server lost reel/spark typing → keep local (Saved Sparks bucket).
        if (asSpark || belongsInSavedSparks(local)), !belongsInSavedSparks(server) {
            return local
        }
        return server
    }

    /// Server list + local-only bookmarks (seed Sparks, offline keeps).
    private static func mergeSavedLists(
        serverOrResolved: [CountryPost],
        localKeep: [CountryPost],
        savedIDs: Set<String>
    ) -> [CountryPost] {
        var byID: [String: CountryPost] = [:]
        for post in serverOrResolved {
            byID[post.id] = post.withSavedByMe(true)
        }
        for post in localKeep where savedIDs.contains(post.id) {
            if let existing = byID[post.id] {
                byID[post.id] = preferredSavedPost(local: post, server: existing, asSpark: belongsInSavedSparks(post))
                    .withSavedByMe(true)
            } else {
                byID[post.id] = post.withSavedByMe(true)
            }
        }
        return byID.values.sorted { $0.createdAt > $1.createdAt }
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

    /// Long-form / feed videos only — **never** Sparks.
    var savedVideoPosts: [CountryPost] {
        savedPosts.filter { post in
            guard post.hasVideo else { return false }
            if reelPresentationSavedIDs.contains(post.id) { return false }
            if Self.belongsInSavedSparks(post) { return false }
            return true
        }
    }

    /// Saved Sparks only (player + feed spark cards).
    var savedReelPosts: [CountryPost] {
        savedPosts.filter { post in
            // Explicit Keep from Sparks player always belongs here.
            if reelPresentationSavedIDs.contains(post.id) {
                return post.playableVideoURL != nil
                    || !(post.mediaURL ?? "").isEmpty
                    || post.hasVideo
            }
            guard post.hasVideo || post.playableVideoURL != nil else { return false }
            return Self.belongsInSavedSparks(post)
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
        // Per-user watch history / resume points (never share across accounts).
        YouTubeCatalogService.shared.bindToUser(auth.currentUser?.id)
        restoreCachedProfile()
        markSessionReady()
        // Defer call stack + permissions so login button returns immediately.
        Task(priority: .utility) {
            await AppPermissionsService.shared.requestEssentialPermissionsOnLaunch()
            VoIPPushService.shared.bootstrap()
            CallSessionManager.shared.bootstrap()
            await registerPushInBackgroundAsync()
        }
        startPolling()
        Task { await finishSessionWarmup() }
        // Signing in reactivates a soft-deactivated account.
        Task { await reactivateIfNeeded() }
    }

    private func registerPushInBackgroundAsync() async {
        await VoIPPushService.shared.ensureToken()
        await PushNotificationService.shared.syncWithServer(force: true)
        await PushNotificationService.shared.registerForRemoteNotificationsIfAuthorized()
        await VoIPPushService.shared.ensureToken()
        await PushNotificationService.shared.syncWithServer(force: true)
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
        YouTubeCatalogService.shared.clearSessionState()
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
        followFollowerDeltas = [:]
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

    func showToast(
        _ message: String,
        style: ToastBanner.ToastStyle = .success,
        durationSeconds: Double = 2.8
    ) {
        // Never surface GraphQL Yoga masked failures for engagement / missing seed rows.
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("unexpected error")
            || trimmed.caseInsensitiveCompare("Unexpected error") == .orderedSame {
            return
        }
        toastMessage = message
        toastStyle = style
        let nanos = UInt64(max(1.0, durationSeconds) * 1_000_000_000)
        Task {
            try? await Task.sleep(nanoseconds: nanos)
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
        // Country feeds are disabled — everything lives on the main feed.
        if case .countryFeed = destination {
            selectedTab = .feed
            navigationPath.removeAll()
            selectedCountry = nil
            return
        }
        navigationPath.append(destination)
    }

    /// Open a chat **instantly**. Optional `seed` avoids any network wait / "Opening chat…".
    /// Hubs mini player keeps running (only collapses expanded → mini).
    func openConversation(id: String, seed: Conversation? = nil) {
        pendingConversationID = nil
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Seed cache so ConversationRouteView paints on the same frame (no spinner).
        if let seed {
            MessagesService.shared.storeConversation(seed)
        }

        // Keep Hubs audio going as mini while chatting (dock under composer).
        // Never stop/pause — only collapse expanded watch if needed.
        if hubPlaybackPost != nil {
            hubPlaybackPlaying = true
            if hubPlaybackExpanded {
                withAnimation(MatteryaMotion.snappy) {
                    hubPlaybackExpanded = false
                }
            }
            hubPlaybackReturnConversationID = trimmed
        }

        // Already on this chat — don't rebuild the stack (feels like "closing everything").
        if case .conversation(let openID) = navigationPath.last, openID == trimmed {
            selectedTab = .messages
            return
        }

        selectedTab = .messages
        // Drop other conversation pushes only — keep settings/profile under the stack when possible.
        navigationPath.removeAll { destination in
            if case .conversation = destination { return true }
            return false
        }
        navigationPath.append(.conversation(trimmed))

        // Warm messages in the background if not already cached (ConversationView also loads).
        Task {
            if MessagesService.shared.cachedMessages(for: trimmed) == nil {
                _ = try? await MessagesService.shared.listMessages(conversationID: trimmed, limit: 40)
            }
            await clearNotifications(forConversation: trimmed)
        }
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
            openConversation(id: conversation.id, seed: conversation)
        } catch {
            showToast(error.localizedDescription, style: .error)
        }
    }

    func openPublicProfile(username: String?, userID: String) {
        // Close Sparks / Moments / expanded Hubs so the profile is visible now —
        // not stuck behind a full-screen player or comments sheet.
        if reelsViewerContext != nil {
            MediaPlaybackCoordinator.shared.stopAllPlayback()
            reelsViewerContext = nil
        }
        if storyViewerContext != nil {
            storyViewerContext = nil
        }
        if hubPlaybackExpanded {
            minimizeHubPlayback(returnToChat: false)
        }
        globePanel = nil
        showAppMenu = false
        sharePostSheet = nil
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

    /// Start / switch the single global hubs player.
    /// - Parameter expanded: full Hubs watch (player + comments). Elsewhere use mini.
    func startHubPlayback(_ post: CountryPost, expanded: Bool = true) {
        // Instant: paint + play with the post we already have (no await before first frame).
        let quick = PlayPlatformBridge.hubWatchPresentation(for: post)
        // Kick AV buffer **before** any pauseAll / route swap so claim can hit a warm slot.
        if let url = quick.playableVideoURL {
            if ArchiveVideoPlayback.isArchiveURL(url) {
                ArchiveVideoPlayback.warmResolve(url)
            }
            SparkWarmPool.shared.warmSingle(postID: quick.id, url: url)
        }
        applyHubPlayback(quick, expanded: expanded)
        // Background: upgrade to full catalog identity if needed (sharer → channel).
        Task { @MainActor in
            let resolved = await PlayPlatformBridge.resolveHubWatchPresentation(for: post)
            guard hubPlaybackPost?.id == quick.id || hubPlaybackPost?.id == post.id else { return }
            if resolved.authorID != hubPlaybackPost?.authorID
                || resolved.playableVideoURL != nil && hubPlaybackPost?.playableVideoURL == nil {
                if let url = resolved.playableVideoURL {
                    SparkWarmPool.shared.warmSingle(postID: resolved.id, url: url)
                }
                applyHubPlayback(resolved, expanded: hubPlaybackExpanded)
            }
        }
    }

    @MainActor
    private func applyHubPlayback(_ watchPost: CountryPost, expanded: Bool) {
        showAppMenu = false
        globePanel = nil
        reelsViewerContext = nil
        isPlayPresented = false
        clearPendingLivingVideo()

        // Intent first — GlobalHubPlaybackLayer mounts with isActive true (no silent first frame).
        hubPlaybackPlaying = true
        hubPlaybackMuted = false

        if expanded {
            rememberHubPlaybackChatReturnIfNeeded()
            navigationPath.removeAll()
            selectedTab = .hubs
            hubPlaybackExpanded = true
        } else {
            hubPlaybackExpanded = false
        }

        let switchingVideo = hubPlaybackPost?.id != watchPost.id
        // Keep warm-pool player for *this* post alive — pauseAll must not kill its buffer.
        let keepWarm = SparkWarmPool.shared.parkedPlayer(for: watchPost.id)
        if switchingVideo {
            // Soft-pause others only — never stopAll/tear-down (that delayed first frame).
            MediaPlaybackCoordinator.shared.pauseAll(except: keepWarm)
            hubPlaybackPost = watchPost
            hubWatchScrollCollapse = 0
            hubPlaybackVideoAspect = 16.0 / 9.0
        } else if hubPlaybackPost?.playableVideoURL == nil, watchPost.playableVideoURL != nil {
            hubPlaybackPost = watchPost
        } else if hubPlaybackPost?.authorID != watchPost.authorID {
            // Upgrade sharer identity → catalog channel without remounting player.
            hubPlaybackPost = watchPost
        } else if hubPlaybackPost == nil {
            hubPlaybackPost = watchPost
            hubWatchScrollCollapse = 0
            hubPlaybackVideoAspect = 16.0 / 9.0
        }

        // Continuous Hubs player (mini or full) owns audio — kill feed/profile autoplay.
        FeedVideoFocus.shared.resetAll()
        YouTubeCatalogService.shared.recordWatch(watchPost.id)
        // Prefetch first comment page so Hubs watch paints threads instantly.
        CommentsWarmCache.shared.warm(watchPost.id)
        if let origin = PostsService.commentThreadOriginID(for: watchPost.id, post: watchPost) {
            CommentsWarmCache.shared.warm(origin)
        }
        if let url = watchPost.playableVideoURL {
            if ArchiveVideoPlayback.isArchiveURL(url) {
                ArchiveVideoPlayback.warmResolve(url)
            }
            // Pre-warm AV buffer immediately (same runloop as open).
            SparkWarmPool.shared.warmSingle(postID: watchPost.id, url: url)
        }
        ImageCache.shared.prefetchPostThumbnails([watchPost], maxPixelSize: 720)
        // Prefetch next related long-form so related taps / auto-next feel instant.
        Task(priority: .utility) {
            let related = YouTubeCatalogService.shared.relatedVideos(
                to: watchPost,
                from: PostsService.shared.hubsSessionCatalog,
                limit: 8
            )
            ImageCache.shared.prefetchPostThumbnails(
                Array(related.prefix(6)),
                maxPixelSize: 480,
                aggressive: false
            )
            // Warm more related players — next tap should claim, not cold-start.
            for post in related.prefix(5) {
                if let u = post.playableVideoURL {
                    SparkWarmPool.shared.warmSingle(postID: post.id, url: u)
                }
            }
        }
        // Kick continuous surface if it was paused.
        NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
    }

    /// Collapse to mini — **playback keeps running** (same continuous AVPlayer, only layout changes).
    /// Geometry morph is owned by `GlobalHubPlaybackLayer` (`collapse` 0→1). This only flips session flags.
    /// - Parameter animated: when false, layer already finished the morph — no second animation.
    func minimizeHubPlayback(returnToChat: Bool = true, animated: Bool = true) {
        guard hubPlaybackPost != nil else { return }
        // Never stop/pause mini — GlobalHubPlaybackLayer only resizes the stage.
        hubPlaybackPlaying = true
        hubWatchScrollCollapse = 0
        // Hold pull at 1 so watch chrome stays fully faded through the handoff.
        if hubPlaybackExpanded {
            hubPlaybackPullProgress = 1
        }
        if animated {
            withAnimation(MatteryaMotion.minimize) {
                hubPlaybackExpanded = false
            }
        } else {
            // Layer already at mini frame — flip with zero animation to avoid a second jump.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                hubPlaybackExpanded = false
            }
        }

        // Defer side-effects so they never hitch the release / morph frame.
        let shouldReturn = returnToChat
        let conversationID = hubPlaybackReturnConversationID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            FeedVideoFocus.shared.resetAll()
            syncHubPlaybackChatReturnWithPath()
            if shouldReturn, let conversationID {
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard hubPlaybackPost != nil, !hubPlaybackExpanded else { return }
                selectedTab = .messages
                navigationPath = [.conversation(conversationID)]
            }
        }
    }

    /// Leaving Hubs always collapses to the mini player (keep watching elsewhere).
    /// Tab switches do not force a chat return — only explicit minimize does.
    func ensureHubPlaybackMinimizedIfNeeded() {
        guard hubPlaybackPost != nil, selectedTab != .hubs else { return }
        minimizeHubPlayback(returnToChat: false)
    }

    /// Tap miniplayer (from chat dock or floating bar) → full Hubs watch with comments.
    /// Same continuous player — expand only grows the stage; audio/video never restart.
    /// YouTube-style: spring expand (handled in GlobalHubPlaybackLayer via collapse 1→0).
    func expandHubPlayback() {
        guard hubPlaybackPost != nil else { return }
        rememberHubPlaybackChatReturnIfNeeded()
        // Always leave chat / other pushes so Hubs watch (player + comments) is the real screen.
        navigationPath.removeAll()
        selectedTab = .hubs
        hubPlaybackPlaying = true
        hubWatchScrollCollapse = 0
        // Clear pull so watch chrome is fully visible during expand.
        hubPlaybackPullProgress = 0
        withAnimation(MatteryaMotion.expand) {
            hubPlaybackExpanded = true
        }
        NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
    }

    /// YouTube: drag down on the meta strip under the video → landscape fullscreen.
    func requestHubFullscreen() {
        guard hubPlaybackPost != nil, hubPlaybackExpanded else { return }
        hubPlaybackFullscreenToken &+= 1
    }

    func stopHubPlayback() {
        hubPlaybackPost = nil
        hubPlaybackExpanded = false
        hubPlaybackPlaying = false
        hubPlaybackPullProgress = 0
        hubWatchScrollCollapse = 0
        hubPlaybackVideoAspect = 16.0 / 9.0
        hubPlaybackFullscreenToken = 0
        hubPlaybackReturnConversationID = nil
        MediaPlaybackCoordinator.shared.stopAllPlayback()
        // Mini closed — feed/profile may elect autoplay again.
        FeedVideoFocus.shared.resetAll()
    }

    /// Update stage aspect from the player’s natural size (width/height).
    func noteHubPlaybackVideoSize(_ size: CGSize) {
        guard size.width > 2, size.height > 2 else { return }
        let next = size.width / size.height
        guard next.isFinite, next > 0.3, next < 3.5 else { return }
        // Ignore tiny AR noise so layout doesn’t thrash.
        if abs(next - hubPlaybackVideoAspect) > 0.02 {
            hubPlaybackVideoAspect = next
        }
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

        // Instant path: share/list already has media — start playing this frame.
        if let post, (post.id == postID || postID.isEmpty),
           post.hasVideo || post.playableVideoURL != nil {
            startHubPlayback(post, expanded: true)
            return
        }
        // Also accept id mismatch when post carries the real playable URL (chat share stamps).
        if let post, post.playableVideoURL != nil || post.hasVideo {
            startHubPlayback(post, expanded: true)
            return
        }

        pendingLivingVideoID = postID
        pendingLivingVideo = (post?.id == postID) ? post : nil
        selectedTab = .hubs
        hubPlaybackExpanded = true
        hubPlaybackPlaying = true
        // Silence others only — never stopAll (that delayed first Hubs frame after chat).
        MediaPlaybackCoordinator.shared.pauseAll()
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
            // Resolve catalog channel async (Archive hub clips must not show the sharer).
            Task { @MainActor in
                let presentation = await PlayPlatformBridge.resolveHubWatchPresentation(for: post)
                openLivingVideo(postID: presentation.id, tab: .home, post: presentation)
            }
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
        // Feed / hubs audio must die before Sparks scroll takes over.
        // Do not drain warm pool here — callers may pre-warm the first few clips.
        MediaPlaybackCoordinator.shared.pauseAll()
        hubPlaybackPlaying = false
        reelsViewerContext = ReelsViewerContext(
            startingPost: startingPost,
            seedPosts: seedPosts
        )
    }

    /// Open endless Sparks from a feed card / share / chat / Hubs / strip.
    /// **One unified player** — same queue builder for every entry path.
    func openGlobalSparksViewer(startingPost: CountryPost) {
        // Always open the playable original (feed/chat shares resolve here).
        let start = ReelsRankingEngine.resolvePlayerStart(startingPost)
        guard start.playableVideoURL != nil else {
            Task { @MainActor in
                var resolved = start
                if let sid = SparkShareMarker.originID(from: startingPost.body)
                    ?? startingPost.sharedPostID,
                   let remote = try? await PostsService.shared.getPostByID(sid),
                   remote.playableVideoURL != nil {
                    resolved = remote
                } else if let remote = try? await PostsService.shared.getPostByID(start.id),
                          remote.playableVideoURL != nil {
                    resolved = remote
                } else if let sid = SparkShareMarker.originID(from: startingPost.body),
                          let hub = await HubVideoSeedService.shared.post(id: sid),
                          hub.playableVideoURL != nil {
                    resolved = hub
                } else if let matched = await HubVideoSeedService.shared.postMatchingMediaURL(
                    startingPost.mediaURL ?? startingPost.playableVideoURL?.absoluteString
                ), matched.playableVideoURL != nil {
                    resolved = matched
                }
                guard resolved.playableVideoURL != nil else {
                    showToast("\(MatteryaCopy.noSparksYet) — publish one to get started.", style: .info)
                    return
                }
                presentGlobalSparks(starting: resolved)
            }
            return
        }

        presentGlobalSparks(starting: start)
    }

    /// Shared open path for feed + chat: multi-seed queue + warm pool + deep expand later.
    private func presentGlobalSparks(starting start: CountryPost) {
        // Large instant bulk so the player never waits on network for the first ~dozen swipes.
        let seeds = Self.instantSparksSeedQueue(starting: start, limit: 72)
        openReelsViewer(startingPost: start, seedPosts: seeds)
        if let url = start.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) {
            ArchiveVideoPlayback.warmResolve(url)
        }
        // Warm a bulk window immediately — short await so open never stalls/flickers.
        SparkWarmPool.shared.preparePlayerWindow(posts: seeds, around: 0)
        Task { @MainActor in
            await SparkWarmPool.shared.awaitReady(
                postIDs: Array(seeds.prefix(3).map(\.id)),
                timeout: 0.35
            )
        }
        // Always kick catalog fuel in the background so expandFeed has bulk ready.
        Task { @MainActor in
            _ = await PostsService.shared.loadSparksDiscoveryCatalog(
                forceRefresh: seeds.count < 24,
                deep: seeds.count < 40
            )
        }
    }

    /// Instant swipe seed — **eligible originals only**, **unviewed discovery order**
    /// (not a sticky shuffle of the same catalog head).
    private static func instantSparksSeedQueue(starting start: CountryPost, limit: Int = 72) -> [CountryPost] {
        let head = ReelsRankingEngine.resolvePlayerStart(start)
        var out: [CountryPost] = [head]
        var seen: Set<String> = [head.id]

        func absorb(_ posts: [CountryPost]) {
            // rankForDiscovery = unviewed first (never re-queue watched ahead of fresh).
            let ranked = SparkDiscoveryEngine.rankForDiscovery(posts)
            for post in ranked {
                guard seen.insert(post.id).inserted else { continue }
                guard ReelsRankingEngine.isSparkEligible(post) else { continue }
                out.append(post)
                if out.count >= limit { return }
            }
        }

        absorb(PostsService.shared.sparksCatalogSnapshot())
        if out.count < limit {
            absorb(PostsService.shared.hubsSessionCatalog)
        }
        return out
    }

    func openReelsFromMenu() async {
        // Full library shuffle every menu open — never a sticky strip.
        let reels = await PostsService.shared.beginFreshSparksSession(preferStart: nil)
        guard let first = reels.first else {
            showToast("\(MatteryaCopy.noSparksYet) — publish one to get started.", style: .info)
            openPlay()
            return
        }
        let head = Array(reels.prefix(max(24, SparkWarmPool.playerAhead + 4)))
        SparkWarmPool.shared.preparePlayerWindow(posts: head, around: 0)
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

        // True Sparks only. Hub long-form / normal videos stay long-form on the feed.
        let isHubCatalogShare = PlayPlatformBridge.isHubCatalogContent(post) || post.isHubSeedVideo
        let isSparkShare = (post.isReel || PlayPlatformBridge.isReelVideo(post))
            && !(isHubCatalogShare && !post.isReel)
        // Sharing from full Sparks or expanded Hubs watch: keep watching in place.
        let stayInSparks = reelsViewerContext != nil
        let stayInHubsWatch = hubPlaybackPost != nil && hubPlaybackExpanded
        let stayInPlace = stayInSparks || stayInHubsWatch

        // Long-form video shares: shadow card on feed. Skip navigation when staying in place.
        var placeholderID: String?
        if post.hasVideo, !stayInPlace {
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
            // Share is feed-only — purge Hubs cache so For you never paints the re-share.
            ContentCache.shared.invalidate(.homeFeed, .livingVideos)
            ContentCache.shared.invalidateAllFeeds()
            contentLoadGeneration += 1
            NotificationCenter.default.post(
                name: .userPostsDidChange,
                object: nil,
                userInfo: ["post": created]
            )
            // Only insert onto the home feed. Never into Hubs catalog / For you.
            HomeFeedStore.shared.insertNewPost(created)

            if stayInPlace {
                // Silent share — toast only; Sparks / Hubs keep playing expanded.
                sharePostSheet = nil
                if stayInHubsWatch {
                    hubPlaybackPlaying = true
                    NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
                }
            } else if let placeholderID {
                finishFeedVideoUpload(placeholderID: placeholderID, post: created)
            } else {
                goToFeedTop(scroll: true)
            }

            if isSparkShare {
                return "Spark shared to the main feed."
            }
            if let sourceCountry = post.countryName, sourceCountry != countryName {
                return "Shared from \(sourceCountry) to the main feed."
            }
            return "Shared to the main feed."
        } catch {
            if let placeholderID {
                failFeedVideoUpload(placeholderID: placeholderID, message: error.localizedDescription)
            }
            #if DEBUG
            print("[Share] sharePostToCountryFeed failed: \(error)")
            #endif
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
            PlayPlatformBridge.isHubChannelUpload(post)
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

    /// Display follower count = last fetched base + any local follow/unfollow deltas.
    func resolvedFollowerCount(for userID: String, base: Int?) -> Int {
        let id = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let delta = followFollowerDeltas[id] ?? 0
        return max(0, (base ?? 0) + delta)
    }

    /// Call after loading fresh follower counts so deltas do not double-count.
    func clearFollowerCountDeltas(for userIDs: some Sequence<String>) {
        for raw in userIDs {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            followFollowerDeltas.removeValue(forKey: id)
        }
    }

    func toggleFollow(_ userID: String) async {
        let id = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != currentProfile?.userID else { return }

        // Optimistic UI first so hub/fake Follow feels instant.
        let wasFollowing = followingIDs.contains(id)
        if wasFollowing {
            followingIDs.remove(id)
            followFollowerDeltas[id, default: 0] -= 1
        } else {
            followingIDs.insert(id)
            followFollowerDeltas[id, default: 0] += 1
        }

        do {
            if wasFollowing {
                try await followService.unfollow(targetID: id)
            } else {
                try await followService.follow(targetID: id)
            }
            // Soft reconcile following set in the background — do NOT await a full
            // followingIDs() round-trip on the critical path, and never bump
            // contentLoadGeneration (that reloads Feed/Hubs/Profile under Sparks
            // and freezes the player when Follow is tapped).
            Task { @MainActor [weak self] in
                guard let self else { return }
                let server = await self.followService.followingIDs()
                // Keep optimistic bit if the network list is momentarily stale.
                var next = server
                if wasFollowing {
                    next.remove(id)
                } else {
                    next.insert(id)
                }
                self.followingIDs = next
            }
            if FollowService.usesLocalFollow(userID: id) {
                showToast(wasFollowing ? "Unfollowed" : "Following", style: .info)
            }
        } catch {
            // Roll back optimistic update.
            if wasFollowing {
                followingIDs.insert(id)
                followFollowerDeltas[id, default: 0] += 1
            } else {
                followingIDs.remove(id)
                followFollowerDeltas[id, default: 0] -= 1
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