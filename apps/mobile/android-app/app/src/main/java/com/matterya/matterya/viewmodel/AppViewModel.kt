package com.matterya.matterya.viewmodel

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.hubs.YouTubeCatalogService
import com.matterya.matterya.data.media.MediaService
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.data.posts.HomeFeedStore
import com.matterya.matterya.data.posts.PostsService
import com.matterya.matterya.data.posts.ProfileService
import com.matterya.matterya.data.search.MatteryaSearchEngine
import com.matterya.matterya.model.AppTab
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.MediaUploadPhase
import com.matterya.matterya.model.PostVisibility
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.UploadProgress
import com.matterya.matterya.model.excludingMoments
import com.matterya.matterya.model.excludingSparks
import com.matterya.matterya.ui.feed.FeedUploadPlaceholder
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Compatibility UI state for existing shells (MainActivity / MainShell).
 * Backed by [AppState] + [HomeFeedStore] as the real sources of truth.
 */
data class AppUiState(
    val bootstrapping: Boolean = true,
    val authenticated: Boolean = false,
    val sessionReady: Boolean = false,
    val needsProfileSetup: Boolean = false,
    val profile: Profile? = null,
    val selectedTab: AppTab = AppTab.Feed,
    val feedPosts: List<CountryPost> = emptyList(),
    val sparkStrip: List<CountryPost> = emptyList(),
    val hubStrip: List<CountryPost> = emptyList(),
    /** Continue watching shelf — history / in-progress hub long-form. */
    val continueWatching: List<CountryPost> = emptyList(),
    val feedLoading: Boolean = false,
    val feedError: String? = null,
    val pendingUploads: List<FeedUploadPlaceholder> = emptyList(),
    val authError: String? = null,
    val authBusy: Boolean = false,
    val messagesUnreadCount: Int = 0,
    val notificationsUnreadCount: Int = 0,
    val toastMessage: String? = null,
    val contentLoadGeneration: Int = 0,
    val savedJournalPosts: List<CountryPost> = emptyList(),
    val savedVideoPosts: List<CountryPost> = emptyList(),
    val savedReelPosts: List<CountryPost> = emptyList(),
    val followersCount: Int = 0,
    val followingCount: Int = 0,
)

/**
 * Android ViewModel facade over [AppState] (iOS AppState.swift port).
 * Prefer [appState] for full app-logic API surface.
 */
class AppViewModel(application: Application) : AndroidViewModel(application) {
    val appState = AppState(application)
    private val homeFeed = HomeFeedStore.get(application)
    private val postsService = PostsService()
    private val profileService = ProfileService()
    private val mediaService = MediaService.get(application)

