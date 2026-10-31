package com.matterya.matterya.viewmodel

import android.content.Context
import android.content.SharedPreferences
import com.matterya.matterya.data.anonymous.AnonymousService
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.messages.MessagesService
import com.matterya.matterya.model.AnonymousCreateCommentInput
import com.matterya.matterya.model.AnonymousCreatePostInput
import com.matterya.matterya.model.AnonymousCreateSpaceInput
import com.matterya.matterya.model.AnonymousError
import com.matterya.matterya.model.AnonymousFeedSort
import com.matterya.matterya.model.AnonymousNotification
import com.matterya.matterya.model.AnonymousPhase
import com.matterya.matterya.model.AnonymousPost
import com.matterya.matterya.model.AnonymousProfile
import com.matterya.matterya.model.AnonymousPublicProfilePayload
import com.matterya.matterya.model.AnonymousRoute
import com.matterya.matterya.model.AnonymousSearchResults
import com.matterya.matterya.model.AnonymousSession
import com.matterya.matterya.model.AnonymousSpace
import com.matterya.matterya.model.AnonymousSpaceAdmission
import com.matterya.matterya.model.AnonymousSpaceFilter
import com.matterya.matterya.model.AnonymousComment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.Instant
import kotlin.math.max
import kotlin.random.Random

/** Snapshot for Compose — mirrors iOS `AnonymousStore` observable fields. */
data class AnonymousUiState(
    val phase: AnonymousPhase = AnonymousPhase.Loading,
    val session: AnonymousSession = AnonymousSession.empty,
    val suggestedUsername: String = "",
    val isClaimingUsername: Boolean = false,
    val isAttesting: Boolean = false,
    val isRefreshing: Boolean = false,
    val showWildeEpigraph: Boolean = false,
    val spacesByFilter: Map<AnonymousSpaceFilter, List<AnonymousSpace>> = emptyMap(),
    val spacesLoading: Map<AnonymousSpaceFilter, Boolean> = emptyMap(),
    val activeSpaceFilter: AnonymousSpaceFilter = AnonymousSpaceFilter.ForYou,
    val feed: List<AnonymousPost> = emptyList(),
    val feedSort: AnonymousFeedSort = AnonymousFeedSort.ForYou,
    val feedLoading: Boolean = false,
    val feedLoadingMore: Boolean = false,
    val feedHasMore: Boolean = true,
    val inbox: List<AnonymousNotification> = emptyList(),
    val inboxLoading: Boolean = false,
    val notificationUnreadCount: Int = 0,
    val masqueradeMessageUnreadCount: Int = 0,
    val currentSpace: AnonymousSpace? = null,
    val spacePosts: List<AnonymousPost> = emptyList(),
    val spacePostsLoading: Boolean = false,
    val spacePostsLoadingMore: Boolean = false,
    val spacePostsHasMore: Boolean = true,
    val membershipLocal: Map<String, Boolean> = emptyMap(),
    val membershipBusyIds: Set<String> = emptySet(),
    val composerTitle: String = "",
    val composerBody: String = "",
    val publishEpoch: Int = 0,
    val navigationPath: List<AnonymousRoute> = emptyList(),
    val lastError: String? = null,
    val shouldToastLastError: Boolean = true,
    val searchResults: AnonymousSearchResults = AnonymousSearchResults(),
    val searchLoading: Boolean = false,
    val commentsByPostId: Map<String, List<AnonymousComment>> = emptyMap(),
    val commentsLoading: Map<String, Boolean> = emptyMap(),
) {
    val totalMasqueradeUnread: Int
        get() = notificationUnreadCount + masqueradeMessageUnreadCount

    val displayUsername: String
        get() = session.profile?.username?.takeIf { it.isNotBlank() }
            ?: suggestedUsername

    val spacesOnboardingCandidates: List<AnonymousSpace>
        get() {
            val seen = mutableSetOf<String>()
            val out = mutableListOf<AnonymousSpace>()
            val pools = listOf(
                spacesByFilter[AnonymousSpaceFilter.ForYou].orEmpty(),
                spacesByFilter[AnonymousSpaceFilter.Popular].orEmpty(),
                spacesByFilter[AnonymousSpaceFilter.Free].orEmpty(),
            )
            for (space in pools.flatten()) {
                if (space.isPaid) continue
                if (!seen.add(space.id)) continue
                out.add(space)
                if (out.size >= 24) break
            }
            return out
        }
}

/**
 * Masquerade state — mirrors iOS `AnonymousStore.swift`.
 */
