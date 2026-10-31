package com.matterya.matterya.data.posts

import android.content.Context
import android.graphics.Bitmap
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.cache.ContentCache
import com.matterya.matterya.data.cache.ContentCacheKey
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.reels.SparkDiscoveryEngine
import com.matterya.matterya.data.social.BlockService
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.excludingMoments
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
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

data class FeedUploadPlaceholder(
    val id: String,
    val caption: String,
    val previewBitmap: Bitmap? = null,
    val progress: Double = 0.02,
    val phaseLabel: String = "Preparing",
    val isHub: Boolean = false,
    val failedMessage: String? = null,
) {
    val progressText: String
        get() {
            failedMessage?.let { return it }
            val pct = (min(1.0, max(0.0, progress)) * 100).roundToInt()
            return "$phaseLabel · $pct%"
        }
}

data class HomeFeedState(
    val posts: List<CountryPost> = emptyList(),
    val windowLimit: Int = 8,
    val isBootstrapping: Boolean = true,
    val isRefreshing: Boolean = false,
    val isLoadingMore: Boolean = false,
    val hasMore: Boolean = true,
    val errorMessage: String? = null,
    val feedSessionId: String = UUID.randomUUID().toString(),
    val didPaint: Boolean = false,
    val pendingUploads: List<FeedUploadPlaceholder> = emptyList(),
) {
    val displayedPosts: List<CountryPost> get() = posts.take(windowLimit)
    val showsSkeleton: Boolean get() = isBootstrapping && posts.isEmpty()
}

