package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.matterya.matterya.data.media.FeedAutoplaySurface
import com.matterya.matterya.data.media.FeedVideoFocus
import com.matterya.matterya.model.CountryPost
import kotlin.math.max
import kotlin.math.min

/**
 * iOS `InFrameVideoPlayer` — feed/profile autoplay slot.
 *
 * - Exactly one winner via [FeedVideoFocus] (≥30% visible)
 * - Always **fillsFrame / Crop / ZOOM** (no letterbox)
 * - Optional mute-only chrome (Sparks feed) sharing app-wide feed mute
 */
@Composable
fun InFrameVideoPlayer(
    post: CountryPost,
    url: String,
    modifier: Modifier = Modifier,
    posterUrl: String? = post.posterImageUrl,
    placement: String? = null,
    loops: Boolean = true,
    showsControls: Boolean = false,
    muteOnlyControls: Boolean = false,
    sharesFeedMute: Boolean = true,
    feedVideosMuted: Boolean = false,
    onFeedVideosMutedChange: (Boolean) -> Unit = {},
    autoplaySurface: FeedAutoplaySurface = FeedAutoplaySurface.Home,
    surfaceLive: Boolean = true,
    reelsOpen: Boolean = false,
    hubPlaying: Boolean = false,
    onViewed: (() -> Unit)? = null,
) {
    val focus = remember { FeedVideoFocus.shared }
    val activeId by focus.activeId.collectAsState()
    val focusId = remember(post.id, autoplaySurface) {
        "${autoplaySurface.name}:${post.id}"
    }
    val isFocusWinner = activeId == focusId
    val shouldPlay = isFocusWinner &&
        surfaceLive &&
        !reelsOpen &&
        !hubPlaying

    var localMuted by remember(sharesFeedMute, feedVideosMuted) {
        mutableStateOf(if (sharesFeedMute) feedVideosMuted else false)
    }
    val effectiveMuted = if (sharesFeedMute) feedVideosMuted else localMuted

    val density = LocalDensity.current
    val config = LocalConfiguration.current
    val screenH = with(density) { config.screenHeightDp.dp.toPx() }
    val screenW = with(density) { config.screenWidthDp.dp.toPx() }

    Box(
        modifier
            .fillMaxSize()
            .background(Color.Black)
            .onGloballyPositioned { coords ->
                val bounds: Rect = coords.boundsInWindow()
                // Visible fraction of this card inside the screen window.
                val visibleTop = max(0f, bounds.top)
                val visibleBottom = min(screenH, bounds.bottom)
                val visibleLeft = max(0f, bounds.left)
                val visibleRight = min(screenW, bounds.right)
                val visH = max(0f, visibleBottom - visibleTop)
                val visW = max(0f, visibleRight - visibleLeft)
                val area = max(1f, bounds.height * bounds.width)
                val ratio = (visH * visW) / area
                // Only count if mostly on-screen horizontally too.
                if (bounds.width < 8f || bounds.height < 8f) {
                    focus.clear(focusId)
                } else {
                    focus.reportVisibility(focusId, ratio)
                }
            },
    ) {
        DisposableEffect(focusId) {
            onDispose { focus.clear(focusId) }
        }

        VideoPlayerView(
            url = url,
            posterUrl = posterUrl,
            placement = placement,
            countryCode = post.countryCode,
            contentCountryCode = post.countryCode,
            postId = post.id,
            adsEnabled = false,
            isActive = shouldPlay,
            loops = loops,
            muted = effectiveMuted,
            showsControls = showsControls && !muteOnlyControls && shouldPlay,
            fillsFrame = true, // iOS: full-bleed fill — never black bars
            onViewed = onViewed,
            modifier = Modifier.fillMaxSize(),
        )

        // Mute-only chip (Sparks feed) — top trailing, leaves 52dp strip free for mute hit.
        if (muteOnlyControls) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .size(36.dp)
                    .background(Color.Black.copy(alpha = 0.35f), CircleShape)
                    .clickable {
                        val next = !effectiveMuted
                        if (sharesFeedMute) onFeedVideosMutedChange(next)
                        else localMuted = next
                    },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (effectiveMuted) Icons.Filled.VolumeOff else Icons.Filled.VolumeUp,
                    contentDescription = if (effectiveMuted) "Unmute" else "Mute",
                    tint = Color.White,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}
