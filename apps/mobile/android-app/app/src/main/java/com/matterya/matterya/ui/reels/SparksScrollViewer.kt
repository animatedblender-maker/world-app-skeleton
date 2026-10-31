package com.matterya.matterya.ui.reels

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.media.MediaUrlResolver
import com.matterya.matterya.data.media.SparkWarmPool
import com.matterya.matterya.data.posts.PostsService
import com.matterya.matterya.data.reels.ReelsRankingEngine
import com.matterya.matterya.data.reels.SparkDiscoveryEngine
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaCopy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * iOS `ReelsScrollViewer` — owns the endless Sparks queue.
 *
 * Instant seed → warm catalog append → deep `beginFreshSparksSession` expand
 * → keep ≥28 unplayed ahead. Append-only so the focused clip never remounts.
 */
@Composable
fun SparksScrollViewer(
    startingPost: CountryPost,
    seedPosts: List<CountryPost> = emptyList(),
    currentUserId: String? = null,
    currentProfile: Profile? = null,
    feedVideosMuted: Boolean = false,
    onFeedVideosMutedChange: (Boolean) -> Unit = {},
    isFollowing: (String) -> Boolean = { false },
    isPostSaved: (String) -> Boolean = { false },
    onBack: () -> Unit = {},
    onLike: (CountryPost) -> Unit = {},
    onSave: (CountryPost) -> Unit = {},
    onShare: (CountryPost) -> Unit = {},
    onOpenProfile: (CountryPost) -> Unit = {},
    onOpenPost: (CountryPost) -> Unit = {},
    onToggleFollow: (suspend (String) -> Unit)? = null,
) {
    val postsService = remember { PostsService() }
    val scope = rememberCoroutineScope()
    val warmPool = remember { SparkWarmPool.shared }

    val initial = remember(startingPost.id) {
        val seed = seedPosts.toMutableList()
        if (seed.none { it.id == startingPost.id }) seed.add(0, startingPost)
        if (seed.isEmpty()) seed.add(startingPost)
        seed.distinctBy { it.id }
    }

    var posts by remember { mutableStateOf(initial) }
    var activeIndex by remember {
        mutableIntStateOf(initial.indexOfFirst { it.id == startingPost.id }.coerceAtLeast(0))
    }
    var isExpanding by remember { mutableStateOf(false) }
    var loadMoreQueued by remember { mutableStateOf(false) }

    fun prepareWarm() {
        warmPool.prepare(posts, around = activeIndex, ahead = 14, behind = 2)
    }

    fun applyExpandedFeed(feed: List<CountryPost>, preserveId: String = "") {
        val seen = posts.map { it.id }.toMutableSet()
        val hasUnviewedIncoming = feed.any {
            it.id !in seen && !SparkDiscoveryEngine.isViewed(it.id)
        }
        val appended = mutableListOf<CountryPost>()
        for (p in feed) {
            if (!seen.add(p.id)) continue
            val eligible = ReelsRankingEngine.isSparkEligible(p) ||
                p.id == preserveId ||
                p.hasVideo ||
                p.playableVideoUrl != null
            if (!eligible) continue
            if (hasUnviewedIncoming &&
                SparkDiscoveryEngine.isViewed(p.id) &&
                p.id != preserveId
            ) {
                continue
            }
            appended.add(p)
        }
        if (appended.isEmpty()) return
        posts = posts + appended
    }

    fun seedFromWarmCatalogIfNeeded() {
        if (posts.size >= MIN_QUEUE_AHEAD) return
        val seen = posts.map { it.id }.toMutableSet()
        val warm = SparkDiscoveryEngine.rankForDiscovery(
            postsService.sparksCatalogSnapshot()
                .filter { ReelsRankingEngine.isSparkEligible(it) },
        )
        val toAppend = mutableListOf<CountryPost>()
        for (post in warm) {
            if (!seen.add(post.id)) continue
            val hasPath = MediaUrlResolver.videoUrl(post) != null ||
                !post.mediaUrl.isNullOrEmpty() ||
                post.hasVideo
            if (!hasPath) continue
            toAppend.add(post)
            if (posts.size + toAppend.size >= 96) break
        }
        if (toAppend.isNotEmpty()) posts = posts + toAppend
    }

    fun rotateQueueForEndless() {
        if (posts.size < 8) return
        val idx = activeIndex.coerceIn(0, posts.lastIndex)
        val live = posts[idx]
        val rest = (posts.take(idx) + posts.drop(idx + 1)).shuffled()
        posts = listOf(live) + rest
        activeIndex = 0
    }

    suspend fun loadMoreReels() {
        if (isExpanding) {
            loadMoreQueued = true
            return
        }
        isExpanding = true
        try {
            val existingIds = posts.map { it.id }.toSet()
            val bulk = BULK_BATCH_SIZE
            val catalog = withContext(Dispatchers.IO) {
                postsService.loadSparksDiscoveryCatalog(forceRefresh = false, deep = true)
            }
            val discover = withContext(Dispatchers.IO) {
                postsService.fetchDiscoverSparks(
                    limit = minOf(120, bulk + 20),
                    excluding = existingIds + SparkDiscoveryEngine.viewedIDList(500).toSet(),
                )
            }
            val remaining = SparkDiscoveryEngine.rankForDiscovery(
                (catalog + discover).filter {
                    it.id !in existingIds && ReelsRankingEngine.isSparkEligible(it)
                },
            )
            if (remaining.isNotEmpty()) {
                applyExpandedFeed(remaining.take(bulk))
                prepareWarm()
                return
            }
            if (posts.size >= 12) {
                rotateQueueForEndless()
                prepareWarm()
            }
        } finally {
            isExpanding = false
            if (loadMoreQueued) {
                loadMoreQueued = false
                loadMoreReels()
            }
        }
    }

    suspend fun ensureBulkQueueAhead(target: Int = MIN_QUEUE_AHEAD) {
        var passes = 0
        while (passes < 5) {
            passes++
            val remaining = maxOf(0, posts.size - activeIndex - 1)
            if (remaining >= target) return
            val before = posts.size
            loadMoreReels()
            if (posts.size > before) {
                prepareWarm()
                continue
            }
            if (posts.size >= 8) {
                rotateQueueForEndless()
                prepareWarm()
            }
            return
        }
    }

    suspend fun expandFeed() {
        if (isExpanding) {
            loadMoreQueued = true
            return
        }
        isExpanding = true
        try {
            val liveId = posts.getOrNull(activeIndex)?.id ?: startingPost.id
            val rankingAnchor = ReelsRankingEngine.resolvePlayerStart(
                posts.firstOrNull { it.id == liveId } ?: startingPost,
            )
            val liveIndexBefore = posts.indexOfFirst { it.id == liveId }.coerceAtLeast(0)
            val aheadBefore = maxOf(0, posts.size - liveIndexBefore - 1)

            val fresh = withContext(Dispatchers.IO) {
                postsService.beginFreshSparksSession(preferStart = rankingAnchor)
            }

            val keepId = posts.getOrNull(activeIndex)?.id ?: liveId
            if (aheadBefore >= 12 && posts.size >= 16) {
                applyExpandedFeed(fresh, preserveId = keepId)
                prepareWarm()
                return
            }

            val liveIndex = posts.indexOfFirst { it.id == keepId }.coerceAtLeast(0)
            val history = posts.take(liveIndex + 1)
            val seen = history.map { it.id }.toMutableSet()
            val upcoming = mutableListOf<CountryPost>()
            for (post in fresh) {
                if (!seen.add(post.id)) continue
                if (!ReelsRankingEngine.isSparkEligible(post) && post.id != keepId) continue
                val hasPath = MediaUrlResolver.videoUrl(post) != null ||
                    !post.mediaUrl.isNullOrEmpty() ||
                    post.hasVideo
                if (!hasPath) continue
                upcoming.add(post)
            }
            if (upcoming.isNotEmpty()) {
                val live = history.lastOrNull()
                posts = history + upcoming.filter { it.id != live?.id }
                activeIndex = posts.indexOfFirst { it.id == keepId }.coerceAtLeast(0)
            }
            prepareWarm()
        } finally {
            isExpanding = false
            if (loadMoreQueued) {
                loadMoreQueued = false
                loadMoreReels()
            }
        }
    }

    LaunchedEffect(Unit) {
        SparkDiscoveryEngine.beginNewBrowseSession()
        prepareWarm()
        seedFromWarmCatalogIfNeeded()
        prepareWarm()
        expandFeed()
        ensureBulkQueueAhead()
        prepareWarm()
    }

    LaunchedEffect(activeIndex) {
        posts.getOrNull(activeIndex)?.let { SparkDiscoveryEngine.markWatched(it.id) }
        prepareWarm()
        ensureBulkQueueAhead()
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        if (posts.isEmpty()) {
            Text(
                "No ${MatteryaCopy.sparks.lowercase()}",
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 14.sp,
                modifier = Modifier.align(Alignment.Center),
            )
        } else {
            ReelsView(
                posts = posts,
                isLoading = false,
                onBack = onBack,
                onLike = onLike,
                onSave = onSave,
                onShare = onShare,
                onComment = {},
                onOpenProfile = onOpenProfile,
                onOpenPost = onOpenPost,
                onToggleFollow = onToggleFollow,
                isFollowing = isFollowing,
                isPostSaved = isPostSaved,
                currentUserId = currentUserId,
                currentProfile = currentProfile,
                feedVideosMuted = feedVideosMuted,
                onFeedVideosMutedChange = onFeedVideosMutedChange,
                startIndex = activeIndex,
                showsOpenPostAction = false,
                showsProgressRail = false,
                bottomInsetDp = 28,
                useOverPlayerComments = true,
                onActiveIndexChange = { idx ->
                    if (idx != activeIndex) activeIndex = idx
                    if (idx >= posts.size - 6) {
                        scope.launch { loadMoreReels() }
                    }
                },
            )
        }
    }
}

private const val MIN_QUEUE_AHEAD = 28
private const val BULK_BATCH_SIZE = 80
