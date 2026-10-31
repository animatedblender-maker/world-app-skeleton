package com.matterya.matterya.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.hubs.YouTubeChannel
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.HandDrawnMediaFrame
import com.matterya.matterya.ui.components.MatteryaHubsLogoView
import com.matterya.matterya.ui.components.VideoThumbnailView

/** iOS `YouTubeVideoFrame` chrome styles for Hubs. */
@Composable
fun YouTubeVideoFrame(
    style: MatteryaPlayerFrameStyle = MatteryaPlayerFrameStyle.Card,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val shape = when (style) {
        MatteryaPlayerFrameStyle.Card -> RoundedCornerShape(14.dp)
        MatteryaPlayerFrameStyle.Feed, MatteryaPlayerFrameStyle.Watch -> RoundedCornerShape(0.dp)
    }
    Box(
        modifier
            .then(
                if (style == MatteryaPlayerFrameStyle.Card) {
                    Modifier
                        .clip(shape)
                        .border(0.5.dp, MatteryaColors.border, shape)
                        .background(MatteryaColors.canvasMuted)
                } else {
                    Modifier.background(Color.Transparent)
                },
            ),
    ) {
        content()
    }
}

/** iOS `YouTubeVideoListRow` — related / home shelf row. */
@Composable
fun YouTubeVideoListRow(
    post: CountryPost,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
    ) {
        HandDrawnMediaFrame(
            seed = post.id,
            padding = 2.dp,
            modifier = Modifier
                .width(160.dp)
                .aspectRatio(16f / 9f),
        ) {
            Box(Modifier.fillMaxWidth()) {
                VideoThumbnailView(
                    post = post,
                    maxLogicalPx = YouTubeMediaLayout.hubsListThumbMaxPixel,
                    showsPlayIcon = false,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f),
                )
                Icon(
                    Icons.Default.PlayArrow,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(6.dp)
                        .size(18.dp),
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                post.displayHeadline ?: post.displayExcerpt.ifEmpty { post.authorDisplayName },
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                fontSize = 14.sp,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "${post.authorDisplayName} · ${post.relativeTime}",
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** iOS `YouTubeChannelRow` / channel card compact. */
@Composable
fun YouTubeChannelRow(
    channel: YouTubeChannel,
    subscriberCount: Int? = null,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvatarView(
            url = channel.author?.avatarUrl,
            seed = channel.authorId,
            size = 48.dp,
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(channel.title, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            val handle = channel.handle?.let { "@$it" }
            val subs = subscriberCount?.let { "$it ${MatteryaCopy.followers}" }
            Text(
                listOfNotNull(handle, subs).joinToString(" · ").ifEmpty { MatteryaCopy.creator },
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
            )
        }
    }
}

/** Mini player bar under chat / tabs. */
@Composable
fun YouTubeMiniPlayerBar(
    post: CountryPost,
    isPlaying: Boolean,
    isMuted: Boolean,
    onExpand: () -> Unit,
    onClose: () -> Unit,
    onTogglePlay: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .fillMaxWidth()
            .height(56.dp)
            .background(MatteryaColors.surface)
            .border(0.5.dp, MatteryaColors.border)
            .clickable(onClick = onExpand)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(width = 72.dp, height = 40.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(MatteryaColors.canvasMuted),
        ) {
            VideoThumbnailView(
                post = post,
                maxLogicalPx = 160,
                showsPlayIcon = false,
                modifier = Modifier.fillMaxSize(),
            )
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(
                post.displayHeadline ?: post.displayExcerpt.ifEmpty { post.authorDisplayName },
                fontWeight = FontWeight.SemiBold,
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = MatteryaColors.ink,
            )
            Text(post.authorDisplayName, fontSize = 11.sp, color = MatteryaColors.inkMuted, maxLines = 1)
        }
        Text(
            if (isPlaying) "❚❚" else "▶",
            modifier = Modifier
                .clickable(onClick = onTogglePlay)
                .padding(8.dp),
            color = MatteryaColors.ink,
        )
        Text(
            "✕",
            modifier = Modifier
                .clickable(onClick = onClose)
                .padding(8.dp),
            color = MatteryaColors.inkMuted,
        )
    }
}

/** iOS `PlayBrandMark` — Matterya Hubs wordmark with TV logo. */
@Composable
fun PlayBrandMark(
    modifier: Modifier = Modifier,
    ringSize: Dp = 24.dp,
    compact: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val clickMod = if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier
    Row(
        modifier.then(clickMod),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (compact) 5.dp else 6.dp),
    ) {
        MatteryaHubsLogoView(size = ringSize + if (compact) 4.dp else 6.dp)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                AppConfig.appName,
                fontFamily = FontFamily.Serif,
                fontSize = if (compact) 16.sp else 19.sp,
                color = MatteryaColors.ink,
                letterSpacing = 0.35.sp,
                maxLines = 1,
            )
            Text(
                "\u00A0Hubs",
                fontWeight = FontWeight.Bold,
                fontSize = if (compact) 16.sp else 19.sp,
                color = MatteryaColors.ink,
                maxLines = 1,
            )
        }
    }
}

