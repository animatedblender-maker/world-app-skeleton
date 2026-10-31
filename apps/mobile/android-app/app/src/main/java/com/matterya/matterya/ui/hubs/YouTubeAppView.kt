package com.matterya.matterya.ui.hubs

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.cache.ContentCache
import com.matterya.matterya.data.cache.ContentCacheKey
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
import com.matterya.matterya.theme.SparksHorizontalStrip
import com.matterya.matterya.theme.YouTubeMediaLayout
import com.matterya.matterya.ui.components.UnreadDot
import com.matterya.matterya.ui.components.VideoThumbnailView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Matterya Hubs home — 1:1 structure with iOS `YouTubeAppView`:
 * filter chips → Sparks strip → Continue watching → For you list,
 * pure-shuffle on every Hubs visit, catalog load (cache → fast network).
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
    val context = LocalContext.current
    val catalog = remember { YouTubeCatalogService.get(context) }
    val postsService = remember { PostsService() }
    val contentCache = remember { ContentCache.get(context) }
    val scope = rememberCoroutineScope()

    var allVideos by remember { mutableStateOf(seedVideos) }
    var sparksStrip by remember { mutableStateOf(seedSparks) }
    var continueWatching by remember { mutableStateOf(seedContinueWatching) }
    var homeVideos by remember { mutableStateOf<List<CountryPost>>(emptyList()) }
    var homeFilter by remember { mutableStateOf(YouTubeHomeFilter.All) }
    var isLoading by remember { mutableStateOf(allVideos.isEmpty()) }
    var isRefreshing by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var homeListEpoch by remember { mutableIntStateOf(0) }

    fun pureShuffle(items: List<CountryPost>): List<CountryPost> =
        if (items.size <= 1) items else items.shuffled()

    fun rebuildHomeLists(shuffle: Boolean, remount: Boolean) {
        // iOS: rankForYouBySlugs (not pure shuffle) for For you / filter shelves.
        val focusSlug = homeFilter.hubSlug
        var home = catalog.rankForYouBySlugs(
            videos = allVideos,
            followingIds = followingIds,
            myUserId = currentUserId,
            sessionSeed = if (shuffle) System.currentTimeMillis() else hubsFreshSessionToken.toLong(),
            focusSlug = focusSlug,
        )
        if (home.isEmpty()) {
            home = catalog.filterVideos(
                videos = allVideos,
                homeFilter = homeFilter,
                followingIds = followingIds,
                viewerCountry = viewerCountry,
            )
        }
        if (home.isEmpty()) {
            home = allVideos.filter { PlayPlatformBridge.isHubsForYouLongForm(it) }
        }
        val displayCap = if (homeFilter == YouTubeHomeFilter.All) 64 else 80
        homeVideos = home.distinctBy { it.id }.take(displayCap)
        if (remount) homeListEpoch++
    }

    fun rebuildContinueAndSparks(shuffle: Boolean) {
        val reels = catalog.reels(allVideos).ifEmpty {
            allVideos.filter {
                it.isReel || it.isSpark || PlayPlatformBridge.isSparkFeedCard(it)
            }
        }
        sparksStrip = (if (shuffle) pureShuffle(reels) else reels).distinctBy { it.id }.take(14)

        val history = catalog.historyVideos(allVideos).filter { !it.isReel }
        val historyOrFallback = history.ifEmpty {
            allVideos.filter { PlayPlatformBridge.isHubsForYouLongForm(it) }
                .filter { catalog.playbackPosition(it.id) >= 1.0 }
        }
        continueWatching = (if (shuffle) pureShuffle(historyOrFallback) else historyOrFallback)
            .distinctBy { it.id }
            .take(8)
    }

    fun refreshHubsVisitShuffle(remount: Boolean = true) {
        rebuildHomeLists(shuffle = true, remount = remount)
        rebuildContinueAndSparks(shuffle = true)
    }

    suspend fun loadCatalog(forceRefresh: Boolean) {
        // 1) Instant paint from session / disk cache
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

        // 2) Network catalog (IO)
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

    // Initial load + content gen style warm
    LaunchedEffect(Unit) {
        catalog.bindToUser(currentUserId)
        if (seedVideos.isNotEmpty()) {
            allVideos = seedVideos.distinctBy { it.id }
            refreshHubsVisitShuffle(remount = true)
            isLoading = false
        }
        loadCatalog(forceRefresh = false)
    }

    // Every re-select of Hubs tab → pure shuffle (iOS hubsFreshSessionToken)
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

    // Filter chip change → reshuffle that shelf
    LaunchedEffect(homeFilter) {
        if (allVideos.isEmpty()) return@LaunchedEffect
        rebuildHomeLists(shuffle = true, remount = true)
        val thumbPx = YouTubeMediaLayout.hubsListThumbMaxPixel
        ImageCache.shared.prefetchPostThumbnails(
            homeVideos.take(12),
            maxPixelSize = thumbPx,
            aggressive = false,
        )
    }

    val bottomPad = if (miniPlayerBottomInset) 68.dp else 24.dp

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        HubsTopBar(
            onSearch = onSearch,
            onNotifications = onNotifications,
            notificationsUnread = notificationsUnread,
        )
        YouTubeFilterChips(
            selected = homeFilter,
            onSelect = { homeFilter = it },
            onLibrary = onOpenLibrary,
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
                isLoading && homeVideos.isEmpty() && sparksStrip.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(color = MatteryaColors.accent)
                            Spacer(Modifier.height(12.dp))
                            Text(
                                MatteryaCopy.loadingHubs,
                                color = MatteryaColors.inkMuted,
                                fontSize = 14.sp,
                            )
                        }
                    }
                }
                errorMessage != null && homeVideos.isEmpty() && sparksStrip.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            errorMessage ?: MatteryaCopy.hubsUnavailable,
                            color = MatteryaColors.danger,
                            modifier = Modifier.padding(24.dp),
                        )
                    }
                }
                homeVideos.isEmpty() &&
                    sparksStrip.isEmpty() &&
                    continueWatching.isEmpty() &&
                    homeFilter == YouTubeHomeFilter.All -> {
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
                    // Remount list on visit shuffle (iOS homeListEpoch).
                    key(homeListEpoch) {
                        LazyColumn(Modifier.fillMaxSize()) {
                            if (sparksStrip.isNotEmpty() && homeFilter == YouTubeHomeFilter.All) {
                                item(key = "sparks") {
                                    SparksHorizontalStrip(
                                        posts = sparksStrip,
                                        onOpen = onOpenSpark,
                                        onBrandTap = onOpenHubsHome,
                                    )
                                }
                            }
                            if (continueWatching.isNotEmpty() && homeFilter == YouTubeHomeFilter.All) {
                                item(key = "continue") {
                                    HubsHorizontalShelf(
                                        title = MatteryaCopy.continueWatching,
                                        posts = continueWatching,
                                        onOpen = onOpenVideo,
                                        trailing = {
                                            Text(
                                                MatteryaCopy.matteryaHubs,
                                                fontSize = 12.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                color = MatteryaColors.accentBright,
                                                modifier = Modifier.clickable(onClick = onOpenHubsHome),
                                            )
                                        },
                                    )
                                }
                            }
                            if (homeFilter == YouTubeHomeFilter.All && homeVideos.isNotEmpty()) {
                                item(key = "new-on-hubs-label") {
                                    Text(
                                        MatteryaCopy.newOnHubs,
                                        fontSize = 17.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MatteryaColors.ink,
                                        modifier = Modifier.padding(
                                            horizontal = MatteryaDimens.pagePadding,
                                            vertical = 10.dp,
                                        ),
                                    )
                                }
                            }
                            itemsIndexed(
                                homeVideos,
                                key = { _, post -> post.id },
                            ) { index, post ->
                                LaunchedEffect(post.id, index) {
                                    ImageCache.shared.prefetchHubsWindow(
                                        posts = homeVideos,
                                        around = index,
                                        behind = 2,
                                        ahead = 8,
                                        maxPixelSize = YouTubeMediaLayout.hubsListThumbMaxPixel,
                                    )
                                }
                                HubsVideoRow(
                                    post = post,
                                    onOpen = { onOpenVideo(post) },
                                )
                            }
                            if (homeVideos.isEmpty() && homeFilter != YouTubeHomeFilter.All) {
                                item(key = "empty-cat") {
                                    Text(
                                        "No videos in this category",
                                        color = MatteryaColors.inkMuted,
                                        modifier = Modifier.padding(24.dp),
                                        fontSize = 14.sp,
                                    )
                                }
                            }
                            item(key = "bottom-pad") { Spacer(Modifier.height(bottomPad)) }
                        }
                    }
                }
            }
        }
    }
}

