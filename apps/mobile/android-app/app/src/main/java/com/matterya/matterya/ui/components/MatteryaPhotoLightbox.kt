package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import kotlin.math.abs

/**
 * Instagram-style fullscreen photo viewer — pinch/pan zoom, double-tap, drag-down dismiss.
 * Mirrors iOS `MatteryaPhotoLightbox`.
 */
@Composable
fun MatteryaPhotoLightbox(
    url: String,
    onClose: () -> Unit,
) {
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
            dismissOnBackPress = true,
            dismissOnClickOutside = false,
        ),
    ) {
        var dragOffset by remember { mutableFloatStateOf(0f) }
        val density = LocalDensity.current
        val dismissThreshold = with(density) { 140.dp.toPx() }
        val bgAlpha = (1f - (abs(dragOffset) / 420f)).coerceIn(0.35f, 1f)

        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = bgAlpha))
                .pointerInput(Unit) {
                    detectVerticalDragGestures(
                        onDragEnd = {
                            if (dragOffset > dismissThreshold) onClose()
                            else dragOffset = 0f
                        },
                        onVerticalDrag = { _, amount ->
                            // Only accumulate downward dismiss when not mid-zoom (page handles that).
                            dragOffset = (dragOffset + amount).coerceAtLeast(0f)
                        },
                    )
                },
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer { translationY = dragOffset },
            ) {
                ZoomablePhotoPage(url = url)
            }

            IconButton(
                onClick = onClose,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .statusBarsPadding()
                    .padding(12.dp)
                    .size(36.dp)
                    .background(Color.White.copy(alpha = 0.18f), CircleShape),
            ) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
            }
        }
    }
}

@Composable
fun ZoomablePhotoPage(
    url: String,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Fit,
) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        val maxW = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val maxH = constraints.maxHeight.toFloat().coerceAtLeast(1f)

        fun clampOffset(raw: Offset, s: Float): Offset {
            if (s <= 1.05f) return Offset.Zero
            val maxX = (maxW * (s - 1f)) / 2f
            val maxY = (maxH * (s - 1f)) / 2f
            return Offset(
                raw.x.coerceIn(-maxX, maxX),
                raw.y.coerceIn(-maxY, maxY),
            )
        }

        AsyncImage(
            model = url,
            contentDescription = null,
            contentScale = contentScale,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    translationX = offset.x
                    translationY = offset.y
                }
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        val next = (scale * zoom).coerceIn(1f, 5f)
                        scale = next
                        offset = clampOffset(offset + pan, next)
                    }
                }
                .pointerInput(Unit) {
                    detectTapGestures(
                        onDoubleTap = {
                            if (scale > 1.05f) {
                                scale = 1f
                                offset = Offset.Zero
                            } else {
                                scale = 2.5f
                            }
                        },
                    )
                },
        )
    }
}

/**
 * In-feed / card photo: tap opens lightbox; two-finger pinch zooms in place (resets on release).
 */
@Composable
fun FeedPinchZoomPhoto(
    url: String,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    onTap: () -> Unit,
    onZoomingChanged: ((Boolean) -> Unit)? = null,
) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var zooming by remember { mutableStateOf(false) }

    val transformState = rememberTransformableState { zoomChange, panChange, _ ->
        val next = (scale * zoomChange).coerceIn(1f, 4f)
        scale = next
        offset = if (next > 1.05f) offset + panChange else Offset.Zero
        val active = next > 1.05f
        if (zooming != active) {
            zooming = active
            onZoomingChanged?.invoke(active)
        }
    }

    LaunchedEffect(transformState.isTransformInProgress) {
        if (!transformState.isTransformInProgress && scale > 1.01f) {
            scale = 1f
            offset = Offset.Zero
            if (zooming) {
                zooming = false
                onZoomingChanged?.invoke(false)
            }
        }
    }

    Box(
        modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                translationX = offset.x
                translationY = offset.y
                clip = scale <= 1.02f
            }
            .transformable(state = transformState, lockRotationOnZoomPan = true)
            .pointerInput(url) {
                detectTapGestures(
                    onTap = { onTap() },
                    onDoubleTap = { onTap() },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        AsyncImage(
            model = url,
            contentDescription = null,
            contentScale = contentScale,
            modifier = Modifier.fillMaxSize(),
        )
    }
}
