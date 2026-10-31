package com.matterya.matterya.ui.post

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.data.posts.PostsService
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.PostCard
import kotlinx.coroutines.withTimeoutOrNull

/** iOS `PostDetailView` — hub/spark banners + edge-to-edge card with expanded comments. */
@Composable
fun PostDetailView(
    postId: String,
    initialPost: CountryPost? = null,
    onLike: (CountryPost) -> Unit = {},
    onUpdated: (CountryPost) -> Unit = {},
    onOpenHubs: (CountryPost) -> Unit = {},
    onOpenSpark: (CountryPost) -> Unit = {},
    onOpenVideo: (CountryPost) -> Unit = {},
) {
    val posts = remember { PostsService() }
    var post by remember(postId) { mutableStateOf(initialPost) }
    var loading by remember(postId) { mutableStateOf(initialPost == null) }
    var error by remember(postId) { mutableStateOf<String?>(null) }

    LaunchedEffect(postId) {
        if (post != null) loading = false
        val fetched = withTimeoutOrNull(12_000) {
            runCatching { posts.getPostById(postId) }.getOrNull()
        }
        if (fetched != null) {
            post = fetched
            error = null
        } else if (post == null) {
            error = "Post not found or couldn’t be loaded. Pull back and try again."
        }
        loading = false
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas)
            .verticalScroll(rememberScrollState())
            .padding(bottom = 24.dp),
    ) {
        when {
            loading && post == null -> {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(top = 40.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = MatteryaColors.facebookBlue)
                }
            }
            error != null && post == null -> {
                Text(error!!, color = MatteryaColors.danger, modifier = Modifier.padding(MatteryaDimens.pagePadding))
            }
            post != null -> {
                val current = post!!
                when {
                    PlayPlatformBridge.isHubFeedCardVideo(current) -> {
                        WatchOnHubsBanner(onClick = { onOpenHubs(current) })
                    }
                    current.isReel || current.isSpark -> {
                        WatchSparkBanner(onClick = { onOpenSpark(current) })
                    }
                }
                PostCard(
                    post = current,
                    onLike = { onLike(current) },
                    onUpdated = {
                        post = it
                        onUpdated(it)
                    },
                    onOpenVideo = {
                        if (current.hasVideo && !current.isReel) onOpenVideo(current)
                    },
                    onOpenReel = {
                        if (current.isReel || current.isSpark) onOpenSpark(current)
                    },
                    commentsInitiallyExpanded = true,
                    edgeToEdge = true,
                )
            }
            else -> {
                Text(
                    "Post not found.",
                    color = MatteryaColors.inkMuted,
                    modifier = Modifier.padding(MatteryaDimens.pagePadding),
                )
            }
        }
    }
}

@Composable
private fun WatchSparkBanner(onClick: () -> Unit) {
    val shape = RoundedCornerShape(MatteryaDimens.controlRadius)
    Row(
        Modifier
            .padding(horizontal = MatteryaDimens.pagePadding)
            .padding(top = 12.dp, bottom = 4.dp)
            .fillMaxWidth()
            .background(MatteryaColors.surface, shape)
            .border(0.5.dp, MatteryaColors.border, shape)
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Default.AutoAwesome,
            contentDescription = null,
            tint = MatteryaColors.accentBright,
            modifier = Modifier.size(22.dp),
        )
        Spacer(Modifier.width(10.dp))
        Text(
            "Play ${MatteryaCopy.spark}",
            fontWeight = FontWeight.SemiBold,
            fontSize = 14.sp,
            color = MatteryaColors.ink,
            modifier = Modifier.weight(1f),
        )
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MatteryaColors.inkMuted,
        )
    }
}

@Composable
private fun WatchOnHubsBanner(onClick: () -> Unit) {
    val shape = RoundedCornerShape(MatteryaDimens.controlRadius)
    Row(
        Modifier
            .padding(horizontal = MatteryaDimens.pagePadding)
            .padding(top = 12.dp, bottom = 4.dp)
            .fillMaxWidth()
            .background(MatteryaColors.surface, shape)
            .border(0.5.dp, MatteryaColors.border, shape)
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                MatteryaCopy.watchOnHubs,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
                color = MatteryaColors.ink,
                maxLines = 1,
            )
            Text(
                "Open in the Hubs player with more like this",
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
                maxLines = 1,
            )
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MatteryaColors.inkMuted,
        )
    }
}
