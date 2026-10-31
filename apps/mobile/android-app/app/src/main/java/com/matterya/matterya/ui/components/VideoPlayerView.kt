package com.matterya.matterya.ui.components

import android.graphics.Color as AndroidColor
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.ui.ads.AdPrerollView
import kotlinx.coroutines.delay

/**
 * ExoPlayer Compose wrapper — mirrors iOS `VideoPlayerView`:
 * poster cover once until first frame, crop/fill gravity, no mid-play poster flash.
 */
@Composable
fun VideoPlayerView(
    url: String?,
    posterUrl: String? = null,
    modifier: Modifier = Modifier,
    placement: String? = null,
    countryCode: String? = null,
    contentCountryCode: String? = null,
    postId: String? = null,
    adsEnabled: Boolean = true,
    isActive: Boolean = true,
    loops: Boolean = false,
    muted: Boolean = false,
    showsControls: Boolean = false,
    allowsFullscreen: Boolean = false,
    startTime: Double? = null,
    fillsFrame: Boolean = true,
    isPausedByUser: Boolean = false,
    restartFromBeginningToken: Int = 0,
    seekToSeconds: Double? = null,
    onSeekConsumed: (() -> Unit)? = null,
    onProgress: ((currentSeconds: Double, durationSeconds: Double) -> Unit)? = null,
    onViewed: (() -> Unit)? = null,
    onFullscreen: (() -> Unit)? = null,
    onVideoSize: ((width: Int, height: Int) -> Unit)? = null,
) {
    val context = LocalContext.current
    var adFinished by remember(url, placement) { mutableStateOf(!adsEnabled || placement == null) }
    var showChrome by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(false) }
    var isMuted by remember(muted) { mutableStateOf(muted) }
    var currentMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }
    // Poster only until the first ready frame — never re-flash on seek/restart (iOS).
    var showPosterCover by remember(url) { mutableStateOf(true) }
    var hasRenderedFrame by remember(url) { mutableStateOf(false) }
    var loadFailed by remember(url) { mutableStateOf(false) }

    val progressCb by rememberUpdatedState(onProgress)
    val viewedCb by rememberUpdatedState(onViewed)
    val videoSizeCb by rememberUpdatedState(onVideoSize)
    val seekConsumedCb by rememberUpdatedState(onSeekConsumed)

    val shouldShowAd = adsEnabled && isActive && !adFinished && placement != null

    val player = remember(url) {
        if (url.isNullOrBlank()) {
            null
        } else {
            try {
                ExoPlayer.Builder(context).build().apply {
                    setMediaItem(MediaItem.fromUri(url))
                    repeatMode = if (loops) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                    volume = if (muted) 0f else 1f
                    // Crop to fill — matches iOS AVLayerVideoGravity.resizeAspectFill.
                    videoScalingMode =
                        androidx.media3.common.C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING
                    prepare()
                }
            } catch (_: Throwable) {
                null
            }
        }
    }

    LaunchedEffect(player) {
        val p = player ?: return@LaunchedEffect
        while (true) {
            val err = p.playerError
            if (err != null) {
                loadFailed = true
                showPosterCover = true
                runCatching { p.pause() }
            }
            val vs: VideoSize = p.videoSize
            if (vs.width > 2 && vs.height > 2) {
                videoSizeCb?.invoke(vs.width, vs.height)
            }
            delay(400)
        }
    }

    DisposableEffect(player) {
        onDispose {
            try {
                player?.stop()
                player?.clearMediaItems()
                player?.release()
            } catch (_: Throwable) {
            }
        }
    }

    LaunchedEffect(isActive, isPausedByUser, player, shouldShowAd) {
        val p = player ?: return@LaunchedEffect
        if (shouldShowAd) {
            p.pause()
            return@LaunchedEffect
        }
        when {
            !isActive -> p.pause()
            isPausedByUser -> p.pause()
            else -> p.play()
        }
    }

    LaunchedEffect(isMuted, player) {
        player?.volume = if (isMuted) 0f else 1f
    }

    // Restart seek only — do NOT re-show poster (that caused Sparks blinking).
    LaunchedEffect(restartFromBeginningToken, player) {
        if (restartFromBeginningToken > 0) {
            runCatching {
                player?.seekTo(0)
                if (isActive && !isPausedByUser && !shouldShowAd) player?.play()
            }
        }
    }

    LaunchedEffect(seekToSeconds, player) {
        val seek = seekToSeconds ?: return@LaunchedEffect
        player?.seekTo((seek * 1000).toLong())
        seekConsumedCb?.invoke()
    }

    LaunchedEffect(startTime, player) {
        val start = startTime ?: return@LaunchedEffect
        player?.seekTo((start * 1000).toLong())
    }

    LaunchedEffect(player, isActive) {
        val p = player ?: return@LaunchedEffect
        var reportedView = false
        while (true) {
            currentMs = p.currentPosition
            durationMs = p.duration.coerceAtLeast(0)
            isPlaying = p.isPlaying
            if (p.playbackState == Player.STATE_READY &&
                (p.currentPosition > 40 || p.bufferedPosition > 0)
            ) {
                hasRenderedFrame = true
                showPosterCover = false
            }
            if (p.playerError != null) loadFailed = true
            if (!reportedView && p.currentPosition > 500 && isActive) {
                reportedView = true
                viewedCb?.invoke()
            }
            progressCb?.invoke(currentMs / 1000.0, durationMs / 1000.0)
            delay(250)
        }
    }

    LaunchedEffect(showChrome, showsControls, isPlaying) {
        if (!showsControls || !showChrome || !isPlaying) return@LaunchedEffect
        delay(2800)
        showChrome = false
    }

    val resizeMode = if (fillsFrame) {
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM
    } else {
        AspectRatioFrameLayout.RESIZE_MODE_FIT
    }
    val imageScale = if (fillsFrame) ContentScale.Crop else ContentScale.Fit

    Box(
        modifier
            .clipToBounds()
            .background(Color.Black)
            .clickable(enabled = showsControls) {
                showChrome = !showChrome
            },
    ) {
        // Static underlay (no crossfade — avoids blink on recompose).
        if (!posterUrl.isNullOrBlank() && (showPosterCover || !hasRenderedFrame)) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(posterUrl)
                    .crossfade(false)
                    .build(),
                contentDescription = null,
                contentScale = imageScale,
                modifier = Modifier.fillMaxSize(),
            )
        }

        when {
            shouldShowAd && placement != null -> {
                AdPrerollView(
                    placement = placement,
                    countryCode = countryCode,
                    contentCountryCode = contentCountryCode,
                    postId = postId,
                    onComplete = { adFinished = true },
                    modifier = Modifier.fillMaxSize(),
                )
            }
            player != null && !loadFailed -> {
                AndroidView(
                    factory = { ctx ->
                        PlayerView(ctx).apply {
                            useController = false
                            // ZOOM = aspectFill (crop); FIT = letterbox. Sparks always want ZOOM.
                            this.resizeMode = resizeMode
                            setShutterBackgroundColor(AndroidColor.BLACK)
                            setBackgroundColor(AndroidColor.BLACK)
                            // Hide default artwork that can flash over frames.
                            defaultArtwork = null
                            artworkDisplayMode = PlayerView.ARTWORK_DISPLAY_MODE_OFF
                            this.player = player
                            layoutParams = FrameLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT,
                            )
                            // Critical for crop: clip surface to view bounds (otherwise letterbox shows).
                            clipChildren = true
                            clipToPadding = true
                            clipToOutline = true
                        }
                    },
                    update = { view ->
                        if (view.player !== player) view.player = player
                        if (view.resizeMode != resizeMode) {
                            view.resizeMode = resizeMode
                        }
                        // Force aspect-ratio frame child to match parent so ZOOM actually crops.
                        (view.getChildAt(0) as? android.view.ViewGroup)?.let { content ->
                            content.layoutParams = content.layoutParams?.apply {
                                width = ViewGroup.LayoutParams.MATCH_PARENT
                                height = ViewGroup.LayoutParams.MATCH_PARENT
                            } ?: FrameLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT,
                            )
                        }
                    },
                    modifier = Modifier
                        .fillMaxSize()
                        .clipToBounds(),
                )
            }
            loadFailed -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Video unavailable", color = Color.White.copy(alpha = 0.8f), fontSize = 13.sp)
                }
            }
        }

        if (showsControls && showChrome && player != null && !shouldShowAd) {
            MatteryaVideoControls(
                isPlaying = isPlaying && !isPausedByUser,
                isMuted = isMuted,
                currentSeconds = currentMs / 1000.0,
                durationSeconds = durationMs / 1000.0,
                showsFullscreen = allowsFullscreen,
                onPlayPause = {
                    if (player.isPlaying) player.pause() else player.play()
                    showChrome = true
                },
                onMuteToggle = {
                    isMuted = !isMuted
                    showChrome = true
                },
                onSeek = { sec ->
                    player.seekTo((sec * 1000).toLong())
                    showChrome = true
                },
                onFullscreen = if (allowsFullscreen) onFullscreen else null,
            )
        }
    }
}

