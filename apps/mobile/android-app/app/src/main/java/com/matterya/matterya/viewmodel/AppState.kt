package com.matterya.matterya.viewmodel

import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import com.matterya.matterya.data.analytics.EngagementTracker
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.cache.ContentCache
import com.matterya.matterya.data.cache.ContentCacheKey
import com.matterya.matterya.data.calls.TelecomCallManager
import com.matterya.matterya.data.hubs.YouTubeCatalogService
import com.matterya.matterya.data.hubs.YouTubeMainTab
import com.matterya.matterya.data.media.FeedVideoFocus
import com.matterya.matterya.data.media.MediaPlaybackCoordinator
import com.matterya.matterya.data.media.NowPlayingService
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.data.messages.MessagesService
import com.matterya.matterya.data.notifications.NotificationsService
import com.matterya.matterya.data.posts.HomeFeedStore
import com.matterya.matterya.data.posts.PostsService
import com.matterya.matterya.data.posts.ProfileService
import com.matterya.matterya.data.presence.PresenceService
import com.matterya.matterya.data.push.PushNotificationService
import com.matterya.matterya.data.push.VoIPPushService
import com.matterya.matterya.data.reels.ReelsRankingEngine
import com.matterya.matterya.data.reels.SparkDiscoveryEngine
import com.matterya.matterya.data.share.ShareService
import com.matterya.matterya.data.social.BlockService
import com.matterya.matterya.data.social.FollowService
import com.matterya.matterya.model.AppDestination
import com.matterya.matterya.model.AppTab
import com.matterya.matterya.model.Conversation
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.CountryStats
import com.matterya.matterya.model.CountryTab
import com.matterya.matterya.model.CreateContentSheet
import com.matterya.matterya.model.GlobalStats
import com.matterya.matterya.model.GlobePanel
import com.matterya.matterya.model.LetterFlightEvent
import com.matterya.matterya.model.LivingChannelMarker
import com.matterya.matterya.model.NotificationItem
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.ProfileLibrarySection
import com.matterya.matterya.model.ReelsViewerContext
import com.matterya.matterya.model.StoryGroup
import com.matterya.matterya.model.StoryViewerContext
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.ui.components.ToastStyle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import kotlin.math.max

/**
 * Single source of truth app state — port of iOS `AppState.swift`.
 * UI should observe [snapshot] and call methods here (or via [AppViewModel] facade).
 */
data class AppStateSnapshot(
    val bootstrapping: Boolean = true,
    val isAuthenticated: Boolean = false,
    val isSessionReady: Boolean = false,
    val contentLoadGeneration: Int = 0,
    val needsProfileSetup: Boolean = false,
    val currentProfile: Profile? = null,
    val selectedTab: AppTab = AppTab.Feed,
    val feedFreshSessionToken: Int = 0,
    val hubsFreshSessionToken: Int = 0,
    val selectedCountry: Country? = null,
    val countryTab: CountryTab = CountryTab.POSTS,
    val globePanel: GlobePanel? = null,
    val globalStats: GlobalStats? = null,
    val countryStats: CountryStats? = null,
    val messagesUnreadCount: Int = 0,
    val notificationsUnreadCount: Int = 0,
    val notifications: List<NotificationItem> = emptyList(),
    val followingIds: Set<String> = emptySet(),
    val followFollowerDeltas: Map<String, Int> = emptyMap(),
    val savedPostIds: Set<String> = emptySet(),
    val savedPosts: List<CountryPost> = emptyList(),
    val reelPresentationSavedIds: Set<String> = emptySet(),
    val profileLibrarySection: ProfileLibrarySection = ProfileLibrarySection.POSTS,
    val searchPrefersCountries: Boolean = false,
    val openComposerOnCountryFeed: Boolean = false,
    val showCreateMenu: Boolean = false,
    val activeCreateSheet: CreateContentSheet? = null,
    val composerCountry: Country? = null,
    val storyGroups: List<StoryGroup> = emptyList(),
    val storyViewerContext: StoryViewerContext? = null,
    val reelsViewerContext: ReelsViewerContext? = null,
    val navigationPath: List<AppDestination> = emptyList(),
    val pendingConversationId: String? = null,
    val isPlayPresented: Boolean = false,
    val pendingLivingVideoId: String? = null,
    val pendingLivingVideo: CountryPost? = null,
    val pendingPlayTab: YouTubeMainTab? = null,
    val pendingPlayChannelAuthorId: String? = null,
    val pendingPlayChannelUsername: String? = null,
    val hubPlaybackPost: CountryPost? = null,
    val hubPlaybackExpanded: Boolean = false,
    val hubPlaybackPlaying: Boolean = true,
    val hubPlaybackMuted: Boolean = false,
    val hubPlaybackPullProgress: Float = 0f,
    val hubWatchScrollCollapse: Float = 0f,
    val hubPlaybackVideoAspect: Float = 16f / 9f,
    val hubPlaybackReturnConversationId: String? = null,
    val feedVideosMuted: Boolean = false,
    val showAppMenu: Boolean = false,
    val floatingPosts: List<CountryPost> = emptyList(),
    val errorMessage: String? = null,
    val toastMessage: String? = null,
    val toastStyle: ToastStyle = ToastStyle.Info,
    val sharePostSheet: CountryPost? = null,
    val quotedSharePostId: String? = null,
    val pendingSearchQuery: String? = null,
    val feedScrollToTopToken: Int = 0,
    val letterComposePresented: Boolean = false,
    val letterFlightEvent: LetterFlightEvent? = null,
    // Auth form chrome (Android shell)
    val authBusy: Boolean = false,
    val authError: String? = null,
) {
    val effectiveNotificationsUnreadCount: Int
        get() {
            val socialUnread = notifications.count { !it.isMessageType && it.isUnread }
            return if (notifications.isNotEmpty()) socialUnread else notificationsUnreadCount
        }

    val hubPlaybackDockInChat: Boolean
        get() {
            if (hubPlaybackPost == null || hubPlaybackExpanded) return false
            return navigationPath.asReversed().any { it is AppDestination.Conversation }
        }

    val savedJournalPosts: List<CountryPost>
        get() = savedPosts.filter { !it.hasVideo }

    val savedVideoPosts: List<CountryPost>
        get() = savedPosts.filter { post ->
            if (!post.hasVideo) return@filter false
            if (post.id in reelPresentationSavedIds) return@filter false
            if (AppState.belongsInSavedSparks(post)) return@filter false
            true
        }

    val savedReelPosts: List<CountryPost>
        get() = savedPosts.filter { post ->
            if (post.id in reelPresentationSavedIds) {
                return@filter post.playableVideoUrl != null ||
                    !post.mediaUrl.isNullOrEmpty() ||
                    post.hasVideo
            }
            if (!post.hasVideo && post.playableVideoUrl == null) return@filter false
            AppState.belongsInSavedSparks(post)
        }

    val homeCountryIso: String?
        get() = currentProfile?.countryCode?.trim()?.uppercase()?.takeIf { it.isNotEmpty() }
}

