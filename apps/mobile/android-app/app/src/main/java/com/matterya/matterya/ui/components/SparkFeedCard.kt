package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.media.FeedAutoplaySurface
import com.matterya.matterya.data.media.MediaUrlResolver
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.FacebookMediaLayout
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy

/**
 * In-feed Sparks surface — **line-by-line from iOS `SparkFeedCard`** (ShareComponents.swift).
 *
 * - Height = [FacebookMediaLayout.dominantFeedVideoHeight] (same tall FB box as other feed video)
 * - Live [InFrameVideoPlayer] with **fillsFrame / Crop** (no letterbox)
 * - Mute-only chrome sharing feed mute
 * - Sparks badge top-leading
 * - Tap (below 52dp mute strip) opens full Sparks player
 */
@Composable
fun SparkFeedCard(
    post: CountryPost,
    edgeToEdge: Boolean = true,
    autoplaySurface: FeedAutoplaySurface = FeedAutoplaySurface.Home,
    feedVideosMuted: Boolean = false,
    onFeedVideosMutedChange: (Boolean) -> Unit = {},
    surfaceLive: Boolean = true,
    reelsOpen: Boolean = false,
    hubPlaying: Boolean = false,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val corner = if (edgeToEdge) 0.dp else 12.dp
    val config = LocalConfiguration.current
    val density = LocalDensity.current
    val screenHpx = with(density) { config.screenHeightDp.dp.toPx() }

    val playUrl = remember(post.id, post.mediaUrl, post.playableVideoUrl) {
        post.playableVideoUrl
            ?: MediaUrlResolver.videoUrl(post)
    }

    BoxWithConstraints(modifier.fillMaxWidth()) {
        val widthPx = with(density) { maxWidth.toPx() }
        // iOS: FacebookMediaLayout.dominantFeedVideoHeight() — NOT full 9:16.
        val heightPx = FacebookMediaLayout.dominantFeedVideoHeight(widthPx, screenHpx)
        val heightDp = with(density) { heightPx.toDp() }

        Box(
            Modifier
                .fillMaxWidth()
                .height(heightDp)
                .clip(RoundedCornerShape(corner))
                .clipToBounds()
                .background(MatteryaColors.ink)
                .then(
                    if (!edgeToEdge) {
                        Modifier.border(
                            0.5.dp,
                            MatteryaColors.border.copy(alpha = 0.5f),
                            RoundedCornerShape(corner),
                        )
                    } else {
                        Modifier
                    },
                ),
        ) {
            if (playUrl != null) {
                // iOS: size the box, then **fill** it — no letterbox that shrinks the picture.
                InFrameVideoPlayer(
                    post = post,
                    url = playUrl,
                    posterUrl = post.posterImageUrl,
                    placement = "reel",
                    loops = true,
                    showsControls = false,
                    muteOnlyControls = true,
                    sharesFeedMute = true,
                    feedVideosMuted = feedVideosMuted,
                    onFeedVideosMutedChange = onFeedVideosMutedChange,
                    autoplaySurface = autoplaySurface,
                    surfaceLive = surfaceLive,
                    reelsOpen = reelsOpen,
                    hubPlaying = hubPlaying,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                VideoThumbnailView(
                    post = post,
                    maxLogicalPx = 720,
                    showsPlayIcon = true,
                    playIconSize = 36.dp,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }

            SparksOriginBadge(
                compact = true,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(10.dp),
            )

            // Tap opens full Sparks player; leave top strip free for mute chip (iOS 52pt).
            Column(Modifier.fillMaxSize()) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                )
                Box(
                    Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .clickable(onClick = onOpen),
                )
            }
        }
    }
}

/** Compact Sparks brand chip — iOS `SparksOriginBadge`. */
@Composable
fun SparksOriginBadge(
    compact: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .background(
                brush = Brush.horizontalGradient(
                    listOf(MatteryaColors.reelsAccent, MatteryaColors.accentBright.copy(alpha = 0.92f)),
                ),
                shape = RoundedCornerShape(999.dp),
            )
            .padding(
                horizontal = if (compact) 8.dp else 10.dp,
                vertical = if (compact) 4.dp else 6.dp,
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Default.AutoAwesome,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier
                .padding(end = if (compact) 4.dp else 6.dp)
                .size(if (compact) 10.dp else 12.dp),
        )
        Text(
            MatteryaCopy.sparks,
            color = Color.White,
            fontSize = if (compact) 10.sp else 12.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.3.sp,
        )
    }
}

/**
 * Hubs long-form feed card — iOS `PlayFeedLinkCard`:
 * tall FB media box, live player when focused, Hubs badge top-leading, center open tap.
 */
@Composable
fun PlayFeedLinkCard(
    post: CountryPost,
    edgeToEdge: Boolean = true,
    forceHubsBadge: Boolean = true,
    autoplaySurface: FeedAutoplaySurface = FeedAutoplaySurface.Home,
    feedVideosMuted: Boolean = false,
    onFeedVideosMutedChange: (Boolean) -> Unit = {},
    surfaceLive: Boolean = true,
    reelsOpen: Boolean = false,
    hubPlaying: Boolean = false,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val corner = if (edgeToEdge) 0.dp else 12.dp
    val config = LocalConfiguration.current
    val density = LocalDensity.current
    val playUrl = remember(post.id, post.mediaUrl) {
        post.playableVideoUrl ?: MediaUrlResolver.videoUrl(post)
    }

    BoxWithConstraints(modifier.fillMaxWidth()) {
        val widthPx = with(density) { maxWidth.toPx() }
        val screenH = with(density) { config.screenHeightDp.dp.toPx() }
        val heightPx = FacebookMediaLayout.dominantFeedVideoHeight(widthPx, screenH)
        val heightDp = with(density) { heightPx.toDp() }

        Box(
            Modifier
                .fillMaxWidth()
                .height(heightDp)
                .clip(RoundedCornerShape(corner))
                .clipToBounds()
                .background(MatteryaColors.canvasDeep)
                .clickable(onClick = onOpen),
        ) {
            if (playUrl != null) {
                InFrameVideoPlayer(
                    post = post,
                    url = playUrl,
                    posterUrl = post.posterImageUrl,
                    placement = null,
                    loops = true,
                    showsControls = true,
                    muteOnlyControls = false,
                    sharesFeedMute = true,
                    feedVideosMuted = feedVideosMuted,
                    onFeedVideosMutedChange = onFeedVideosMutedChange,
                    autoplaySurface = autoplaySurface,
                    surfaceLive = surfaceLive,
                    reelsOpen = reelsOpen,
                    hubPlaying = hubPlaying,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                VideoThumbnailView(
                    post = post,
                    maxLogicalPx = 480,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
                Icon(
                    Icons.Filled.PlayCircle,
                    contentDescription = "Play",
                    tint = Color.White.copy(alpha = 0.92f),
                    modifier = Modifier
                        .align(Alignment.Center)
                        .size(52.dp),
                )
            }

            // iOS HubsOriginBadge — top-leading capsule
            if (forceHubsBadge) {
                Text(
                    MatteryaCopy.matteryaHubs,
                    color = Color.White,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    letterSpacing = 0.2.sp,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(10.dp)
                        .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(999.dp))
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }
        }
    }
}
