package com.matterya.matterya.ui.hubs

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.cache.ContentCache
import com.matterya.matterya.data.cache.ContentCacheKey
import com.matterya.matterya.data.hubs.HubVideoSeedService
import com.matterya.matterya.data.hubs.YouTubeCatalogService
import com.matterya.matterya.data.hubs.YouTubeHomeFilter
import com.matterya.matterya.data.media.ImageCache
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.data.posts.PostsService
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.HubsHorizontalShelf
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.theme.PlayBrandMark
import com.matterya.matterya.theme.YouTubeMediaLayout
import com.matterya.matterya.ui.components.UnreadDot
import com.matterya.matterya.ui.components.VideoThumbnailView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class HubsVibeRail(
    val slug: String,
    val title: String,
    val posts: List<CountryPost>,
)

private data class HubsMoreRail(
    val id: String,
    val title: String,
    val posts: List<CountryPost>,
)

/**
 * Matterya Hubs home — Netflix-style hero + horizontal rails (iOS `YouTubeAppView`).
 * Categories are rows, not chips. Sparks strip lives on Feed, not here.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YouTubeAppView(
    /** Seed from feed strips so first frame is never blank. */
    seedVideos: List<CountryPost> = emptyList(),
    seedSparks: List<CountryPost> = emptyList(),
    seedContinueWatching: List<CountryPost> = emptyList(),
    followingIds: Set<String> = emptySet(),
    viewerCountry: String? = null,
    currentUserId: String? = null,
    /** Bumps when user re-selects Hubs tab (iOS hubsFreshSessionToken). */
    hubsFreshSessionToken: Int = 0,
    notificationsUnread: Int = 0,
    onSearch: () -> Unit = {},
    onNotifications: () -> Unit = {},
    onOpenVideo: (CountryPost) -> Unit = {},
    onOpenSpark: (CountryPost) -> Unit = {},
    onOpenHubsHome: () -> Unit = {},
    onOpenLibrary: () -> Unit = {},
    miniPlayerBottomInset: Boolean = false,
) {
    @Suppress("UNUSED_VARIABLE")
    val _unusedSparks = seedSparks
    @Suppress("UNUSED_VARIABLE")
    val _unusedViewer = viewerCountry
    @Suppress("UNUSED_VARIABLE")
    val _unusedOpenSpark = onOpenSpark

    val context = LocalContext.current
    val catalog = remember { YouTubeCatalogService.get(context) }
    val postsService = remember { PostsService() }
    val contentCache = remember { ContentCache.get(context) }
    val scope = rememberCoroutineScope()

    var allVideos by remember { mutableStateOf(seedVideos) }
    var continueWatching by remember { mutableStateOf(seedContinueWatching) }
    var homeVideos by remember { mutableStateOf<List<CountryPost>>(emptyList()) }
    var isLoading by remember { mutableStateOf(allVideos.isEmpty()) }
    var isRefreshing by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var homeListEpoch by remember { mutableIntStateOf(0) }
    var hubsRailsDense by remember { mutableStateOf(false) }

    var cachedVibeRails by remember { mutableStateOf<List<HubsVibeRail>>(emptyList()) }
    var cachedMoreWatchRails by remember { mutableStateOf<List<HubsMoreRail>>(emptyList()) }
    var cachedBecauseYouWatched by remember { mutableStateOf<HubsMoreRail?>(null) }
    var cachedPeopleRail by remember { mutableStateOf<List<CountryPost>>(emptyList()) }

    val railCardCount = 15
    val railCardWidth = 168.dp
    val peopleRailCardWidth = 180.dp

    fun pureShuffle(items: List<CountryPost>): List<CountryPost> =
        if (items.size <= 1) items else items.shuffled()

    fun hubsRailMediaKey(post: CountryPost): String {
        val url = post.playableVideoUrl
            ?: post.mediaUrl
            ?: post.mediaPayload?.primaryUrl
        if (!url.isNullOrBlank()) {
            val bare = url.substringBefore('?').lowercase()
            return "media:$bare"
        }
        return "id:${post.id.lowercase()}"
    }

    fun rebuildContinue(shuffle: Boolean) {
        val history = catalog.historyVideos(allVideos).filter { !it.isReel }
        val historyOrFallback = history.ifEmpty {
            allVideos.filter { PlayPlatformBridge.isHubsForYouLongForm(it) }
                .filter { catalog.playbackPosition(it.id) >= 1.0 }
        }
        val seed = (if (shuffle) pureShuffle(historyOrFallback) else historyOrFallback)
            .distinctBy { it.id }
        // Pad Continue toward ~15 unique media (iOS padContinueRail).
        if (seed.size >= railCardCount) {
            continueWatching = seed.take(railCardCount)
            return
        }
        val seenIds = seed.map { it.id }.toMutableSet()
        val seenMedia = seed.map { hubsRailMediaKey(it) }.toMutableSet()
        val out = seed.toMutableList()
        val filler = allVideos.filter {
            PlayPlatformBridge.isHubsForYouLongForm(it) || (it.hasVideo && !it.isReel)
        }
        for (post in filler) {
            if (out.size >= railCardCount) break
            if (post.id in seenIds) continue
            val key = hubsRailMediaKey(post)
            if (key in seenMedia) continue
            seenIds.add(post.id)
            seenMedia.add(key)
            out.add(post)
        }
        continueWatching = out.take(railCardCount)
    }

    fun rebuildHomeLists(shuffle: Boolean, remount: Boolean) {
        var home = catalog.rankForYouBySlugs(
            videos = allVideos,
            followingIds = followingIds,
            myUserId = currentUserId,
            sessionSeed = if (shuffle) System.currentTimeMillis() else hubsFreshSessionToken.toLong(),
            focusSlug = null,
        )
        if (home.isEmpty()) {
            home = allVideos.filter { PlayPlatformBridge.isHubsForYouLongForm(it) }
        }
        homeVideos = home.distinctBy { it.id }.take(2200)
        if (remount) homeListEpoch++
    }

    fun rebuildCachedHubsRails(dense: Boolean) {
        val hero = continueWatching.firstOrNull()
            ?: homeVideos.firstOrNull()
            ?: allVideos.firstOrNull { PlayPlatformBridge.isHubsForYouLongForm(it) }
        val ranked = homeVideos
        val railN = railCardCount
        val minRail = if (dense) railN else minOf(10, railN)
        val vibeCount = if (dense) 3 else 2
        val moreRows = if (dense) 2 else 1

        val buckets = linkedMapOf<String, MutableList<CountryPost>>()
        val mediaKeys = mutableMapOf<String, String>()
        fun mediaKey(post: CountryPost): String =
            mediaKeys.getOrPut(post.id) { hubsRailMediaKey(post) }
        val bucketSeenMedia = mutableMapOf<String, MutableSet<String>>()
        for (post in ranked) {
            if (!(PlayPlatformBridge.isHubsForYouLongForm(post) || (post.hasVideo && !post.isReel))) continue
            val slug = catalog.parentHubSlug(post)
            val key = mediaKey(post)
            val seen = bucketSeenMedia.getOrPut(slug) { mutableSetOf() }
            if (!seen.add(key)) continue
            val list = buckets.getOrPut(slug) { mutableListOf() }
            if (list.size < railN * 2) list.add(post)
        }

        val claimedIds = mutableSetOf<String>()
        val claimedMedia = mutableSetOf<String>()
        hero?.let {
            claimedIds.add(it.id)
            claimedMedia.add(mediaKey(it))
        }
        for (post in continueWatching.take(railN)) {
            claimedIds.add(post.id)
            claimedMedia.add(mediaKey(post))
        }

        fun claim(posts: List<CountryPost>, limit: Int): List<CountryPost> {
            val out = mutableListOf<CountryPost>()
            for (post in posts) {
                if (post.id in claimedIds) continue
                val key = mediaKey(post)
                if (key in claimedMedia) continue
                claimedIds.add(post.id)
                claimedMedia.add(key)
                out.add(post)
                if (out.size >= limit) break
            }
            return out
        }

        fun padToRailN(seed: List<CountryPost>): List<CountryPost> {
            if (seed.size >= railN) return seed.take(railN)
            val out = seed.toMutableList()
            val filler = ranked.filter {
                it.id !in claimedIds && mediaKey(it) !in claimedMedia
            }
            out.addAll(claim(filler, railN - out.size))
            return out
        }

        // Because you watched — dense only; same-slug, ≥15 unique or skip.
        cachedBecauseYouWatched = if (dense) {
            val seed = continueWatching.firstOrNull()
            if (seed != null) {
                claimedIds.add(seed.id)
                claimedMedia.add(mediaKey(seed))
                val seedSlug = catalog.parentHubSlug(seed)
                val related = (buckets[seedSlug] ?: emptyList()).filter { it.id != seed.id }
                var becausePosts = claim(related, railN)
                if (becausePosts.size < railN && becausePosts.size >= maxOf(4, minRail - 4)) {
                    becausePosts = padToRailN(becausePosts)
                }
                if (becausePosts.size >= minRail) {
                    val raw = (seed.displayHeadline ?: seed.displayExcerpt).trim()
                        .replace('\n', ' ')
                        .replace(Regex("\\s+"), " ")
                    val title = when {
                        raw.isEmpty() -> "Because you watched"
                        raw.length <= 42 -> "Because you watched $raw"
                        else -> "Because you watched ${raw.take(42).trim()}…"
                    }
                    HubsMoreRail(
                        id = "because-${seed.id}",
                        title = title,
                        posts = becausePosts.take(railN),
                    )
                } else {
                    for (post in becausePosts) {
                        claimedIds.remove(post.id)
                        claimedMedia.remove(mediaKey(post))
                    }
                    null
                }
            } else null
        } else null

        var slugOrder = HubVideoSeedService.HUB_ORDER.toMutableList()
        val extras = buckets.keys.filter { it !in slugOrder }.sorted()
        slugOrder.addAll(extras)

        val vibe = mutableListOf<HubsVibeRail>()
        for (slug in slugOrder) {
            if (vibe.size >= vibeCount) break
            val seed = buckets[slug] ?: emptyList()
            var posts = claim(seed, railN)
            if (posts.size < railN && posts.size >= maxOf(4, minRail - 4)) {
                posts = padToRailN(posts)
            }
            if (posts.size < minRail) {
                for (post in posts) {
                    claimedIds.remove(post.id)
                    claimedMedia.remove(mediaKey(post))
                }
                continue
            }
            val title = YouTubeHomeFilter.entries
                .firstOrNull { it.hubSlug == slug }
                ?.title
                ?: slug.replaceFirstChar { it.uppercase() }
            vibe.add(HubsVibeRail(slug = slug, title = title, posts = posts.take(railN)))
        }
        cachedVibeRails = vibe

        val peopleCandidates = ranked.filter {
            it.id !in claimedIds && mediaKey(it) !in claimedMedia
        }
        cachedPeopleRail = padToRailN(claim(peopleCandidates, railN)).take(railN)

        val rest = ranked.filter {
            it.id !in claimedIds && mediaKey(it) !in claimedMedia
        }
        val fillerTitles = listOf(
            "Fresh uploads", "Keep browsing", "More to watch", "Popular now",
            "Still more", "Worth another look", "Deep cuts", "Browse all",
        )
        val more = mutableListOf<HubsMoreRail>()
        var offset = 0
        var row = 0
        val moreFloor = if (dense) railN else maxOf(6, minRail)
        while (offset < rest.size && row < moreRows) {
            val window = rest.subList(offset, minOf(offset + railN * 2, rest.size))
            var slice = claim(window, railN)
            if (slice.size < railN && slice.size >= moreFloor) {
                slice = padToRailN(slice)
            }
            offset += railN
            if (slice.size < moreFloor) break
            more.add(
                HubsMoreRail(
                    id = "more-$row",
                    title = fillerTitles[minOf(row, fillerTitles.lastIndex)],
                    posts = slice.take(railN),
                ),
            )
            row++
        }
        cachedMoreWatchRails = more
    }

    fun refreshHubsVisitShuffle(remount: Boolean = true) {
        hubsRailsDense = false
        rebuildHomeLists(shuffle = true, remount = remount)
        rebuildContinue(shuffle = true)
        rebuildCachedHubsRails(dense = false)
    }

    suspend fun loadCatalog(forceRefresh: Boolean) {
        if (allVideos.isEmpty() || forceRefresh) {
            val cached = contentCache.posts(ContentCacheKey.LivingVideos).orEmpty()
            val session = postsService.hubsSessionCatalog
            val seed = when {
                session.isNotEmpty() -> session
                cached.isNotEmpty() -> cached
                seedVideos.isNotEmpty() -> seedVideos
                else -> emptyList()
            }
            if (seed.isNotEmpty()) {
                allVideos = seed.distinctBy { it.id }
                catalog.bindToUser(currentUserId)
                refreshHubsVisitShuffle(remount = true)
                isLoading = false
            }
        }

        try {
            val loaded = withContext(Dispatchers.IO) {
                postsService.loadPlayCatalog(forceRefresh = forceRefresh)
            }
            if (loaded.isNotEmpty()) {
                allVideos = loaded.distinctBy { it.id }
                contentCache.setPosts(
                    loaded.filter { !it.isReel },
                    ContentCacheKey.LivingVideos,
                )
                postsService.rememberHubsSessionCatalog(loaded)
                catalog.bindToUser(currentUserId)
                refreshHubsVisitShuffle(remount = true)
                errorMessage = null
            } else if (allVideos.isEmpty()) {
                errorMessage = MatteryaCopy.hubsUnavailable
            }
        } catch (e: Exception) {
            if (allVideos.isEmpty()) {
                errorMessage = e.message ?: MatteryaCopy.hubsUnavailable
            }
        } finally {
            isLoading = false
            isRefreshing = false
        }
    }

    LaunchedEffect(Unit) {
        catalog.bindToUser(currentUserId)
        if (seedVideos.isNotEmpty()) {
            allVideos = seedVideos.distinctBy { it.id }
            refreshHubsVisitShuffle(remount = true)
            isLoading = false
        }
        loadCatalog(forceRefresh = false)
    }

    LaunchedEffect(hubsFreshSessionToken) {
        if (hubsFreshSessionToken <= 0) return@LaunchedEffect
        if (allVideos.isNotEmpty()) {
            refreshHubsVisitShuffle(remount = true)
        }
        val longFormCount = allVideos.count { !it.isReel && it.hasVideo }
        if (longFormCount < 8) {
            loadCatalog(forceRefresh = false)
        }
    }

    // Densify rails after first paint (iOS scheduleHubsDensifyIfNeeded ~1.2–2.8s).
    LaunchedEffect(homeListEpoch, homeVideos.size) {
        if (homeVideos.isEmpty() || hubsRailsDense) return@LaunchedEffect
        delay(1_400)
        hubsRailsDense = true
        rebuildCachedHubsRails(dense = true)
        ImageCache.shared.prefetchPostThumbnails(
            (continueWatching + cachedVibeRails.flatMap { it.posts } + cachedPeopleRail)
                .distinctBy { it.id }
                .take(18),
            maxPixelSize = YouTubeMediaLayout.hubsListThumbMaxPixel,
            aggressive = false,
        )
    }

    val bottomPad = if (miniPlayerBottomInset) 68.dp else 24.dp
    val heroPost = continueWatching.firstOrNull()
        ?: homeVideos.firstOrNull()
        ?: allVideos.firstOrNull { PlayPlatformBridge.isHubsForYouLongForm(it) }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        HubsTopBar(
            onSearch = onSearch,
            onNotifications = onNotifications,
            notificationsUnread = notificationsUnread,
            onLibrary = onOpenLibrary,
            onBrandTap = onOpenHubsHome,
        )

        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                scope.launch { loadCatalog(forceRefresh = true) }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            when {
                isLoading && homeVideos.isEmpty() && continueWatching.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(color = MatteryaColors.ink)
                            Spacer(Modifier.height(12.dp))
                            Text(
                                MatteryaCopy.loadingHubs,
                                color = MatteryaColors.inkMuted,
                                fontSize = 14.sp,
                            )
                        }
                    }
                }
                errorMessage != null && homeVideos.isEmpty() && continueWatching.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            errorMessage ?: MatteryaCopy.hubsUnavailable,
                            color = MatteryaColors.danger,
                            modifier = Modifier.padding(24.dp),
                        )
                    }
                }
                homeVideos.isEmpty() && continueWatching.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            MatteryaCopy.hubsPublishHint,
                            color = MatteryaColors.inkMuted,
                            modifier = Modifier.padding(24.dp),
                            fontSize = 14.sp,
                        )
                    }
                }
                else -> {
                    key(homeListEpoch) {
                        LazyColumn(
                            Modifier.fillMaxSize(),
                            verticalArrangement = Arrangement.spacedBy(20.dp),
                        ) {
                            if (heroPost != null) {
                                item(key = "hero") {
                                    HubsHeroBillboard(
                                        post = heroPost,
                                        onOpen = { onOpenVideo(heroPost) },
                                    )
                                }
                            }
                            if (continueWatching.isNotEmpty()) {
                                item(key = "continue") {
                                    HubsHorizontalShelf(
                                        title = MatteryaCopy.continueWatching,
                                        posts = continueWatching.take(railCardCount),
                                        onOpen = onOpenVideo,
                                        cardWidth = railCardWidth,
                                        showsMetadata = true,
                                        endless = true,
                                    )
                                }
                            }
                            cachedBecauseYouWatched?.takeIf { it.posts.isNotEmpty() }?.let { because ->
                                item(key = because.id) {
                                    HubsHorizontalShelf(
                                        title = because.title,
                                        posts = because.posts,
                                        onOpen = onOpenVideo,
                                        cardWidth = railCardWidth,
                                        showsMetadata = true,
                                        endless = true,
                                    )
                                }
                            }
                            if (cachedPeopleRail.isNotEmpty()) {
                                item(key = "people") {
                                    HubsHorizontalShelf(
                                        title = MatteryaCopy.fromPeopleLikeYou,
                                        posts = cachedPeopleRail,
                                        onOpen = onOpenVideo,
                                        cardWidth = peopleRailCardWidth,
                                        showsMetadata = true,
                                        endless = true,
                                    )
                                }
                            }
                            items(cachedVibeRails, key = { it.slug }) { rail ->
                                HubsHorizontalShelf(
                                    title = rail.title,
                                    posts = rail.posts,
                                    onOpen = onOpenVideo,
                                    cardWidth = railCardWidth,
                                    showsMetadata = true,
                                    endless = true,
                                )
                            }
                            items(cachedMoreWatchRails, key = { it.id }) { rail ->
                                HubsHorizontalShelf(
                                    title = rail.title,
                                    posts = rail.posts,
                                    onOpen = onOpenVideo,
                                    cardWidth = railCardWidth,
                                    showsMetadata = true,
                                    endless = true,
                                )
                            }
                            item(key = "bottom-pad") { Spacer(Modifier.height(bottomPad)) }
                        }
                    }
                }
            }
        }
    }
}