class AppState(private val app: Application) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val auth get() = AuthService.instance
    private val profileService = ProfileService()
    private val postsService = PostsService()
    private val notificationsService = NotificationsService.shared
    private val presenceService = PresenceService.shared
    private val followService by lazy { FollowService(prefsContext = app) }
    private val messagesService = MessagesService.shared
    private val contentCache get() = ContentCache.get(app)
    private val blockService get() = BlockService.get(app)
    private val homeFeed get() = HomeFeedStore.get(app)
    private val youtubeCatalog get() = YouTubeCatalogService.get(app)
    private val shareService = ShareService.shared
    private val engagement = EngagementTracker.shared

    /**
     * Platform service surfaces — keep strong refs so CallKit→Telecom and
     * AppleMusic→NowPlaying are never a "missing service" gap from AppState.
     * iOS warms CallKitManager in AppDelegate; Android warms here + MatteryaApp.
     * Construction is defensive: never crash AppState if a platform service fails.
     */
    val telecomCallManager: TelecomCallManager by lazy {
        runCatching { TelecomCallManager.init(app) }.getOrElse { TelecomCallManager.shared }
    }
    val nowPlayingService: NowPlayingService by lazy {
        NowPlayingService.init(app)
    }
    val pushNotificationService: PushNotificationService by lazy {
        PushNotificationService.init(app)
    }
    val voipPushService: VoIPPushService by lazy {
        VoIPPushService.init(app)
    }

    /** Settings / diagnostics: Telecom (CallKit) readiness line. */
    val telecomStatusSummary: String
        get() = if (telecomCallManager.isAudioSessionActivated) {
            "Telecom audio session active"
        } else {
            "Telecom ready (in-app + high-priority FCM ring path)"
        }

    /** Settings / diagnostics: MediaSession now-playing surface (Apple Music parity). */
    val nowPlayingStatusSummary: String
        get() {
            val snap = nowPlayingService.localSnapshot
            return if (snap != null) {
                "Now playing: ${snap.title} — ${snap.subtitle}"
            } else {
                "MediaSession ready — share Now Playing from Connected"
            }
        }

    private val prefs = app.getSharedPreferences("matterya_app_state", Context.MODE_PRIVATE)
    private val reelSavedDefaultsKey = "saved_reel_presentation_ids"
    private val localSavedPostIdsKey = "local_saved_post_ids"
    private val viewedStoriesDefaultsKey = "viewed_story_post_ids"

    private val feedStaleAwayIntervalMs = 3 * 60 * 1000L
    private var feedLeftAt: Long? = null
    private var pollJob: Job? = null
    private var pendingHubCreateSheet: CreateContentSheet? = null
    private var pendingPushRoute: PendingPushRoute? = null

    private data class PendingPushRoute(
        val type: String,
        val conversationId: String?,
        val postId: String?,
        val username: String?,
    )

    private val _snapshot = MutableStateFlow(AppStateSnapshot())
    val snapshot: StateFlow<AppStateSnapshot> = _snapshot.asStateFlow()

    val homeFeedState get() = homeFeed.state

    // ── Bootstrap / session ───────────────────────────────────────────

    fun bootstrap() {
        scope.launch {
            _snapshot.update { it.copy(bootstrapping = true) }
            try {
                // Load session with a hard timeout so unauthenticated users never hang on splash.
                withTimeoutOrNull(4_000) {
                    runCatching { auth.load() }
                }
                SparkDiscoveryEngine.bind(app)
                val reelIds = loadReelPresentationSavedIds()
                val authed = auth.isAuthenticated
                if (!authed) {
                    _snapshot.update {
                        it.copy(
                            bootstrapping = false,
                            isAuthenticated = false,
                            isSessionReady = true,
                            needsProfileSetup = false,
                            reelPresentationSavedIds = reelIds,
                        )
                    }
                    return@launch
                }
                _snapshot.update {
                    it.copy(isAuthenticated = true, reelPresentationSavedIds = reelIds)
                }
                restoreCachedProfile()
                // Unlock shell immediately; warm network in background.
                markSessionReady()
                _snapshot.update { it.copy(bootstrapping = false) }
                startPolling()
                flushPendingPushRoute()
                finishSessionWarmup()
            } catch (_: Exception) {
                // Fail open to Auth so the app is never stuck on splash.
                _snapshot.update {
                    it.copy(
                        bootstrapping = false,
                        isAuthenticated = auth.isAuthenticated,
                        isSessionReady = true,
                        needsProfileSetup = false,
                    )
                }
            }
        }
    }

    fun handleBecameActive() {
        scope.launch {
            val s = _snapshot.value
            if (!s.isAuthenticated) return@launch
            if (!s.isSessionReady) {
                restoreCachedProfile()
                markSessionReady()
                finishSessionWarmup()
                return@launch
            }
            prepareSession()
            val left = feedLeftAt
            if (s.selectedTab == AppTab.Feed && left != null &&
                System.currentTimeMillis() - left >= feedStaleAwayIntervalMs
            ) {
                requestFreshFeedSession("foreground_after_away")
                feedLeftAt = null
            }
        }
    }

    private fun restoreCachedProfile() {
        if (_snapshot.value.currentProfile != null) return
        val cached = contentCache.cachedProfile() ?: return
        _snapshot.update {
            it.copy(currentProfile = cached, needsProfileSetup = !cached.isComplete)
        }
    }

    private fun markSessionReady() {
        _snapshot.update { if (it.isSessionReady) it else it.copy(isSessionReady = true) }
    }

    private suspend fun finishSessionWarmup() {
        _snapshot.update {
            it.copy(
                hubsFreshSessionToken = it.hubsFreshSessionToken + 1,
                contentLoadGeneration = it.contentLoadGeneration + 1,
            )
        }
        homeFeed.bootstrap()
        scope.launch {
            prepareSession()
            refreshProfile()
            refreshAllInBackground()
        }
    }

    fun noteSelectedTabChanged(from: AppTab, to: AppTab) {
        if (from == AppTab.Feed && to != AppTab.Feed) {
            feedLeftAt = System.currentTimeMillis()
            return
        }
        if (to == AppTab.Feed && from != AppTab.Feed) {
            val left = feedLeftAt
            if (left != null && System.currentTimeMillis() - left >= feedStaleAwayIntervalMs) {
                requestFreshFeedSession("away_3m")
            }
            feedLeftAt = null
        }
        if (to == AppTab.Hubs && from != AppTab.Hubs) {
            _snapshot.update { it.copy(hubsFreshSessionToken = it.hubsFreshSessionToken + 1) }
        }
        ensureHubPlaybackMinimizedIfNeeded()
    }

    fun requestFreshFeedSession(reason: String) {
        feedLeftAt = null
        _snapshot.update { it.copy(feedFreshSessionToken = it.feedFreshSessionToken + 1) }
        SparkDiscoveryEngine.resetSession()
        postsService.invalidateSparksDiscoveryCatalog()
        homeFeed.beginFreshSession()
    }

    private suspend fun prepareSession() {
        withTimeoutOrNull(10_000) {
            runCatching { auth.ensureValidToken() }
        }
    }

    fun refreshAll() {
        scope.launch {
            refreshProfile()
            refreshAllInBackground()
        }
    }

    private suspend fun refreshAllInBackground() {
        coroutineScope {
            val following = async { refreshFollowingIds() }
            val notifs = async { refreshNotifications() }
            following.await()
            notifs.await()
        }
        startPresence()
        scope.launch {
            refreshGlobalStats()
            refreshSavedPosts()
            refreshStories()
        }
        scope.launch {
            delay(1_200)
            val profile = _snapshot.value.currentProfile ?: return@launch
            if (postsService.hubsSessionIsWarm()) return@launch
            if (contentCache.isFresh(ContentCacheKey.LivingVideos)) {
                contentCache.posts(ContentCacheKey.LivingVideos)?.let {
                    postsService.rememberHubsSessionCatalog(it)
                }
                return@launch
            }
            postsService.loadPlayCatalog(forceRefresh = false)
        }
    }

    suspend fun refreshProfile() {
        val previousCountry = contentCache.profileCountryCode()
        try {
            val profile = profileService.meProfile()
            contentCache.setProfile(profile)
            _snapshot.update {
                it.copy(
                    currentProfile = profile,
                    needsProfileSetup = !(profile?.isComplete ?: false),
                )
            }
            val newCountry = profile?.countryCode?.uppercase()
            if (newCountry != previousCountry && newCountry != null) {
                contentCache.invalidate(ContentCacheKey.HomeFeed, ContentCacheKey.LivingVideos)
                _snapshot.update { it.copy(contentLoadGeneration = it.contentLoadGeneration + 1) }
            }
        } catch (e: Exception) {
            val message = e.message?.lowercase().orEmpty()
            if (message.contains("authentication required") || message.contains("unauthenticated")) {
                logout()
                return
            }
            _snapshot.update {
                it.copy(
                    needsProfileSetup = it.currentProfile?.isComplete != true,
                )
            }
        }
    }

    suspend fun refreshGlobalStats() {
        _snapshot.update { it.copy(globalStats = runCatching { profileService.globalStats() }.getOrNull()) }
    }

    suspend fun refreshCountryStats(forCountry: Country) {
        _snapshot.update {
            it.copy(countryStats = runCatching { profileService.countryStats(forCountry.iso) }.getOrNull())
        }
    }

    suspend fun refreshFollowingIds() {
        _snapshot.update { it.copy(followingIds = followService.followingIds()) }
    }

    // ── Saved / bookmarks ─────────────────────────────────────────────

    suspend fun refreshSavedPosts() {
        val diskIds = prefs.getStringSet(localSavedPostIdsKey, emptySet())?.toSet().orEmpty()
        var savedIds = _snapshot.value.savedPostIds + diskIds
        val diskReelIds = loadReelPresentationSavedIds()
        var reelIds = _snapshot.value.reelPresentationSavedIds + diskReelIds

        var savedPosts = _snapshot.value.savedPosts
        val cachedLocal = contentCache.posts(ContentCacheKey.SavedPosts).orEmpty()
        if (savedPosts.isEmpty() && cachedLocal.isNotEmpty()) {
            savedPosts = cachedLocal
            savedIds = savedIds + cachedLocal.map { it.id }
        }
        val previousLocal = savedPosts
        val loaded = postsService.loadBookmarkedPosts(localIds = savedIds, limit = 100)
        val keepRows = previousLocal + cachedLocal + savedPosts
        var merged = mergeSavedLists(
            serverOrResolved = loaded,
            localKeep = keepRows,
            savedIds = savedIds + loaded.map { it.id } + keepRows.map { it.id },
        )
        val mergedIds = merged.map { it.id }.toSet()
        for (post in keepRows) {
            if (post.id in savedIds && post.id !in mergedIds) {
                merged = merged + post.withSavedByMe(true)
            }
        }
        val fixed = merged.map { post ->
            val asSpark = post.id in reelIds || belongsInSavedSparks(post)
            if (asSpark) {
                reelIds = reelIds + post.id
                post.withSavedByMe(true)
            } else {
                preparePostForSave(post, asSpark = false).withSavedByMe(true)
            }
        }.sortedByDescending { it.createdAt }

        for (post in fixed) {
            if (belongsInSavedSparks(post)) reelIds = reelIds + post.id
        }
        savedIds = savedIds + fixed.map { it.id }
        _snapshot.update {
            it.copy(
                savedPosts = fixed,
                savedPostIds = savedIds,
                reelPresentationSavedIds = reelIds,
            )
        }
        if (fixed.isNotEmpty()) contentCache.setPosts(fixed, ContentCacheKey.SavedPosts)
        persistLocalSavedPostIds()
        persistReelPresentationSavedIds()
    }

    fun isPostSaved(postId: String): Boolean = postId in _snapshot.value.savedPostIds

    suspend fun toggleSavePost(post: CountryPost, reelPresentation: Boolean = false): String? {
        val wasSaved = post.id in _snapshot.value.savedPostIds
        val targetSaved = !wasSaved
        val asSpark = reelPresentation || belongsInSavedSparks(post)
        var prepared = preparePostForSave(post, asSpark).withSavedByMe(targetSaved)
        if (asSpark && prepared.mediaType?.lowercase() != "reel" && prepared.mediaType?.lowercase() != "spark") {
            prepared = prepared.withMediaTypeForSave("reel")
        }
        applySavedState(prepared, targetSaved, asSpark)
        persistLocalSavedPostIds()
        persistReelPresentationSavedIds()
        val current = _snapshot.value.savedPosts
        if (current.isNotEmpty()) contentCache.setPosts(current, ContentCacheKey.SavedPosts)
        else if (!targetSaved) contentCache.invalidate(ContentCacheKey.SavedPosts)
        return try {
            val updated = postsService.toggleBookmark(post, targetSaved)
            val stored = preferredSavedPost(prepared, updated, asSpark)
            val fixed = preparePostForSave(stored, asSpark).withSavedByMe(targetSaved)
            applySavedState(fixed, targetSaved, asSpark)
            persistLocalSavedPostIds()
            if (_snapshot.value.savedPosts.isNotEmpty()) {
                contentCache.setPosts(_snapshot.value.savedPosts, ContentCacheKey.SavedPosts)
            }
            null
        } catch (e: Exception) {
            if (asSpark || postsService.mustBookmarkLocally(post)) {
                applySavedState(prepared, targetSaved, asSpark)
                persistLocalSavedPostIds()
                if (_snapshot.value.savedPosts.isNotEmpty()) {
                    contentCache.setPosts(_snapshot.value.savedPosts, ContentCacheKey.SavedPosts)
                }
                null
            } else {
                applySavedState(post, wasSaved, asSpark)
                persistLocalSavedPostIds()
                e.message
            }
        }
    }

    private fun applySavedState(post: CountryPost, saved: Boolean, asSpark: Boolean) {
        _snapshot.update { s ->
            if (saved) {
                val reels = if (asSpark || belongsInSavedSparks(post)) {
                    s.reelPresentationSavedIds + post.id
                } else s.reelPresentationSavedIds
                s.copy(
                    savedPostIds = s.savedPostIds + post.id,
                    savedPosts = listOf(post) + s.savedPosts.filter { it.id != post.id },
                    reelPresentationSavedIds = reels,
                )
            } else {
                s.copy(
                    savedPostIds = s.savedPostIds - post.id,
                    savedPosts = s.savedPosts.filter { it.id != post.id },
                    reelPresentationSavedIds = s.reelPresentationSavedIds - post.id,
                )
            }
        }
        if (asSpark) persistReelPresentationSavedIds()
    }

    private suspend fun preparePostForSave(post: CountryPost, asSpark: Boolean): CountryPost {
        if (asSpark) return post
        val needsChannel = PlayPlatformBridge.isHubOriginShare(post) ||
            PlayPlatformBridge.isHubCatalogContent(post) ||
            PlayPlatformBridge.isArchiveCatalogMedia(post) ||
            PlayPlatformBridge.isFeedOnlyShare(post)
        if (!needsChannel) return post
        val channel = PlayPlatformBridge.resolveHubWatchPresentation(post, postsService)
        val origin = com.matterya.matterya.model.HubOriginShareMarker.originPresentation(post)
        if (origin != null) return PlayPlatformBridge.withChannelIdentity(post, origin)
        if (channel.authorId != post.authorId || channel.authorId.startsWith("hub_")) {
            return PlayPlatformBridge.withChannelIdentity(post, channel)
        }
        return post
    }

    // ── Auth ──────────────────────────────────────────────────────────

    fun login(email: String, password: String) {
        scope.launch {
            _snapshot.update { it.copy(authBusy = true, authError = null) }
            try {
                auth.login(email, password)
            } catch (e: Exception) {
                android.util.Log.e("AppState", "login failed", e)
                _snapshot.update {
                    it.copy(
                        authError = e.message?.takeIf { m -> m.isNotBlank() } ?: "Login failed",
                        authBusy = false,
                        isAuthenticated = false,
                    )
                }
                return@launch
            }
            // Session is valid — never roll back to "login failed" if warmup errors.
            try {
                onAuthenticated()
            } catch (e: Exception) {
                android.util.Log.e("AppState", "post-login warmup failed", e)
                _snapshot.update {
                    it.copy(
                        isAuthenticated = true,
                        isSessionReady = true,
                        needsProfileSetup = false,
                        authBusy = false,
                        authError = null,
                    )
                }
                return@launch
            }
            _snapshot.update { it.copy(authBusy = false, authError = null) }
        }
    }

    fun register(email: String, password: String) {
        scope.launch {
            _snapshot.update { it.copy(authBusy = true, authError = null) }
            try {
                val result = auth.register(email, password)
                when {
                    result.isExistingEmail -> _snapshot.update {
                        it.copy(
                            authBusy = false,
                            authError = "This email is already registered. Sign in instead.",
                        )
                    }
                    result.needsEmailConfirm -> _snapshot.update {
                        it.copy(
                            authBusy = false,
                            authError = "Check your email to confirm, then sign in.",
                        )
                    }
                    auth.isAuthenticated -> {
                        onAuthenticated()
                        _snapshot.update { it.copy(authBusy = false) }
                    }
                    else -> _snapshot.update {
                        it.copy(authBusy = false, authError = "Check your email to confirm, then sign in.")
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("AppState", "register failed", e)
                _snapshot.update {
                    it.copy(
                        authError = e.message?.takeIf { m -> m.isNotBlank() } ?: "Sign up failed",
                        authBusy = false,
                    )
                }
            }
        }
    }

    /**
     * iOS `ProfileSetupView.saveProfile()` — full identity + detected location + bio.
     * Country is always from device location detection (not free-typed).
     */
    fun completeProfile(
        displayName: String,
        username: String? = null,
        countryName: String,
        countryCode: String? = null,
        cityName: String? = null,
        bio: String? = null,
        avatarUrl: String? = null,
    ) {
        scope.launch {
            _snapshot.update { it.copy(authBusy = true, authError = null) }
            try {
                val name = displayName.trim()
                val country = countryName.trim()
                require(name.isNotEmpty()) { "Display name is required." }
                require(country.isNotEmpty() && country != "Unknown") {
                    "Location is required. Tap Detect location and allow access."
                }
                val p = profileService.updateProfile(
                    displayName = name,
                    username = username?.trim()?.takeIf { it.isNotEmpty() },
                    countryName = country,
                    countryCode = countryCode?.trim()?.takeIf { it.isNotEmpty() },
                    cityName = cityName?.trim()?.takeIf { it.isNotEmpty() },
                    bio = bio?.trim()?.takeIf { it.isNotEmpty() },
                    avatarUrl = avatarUrl?.takeIf { it.isNotBlank() },
                )
                contentCache.setProfile(p)
                _snapshot.update {
                    it.copy(
                        currentProfile = p,
                        needsProfileSetup = !p.isComplete,
                        authBusy = false,
                        authError = null,
                    )
                }
                if (p.isComplete) {
                    homeFeed.bootstrap()
                    scope.launch { refreshProfile() }
                }
            } catch (e: Exception) {
                android.util.Log.e("AppState", "completeProfile failed", e)
                _snapshot.update {
                    it.copy(
                        authError = e.message ?: "Could not save profile",
                        authBusy = false,
                    )
                }
            }
        }
    }

    /**
     * Full Edit Profile save — iOS `EditProfileView.save()`.
     * Preserves living-channel bio marker and updates identity + location + bio.
     */
    suspend fun saveEditProfile(
        displayName: String,
        username: String?,
        countryName: String?,
        countryCode: String?,
        cityName: String?,
        bio: String,
        avatarUrl: String? = null,
    ): Profile {
        val name = displayName.trim()
        require(name.isNotEmpty()) { "Display name is required." }
        val existingChannel = runCatching {
            LivingChannelMarker.parse(_snapshot.value.currentProfile?.bio)
        }.getOrNull()
        val composedBio = runCatching {
            LivingChannelMarker.buildBio(
                displayBio = bio,
                channelName = existingChannel,
            )
        }.getOrDefault(bio.trim())
        val profile = profileService.updateProfile(
            displayName = name,
            username = username?.trim()?.takeIf { it.isNotEmpty() },
            countryName = countryName?.trim()?.takeIf { it.isNotEmpty() },
            countryCode = countryCode?.trim()?.takeIf { it.isNotEmpty() },
            cityName = cityName?.trim()?.takeIf { it.isNotEmpty() },
            bio = composedBio,
            avatarUrl = avatarUrl?.takeIf { it.isNotBlank() },
        )
        contentCache.setProfile(profile)
        _snapshot.update {
            it.copy(
                currentProfile = profile,
                needsProfileSetup = !profile.isComplete,
            )
        }
        showToast("Profile saved.", ToastStyle.Success)
        return profile
    }

    /** Apply an already-uploaded avatar URL to the current profile. */
    suspend fun applyAvatarUrl(avatarUrl: String): Profile {
        val profile = profileService.updateProfile(avatarUrl = avatarUrl)
        contentCache.setProfile(profile)
        _snapshot.update {
            it.copy(
                currentProfile = profile,
                needsProfileSetup = !profile.isComplete,
            )
        }
        showToast("Profile photo updated.", ToastStyle.Success)
        return profile
    }

    /** Detect device location and optionally persist country/city onto the profile. */
    suspend fun detectAndApplyLocation(): com.matterya.matterya.model.DetectedLocation {
        val locationService = runCatching {
            com.matterya.matterya.data.location.LocationService.shared
        }.getOrElse {
            com.matterya.matterya.data.location.LocationService.get(app)
        }
        val coord = locationService.currentCoordinate()
            ?: error("Location unavailable. Enable Location for Matterya in Settings, then try again.")
        val detected = profileService.detectLocation(coord.first, coord.second)
        // Persist so country feed + composer home resolve immediately (iOS path).
        runCatching {
            val profile = profileService.updateProfile(
                countryName = detected.countryName.takeIf { it.isNotBlank() },
                countryCode = detected.countryCode.takeIf { it.isNotBlank() },
                cityName = detected.cityName?.takeIf { it.isNotBlank() },
            )
            contentCache.setProfile(profile)
            _snapshot.update {
                it.copy(
                    currentProfile = profile,
                    needsProfileSetup = !profile.isComplete,
                )
            }
        }
        return detected
    }

    suspend fun onAuthenticated() {
        _snapshot.update { it.copy(isAuthenticated = true) }
        youtubeCatalog.bindToUser(auth.currentUser?.id)
        restoreCachedProfile()
        markSessionReady()
        startPolling()
        finishSessionWarmup()
        scope.launch { reactivateIfNeeded() }
    }

    suspend fun reactivateIfNeeded() {
        try {
            val profile = profileService.meProfile()
            if (profile?.isDeleted == true) {
                showToast("This account was permanently deleted.", ToastStyle.Error)
                logout()
                return
            }
            if (profile?.isDeactivated == true) {
                val result = profileService.reactivateAccount()
                if (result.ok) {
                    showToast(result.message ?: "Welcome back — account reactivated.", ToastStyle.Success)
                    refreshProfile()
                }
            }
        } catch (_: Exception) {
        }
    }

    suspend fun deactivateAccount() {
        val result = profileService.deactivateAccount()
        if (!result.ok) error(result.message ?: "Could not deactivate account.")
        showToast(result.message ?: "Account deactivated.", ToastStyle.Info)
        logout()
    }

    suspend fun deleteAccount(confirmation: String) {
        val result = profileService.deleteAccount(confirmation)
        if (!result.ok) error(result.message ?: "Could not delete account.")
        showToast(result.message ?: "Account deleted.", ToastStyle.Info)
        logout()
    }

    fun logout() {
        stopPolling()
        presenceService.stopHeartbeat()
        youtubeCatalog.clearSessionState()
        MediaPlaybackCoordinator.shared.stopAllPlayback()
        FeedVideoFocus.shared.resetAll()
        scope.launch {
            runCatching { presenceService.setOffline() }
            runCatching { auth.logout() }
        }
        _snapshot.value = AppStateSnapshot(
            bootstrapping = false,
            isAuthenticated = false,
            isSessionReady = true,
        )
    }

    // ── Tabs / navigation ─────────────────────────────────────────────

    fun selectTab(tab: AppTab) {
        val old = _snapshot.value.selectedTab
        _snapshot.update { it.copy(selectedTab = tab) }
        noteSelectedTabChanged(old, tab)
        engagement.screenOpened(tab.rawValue)
    }

    fun navigate(to: AppDestination) {
        if (to is AppDestination.CountryFeed) {
            _snapshot.update {
                it.copy(selectedTab = AppTab.Feed, navigationPath = emptyList(), selectedCountry = null)
            }
            return
        }
        _snapshot.update { it.copy(navigationPath = it.navigationPath + to) }
    }

    fun openConversation(id: String, seed: Conversation? = null) {
        val trimmed = id.trim()
        if (trimmed.isEmpty()) return
        if (seed != null) messagesService.storeConversation(seed)
        _snapshot.update { s ->
            var next = s.copy(pendingConversationId = null)
            if (next.hubPlaybackPost != null) {
                next = next.copy(
                    hubPlaybackPlaying = true,
                    hubPlaybackExpanded = false,
                    hubPlaybackReturnConversationId = trimmed,
                )
            }
            val last = next.navigationPath.lastOrNull()
            if (last is AppDestination.Conversation && last.conversationId == trimmed) {
                return@update next.copy(selectedTab = AppTab.Messages)
            }
            val path = next.navigationPath.filter { it !is AppDestination.Conversation } +
                AppDestination.Conversation(trimmed)
            next.copy(selectedTab = AppTab.Messages, navigationPath = path)
        }
        scope.launch {
            if (messagesService.cachedMessages(trimmed) == null) {
                runCatching { messagesService.listMessages(trimmed, 40) }
            }
            clearNotifications(forConversation = trimmed)
        }
    }

    fun closeConversation(id: String) {
        _snapshot.update {
            it.copy(navigationPath = it.navigationPath.filterNot {
                dest -> dest is AppDestination.Conversation && dest.conversationId == id
            })
        }
    }

    fun openDirectMessage(userId: String) {
        scope.launch {
            _snapshot.update { it.copy(globePanel = null, showAppMenu = false) }
            try {
                val conversation = messagesService.startConversation(userId)
                openConversation(conversation.id, seed = conversation)
            } catch (e: Exception) {
                showToast(e.message ?: "Could not open chat", ToastStyle.Error)
            }
        }
    }

    fun openPublicProfile(username: String?, userId: String) {
        if (_snapshot.value.reelsViewerContext != null) {
            MediaPlaybackCoordinator.shared.stopAllPlayback()
        }
        _snapshot.update {
            it.copy(
                reelsViewerContext = null,
                storyViewerContext = null,
                hubPlaybackExpanded = if (it.hubPlaybackExpanded) false else it.hubPlaybackExpanded,
                globePanel = null,
                showAppMenu = false,
                sharePostSheet = null,
                selectedTab = AppTab.Feed,
                navigationPath = emptyList(),
            )
        }
        if (itHubExpanded()) minimizeHubPlayback(returnToChat = false)
        val trimmedUsername = username?.trim()?.replace(Regex("^@+"), "")
        val trimmedId = userId.trim()
        engagement.profileOpened(trimmedId, trimmedUsername)
        when {
            trimmedId.isNotEmpty() -> navigate(AppDestination.PublicProfileByUserId(trimmedId))
            !trimmedUsername.isNullOrEmpty() -> navigate(AppDestination.PublicProfile(trimmedUsername))
        }
    }

    private fun itHubExpanded(): Boolean = _snapshot.value.hubPlaybackExpanded

    fun openFromMenu(destination: AppDestination) {
        _snapshot.update { it.copy(showAppMenu = false) }
        when (destination) {
            is AppDestination.People,
            is AppDestination.Ads,
            is AppDestination.EditProfile,
            is AppDestination.Settings,
            is AppDestination.Premium,
            is AppDestination.Search,
            -> _snapshot.update {
                it.copy(selectedTab = AppTab.Feed, navigationPath = listOf(destination))
            }
            else -> navigate(destination)
        }
    }

    fun openProfileFromMenu() {
        _snapshot.update {
            it.copy(showAppMenu = false, selectedTab = AppTab.Profile, navigationPath = emptyList())
        }
    }

    fun openSavedFromMenu(section: ProfileLibrarySection = ProfileLibrarySection.SAVED_POSTS) {
        _snapshot.update {
            it.copy(
                showAppMenu = false,
                profileLibrarySection = section,
                selectedTab = AppTab.Profile,
                navigationPath = emptyList(),
            )
        }
    }

    fun openNotificationsFromMenu() {
        _snapshot.update {
            it.copy(showAppMenu = false, globePanel = GlobePanel.NOTIFICATIONS)
        }
        scope.launch { refreshNotifications() }
    }

    fun goToFeedTop(scroll: Boolean = true) {
        _snapshot.update {
            it.copy(
                showCreateMenu = false,
                activeCreateSheet = null,
                showAppMenu = false,
                globePanel = null,
                navigationPath = emptyList(),
                selectedTab = AppTab.Feed,
                feedScrollToTopToken = if (scroll) it.feedScrollToTopToken + 1 else it.feedScrollToTopToken,
            )
        }
    }

    fun reloadContent() {
        contentCache.invalidateAllFeeds()
        _snapshot.update { it.copy(contentLoadGeneration = it.contentLoadGeneration + 1) }
        homeFeed.beginFreshSession()
    }

    // ── Hubs playback ─────────────────────────────────────────────────

    fun startHubPlayback(post: CountryPost, expanded: Boolean = true) {
        val quick = PlayPlatformBridge.hubWatchPresentation(post)
        applyHubPlayback(quick, expanded)
        scope.launch {
            val resolved = PlayPlatformBridge.resolveHubWatchPresentation(post, postsService)
            val current = _snapshot.value.hubPlaybackPost
            if (current?.id != quick.id && current?.id != post.id) return@launch
            if (resolved.authorId != current?.authorId ||
                (resolved.playableVideoUrl != null && current?.playableVideoUrl == null)
            ) {
                applyHubPlayback(resolved, _snapshot.value.hubPlaybackExpanded)
            }
        }
    }

    private fun applyHubPlayback(watchPost: CountryPost, expanded: Boolean) {
        MediaPlaybackCoordinator.shared.pauseAll()
        _snapshot.update { s ->
            var next = s.copy(
                showAppMenu = false,
                globePanel = null,
                reelsViewerContext = null,
                isPlayPresented = false,
                pendingLivingVideoId = null,
                pendingLivingVideo = null,
                hubPlaybackPlaying = true,
                hubPlaybackMuted = false,
            )
            if (expanded) {
                val returnId = currentConversationIdOnPath()
                next = next.copy(
                    navigationPath = emptyList(),
                    selectedTab = AppTab.Hubs,
                    hubPlaybackExpanded = true,
                    hubPlaybackReturnConversationId = returnId ?: next.hubPlaybackReturnConversationId,
                )
            } else {
                next = next.copy(hubPlaybackExpanded = false)
            }
            val switching = next.hubPlaybackPost?.id != watchPost.id
            if (switching || next.hubPlaybackPost == null) {
                next = next.copy(
                    hubPlaybackPost = watchPost,
                    hubWatchScrollCollapse = 0f,
                    hubPlaybackVideoAspect = 16f / 9f,
                )
            } else if (next.hubPlaybackPost?.playableVideoUrl == null && watchPost.playableVideoUrl != null) {
                next = next.copy(hubPlaybackPost = watchPost)
            } else if (next.hubPlaybackPost?.authorId != watchPost.authorId) {
                next = next.copy(hubPlaybackPost = watchPost)
            }
            next
        }
        FeedVideoFocus.shared.resetAll()
        youtubeCatalog.recordWatch(watchPost.id)
        engagement.hubVideoOpened(watchPost)
    }

    fun minimizeHubPlayback(returnToChat: Boolean = true, animated: Boolean = true) {
        @Suppress("UNUSED_VARIABLE")
        val _a = animated
        if (_snapshot.value.hubPlaybackPost == null) return
        val conversationId = _snapshot.value.hubPlaybackReturnConversationId
        _snapshot.update {
            it.copy(
                hubPlaybackPlaying = true,
                hubWatchScrollCollapse = 0f,
                hubPlaybackPullProgress = max(it.hubPlaybackPullProgress, 1f),
                hubPlaybackExpanded = false,
            )
        }
        scope.launch {
            delay(40)
            FeedVideoFocus.shared.resetAll()
            syncHubPlaybackChatReturnWithPath()
            if (returnToChat && conversationId != null) {
                delay(120)
                if (_snapshot.value.hubPlaybackPost != null && !_snapshot.value.hubPlaybackExpanded) {
                    _snapshot.update {
                        it.copy(
                            selectedTab = AppTab.Messages,
                            navigationPath = listOf(AppDestination.Conversation(conversationId)),
                        )
                    }
                }
            }
        }
    }

    fun ensureHubPlaybackMinimizedIfNeeded() {
        val s = _snapshot.value
        if (s.hubPlaybackPost != null && s.selectedTab != AppTab.Hubs) {
            minimizeHubPlayback(returnToChat = false)
        }
    }

    fun expandHubPlayback() {
        if (_snapshot.value.hubPlaybackPost == null) return
        val returnId = currentConversationIdOnPath()
        _snapshot.update {
            it.copy(
                hubPlaybackReturnConversationId = returnId ?: it.hubPlaybackReturnConversationId,
                navigationPath = emptyList(),
                selectedTab = AppTab.Hubs,
                hubPlaybackPlaying = true,
                hubWatchScrollCollapse = 0f,
                hubPlaybackExpanded = true,
            )
        }
    }

    fun stopHubPlayback() {
        _snapshot.update {
            it.copy(
                hubPlaybackPost = null,
                hubPlaybackExpanded = false,
                hubPlaybackPlaying = false,
                hubPlaybackPullProgress = 0f,
                hubWatchScrollCollapse = 0f,
                hubPlaybackVideoAspect = 16f / 9f,
                hubPlaybackReturnConversationId = null,
            )
        }
        MediaPlaybackCoordinator.shared.stopAllPlayback()
        FeedVideoFocus.shared.resetAll()
    }

    fun setHubPlaybackPlaying(playing: Boolean) {
        _snapshot.update { it.copy(hubPlaybackPlaying = playing) }
    }

    fun inviteFriendsFromMenu() {
        _snapshot.update { it.copy(showAppMenu = false) }
    }

    fun noteHubPlaybackVideoSize(width: Float, height: Float) {
        if (width <= 2 || height <= 2) return
        val next = width / height
        if (!next.isFinite() || next <= 0.3f || next >= 3.5f) return
        _snapshot.update {
            if (kotlin.math.abs(next - it.hubPlaybackVideoAspect) > 0.02f) {
                it.copy(hubPlaybackVideoAspect = next)
            } else it
        }
    }

    fun currentConversationIdOnPath(): String? {
        for (d in _snapshot.value.navigationPath.asReversed()) {
            if (d is AppDestination.Conversation) return d.conversationId
        }
        return null
    }

    fun syncHubPlaybackChatReturnWithPath() {
        val returnId = _snapshot.value.hubPlaybackReturnConversationId ?: return
        if (_snapshot.value.hubPlaybackExpanded) return
        if (currentConversationIdOnPath() != returnId) {
            _snapshot.update { it.copy(hubPlaybackReturnConversationId = null) }
        }
    }

    fun openLivingVideo(postId: String, tab: YouTubeMainTab? = null, post: CountryPost? = null) {
        val returnId = currentConversationIdOnPath()
        _snapshot.update {
            it.copy(
                hubPlaybackReturnConversationId = returnId ?: it.hubPlaybackReturnConversationId,
                navigationPath = emptyList(),
                showAppMenu = false,
                globePanel = null,
                reelsViewerContext = null,
                isPlayPresented = false,
                pendingPlayTab = tab ?: it.pendingPlayTab,
            )
        }
        if (post != null && (post.id == postId || postId.isEmpty()) &&
            (post.hasVideo || post.playableVideoUrl != null)
        ) {
            startHubPlayback(post, expanded = true)
            return
        }
        if (post != null && (post.playableVideoUrl != null || post.hasVideo)) {
            startHubPlayback(post, expanded = true)
            return
        }
        MediaPlaybackCoordinator.shared.pauseAll()
        _snapshot.update {
            it.copy(
                pendingLivingVideoId = postId,
                pendingLivingVideo = if (post?.id == postId) post else null,
                selectedTab = AppTab.Hubs,
                hubPlaybackExpanded = true,
                hubPlaybackPlaying = true,
            )
        }
    }

    fun clearPendingLivingVideo() {
        _snapshot.update { it.copy(pendingLivingVideoId = null, pendingLivingVideo = null) }
    }

    fun clearPendingPlayRouting() {
        _snapshot.update {
            it.copy(
                pendingPlayTab = null,
                pendingPlayChannelAuthorId = null,
                pendingPlayChannelUsername = null,
            )
        }
    }

    fun openPlay(tab: YouTubeMainTab = YouTubeMainTab.Home) {
        _snapshot.update {
            it.copy(
                navigationPath = emptyList(),
                showAppMenu = false,
                globePanel = null,
                isPlayPresented = false,
                pendingPlayTab = tab,
                selectedTab = AppTab.Hubs,
            )
        }
    }

    fun openPlayFromMenu(tab: YouTubeMainTab = YouTubeMainTab.Home) = openPlay(tab)

    fun openPlayChannel(authorId: String, username: String? = null) {
        _snapshot.update {
            it.copy(
                navigationPath = emptyList(),
                showAppMenu = false,
                globePanel = null,
                isPlayPresented = false,
                pendingPlayChannelAuthorId = authorId,
                pendingPlayChannelUsername = username,
                selectedTab = AppTab.Hubs,
            )
        }
    }

    fun openPlayChannel(username: String) {
        _snapshot.update {
            it.copy(
                navigationPath = emptyList(),
                showAppMenu = false,
                globePanel = null,
                isPlayPresented = false,
                pendingPlayChannelUsername = username,
                selectedTab = AppTab.Hubs,
            )
        }
    }

    fun presentPlaySurface() = openPlay(YouTubeMainTab.Home)

    fun dismissPlay() {
        _snapshot.update { it.copy(isPlayPresented = false) }
        clearPendingLivingVideo()
        clearPendingPlayRouting()
    }

    // ── Posts / reels / feed actions ──────────────────────────────────

    fun openPost(post: CountryPost) {
        when {
            post.isReel -> openReelsViewer(post)
            PlayPlatformBridge.isHubCatalogContent(post) && post.hasVideo -> {
                scope.launch {
                    val presentation = PlayPlatformBridge.resolveHubWatchPresentation(post, postsService)
                    openLivingVideo(presentation.id, tab = YouTubeMainTab.Home, post = presentation)
                }
            }
            else -> {
                _snapshot.update {
                    it.copy(selectedTab = AppTab.Feed, navigationPath = emptyList())
                }
                navigate(AppDestination.Post(post.id))
            }
        }
    }

    fun openPost(id: String) {
        scope.launch {
            val post = runCatching { postsService.getPostById(id) }.getOrNull()
            if (post != null) openPost(post)
            else {
                _snapshot.update {
                    it.copy(selectedTab = AppTab.Feed, navigationPath = emptyList())
                }
                navigate(AppDestination.Post(id))
            }
        }
    }

    fun openPlayVideo(id: String) {
        scope.launch {
            val post = runCatching { postsService.getPostById(id) }.getOrNull()
            if (post != null) openPost(post) else openLivingVideo(id)
        }
    }

    fun openPostInFeed(postId: String) {
        _snapshot.update {
            it.copy(selectedTab = AppTab.Feed, navigationPath = emptyList())
        }
        navigate(AppDestination.Post(postId))
    }

    fun openReelsViewer(startingPost: CountryPost, seedPosts: List<CountryPost> = emptyList()) {
        MediaPlaybackCoordinator.shared.pauseAll()
        _snapshot.update {
            it.copy(
                hubPlaybackPlaying = false,
                reelsViewerContext = ReelsViewerContext(startingPost, seedPosts),
            )
        }
    }

    fun openGlobalSparksViewer(startingPost: CountryPost) {
        val start = ReelsRankingEngine.resolvePlayerStart(startingPost)
        if (start.playableVideoUrl == null) {
            scope.launch {
                var resolved = start
                val sid = com.matterya.matterya.model.SparkShareMarker.originId(startingPost.body)
                    ?: startingPost.sharedPostId
                if (sid != null) {
                    runCatching { postsService.getPostById(sid) }.getOrNull()
                        ?.takeIf { it.playableVideoUrl != null }
                        ?.let { resolved = it }
                }
                if (resolved.playableVideoUrl == null) {
                    runCatching { postsService.getPostById(start.id) }.getOrNull()
                        ?.takeIf { it.playableVideoUrl != null }
                        ?.let { resolved = it }
                }
                if (resolved.playableVideoUrl == null) {
                    showToast("${MatteryaCopy.noSparksYet} — publish one to get started.", ToastStyle.Info)
                    return@launch
                }
                presentGlobalSparks(resolved)
            }
            return
        }
        presentGlobalSparks(start)
    }

    private fun presentGlobalSparks(start: CountryPost) {
        val seeds = instantSparksSeedQueue(start)
        openReelsViewer(start, seeds)
        if (seeds.size < 12) {
            scope.launch { postsService.loadSparksDiscoveryCatalog(forceRefresh = false) }
        }
    }

    private fun instantSparksSeedQueue(start: CountryPost, limit: Int = 48): List<CountryPost> {
        val head = ReelsRankingEngine.resolvePlayerStart(start)
        val out = mutableListOf(head)
        val seen = mutableSetOf(head.id)
        fun absorb(posts: List<CountryPost>) {
            for (post in posts) {
                if (!seen.add(post.id)) continue
                if (!ReelsRankingEngine.isSparkEligible(post)) continue
                out.add(post)
                if (out.size >= limit) return
            }
        }
        absorb(postsService.sparksCatalogSnapshot().shuffled())
        if (out.size < limit) absorb(postsService.hubsSessionCatalog.shuffled())
        return out
    }

    fun openReelsFromMenu() {
        scope.launch {
            val reels = postsService.beginFreshSparksSession(preferStart = null)
            val first = reels.firstOrNull()
            if (first == null) {
                showToast("${MatteryaCopy.noSparksYet} — publish one to get started.", ToastStyle.Info)
                openPlay()
                return@launch
            }
            openReelsViewer(first, reels)
        }
    }

    fun openCountryReels(country: Country) {
        scope.launch {
            val posts = runCatching { postsService.videoPosts(country.iso) }.getOrDefault(emptyList())
            val reels = posts.filter { it.isReel && it.playableVideoUrl != null }
            val first = reels.firstOrNull()
            if (first == null) {
                showToast("${MatteryaCopy.noSparksForCountry} ${country.name} yet.", ToastStyle.Info)
                openPlay()
                return@launch
            }
            openReelsViewer(first, reels)
        }
    }

    fun toggleLike(post: CountryPost) {
        scope.launch {
            val optimistic = if (post.likedByMe) {
                post.copyEngagement(likedByMe = false, likeCount = (post.likeCount - 1).coerceAtLeast(0))
            } else {
                post.copyEngagement(likedByMe = true, likeCount = post.likeCount + 1)
            }
            homeFeed.applyLocalUpdate(optimistic)
            engagement.enqueueLike(post, !post.likedByMe)
            val updated = postsService.toggleLike(post)
            homeFeed.applyLocalUpdate(updated)
        }
    }

    fun applyPostUpdate(post: CountryPost) {
        homeFeed.applyLocalUpdate(post)
    }

    fun toggleFollow(userId: String) {
        scope.launch {
            val id = userId.trim()
            if (id.isEmpty() || id == _snapshot.value.currentProfile?.userId) return@launch
            val wasFollowing = id in _snapshot.value.followingIds
            _snapshot.update { s ->
                val deltas = s.followFollowerDeltas.toMutableMap()
                deltas[id] = (deltas[id] ?: 0) + if (wasFollowing) -1 else 1
                s.copy(
                    followingIds = if (wasFollowing) s.followingIds - id else s.followingIds + id,
                    followFollowerDeltas = deltas,
                )
            }
            try {
                if (wasFollowing) followService.unfollow(id) else followService.follow(id)
                // Soft reconcile only — do NOT bump contentLoadGeneration (iOS freezes Sparks if we do).
                _snapshot.update {
                    it.copy(followingIds = followService.followingIds())
                }
                engagement.enqueuePersonFollow(id, !wasFollowing)
                if (followService.usesLocalFollow(id)) {
                    showToast(if (wasFollowing) "Unfollowed" else "Following", ToastStyle.Info)
                }
            } catch (e: Exception) {
                _snapshot.update { s ->
                    val deltas = s.followFollowerDeltas.toMutableMap()
                    deltas[id] = (deltas[id] ?: 0) + if (wasFollowing) 1 else -1
                    s.copy(
                        followingIds = if (wasFollowing) s.followingIds + id else s.followingIds - id,
                        followFollowerDeltas = deltas,
                    )
                }
                showToast(e.message ?: "Follow failed", ToastStyle.Error)
            }
        }
    }

    fun isFollowing(userId: String): Boolean = userId in _snapshot.value.followingIds

    fun resolvedFollowerCount(userId: String, base: Int?): Int {
        val id = userId.trim()
        val delta = _snapshot.value.followFollowerDeltas[id] ?: 0
        return max(0, (base ?: 0) + delta)
    }

    fun clearFollowerCountDeltas(userIds: Iterable<String>) {
        _snapshot.update { s ->
            val deltas = s.followFollowerDeltas.toMutableMap()
            userIds.forEach { raw ->
                val id = raw.trim()
                if (id.isNotEmpty()) deltas.remove(id)
            }
            s.copy(followFollowerDeltas = deltas)
        }
    }

    fun blockUser(userId: String, username: String? = null, displayName: String? = null) {
        blockService.block(userId, username, displayName)
        _snapshot.update {
            it.copy(followingIds = it.followingIds - userId)
        }
        reloadContent()
        showToast("Account blocked")
    }

    fun unblockUser(userId: String) {
        blockService.unblock(userId)
        showToast("Account unblocked")
    }

    // ── Notifications ─────────────────────────────────────────────────

    suspend fun refreshNotifications() {
        val all = notificationsService.list(80)
        val notifCount = notificationsService.unreadCount()
        val messagesCount = messagesService.messagesUnreadCount()
        _snapshot.update {
            it.copy(
                notifications = all.filter { n: NotificationItem -> !n.isMessageType },
                notificationsUnreadCount = notifCount,
                messagesUnreadCount = messagesCount,
            )
        }
    }

    suspend fun refreshUnreadCounts() {
        val notifCount = notificationsService.unreadCount()
        val messagesCount = messagesService.messagesUnreadCount()
        _snapshot.update {
            it.copy(notificationsUnreadCount = notifCount, messagesUnreadCount = messagesCount)
        }
    }

    suspend fun markNotificationRead(notification: NotificationItem) {
        applyLocalNotificationRead(notification)
        runCatching { notificationsService.markRead(notification.id) }
        refreshUnreadCounts()
    }

    suspend fun markAllNotificationsRead() {
        try {
            notificationsService.markAllRead()
        } catch (_: Exception) {
            showToast("Could not mark notifications read", ToastStyle.Error)
            return
        }
        _snapshot.update {
            it.copy(
                notifications = it.notifications.map { n -> n.markedAsRead() },
                notificationsUnreadCount = 0,
            )
        }
        refreshUnreadCounts()
    }

    fun openNotification(notification: NotificationItem) {
        applyLocalNotificationRead(notification)
        val type = notification.type.lowercase()
        val opened = routeNotificationDestination(notification, type)
        scope.launch {
            runCatching { notificationsService.markRead(notification.id) }
            refreshUnreadCounts()
            refreshNotifications()
        }
        if (!opened) showToast("Couldn't open that notification.", ToastStyle.Error)
    }

    private fun routeNotificationDestination(notification: NotificationItem, type: String): Boolean {
        _snapshot.update {
            it.copy(showAppMenu = false, reelsViewerContext = null, isPlayPresented = false)
        }
        notification.conversationId?.let {
            _snapshot.update { s -> s.copy(globePanel = null) }
            openConversation(it)
            return true
        }
        if (type == "follow") {
            notification.actorUserId?.let { actorId ->
                _snapshot.update { it.copy(globePanel = null) }
                openPublicProfile(notification.actor?.username, actorId)
                return true
            }
        }
        notification.resolvedPostId?.let {
            openNotificationPost(it)
            return true
        }
        if (notification.entityType?.equals("post", true) == true) {
            notification.entityId?.trim()?.takeIf { it.isNotEmpty() }?.let {
                openNotificationPost(it)
                return true
            }
        }
        if (type in listOf("like", "comment", "comment_like", "comment_reply", "reply", "mention", "share")) {
            notification.entityId?.trim()?.takeIf { it.isNotEmpty() }?.let {
                openNotificationPost(it)
                return true
            }
        }
        notification.actorUserId?.let {
            _snapshot.update { s -> s.copy(globePanel = null) }
            openPublicProfile(notification.actor?.username, it)
            return true
        }
        _snapshot.update { it.copy(globePanel = null) }
        return false
    }

    fun openNotificationPost(id: String, preferComments: Boolean = false) {
        @Suppress("UNUSED_VARIABLE")
        val _p = preferComments
        val trimmed = id.trim()
        if (trimmed.isEmpty()) return
        _snapshot.update {
            it.copy(
                showAppMenu = false,
                globePanel = null,
                reelsViewerContext = null,
                isPlayPresented = false,
                selectedTab = AppTab.Feed,
                navigationPath = listOf(AppDestination.Post(trimmed)),
            )
        }
    }

    private fun applyLocalNotificationRead(notification: NotificationItem) {
        if (!notification.isUnread) return
        _snapshot.update {
            it.copy(
                notifications = it.notifications.map { n ->
                    if (n.id == notification.id) n.markedAsRead() else n
                },
                notificationsUnreadCount = max(0, it.notificationsUnreadCount - 1),
            )
        }
    }

    suspend fun clearNotifications(forConversation: String) {
        val trimmed = forConversation.trim()
        if (trimmed.isEmpty()) return
        val all = notificationsService.list(40)
        for (item in all) {
            if (item.isMessageType && item.isUnread && item.conversationId == trimmed) {
                runCatching { notificationsService.markRead(item.id) }
            }
        }
        refreshUnreadCounts()
    }

    fun handlePushNavigation(type: String, conversationId: String?, postId: String?, username: String?) {
        val s = _snapshot.value
        if (!s.isAuthenticated || !s.isSessionReady) {
            pendingPushRoute = PendingPushRoute(type, conversationId, postId, username)
            return
        }
        applyPushNavigation(type, conversationId, postId, username)
    }

    fun flushPendingPushRoute() {
        val pending = pendingPushRoute ?: return
        val s = _snapshot.value
        if (!s.isAuthenticated || !s.isSessionReady) return
        pendingPushRoute = null
        applyPushNavigation(pending.type, pending.conversationId, pending.postId, pending.username)
    }

    private fun applyPushNavigation(type: String, conversationId: String?, postId: String?, username: String?) {
        _snapshot.update {
            it.copy(
                showAppMenu = false,
                globePanel = null,
                reelsViewerContext = null,
                isPlayPresented = false,
            )
        }
        val normalized = type.lowercase()
        if (normalized == "message" && !conversationId.isNullOrEmpty()) {
            openConversation(conversationId)
            return
        }
        if (normalized == "call" || normalized == "incoming_call") {
            _snapshot.update { it.copy(selectedTab = AppTab.Messages, navigationPath = emptyList()) }
            return
        }
        if (normalized == "follow") {
            _snapshot.update { it.copy(selectedTab = AppTab.Feed, navigationPath = emptyList()) }
            if (!username.isNullOrEmpty()) openPublicProfile(username, username)
            return
        }
        if (!postId.isNullOrEmpty()) {
            openNotificationPost(
                postId,
                preferComments = notificationTypeOpensComments(normalized),
            )
            return
        }
        _snapshot.update { it.copy(globePanel = GlobePanel.NOTIFICATIONS) }
        scope.launch { refreshNotifications() }
    }

    private fun notificationTypeOpensComments(type: String): Boolean =
        type in setOf("comment", "comment_like", "comment_reply", "reply")

    // ── Country / compose / share ─────────────────────────────────────

    fun selectCountry(country: Country) {
        _snapshot.update { it.copy(selectedCountry = country, countryTab = CountryTab.POSTS) }
        scope.launch {
            refreshCountryStats(country)
            presenceService.startHeartbeat(country.iso)
        }
    }

    fun clearCountry() {
        _snapshot.update {
            it.copy(selectedCountry = null, countryStats = null, countryTab = CountryTab.POSTS)
        }
        startPresence()
    }

    suspend fun resolveHomeCountry(): Country? {
        val code = _snapshot.value.currentProfile?.countryCode?.uppercase()?.takeIf { it.isNotEmpty() }
            ?: return null
        val countries = runCatching { profileService.countries() }.getOrDefault(emptyList())
        countries.firstOrNull { it.iso.equals(code, true) }?.let { return it }
        val name = _snapshot.value.currentProfile?.countryName ?: code
        return Country(id = code, name = name, iso = code)
    }

    fun canPostToCountry(country: Country): Boolean {
        val home = _snapshot.value.homeCountryIso ?: return false
        return home == country.iso.uppercase()
    }

    /**
     * iOS `navigateToHomeCountryFeed` — select home country + optional composer flag.
     *
     * Note: [navigate] intentionally no-ops [AppDestination.CountryFeed] (same as iOS —
     * country feeds are driven by NavHost `country/{iso}` on Android). Callers that need
     * the route pushed should use NavController after this (see MainTabView go-home).
     * We still [selectCountry] + set [openComposerOnCountryFeed] so the destination feed
     * opens the composer reliably.
     */
    fun navigateToHomeCountryFeed(openComposer: Boolean = false) {
        scope.launch {
            val home = resolveHomeCountry()
            if (home == null) {
                showToast("Set your home country in profile before posting.", ToastStyle.Error)
                return@launch
            }
            _snapshot.update {
                it.copy(globePanel = null, showAppMenu = false, navigationPath = emptyList())
            }
            selectCountry(home)
            // Keep selectedCountry (do not call navigate(CountryFeed) which clears it).
            if (openComposer) {
                _snapshot.update { it.copy(openComposerOnCountryFeed = true) }
            }
        }
    }

    fun clearOpenComposerOnCountryFeed() {
        _snapshot.update { it.copy(openComposerOnCountryFeed = false) }
    }

    fun requestOpenComposerOnCountryFeed() {
        _snapshot.update { it.copy(openComposerOnCountryFeed = true) }
    }

    fun presentCreateSheet(sheet: CreateContentSheet) {
        scope.launch {
            val home = resolveHomeCountry()
            if (home == null) {
                showToast("Set your home country in profile before posting.", ToastStyle.Error)
                return@launch
            }
            _snapshot.update {
                it.copy(
                    composerCountry = home,
                    showCreateMenu = false,
                    activeCreateSheet = sheet,
                )
            }
        }
    }

    fun presentHubVideoCreate() {
        _snapshot.update { it.copy(showCreateMenu = false) }
        if (LivingChannelMarker.hasChannel(_snapshot.value.currentProfile)) {
            presentCreateSheet(CreateContentSheet.HUB_VIDEO)
        } else {
            pendingHubCreateSheet = CreateContentSheet.HUB_VIDEO
            _snapshot.update { it.copy(activeCreateSheet = CreateContentSheet.CHANNEL_SETUP) }
        }
    }

    fun presentHubSparkCreate() {
        _snapshot.update { it.copy(showCreateMenu = false) }
        if (LivingChannelMarker.hasChannel(_snapshot.value.currentProfile)) {
            presentCreateSheet(CreateContentSheet.REEL)
        } else {
            pendingHubCreateSheet = CreateContentSheet.REEL
            _snapshot.update { it.copy(activeCreateSheet = CreateContentSheet.CHANNEL_SETUP) }
        }
    }

    fun completeChannelSetupAndContinue() {
        scope.launch {
            val next = pendingHubCreateSheet ?: CreateContentSheet.HUB_VIDEO
            pendingHubCreateSheet = null
            _snapshot.value.currentProfile?.let { me ->
                runCatching { profileService.profileById(me.userId) }.getOrNull()?.let { fresh ->
                    _snapshot.update { it.copy(currentProfile = fresh) }
                }
            }
            presentCreateSheet(next)
        }
    }

    fun presentShareSheet(forPost: CountryPost) {
        if (forPost.isStory) {
            showToast("Moments live in Globe — they aren't shared as feed posts.", ToastStyle.Info)
            return
        }
        _snapshot.update { it.copy(sharePostSheet = forPost) }
    }

    fun needsRepeatShareWarning(forPost: CountryPost): Boolean {
        val profile = _snapshot.value.currentProfile ?: return false
        val countryCode = _snapshot.value.homeCountryIso?.uppercase() ?: return false
        val originalId = forPost.sharedPostId ?: forPost.id
        if (forPost.countryCode?.uppercase() == countryCode &&
            forPost.authorId == profile.userId &&
            forPost.sharedPostId == null
        ) return true
        val cached = (contentCache.posts(ContentCacheKey.HomeFeed) ?: emptyList()) +
            (contentCache.posts(ContentCacheKey.ProfilePosts) ?: emptyList())
        return cached.any { it.authorId == profile.userId && it.sharedPostId == originalId }
    }

    suspend fun sharePostToCountryFeed(post: CountryPost, caption: String? = null): String {
        if (!_snapshot.value.isAuthenticated) return "Sign in to share."
        if (post.isStory) return "Moments live in Globe — they can't be shared as feed posts."
        val profile = _snapshot.value.currentProfile
        val countryCode = _snapshot.value.homeCountryIso
        val countryName = profile?.countryName
        if (profile == null || countryCode == null || countryName.isNullOrEmpty()) {
            return "Set your home country to share."
        }
        val isHubCatalogShare = PlayPlatformBridge.isHubCatalogContent(post) || post.isHubSeedVideo
        val isSparkShare = (post.isReel || PlayPlatformBridge.isReelVideo(post)) &&
            !(isHubCatalogShare && !post.isReel)
        val stayInSparks = _snapshot.value.reelsViewerContext != null
        val stayInHubsWatch = _snapshot.value.hubPlaybackPost != null && _snapshot.value.hubPlaybackExpanded
        val stayInPlace = stayInSparks || stayInHubsWatch
        var placeholderId: String? = null
        if (post.hasVideo && !stayInPlace) {
            placeholderId = beginFeedVideoUpload(
                caption = caption?.trim()?.takeIf { it.isNotEmpty() }
                    ?: (post.displayHeadline ?: post.displayBody),
                preview = null,
                isHub = isHubCatalogShare,
            )
            homeFeed.updateVideoUpload(placeholderId, 0.35, "Sharing")
        }
        return try {
            val created = postsService.sharePostToCountryFeed(
                post = post,
                countryName = countryName,
                countryCode = countryCode,
                cityName = profile.cityName,
                caption = caption,
            )
            contentCache.invalidate(ContentCacheKey.HomeFeed, ContentCacheKey.LivingVideos)
            contentCache.invalidateAllFeeds()
            _snapshot.update { it.copy(contentLoadGeneration = it.contentLoadGeneration + 1) }
            homeFeed.insertNewPost(created)
            if (stayInPlace) {
                _snapshot.update {
                    it.copy(
                        sharePostSheet = null,
                        hubPlaybackPlaying = if (stayInHubsWatch) true else it.hubPlaybackPlaying,
                    )
                }
            } else if (placeholderId != null) {
                finishFeedVideoUpload(placeholderId, created)
            } else {
                goToFeedTop(scroll = true)
            }
            when {
                isSparkShare -> "Spark shared to the main feed."
                post.countryName != null && post.countryName != countryName ->
                    "Shared from ${post.countryName} to the main feed."
                else -> "Shared to the main feed."
            }
        } catch (e: Exception) {
            placeholderId?.let { failFeedVideoUpload(it, e.message ?: "Share failed") }
            e.message ?: "Share failed"
        }
    }

    fun beginFeedVideoUpload(caption: String, preview: Bitmap?, isHub: Boolean): String {
        val id = homeFeed.beginVideoUpload(caption, preview, isHub)
        goToFeedTop(scroll = true)
        return id
    }

    fun finishFeedVideoUpload(placeholderId: String, post: CountryPost) {
        homeFeed.completeVideoUpload(placeholderId, post)
        contentCache.invalidate(
            ContentCacheKey.HomeFeed,
            ContentCacheKey.LivingVideos,
            ContentCacheKey.ProfilePosts,
        )
        goToFeedTop(scroll = true)
        showToast(
            if (PlayPlatformBridge.isHubChannelUpload(post)) {
                "Published to ${MatteryaCopy.matteryaHubs}"
            } else {
                "Posted to your feed"
            },
            ToastStyle.Success,
        )
    }

    fun failFeedVideoUpload(placeholderId: String, message: String) {
        homeFeed.failVideoUpload(placeholderId, message)
        showToast(message, ToastStyle.Error)
    }

    // ── Stories ───────────────────────────────────────────────────────

    suspend fun refreshStories() {
        val s = _snapshot.value
        val groups = postsService.loadActiveStoryGroups(
            countryCode = s.currentProfile?.countryCode?.uppercase(),
            followingIds = s.followingIds,
            viewedStoryIds = viewedStoryIds,
            currentUserId = s.currentProfile?.userId,
        )
        _snapshot.update { it.copy(storyGroups = groups) }
    }

    val viewedStoryIds: Set<String>
        get() = prefs.getStringSet(viewedStoriesDefaultsKey, emptySet())?.toSet().orEmpty()

    fun markStoryViewed(postId: String) {
        val ids = viewedStoryIds + postId
        prefs.edit().putStringSet(viewedStoriesDefaultsKey, ids).apply()
        _snapshot.update { s ->
            s.copy(
                storyGroups = s.storyGroups.map { group ->
                    if (group.stories.none { it.id == postId }) group
                    else StoryGroup(
                        authorId = group.authorId,
                        author = group.author,
                        stories = group.stories,
                        hasUnviewed = group.stories.any { it.id !in ids },
                    )
                },
            )
        }
    }

    fun openStoryViewer(group: StoryGroup) {
        val index = _snapshot.value.storyGroups.indexOfFirst { it.authorId == group.authorId }
        if (index < 0) return
        _snapshot.update {
            it.copy(
                storyViewerContext = StoryViewerContext(
                    groups = it.storyGroups,
                    groupIndex = index,
                    storyIndex = 0,
                ),
            )
        }
    }

    fun openStoryComposerOrViewer() {
        scope.launch {
            val mine = _snapshot.value.storyGroups.firstOrNull {
                it.authorId == _snapshot.value.currentProfile?.userId
            }
            if (mine != null && mine.stories.isNotEmpty()) openStoryViewer(mine)
            else presentCreateSheet(CreateContentSheet.STORY)
        }
    }

    // ── Letters ───────────────────────────────────────────────────────

    fun presentLetterCompose() {
        _snapshot.update {
            it.copy(letterComposePresented = true, navigationPath = it.navigationPath + AppDestination.Letters)
        }
    }

    fun presentLetterFlight(event: LetterFlightEvent) {
        _snapshot.update { it.copy(letterFlightEvent = event) }
    }

    fun dismissLetterFlight() {
        _snapshot.update { it.copy(letterFlightEvent = null) }
    }

    // ── Toast / deep links ────────────────────────────────────────────

    fun showToast(message: String, style: ToastStyle = ToastStyle.Success, durationSeconds: Double = 2.8) {
        val trimmed = message.trim()
        if (trimmed.contains("unexpected error", ignoreCase = true) ||
            trimmed.equals("Unexpected error", ignoreCase = true)
        ) return
        _snapshot.update { it.copy(toastMessage = message, toastStyle = style) }
        scope.launch {
            delay((max(1.0, durationSeconds) * 1000).toLong())
            if (_snapshot.value.toastMessage == message) {
                _snapshot.update { it.copy(toastMessage = null) }
            }
        }
    }

    fun handleDeepLink(url: String) {
        if (handleInternalDeepLink(url)) return
        val destination = shareService.parseDeepLink(url) ?: return
        _snapshot.update { it.copy(showAppMenu = false, globePanel = null) }
        when (destination) {
            is AppDestination.PlayWatch -> scope.launch { openPlayVideo(destination.postId) }
            is AppDestination.PlayChannel -> openPlayChannel(destination.username)
            is AppDestination.PlayChannelId -> openPlayChannel(authorId = destination.channelId)
            is AppDestination.Post -> openPost(destination.postId)
            is AppDestination.Conversation -> openConversation(destination.conversationId)
            is AppDestination.People,
            is AppDestination.Ads,
            is AppDestination.EditProfile,
            is AppDestination.Settings,
            is AppDestination.Premium,
            is AppDestination.Search,
            is AppDestination.Letters,
            is AppDestination.LetterThread,
            is AppDestination.News,
            is AppDestination.PublicProfile,
            is AppDestination.PublicProfileByUserId,
            is AppDestination.PublicProfileById,
            is AppDestination.Reels,
            is AppDestination.CountryFeed,
            -> _snapshot.update {
                it.copy(selectedTab = AppTab.Feed, navigationPath = listOf(destination))
            }
            else -> _snapshot.update {
                it.copy(selectedTab = AppTab.Feed, navigationPath = listOf(destination))
            }
        }
    }

    private fun handleInternalDeepLink(url: String): Boolean {
        val uri = android.net.Uri.parse(url)
        val scheme = uri.scheme?.lowercase().orEmpty()
        if (scheme != "matterya" && scheme != "worldapp") return false
        val host = uri.host?.lowercase().orEmpty()
        val pathParts = uri.path?.trim('/')?.split('/')?.filter { it.isNotEmpty() }.orEmpty()
        if (host == "tab") {
            val tabName = pathParts.firstOrNull()?.lowercase().orEmpty()
            val tab = AppTab.entries.firstOrNull { it.rawValue == tabName } ?: return false
            _snapshot.update {
                it.copy(showAppMenu = false, globePanel = null, navigationPath = emptyList(), selectedTab = tab)
            }
            return true
        }
        if (host == "search") {
            var q = uri.getQueryParameter("q")?.trim()
            if (q.isNullOrEmpty()) q = pathParts.firstOrNull()
            _snapshot.update {
                it.copy(
                    showAppMenu = false,
                    globePanel = null,
                    selectedTab = AppTab.Feed,
                    navigationPath = listOf(AppDestination.Search),
                    pendingSearchQuery = q,
                )
            }
            return true
        }
        return false
    }

    fun loadFloatingPosts() {
        scope.launch {
            // sample via recent posts
            val posts = postsService.fetchFirstPaintHomePosts(10)
            _snapshot.update { it.copy(floatingPosts = posts) }
        }
    }

    fun setShowCreateMenu(show: Boolean) {
        _snapshot.update { it.copy(showCreateMenu = show) }
    }

    fun setShowAppMenu(show: Boolean) {
        _snapshot.update { it.copy(showAppMenu = show) }
    }

    fun setFeedVideosMuted(muted: Boolean) {
        _snapshot.update { it.copy(feedVideosMuted = muted) }
    }

    fun setActiveCreateSheet(sheet: CreateContentSheet?) {
        _snapshot.update { it.copy(activeCreateSheet = sheet) }
    }

    fun setSharePostSheet(post: CountryPost?) {
        _snapshot.update { it.copy(sharePostSheet = post) }
    }

    fun setReelsViewerContext(ctx: ReelsViewerContext?) {
        _snapshot.update { it.copy(reelsViewerContext = ctx) }
    }

    fun setStoryViewerContext(ctx: StoryViewerContext?) {
        _snapshot.update { it.copy(storyViewerContext = ctx) }
    }

    fun setGlobePanel(panel: GlobePanel?) {
        _snapshot.update { it.copy(globePanel = panel) }
    }

    fun toggleNotificationsPanel() {
        val current = _snapshot.value.globePanel
        if (current == GlobePanel.NOTIFICATIONS) {
            _snapshot.update { it.copy(globePanel = null) }
        } else {
            _snapshot.update { it.copy(globePanel = GlobePanel.NOTIFICATIONS) }
            scope.launch { refreshNotifications() }
        }
    }

    // ── Private helpers ───────────────────────────────────────────────

    private fun startPresence() {
        val iso = _snapshot.value.selectedCountry?.iso
            ?: _snapshot.value.currentProfile?.countryCode
        presenceService.startHeartbeat(iso)
    }

    private fun startPolling() {
        stopPolling()
        pollJob = scope.launch {
            while (true) {
                refreshUnreadCounts()
                refreshNotifications()
                delay(45_000)
            }
        }
    }

    private fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    private fun loadReelPresentationSavedIds(): Set<String> =
        prefs.getStringSet(reelSavedDefaultsKey, emptySet())?.toSet().orEmpty()

    private fun persistReelPresentationSavedIds() {
        prefs.edit().putStringSet(
            reelSavedDefaultsKey,
            _snapshot.value.reelPresentationSavedIds,
        ).apply()
    }

    private fun persistLocalSavedPostIds() {
        prefs.edit().putStringSet(localSavedPostIdsKey, _snapshot.value.savedPostIds).apply()
    }

    companion object {
        fun belongsInSavedSparks(post: CountryPost): Boolean {
            if (post.isStory) return false
            if (post.isReel || post.isSpark) return true
            if (post.isSparkFeedShare) return true
            if (PlayPlatformBridge.isSparkFeedCard(post)) return true
            if (post.isHubSeedVideo && post.hasVideo) {
                val type = (post.mediaType ?: "").lowercase()
                if (type == "reel" || type == "spark") return true
                if (type == "video" || type.isEmpty()) {
                    val media = (post.mediaUrl ?: "").lowercase()
                    if (media.contains("spark") || media.contains("/reel")) return true
                }
            }
            if (post.isR2HostedMedia && post.hasVideo && !PlayPlatformBridge.isHubCatalogContent(post)) {
                val media = (post.mediaUrl ?: "").lowercase()
                if (media.contains("spark") || media.contains("/reels") || media.contains("\"reel\"")) {
                    return true
                }
            }
            if (post.isArchiveSparkSource) return true
            return false
        }

        private fun preferredSavedPost(local: CountryPost, server: CountryPost, asSpark: Boolean): CountryPost {
            val serverHas = server.playableVideoUrl != null || !server.mediaUrl.isNullOrEmpty()
            val localHas = local.playableVideoUrl != null || !local.mediaUrl.isNullOrEmpty()
            if (!serverHas && localHas) return local
            if ((asSpark || belongsInSavedSparks(local)) && !belongsInSavedSparks(server)) return local
            return server
        }

        private fun mergeSavedLists(
            serverOrResolved: List<CountryPost>,
            localKeep: List<CountryPost>,
            savedIds: Set<String>,
        ): List<CountryPost> {
            val byId = linkedMapOf<String, CountryPost>()
            for (post in serverOrResolved) byId[post.id] = post.withSavedByMe(true)
            for (post in localKeep) {
                if (post.id !in savedIds) continue
                val existing = byId[post.id]
                byId[post.id] = if (existing != null) {
                    preferredSavedPost(post, existing, belongsInSavedSparks(post)).withSavedByMe(true)
                } else {
                    post.withSavedByMe(true)
                }
            }
            return byId.values.sortedByDescending { it.createdAt }
        }
    }
}
