package com.matterya.matterya.ui.living

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.hubs.YouTubeChannel
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.theme.YouTubeMediaLayout
import com.matterya.matterya.theme.YouTubeVideoListRow
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.VideoPlayerView

/**
 * iOS `YouTubeWatchView` — 16:9 stage, title, actions, channel, related shelf.
 */
@Composable
fun YouTubeWatchView(
    post: CountryPost,
    channel: YouTubeChannel? = null,
    related: List<CountryPost> = emptyList(),
    subscriberCount: Int? = null,
    embedsPlayer: Boolean = true,
    onBack: () -> Unit = {},
    onOpenVideo: (CountryPost) -> Unit = {},
    onOpenChannel: (YouTubeChannel) -> Unit = {},
    onLike: (CountryPost) -> Unit = {},
    onShare: (CountryPost) -> Unit = {},
    isPlaying: Boolean = true,
    isMuted: Boolean = false,
) {
    var current by remember(post.id) { mutableStateOf(post) }
    var commentsExpanded by remember { mutableStateOf(false) }

    BoxWithConstraints(Modifier.fillMaxSize().background(MatteryaColors.paper)) {
        val density = LocalDensity.current
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        // Exact 16:9 stage (iOS YouTubeWatchView / hubs continuous stage)
        val stageH = with(density) {
            YouTubeMediaLayout.watchPlayerHeight(widthPx, heightPx, heightPx).toDp()
        }
        val classic16x9 = maxWidth / YouTubeMediaLayout.aspect
        val stageHeight = maxOf(stageH, classic16x9).coerceAtLeast(120.dp)

        Column(Modifier.fillMaxSize()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(stageHeight)
                    .background(MatteryaColors.ink),
            ) {
                if (embedsPlayer) {
                    VideoPlayerView(
                        url = current.playableVideoUrl,
                        posterUrl = current.posterImageUrl,
                        placement = "hubs_preroll",
                        adsEnabled = true,
                        isActive = isPlaying,
                        muted = isMuted,
                        showsControls = true,
                        allowsFullscreen = true,
                        fillsFrame = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .aspectRatio(YouTubeMediaLayout.aspect)
                            .align(Alignment.Center),
                    )
                }
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(8.dp),
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = androidx.compose.ui.graphics.Color.White)
                }
            }

            Spacer(Modifier.height(YouTubeMediaLayout.hubsTitleGapBelowVideo))

            LazyColumn(Modifier.fillMaxSize()) {
                item {
                    Column(Modifier.padding(horizontal = MatteryaDimens.pagePadding)) {
                        Text(
                            current.displayHeadline
                                ?: current.displayExcerpt.ifEmpty { current.authorDisplayName },
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 17.sp,
                            color = MatteryaColors.ink,
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "${current.viewCount} views · ${current.relativeTime}",
                            fontSize = 12.sp,
                            color = MatteryaColors.inkMuted,
                        )
                        Spacer(Modifier.height(12.dp))
                        // Actions: Like · Share
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TextButton(onClick = {
                                onLike(current)
                                current = current.copyEngagement(
                                    likedByMe = !current.likedByMe,
                                    likeCount = current.likeCount + if (current.likedByMe) -1 else 1,
                                )
                            }) {
                                Icon(
                                    if (current.likedByMe) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                                    contentDescription = null,
                                    tint = if (current.likedByMe) MatteryaColors.like else MatteryaColors.ink,
                                    modifier = Modifier.size(18.dp),
                                )
                                Spacer(Modifier.width(6.dp))
                                Text("${current.displayLikeCount}", color = MatteryaColors.ink)
                            }
                            TextButton(onClick = { onShare(current) }) {
                                Icon(Icons.Default.Share, null, tint = MatteryaColors.ink, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("Share", color = MatteryaColors.ink)
                            }
                        }
                    }
                }

                item {
                    // Channel section
                    val ch = channel
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable(enabled = ch != null) { ch?.let(onOpenChannel) }
                            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        AvatarView(
                            url = ch?.author?.avatarUrl ?: current.author?.avatarUrl,
                            seed = ch?.authorId ?: current.authorId,
                            size = 40.dp,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                ch?.title ?: current.authorDisplayName,
                                fontWeight = FontWeight.SemiBold,
                                color = MatteryaColors.ink,
                            )
                            Text(
                                subscriberCount?.let { "$it ${MatteryaCopy.followers}" }
                                    ?: MatteryaCopy.viewCreatorHub,
                                fontSize = 12.sp,
                                color = MatteryaColors.inkMuted,
                            )
                        }
                    }
                    HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
                }

                item {
                    if (current.displayBody.isNotEmpty()) {
                        Text(
                            current.displayBody,
                            color = MatteryaColors.inkSecondary,
                            fontSize = 14.sp,
                            modifier = Modifier.padding(MatteryaDimens.pagePadding),
                            maxLines = if (commentsExpanded) Int.MAX_VALUE else 4,
                            overflow = TextOverflow.Ellipsis,
                        )
                        TextButton(
                            onClick = { commentsExpanded = !commentsExpanded },
                            modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding),
                        ) {
                            Text(if (commentsExpanded) "Show less" else "Show more", color = MatteryaColors.accent)
                        }
                    }
                }

                if (related.isNotEmpty()) {
                    item {
                        Text(
                            MatteryaCopy.moreOnHubs,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 16.sp,
                            color = MatteryaColors.ink,
                            modifier = Modifier.padding(
                                horizontal = MatteryaDimens.pagePadding,
                                vertical = 12.dp,
                            ),
                        )
                    }
                    items(related.distinctBy { it.id }, key = { it.id }) { relatedPost ->
                        YouTubeVideoListRow(post = relatedPost, onOpen = { onOpenVideo(relatedPost) })
                    }
                }

                item { Spacer(Modifier.height(32.dp)) }
            }
        }
    }
}