@Composable
fun MatteryaVideoControls(
    isPlaying: Boolean,
    isMuted: Boolean,
    currentSeconds: Double,
    durationSeconds: Double,
    showsFullscreen: Boolean,
    onPlayPause: () -> Unit,
    onMuteToggle: () -> Unit,
    onSeek: (Double) -> Unit,
    onFullscreen: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    var scrub by remember(currentSeconds) { mutableFloatStateOf(currentSeconds.toFloat()) }
    val duration = durationSeconds.toFloat().coerceAtLeast(0.1f)

    Box(
        modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f)),
                ),
            ),
    ) {
        IconButton(
            onClick = onPlayPause,
            modifier = Modifier
                .align(Alignment.Center)
                .size(56.dp)
                .background(Color.Black.copy(alpha = 0.45f), CircleShape),
        ) {
            Icon(
                if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                contentDescription = if (isPlaying) "Pause" else "Play",
                tint = Color.White,
                modifier = Modifier.size(32.dp),
            )
        }

        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
        ) {
            Slider(
                value = scrub.coerceIn(0f, duration),
                onValueChange = { scrub = it },
                onValueChangeFinished = { onSeek(scrub.toDouble()) },
                valueRange = 0f..duration,
                colors = SliderDefaults.colors(
                    thumbColor = Color.White,
                    activeTrackColor = MatteryaColors.accentBright,
                    inactiveTrackColor = Color.White.copy(alpha = 0.35f),
                ),
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    "${formatTime(currentSeconds)} / ${formatTime(durationSeconds)}",
                    color = Color.White,
                    fontSize = 11.sp,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onMuteToggle, modifier = Modifier.size(36.dp)) {
                        Icon(
                            if (isMuted) Icons.Default.VolumeOff else Icons.Default.VolumeUp,
                            contentDescription = "Mute",
                            tint = Color.White,
                        )
                    }
                    if (showsFullscreen && onFullscreen != null) {
                        IconButton(onClick = onFullscreen, modifier = Modifier.size(36.dp)) {
                            Icon(Icons.Default.Fullscreen, contentDescription = "Fullscreen", tint = Color.White)
                        }
                    }
                }
            }
        }
    }
}

private fun formatTime(seconds: Double): String {
    if (seconds.isNaN() || seconds < 0) return "0:00"
    val total = seconds.toInt()
    val m = total / 60
    val s = total % 60
    return "%d:%02d".format(m, s)
}
