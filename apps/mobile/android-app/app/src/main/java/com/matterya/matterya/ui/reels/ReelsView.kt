package com.matterya.matterya.ui.reels

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Reply
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.reels.SparkDiscoveryEngine
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.FollowButton
import com.matterya.matterya.ui.components.VideoPlayerView
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val paper = MatteryaColors.paper
private val glassShape = RoundedCornerShape(18.dp)
private val chipShape = RoundedCornerShape(percent = 50)

/**
 * Sparks full-screen vertical pager — mirrors iOS `ReelsScrollViewer` + `ReelsVerticalFeed`.
 *
 * Chrome: Sparks badge + close, author row + Follow, caption, glass action dock
 * (Like / Chat / Keep / Send / mute), timeline scrubber, muted from [feedVideosMuted].
 */
@Composable
fun ReelsView(
    posts: List<CountryPost>,
    title: String = MatteryaCopy.sparks,
    isLoading: Boolean = false,
    errorMessage: String? = null,
    onBack: () -> Unit = {},
    onLike: (CountryPost) -> Unit = {},
    onSave: (CountryPost) -> Unit = {},
    onShare: (CountryPost) -> Unit = {},
    onComment: (CountryPost) -> Unit = {},
    onOpenProfile: (CountryPost) -> Unit = {},
    onOpenPost: (CountryPost) -> Unit = {},
    onToggleFollow: (suspend (String) -> Unit)? = null,
    isFollowing: (String) -> Boolean = { false },
    isPostSaved: (String) -> Boolean = { false },
    currentUserId: String? = null,
    currentProfile: com.matterya.matterya.model.Profile? = null,
    feedVideosMuted: Boolean = false,
    onFeedVideosMutedChange: (Boolean) -> Unit = {},
    startIndex: Int = 0,
    showsOpenPostAction: Boolean = false,
    showsProgressRail: Boolean = false,
    bottomInsetDp: Int = 28,
    /** When true, Chat opens over-player comments (iOS SparksCommentsOverlay) instead of only onComment. */
    useOverPlayerComments: Boolean = true,
    /** Notify owner when pager settles (iOS ReelsScrollViewer activeIndex). */
    onActiveIndexChange: (Int) -> Unit = {},
) {
    var commentsPost by remember { mutableStateOf<CountryPost?>(null) }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        when {
            isLoading -> {
                Column(
                    Modifier.align(Alignment.Center),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator(color = Color.White)
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "Loading ${MatteryaCopy.sparks.lowercase()}…",
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = 14.sp,
                    )
                }
            }
            errorMessage != null -> {
                Text(
                    errorMessage,
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(24.dp),
                )
            }
            posts.isEmpty() -> {
                Column(
                    Modifier.align(Alignment.Center),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        "No ${MatteryaCopy.sparks.lowercase()}",
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "This ${MatteryaCopy.spark.lowercase()} is no longer available.",
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 14.sp,
                    )
                }
            }
            else -> {
                val safeStart = startIndex.coerceIn(0, (posts.size - 1).coerceAtLeast(0))
                val pagerState = rememberPagerState(
                    initialPage = safeStart,
                    pageCount = { posts.size.coerceAtLeast(1) },
                )
                LaunchedEffect(pagerState.currentPage) {
                    onActiveIndexChange(pagerState.currentPage)
                }
                // One neighbor for seamless swipe (iOS warms ahead; 1 keeps memory sane on emulator).
                VerticalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxSize(),
                    beyondViewportPageCount = 1,
                ) { page ->
                    if (page !in posts.indices) return@VerticalPager
                    val post = posts[page]
                    ReelsPagerCard(
                        post = post,
                        isActive = pagerState.currentPage == page,
                        bottomInsetDp = bottomInsetDp,
                        showsOpenPostAction = showsOpenPostAction,
                        feedVideosMuted = feedVideosMuted,
                        onFeedVideosMutedChange = onFeedVideosMutedChange,
                        isSaved = isPostSaved(post.id),
                        isFollowingAuthor = isFollowing(post.authorId),
                        currentUserId = currentUserId,
                        onLike = { onLike(post) },
                        onSave = { onSave(post) },
                        onShare = { onShare(post) },
                        onComment = {
                            if (useOverPlayerComments) {
                                commentsPost = post
                            }
                            onComment(post)
                        },
                        onOpenProfile = { onOpenProfile(post) },
                        onOpenPost = { onOpenPost(post) },
                        onToggleFollow = onToggleFollow,
                    )
                }

                if (showsProgressRail && posts.size > 1) {
                    ReelsProgressRail(
                        count = posts.size,
                        activeIndex = pagerState.currentPage,
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .statusBarsPadding()
                            .padding(top = 54.dp, start = 16.dp, end = 16.dp),
                    )
                }
            }
        }

        // iOS SparksTopChrome — close (X) + SPARKS badge
        SparksTopChrome(
            title = title.ifBlank { MatteryaCopy.sparks },
            onClose = onBack,
            modifier = Modifier.align(Alignment.TopCenter),
        )

        // iOS SparksCommentsOverlay — bottom sheet over live player (video keeps playing).
        commentsPost?.let { post ->
            SparksCommentsOverlay(
                post = post,
                currentProfile = currentProfile,
                onClose = { commentsPost = null },
                onOpenProfile = { _, _ ->
                    // Dismiss comments only; profile navigation is handled by shell via onOpenProfile(post).
                    commentsPost = null
                    onOpenProfile(post)
                },
            )
        }
    }
}

