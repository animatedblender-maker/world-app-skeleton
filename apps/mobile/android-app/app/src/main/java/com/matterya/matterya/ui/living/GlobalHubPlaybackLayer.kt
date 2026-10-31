package com.matterya.matterya.ui.living

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaMotion
import com.matterya.matterya.theme.YouTubeMediaLayout
import com.matterya.matterya.theme.YouTubeMiniPlayerBar
import com.matterya.matterya.ui.components.VideoPlayerView

/**
 * iOS `GlobalHubPlaybackLayer` — single continuous ExoPlayer for Hubs.
 * Expand ↔ mini only resizes the same surface (ytMorph easeOut ~0.22).
 * [protectAsContinuous] spares audio across tab hops.
 */
@Composable
fun GlobalHubPlaybackLayer(
    post: CountryPost?,
    expanded: Boolean,
    isPlaying: Boolean,
    isMuted: Boolean,
    bottomClearance: Dp = 0.dp,
    onTogglePlay: () -> Unit = {},
    onExpand: () -> Unit = {},
    onClose: () -> Unit = {},
    onProgress: (Double, Double) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier,
) {
    if (post == null) return

    val morph = tween<Dp>(
        durationMillis = MatteryaMotion.ytMorphMs,
        easing = MatteryaMotion.ytMorphEasing,
    )
    val morphInt = tween<Float>(
        durationMillis = MatteryaMotion.ytMorphMs,
        easing = MatteryaMotion.ytMorphEasing,
    )

    BoxWithConstraints(modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        val stageH = with(density) {
            YouTubeMediaLayout.hubsExpandedStageHeight(widthPx, heightPx).toDp()
        }.coerceAtLeast(120.dp)

        val miniBarH = 56.dp
        val thumbW = 72.dp
        val thumbH = 40.dp
        val thumbPad = 10.dp
        val thumbTopInset = ((miniBarH - thumbH) / 2)

        val playerW by animateDpAsState(
            targetValue = if (expanded) maxWidth else thumbW,
            animationSpec = morph,
            label = "hubPlayerW",
        )
        val playerH by animateDpAsState(
            targetValue = if (expanded) stageH else thumbH,
            animationSpec = morph,
            label = "hubPlayerH",
        )
        val playerX by animateDpAsState(
            targetValue = if (expanded) 0.dp else thumbPad,
            animationSpec = morph,
            label = "hubPlayerX",
        )
        val playerY by animateDpAsState(
            targetValue = if (expanded) {
                0.dp
            } else {
                (maxHeight - bottomClearance - miniBarH + thumbTopInset).coerceAtLeast(0.dp)
            },
            animationSpec = morph,
            label = "hubPlayerY",
        )
        val corner by animateDpAsState(
            targetValue = if (expanded) 0.dp else 6.dp,
            animationSpec = morph,
            label = "hubPlayerR",
        )

        // Cheap ink dim while expanded (iOS morph scrim — flat ink, no material blur).
        if (expanded) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(MatteryaColors.ink.copy(alpha = 0.04f)),
            )
        }

        // Mini chrome under the continuous thumb (hole via showsThumbnail=false).
        AnimatedVisibility(
            visible = !expanded,
            enter = fadeIn(morphInt),
            exit = fadeOut(tween(140, easing = MatteryaMotion.ytMorphEasing)),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = bottomClearance),
        ) {
            YouTubeMiniPlayerBar(
                post = post,
                isPlaying = isPlaying,
                isMuted = isMuted,
                onExpand = onExpand,
                onClose = onClose,
                onTogglePlay = onTogglePlay,
                showsThumbnail = false,
            )
        }

        // One continuous ExoPlayer — never remount on expand↔mini.
        Box(
            Modifier
                .offset(x = playerX, y = playerY)
                .size(playerW, playerH)
                .clip(RoundedCornerShape(corner))
                .background(Color.Black)
                .then(
                    if (!expanded) Modifier.clickable(onClick = onExpand)
                    else Modifier,
                ),
        ) {
            VideoPlayerView(
                url = post.playableVideoUrl,
                posterUrl = post.posterImageUrl,
                postId = post.id,
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
    }
}