/** iOS `YouTubeFilterChips`. */
@Composable
fun YouTubeFilterChips(
    selected: YouTubeHomeFilter,
    onSelect: (YouTubeHomeFilter) -> Unit,
    onLibrary: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val filters = listOf(YouTubeHomeFilter.All) + YouTubeHomeFilter.hubCategories
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onLibrary != null) {
                FilterPill(label = "Library", selected = false, onClick = onLibrary)
            }
            filters.forEach { filter ->
                FilterPill(
                    label = filter.title,
                    selected = selected == filter,
                    onClick = { onSelect(filter) },
                )
            }
        }
        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
    }
}

@Composable
private fun FilterPill(label: String, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(percent = 50)
    Text(
        label,
        fontSize = 13.sp,
        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
        color = if (selected) MatteryaColors.surface else MatteryaColors.ink,
        modifier = Modifier
            .clip(shape)
            .background(if (selected) MatteryaColors.ink else MatteryaColors.surfaceMuted)
            .border(
                0.5.dp,
                if (selected) MatteryaColors.ink else MatteryaColors.border,
                shape,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    )
}

@Composable
private fun HubsTopBar(
    onSearch: () -> Unit,
    onNotifications: () -> Unit,
    notificationsUnread: Int = 0,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface.copy(alpha = 0.92f))
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(Modifier.size(44.dp))
        PlayBrandMark(compact = true, modifier = Modifier.weight(1f))
        IconButton(onClick = onSearch, modifier = Modifier.size(40.dp)) {
            Icon(Icons.Default.Search, contentDescription = MatteryaCopy.searchHubs, tint = MatteryaColors.ink)
        }
        Box {
            IconButton(onClick = onNotifications, modifier = Modifier.size(40.dp)) {
                Icon(Icons.Default.NotificationsNone, contentDescription = "Notifications", tint = MatteryaColors.ink)
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

@Composable
private fun HubsVideoRow(post: CountryPost, onOpen: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .padding(bottom = 16.dp)
            .background(MatteryaColors.canvas),
    ) {
        // 16:9 stage, aspectFill crop (iOS YouTubeVideoListRow).
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f)
                .clipToBounds()
                .background(Color.Black),
        ) {
            VideoThumbnailView(
                post = post,
                maxLogicalPx = 480,
                showsPlayIcon = false,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            Text(
                post.displayHeadline ?: post.displayExcerpt.ifEmpty { post.authorDisplayName },
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
                color = MatteryaColors.ink,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                "${post.authorDisplayName} · ${post.relativeTime}",
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
            )
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
