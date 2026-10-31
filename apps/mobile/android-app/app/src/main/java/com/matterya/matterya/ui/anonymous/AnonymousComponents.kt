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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.HeartBroken
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.HeartBroken
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.matterya.matterya.model.AnonymousComment
import com.matterya.matterya.model.AnonymousPost
import com.matterya.matterya.model.AnonymousSpace
import com.matterya.matterya.model.RelativeTime
import com.matterya.matterya.theme.FacebookMediaLayout
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.theme.MatteryaReportCategories
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.FeedPinchZoomPhoto
import com.matterya.matterya.ui.components.MasqueradeInFrameVideo
import com.matterya.matterya.ui.components.MasqueradeVideoPoster
import com.matterya.matterya.ui.components.MatteryaPhotoLightbox
import com.matterya.matterya.ui.components.MatteryaVerifiedBadge
import kotlin.math.max
import kotlin.math.min

@Composable
fun MasqueradeBrandMark(compact: Boolean = false, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
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
        if (compact) {
            Text(
                MatteryaCopy.anonymousModeChip,
                color = MatteryaColors.inkMuted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(start = 30.dp, top = 1.dp),
            )
        }
    }
}

/** iOS `MasqueradePushChrome` — always-visible Back row on Space/post/chat overlays. */
@Composable
fun MasqueradePushChrome(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    trailing: @Composable (() -> Unit)? = null,
) {
    Box(
        modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface.copy(alpha = 0.96f))
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 4.dp),
    ) {
        Text(
            title,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.ink,
            fontSize = 17.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = 72.dp),
        )
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier
                    .clickable(onClick = onBack)
                    .padding(vertical = 10.dp, horizontal = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                    contentDescription = null,
                    tint = MatteryaColors.ink,
                    modifier = Modifier.size(22.dp),
                )
                Text("Back", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            }
            Spacer(Modifier.weight(1f))
            trailing?.invoke()
        }
    }
    Box(
        Modifier
            .fillMaxWidth()
            .height(0.5.dp)
            .background(MatteryaColors.divider),
    )
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
    onReport: ((String) -> Unit)? = null,
    onBlockAuthor: (() -> Unit)? = null,
    /** Cached comments for feed tease (iOS AnonymousCommentsWarmCache). */
    warmComments: List<AnonymousComment> = emptyList(),
    onWarmComments: (() -> Unit)? = null,
) {
    var photoLightbox by remember(post.id) { mutableStateOf(false) }
    var pinching by remember(post.id) { mutableStateOf(false) }
    var menuOpen by remember(post.id) { mutableStateOf(false) }
    var showReport by remember(post.id) { mutableStateOf(false) }
    var photoPixelSize by remember(post.id) { mutableStateOf<Pair<Int, Int>?>(null) }
    var teasedComment by remember(post.id) { mutableStateOf<AnonymousComment?>(null) }
    val corner = if (style == AnonymousPostCardStyle.Feed) 0.dp else 10.dp
    val bodyMaxLines = if (style == AnonymousPostCardStyle.Thread) Int.MAX_VALUE else 6
    val myVote = post.myVote ?: 0
    val liked = myVote > 0
    val disliked = myVote < 0
    val commentCount = (post.commentCount ?: 0).coerceAtLeast(0)
    val commentsLabel = when (commentCount) {
        0 -> "Add a comment"
        1 -> "1 comment"
        else -> "$commentCount comments"
    }
    val spaceLabel = post.spaceTitle?.trim()?.takeIf { it.isNotEmpty() }
        ?: post.spaceSlug?.trim()?.takeIf { it.isNotEmpty() }
    val isOfficial = post.authorUsername.trim().equals("matterya", ignoreCase = true)
    val bodyText = post.displayBody.trim()
    val showsSeeMore = style != AnonymousPostCardStyle.Thread &&
        (bodyText.length > 160 || bodyText.count { it == '\n' } > 4)
    val photoAspect = remember(photoPixelSize) {
        val px = photoPixelSize
        if (px == null || px.first <= 1 || px.second <= 1) {
            FacebookMediaLayout.photoSquareAspect
        } else {
            val raw = px.first.toFloat() / px.second.toFloat()
            if (!raw.isFinite() || raw <= 0.05f) FacebookMediaLayout.photoSquareAspect
            else min(max(raw, 0.33f), 2.5f)
        }
    }

    fun pickTease(list: List<AnonymousComment>): AnonymousComment? =
        list.maxByOrNull { it.score ?: 0 } ?: list.firstOrNull()

    LaunchedEffect(post.id, style, commentCount) {
        if (style != AnonymousPostCardStyle.Feed || commentCount <= 0) return@LaunchedEffect
        if (warmComments.isEmpty()) onWarmComments?.invoke()
    }

    LaunchedEffect(warmComments, style, commentCount) {
        if (style != AnonymousPostCardStyle.Feed || commentCount <= 0) {
            teasedComment = null
            return@LaunchedEffect
        }
        teasedComment = pickTease(warmComments)
    }

    Column(
        Modifier
            .fillMaxWidth()
            .zIndex(if (pinching) 80f else 0f)
            .background(MatteryaColors.surface)
            .padding(vertical = 16.dp),
    ) {
        // Meta · title · body — padded. Media is full-bleed on feed.
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.pagePadding),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (isOfficial) {
                    AvatarView(url = null, seed = "matterya", size = 22.dp)
                    Spacer(Modifier.width(6.dp))
                }
                if (style == AnonymousPostCardStyle.Feed && spaceLabel != null) {
                    Text(
                        spaceLabel,
                        color = MatteryaColors.ink,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .weight(1f, fill = false)
                            .clickable(enabled = onOpenSpace != null) { onOpenSpace?.invoke() },
                    )
                    Text(" · ", color = MatteryaColors.inkMuted, fontSize = 12.sp)
                }
                if (isOfficial) {
                    Text(
                        "Matterya",
                        color = MatteryaColors.ink,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                    )
                    Spacer(Modifier.width(4.dp))
                    MatteryaVerifiedBadge(size = 13.dp)
                } else {
                    Text(
                        "@${post.authorUsername}",
                        color = MatteryaColors.inkMuted,
                        fontSize = 14.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .weight(1f, fill = false)
                            .clickable(enabled = onOpenAuthor != null) { onOpenAuthor?.invoke() },
                    )
                }
                Spacer(Modifier.weight(1f))
                if (post.createdAt.isNotBlank()) {
                    Text(
                        RelativeTime.format(post.createdAt),
                        color = MatteryaColors.inkMuted,
                        fontSize = 12.sp,
                    )
                }
                Box {
                    IconButton(
                        onClick = { menuOpen = true },
                        modifier = Modifier.size(28.dp),
                    ) {
                        Icon(
                            Icons.Default.MoreHoriz,
                            contentDescription = "Post options",
                            tint = MatteryaColors.inkMuted,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("Report", color = MatteryaColors.danger) },
                            leadingIcon = {
                                Icon(Icons.Default.Flag, null, tint = MatteryaColors.danger)
                            },
                            onClick = {
                                menuOpen = false
                                showReport = true
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Block author", color = MatteryaColors.danger) },
                            onClick = {
                                menuOpen = false
                                onBlockAuthor?.invoke()
                            },
                            enabled = onBlockAuthor != null && post.authorProfileId.isNotBlank(),
                        )
                    }
                }
            }

            post.displayTitle?.takeIf { it.isNotEmpty() }?.let { title ->
                Spacer(Modifier.height(10.dp))
                Text(
                    title,
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.Normal,
                    color = MatteryaColors.ink,
                    fontSize = 22.sp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onOpen),
                )
            }

            if (post.isFlagged) {
                Spacer(Modifier.height(8.dp))
                Row(
                    Modifier
                        .background(MatteryaColors.accentSoft, RoundedCornerShape(50))
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Default.Flag, null, tint = MatteryaColors.accent, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Flagged", color = MatteryaColors.accent, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            if (bodyText.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    bodyText,
                    color = MatteryaColors.inkSecondary,
                    fontSize = 15.sp,
                    maxLines = bodyMaxLines,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onOpen),
                )
                if (showsSeeMore) {
                    Text(
                        "See more",
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.ink,
                        fontSize = 14.sp,
                        modifier = Modifier
                            .padding(top = 4.dp)
                            .clickable(onClick = onOpen),
                    )
                }
            }
        }

        AnonymousPostMediaBlock(
            post = post,
            style = style,
            corner = corner,
            photoAspect = photoAspect,
            onPinchingChanged = { pinching = it },
            onOpenLightbox = { photoLightbox = true },
            onImageSize = { w, h ->
                if (w > 1 && h > 1 && photoPixelSize != (w to h)) {
                    photoPixelSize = w to h
                }
            },
        )

        // Hearts · score · comments — not Reddit up/down arrows.
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(top = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier
                    .background(MatteryaColors.canvasMuted, RoundedCornerShape(50))
                    .padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    if (liked) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                    contentDescription = if (liked) "Remove like" else "Like",
                    tint = if (liked) MatteryaColors.like else MatteryaColors.inkMuted,
                    modifier = Modifier
                        .size(36.dp)
                        .clickable(enabled = onVote != null) {
                            onVote?.invoke(if (liked) 0 else 1)
                        }
                        .padding(9.dp),
                )
                Text(
                    "${post.score ?: 0}",
                    color = if (liked || disliked) MatteryaColors.ink else MatteryaColors.inkMuted,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 2.dp),
                )
                Icon(
                    if (disliked) Icons.Filled.HeartBroken else Icons.Outlined.HeartBroken,
                    contentDescription = if (disliked) "Remove dislike" else "Dislike",
                    tint = if (disliked) MatteryaColors.ink else MatteryaColors.inkMuted,
                    modifier = Modifier
                        .size(36.dp)
                        .clickable(enabled = onVote != null) {
                            onVote?.invoke(if (disliked) 0 else -1)
                        }
                        .padding(9.dp),
                )
            }
            Spacer(Modifier.width(14.dp))
            Row(
                Modifier
                    .background(MatteryaColors.canvasMuted, RoundedCornerShape(50))
                    .clickable(enabled = style != AnonymousPostCardStyle.Thread, onClick = onOpen)
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.ChatBubbleOutline,
                    contentDescription = null,
                    tint = if (commentCount > 0) MatteryaColors.ink else MatteryaColors.inkMuted,
                    modifier = Modifier.size(15.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    commentsLabel,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    color = if (commentCount > 0) MatteryaColors.ink else MatteryaColors.inkMuted,
                )
            }
        }

        if (style == AnonymousPostCardStyle.Feed) {
            teasedComment?.let { tease ->
                Spacer(Modifier.height(10.dp))
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = MatteryaDimens.pagePadding)
                        .clip(RoundedCornerShape(12.dp))
                        .background(MatteryaColors.canvasMuted.copy(alpha = 0.85f))
                        .clickable(onClick = onOpen)
                        .padding(12.dp),
                ) {
                    Box(
                        Modifier
                            .width(3.dp)
                            .height(36.dp)
                            .background(MatteryaColors.ink.copy(alpha = 0.18f), RoundedCornerShape(1.5.dp)),
                    )
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            "@${tease.authorUsername}",
                            color = MatteryaColors.inkMuted,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            tease.displayBody,
                            color = MatteryaColors.inkSecondary,
                            fontSize = 14.sp,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(MatteryaColors.divider),
            )
        }
    }

    val imageUrl = post.usableMediaUrl
    if (photoLightbox && post.hasImage && imageUrl != null) {
        MatteryaPhotoLightbox(url = imageUrl, onClose = { photoLightbox = false })
    }

    if (showReport) {
        MatteryaReportDialog(
            title = "Report post",
            onDismiss = { showReport = false },
            onReason = { label ->
                showReport = false
                onReport?.invoke(MatteryaReportCategories.slugForLabel(label))
            },
        )
    }
}

