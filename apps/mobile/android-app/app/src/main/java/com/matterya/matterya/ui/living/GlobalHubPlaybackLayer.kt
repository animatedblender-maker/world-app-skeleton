package com.matterya.matterya.ui.living

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.matterya.matterya.data.media.HubContinuousDockSlot
import com.matterya.matterya.data.media.MediaPlaybackCoordinator
import com.matterya.matterya.data.reels.MatteryaPullDownDismiss
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaMotion
import com.matterya.matterya.theme.YouTubeMediaLayout
import com.matterya.matterya.theme.YouTubeMiniPlayerBar
import com.matterya.matterya.ui.components.VideoPlayerView
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/**
 * iOS `GlobalHubPlaybackLayer` — single continuous ExoPlayer for Hubs.
 * Expand ↔ mini only resizes the same surface (ytMorph easeOut ~0.22).
 * Pull-down on expanded stage minimizes; landscape FS uses aspect-fit letterbox.
 * [protectAsContinuous] spares audio across tab hops.
 */
@Composable
fun GlobalHubPlaybackLayer(
    post: CountryPost?,
    expanded: Boolean,
    isPlaying: Boolean,
    isMuted: Boolean,
    landscapeFullscreen: Boolean = false,
    pullProgress: Float = 0f,
    bottomClearance: Dp = 0.dp,
    /** Chat owns mini chrome+hole — hide floating bar chrome; film docks into slot. */
    dockInChat: Boolean = false,
    onTogglePlay: () -> Unit = {},
    onExpand: () -> Unit = {},
    onClose: () -> Unit = {},
    onProgress: (Double, Double) -> Unit = { _, _ -> },
    onPullProgress: (Float) -> Unit = {},
    onPullEnd: (Float) -> Unit = {},
    onRequestFullscreen: () -> Unit = {},
    onExitFullscreen: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    if (post == null) return

    val context = LocalContext.current
    val morph = tween<Dp>(
        durationMillis = MatteryaMotion.ytMorphMs,
        easing = MatteryaMotion.ytMorphEasing,
    )
    val morphInt = tween<Float>(
        durationMillis = MatteryaMotion.ytMorphMs,
        easing = MatteryaMotion.ytMorphEasing,
    )

    // Orientation lock for landscape FS — restore on exit / dispose.
    DisposableEffect(landscapeFullscreen) {
        val activity = context.findActivity()
        if (landscapeFullscreen) {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        } else {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        onDispose {
            if (landscapeFullscreen) {
                activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }
        }
    }

    if (landscapeFullscreen) {
        BackHandler { onExitFullscreen() }
    }

    // Mini + playing: keep Exo rolling after morph/tab silence (chrome can show ❚❚ while paused).
    LaunchedEffect(expanded, landscapeFullscreen, isPlaying, post.id) {
        if (!expanded && !landscapeFullscreen && isPlaying) {
            delay(260)
            MediaPlaybackCoordinator.shared.ensureContinuingHubsPlayback(userMuted = isMuted)
        }
    }

    var dragOffsetPx by remember { mutableFloatStateOf(0f) }
    var isPulling by remember { mutableStateOf(false) }
    val dragState = remember { MatteryaPullDownDismiss.DragState() }
    val onPullProgressLatest by rememberUpdatedState(onPullProgress)
    val onPullEndLatest by rememberUpdatedState(onPullEnd)
    val pullProgressLatest by rememberUpdatedState(pullProgress)

    // Snap local drag back when session leaves expanded (minimize / stop / FS).
    DisposableEffect(expanded, landscapeFullscreen) {
        if (!expanded || landscapeFullscreen) {
            dragOffsetPx = 0f
            isPulling = false
            dragState.offset = 0f
            dragState.isDragging = false
        }
        onDispose { }
    }

    val localPull = MatteryaPullDownDismiss.pullProgressForOffset(dragOffsetPx)
    val effectivePull = maxOf(localPull, pullProgress).coerceIn(0f, 1f)
    val pullScale = if (expanded && !landscapeFullscreen && (isPulling || dragOffsetPx > 1f)) {
        1f - effectivePull * 0.12f
    } else {
        1f
    }
    val pullYPx = if (expanded && !landscapeFullscreen && (isPulling || dragOffsetPx > 1f)) {
        dragOffsetPx * 0.92f
    } else {
        0f
    }

    fun applyPullTranslation(totalY: Float) {
        MatteryaPullDownDismiss.applyChanged(
            translationX = 0f,
            translationY = totalY,
            state = dragState,
        )
        if (dragState.isDragging) {
            dragOffsetPx = dragState.offset
            isPulling = true
            val progress = MatteryaPullDownDismiss.pullProgressForOffset(dragOffsetPx)
            val previous = pullProgressLatest
            if (previous < 0.05f && progress >= 0.05f) {
                onPullProgressLatest(0.05f)
            }
        } else if (totalY <= 0f) {
            dragOffsetPx = 0f
            isPulling = false
            if (pullProgressLatest > 0f) onPullProgressLatest(0f)
        }
    }

    fun finishPull(totalY: Float) {
        val y = maxOf(dragOffsetPx, dragState.offset, totalY)
        val progress = MatteryaPullDownDismiss.pullProgressForOffset(y)
        isPulling = false
        onPullEndLatest(progress)
        val commit = MatteryaPullDownDismiss.shouldMinimizeOnRelease(
            translationY = y,
            predictedY = y,
            dragOffset = y,
            pullProgress = progress,
        )
        if (!commit) {
            dragOffsetPx = 0f
            dragState.offset = 0f
            dragState.isDragging = false
        }
    }

    fun cancelPull() {
        isPulling = false
        dragOffsetPx = 0f
        dragState.offset = 0f
        dragState.isDragging = false
        onPullProgressLatest(0f)
    }

    var layerBoundsInWindow by remember { mutableStateOf<androidx.compose.ui.geometry.Rect?>(null) }

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .onGloballyPositioned { layerBoundsInWindow = it.boundsInWindow() },
    ) {
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

        // iOS: prefer exact dock-slot hole when chat (or floating bar) reports it.
        val dockFrame = HubContinuousDockSlot.frameInWindow
        val layerFrame = layerBoundsInWindow
        val dockedLayout = if (!expanded && !landscapeFullscreen &&
            dockFrame != null && layerFrame != null &&
            dockFrame.width > 8f && dockFrame.height > 8f
        ) {
            val x = dockFrame.left - layerFrame.left
            val y = dockFrame.top - layerFrame.top
            val inBottomBand = y >= heightPx * 0.45f
            val looksLikeMini = dockFrame.height > 40f &&
                dockFrame.height < heightPx * 0.42f &&
                dockFrame.width > 40f &&
                (inBottomBand || dockInChat)
            if (looksLikeMini &&
                y > -20f && y < heightPx + 20f &&
                x > -20f && x < widthPx + 20f
            ) {
                Triple(
                    with(density) { dockFrame.width.toDp() },
                    with(density) { dockFrame.height.toDp() },
                    with(density) { x.toDp() } to with(density) { y.toDp() },
                )
            } else {
                null
            }
        } else {
            null
        }

        val targetW = when {
            landscapeFullscreen -> maxWidth
            expanded -> maxWidth
            dockedLayout != null -> dockedLayout.first
            else -> thumbW
        }
        val targetH = when {
            landscapeFullscreen -> maxHeight
            expanded -> stageH
            dockedLayout != null -> dockedLayout.second
            else -> thumbH
        }
        val targetX = when {
            landscapeFullscreen || expanded -> 0.dp
            dockedLayout != null -> dockedLayout.third.first
            else -> thumbPad
        }
        val targetY = when {
            landscapeFullscreen -> 0.dp
            expanded -> 0.dp
            dockedLayout != null -> dockedLayout.third.second
            else -> (maxHeight - bottomClearance - miniBarH + thumbTopInset).coerceAtLeast(0.dp)
        }
        val playerW by animateDpAsState(
            targetValue = targetW,
            animationSpec = morph,
            label = "hubPlayerW",
        )
        val playerH by animateDpAsState(
            targetValue = targetH,
            animationSpec = morph,
            label = "hubPlayerH",
        )
        val playerX by animateDpAsState(
            targetValue = targetX,
            animationSpec = morph,
            label = "hubPlayerX",
        )
        val playerY by animateDpAsState(
            targetValue = targetY,
            animationSpec = morph,
            label = "hubPlayerY",
        )
        val corner by animateDpAsState(
            targetValue = when {
                landscapeFullscreen -> 0.dp
                expanded && isPulling -> 12.dp
                expanded -> 0.dp
                else -> 6.dp
            },
            animationSpec = morph,
            label = "hubPlayerR",
        )
        val animatedPullScale by animateFloatAsState(
            targetValue = pullScale,
            animationSpec = if (isPulling) tween(0) else morphInt,
            label = "hubPullScale",
        )

        // Cheap ink dim while expanded (iOS morph scrim — flat ink, no material blur).
        if (expanded && !landscapeFullscreen) {
            val scrimAlpha = (0.04f + effectivePull * 0.18f).coerceIn(0.04f, 0.22f)
            Box(
                Modifier
                    .fillMaxSize()
                    .background(MatteryaColors.ink.copy(alpha = scrimAlpha)),
            )
        }

        // Mini chrome under continuous thumb (hole via showsThumbnail=false).
        // Chat dock owns its own bar — skip floating chrome to avoid double strip.
        AnimatedVisibility(
            visible = !expanded && !landscapeFullscreen && !dockInChat,
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
                reportDockSlot = true,
            )
        }
        // One continuous ExoPlayer — never remount on expand↔mini / FS.
        // Mini: skip graphicsLayer/clip on the AndroidView ancestor — Compose clip +
        // TextureView blanks the surface at thumb size (static black hole).
        val mini = !expanded && !landscapeFullscreen
        val pullingScale = expanded && !landscapeFullscreen &&
            (isPulling || animatedPullScale < 0.999f)
        Box(
            Modifier
                .offset(x = playerX, y = playerY)
                .offset { IntOffset(0, pullYPx.roundToInt()) }
                .size(playerW, playerH)
                .then(
                    if (pullingScale) {
                        Modifier.graphicsLayer {
                            scaleX = animatedPullScale
                            scaleY = animatedPullScale
                            transformOrigin = TransformOrigin(0.5f, 0f)
                        }
                    } else {
                        Modifier
                    },
                )
                .then(
                    if (mini) Modifier
                    else Modifier.clip(RoundedCornerShape(corner)),
                )
                .background(if (mini) Color.Transparent else Color.Black)
                .then(
                    if (mini) Modifier.clickable(onClick = onExpand)
                    else Modifier,
                ),
        ) {
            val pullEnabled = expanded && !landscapeFullscreen
            VideoPlayerView(
                url = post.playableVideoUrl,
                posterUrl = post.posterImageUrl,
                postId = post.id,
                placement = if (expanded && !landscapeFullscreen) "hubs_preroll" else null,
                adsEnabled = expanded && !landscapeFullscreen,
                isActive = isPlaying,
                loops = true,
                muted = isMuted,
                showsControls = (expanded || landscapeFullscreen) && !isPulling,
                allowsFullscreen = expanded || landscapeFullscreen,
                // Hubs continuous: always aspect-fit (letterbox). Never crop in FS.
                fillsFrame = false,
                protectAsContinuous = true,
                onProgress = onProgress,
                onFullscreen = {
                    if (landscapeFullscreen) onExitFullscreen() else onRequestFullscreen()
                },
                onPullDrag = if (pullEnabled) { y -> applyPullTranslation(y) } else null,
                onPullDragEnd = if (pullEnabled) { y -> finishPull(y) } else null,
                onPullDragCancel = if (pullEnabled) { { cancelPull() } } else null,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

private fun Context.findActivity(): Activity? {
    var ctx: Context = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}