/** iOS `HomeFeedStore.swift` — cache → first paint → prefetch → SWR. */
class HomeFeedStore private constructor(
    private val context: Context,
    private val postsService: PostsService = PostsService(),
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val cache get() = ContentCache.get(context)
    private val blocks get() = BlockService.get(context)

    private val _state = MutableStateFlow(HomeFeedState())
    val state: StateFlow<HomeFeedState> = _state.asStateFlow()

    private var nextCursor: String? = null
    private var generation = 0
    private var pendingLoadMoreTask: Job? = null

    private val pageSize = 12
    private val windowPageSize = 8
    private val firstWindow = 8
    private val prefetchRatio = 0.65

    val displayedPosts: List<CountryPost> get() = _state.value.displayedPosts
    val posts: List<CountryPost> get() = _state.value.posts

    fun beginFreshSession() {
        generation += 1
        val gen = generation
        scope.launch {
            _state.update {
                it.copy(
                    errorMessage = null,
                    feedSessionId = UUID.randomUUID().toString(),
                    isRefreshing = true,
                    hasMore = true,
                )
            }
            nextCursor = null
            try {
                var pool = _state.value.posts
                if (pool.isEmpty()) {
                    pool = liveOnlyPosts(cache.posts(ContentCacheKey.HomeFeed) ?: emptyList())
                }
                // iOS forHomeFeed: keep spark *shares* + playable sparks; drop pure non-share sparks only via liveOnly.
                pool = liveOnlyPosts(
                    blocks.filterPosts(pool.excludingMoments()),
                )
                if (pool.isNotEmpty()) {
                    val fresh = postsService.chronologicalNewestFirst(pool)
                    applyPosts(fresh.take(48), replace = true, sessionId = _state.value.feedSessionId)
                    _state.update { it.copy(isBootstrapping = false, didPaint = true) }
                } else {
                    _state.update { it.copy(isBootstrapping = true) }
                }

                val live = liveOnlyPosts(postsService.fetchFirstPaintHomePosts(48))
                if (gen != generation) return@launch
                val realBatch = liveOnlyPosts(live + _state.value.posts)
                val merged = postsService.chronologicalNewestFirst(realBatch)
                val capped = merged.take(min(merged.size, 48))
                if (capped.isNotEmpty()) {
                    applyPosts(capped, replace = true, sessionId = _state.value.feedSessionId)
                    cache.setPosts(_state.value.posts, ContentCacheKey.HomeFeed)
                    _state.update { it.copy(didPaint = true, hasMore = true) }
                } else if (_state.value.posts.isEmpty()) {
                    applyPosts(emptyList(), replace = true, sessionId = _state.value.feedSessionId)
                    cache.invalidate(ContentCacheKey.HomeFeed)
                }
            } finally {
                _state.update { it.copy(isBootstrapping = false, isRefreshing = false) }
            }
        }
    }

    fun bootstrap(forceRefresh: Boolean = false) {
        generation += 1
        val gen = generation
        scope.launch {
            _state.update { it.copy(errorMessage = null) }
            if (forceRefresh) {
                _state.update { it.copy(isRefreshing = true) }
                try {
                    hardRefresh(gen)
                } finally {
                    _state.update { it.copy(isRefreshing = false) }
                }
                return@launch
            }
            if (_state.value.posts.isEmpty()) {
                val cached = cache.posts(ContentCacheKey.HomeFeed)
                if (!cached.isNullOrEmpty()) {
                    val clean = liveOnlyPosts(cached)
                    if (clean.isEmpty()) {
                        cache.invalidate(ContentCacheKey.HomeFeed)
                    } else {
                        applyPosts(
                            postsService.chronologicalNewestFirst(
                                blocks.filterPosts(clean.excludingMoments()),
                            ),
                            replace = true,
                            sessionId = _state.value.feedSessionId,
                        )
                        _state.update { it.copy(isBootstrapping = false, didPaint = true) }
                    }
                }
            }
            val live = liveOnlyPosts(postsService.fetchFirstPaintHomePosts(40))
            if (gen != generation) return@launch
            val existingLive = _state.value.posts.filter { !it.isStory }
            val realBatch = liveOnlyPosts(live + existingLive)
            val merged = postsService.chronologicalNewestFirst(realBatch)
            val capped = merged.take(min(merged.size, 48))
            if (capped.isNotEmpty()) {
                applyPosts(capped, replace = true, sessionId = _state.value.feedSessionId)
                cache.setPosts(_state.value.posts, ContentCacheKey.HomeFeed)
                _state.update { it.copy(didPaint = true, hasMore = true) }
            } else if (_state.value.posts.isEmpty()) {
                applyPosts(emptyList(), replace = true, sessionId = _state.value.feedSessionId)
                cache.invalidate(ContentCacheKey.HomeFeed)
            }
            _state.update { it.copy(isBootstrapping = false) }
        }
    }

    fun onRowAppear(post: CountryPost, isFlinging: Boolean = false) {
        val displayed = _state.value.displayedPosts
        val index = displayed.indexOfFirst { it.id == post.id }
        if (index < 0) return
        val growBy = if (isFlinging) windowPageSize * 3 else windowPageSize
        val growWhenWithin = if (isFlinging) 8 else 3
        val s = _state.value
        if (index >= displayed.size - growWhenWithin && s.windowLimit < s.posts.size) {
            _state.update {
                it.copy(
                    windowLimit = min(it.posts.size, it.windowLimit + growBy),
                    hasMore = min(it.posts.size, it.windowLimit + growBy) < it.posts.size,
                )
            }
        }
        if (isFlinging) return
        val threshold = max(0, (max(s.posts.size, 1) * prefetchRatio).toInt() - 1)
        if (index >= threshold && s.windowLimit >= s.posts.size - windowPageSize) {
            requestLoadMore()
        }
    }

    fun requestLoadMore() {
        val s = _state.value
        if (s.windowLimit < s.posts.size) {
            _state.update {
                it.copy(
                    windowLimit = min(it.posts.size, it.windowLimit + windowPageSize),
                    hasMore = min(it.posts.size, it.windowLimit + windowPageSize) < it.posts.size,
                )
            }
            return
        }
        if (!s.hasMore || s.isLoadingMore || s.isBootstrapping) return
        val gen = generation
        pendingLoadMoreTask?.cancel()
        pendingLoadMoreTask = scope.launch { loadMore(gen) }
    }

    fun applyLocalUpdate(post: CountryPost) {
        _state.update { st ->
            val idx = st.posts.indexOfFirst { it.id == post.id }
            if (idx < 0) st
            else st.copy(posts = st.posts.toMutableList().also { it[idx] = post })
        }
    }

    fun insertNewPost(post: CountryPost) {
        if (post.isStory) return
        _state.update { st ->
            val without = st.posts.filter { it.id != post.id }
            st.copy(
                posts = listOf(post) + without,
                windowLimit = max(st.windowLimit, firstWindow),
            )
        }
        cache.setPosts(_state.value.posts, ContentCacheKey.HomeFeed)
    }

    fun beginVideoUpload(caption: String, preview: Bitmap?, isHub: Boolean): String {
        val id = "upload-${UUID.randomUUID()}"
        val placeholder = FeedUploadPlaceholder(
            id = id,
            caption = caption,
            previewBitmap = preview,
            progress = 0.02,
            phaseLabel = "Preparing",
            isHub = isHub,
        )
        _state.update {
            it.copy(
                pendingUploads = listOf(placeholder) + it.pendingUploads,
                windowLimit = max(it.windowLimit, firstWindow),
            )
        }
        return id
    }

    fun updateVideoUpload(id: String, progress: Double, phaseLabel: String) {
        _state.update { st ->
            st.copy(
                pendingUploads = st.pendingUploads.map {
                    if (it.id == id) it.copy(
                        progress = min(1.0, max(0.0, progress)),
                        phaseLabel = phaseLabel,
                        failedMessage = null,
                    ) else it
                },
            )
        }
    }

    fun completeVideoUpload(id: String, post: CountryPost) {
        _state.update { it.copy(pendingUploads = it.pendingUploads.filter { p -> p.id != id }) }
        insertNewPost(post)
    }

    fun failVideoUpload(id: String, message: String) {
        _state.update { st ->
            st.copy(
                pendingUploads = st.pendingUploads.map {
                    if (it.id == id) it.copy(failedMessage = message, phaseLabel = "Failed") else it
                },
            )
        }
        scope.launch {
            delay(3_500)
            dismissUpload(id)
        }
    }

    fun dismissUpload(id: String) {
        _state.update { it.copy(pendingUploads = it.pendingUploads.filter { p -> p.id != id }) }
    }

    fun removePost(id: String) {
        _state.update { it.copy(posts = it.posts.filter { p -> p.id != id }) }
    }

    private suspend fun hardRefresh(gen: Int) {
        val sessionId = UUID.randomUUID().toString()
        nextCursor = null
        _state.update { it.copy(feedSessionId = sessionId, hasMore = true) }
        val live = liveOnlyPosts(postsService.fetchNetworkHomePosts(60))
        if (gen != generation) return
        val filtered = postsService.chronologicalNewestFirst(live)
        applyPosts(filtered, replace = true, sessionId = sessionId)
        nextCursor = cursorFrom(filtered.lastOrNull())
        _state.update {
            it.copy(
                hasMore = filtered.size >= pageSize || it.windowLimit < it.posts.size,
                didPaint = it.posts.isNotEmpty(),
            )
        }
        if (filtered.isNotEmpty()) cache.setPosts(_state.value.posts, ContentCacheKey.HomeFeed)
        else cache.invalidate(ContentCacheKey.HomeFeed)
    }

    private suspend fun loadMore(gen: Int) {
        val s = _state.value
        if (s.windowLimit < s.posts.size) {
            _state.update {
                it.copy(
                    windowLimit = min(it.posts.size, it.windowLimit + windowPageSize),
                    hasMore = min(it.posts.size, it.windowLimit + windowPageSize) < it.posts.size,
                )
            }
            return
        }
        if (!s.hasMore) return
        _state.update { it.copy(isLoadingMore = true) }
        try {
            val page = postsService.loadHomeFeedPage(limit = pageSize, cursor = nextCursor)
            if (gen != generation) return
            if (page.items.isEmpty()) {
                _state.update { it.copy(hasMore = it.windowLimit < it.posts.size) }
                return
            }
            val seen = _state.value.posts.map { it.id }.toMutableSet()
            val appended = page.items.filter { seen.add(it.id) }
            if (appended.isEmpty()) {
                nextCursor = page.nextCursor
                _state.update {
                    it.copy(hasMore = page.nextCursor != null && page.nextCursor != nextCursor)
                }
                return
            }
            val ordered = postsService.chronologicalNewestFirst(appended)
            _state.update { st ->
                val seenIds = st.posts.map { it.id }.toMutableSet()
                val extra = ordered.filter { seenIds.add(it.id) }
                st.copy(posts = st.posts + extra)
            }
            nextCursor = page.nextCursor
            _state.update {
                it.copy(hasMore = page.nextCursor != null || it.windowLimit < it.posts.size)
            }
            cache.setPosts(_state.value.posts, ContentCacheKey.HomeFeed)
        } finally {
            _state.update { it.copy(isLoadingMore = false) }
        }
    }

    private fun applyPosts(next: List<CountryPost>, replace: Boolean, sessionId: String) {
        // Always unique by id — Compose LazyColumn keys require it.
        val unique = next.distinctBy { it.id }
        // iOS sessionHomeFeedOrder: unviewed first (follows need async IDs — applied when available).
        val ordered = try {
            val me = runCatching { AuthService.instance.currentUser?.id }.getOrNull()
            val seed = sessionId.hashCode().toLong() and 0x7fff_ffffL
            SparkDiscoveryEngine.sessionHomeFeedOrder(
                posts = unique,
                followingIds = emptySet(), // filled by feed path when follow set is warm
                myUserId = me,
                sessionSeed = seed,
            )
        } catch (_: Throwable) {
            unique
        }
        _state.update {
            it.copy(
                feedSessionId = sessionId,
                posts = ordered,
                windowLimit = if (replace) min(firstWindow, max(ordered.size, 0)) else it.windowLimit,
                hasMore = if (ordered.isNotEmpty()) {
                    (if (replace) min(firstWindow, max(ordered.size, 0)) else it.windowLimit) < ordered.size ||
                        ordered.size >= pageSize
                } else it.hasMore,
            )
        }
        if (ordered.isNotEmpty()) nextCursor = cursorFrom(ordered.lastOrNull())
    }

    private fun liveOnlyPosts(posts: List<CountryPost>): List<CountryPost> =
        posts.filter { post ->
            if (post.authorId.startsWith("user_")) return@filter false
            if (post.id.startsWith("post_") || post.id.startsWith("demo_")) return@filter false
            if (post.id.startsWith("ia_") || post.id.startsWith("hub_")) return@filter false
            if (post.isStory) return@filter false
            if (post.isHubSeedVideo) return@filter false
            if (!AppConfig.archiveContentEnabled) {
                if (post.isArchiveSparkSource) return@filter false
                if (PlayPlatformBridge.isArchiveCatalogMedia(post)) return@filter false
            }
            true
        }

    companion object {
        fun cursorFrom(post: CountryPost?): String? {
            if (post == null) return null
            if (post.createdAt.isNotEmpty()) return post.createdAt
            return null
        }

        @Volatile private var instance: HomeFeedStore? = null
        fun get(context: Context): HomeFeedStore =
            instance ?: synchronized(this) {
                instance ?: HomeFeedStore(context.applicationContext).also { instance = it }
            }
    }
}
