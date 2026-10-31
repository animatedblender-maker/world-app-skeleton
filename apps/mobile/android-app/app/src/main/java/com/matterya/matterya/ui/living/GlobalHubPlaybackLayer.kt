package com.matterya.matterya.ui.living

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.YouTubeMediaLayout
import com.matterya.matterya.theme.YouTubeMiniPlayerBar
import com.matterya.matterya.ui.components.VideoPlayerView

/**
 * iOS `GlobalHubPlaybackLayer` — single continuous ExoPlayer surface for Hubs.
 * Expanded = 16:9 watch stage; minimized = mini bar (same player keeps running).
 * [protectAsContinuous] spares audio across tab hops.
 */
@Composable
fun GlobalHubPlaybackLayer(
    post: CountryPost?,
    expanded: Boolean,
    isPlaying: Boolean,
    isMuted: Boolean,
    onTogglePlay: () -> Unit = {},
    onExpand: () -> Unit = {},
    onClose: () -> Unit = {},
    onProgress: (Double, Double) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier,
) {
    if (post == null) return

    BoxWithConstraints(modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        val stageH = with(density) {
            YouTubeMediaLayout.hubsExpandedStageHeight(widthPx, heightPx).toDp()
        }

        // One continuous player for expand ↔ mini (never remount on morph).
        Box(
            Modifier
                .fillMaxWidth()
                .then(
                    if (expanded) {
                        Modifier
                            .height(stageH.coerceAtLeast(120.dp))
                            .align(Alignment.TopCenter)
                    } else {
                        Modifier
                            .height(1.dp)
                            .alpha(0f)
                    },
                )
                .background(Color.Black),
        ) {
            VideoPlayerView(
                url = post.playableVideoUrl,
                posterUrl = post.posterImageUrl,
                placement = if (expanded) "hubs_preroll" else null,
                adsEnabled = expanded,
                isActive = isPlaying,
                muted = isMuted,
                showsControls = expanded,
                fillsFrame = true,
                protectAsContinuous = true,
                onProgress = onProgress,
                modifier = Modifier.fillMaxSize(),
            )
        }

        AnimatedVisibility(
            visible = !expanded,
            enter = fadeIn(tween(180)) + slideInVertically(tween(220)) { it / 3 },
            exit = fadeOut(tween(140)) + slideOutVertically(tween(180)) { it / 4 },
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            YouTubeMiniPlayerBar(
                post = post,
                isPlaying = isPlaying,
                isMuted = isMuted,
                onExpand = onExpand,
                onClose = onClose,
                onTogglePlay = onTogglePlay,
            )
        }
    }
}