/** Alias matching iOS `ReelsVerticalFeed` naming. */
@Composable
fun ReelsVerticalFeed(
    posts: List<CountryPost>,
    title: String = MatteryaCopy.sparks,
    isLoading: Boolean = false,
    errorMessage: String? = null,
    onBack: () -> Unit = {},
    onLike: (CountryPost) -> Unit = {},
    onSave: (CountryPost) -> Unit = {},
    onShare: (CountryPost) -> Unit = {},
    onComment: (CountryPost) -> Unit = {},
    onOpenProfile: (CountryPost) -> Unit = {},
    onOpenPost: (CountryPost) -> Unit = {},
    onToggleFollow: (suspend (String) -> Unit)? = null,
    isFollowing: (String) -> Boolean = { false },
    isPostSaved: (String) -> Boolean = { false },
    currentUserId: String? = null,
    feedVideosMuted: Boolean = false,
    onFeedVideosMutedChange: (Boolean) -> Unit = {},
    startIndex: Int = 0,
    showsOpenPostAction: Boolean = true,
    showsProgressRail: Boolean = true,
    bottomInsetDp: Int = 48,
) = ReelsView(
    posts = posts,
    title = title,
    isLoading = isLoading,
    errorMessage = errorMessage,
    onBack = onBack,
    onLike = onLike,
    onSave = onSave,
    onShare = onShare,
    onComment = onComment,
    onOpenProfile = onOpenProfile,
    onOpenPost = onOpenPost,
    onToggleFollow = onToggleFollow,
    isFollowing = isFollowing,
    isPostSaved = isPostSaved,
    currentUserId = currentUserId,
    feedVideosMuted = feedVideosMuted,
    onFeedVideosMutedChange = onFeedVideosMutedChange,
    startIndex = startIndex,
    showsOpenPostAction = showsOpenPostAction,
    showsProgressRail = showsProgressRail,
    bottomInsetDp = bottomInsetDp,
)

