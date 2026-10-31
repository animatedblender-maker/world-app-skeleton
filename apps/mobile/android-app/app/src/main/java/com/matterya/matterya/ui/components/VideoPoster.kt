package com.matterya.matterya.ui.components

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.matterya.matterya.data.media.MediaUrlResolver
import com.matterya.matterya.data.media.VideoFrameCache
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.MatteryaColors

/**
 * Poster for feed / shelf / sparks — remote thumb first, else one cached video frame.
 * Mirrors iOS `VideoThumbnailView` (`extractFrameIfNeeded`). Always crops to fill like iOS.
 */
@Composable
fun VideoPoster(
    post: CountryPost,
    modifier: Modifier = Modifier,
    maxLogicalPx: Int = 420,
    extractFrameIfNeeded: Boolean = true,
    contentScale: ContentScale = ContentScale.Crop,
) {
    val context = LocalContext.current
    val remote = remember(post.id, post.thumbUrl, post.mediaUrl) {
        MediaUrlResolver.posterUrl(post) ?: MediaUrlResolver.imageUrl(post)
    }
    val video = remember(post.id, post.mediaUrl) { MediaUrlResolver.videoUrl(post) }
    var frame by remember(post.id) { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(post.id, remote, video, extractFrameIfNeeded) {
        if (!extractFrameIfNeeded || remote != null || video == null) return@LaunchedEffect
        frame = VideoFrameCache.instance(context).image(
            postId = post.id,
            videoUrl = video,
            maxSize = (maxLogicalPx * 1.5).toInt().coerceIn(240, 720),
        )
    }

    // clipToBounds + Crop = iOS aspectFill (no letterboxing inside the card).
    Box(
        modifier
            .clipToBounds()
            .background(MatteryaColors.canvasMuted),
        contentAlignment = Alignment.Center,
    ) {
        when {
            remote != null -> {
                AsyncImage(
                    model = ImageRequest.Builder(context)
                        .data(remote)
                        .crossfade(false)
                        .size(maxLogicalPx * 2)
                        .build(),
                    contentDescription = null,
                    contentScale = contentScale,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            frame != null -> {
                Image(
                    bitmap = frame!!.asImageBitmap(),
                    contentDescription = null,
                    contentScale = contentScale,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            else -> {
                Icon(
                    imageVector = if (post.hasVideo) Icons.Outlined.Videocam else Icons.Outlined.Image,
                    contentDescription = null,
                    tint = MatteryaColors.inkMuted,
                )
            }
        }
    }
}