    val state: StateFlow<AppUiState> = combine(
        appState.snapshot,
        homeFeed.state,
    ) { app, feed ->
        // Unique ids required by Compose LazyColumn keys in FeedView / Hubs.
        val posts = feed.displayedPosts.distinctBy { it.id }
        val sparks = posts.filter {
            it.isSparkFeedShare || it.isReel || PlayPlatformBridge.isSparkFeedCard(it)
        }.distinctBy { it.id }.take(14)
        val hubs = posts.filter {
            PlayPlatformBridge.isHubFeedCardVideo(it) || (it.hasVideo && !it.isReel)
        }.distinctBy { it.id }.take(12)
        // Continue watching: catalog history + in-progress hub long-form (iOS FeedView path).
        val catalog = YouTubeCatalogService.get(getApplication())
        val hubLongForm = (hubs + posts).filter {
            !it.isReel && PlayPlatformBridge.isHubCatalogContent(it) && it.playableVideoUrl != null
        }.distinctBy { it.id }
        val history = catalog.historyVideos(hubLongForm)
        val inProgress = hubLongForm
            .filter { catalog.playbackPosition(it.id) >= 1.0 }
            .sortedByDescending { catalog.playbackPosition(it.id) }
        val continueWatching = (history + inProgress).distinctBy { it.id }.take(8)
        AppUiState(
            bootstrapping = app.bootstrapping,
            authenticated = app.isAuthenticated,
            sessionReady = app.isSessionReady,
            needsProfileSetup = app.needsProfileSetup,
            profile = app.currentProfile,
            selectedTab = app.selectedTab,
            feedPosts = posts,
            sparkStrip = sparks,
            hubStrip = hubs,
            continueWatching = continueWatching,
            feedLoading = feed.isBootstrapping || feed.isRefreshing,
            feedError = feed.errorMessage,
            pendingUploads = feed.pendingUploads.map { p ->
                FeedUploadPlaceholder(
                    id = p.id,
                    caption = p.caption,
                    progress = p.progress.toFloat(),
                    isHub = p.isHub,
                    isSpark = !p.isHub,
                    failedMessage = p.failedMessage ?: p.phaseLabel.takeIf { it == "Failed" },
                )
            },
            authError = app.authError,
            authBusy = app.authBusy,
            messagesUnreadCount = app.messagesUnreadCount,
            notificationsUnreadCount = app.effectiveNotificationsUnreadCount,
            toastMessage = app.toastMessage,
            contentLoadGeneration = app.contentLoadGeneration,
            savedJournalPosts = app.savedJournalPosts,
            savedVideoPosts = app.savedVideoPosts,
            savedReelPosts = app.savedReelPosts,
            followersCount = 0,
            followingCount = app.followingIds.size,
        )
    }.stateIn(
        viewModelScope,
        SharingStarted.Eagerly,
        AppUiState(),
    )

    fun bootstrap() = appState.bootstrap()

    fun login(email: String, password: String) = appState.login(email, password)

    fun register(email: String, password: String) = appState.register(email, password)

    fun completeProfile(
        displayName: String,
        username: String? = null,
        countryName: String,
        countryCode: String? = null,
        cityName: String? = null,
        bio: String? = null,
        avatarUrl: String? = null,
    ) = appState.completeProfile(
        displayName = displayName,
        username = username,
        countryName = countryName,
        countryCode = countryCode,
        cityName = cityName,
        bio = bio,
        avatarUrl = avatarUrl,
    )

    fun logout() = appState.logout()

    fun selectTab(tab: AppTab) = appState.selectTab(tab)

    fun refreshFeed() {
        homeFeed.beginFreshSession()
    }

    fun loadMoreFeed() {
        homeFeed.requestLoadMore()
    }

    fun onFeedRowAppear(post: CountryPost) {
        homeFeed.onRowAppear(post)
    }

    fun toggleLike(post: CountryPost) = appState.toggleLike(post)

    fun applyPostUpdate(post: CountryPost) = appState.applyPostUpdate(post)

    fun toggleSave(post: CountryPost) {
        viewModelScope.launch {
            appState.toggleSavePost(post)
        }
    }

    fun toggleFollow(userId: String) = appState.toggleFollow(userId)

    fun onBecameActive() = appState.handleBecameActive()

    // ── Publish helpers (MediaService + PostsService) ─────────────────

    suspend fun publishPost(
        title: String,
        body: String,
        visibility: PostVisibility,
        imageUri: Uri?,
    ): CountryPost {
        val profile = state.value.profile
            ?: throw IllegalStateException("Profile required to publish.")
        val authorId = AuthService.instance.currentUser?.id
            ?: throw IllegalStateException("Not signed in.")
        val countryName = profile.countryName ?: "Home"
        val countryCode = profile.countryCode ?: "XX"
        var mediaUrl: String? = null
        var mediaType: String? = null
        if (imageUri != null) {
            val uploaded = mediaService.uploadPostMediaFromUri(imageUri, isVideo = false)
            mediaUrl = uploaded.publicURL
            mediaType = "image"
        }
        val post = postsService.createPost(
            authorId = authorId,
            body = body,
            countryName = countryName,
            countryCode = countryCode,
            cityName = profile.cityName,
            title = title.ifBlank { null },
            visibility = visibility,
            mediaType = mediaType,
            mediaUrl = mediaUrl,
        )
        homeFeed.insertNewPost(post)
        return post
    }

