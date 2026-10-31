package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage

/**
 * Masquerade list/feed video poster — tap opens fullscreen player cover.
 * Matches iOS `MasqueradeVideoPoster` + `MasqueradeVideoPlayerCover`.
 */
@Composable
fun MasqueradeVideoPoster(
    videoUrl: String,
    posterUrl: String?,
    height: Dp,
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 10.dp,
) {
    var showPlayer by remember { mutableStateOf(false) }

    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(cornerRadius))
            .background(Color.Black)
            .clickable { showPlayer = true },
        contentAlignment = Alignment.Center,
    ) {
        val thumb = posterUrl?.takeIf { it.isNotBlank() } ?: videoUrl
        AsyncImage(
            model = thumb,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            Modifier
                .size(56.dp)
                .background(Color.Black.copy(alpha = 0.45f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Default.PlayArrow,
                contentDescription = "Play",
                tint = Color.White,
                modifier = Modifier.size(36.dp),
            )
        }
    }

    if (showPlayer) {
        MasqueradeVideoPlayerCover(
            url = videoUrl,
            posterUrl = posterUrl,
            onClose = { showPlayer = false },
        )
    }
}

/**
 * Thread / post-detail in-frame player with fullscreen affordance.
 * Mirrors iOS thread `MatteryaHubPlayerView` (controls + allowsFullscreen).
 */
@Composable
fun MasqueradeInFrameVideo(
    url: String,
    posterUrl: String?,
    modifier: Modifier = Modifier,
    height: Dp = 380.dp,
    cornerRadius: Dp = 10.dp,
) {
    var fullscreen by remember { mutableStateOf(false) }
    var muted by remember { mutableStateOf(false) }

    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(cornerRadius))
            .background(Color.Black),
    ) {
        VideoPlayerView(
            url = url,
            posterUrl = posterUrl,
            isActive = !fullscreen,
            loops = true,
            muted = muted,
            showsControls = true,
            allowsFullscreen = true,
            fillsFrame = false,
            adsEnabled = false,
            onFullscreen = { fullscreen = true },
            modifier = Modifier.fillMaxSize(),
        )
    }

    if (fullscreen) {
        MasqueradeVideoPlayerCover(
            url = url,
            posterUrl = posterUrl,
            startMuted = muted,
            onClose = { fullscreen = false },
        )
    }
}

@Composable
fun MasqueradeVideoPlayerCover(
    url: String,
    posterUrl: String?,
    onClose: () -> Unit,
    startMuted: Boolean = false,
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
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black),
        ) {
            VideoPlayerView(
                url = url,
                posterUrl = posterUrl,
                isActive = true,
                loops = true,
                muted = startMuted,
                showsControls = true,
                allowsFullscreen = false,
                fillsFrame = false,
                adsEnabled = false,
                modifier = Modifier.fillMaxSize(),
            )
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
