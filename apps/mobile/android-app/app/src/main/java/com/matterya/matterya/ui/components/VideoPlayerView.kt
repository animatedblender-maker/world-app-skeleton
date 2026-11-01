package com.matterya.matterya.ui.components

import android.graphics.Color as AndroidColor
import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
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
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.input.pointer.pointerInput
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
import com.matterya.matterya.R
import com.matterya.matterya.data.media.MediaPlaybackCoordinator
import com.matterya.matterya.data.media.SparkWarmPool
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.ui.ads.AdPrerollView
import kotlinx.coroutines.awaitCancellation
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
    /** Mark as continuous Hubs player so tab silence spares this ExoPlayer. */
    protectAsContinuous: Boolean = false,
    /** Absolute downward pull px while dragging (Hubs expand → mini). Same node as clickable. */
    onPullDrag: ((translationY: Float) -> Unit)? = null,
    onPullDragEnd: ((translationY: Float) -> Unit)? = null,
    onPullDragCancel: (() -> Unit)? = null,
    /**
     * Feed→Sparks mid-clip open — keep stage floor transparent from first composition
     * (before claim flips [claimedContinuing]) so mount never paints black.
     */
    continueHandoff: Boolean = false,
) {
    val context = LocalContext.current
    var adFinished by remember(url, placement) { mutableStateOf(!adsEnabled || placement == null) }
    var showChrome by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(false) }
    var isMuted by remember(muted) { mutableStateOf(muted) }
    var currentMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }
    // Poster until painted frames — never drop on readyToPlay alone (iOS blink fix).
    var showPosterCover by remember(url) { mutableStateOf(true) }
    var hasRenderedFrame by remember(url) { mutableStateOf(false) }
    /** Keep poster on top while seek-to-0 runs so Exo shutter never flashes black. */
    var isRestartSeeking by remember(url) { mutableStateOf(false) }
    var loadFailed by remember(url) { mutableStateOf(false) }
    var lastHandledRestartToken by remember(url) { mutableIntStateOf(0) }

    val progressCb by rememberUpdatedState(onProgress)
    val viewedCb by rememberUpdatedState(onViewed)
    val videoSizeCb by rememberUpdatedState(onVideoSize)
    val seekConsumedCb by rememberUpdatedState(onSeekConsumed)
    val loopsLatest by rememberUpdatedState(loops)
    val mutedLatest by rememberUpdatedState(muted)
    val onPullDragLatest by rememberUpdatedState(onPullDrag)
    val onPullDragEndLatest by rememberUpdatedState(onPullDragEnd)
    val onPullDragCancelLatest by rememberUpdatedState(onPullDragCancel)
    val isActiveLatest by rememberUpdatedState(isActive)
    val isPausedLatest by rememberUpdatedState(isPausedByUser)

    val shouldShowAd = adsEnabled && isActive && !adFinished && placement != null

    // Claim warm/continuing ExoPlayer first (iOS installClaimedPlayer); else cold-start.
    var player by remember(url) { mutableStateOf<ExoPlayer?>(null) }
    var handedOffToPool by remember(url) { mutableStateOf(false) }
    var claimedContinuing by remember(url) { mutableStateOf(false) }
    var handoffPaintNotified by remember(url) { mutableStateOf(false) }
    val handedOffLatest = rememberUpdatedState(handedOffToPool)

    // iOS shouldShowPosterCover: never cover just because !isPlaying; keep during restart seek.
    val shouldShowPosterCover =
        when {
            isPausedByUser && player != null && !isRestartSeeking -> false
            player == null -> true
            isRestartSeeking -> true
            else -> showPosterCover
        }

    LaunchedEffect(url, postId, protectAsContinuous) {
        if (url.isNullOrBlank()) {
            player = null
            return@LaunchedEffect
        }
        if (player != null || handedOffToPool) return@LaunchedEffect
        // Reclaim continuous Hubs Exo after VideoPlayerView remount (never release on dispose).
        if (protectAsContinuous) {
            val existing = MediaPlaybackCoordinator.shared.continuousHubPlayer as? ExoPlayer
            if (existing != null && existing.mediaItemCount > 0) {
                existing.repeatMode =
                    if (loopsLatest) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                existing.volume = if (mutedLatest) 0f else 1f
                showPosterCover = false
                hasRenderedFrame = true
                currentMs = existing.currentPosition
                MediaPlaybackCoordinator.shared.register(existing)
                MediaPlaybackCoordinator.shared.protectContinuous(existing)
                player = existing
                return@LaunchedEffect
            }
        }
        val pool = SparkWarmPool.shared
        val claimed = postId?.let { pool.claim(it) } ?: pool.claimFirstContinuing()
        if (claimed != null) {
            val wasContinuing = pool.takeLastClaimWasContinuing()
            val t0 = claimed.currentPosition / 1000.0
            val midClip = t0.isFinite() && t0 > 0.45
            claimed.repeatMode = if (loopsLatest) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            claimed.videoScalingMode =
                androidx.media3.common.C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING
            claimed.volume = if (mutedLatest) 0f else 1f
            claimedContinuing = wasContinuing && midClip
            if (claimedContinuing || midClip) {
                // Mid-clip Feed→Sparks: keep decoded frames, skip poster blink.
                showPosterCover = false
                hasRenderedFrame = true
                isRestartSeeking = false
                currentMs = claimed.currentPosition
                postId?.let {
                    pool.clearContinueFlag(it)
                    pool.takePlayheadSeconds(it)
                }
                // Surface just transferred — treat as painted once time proves (below).
                // Do NOT flip hasRenderedFrame false; Sparks stage stays see-through until progress.
            } else if (postId != null && pool.shouldContinueFromCurrentTime(postId)) {
                val head = pool.peekPlayheadSeconds(postId)
                if (head != null && head > 0.45) {
                    runCatching { claimed.seekTo((head * 1000).toLong()) }
                    currentMs = (head * 1000).toLong()
                    // Keep poster until paint proof after handoff seek.
                    isRestartSeeking = true
                    showPosterCover = true
                }
            } else if (claimed.playbackState == Player.STATE_READY &&
                claimed.bufferedPosition > 0
            ) {
                // Warm t≈0 claim: still wait for painted frames before dropping poster.
                showPosterCover = true
            }
            MediaPlaybackCoordinator.shared.register(claimed)
            // First frame on the NEW TextureView — not readyToPlay / playhead alone.
            if (claimedContinuing || midClip) {
                val paintOnce = java.util.concurrent.atomic.AtomicBoolean(false)
                val notifyId = postId
                claimed.addListener(object : Player.Listener {
                    override fun onRenderedFirstFrame() {
                        if (!paintOnce.compareAndSet(false, true)) return
                        handoffPaintNotified = true
                        showPosterCover = false
                        isRestartSeeking = false
                        hasRenderedFrame = true
                        notifyId?.let { SparkWarmPool.shared.notifyHandoffPainted(it) }
                        claimed.removeListener(this)
                    }
                })
            }
            player = claimed
            return@LaunchedEffect
        }
        try {
            val fresh = ExoPlayer.Builder(context).build().apply {
                setMediaItem(MediaItem.fromUri(url))
                repeatMode = if (loopsLatest) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                volume = if (mutedLatest) 0f else 1f
                videoScalingMode =
                    androidx.media3.common.C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING
                prepare()
            }
            MediaPlaybackCoordinator.shared.register(fresh)
            player = fresh
        } catch (_: Throwable) {
            player = null
            loadFailed = true
        }
    }

    // Live bind so AppState can sync-export before Sparks mounts.
    LaunchedEffect(player, postId) {
        val p = player
        val id = postId
        if (p == null || id.isNullOrBlank() || handedOffToPool) return@LaunchedEffect
        SparkWarmPool.shared.attachLive(id, p)
        try {
            kotlinx.coroutines.awaitCancellation()
        } finally {
            SparkWarmPool.shared.detachLive(id, p)
        }
    }

    // Detach when pool took our player via exportPlaybackForHandoff (do not release).
    LaunchedEffect(postId, url) {
        val id = postId ?: return@LaunchedEffect
        SparkWarmPool.shared.exportTaken.collect { taken ->
            if (id !in taken) return@collect
            if (handedOffToPool) return@collect
            handedOffToPool = true
            player = null
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

    DisposableEffect(player, protectAsContinuous, postId) {
        val p = player
        if (p != null) {
            MediaPlaybackCoordinator.shared.register(p)
            if (protectAsContinuous) {
                MediaPlaybackCoordinator.shared.protectContinuous(p)
            }
        }
        onDispose {
            try {
                // Continuous Hubs Exo survives VideoPlayerView remounts; stopHubPlayback releases.
                if (protectAsContinuous && p != null) {
                    MediaPlaybackCoordinator.shared.protectContinuous(p)
                    return@onDispose
                }
                if (handedOffLatest.value) {
                    // Pool owns the ExoPlayer now — do not release.
                    return@onDispose
                }
                val id = postId
                val pool = SparkWarmPool.shared
                if (id != null && p != null) {
                    // Already parked by exportPlaybackForHandoff?
                    if (pool.isParked(id, p) || pool.parkedPlayer(id) === p) {
                        return@onDispose
                    }
                    val sec = p.currentPosition / 1000.0
                    if (sec > 0.45) pool.rememberPlayhead(id, sec)
                    // Opening Sparks/Hubs marked continue → park mid-clip; else rewind park.
                    if (pool.shouldContinueFromCurrentTime(id) && sec > 0.45) {
                        pool.parkContinuing(id, p)
                        return@onDispose
                    }
                    // Scroll-away: park silent t≈0 for instant reclaim (iOS park).
                    if (p.mediaItemCount > 0 && p.playbackState != Player.STATE_IDLE) {
                        pool.park(id, p)
                        return@onDispose
                    }
                    pool.release(id)
                }
                if (p != null) MediaPlaybackCoordinator.shared.unregister(p)
                p?.stop()
                p?.clearMediaItems()
                p?.release()
            } catch (_: Throwable) {
            }
        }
    }

    LaunchedEffect(isActive, isPausedByUser, player, shouldShowAd, postId) {
        val p = player ?: return@LaunchedEffect
        if (shouldShowAd) {
            p.pause()
            return@LaunchedEffect
        }
        when {
            !isActive -> {
                // Park playhead while still alive (reelsOpen pauses feed before dispose).
                val id = postId
                if (id != null) {
                    val sec = p.currentPosition / 1000.0
                    if (sec > 0.45) SparkWarmPool.shared.rememberPlayhead(id, sec)
                }
                p.pause()
            }
            isPausedByUser -> p.pause()
            else -> p.play()
        }
    }

    // Continuous Hubs mini: AppState can stay isActive while tab silence / surface rebind
    // leaves Exo paused — re-assert play without waiting for an isActive edge.
    LaunchedEffect(protectAsContinuous, isActive, isPausedByUser, player, shouldShowAd) {
        if (!protectAsContinuous) return@LaunchedEffect
        val p = player ?: return@LaunchedEffect
        while (true) {
            delay(400)
            if (!isActiveLatest || isPausedLatest || shouldShowAd) continue
            MediaPlaybackCoordinator.shared.protectContinuous(p)
            if (loopsLatest) {
                p.repeatMode = Player.REPEAT_MODE_ONE
            }
            val wantVol = if (mutedLatest) 0f else 1f
            // hardSilence zeros volume; ENDED needs seek before play restarts.
            val volWrong = kotlin.math.abs(p.volume - wantVol) > 0.02f
            val ended = p.playbackState == Player.STATE_ENDED
            if (!p.isPlaying || volWrong || ended) {
                p.volume = wantVol
                when {
                    ended -> runCatching { p.seekTo(0); p.play() }
                    p.playbackState == Player.STATE_IDLE && p.mediaItemCount > 0 -> {
                        runCatching { p.prepare() }
                        p.play()
                    }
                    !p.isPlaying -> p.play()
                }
            }
        }
    }

    LaunchedEffect(isMuted, player) {
        player?.volume = if (isMuted) 0f else 1f
    }

    // Restart seek: cover with poster first (iOS isRestartSeeking) — black shutter was the blink.
    // Skip seek-to-0 when this clip is a mid-clip Feed→Sparks handoff.
    LaunchedEffect(restartFromBeginningToken, player, postId) {
        if (restartFromBeginningToken <= 0) return@LaunchedEffect
        if (restartFromBeginningToken == lastHandledRestartToken) return@LaunchedEffect
        lastHandledRestartToken = restartFromBeginningToken
        val p = player ?: return@LaunchedEffect
        val continuing = claimedContinuing ||
            (postId != null && SparkWarmPool.shared.shouldContinueFromCurrentTime(postId))
        if (continuing) {
            val head = postId?.let { SparkWarmPool.shared.peekPlayheadSeconds(it) }
            if (head != null && head > 0.45) {
                runCatching {
                    p.seekTo((head * 1000).toLong())
                    if (isActiveLatest && !isPausedLatest && !shouldShowAd) p.play()
                }
                return@LaunchedEffect
            }
            if (isActiveLatest && !isPausedLatest && !shouldShowAd) {
                runCatching { p.play() }
            }
            return@LaunchedEffect
        }
        // Poster underlay while Exo seeks to 0 — never reveal black shutter.
        if (!posterUrl.isNullOrBlank()) {
            isRestartSeeking = true
            showPosterCover = true
        }
        runCatching {
            p.seekTo(0)
            if (isActiveLatest && !isPausedLatest && !shouldShowAd) p.play()
        }
    }

    LaunchedEffect(seekToSeconds, player) {
        val seek = seekToSeconds ?: return@LaunchedEffect
        val p = player ?: return@LaunchedEffect
        // Skip redundant seek that fights a mid-clip claim (blink).
        if (claimedContinuing) {
            seekConsumedCb?.invoke()
            return@LaunchedEffect
        }
        val cur = p.currentPosition / 1000.0
        if (kotlin.math.abs(cur - seek) < 0.35) {
            seekConsumedCb?.invoke()
            return@LaunchedEffect
        }
        if (!posterUrl.isNullOrBlank() && !hasRenderedFrame) {
            isRestartSeeking = true
            showPosterCover = true
        }
        p.seekTo((seek * 1000).toLong())
        seekConsumedCb?.invoke()
    }

    LaunchedEffect(startTime, player) {
        val start = startTime ?: return@LaunchedEffect
        val p = player ?: return@LaunchedEffect
        // Claimed mid-clip already at playhead — never re-seek (iOS handoff).
        if (claimedContinuing) return@LaunchedEffect
        val cur = p.currentPosition / 1000.0
        if (cur.isFinite() && kotlin.math.abs(cur - start) < 0.35) return@LaunchedEffect
        if (!posterUrl.isNullOrBlank()) {
            isRestartSeeking = true
            showPosterCover = true
        }
        p.seekTo((start * 1000).toLong())
    }

    LaunchedEffect(player, isActive) {
        val p = player ?: return@LaunchedEffect
        var reportedView = false
        var paintedAtMs = 0L
        while (true) {
            currentMs = p.currentPosition
            durationMs = p.duration.coerceAtLeast(0)
            isPlaying = p.isPlaying
            // iOS playerHasPaintedFrames: playing AND time advanced — not readyToPlay alone.
            val tSec = p.currentPosition / 1000.0
            val painted = p.playbackState == Player.STATE_READY &&
                (p.isPlaying || p.playWhenReady) &&
                tSec.isFinite() &&
                tSec >= 0.08
            val midClipPainted = claimedContinuing &&
                tSec.isFinite() &&
                tSec >= 0.25 &&
                p.playbackState == Player.STATE_READY
            if ((painted || midClipPainted) && (showPosterCover || isRestartSeeking || claimedContinuing)) {
                hasRenderedFrame = true
                val now = android.os.SystemClock.elapsedRealtime()
                if (isRestartSeeking) {
                    if (paintedAtMs == 0L) paintedAtMs = now
                    // Settle ~2 frames so dropping cover never reveals black (iOS 64ms).
                    if (now - paintedAtMs >= 64L) {
                        isRestartSeeking = false
                        showPosterCover = false
                        paintedAtMs = 0L
                        if (claimedContinuing && !handoffPaintNotified) {
                            handoffPaintNotified = true
                            postId?.let { SparkWarmPool.shared.notifyHandoffPainted(it) }
                        }
                    }
                } else {
                    showPosterCover = false
                    paintedAtMs = 0L
                    if (claimedContinuing && !handoffPaintNotified) {
                        handoffPaintNotified = true
                        postId?.let { SparkWarmPool.shared.notifyHandoffPainted(it) }
                    }
                }
            }
            if (p.playerError != null) loadFailed = true
            if (!reportedView && p.currentPosition > 500 && isActive) {
                reportedView = true
                viewedCb?.invoke()
            }
            progressCb?.invoke(currentMs / 1000.0, durationMs / 1000.0)
            delay(40)
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

    // Mid-clip Feed→Sparks: transparent floor so Feed TextureView last-frame shows through
    // until onRenderedFirstFrame (opaque black floor was the open blink).
    val stageFloor =
        if ((continueHandoff || claimedContinuing) && !handoffPaintNotified) {
            Color.Transparent
        } else {
            Color.Black
        }

    // Continuous Hubs mini: clipToBounds blanks TextureView at thumb size — skip it.
    Box(
        modifier
            .then(if (protectAsContinuous) Modifier else Modifier.clipToBounds())
            .background(stageFloor)
            .clickable(enabled = showsControls) {
                showChrome = !showChrome
            }
            .then(
                if (onPullDrag != null) {
                    Modifier.pointerInput(Unit) {
                        var totalY = 0f
                        detectVerticalDragGestures(
                            onDragStart = { totalY = 0f },
                            onVerticalDrag = { change, amount ->
                                change.consume()
                                totalY = maxOf(0f, totalY + amount)
                                onPullDragLatest?.invoke(totalY)
                            },
                            onDragEnd = { onPullDragEndLatest?.invoke(totalY) },
                            onDragCancel = { onPullDragCancelLatest?.invoke() },
                        )
                    }
                } else {
                    Modifier
                },
            ),
    ) {
        // Static underlay (no crossfade). Keep during cold open + restart seek (iOS).
        if (!posterUrl.isNullOrBlank() && (shouldShowPosterCover || !hasRenderedFrame)) {
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
                        // texture_view + keep_content: Feed keeps last frame after player leaves
                        // (SurfaceView went black on Feed→Sparks open — the blink).
                        val view = LayoutInflater.from(ctx)
                            .inflate(R.layout.matterya_player_view, null, false) as PlayerView
                        view.apply {
                            useController = false
                            // ZOOM = aspectFill (crop); FIT = letterbox. Sparks always want ZOOM.
                            this.resizeMode = resizeMode
                            val shutter = if (claimedContinuing) {
                                AndroidColor.TRANSPARENT
                            } else {
                                AndroidColor.BLACK
                            }
                            setShutterBackgroundColor(shutter)
                            setBackgroundColor(
                                if (claimedContinuing) AndroidColor.TRANSPARENT else AndroidColor.BLACK,
                            )
                            defaultArtwork = null
                            artworkDisplayMode = PlayerView.ARTWORK_DISPLAY_MODE_OFF
                            this.player = player
                            layoutParams = FrameLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT,
                            )
                            clipChildren = true
                            clipToPadding = true
                            clipToOutline = true
                        }
                        view
                    },
                    update = { view ->
                        if (handedOffLatest.value) {
                            // Leave TextureView last-frame bitmap — do not clear player if
                            // already null; avoid forcing a redraw to black.
                            if (view.player != null) view.player = null
                            return@AndroidView
                        }
                        val id = postId
                        // Sparks claimed — Feed must not steal the surface back. Keep the
                        // TextureView's last bitmap visible under transparent Sparks.
                        if (id != null &&
                            SparkWarmPool.shared.isInUse(id) &&
                            !claimedContinuing
                        ) {
                            return@AndroidView
                        }
                        if (view.player !== player) view.player = player
                        if (view.resizeMode != resizeMode) {
                            view.resizeMode = resizeMode
                        }
                        val shutter = if (claimedContinuing && !isRestartSeeking) {
                            AndroidColor.TRANSPARENT
                        } else {
                            AndroidColor.BLACK
                        }
                        view.setShutterBackgroundColor(shutter)
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

        val controlsPlayer = player
        if (showsControls && showChrome && controlsPlayer != null && !shouldShowAd) {
            MatteryaVideoControls(
                isPlaying = isPlaying && !isPausedByUser,
                isMuted = isMuted,
                currentSeconds = currentMs / 1000.0,
                durationSeconds = durationMs / 1000.0,
                showsFullscreen = allowsFullscreen,
                onPlayPause = {
                    if (controlsPlayer.isPlaying) controlsPlayer.pause() else controlsPlayer.play()
                    showChrome = true
                },
                onMuteToggle = {
                    isMuted = !isMuted
                    showChrome = true
                },
                onSeek = { sec ->
                    controlsPlayer.seekTo((sec * 1000).toLong())
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
