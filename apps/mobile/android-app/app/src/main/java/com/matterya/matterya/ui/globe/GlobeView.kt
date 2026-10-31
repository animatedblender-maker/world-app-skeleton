package com.matterya.matterya.ui.globe

import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.matterya.matterya.data.globe.CountryMapData
import com.matterya.matterya.data.globe.CountryMapEntry
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.CountryTab
import com.matterya.matterya.model.ExternalNewsItem
import com.matterya.matterya.model.PostVisibility
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.HandDrawnGlobeStoryRing
import com.matterya.matterya.ui.components.MatteryaTopBar
import com.matterya.matterya.ui.components.PostCard
import com.matterya.matterya.ui.components.PostComposerView
import com.matterya.matterya.ui.news.NewsListCard
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Hand-drawn disc globe with [CountryMapData] hit-testing.
 * iOS currently disables country selection on the presence globe; this disc still
 * supports selection for CountryFeed deep-links (parity with CountryMapData algorithms).
 */
@Composable
fun GlobeView(
    onMenu: () -> Unit = {},
    onSearch: () -> Unit = {},
    onNotifications: () -> Unit = {},
    notificationsUnread: Int = 0,
    allowsCountrySelection: Boolean = true,
    onSelectCountry: (Country) -> Unit = {},
) {
    val context = LocalContext.current
    val entries = remember { CountryMapData.load(context) }
    var rotationY by remember { mutableFloatStateOf(20f) }
    var selected by remember { mutableStateOf<CountryMapEntry?>(null) }

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(MatteryaColors.oceanWash.copy(alpha = 0.55f), MatteryaColors.paper),
                ),
            ),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .padding(top = 48.dp),
            contentAlignment = Alignment.Center,
        ) {
            HandDrawnGlobeDisc(
                entries = entries,
                rotationYDeg = rotationY,
                selected = selected,
                modifier = Modifier.size(300.dp),
                onDragRotate = { delta -> rotationY = (rotationY + delta) % 360f },
                onTap = { entry ->
                    if (!allowsCountrySelection) return@HandDrawnGlobeDisc
                    selected = entry
                    onSelectCountry(
                        Country(
                            id = entry.iso2,
                            name = entry.name,
                            iso = entry.iso2,
                            centerLat = entry.lat,
                            centerLng = entry.lng,
                        ),
                    )
                },
            )
        }

        Column(Modifier.fillMaxSize()) {
            MatteryaTopBar(
                showsSearch = true,
                notificationsUnread = notificationsUnread,
                onMenu = onMenu,
                onSearch = onSearch,
                onNotifications = onNotifications,
            )
            Spacer(Modifier.weight(1f))
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(MatteryaDimens.pagePadding),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                HandDrawnGlobeStoryRing(size = 48.dp, highlighted = true)
                Spacer(Modifier.height(12.dp))
                Text(
                    selected?.name ?: "Globe",
                    fontFamily = FontFamily.Serif,
                    fontSize = 28.sp,
                    color = MatteryaColors.ink,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    if (selected != null) {
                        "Open ${selected!!.name} feed · drag to spin"
                    } else {
                        "Presence only — all posts live on the main feed."
                    },
                    color = MatteryaColors.inkMuted,
                    fontSize = 14.sp,
                )
                Spacer(Modifier.height(48.dp))
            }
        }
    }
}