    suspend fun publishSpark(
        caption: String,
        videoUri: Uri,
        onPhase: (MediaUploadPhase) -> Unit,
        onProgress: (UploadProgress) -> Unit,
    ): CountryPost {
        val profile = state.value.profile
            ?: throw IllegalStateException("Profile required to publish.")
        val authorId = AuthService.instance.currentUser?.id
            ?: throw IllegalStateException("Not signed in.")
        val uploadId = homeFeed.beginVideoUpload(caption, preview = null, isHub = false)
        return try {
            onPhase(MediaUploadPhase.Compressing)
            homeFeed.updateVideoUpload(uploadId, 0.05, "Compressing")
            onPhase(MediaUploadPhase.Uploading)
            val uploaded = mediaService.uploadPostMediaFromUri(videoUri, isVideo = true) { p ->
                onProgress(p)
                homeFeed.updateVideoUpload(uploadId, 0.1 + p.fractionCompleted * 0.8, "Uploading")
            }
            onPhase(MediaUploadPhase.Publishing)
            homeFeed.updateVideoUpload(uploadId, 0.95, "Publishing")
            val post = postsService.createSpark(
                authorId = authorId,
                body = caption,
                countryName = profile.countryName ?: "Home",
                countryCode = profile.countryCode ?: "XX",
                cityName = profile.cityName,
                mediaUrl = uploaded.publicURL,
            )
            homeFeed.completeVideoUpload(uploadId, post)
            post
        } catch (e: Exception) {
            homeFeed.failVideoUpload(uploadId, e.message ?: "Upload failed")
            throw e
        }
    }

    suspend fun publishHubVideo(
        caption: String,
        videoTitle: String,
        videoUri: Uri,
        onPhase: (MediaUploadPhase) -> Unit,
        onProgress: (UploadProgress) -> Unit,
    ): CountryPost {
        val profile = state.value.profile
            ?: throw IllegalStateException("Profile required to publish.")
        val authorId = AuthService.instance.currentUser?.id
            ?: throw IllegalStateException("Not signed in.")
        val uploadId = homeFeed.beginVideoUpload(caption.ifBlank { videoTitle }, preview = null, isHub = true)
        return try {
            onPhase(MediaUploadPhase.Compressing)
            homeFeed.updateVideoUpload(uploadId, 0.05, "Compressing")
            onPhase(MediaUploadPhase.Uploading)
            val uploaded = mediaService.uploadPostMediaFromUri(videoUri, isVideo = true) { p ->
                onProgress(p)
                homeFeed.updateVideoUpload(uploadId, 0.1 + p.fractionCompleted * 0.8, "Uploading")
            }
            onPhase(MediaUploadPhase.Publishing)
            homeFeed.updateVideoUpload(uploadId, 0.95, "Publishing")
            val post = postsService.createHub(
                authorId = authorId,
                body = caption,
                countryName = profile.countryName ?: "Home",
                countryCode = profile.countryCode ?: "XX",
                cityName = profile.cityName,
                title = videoTitle.ifBlank { null },
                mediaUrl = uploaded.publicURL,
            )
            homeFeed.completeVideoUpload(uploadId, post)
            post
        } catch (e: Exception) {
            homeFeed.failVideoUpload(uploadId, e.message ?: "Upload failed")
            throw e
        }
    }

