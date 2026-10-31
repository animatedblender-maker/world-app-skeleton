package com.matterya.matterya.ui.living

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.YouTubeMediaLayout
import com.matterya.matterya.theme.YouTubeMiniPlayerBar
import com.matterya.matterya.ui.components.VideoPlayerView

/**
 * iOS `GlobalHubPlaybackLayer` — single continuous ExoPlayer surface for Hubs.
 * Expanded = 16:9 watch stage; minimized = mini bar (player keeps running).
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

        // Stable player id — same surface for expand ↔ mini so playback continues.
        val playerKey = "global-hub-continuous-${post.id}"

        if (expanded) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(stageH.coerceAtLeast(120.dp))
                    .align(Alignment.TopCenter)
                    .background(Color.Black),
            ) {
                VideoPlayerView(
                    url = post.playableVideoUrl,
                    posterUrl = post.posterImageUrl,
                    placement = "hubs_preroll",
                    adsEnabled = true,
                    isActive = isPlaying,
                    muted = isMuted,
                    showsControls = true,
                    fillsFrame = true,
                    onProgress = onProgress,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        } else {
            // Hidden continuous player keeps decoding while mini chrome shows
            Box(Modifier.height(0.dp)) {
                VideoPlayerView(
                    url = post.playableVideoUrl,
                    posterUrl = post.posterImageUrl,
                    adsEnabled = false,
                    isActive = isPlaying,
                    muted = isMuted,
                    showsControls = false,
                    fillsFrame = true,
                    onProgress = onProgress,
                    modifier = Modifier.height(1.dp),
                )
            }
            YouTubeMiniPlayerBar(
                post = post,
                isPlaying = isPlaying,
                isMuted = isMuted,
                onExpand = onExpand,
                onClose = onClose,
                onTogglePlay = onTogglePlay,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
        @Suppress("UNUSED_VARIABLE")
        val _key = playerKey
    }
}
