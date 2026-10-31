package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.matterya.matterya.model.AnonymousPost
import com.matterya.matterya.model.AnonymousSpace
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.FeedPinchZoomPhoto
import com.matterya.matterya.ui.components.MasqueradeInFrameVideo
import com.matterya.matterya.ui.components.MasqueradeVideoPoster
import com.matterya.matterya.ui.components.MatteryaPhotoLightbox


@Composable
fun MasqueradeBrandMark(compact: Boolean = false, modifier: Modifier = Modifier) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        Icon(
            Icons.Default.TheaterComedy,
            contentDescription = null,
            tint = MatteryaColors.ink,
            modifier = Modifier.size(if (compact) 22.dp else 28.dp),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            MatteryaCopy.matteryaMasquerade,
            fontFamily = FontFamily.Serif,
            fontWeight = FontWeight.SemiBold,
            fontSize = if (compact) 18.sp else 22.sp,
            color = MatteryaColors.ink,
            maxLines = 1,
        )
    }
}

@Composable
fun AnonymousEmptyState(
    title: String,
    message: String,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Default.TheaterComedy,
            contentDescription = null,
            tint = MatteryaColors.inkMuted,
            modifier = Modifier.size(40.dp),
        )
        Spacer(Modifier.height(16.dp))
        Text(title, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink, fontSize = 18.sp)
        Spacer(Modifier.height(8.dp))
        Text(message, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
        if (actionTitle != null && onAction != null) {
            Spacer(Modifier.height(16.dp))
            TextButton(onClick = onAction) {
                Text(actionTitle, color = MatteryaColors.accent)
            }
        }
    }
}

@Composable
fun AnonymousLoadingSkeleton() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(color = MatteryaColors.accent)
    }
}