    suspend fun publishStory(
        caption: String,
        mediaUri: Uri,
        isVideo: Boolean,
        onPhase: (MediaUploadPhase) -> Unit,
        onProgress: (UploadProgress) -> Unit,
    ): CountryPost {
        val profile = state.value.profile
            ?: throw IllegalStateException("Profile required to publish.")
        val authorId = AuthService.instance.currentUser?.id
            ?: throw IllegalStateException("Not signed in.")
        onPhase(if (isVideo) MediaUploadPhase.Compressing else MediaUploadPhase.Uploading)
        val uploaded = mediaService.uploadPostMediaFromUri(mediaUri, isVideo = isVideo) { p ->
            onPhase(MediaUploadPhase.Uploading)
            onProgress(p)
        }
        onPhase(MediaUploadPhase.Publishing)
        return postsService.createStory(
            authorId = authorId,
            body = caption,
            countryName = profile.countryName ?: "Home",
            countryCode = profile.countryCode ?: "XX",
            cityName = profile.cityName,
            mediaUrl = uploaded.publicURL,
        )
    }

    suspend fun searchPeopleAndContent(query: String): Pair<List<Profile>, List<CountryPost>> {
        val q = query.trim()
        if (q.isEmpty()) return emptyList<Profile>() to emptyList()
        val people = runCatching { profileService.searchProfiles(q, 20) }.getOrDefault(emptyList())
        val posts = runCatching { postsService.searchPosts(q, 30) }.getOrDefault(emptyList())
        val rankedPeople = MatteryaSearchEngine.rankProfiles(people, q)
        val rankedPosts = MatteryaSearchEngine.rankContent(posts, q)
        return rankedPeople to rankedPosts
    }

    suspend fun loadProfileByUsername(username: String): Profile? =
        profileService.profileByUsername(username)

    suspend fun loadProfileById(userId: String): Profile? =
        profileService.profileById(userId)

    suspend fun loadPostsForAuthor(authorId: String, limit: Int = 25): List<CountryPost> =
        postsService.listForAuthor(authorId, limit)

    suspend fun browsePeople(limit: Int = 30, offset: Int = 0): List<Profile> =
        profileService.browseProfiles(limit, offset)

    // ── Edit profile (full save path) ─────────────────────────────────

    suspend fun saveEditProfile(
        displayName: String,
        username: String?,
        countryName: String?,
        countryCode: String?,
        cityName: String?,
        bio: String,
        avatarUrl: String? = null,
    ): Profile = appState.saveEditProfile(
        displayName = displayName,
        username = username,
        countryName = countryName,
        countryCode = countryCode,
        cityName = cityName,
        bio = bio,
        avatarUrl = avatarUrl,
    )

    suspend fun uploadAvatarAndApply(uri: Uri): Profile {
        val uploaded = mediaService.uploadAvatarFromUri(uri)
        return appState.applyAvatarUrl(uploaded.publicURL)
    }

    suspend fun detectAndApplyLocation() = appState.detectAndApplyLocation()

    suspend fun loadCountryFeedPosts(iso: String): List<CountryPost> =
        postsService.loadCountryFeedPosts(iso)
            .excludingMoments()
            .excludingSparks()

    suspend fun loadFollowingFeedPosts(): List<CountryPost> =
        postsService.loadFollowingFeed(limitPerAuthor = 6, maxAuthors = 32)
            .excludingMoments()
            .excludingSparks()

    suspend fun loadCountryNews(iso: String, limit: Int = 15) =
        com.matterya.matterya.data.news.NewsService().countryConflictUpdates(iso, limit)

    suspend fun loadCountryStats(iso: String) = profileService.countryStats(iso)

    suspend fun loadGlobalStats() = profileService.globalStats()

    suspend fun resolveHasHubsChannel(profile: Profile, posts: List<CountryPost>): Boolean {
        if (com.matterya.matterya.model.LivingChannelMarker.hasChannel(profile)) return true
        val channel = runCatching {
            com.matterya.matterya.data.channels.ChannelsService().channelByOwner(profile.userId)
        }.getOrNull()
        if (channel != null && channel.id.isNotBlank()) return true
        return posts.any { post ->
            !post.isReel && PlayPlatformBridge.isHubChannelUpload(post)
        }
    }
}