@Composable
fun MatteryaReportDialog(
    title: String,
    onDismiss: () -> Unit,
    onReason: (String) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, color = MatteryaColors.ink) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                MatteryaReportCategories.all.forEach { item ->
                    Text(
                        item.label,
                        color = MatteryaColors.danger,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onReason(item.label) }
                            .padding(vertical = 12.dp),
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = MatteryaColors.inkMuted)
            }
        },
        containerColor = MatteryaColors.surface,
    )
}

@Composable
private fun AnonymousPostMediaBlock(
    post: AnonymousPost,
    style: AnonymousPostCardStyle,
    corner: androidx.compose.ui.unit.Dp,
    photoAspect: Float,
    onPinchingChanged: (Boolean) -> Unit,
    onOpenLightbox: () -> Unit,
    onImageSize: (Int, Int) -> Unit,
) {
    val mediaUrl = post.usableMediaUrl
    val thumbUrl = post.usableThumbUrl
    val feedBleed = style == AnonymousPostCardStyle.Feed
    when {
        post.hasImage && mediaUrl != null -> {
            Spacer(Modifier.height(8.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .then(if (feedBleed) Modifier else Modifier.padding(horizontal = MatteryaDimens.pagePadding))
                    .aspectRatio(photoAspect)
                    .clip(RoundedCornerShape(corner))
                    .background(MatteryaColors.canvasMuted)
                    .then(
                        if (feedBleed) Modifier
                        else Modifier.border(0.5.dp, MatteryaColors.border.copy(alpha = 0.7f), RoundedCornerShape(corner)),
                    ),
            ) {
                FeedPinchZoomPhoto(
                    url = mediaUrl,
                    contentScale = ContentScale.Crop,
                    onTap = onOpenLightbox,
                    onZoomingChanged = onPinchingChanged,
                    onImageSize = onImageSize,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        post.hasVideo && mediaUrl != null -> {
            Spacer(Modifier.height(8.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .then(if (feedBleed) Modifier else Modifier.padding(horizontal = MatteryaDimens.pagePadding)),
            ) {
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
                        cornerRadius = corner.coerceAtLeast(if (feedBleed) 0.dp else 10.dp),
                    )
                }
            }
        }
        post.hasVideo -> {
            Spacer(Modifier.height(8.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .then(if (feedBleed) Modifier else Modifier.padding(horizontal = MatteryaDimens.pagePadding))
                    .height(if (style == AnonymousPostCardStyle.Thread) 280.dp else 240.dp)
                    .clip(RoundedCornerShape(corner.coerceAtLeast(if (feedBleed) 0.dp else 10.dp)))
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
                Box(
                    Modifier
                        .fillMaxWidth()
                        .then(if (feedBleed) Modifier else Modifier.padding(horizontal = MatteryaDimens.pagePadding)),
                ) {
                    MasqueradeVideoPoster(
                        videoUrl = url,
                        posterUrl = thumbUrl,
                        height = 200.dp,
                        cornerRadius = if (feedBleed) 0.dp else 12.dp,
                    )
                }
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
        TextButton(
            onClick = onToggleJoin,
            enabled = !busy && !(space.isPaid && !joined),
        ) {
            Text(
                when {
                    busy -> "…"
                    space.isPaid && !joined -> "Paid"
                    joined -> "Joined"
                    else -> "Join"
                },
                color = if (joined) MatteryaColors.inkMuted else MatteryaColors.accent,
            )
        }
    }
}