/** iOS `SparksTopChrome` — close top-leading + SPARKS wordmark centered. */
@Composable
fun SparksTopChrome(
    title: String = MatteryaCopy.sparks,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val word = title.uppercase()
    Box(
        modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .height(44.dp)
            .padding(horizontal = (MatteryaDimens.pagePadding - 4.dp).coerceAtLeast(8.dp)),
    ) {
        Text(
            word,
            fontSize = 13.sp,
            fontWeight = FontWeight.Black,
            fontFamily = FontFamily.SansSerif,
            letterSpacing = 4.5.sp,
            color = paper.copy(alpha = 0.95f),
            modifier = Modifier.align(Alignment.Center),
        )
        // Soft gold wash over the badge (gradient approximation)
        Text(
            word,
            fontSize = 13.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 4.5.sp,
            color = MatteryaColors.accentBright.copy(alpha = 0.35f),
            modifier = Modifier.align(Alignment.Center),
        )
        IconButton(
            onClick = onClose,
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(40.dp),
        ) {
            Box(
                Modifier
                    .size(32.dp)
                    .background(Color.Black.copy(alpha = 0.28f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Default.Close,
                    contentDescription = "Close ${MatteryaCopy.sparks.lowercase()}",
                    tint = Color.White,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

@Composable
private fun ReelsProgressRail(
    count: Int,
    activeIndex: Int,
    modifier: Modifier = Modifier,
) {
    val window = minOf(count, 12)
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(window) { index ->
            val isActive = index == activeIndex % 12
            Box(
                Modifier
                    .height(2.5.dp)
                    .width(if (isActive) 18.dp else 8.dp)
                    .clip(chipShape)
                    .background(
                        if (isActive) MatteryaColors.reelsAccent
                        else Color.White.copy(alpha = 0.28f),
                    ),
            )
        }
    }
}

@Composable
private fun ReelsPagerCard(
    post: CountryPost,
    isActive: Boolean,
    bottomInsetDp: Int,
    showsOpenPostAction: Boolean,
    feedVideosMuted: Boolean,
    onFeedVideosMutedChange: (Boolean) -> Unit,
    isSaved: Boolean,
    isFollowingAuthor: Boolean,
    currentUserId: String?,
    onLike: () -> Unit,
    onSave: () -> Unit,
    onShare: () -> Unit,
    onComment: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenPost: () -> Unit,
    onToggleFollow: (suspend (String) -> Unit)?,
) {
    var pausedByUser by remember(post.id) { mutableStateOf(false) }
    var showPauseGlyph by remember(post.id) { mutableStateOf(false) }
    var showLikeBurst by remember(post.id) { mutableStateOf(false) }
    var likeScale by remember(post.id) { mutableFloatStateOf(1f) }
    var saveFeedback by remember(post.id) { mutableStateOf<String?>(null) }
    var currentSec by remember(post.id) { mutableDoubleStateOf(0.0) }
    var durationSec by remember(post.id) { mutableDoubleStateOf(0.0) }
    var seekTo by remember(post.id) { mutableStateOf<Double?>(null) }
    var isScrubbing by remember(post.id) { mutableStateOf(false) }
    // Bump once per focus — not every recompose (old page+1 token caused restart/poster blink).
    var focusGeneration by remember(post.id) { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()

    val muteIcon = if (feedVideosMuted) Icons.Default.VolumeOff else Icons.Default.VolumeUp
    val likeScaleAnim by animateFloatAsState(
        targetValue = likeScale,
        animationSpec = spring(dampingRatio = 0.55f, stiffness = 400f),
        label = "likeScale",
    )

    fun keepPlaying() {
        pausedByUser = false
        showPauseGlyph = false
    }

    fun triggerLike(fromButton: Boolean) {
        keepPlaying()
        val willLike = !post.likedByMe
        if (fromButton) {
            onLike()
        } else if (!post.likedByMe) {
            onLike()
        }
        if (willLike || !fromButton) {
            showLikeBurst = true
            likeScale = 1.22f
            scope.launch {
                delay(550)
                showLikeBurst = false
                likeScale = 1f
            }
        }
    }

    fun flashPauseGlyph() {
        showPauseGlyph = true
        scope.launch {
            delay(700)
            showPauseGlyph = false
        }
    }

    LaunchedEffect(isActive) {
        if (!isActive) {
            pausedByUser = false
            showPauseGlyph = false
            currentSec = 0.0
            seekTo = null
            isScrubbing = false
        } else {
            focusGeneration += 1
            pausedByUser = false
            showPauseGlyph = false
            currentSec = 0.0
            seekTo = null
            isScrubbing = false
            // iOS marks watched on page settle so discovery never re-serves early.
            SparkDiscoveryEngine.markWatched(post.id)
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .clipToBounds()
            .pointerInput(post.id) {
                detectTapGestures(
                    onDoubleTap = { triggerLike(fromButton = false) },
                    onTap = {
                        pausedByUser = !pausedByUser
                        if (pausedByUser) flashPauseGlyph() else showPauseGlyph = false
                    },
                )
            },
    ) {
        // Film stage — ALWAYS aspectFill edge-to-edge (iOS SparksUIKitPager / Shorts).
        // Landscape sources crop top/bottom; never letterbox (black bars were a major UX bug).
        VideoPlayerView(
            url = post.playableVideoUrl,
            posterUrl = post.posterImageUrl,
            placement = "reel",
            countryCode = post.countryCode,
            contentCountryCode = post.countryCode,
            postId = post.id,
            adsEnabled = false,
            isActive = isActive && !pausedByUser,
            isPausedByUser = pausedByUser,
            loops = true,
            muted = feedVideosMuted,
            showsControls = false,
            fillsFrame = true,
            restartFromBeginningToken = if (isActive) focusGeneration else 0,
            seekToSeconds = seekTo,
            onSeekConsumed = { seekTo = null },
            onProgress = { cur, dur ->
                if (!isScrubbing) {
                    currentSec = cur
                    if (dur > 0.25) durationSec = dur
                }
            },
            modifier = Modifier.fillMaxSize(),
        )

        // Soft vignette (iOS filmStage)
        Column(Modifier.fillMaxSize()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(64.dp)
                    .background(
                        Brush.verticalGradient(
                            listOf(MatteryaColors.ink.copy(alpha = 0.22f), Color.Transparent),
                        ),
                    ),
            )
            Spacer(Modifier.weight(1f))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(160.dp)
                    .background(
                        Brush.verticalGradient(
                            listOf(
                                Color.Transparent,
                                MatteryaColors.ink.copy(alpha = 0.18f),
                                MatteryaColors.ink.copy(alpha = 0.42f),
                            ),
                        ),
                    ),
            )
        }

        // Pause glyph
        if (showPauseGlyph) {
            Icon(
                Icons.Default.PlayArrow,
                contentDescription = null,
                tint = Color(red = 0.96f, green = 0.93f, blue = 0.86f).copy(alpha = 0.72f),
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(72.dp),
            )
        }

        // Like burst
        if (showLikeBurst) {
            Icon(
                Icons.Filled.Favorite,
                contentDescription = null,
                tint = MatteryaColors.like.copy(alpha = 0.95f),
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(88.dp),
            )
        }

        // Save feedback toast
        saveFeedback?.let { msg ->
            Text(
                msg,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(top = 56.dp)
                    .background(paper.copy(alpha = 0.94f), chipShape)
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }

        // Side mute control (top-trailing, over film — iOS dock doesn't host mute but
        // product req wires AppState.feedVideosMuted)
        IconButton(
            onClick = { onFeedVideosMutedChange(!feedVideosMuted) },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(top = 40.dp, end = 8.dp),
        ) {
            Box(
                Modifier
                    .size(36.dp)
                    .background(Color.Black.copy(alpha = 0.28f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(muteIcon, contentDescription = "Mute", tint = Color.White, modifier = Modifier.size(18.dp))
            }
        }

        // Spark glass dock (iOS sparkDock)
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 12.dp)
                .padding(bottom = bottomInsetDp.dp.coerceAtLeast(10.dp)),
        ) {
            SparkDock(
                post = post,
                isActive = isActive,
                isSaved = isSaved,
                isFollowingAuthor = isFollowingAuthor,
                currentUserId = currentUserId,
                showsOpenPostAction = showsOpenPostAction,
                currentSec = currentSec,
                durationSec = durationSec,
                isScrubbing = isScrubbing,
                likeScale = likeScaleAnim,
                onScrubbingChange = { isScrubbing = it },
                onSeek = { seconds ->
                    currentSec = seconds
                    seekTo = seconds
                },
                onLike = { triggerLike(fromButton = true) },
                onComment = {
                    keepPlaying()
                    onComment()
                },
                onSave = {
                    keepPlaying()
                    val willSave = !isSaved
                    onSave()
                    val message = if (willSave) {
                        "Saved to ${MatteryaCopy.savedSparks}"
                    } else {
                        "Removed from saved"
                    }
                    saveFeedback = message
                    scope.launch {
                        delay(1600)
                        if (saveFeedback == message) saveFeedback = null
                    }
                },
                onShare = {
                    keepPlaying()
                    onShare()
                },
                onOpenPost = {
                    keepPlaying()
                    onOpenPost()
                },
                onOpenProfile = onOpenProfile,
                onToggleFollow = onToggleFollow,
            )
        }
    }
}

@Composable
private fun SparkDock(
    post: CountryPost,
    isActive: Boolean,
    isSaved: Boolean,
    isFollowingAuthor: Boolean,
    currentUserId: String?,
    showsOpenPostAction: Boolean,
    currentSec: Double,
    durationSec: Double,
    isScrubbing: Boolean,
    likeScale: Float,
    onScrubbingChange: (Boolean) -> Unit,
    onSeek: (Double) -> Unit,
    onLike: () -> Unit,
    onComment: () -> Unit,
    onSave: () -> Unit,
    onShare: () -> Unit,
    onOpenPost: () -> Unit,
    onOpenProfile: () -> Unit,
    onToggleFollow: (suspend (String) -> Unit)?,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(glassShape)
            .background(paper.copy(alpha = 0.14f))
            .background(Color.Black.copy(alpha = 0.28f))
            .border(0.5.dp, paper.copy(alpha = 0.22f), glassShape)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Author row + Follow
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                Modifier
                    .weight(1f)
                    .clickable(onClick = onOpenProfile),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AvatarView(
                    url = post.author?.avatarUrl,
                    seed = post.authorId.ifEmpty { post.authorDisplayName },
                    size = 34.dp,
                )
                Spacer(Modifier.width(8.dp))
                Column {
                    Text(
                        post.author?.displayName ?: "Member",
                        color = paper,
                        fontFamily = FontFamily.Serif,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        post.author?.username?.takeIf { it.isNotBlank() }?.let { handle ->
                            Text(
                                "@$handle",
                                color = paper.copy(alpha = 0.7f),
                                fontSize = 11.sp,
                                maxLines = 1,
                            )
                        }
                        val place = post.countryName ?: post.countryCode?.uppercase()
                        if (!place.isNullOrBlank()) {
                            Text("·", color = paper.copy(alpha = 0.4f), fontSize = 11.sp)
                            Text(
                                place,
                                color = paper.copy(alpha = 0.65f),
                                fontSize = 11.sp,
                                maxLines = 1,
                            )
                        }
                    }
                }
            }
            val authorId = post.authorId
            if (
                onToggleFollow != null &&
                authorId.isNotBlank() &&
                authorId != currentUserId
            ) {
                FollowButton(
                    userId = authorId,
                    isFollowing = isFollowingAuthor,
                    isSelf = false,
                    onToggle = { onToggleFollow(authorId) },
                    compact = true,
                    onDark = true,
                )
            }
        }

        // Caption
        post.sparkDisplayCaption?.takeIf { it.isNotBlank() }?.let { caption ->
            Text(
                caption,
                color = paper.copy(alpha = 0.94f),
                fontFamily = FontFamily.Serif,
                fontSize = 14.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }

        // Timeline
        if (isActive) {
            SparksTimelineBar(
                currentSeconds = currentSec,
                durationSeconds = durationSec,
                isScrubbing = isScrubbing,
                onScrubbingChange = onScrubbingChange,
                onSeek = onSeek,
            )
        }

        // Action ribbon — Like / Chat / Keep / Send [/ Open]
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            SparkActionChip(
                icon = if (post.likedByMe) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                label = if (post.likeCount > 0) "${post.likeCount}" else "Like",
                accent = if (post.likedByMe) MatteryaColors.like else paper,
                scale = likeScale,
                onClick = onLike,
                modifier = Modifier.weight(1f),
            )
            SparkActionChip(
                icon = Icons.Outlined.ChatBubbleOutline,
                label = if (post.commentCount > 0) "${post.commentCount}" else "Chat",
                accent = paper,
                onClick = onComment,
                modifier = Modifier.weight(1f),
            )
            SparkActionChip(
                icon = if (isSaved) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                label = "Keep",
                accent = if (isSaved) MatteryaColors.accentBright else paper,
                onClick = onSave,
                modifier = Modifier.weight(1f),
            )
            SparkActionChip(
                icon = Icons.AutoMirrored.Outlined.Reply,
                label = "Send",
                accent = paper,
                onClick = onShare,
                modifier = Modifier.weight(1f),
            )
            if (showsOpenPostAction) {
                SparkActionChip(
                    icon = Icons.Default.NorthEast,
                    label = "Open",
                    accent = paper,
                    onClick = onOpenPost,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun SparkActionChip(
    icon: ImageVector,
    label: String,
    accent: Color,
    scale: Float = 1f,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .clip(chipShape)
            .background(paper.copy(alpha = 0.12f))
            .border(0.5.dp, paper.copy(alpha = 0.14f), chipShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Icon(
            icon,
            contentDescription = label,
            tint = accent,
            modifier = Modifier
                .size(12.dp)
                .scale(scale),
        )
        Spacer(Modifier.width(4.dp))
        Text(
            label,
            color = accent,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** iOS `SparksTimelineBar` — slim amber trail. */
@Composable
private fun SparksTimelineBar(
    currentSeconds: Double,
    durationSeconds: Double,
    isScrubbing: Boolean,
    onScrubbingChange: (Boolean) -> Unit,
    onSeek: (Double) -> Unit,
) {
    val fraction = when {
        !durationSeconds.isFinite() || durationSeconds <= 0.35 -> 0f
        else -> (currentSeconds / durationSeconds).toFloat().coerceIn(0f, 1f)
    }
    val trackH = if (isScrubbing) 3.5.dp else 1.5.dp

    Column(Modifier.fillMaxWidth()) {
        if (isScrubbing && durationSeconds > 0.35) {
            Text(
                "${formatClock(currentSeconds)} · ${formatClock(durationSeconds)}",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = paper.copy(alpha = 0.85f),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 3.dp),
                // trailing
            )
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(18.dp)
                .pointerInput(durationSeconds) {
                    detectTapGestures { offset ->
                        if (durationSeconds > 0.35) {
                            val f = (offset.x / size.width).coerceIn(0f, 1f)
                            onSeek(f * durationSeconds)
                        }
                    }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(trackH)
                    .clip(chipShape)
                    .background(paper.copy(alpha = 0.18f)),
            )
            Box(
                Modifier
                    .fillMaxWidth(fraction.coerceAtLeast(0.001f))
                    .height(trackH)
                    .clip(chipShape)
                    .background(MatteryaColors.accentBright.copy(alpha = 0.95f)),
            )
            if (isScrubbing) {
                Box(
                    Modifier
                        .padding(start = ((fraction * 100).coerceIn(0f, 100f)).dp) // approximate
                        .size(11.dp)
                        .background(paper, CircleShape)
                        .border(1.2.dp, MatteryaColors.accentBright, CircleShape),
                )
            }
        }
    }
    // Suppress unused — scrubbing state is driven by parent for seek; drag can be added later
    @Suppress("UNUSED_VARIABLE")
    val _scrub = onScrubbingChange
}

private fun formatClock(seconds: Double): String {
    val s = maxOf(0, seconds.toInt())
    val m = s / 60
    val r = s % 60
    return "%d:%02d".format(m, r)
}

/**
 * iOS `SparksCommentsOverlay` — bottom sheet over the live Sparks player.
 * Video keeps playing; dismiss via Close, dimmer, or drag handle.
 */
@Composable
fun SparksCommentsOverlay(
    post: CountryPost,
    currentProfile: com.matterya.matterya.model.Profile? = null,
    onClose: () -> Unit = {},
    onOpenProfile: (userId: String, username: String?) -> Unit = { _, _ -> },
) {
    var dragOffset by remember { mutableFloatStateOf(0f) }

    Box(Modifier.fillMaxSize()) {
        // Dimmer / tap outside
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.32f))
                .clickable(onClick = onClose),
        )
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .fillMaxHeight(0.62f)
                .offset { IntOffset(0, maxOf(0, dragOffset.roundToInt())) }
                .clip(RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp))
                .background(MatteryaColors.surface),
        ) {
            // Grab handle
            Box(
                Modifier
                    .fillMaxWidth()
                    .pointerInput(Unit) {
                        detectVerticalDragGestures(
                            onVerticalDrag = { _, amount ->
                                if (amount > 0) dragOffset = (dragOffset + amount).coerceAtLeast(0f)
                            },
                            onDragEnd = {
                                if (dragOffset > 90f) onClose()
                                dragOffset = 0f
                            },
                        )
                    }
                    .padding(top = 10.dp, bottom = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .size(width = 44.dp, height = 5.dp)
                        .clip(chipShape)
                        .background(MatteryaColors.inkMuted.copy(alpha = 0.45f)),
                )
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Close",
                    color = MatteryaColors.accentBright,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                    modifier = Modifier
                        .clickable(onClick = onClose)
                        .padding(8.dp),
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "Comments",
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 17.sp,
                    color = MatteryaColors.ink,
                )
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.width(56.dp))
            }
            com.matterya.matterya.ui.components.PostCommentsPageView(
                post = post,
                currentProfile = currentProfile,
                onOpenProfile = onOpenProfile,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            )
        }
    }
}
