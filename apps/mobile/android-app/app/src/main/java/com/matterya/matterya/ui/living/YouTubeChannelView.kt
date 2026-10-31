package com.matterya.matterya.ui.living

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.matterya.matterya.data.hubs.YouTubeChannel
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.theme.YouTubeVideoListRow
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.HandDrawnMediaFrame
import com.matterya.matterya.ui.components.VideoThumbnailView

enum class YouTubeChannelTab {
    Videos, Reels, About;

    val title: String
        get() = when (this) {
            Videos -> "Videos"
            Reels -> MatteryaCopy.sparks
            About -> "About"
        }
}

/** iOS `YouTubeChannelView` — banner, header, tabs, video list. */
@Composable
fun YouTubeChannelView(
    channel: YouTubeChannel,
    subscriberCount: Int? = null,
    canManage: Boolean = false,
    isFollowing: Boolean = false,
    onBack: () -> Unit = {},
    onOpenVideo: (CountryPost) -> Unit = {},
    onFollow: () -> Unit = {},
    onSettings: () -> Unit = {},
) {
    var tab by remember { mutableStateOf(YouTubeChannelTab.Videos) }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas),
    ) {
        Box {
            // Banner
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(140.dp)
                    .background(
                        Brush.horizontalGradient(
                            listOf(MatteryaColors.canvasDeep, MatteryaColors.oceanWash.copy(alpha = 0.5f)),
                        ),
                    ),
            )
            IconButton(
                onClick = onBack,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(8.dp)
                    .background(MatteryaColors.surface.copy(alpha = 0.94f), CircleShape),
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MatteryaColors.ink)
            }
            if (canManage) {
                IconButton(
                    onClick = onSettings,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(8.dp)
                        .background(MatteryaColors.surface.copy(alpha = 0.94f), CircleShape),
                ) {
                    Icon(Icons.Default.Settings, "Settings", tint = MatteryaColors.ink)
                }
            }
        }

        // Header
        Row(
            Modifier
                .fillMaxWidth()
                .padding(MatteryaDimens.pagePadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AvatarView(
                url = channel.author?.avatarUrl,
                seed = channel.authorId,
                size = 72.dp,
            )
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(channel.title, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, color = MatteryaColors.ink)
                channel.handle?.let {
                    Text("@$it", fontSize = 13.sp, color = MatteryaColors.inkMuted)
                }
                Text(
                    listOfNotNull(
                        subscriberCount?.let { "$it ${MatteryaCopy.followers}" },
                        "${channel.videos.size} videos",
                    ).joinToString(" · "),
                    fontSize = 12.sp,
                    color = MatteryaColors.inkMuted,
                )
            }
            TextButton(
                onClick = onFollow,
                modifier = Modifier.background(
                    if (isFollowing) MatteryaColors.buttonMuted else MatteryaColors.ink,
                    androidx.compose.foundation.shape.RoundedCornerShape(MatteryaDimens.controlRadius),
                ),
            ) {
                Text(
                    if (isFollowing) MatteryaCopy.following else MatteryaCopy.follow,
                    color = if (isFollowing) MatteryaColors.ink else MatteryaColors.paper,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }

        // Tabs
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.pagePadding),
        ) {
            YouTubeChannelTab.entries.forEach { t ->
                Column(
                    Modifier
                        .clickable { tab = t }
                        .padding(end = 20.dp, bottom = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        t.title.uppercase(),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (tab == t) MatteryaColors.ink else MatteryaColors.inkMuted,
                    )
                    if (tab == t) {
                        Spacer(
                            Modifier
                                .height(2.dp)
                                .width(28.dp)
                                .background(MatteryaColors.ink),
                        )
                    }
                }
            }
        }

        when (tab) {
            YouTubeChannelTab.Videos -> {
                if (channel.videos.isEmpty()) {
                    Text(
                        MatteryaCopy.hubsNoChannelVideos,
                        color = MatteryaColors.inkMuted,
                        modifier = Modifier.padding(24.dp),
                    )
                } else {
                    LazyColumn(Modifier.fillMaxSize()) {
                        items(channel.videos, key = { it.id }) { video ->
                            YouTubeVideoListRow(post = video, onOpen = { onOpenVideo(video) })
                        }
                    }
                }
            }
            YouTubeChannelTab.Reels -> {
                if (channel.reels.isEmpty()) {
                    Text(MatteryaCopy.noSparksYet, color = MatteryaColors.inkMuted, modifier = Modifier.padding(24.dp))
                } else {
                    LazyColumn(Modifier.fillMaxSize()) {
                        items(channel.reels.chunked(3)) { row ->
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 2.dp),
                            ) {
                                row.forEach { spark ->
                                    Box(
                                        Modifier
                                            .weight(1f)
                                            .aspectRatio(9f / 16f)
                                            .padding(2.dp)
                                            .clickable { onOpenVideo(spark) },
                                    ) {
                                        VideoThumbnailView(
                                            post = spark,
                                            maxLogicalPx = 240,
                                            modifier = Modifier.fillMaxSize(),
                                        )
                                    }
                                }
                                repeat(3 - row.size) {
                                    Spacer(Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }
            }
            YouTubeChannelTab.About -> {
                Column(Modifier.padding(MatteryaDimens.pagePadding)) {
                    Text(MatteryaCopy.aboutThisHub, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "${channel.title} on ${MatteryaCopy.matteryaHubs}",
                        color = MatteryaColors.inkSecondary,
                        fontSize = 14.sp,
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "${channel.videos.size} long-form · ${channel.reels.size} ${MatteryaCopy.sparks.lowercase()}",
                        color = MatteryaColors.inkMuted,
                        fontSize = 13.sp,
                    )
                }
            }
        }
    }
}