/**
 * iOS `SparksHorizontalStrip` — title + subtitle + optional brand mark + fixed 108×192 tiles.
 */
@Composable
fun SparksHorizontalStrip(
    posts: List<CountryPost>,
    onOpen: (CountryPost) -> Unit,
    modifier: Modifier = Modifier,
    title: String = MatteryaCopy.sparksForYou,
    subtitle: String = "Swipe the world on Matterya",
    showsBrandMark: Boolean = true,
    onBrandTap: (() -> Unit)? = null,
) {
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(top = 12.dp, bottom = 10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    title,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.ink,
                )
                if (subtitle.isNotEmpty()) {
                    Text(
                        subtitle,
                        fontSize = 12.sp,
                        color = MatteryaColors.inkMuted,
                    )
                }
            }
            if (showsBrandMark && onBrandTap != null) {
                PlayBrandMark(compact = true, onClick = onBrandTap)
            }
        }
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = MatteryaDimens.pagePadding),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            posts.forEach { post ->
                SparksStripTile(post = post, onTap = { onOpen(post) })
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

/** iOS `SparksStripTile` — fixed 108×192 portrait spark chrome. */
@Composable
fun SparksStripTile(
    post: CountryPost,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
    width: Dp = 108.dp,
    height: Dp = 192.dp,
) {
    val shape = RoundedCornerShape(12.dp)
    Box(
        modifier
            .width(width)
            .height(height)
            .clip(shape)
            .clipToBounds()
            .border(0.5.dp, MatteryaColors.border.copy(alpha = 0.45f), shape)
            .clickable(onClick = onTap),
    ) {
        VideoThumbnailView(
            post = post,
            maxLogicalPx = 420,
            showsPlayIcon = false,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        // Country badge top-trailing
        val country = post.countryName?.trim()?.takeIf { it.isNotEmpty() }
            ?: post.countryCode?.trim()?.uppercase()?.takeIf { it.isNotEmpty() }
        if (country != null) {
            Text(
                country,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 1,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .background(Color.Black.copy(alpha = 0.48f), RoundedCornerShape(999.dp))
                    .padding(horizontal = 6.dp, vertical = 3.dp),
            )
        }
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(72.dp)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f)),
                    ),
                ),
        )
        Text(
            post.authorDisplayName,
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(8.dp),
        )
    }
}

/**
 * iOS `HubsShelfThumbCard` — fixed-width 16:9 shelf card (Continue watching / New on Hubs).
 */
@Composable
fun HubsShelfThumbCard(
    post: CountryPost,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
    width: Dp = 168.dp,
    showsMetadata: Boolean = false,
) {
    val thumbHeight = width * (9f / 16f)
    val titleBlockHeight = 34.dp
    val shape = RoundedCornerShape(10.dp)
    Column(
        modifier
            .width(width)
            .clickable(onClick = onTap),
    ) {
        Box(
            Modifier
                .width(width)
                .height(thumbHeight)
                .clip(shape)
                .clipToBounds()
                .background(MatteryaColors.canvasDeep)
                .border(0.5.dp, MatteryaColors.border.copy(alpha = 0.6f), shape),
        ) {
            VideoThumbnailView(
                post = post,
                maxLogicalPx = YouTubeMediaLayout.hubsListThumbMaxPixel,
                showsPlayIcon = false,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        Text(
            post.displayHeadline ?: post.displayExcerpt.ifEmpty { post.authorDisplayName }.ifEmpty { " " },
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.ink,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .width(width)
                .height(titleBlockHeight)
                .padding(top = 6.dp),
        )
        if (showsMetadata) {
            val parts = buildList {
                add(post.authorDisplayName)
                if (post.viewCount > 0) add("${post.viewCount} views")
            }
            Text(
                parts.joinToString(" · "),
                fontSize = 11.sp,
                color = MatteryaColors.inkMuted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .width(width)
                    .padding(top = 2.dp),
            )
        }
    }
}

/** Horizontal shelf of [HubsShelfThumbCard]s with optional trailing action. */
@Composable
fun HubsHorizontalShelf(
    title: String,
    posts: List<CountryPost>,
    onOpen: (CountryPost) -> Unit,
    modifier: Modifier = Modifier,
    trailing: @Composable (() -> Unit)? = null,
    cardWidth: Dp = 168.dp,
    showsMetadata: Boolean = false,
) {
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(top = 14.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                title,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
                modifier = Modifier.weight(1f),
            )
            trailing?.invoke()
        }
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = MatteryaDimens.pagePadding),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            posts.forEach { post ->
                HubsShelfThumbCard(
                    post = post,
                    width = cardWidth,
                    showsMetadata = showsMetadata,
                    onTap = { onOpen(post) },
                )
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}