class AnonymousStore private constructor(appContext: Context) {
    private val prefs: SharedPreferences =
        appContext.getSharedPreferences("matterya_anonymous", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val feedMutex = Mutex()

    private val _state = MutableStateFlow(AnonymousUiState())
    val state: StateFlow<AnonymousUiState> = _state.asStateFlow()

    private val postById = mutableMapOf<String, AnonymousPost>()
    private val sessionSeenFeedIds = mutableSetOf<String>()
    private var feedCursor: String? = null
    private var spacePostsCursor: String? = null
    private var allowFeedReplace = false
    private var lastBootstrapAtMs = 0L
    private var lastFeedReplaceAtMs = 0L
    private var feedLoadJob: Job? = null
    private var ownRecentPosts: List<AnonymousPost> = emptyList()

    private val softBootstrapIntervalMs = 90_000L
    private val feedReshuffleIntervalMs = 12_000L
    private val feedCacheMaxAgeMs = 60_000L

    init {
        loadCachedSession()
        loadCachedFeed()
        val wildeSeen = prefs.getBoolean(KEY_WILDE_SEEN, false)
        _state.update { it.copy(showWildeEpigraph = !wildeSeen) }
    }

    // MARK: - Navigation

    fun pushSpace(slug: String) {
        val trimmed = slug.trim()
        if (trimmed.isEmpty()) return
        val last = _state.value.navigationPath.lastOrNull()
        if (last is AnonymousRoute.Space && last.slug == trimmed) return
        _state.update { it.copy(navigationPath = it.navigationPath + AnonymousRoute.Space(trimmed)) }
    }

    fun pushPost(post: AnonymousPost) {
        val id = post.id.trim()
        if (id.isEmpty()) return
        postById[id] = post
        val last = _state.value.navigationPath.lastOrNull()
        if (last is AnonymousRoute.Post && last.id == id) return
        _state.update { it.copy(navigationPath = it.navigationPath + AnonymousRoute.Post(id)) }
    }

    fun pushPostId(id: String) {
        val trimmed = id.trim()
        if (trimmed.isEmpty()) return
        val last = _state.value.navigationPath.lastOrNull()
        if (last is AnonymousRoute.Post && last.id == trimmed) return
        _state.update { it.copy(navigationPath = it.navigationPath + AnonymousRoute.Post(trimmed)) }
    }

    fun pushProfile(username: String) {
        val trimmed = username.trim().trimStart('@')
        if (trimmed.isEmpty()) return
        if (trimmed.equals("matterya", ignoreCase = true)) return
        val last = _state.value.navigationPath.lastOrNull()
        if (last is AnonymousRoute.Profile && last.username.equals(trimmed, ignoreCase = true)) return
        _state.update { it.copy(navigationPath = it.navigationPath + AnonymousRoute.Profile(trimmed)) }
    }

    fun pushConversation(id: String) {
        val trimmed = id.trim()
        if (trimmed.isEmpty()) return
        val last = _state.value.navigationPath.lastOrNull()
        if (last is AnonymousRoute.Conversation && last.id == trimmed) return
        _state.update { s ->
            val filtered = s.navigationPath.filterNot { it is AnonymousRoute.Conversation }
            s.copy(navigationPath = filtered + AnonymousRoute.Conversation(trimmed))
        }
    }

    fun postForId(id: String): AnonymousPost? {
        val key = id.trim()
        if (key.isEmpty()) return null
        postById[key]?.let { return it }
        _state.value.feed.firstOrNull { it.id == key }?.let {
            postById[key] = it
            return it
        }
        _state.value.spacePosts.firstOrNull { it.id == key }?.let {
            postById[key] = it
            return it
        }
        return null
    }

    fun rememberPost(post: AnonymousPost) {
        val existing = postById[post.id]
            ?: _state.value.feed.firstOrNull { it.id == post.id }
            ?: _state.value.spacePosts.firstOrNull { it.id == post.id }
        val merged = mergePreservingMedia(post, existing)
        postById[merged.id] = merged
        _state.update { s ->
            s.copy(
                feed = s.feed.map { if (it.id == merged.id) mergePreservingMedia(merged, it) else it },
                spacePosts = s.spacePosts.map {
                    if (it.id == merged.id) mergePreservingMedia(merged, it) else it
                },
            )
        }
    }

    fun popNavigation() {
        _state.update { s ->
            if (s.navigationPath.isEmpty()) s
            else s.copy(navigationPath = s.navigationPath.dropLast(1))
        }
    }

    fun resetNavigation() {
        _state.update { s ->
            if (s.navigationPath.isEmpty()) s else s.copy(navigationPath = emptyList())
        }
    }

    // MARK: - Lifecycle

    suspend fun bootstrap() {
        val s = _state.value
        if (s.phase == AnonymousPhase.Loading) {
            applySession(s.session, animated = false)
        }
        val now = System.currentTimeMillis()
        if (s.phase == AnonymousPhase.Ready && s.feed.isNotEmpty() &&
            now - lastBootstrapAtMs < softBootstrapIntervalMs
        ) {
            reshuffleFeedOnOpen()
            return
        }
        refreshSession()
        lastBootstrapAtMs = System.currentTimeMillis()
        if (_state.value.phase == AnonymousPhase.Ready) {
            reshuffleFeedOnOpen()
        }
    }

    suspend fun refreshSession() {
        if (_state.value.isRefreshing) return
        _state.update { it.copy(isRefreshing = true) }
        try {
            val remote = AnonymousService.session()
            applySession(remote, animated = true)
            cacheSession(remote)
            if (_state.value.phase == AnonymousPhase.Ready) {
                loadFeed(force = _state.value.feed.isEmpty() || isFeedCacheStale())
                scope.launch { loadSpaces(filter = _state.value.activeSpaceFilter, force = false) }
            }
        } catch (err: AnonymousError) {
            handleGateError(err)
        } catch (e: Exception) {
            val session = _state.value.session
            if (session.profile != null) {
                _state.update { it.copy(phase = AnonymousPhase.Ready) }
                noteSoftNetworkError(AnonymousError.Network(e.message).message)
                loadFeed(force = false)
            } else if (_state.value.phase == AnonymousPhase.Loading) {
                _state.update {
                    it.copy(
                        phase = AnonymousPhase.Offline,
                        shouldToastLastError = false,
                        lastError = AnonymousError.Network(e.message).message,
                    )
                }
            } else {
                noteSoftNetworkError(AnonymousError.Network(e.message).message)
            }
        } finally {
            _state.update { it.copy(isRefreshing = false) }
        }
    }

    suspend fun attest() {
        if (_state.value.isAttesting) return
        _state.update { it.copy(isAttesting = true) }
        try {
            AnonymousService.attest()
            refreshSession()
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
            handleGateError(err)
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
        } finally {
            _state.update { it.copy(isAttesting = false) }
        }
    }

    suspend fun regenerateUsername() {
        try {
            val name = AnonymousService.suggestUsername()
            _state.update { it.copy(suggestedUsername = name) }
        } catch (_: Exception) {
            _state.update { it.copy(suggestedUsername = localSafeUsername()) }
        }
    }

    suspend fun claimUsername() {
        if (_state.value.isClaimingUsername) return
        val candidate = _state.value.suggestedUsername.trim()
        if (candidate.isEmpty()) return
        _state.update { it.copy(isClaimingUsername = true) }
        try {
            val profile = AnonymousService.claimProfile(username = candidate)
            prefs.edit().putString(KEY_PINNED_USERNAME, profile.username).apply()
            val next = _state.value.session.copy(
                profile = profile,
                suggestedUsername = profile.username,
                ageAttested = true,
            )
            applySession(next, animated = true)
            cacheSession(next)
            _state.update { it.copy(suggestedUsername = profile.username) }
            markWildeSeenIfReady()
            _state.update { it.copy(shouldToastLastError = false) }
            refreshSession()
            if (_state.value.session.profile == null) {
                applySession(next.copy(profile = profile), animated = false)
                cacheSession(next.copy(profile = profile))
            }
            when {
                !hasCompletedWelcomeLetter() ->
                    _state.update { it.copy(phase = AnonymousPhase.WelcomeLetter) }
                !hasCompletedSpacesOnboarding() -> {
                    _state.update { it.copy(phase = AnonymousPhase.PickSpaces) }
                    loadSpaces(AnonymousSpaceFilter.ForYou, force = true)
                    loadSpaces(AnonymousSpaceFilter.Popular, force = true)
                }
                else -> {
                    loadFeed(force = true)
                    loadSpaces(AnonymousSpaceFilter.Joined, force = true)
                }
            }
            _state.update { it.copy(lastError = null) }
        } catch (err: AnonymousError) {
            _state.update { it.copy(shouldToastLastError = true, lastError = err.message) }
            if (err is AnonymousError.UsernameTaken) regenerateUsername()
        } catch (e: Exception) {
            _state.update { it.copy(shouldToastLastError = true, lastError = e.message) }
        } finally {
            _state.update { it.copy(isClaimingUsername = false) }
        }
    }

    fun markWildeSeenIfReady() {
        val phase = _state.value.phase
        if (phase != AnonymousPhase.Ready &&
            phase != AnonymousPhase.WelcomeLetter &&
            phase != AnonymousPhase.PickSpaces &&
            _state.value.session.profile == null
        ) return
        prefs.edit().putBoolean(KEY_WILDE_SEEN, true).apply()
        _state.update { it.copy(showWildeEpigraph = false) }
    }

    fun hasCompletedWelcomeLetter(): Boolean = prefs.getBoolean(KEY_WELCOME_SEEN, false)

    fun hasCompletedSpacesOnboarding(): Boolean = prefs.getBoolean(KEY_SPACES_ONBOARDING, false)

    fun completeWelcomeLetter() {
        prefs.edit().putBoolean(KEY_WELCOME_SEEN, true).apply()
        if (!hasCompletedSpacesOnboarding()) {
            _state.update { it.copy(phase = AnonymousPhase.PickSpaces) }
            scope.launch {
                loadSpaces(AnonymousSpaceFilter.ForYou, force = true)
                loadSpaces(AnonymousSpaceFilter.Popular, force = true)
            }
        } else {
            completeSpacesOnboarding()
        }
    }

    fun completeSpacesOnboarding() {
        prefs.edit().putBoolean(KEY_SPACES_ONBOARDING, true).apply()
        _state.update { it.copy(phase = AnonymousPhase.Ready) }
        scope.launch {
            loadFeed(force = true)
            loadSpaces(AnonymousSpaceFilter.Joined, force = true)
            loadSpaces(AnonymousSpaceFilter.ForYou, force = false)
        }
    }

    // MARK: - Spaces

    suspend fun loadSpaces(filter: AnonymousSpaceFilter, force: Boolean = false) {
        val cached = _state.value.spacesByFilter[filter]
        if (!force && !cached.isNullOrEmpty()) return
        _state.update { it.copy(spacesLoading = it.spacesLoading + (filter to true)) }
        try {
            val page = AnonymousService.listSpaces(filter = filter)
            val membership = _state.value.membershipLocal
            val items = page.items.map { space ->
                membership[space.id]?.let { joined -> space.copy(isJoined = joined) } ?: space
            }
            _state.update {
                it.copy(spacesByFilter = it.spacesByFilter + (filter to items))
            }
        } catch (err: AnonymousError) {
            if (err is AnonymousError.PaidDisabled && filter == AnonymousSpaceFilter.Paid) {
                _state.update { it.copy(spacesByFilter = it.spacesByFilter + (filter to emptyList())) }
            } else if (cached.isNullOrEmpty()) {
                noteSoftNetworkError(err.message)
            }
        } catch (e: Exception) {
            if (cached.isNullOrEmpty()) noteSoftNetworkError(e.message)
        } finally {
            _state.update { it.copy(spacesLoading = it.spacesLoading + (filter to false)) }
        }
    }

    fun setActiveSpaceFilter(filter: AnonymousSpaceFilter) {
        _state.update { it.copy(activeSpaceFilter = filter) }
        scope.launch { loadSpaces(filter, force = false) }
    }

    suspend fun openSpace(slug: String) {
        val trimmed = slug.trim()
        if (trimmed.isEmpty()) return
        val needle = trimmed.lowercase()
        val known = findCachedSpace(trimmed, needle)
        if (known != null) {
            _state.update {
                it.copy(
                    currentSpace = applyingMembershipLocal(known),
                    spacePosts = emptyList(),
                    spacePostsHasMore = true,
                )
            }
            spacePostsCursor = null
        } else {
            _state.update {
                it.copy(spacePosts = emptyList(), spacePostsHasMore = true)
            }
            spacePostsCursor = null
        }
        _state.update { it.copy(spacePostsLoading = true) }
        try {
            val cached = _state.value.currentSpace
            if (cached != null &&
                (cached.slug == trimmed || cached.normalizedSlug == needle) &&
                cached.id.isNotEmpty()
            ) {
                val page = AnonymousService.listPosts(
                    spaceId = cached.id,
                    sort = AnonymousFeedSort.New,
                    limit = AnonymousService.spacePostsPageLimit,
                )
                scope.launch {
                    runCatching { AnonymousService.space(trimmed) }.getOrNull()?.let { fresh ->
                        _state.update { it.copy(currentSpace = applyingMembershipLocal(fresh)) }
                    }
                }
                page.items.forEach { postById[it.id] = it }
                val spaceId = _state.value.currentSpace?.id ?: cached.id
                val posts = mergeOwnRecentPosts(page.items).filter { it.spaceId == spaceId }
                spacePostsCursor = page.nextCursor
                _state.update {
                    it.copy(
                        spacePosts = posts,
                        spacePostsHasMore = page.nextCursor != null,
                    )
                }
                return
            }
            val space = AnonymousService.space(trimmed)
            _state.update { it.copy(currentSpace = applyingMembershipLocal(space)) }
            val page = AnonymousService.listPosts(
                spaceId = space.id,
                sort = AnonymousFeedSort.New,
                limit = AnonymousService.spacePostsPageLimit,
            )
            page.items.forEach { postById[it.id] = it }
            val posts = mergeOwnRecentPosts(page.items).filter { it.spaceId == space.id }
            spacePostsCursor = page.nextCursor
            _state.update {
                it.copy(
                    spacePosts = posts,
                    spacePostsHasMore = page.nextCursor != null,
                )
            }
        } catch (err: AnonymousError) {
            _state.update {
                it.copy(
                    lastError = err.message,
                    shouldToastLastError = it.currentSpace?.slug != trimmed,
                )
            }
        } catch (e: Exception) {
            _state.update {
                it.copy(
                    lastError = e.message,
                    shouldToastLastError = it.currentSpace?.slug != trimmed,
                )
            }
        } finally {
            _state.update { it.copy(spacePostsLoading = false) }
        }
    }

    suspend fun loadMoreSpacePosts() {
        val space = _state.value.currentSpace ?: return
        val s = _state.value
        if (s.spacePostsLoading || s.spacePostsLoadingMore) return
        if (!s.spacePostsHasMore) return
        val cursor = spacePostsCursor ?: return
        if (cursor.isEmpty()) return
        _state.update { it.copy(spacePostsLoadingMore = true) }
        try {
            val page = AnonymousService.listPosts(
                spaceId = space.id,
                cursor = cursor,
                sort = AnonymousFeedSort.New,
                limit = AnonymousService.spacePostsPageLimit,
            )
            val seen = s.spacePosts.map { it.id }.toMutableSet()
            val appended = mutableListOf<AnonymousPost>()
            for (item in page.items) {
                if (seen.add(item.id)) {
                    postById[item.id] = item
                    appended.add(item)
                }
            }
            spacePostsCursor = page.nextCursor
            _state.update {
                it.copy(
                    spacePosts = it.spacePosts + appended,
                    spacePostsHasMore = page.nextCursor != null && page.items.isNotEmpty(),
                )
            }
        } catch (_: Exception) {
            _state.update { it.copy(spacePostsHasMore = spacePostsCursor != null) }
        } finally {
            _state.update { it.copy(spacePostsLoadingMore = false) }
        }
    }

    fun isJoined(space: AnonymousSpace): Boolean {
        _state.value.membershipLocal[space.id]?.let { return it }
        return space.isJoined == true
    }

    fun isMembershipBusy(spaceId: String): Boolean =
        _state.value.membershipBusyIds.contains(spaceId)

    suspend fun joinSpace(space: AnonymousSpace): Boolean =
        ensureJoined(space, waitForServer = false)

    suspend fun joinCurrentSpace(): Boolean {
        val space = _state.value.currentSpace ?: return false
        return ensureJoined(space, waitForServer = false)
    }

    suspend fun ensureJoined(space: AnonymousSpace, waitForServer: Boolean = true): Boolean {
        if (isJoined(space)) return true
        if (space.isPaid) {
            _state.update { it.copy(lastError = AnonymousError.PaidDisabled.message) }
            return false
        }
        if (_state.value.membershipBusyIds.contains(space.id)) {
            if (!waitForServer) return isJoined(space)
            var waits = 0
            while (_state.value.membershipBusyIds.contains(space.id) && waits < 40) {
                delay(50)
                waits++
            }
            return isJoined(space)
        }
        applyMembershipOptimistic(space.id, space.slug, joined = true)
        _state.update { it.copy(membershipBusyIds = it.membershipBusyIds + space.id) }
        return if (waitForServer) {
            val ok = commitJoin(space.id, space.slug)
            _state.update { it.copy(membershipBusyIds = it.membershipBusyIds - space.id) }
            ok
        } else {
            scope.launch {
                commitJoin(space.id, space.slug)
                _state.update { it.copy(membershipBusyIds = it.membershipBusyIds - space.id) }
            }
            true
        }
    }

    fun leaveCurrentSpace() {
        val space = _state.value.currentSpace ?: return
        if (_state.value.membershipBusyIds.contains(space.id)) return
        if (!isJoined(space)) return
        applyMembershipOptimistic(space.id, space.slug, joined = false)
        _state.update { it.copy(membershipBusyIds = it.membershipBusyIds + space.id) }
        val spaceId = space.id
        val slug = space.slug
        scope.launch {
            try {
                AnonymousService.leave(spaceId)
                delay(800)
                loadSpaces(AnonymousSpaceFilter.Joined, force = true)
            } catch (err: AnonymousError) {
                applyMembershipOptimistic(spaceId, slug, joined = true)
                _state.update { it.copy(lastError = err.message) }
            } catch (e: Exception) {
                applyMembershipOptimistic(spaceId, slug, joined = true)
                _state.update { it.copy(lastError = e.message) }
            } finally {
                _state.update { it.copy(membershipBusyIds = it.membershipBusyIds - spaceId) }
            }
        }
    }

    suspend fun createSpace(input: AnonymousCreateSpaceInput): AnonymousSpace? {
        if (input.admission != AnonymousSpaceAdmission.Free.rawValue) {
            _state.update { it.copy(lastError = AnonymousError.PaidDisabled.message) }
            return null
        }
        return try {
            var space = AnonymousService.createSpace(input)
            space = space.copy(isJoined = true, isOwner = true)
            prependSpace(space)
            _state.update { it.copy(activeSpaceFilter = AnonymousSpaceFilter.Joined) }
            loadSpaces(AnonymousSpaceFilter.Newest, force = true)
            loadSpaces(AnonymousSpaceFilter.Joined, force = true)
            space
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
            null
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
            null
        }
    }

    // MARK: - Feed

    suspend fun loadFeed(force: Boolean = false) {
        feedMutex.withLock {
            if (!force && _state.value.feed.isNotEmpty() && !isFeedCacheStale()) return
            performLoadFeed(force || isFeedCacheStale())
        }
    }

    fun markFeedPostSeen(id: String) {
        val trimmed = id.trim()
        if (trimmed.isNotEmpty()) sessionSeenFeedIds.add(trimmed)
    }

    suspend fun reshuffleFeedOnOpen() {
        if (_state.value.feedLoading) return
        val due = _state.value.feed.isEmpty() ||
            isFeedCacheStale() ||
            System.currentTimeMillis() - lastFeedReplaceAtMs >= feedReshuffleIntervalMs
        if (!due) return
        allowFeedReplace = true
        try {
            loadFeed(force = true)
        } finally {
            allowFeedReplace = false
        }
    }

    suspend fun loadMoreFeed() {
        val s = _state.value
        if (s.feedLoading || s.feedLoadingMore) return
        if (s.feed.size >= AnonymousService.feedSoftCap) {
            val keep = s.feed.takeLast(90)
            val keepIds = keep.map { it.id }.toSet()
            postById.keys.retainAll(keepIds)
            _state.update { it.copy(feed = keep, feedHasMore = true) }
        }
        _state.update { it.copy(feedLoadingMore = true) }
        try {
            var hops = 0
            while (hops < 4) {
                hops++
                val cursor = feedCursor
                try {
                    val page = AnonymousService.feed(
                        sort = _state.value.feedSort,
                        cursor = cursor?.takeIf { it.isNotEmpty() },
                        limit = AnonymousService.feedPageLimit,
                    )
                    val seen = _state.value.feed.map { it.id }.toMutableSet()
                    val appended = mutableListOf<AnonymousPost>()
                    for (item in page.items) {
                        if (seen.add(item.id)) {
                            postById[item.id] = item
                            sessionSeenFeedIds.add(item.id)
                            appended.add(item)
                        }
                    }
                    feedCursor = page.nextCursor
                    if (appended.isNotEmpty()) {
                        _state.update {
                            it.copy(feed = it.feed + appended, feedHasMore = true)
                        }
                        cacheFeed(_state.value.feed, feedCursor)
                        return
                    }
                    if (page.nextCursor != null && page.nextCursor != cursor) {
                        feedCursor = page.nextCursor
                        continue
                    }
                    if (hops >= 2) {
                        sessionSeenFeedIds.clear()
                        sessionSeenFeedIds.addAll(_state.value.feed.takeLast(24).map { it.id })
                        feedCursor = null
                    }
                } catch (_: Exception) {
                    _state.update { it.copy(feedHasMore = true) }
                    return
                }
            }
            _state.update { it.copy(feedHasMore = true) }
            cacheFeed(_state.value.feed, feedCursor)
        } finally {
            _state.update { it.copy(feedLoadingMore = false) }
        }
    }

    suspend fun refreshFeed() {
        _state.value.feed.take(60).forEach { sessionSeenFeedIds.add(it.id) }
        allowFeedReplace = true
        try {
            loadFeed(force = true)
        } finally {
            allowFeedReplace = false
        }
    }

    // MARK: - Inbox / search / comments

    suspend fun loadInbox(force: Boolean = false) {
        if (!force && _state.value.inbox.isNotEmpty()) return
        _state.update { it.copy(inboxLoading = true) }
        try {
            val page = AnonymousService.notifications()
            _state.update {
                it.copy(
                    inbox = page.items,
                    notificationUnreadCount = max(
                        page.unreadCount,
                        page.items.count { n -> n.isUnread },
                    ),
                )
            }
        } catch (err: AnonymousError) {
            _state.update {
                it.copy(
                    lastError = err.message,
                    inbox = if (it.inbox.isEmpty()) emptyList() else it.inbox,
                )
            }
        } catch (e: Exception) {
            _state.update {
                it.copy(
                    lastError = e.message,
                    inbox = if (it.inbox.isEmpty()) emptyList() else it.inbox,
                )
            }
        } finally {
            _state.update { it.copy(inboxLoading = false) }
        }
    }

    suspend fun markNotificationRead(item: AnonymousNotification) {
        if (!item.isUnread) return
        val now = Instant.now().toString()
        _state.update { s ->
            val inbox = s.inbox.map {
                if (it.id == item.id) it.copy(readAt = now) else it
            }
            s.copy(
                inbox = inbox,
                notificationUnreadCount = max(0, inbox.count { it.isUnread }),
            )
        }
        runCatching { AnonymousService.markNotificationRead(item.id) }
    }

    suspend fun markAllNotificationsRead() {
        val now = Instant.now().toString()
        _state.update { s ->
            s.copy(
                inbox = s.inbox.map { if (it.readAt == null) it.copy(readAt = now) else it },
                notificationUnreadCount = 0,
            )
        }
        runCatching { AnonymousService.markAllNotificationsRead() }
    }

    /** Badge for Masquerade Inbox DM threads (official Matterya peer only). */
    suspend fun refreshMasqueradeMessageUnread() {
        try {
            val page = MessagesService.shared.listConversations(limit = 40, inbox = "masquerade")
            val me = AuthService.instance.currentUser?.id
            val unread = if (me.isNullOrBlank()) {
                0
            } else {
                page.count { it.hasUnread(me) }
            }
            _state.update { it.copy(masqueradeMessageUnreadCount = unread) }
        } catch (_: Exception) {
            // Keep last known count — badge must not clear on a flaky inbox probe.
        }
    }

    suspend fun search(query: String) {
        val q = query.trim()
        if (q.isEmpty()) {
            _state.update { it.copy(searchResults = AnonymousSearchResults(), searchLoading = false) }
            return
        }
        _state.update { it.copy(searchLoading = true) }
        try {
            val results = AnonymousService.search(q)
            _state.update { it.copy(searchResults = results) }
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
        } finally {
            _state.update { it.copy(searchLoading = false) }
        }
    }

    suspend fun loadComments(postId: String, force: Boolean = false) {
        if (!force && _state.value.commentsByPostId.containsKey(postId)) return
        _state.update { it.copy(commentsLoading = it.commentsLoading + (postId to true)) }
        try {
            val page = AnonymousService.listComments(postId)
            _state.update {
                it.copy(commentsByPostId = it.commentsByPostId + (postId to page.items))
            }
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
        } finally {
            _state.update { it.copy(commentsLoading = it.commentsLoading + (postId to false)) }
        }
    }

    suspend fun createComment(postId: String, body: String, parentId: String? = null): AnonymousComment? {
        val trimmed = body.trim()
        if (trimmed.isEmpty()) return null
        return try {
            val comment = AnonymousService.createComment(
                postId,
                AnonymousCreateCommentInput(body = trimmed, parentCommentId = parentId),
            )
            _state.update { s ->
                val existing = s.commentsByPostId[postId].orEmpty()
                s.copy(commentsByPostId = s.commentsByPostId + (postId to (existing + comment)))
            }
            comment
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
            null
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
            null
        }
    }

    suspend fun fetchPublicProfile(username: String): AnonymousPublicProfilePayload? =
        try {
            AnonymousService.publicProfile(username)
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
            null
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
            null
        }

    suspend fun loadAuthorPosts(username: String): List<AnonymousPost> =
        try {
            val page = AnonymousService.authorPosts(username)
            page.items.forEach { postById[it.id] = it }
            page.items
        } catch (_: Exception) {
            emptyList()
        }

    suspend fun fetchPost(id: String): AnonymousPost? =
        try {
            val post = AnonymousService.getPost(id)
            rememberPost(post)
            post
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
            null
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
            null
        }

    // MARK: - Publish / vote / report

    fun setComposerTitle(value: String) {
        _state.update { it.copy(composerTitle = value) }
    }

    fun setComposerBody(value: String) {
        _state.update { it.copy(composerBody = value) }
    }

    suspend fun publishPost(
        spaceId: String,
        mediaType: String? = null,
        mediaURL: String? = null,
        thumbURL: String? = null,
    ): AnonymousPost? {
        val title = _state.value.composerTitle.trim()
        val body = _state.value.composerBody.trim()
        val hasMedia = !mediaURL.isNullOrBlank()
        if (body.isEmpty() && title.isEmpty() && !hasMedia) {
            _state.update { it.copy(lastError = "Write something or attach a photo/video.") }
            return null
        }
        val space = _state.value.currentSpace
        if (space != null && space.id == spaceId) {
            ensureJoined(space, waitForServer = true)
        }
        return try {
            val post = AnonymousService.createPost(
                spaceId,
                AnonymousCreatePostInput(
                    title = title.ifEmpty { null },
                    body = body,
                    mediaType = mediaType,
                    mediaURL = mediaURL,
                    thumbURL = thumbURL,
                ),
            )
            postById[post.id] = post
            ownRecentPosts = listOf(post) + ownRecentPosts.take(19)
            _state.update {
                it.copy(
                    feed = listOf(post) + it.feed,
                    spacePosts = if (it.currentSpace?.id == spaceId) {
                        listOf(post) + it.spacePosts
                    } else it.spacePosts,
                    composerTitle = "",
                    composerBody = "",
                    publishEpoch = it.publishEpoch + 1,
                )
            }
            cacheFeed(_state.value.feed, feedCursor)
            post
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
            null
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
            null
        }
    }

    suspend fun vote(post: AnonymousPost, value: Int): AnonymousPost? {
        val nextValue = if (post.myVote == value) 0 else value
        val delta = nextValue - (post.myVote ?: 0)
        val optimistic = post.copy(
            myVote = nextValue,
            score = (post.score ?: 0) + delta,
        )
        rememberPost(optimistic)
        return try {
            val result = AnonymousService.vote("post", post.id, nextValue)
            val updated = optimistic.copy(
                myVote = result.value ?: nextValue,
                score = result.score ?: optimistic.score,
            )
            rememberPost(updated)
            updated
        } catch (err: AnonymousError) {
            rememberPost(post)
            _state.update { it.copy(lastError = err.message) }
            null
        } catch (e: Exception) {
            rememberPost(post)
            _state.update { it.copy(lastError = e.message) }
            null
        }
    }

    suspend fun voteComment(comment: AnonymousComment, value: Int): AnonymousComment? {
        val nextValue = if (comment.myVote == value) 0 else value
        return try {
            val result = AnonymousService.vote("comment", comment.id, nextValue)
            comment.copy(
                myVote = result.value ?: nextValue,
                score = result.score ?: ((comment.score ?: 0) + (nextValue - (comment.myVote ?: 0))),
            )
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
            null
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
            null
        }
    }

    suspend fun report(targetType: String, targetId: String, reason: String) {
        try {
            AnonymousService.report(targetType, targetId, reason)
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
        }
    }

    suspend fun block(profileId: String): Boolean =
        try {
            AnonymousService.block(profileId)
            true
        } catch (err: AnonymousError) {
            _state.update { it.copy(lastError = err.message) }
            false
        } catch (e: Exception) {
            _state.update { it.copy(lastError = e.message) }
            false
        }

    fun consumeError(): String? {
        val msg = _state.value.lastError
        _state.update { it.copy(lastError = null) }
        return msg
    }

    // MARK: - Session helpers

    private fun applySession(remote: AnonymousSession, animated: Boolean) {
        val pinned = prefs.getString(KEY_PINNED_USERNAME, null)
        var session = remote
        if (pinned != null && session.profile == null) {
            // Keep prior profile if thin payload.
            session = session.copy(profile = _state.value.session.profile)
        }
        val suggested = session.suggestedUsername
            ?: session.profile?.username
            ?: _state.value.suggestedUsername
        val phase = resolvePhase(session)
        _state.update {
            it.copy(
                session = session,
                suggestedUsername = suggested,
                phase = phase,
            )
        }
        if (phase == AnonymousPhase.NeedUsername && suggested.isBlank()) {
            scope.launch { regenerateUsername() }
        }
    }

    private fun resolvePhase(session: AnonymousSession): AnonymousPhase {
        if (session.suspended) return AnonymousPhase.Suspended
        if (session.birthdateMissing || session.gateCode == "under_18") {
            return if (session.gateCode == "under_18" || !session.eligibleAdult) {
                AnonymousPhase.GatedUnder18
            } else {
                AnonymousPhase.GatedUnder18
            }
        }
        if (!session.eligibleAdult) return AnonymousPhase.GatedUnder18
        if (!session.ageAttested) return AnonymousPhase.NeedAttest
        if (session.profile == null) return AnonymousPhase.NeedUsername
        if (!hasCompletedWelcomeLetter()) return AnonymousPhase.WelcomeLetter
        if (!hasCompletedSpacesOnboarding()) return AnonymousPhase.PickSpaces
        return AnonymousPhase.Ready
    }

    private fun handleGateError(err: AnonymousError) {
        when (err) {
            is AnonymousError.Under18 ->
                _state.update { it.copy(phase = AnonymousPhase.GatedUnder18, lastError = err.message) }
            is AnonymousError.Unattested ->
                _state.update { it.copy(phase = AnonymousPhase.NeedAttest, lastError = err.message) }
            is AnonymousError.NoProfile ->
                _state.update { it.copy(phase = AnonymousPhase.NeedUsername, lastError = err.message) }
            is AnonymousError.Suspended ->
                _state.update { it.copy(phase = AnonymousPhase.Suspended, lastError = err.message) }
            is AnonymousError.Network, is AnonymousError.NotFound, is AnonymousError.Server -> {
                if (_state.value.session.profile != null) {
                    _state.update { it.copy(phase = AnonymousPhase.Ready) }
                    noteSoftNetworkError(err.message)
                } else {
                    _state.update {
                        it.copy(
                            phase = AnonymousPhase.Offline,
                            shouldToastLastError = false,
                            lastError = err.message,
                        )
                    }
                }
            }
            else -> _state.update { it.copy(lastError = err.message) }
        }
    }

    private fun noteSoftNetworkError(message: String?) {
        if (message.isNullOrBlank()) return
        _state.update { it.copy(shouldToastLastError = false, lastError = message) }
    }

    private suspend fun performLoadFeed(force: Boolean) {
        if (!force && _state.value.feed.isNotEmpty() && !isFeedCacheStale()) return
        val showSpinner = _state.value.feed.isEmpty()
        if (showSpinner) _state.update { it.copy(feedLoading = true) }
        try {
            val page = fetchFeedPageWithRetry()
            page.items.forEach { postById[it.id] = it }
            val lastHead = prefs.getStringSet(KEY_LAST_FEED_HEAD, emptySet()).orEmpty()
            val suppress = sessionSeenFeedIds + lastHead
            val fresh = page.items.filter { it.id !in suppress }
            val preferred = when {
                fresh.size >= minOf(6, max(1, page.items.size / 2)) -> fresh
                fresh.isNotEmpty() -> {
                    val seen = fresh.map { it.id }.toMutableSet()
                    val mixed = fresh.toMutableList()
                    for (item in page.items) {
                        if (item.id !in sessionSeenFeedIds && seen.add(item.id)) {
                            mixed.add(item)
                            if (mixed.size >= page.items.size) break
                        }
                    }
                    if (mixed.isEmpty()) page.items else mixed
                }
                else -> {
                    val head = page.items.filter { it.id in lastHead }
                    val rest = page.items.filter { it.id !in lastHead }
                    rest + head
                }
            }
            var merged = mergeOwnRecentPosts(preferred)
            if (merged.size < 6 && _state.value.feed.size > merged.size) {
                val incomingIds = merged.map { it.id }.toSet()
                val keep = _state.value.feed.filter {
                    it.id !in incomingIds && it.id !in sessionSeenFeedIds
                }.ifEmpty {
                    _state.value.feed.filter { it.id !in incomingIds }
                }
                merged = mergeOwnRecentPosts((merged + keep).take(48))
            }
            merged.forEach { sessionSeenFeedIds.add(it.id) }
            rememberFeedHead(merged)
            feedCursor = page.nextCursor
            _state.update {
                it.copy(feed = merged, feedHasMore = true)
            }
            lastFeedReplaceAtMs = System.currentTimeMillis()
            cacheFeed(merged, feedCursor)
            if (_state.value.lastError != null && !_state.value.shouldToastLastError) {
                _state.update { it.copy(lastError = null) }
            }
        } catch (err: AnonymousError) {
            if (_state.value.feed.isEmpty()) noteSoftNetworkError(err.message)
        } catch (e: Exception) {
            if (_state.value.feed.isEmpty()) noteSoftNetworkError(e.message)
        } finally {
            if (showSpinner) _state.update { it.copy(feedLoading = false) }
        }
    }

    private suspend fun fetchFeedPageWithRetry() =
        try {
            AnonymousService.feed(sort = _state.value.feedSort, limit = AnonymousService.feedPageLimit)
        } catch (err: AnonymousError) {
            if (err !is AnonymousError.Network) throw err
            delay(400)
            AnonymousService.feed(sort = _state.value.feedSort, limit = AnonymousService.feedPageLimit)
        } catch (_: Exception) {
            delay(400)
            AnonymousService.feed(sort = _state.value.feedSort, limit = AnonymousService.feedPageLimit)
        }

    private suspend fun commitJoin(spaceId: String, slug: String): Boolean =
        try {
            AnonymousService.join(spaceId)
            scope.launch {
                delay(800)
                loadSpaces(AnonymousSpaceFilter.Joined, force = true)
            }
            true
        } catch (err: AnonymousError) {
            applyMembershipOptimistic(spaceId, slug, joined = false)
            _state.update { it.copy(lastError = err.message) }
            false
        } catch (e: Exception) {
            applyMembershipOptimistic(spaceId, slug, joined = false)
            _state.update { it.copy(lastError = e.message) }
            false
        }

    private fun applyMembershipOptimistic(spaceId: String, slug: String, joined: Boolean) {
        _state.update { s ->
            val current = s.currentSpace
            val updatedCurrent = if (current?.id == spaceId || current?.slug == slug) {
                current.copy(isJoined = joined)
            } else current
            val filters = listOf(s.activeSpaceFilter, AnonymousSpaceFilter.Joined)
            var spaces = s.spacesByFilter
            for (key in filters.distinct()) {
                val list = spaces[key]?.toMutableList() ?: continue
                val idx = list.indexOfFirst { it.id == spaceId || it.slug == slug }
                if (idx >= 0) {
                    val was = list[idx].isJoined == true
                    var item = list[idx].copy(isJoined = joined)
                    if (was != joined) {
                        item = item.copy(
                            memberCount = ((item.memberCount ?: 0) + if (joined) 1 else -1)
                                .coerceAtLeast(0),
                        )
                    }
                    list[idx] = item
                    spaces = spaces + (key to list)
                }
            }
            s.copy(
                membershipLocal = s.membershipLocal + (spaceId to joined),
                currentSpace = updatedCurrent,
                spacesByFilter = spaces,
            )
        }
    }

    private fun applyingMembershipLocal(space: AnonymousSpace): AnonymousSpace {
        val joined = _state.value.membershipLocal[space.id] ?: return space
        return space.copy(isJoined = joined)
    }

    private fun findCachedSpace(trimmed: String, needle: String): AnonymousSpace? {
        fun matches(space: AnonymousSpace) =
            space.slug == trimmed || space.normalizedSlug == needle
        val map = _state.value.spacesByFilter
        return map[AnonymousSpaceFilter.ForYou]?.firstOrNull(::matches)
            ?: map[AnonymousSpaceFilter.Popular]?.firstOrNull(::matches)
            ?: map[AnonymousSpaceFilter.Joined]?.firstOrNull(::matches)
            ?: map.values.flatten().firstOrNull(::matches)
    }

    private fun prependSpace(space: AnonymousSpace) {
        val filters = listOf(
            AnonymousSpaceFilter.Newest,
            AnonymousSpaceFilter.Joined,
            AnonymousSpaceFilter.ForYou,
            AnonymousSpaceFilter.Popular,
            AnonymousSpaceFilter.Free,
        )
        _state.update { s ->
            var map = s.spacesByFilter
            for (filter in filters) {
                val list = (map[filter].orEmpty()).filterNot {
                    it.id == space.id || it.slug == space.slug
                }.toMutableList()
                list.add(0, space)
                map = map + (filter to list)
            }
            s.copy(spacesByFilter = map)
        }
    }

    private fun mergeOwnRecentPosts(incoming: List<AnonymousPost>): List<AnonymousPost> {
        if (ownRecentPosts.isEmpty()) return incoming
        val seen = incoming.map { it.id }.toMutableSet()
        val head = ownRecentPosts.filter { seen.add(it.id) }
        return head + incoming
    }

    private fun mergePreservingMedia(incoming: AnonymousPost, existing: AnonymousPost?): AnonymousPost {
        if (existing == null) return incoming
        var out = incoming
        if (out.mediaURL.isNullOrEmpty() && !existing.mediaURL.isNullOrEmpty()) {
            out = out.copy(mediaURL = existing.mediaURL)
        }
        if (out.thumbURL.isNullOrEmpty() && !existing.thumbURL.isNullOrEmpty()) {
            out = out.copy(thumbURL = existing.thumbURL)
        }
        if (out.mediaType == null && existing.mediaType != null) {
            out = out.copy(mediaType = existing.mediaType)
        }
        return out
    }

    private fun rememberFeedHead(posts: List<AnonymousPost>) {
        prefs.edit()
            .putStringSet(KEY_LAST_FEED_HEAD, posts.take(8).map { it.id }.toSet())
            .apply()
    }

    private fun isFeedCacheStale(): Boolean {
        val saved = prefs.getLong(KEY_FEED_SAVED_AT, 0L)
        if (saved <= 0L) return _state.value.feed.isNotEmpty()
        return System.currentTimeMillis() - saved > feedCacheMaxAgeMs
    }

    private fun cacheSession(session: AnonymousSession) {
        // Lightweight: store profile username/id only.
        prefs.edit()
            .putBoolean("eligible", session.eligibleAdult)
            .putBoolean("attested", session.ageAttested)
            .putBoolean("birthdate_missing", session.birthdateMissing)
            .putBoolean("suspended", session.suspended)
            .putString("profile_id", session.profile?.id)
            .putString("profile_username", session.profile?.username)
            .putString("suggested", session.suggestedUsername)
            .apply()
    }

    private fun loadCachedSession() {
        val username = prefs.getString("profile_username", null)
        val id = prefs.getString("profile_id", null)
        val profile = if (username != null && id != null) {
            AnonymousProfile(id = id, username = username)
        } else null
        val session = AnonymousSession(
            eligibleAdult = prefs.getBoolean("eligible", false),
            ageAttested = prefs.getBoolean("attested", false),
            birthdateMissing = prefs.getBoolean("birthdate_missing", false),
            suspended = prefs.getBoolean("suspended", false),
            profile = profile,
            suggestedUsername = prefs.getString("suggested", null)
                ?: prefs.getString(KEY_PINNED_USERNAME, null),
        )
        if (profile != null && session.eligibleAdult && session.ageAttested) {
            applySession(session, animated = false)
        } else if (profile != null || session.ageAttested || session.eligibleAdult) {
            applySession(session, animated = false)
        }
    }

    private fun cacheFeed(feed: List<AnonymousPost>, cursor: String?) {
        prefs.edit()
            .putString(KEY_FEED_IDS, feed.take(48).joinToString(",") { it.id })
            .putString(KEY_FEED_CURSOR, cursor)
            .putLong(KEY_FEED_SAVED_AT, System.currentTimeMillis())
            .apply()
    }

    private fun loadCachedFeed() {
        feedCursor = prefs.getString(KEY_FEED_CURSOR, null)
    }

    companion object {
        private const val KEY_WILDE_SEEN = "wildeSeen.v1"
        private const val KEY_WELCOME_SEEN = "welcomeLetterSeen.v1"
        private const val KEY_SPACES_ONBOARDING = "spacesOnboardingSeen.v1"
        private const val KEY_PINNED_USERNAME = "pinnedUsername.v1"
        private const val KEY_LAST_FEED_HEAD = "feed.lastHead.v1"
        private const val KEY_FEED_IDS = "feed.ids.v6"
        private const val KEY_FEED_CURSOR = "feed.cursor.v6"
        private const val KEY_FEED_SAVED_AT = "feed.savedAt.v6"
        @Volatile private var instance: AnonymousStore? = null

        fun get(context: Context): AnonymousStore {
            return instance ?: synchronized(this) {
                instance ?: AnonymousStore(context.applicationContext).also { instance = it }
            }
        }

        val shared: AnonymousStore
            get() = instance ?: error("AnonymousStore.get(context) must be called first")

        fun localSafeUsername(): String {
            val adjectives = listOf("quiet", "silver", "velvet", "hidden", "amber", "misty", "copper", "lunar")
            val nouns = listOf("mask", "lantern", "echo", "harbor", "cipher", "mirror", "ember", "veil")
            val a = adjectives.random(Random)
            val n = nouns.random(Random)
            val num = Random.nextInt(10, 99)
            return "${a}_${n}_$num"
        }
    }
}