@Composable
private fun HandDrawnGlobeDisc(
    entries: List<CountryMapEntry>,
    rotationYDeg: Float,
    selected: CountryMapEntry?,
    modifier: Modifier = Modifier,
    onDragRotate: (Float) -> Unit,
    onTap: (CountryMapEntry) -> Unit,
) {
    Canvas(
        modifier
            .pointerInput(rotationYDeg) {
                detectDragGestures { change, dragAmount ->
                    change.consume()
                    onDragRotate(dragAmount.x * 0.35f)
                }
            }
            .pointerInput(entries, rotationYDeg) {
                detectTapGestures { offset ->
                    val cx = size.width / 2f
                    val cy = size.height / 2f
                    val r = min(size.width, size.height) / 2f - 8f
                    val geo: Pair<Double, Double> = CountryMapData.discToGeographic(
                        offset.x,
                        offset.y,
                        rotationYDeg,
                        r,
                        cx,
                        cy,
                    ) ?: return@detectTapGestures
                    val lat = geo.first
                    val lng = geo.second
                    val hit = CountryMapData.country(
                        containingLng = lng,
                        containingLat = lat,
                        entries = entries,
                    )
                    if (hit != null) onTap(hit)
                }
            },
    ) {
        val c = Offset(size.width / 2, size.height / 2)
        val r = min(size.width, size.height) / 2f - 8f

        // Ocean disc
        drawCircle(color = MatteryaColors.oceanWash.copy(alpha = 0.55f), radius = r, center = c)
        // Paper land wash
        drawCircle(color = MatteryaColors.paper.copy(alpha = 0.35f), radius = r * 0.98f, center = c)

        // Country markers (centroids projected)
        entries.forEach { entry ->
            val proj: Pair<Float, Float> = CountryMapData.projectToDisc(
                entry.lat,
                entry.lng,
                rotationYDeg,
                r * 0.92f,
                c.x,
                c.y,
            ) ?: return@forEach
            val isSelected = selected?.iso3 == entry.iso3
            val p = Offset(proj.first, proj.second)
            drawCircle(
                color = if (isSelected) MatteryaColors.accentBright else MatteryaColors.landFill.copy(alpha = 0.9f),
                radius = if (isSelected) 5.5f else 2.8f,
                center = p,
            )
            if (isSelected) {
                drawCircle(
                    color = MatteryaColors.accent.copy(alpha = 0.35f),
                    radius = 12f,
                    center = p,
                    style = Stroke(width = 1.5f),
                )
            }
        }

        // Rim
        drawCircle(
            color = MatteryaColors.accent.copy(alpha = 0.55f),
            radius = r,
            center = c,
            style = Stroke(width = 2.2f),
        )

        // Meridians
        for (i in -2..2) {
            val ox = i * r * 0.28f
            drawArc(
                color = MatteryaColors.border.copy(alpha = 0.7f),
                startAngle = -70f,
                sweepAngle = 140f,
                useCenter = false,
                topLeft = Offset(c.x - r + ox, c.y - r),
                size = androidx.compose.ui.geometry.Size(r * 2 - ox * 0.2f, r * 2),
                style = Stroke(width = 1f),
            )
        }

        // Equator wobble
        val path = Path()
        for (i in 0..40) {
            val t = i / 40f
            val angle = t * Math.PI
            val x = c.x + cos(angle).toFloat() * r * 0.92f
            val y = c.y + sin(t * 8) * 3f
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        drawPath(path, MatteryaColors.landFill.copy(alpha = 0.8f), style = Stroke(1.2f))
    }
}

/**
 * Country feed — iOS `CountryFeedView` tabs: Posts / Following / Media / Stats / News
 * plus home vs foreign composer bars. Composer opens as a sheet (iOS `.sheet`) when
 * [onPublishPost] is provided; otherwise falls back to [onCompose] navigation.
 */
@Composable
fun CountryFeedView(
    countryName: String,
    countryIso: String,
    posts: List<CountryPost> = emptyList(),
    followingPosts: List<CountryPost> = emptyList(),
    newsItems: List<ExternalNewsItem> = emptyList(),
    isLoading: Boolean = false,
    loadError: String? = null,
    newsError: String? = null,
    selectedTab: CountryTab = CountryTab.POSTS,
    onTabChange: (CountryTab) -> Unit = {},
    onOpenSparks: () -> Unit = {},
    onLike: (CountryPost) -> Unit = {},
    onOpenPost: (CountryPost) -> Unit = {},
    onOpenNews: (ExternalNewsItem) -> Unit = {},
    onCompose: () -> Unit = {},
    onGoHomeToCompose: () -> Unit = {},
    canPost: Boolean = false,
    homeCountryLabel: String = "your country",
    profileAvatarUrl: String? = null,
    profileSeed: String = "me",
    profile: Profile? = null,
    openComposerRequested: Boolean = false,
    onComposerRequestConsumed: () -> Unit = {},
    onPublishPost: (suspend (title: String, body: String, visibility: PostVisibility, imageUri: Uri?) -> CountryPost?)? = null,
    onPostPublished: (CountryPost) -> Unit = {},
    countryStatsUsers: Int? = null,
    countryStatsOnline: Int? = null,
    globalStatsUsers: Int? = null,
    globalStatsOnline: Int? = null,
) {
    var showComposer by remember(countryIso) { mutableStateOf(false) }
    var localPosts by remember(countryIso, posts) { mutableStateOf(posts) }

    LaunchedEffect(posts) { localPosts = posts }

    // iOS openComposerIfRequested — auto-present sheet when navigating with openComposer flag.
    LaunchedEffect(openComposerRequested, canPost) {
        if (openComposerRequested && canPost) {
            showComposer = true
            onComposerRequestConsumed()
        }
    }

    fun openComposer() {
        if (onPublishPost != null && canPost) {
            showComposer = true
        } else {
            onCompose()
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas),
    ) {
        // Toolbar-style header
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.pagePadding, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(countryName, fontFamily = FontFamily.Serif, fontSize = 20.sp, color = MatteryaColors.ink)
            }
            Text(
                "${MatteryaCopy.sparksFromCountry} $countryName",
                color = MatteryaColors.accentBright,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .padding(end = 10.dp)
                    .clickable { onOpenSparks() },
            )
            Text(
                countryIso.uppercase(),
                fontWeight = FontWeight.Black,
                color = MatteryaColors.inkMuted,
                letterSpacing = 1.sp,
                fontSize = 12.sp,
            )
        }

        LazyRow(
            Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(CountryTab.entries.size) { idx ->
                val tab = CountryTab.entries[idx]
                FilterChip(
                    selected = selectedTab == tab,
                    onClick = { onTabChange(tab) },
                    label = { Text(tab.title) },
                )
            }
        }

        when {
            isLoading -> {
                Text(
                    "Loading $countryName…",
                    color = MatteryaColors.inkMuted,
                    modifier = Modifier.padding(24.dp),
                )
            }
            loadError != null && selectedTab != CountryTab.NEWS -> {
                Text(loadError, color = MatteryaColors.danger, modifier = Modifier.padding(24.dp))
            }
            else -> when (selectedTab) {
                CountryTab.POSTS -> {
                    LazyColumn(Modifier.fillMaxSize()) {
                        item {
                            CountryComposerBar(
                                canPost = canPost,
                                countryName = countryName,
                                homeCountryLabel = homeCountryLabel,
                                avatarUrl = profileAvatarUrl,
                                seed = profileSeed,
                                onCompose = { openComposer() },
                                onGoHome = onGoHomeToCompose,
                            )
                        }
                        if (localPosts.isEmpty()) {
                            item {
                                EmptyCountryCard("Posts from $countryName will appear here.")
                            }
                        }
                        items(localPosts.distinctBy { it.id }, key = { it.id }) { post ->
                            PostCard(
                                post = post,
                                onLike = { onLike(post) },
                                onOpenPost = { onOpenPost(post) },
                                edgeToEdge = true,
                            )
                        }
                    }
                }
                CountryTab.FOLLOWING -> {
                    LazyColumn(Modifier.fillMaxSize()) {
                        if (followingPosts.isEmpty()) {
                            item {
                                EmptyCountryCard("Follow people to see their posts from around the world here.")
                            }
                        }
                        items(followingPosts.distinctBy { it.id }, key = { it.id }) { post ->
                            PostCard(
                                post = post,
                                onLike = { onLike(post) },
                                onOpenPost = { onOpenPost(post) },
                                edgeToEdge = true,
                            )
                        }
                    }
                }
                CountryTab.MEDIA -> {
                    val media = localPosts.filter { it.hasMedia }
                    LazyColumn(Modifier.fillMaxSize()) {
                        if (media.isEmpty()) {
                            item {
                                EmptyCountryCard("No photos or videos in $countryName yet.")
                            }
                        }
                        items(media.distinctBy { it.id }, key = { it.id }) { post ->
                            PostCard(
                                post = post,
                                onLike = { onLike(post) },
                                onOpenPost = { onOpenPost(post) },
                                edgeToEdge = true,
                            )
                        }
                    }
                }
                CountryTab.STATS -> {
                    Column(
                        Modifier.padding(MatteryaDimens.pagePadding),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        if (countryStatsUsers == null && globalStatsUsers == null) {
                            EmptyCountryCard("Stats for $countryName are loading or unavailable.")
                        }
                        countryStatsUsers?.let { StatRow("Total users", "$it") }
                        countryStatsOnline?.let { StatRow("Online now", "$it") }
                        globalStatsUsers?.let { StatRow("Global users", "$it") }
                        globalStatsOnline?.let { StatRow("Global online", "$it") }
                    }
                }
                CountryTab.NEWS -> {
                    LazyColumn(
                        Modifier.fillMaxSize(),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(MatteryaDimens.pagePadding),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        if (newsError != null && newsItems.isEmpty()) {
                            item { EmptyCountryCard(newsError) }
                        } else if (newsItems.isEmpty()) {
                            item { EmptyCountryCard("No news updates for this country right now.") }
                        }
                        items(newsItems, key = { it.id }) { item ->
                            NewsListCard(item = item, onClick = { onOpenNews(item) })
                        }
                    }
                }
            }
        }
    }

    // iOS CountryFeedView `.sheet { PostComposerView }` — full-screen dialog sheet.
    if (showComposer && onPublishPost != null) {
        Dialog(
            onDismissRequest = { showComposer = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(MatteryaColors.paper),
            ) {
                PostComposerView(
                    country = Country(
                        id = countryIso.ifBlank { "XX" },
                        name = countryName.ifBlank { "Home" },
                        iso = countryIso.ifBlank { "XX" },
                    ),
                    profile = profile,
                    canPostHere = canPost,
                    onCancel = { showComposer = false },
                    onPublish = { title, body, visibility, imageUri ->
                        onPublishPost.invoke(title, body, visibility, imageUri)
                    },
                    onPosted = { post ->
                        localPosts = listOf(post) + localPosts.filter { it.id != post.id }
                        showComposer = false
                        onPostPublished(post)
                    },
                )
            }
        }
    }
}