@Composable
fun AnonymousPrivacyCard(modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
            .padding(16.dp),
    ) {
        Text("Privacy boundary", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
        Spacer(Modifier.height(8.dp))
        Text(MatteryaCopy.anonymousPrivacyBoundary, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
    }
}

enum class AnonymousPostCardStyle { Feed, Space, Profile, Thread }

@Composable
fun AnonymousPostCard(
    post: AnonymousPost,
    style: AnonymousPostCardStyle = AnonymousPostCardStyle.Feed,
    onOpen: () -> Unit,
    onOpenSpace: (() -> Unit)? = null,
    onOpenAuthor: (() -> Unit)? = null,
    onVote: ((Int) -> Unit)? = null,
) {
    var photoLightbox by remember(post.id) { mutableStateOf(false) }
    var pinching by remember(post.id) { mutableStateOf(false) }
    val corner = if (style == AnonymousPostCardStyle.Feed) 0.dp else 10.dp
    val bodyMaxLines = if (style == AnonymousPostCardStyle.Thread) Int.MAX_VALUE else 8

    Column(
        Modifier
            .fillMaxWidth()
            .zIndex(if (pinching) 80f else 0f)
            .clickable(onClick = onOpen)
            .background(MatteryaColors.surface)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (style == AnonymousPostCardStyle.Feed && !post.spaceTitle.isNullOrBlank()) {
                Text(
                    post.spaceTitle ?: "",
                    color = MatteryaColors.accent,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clickable(enabled = onOpenSpace != null) {
                        onOpenSpace?.invoke()
                    },
                )
                Spacer(Modifier.width(8.dp))
            }
            Text(
                "@${post.authorUsername}",
                color = MatteryaColors.inkMuted,
                fontSize = 13.sp,
                modifier = Modifier.clickable(enabled = onOpenAuthor != null) {
                    onOpenAuthor?.invoke()
                },
            )
            if (post.isFlagged) {
                Spacer(Modifier.width(8.dp))
                Text("Flagged", color = MatteryaColors.danger, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        post.displayTitle?.let {
            Spacer(Modifier.height(6.dp))
            Text(it, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink, fontSize = 16.sp)
        }
        if (post.displayBody.isNotBlank()) {
            Spacer(Modifier.height(4.dp))
            Text(post.displayBody, color = MatteryaColors.ink, fontSize = 15.sp, maxLines = bodyMaxLines)
        }
        AnonymousPostMediaBlock(
            post = post,
            style = style,
            corner = corner,
            onPinchingChanged = { pinching = it },
            onOpenLightbox = { photoLightbox = true },
        )
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Filled.KeyboardArrowUp,
                contentDescription = "Upvote",
                tint = if (post.myVote == 1) MatteryaColors.accent else MatteryaColors.inkMuted,
                modifier = Modifier
                    .size(22.dp)
                    .clickable(enabled = onVote != null) { onVote?.invoke(1) },
            )
            Text(
                "${post.score ?: 0}",
                color = MatteryaColors.ink,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
            Icon(
                Icons.Filled.KeyboardArrowDown,
                contentDescription = "Downvote",
                tint = if (post.myVote == -1) MatteryaColors.accent else MatteryaColors.inkMuted,
                modifier = Modifier
                    .size(22.dp)
                    .clickable(enabled = onVote != null) { onVote?.invoke(-1) },
            )
            Spacer(Modifier.width(16.dp))
            Icon(
                Icons.Default.ChatBubbleOutline,
                contentDescription = null,
                tint = MatteryaColors.inkMuted,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(4.dp))
            Text("${post.commentCount ?: 0}", color = MatteryaColors.inkMuted, fontSize = 13.sp)
        }
        Spacer(Modifier.height(8.dp))
        Box(
            Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(MatteryaColors.divider),
        )
    }

    val imageUrl = post.usableMediaUrl
    if (photoLightbox && post.hasImage && imageUrl != null) {
        MatteryaPhotoLightbox(url = imageUrl, onClose = { photoLightbox = false })
    }
}

@Composable
private fun AnonymousPostMediaBlock(
    post: AnonymousPost,
    style: AnonymousPostCardStyle,
    corner: androidx.compose.ui.unit.Dp,
    onPinchingChanged: (Boolean) -> Unit,
    onOpenLightbox: () -> Unit,
) {
    val mediaUrl = post.usableMediaUrl
    val thumbUrl = post.usableThumbUrl
    when {
        post.hasImage && mediaUrl != null -> {
            Spacer(Modifier.height(8.dp))
            // Feed: full-bleed; thread/space: rounded. Aspect ~4:3 until real size known.
            Box(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(4f / 3f)
                    .clip(RoundedCornerShape(corner))
                    .background(MatteryaColors.canvasMuted)
                    .then(
                        if (style == AnonymousPostCardStyle.Feed) Modifier
                        else Modifier.border(0.5.dp, MatteryaColors.border.copy(alpha = 0.7f), RoundedCornerShape(corner)),
                    ),
            ) {
                FeedPinchZoomPhoto(
                    url = mediaUrl,
                    contentScale = ContentScale.Crop,
                    onTap = onOpenLightbox,
                    onZoomingChanged = onPinchingChanged,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        post.hasVideo && mediaUrl != null -> {
            Spacer(Modifier.height(8.dp))
            if (style == AnonymousPostCardStyle.Thread) {
                MasqueradeInFrameVideo(
                    url = mediaUrl,
                    posterUrl = thumbUrl,
                    height = 380.dp,
                    cornerRadius = corner,
                )
            } else {
                MasqueradeVideoPoster(
                    videoUrl = mediaUrl,
                    posterUrl = thumbUrl,
                    height = 240.dp,
                    cornerRadius = corner.coerceAtLeast(10.dp),
                )
            }
        }
        post.hasVideo -> {
            Spacer(Modifier.height(8.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(if (style == AnonymousPostCardStyle.Thread) 280.dp else 240.dp)
                    .clip(RoundedCornerShape(corner.coerceAtLeast(10.dp)))
                    .background(MatteryaColors.ink),
                contentAlignment = Alignment.Center,
            ) {
                Text("Video unavailable", color = MatteryaColors.inkMuted, fontSize = 13.sp)
            }
        }
        mediaUrl != null || thumbUrl != null -> {
            val url = mediaUrl ?: thumbUrl
            if (url != null) {
                Spacer(Modifier.height(8.dp))
                MasqueradeVideoPoster(
                    videoUrl = url,
                    posterUrl = thumbUrl,
                    height = 200.dp,
                    cornerRadius = 12.dp,
                )
            }
        }
    }
}

@Composable
fun AnonymousSpaceRow(
    space: AnonymousSpace,
    joined: Boolean,
    busy: Boolean,
    onOpen: () -> Unit,
    onToggleJoin: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(MatteryaColors.canvasMuted),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                space.title.take(1).uppercase(),
                fontWeight = FontWeight.Bold,
                color = MatteryaColors.ink,
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(space.title, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            val meta = buildList {
                add("${space.memberCount ?: 0} members")
                space.category?.let { add(it) }
                if (space.isPaid) add(space.priceLabel ?: "Paid")
            }.joinToString(" · ")
            Text(meta, color = MatteryaColors.inkMuted, fontSize = 12.sp)
        }
        TextButton(onClick = onToggleJoin, enabled = !busy && !space.isPaid) {
            Text(
                when {
                    busy -> "…"
                    space.isPaid -> "Paid"
                    joined -> "Joined"
                    else -> "Join"
                },
                color = if (joined) MatteryaColors.inkMuted else MatteryaColors.accent,
            )
        }
    }
}