/** iOS `hubsHeroBillboard` — cinema featured card. */
@Composable
private fun HubsHeroBillboard(
    post: CountryPost,
    onOpen: () -> Unit,
) {
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MatteryaDimens.pagePadding)
            .clip(RoundedCornerShape(22.dp))
            .clickable(onClick = onOpen),
    ) {
        val heroH: Dp = minOf(320.dp, maxOf(220.dp, maxWidth * 0.72f))
        Box(
            Modifier
                .fillMaxWidth()
                .height(heroH)
                .clipToBounds()
                .background(Color.Black),
        ) {
            VideoThumbnailView(
                post = post,
                maxLogicalPx = 720,
                showsPlayIcon = false,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
            Box(
                Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(
                                Color.Transparent,
                                MatteryaColors.ink.copy(alpha = 0.08f),
                                MatteryaColors.ink.copy(alpha = 0.55f),
                                MatteryaColors.ink.copy(alpha = 0.92f),
                            ),
                        ),
                    ),
            )
            Column(
                Modifier
                    .align(Alignment.BottomStart)
                    .padding(22.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    MatteryaCopy.peoplesCinema,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.2.sp,
                    color = MatteryaColors.paper.copy(alpha = 0.78f),
                )
                Text(
                    post.displayHeadline
                        ?: post.displayExcerpt.ifEmpty { MatteryaCopy.watchNow },
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = MatteryaColors.paper,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(
                        Modifier
                            .clip(RoundedCornerShape(percent = 50))
                            .background(MatteryaColors.paper)
                            .padding(horizontal = 18.dp, vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.PlayArrow,
                            contentDescription = null,
                            tint = MatteryaColors.ink,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            MatteryaCopy.play,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = MatteryaColors.ink,
                        )
                    }
                    val name = post.authorDisplayName.trim()
                    if (name.isNotEmpty()) {
                        Text(
                            name,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            color = MatteryaColors.paper.copy(alpha = 0.9f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun HubsTopBar(
    onSearch: () -> Unit,
    onNotifications: () -> Unit,
    notificationsUnread: Int = 0,
    onLibrary: () -> Unit = {},
    onBrandTap: () -> Unit = {},
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface.copy(alpha = 0.92f))
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            MatteryaCopy.library,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.ink,
            modifier = Modifier
                .clip(RoundedCornerShape(percent = 50))
                .background(MatteryaColors.matteDeep)
                .clickable(onClick = onLibrary)
                .padding(horizontal = 12.dp, vertical = 8.dp),
        )
        PlayBrandMark(
            compact = true,
            onClick = onBrandTap,
            modifier = Modifier.weight(1f),
        )
        IconButton(onClick = onSearch, modifier = Modifier.size(40.dp)) {
            Icon(Icons.Default.Search, contentDescription = MatteryaCopy.searchHubs, tint = MatteryaColors.ink)
        }
        Box {
            IconButton(onClick = onNotifications, modifier = Modifier.size(40.dp)) {
                Icon(
                    Icons.Default.NotificationsNone,
                    contentDescription = MatteryaCopy.notifications,
                    tint = MatteryaColors.ink,
                )
            }
            if (notificationsUnread > 0) {
                UnreadDot(
                    size = 7.dp,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 8.dp, end = 8.dp),
                )
            }
        }
    }
}

/**
 * Hubs tab entry — loads full play catalog (not just feed strip).
 * Mirrors iOS `MatteryaHubsView` → `YouTubeAppView`.
 */
@Composable
fun MatteryaHubsView(
    seedVideos: List<CountryPost> = emptyList(),
    seedSparks: List<CountryPost> = emptyList(),
    seedContinueWatching: List<CountryPost> = emptyList(),
    followingIds: Set<String> = emptySet(),
    viewerCountry: String? = null,
    currentUserId: String? = null,
    hubsFreshSessionToken: Int = 0,
    notificationsUnread: Int = 0,
    onSearch: () -> Unit = {},
    onNotifications: () -> Unit = {},
    onOpenVideo: (CountryPost) -> Unit = {},
    onOpenSpark: (CountryPost) -> Unit = {},
    onOpenLibrary: () -> Unit = {},
    miniPlayerBottomInset: Boolean = false,
) = YouTubeAppView(
    seedVideos = seedVideos,
    seedSparks = seedSparks,
    seedContinueWatching = seedContinueWatching,
    followingIds = followingIds,
    viewerCountry = viewerCountry,
    currentUserId = currentUserId,
    hubsFreshSessionToken = hubsFreshSessionToken,
    notificationsUnread = notificationsUnread,
    onSearch = onSearch,
    onNotifications = onNotifications,
    onOpenVideo = onOpenVideo,
    onOpenSpark = onOpenSpark,
    onOpenLibrary = onOpenLibrary,
    miniPlayerBottomInset = miniPlayerBottomInset,
)