@Composable
private fun CountryComposerBar(
    canPost: Boolean,
    countryName: String,
    homeCountryLabel: String,
    avatarUrl: String?,
    seed: String,
    onCompose: () -> Unit,
    onGoHome: () -> Unit,
) {
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(MatteryaDimens.cardRadius)
    if (canPost) {
        Row(
            Modifier
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(top = 12.dp, bottom = 8.dp)
                .fillMaxWidth()
                .background(MatteryaColors.surface, shape)
                .clickable(onClick = onCompose)
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            com.matterya.matterya.ui.components.AvatarView(url = avatarUrl, seed = seed, size = 40.dp)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    MatteryaCopy.postToYourFeed,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    color = MatteryaColors.ink,
                )
                Text(
                    "Write in $countryName — your home feed",
                    fontSize = 12.sp,
                    color = MatteryaColors.inkMuted,
                    maxLines = 2,
                )
            }
            Text("+", fontSize = 22.sp, color = MatteryaColors.accentBright, fontWeight = FontWeight.Bold)
        }
    } else {
        Column(
            Modifier
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(top = 12.dp, bottom = 8.dp)
                .fillMaxWidth()
                .background(MatteryaColors.surface, shape)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.Top) {
                Box(
                    Modifier
                        .size(40.dp)
                        .background(MatteryaColors.accentSoft, androidx.compose.foundation.shape.CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("◎", color = MatteryaColors.accentBright)
                }
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(
                        "Browsing $countryName",
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp,
                        color = MatteryaColors.ink,
                    )
                    Text(
                        "Posts open in $homeCountryLabel. ${MatteryaCopy.shareFromForeignHint}",
                        fontSize = 12.sp,
                        color = MatteryaColors.inkMuted,
                    )
                }
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(MatteryaColors.accentSoft, androidx.compose.foundation.shape.RoundedCornerShape(MatteryaDimens.controlRadius))
                    .clickable(onClick = onGoHome)
                    .padding(vertical = 12.dp, horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        MatteryaCopy.postToYourFeed,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp,
                        color = MatteryaColors.accentBright,
                    )
                    Text("Go to $homeCountryLabel", fontSize = 12.sp, color = MatteryaColors.accentBright)
                }
            }
        }
    }
}

@Composable
private fun EmptyCountryCard(message: String) {
    Text(
        message,
        fontSize = 14.sp,
        color = MatteryaColors.inkMuted,
        modifier = Modifier
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp)
            .fillMaxWidth()
            .background(MatteryaColors.surface, androidx.compose.foundation.shape.RoundedCornerShape(MatteryaDimens.cardRadius))
            .padding(16.dp),
    )
}

@Composable
private fun StatRow(label: String, value: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface, androidx.compose.foundation.shape.RoundedCornerShape(MatteryaDimens.cardRadius))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = MatteryaColors.inkMuted, modifier = Modifier.weight(1f))
        Text(value, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
    }
}
