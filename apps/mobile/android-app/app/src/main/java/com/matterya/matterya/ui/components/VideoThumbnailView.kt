package com.matterya.matterya.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.matterya.matterya.model.CountryPost

/**
 * Mirrors iOS `VideoThumbnailView` — remote poster first, else extracted video frame.
 * Implementation delegates to [VideoPoster].
 */
@Composable
fun VideoThumbnailView(
    post: CountryPost,
    modifier: Modifier = Modifier,
    maxLogicalPx: Int = 480,
    extractFrameIfNeeded: Boolean = true,
    showsPlayIcon: Boolean = false,
    playIconSize: Dp = 36.dp,
    contentScale: ContentScale = ContentScale.Crop,
) {
    Box(modifier, contentAlignment = Alignment.Center) {
        VideoPoster(
            post = post,
            modifier = Modifier.fillMaxSize(),
            maxLogicalPx = maxLogicalPx,
            extractFrameIfNeeded = extractFrameIfNeeded,
            contentScale = contentScale,
        )
        if (showsPlayIcon && post.hasVideo) {
            Icon(
                Icons.Filled.PlayCircle,
                contentDescription = "Play",
                tint = Color.White.copy(alpha = 0.92f),
                modifier = Modifier.size(playIconSize),
            )
        }
    }
}
