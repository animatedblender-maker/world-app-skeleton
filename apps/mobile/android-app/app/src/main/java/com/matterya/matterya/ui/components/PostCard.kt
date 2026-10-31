package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Reply
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.hubs.HubVideoSeedService
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.data.posts.PostsService
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.HubChannelPostMarker
import com.matterya.matterya.model.HubOriginShareMarker
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.SparkShareMarker
import com.matterya.matterya.theme.ContentSanitizer
import com.matterya.matterya.theme.FacebookMediaLayout
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import kotlinx.coroutines.launch

/**
 * Full feed post card — **line-by-line structure from iOS `FacebookPostCard`**.
 *
 * Layout order (iOS body):
 * 1. authorHeader (hand-drawn avatar, name, Follow, sharedBy / location, time, ⋯, ↗)
 * 2. image caption above photo (image-only posts)
 * 3. media branch: SparkFeedCard | shared embed | PlayFeedLinkCard | media
 * 4. caption below (non-image)
 * 5. actions (heart, bubble, share, bookmark)
 * 6. meta (likes, view N comments)
 * 7. inline PostCommentsView when expanded
 * 8. bottom divider + 10dp pad when edgeToEdge
 */
@Composable
fun PostCard(
    post: CountryPost,
    onLike: () -> Unit,
    onUpdated: (CountryPost) -> Unit = {},
    onOpenPost: () -> Unit = {},
    onOpenAuthor: () -> Unit = {},
    onOpenVideo: () -> Unit = {},
    onOpenReel: () -> Unit = {},
    onShare: () -> Unit = {},
    onSave: () -> Unit = {},
    onToggleFollow: (suspend () -> Unit)? = null,
    isFollowingAuthor: Boolean = false,
    isPostSaved: Boolean = post.savedByMe,
    currentUserId: String? = null,
    currentProfile: Profile? = null,
    commentsInitiallyExpanded: Boolean = false,
    /**
     * iOS home feed uses `showsAuthorHeader: false` + `showsAuthorInJournal: true`
     * (journal header: trailing timestamp, title under row).
     */
    showsAuthorHeader: Boolean = true,
    showsAuthorInJournal: Boolean = false,
    edgeToEdge: Boolean = true,
    viewingCountryIso: String? = null,
    /** iOS AppState.feedVideosMuted — all feed players stay in sync. */
    feedVideosMuted: Boolean = false,
    onFeedVideosMutedChange: (Boolean) -> Unit = {},
    surfaceLive: Boolean = true,
    reelsOpen: Boolean = false,
    hubPlaying: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val resolvedCurrentUserId = currentUserId ?: currentProfile?.userId
    var commentsExpanded by remember(post.id) { mutableStateOf(commentsInitiallyExpanded) }
    var loadedCommentCount by remember(post.id) { mutableIntStateOf(post.displayCommentCount) }
    var menuOpen by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val postsService = remember { PostsService() }

    val opensAsSpark = PlayPlatformBridge.isSparkFeedCard(post)
    val isFeedReshare = isFeedReshareCard(post)
    val showsPlayLink = PlayPlatformBridge.showsPlayLinkInFeed(post)
    val isImageOnly = post.hasImage && !post.hasVideo && !post.isReel &&
        !post.isStory && post.sharedPost == null

    val effectiveCommentCount = maxOf(post.displayCommentCount, loadedCommentCount)
    // iOS meta uses post.likeCount (not displayLikeCount) in the Text — but shares show 0.
    // Prefer displayLikeCount so origin engagement appears (iOS model often hydrates share counts).
    val effectiveLikeCount = post.displayLikeCount

    val primaryName = if (isFeedReshare) {
        post.authorDisplayName
    } else {
        PlayPlatformBridge.displayCreator(post).name
    }
    val primaryAvatar = if (isFeedReshare) {
        post.author?.avatarUrl
    } else {
        PlayPlatformBridge.displayCreator(post).avatarUrl
    }
    val primarySeed = if (isFeedReshare) {
        post.authorId
    } else {
        PlayPlatformBridge.displayCreator(post).seed
    }
    val followId = if (isFeedReshare) {
        post.authorId
    } else {
        PlayPlatformBridge.displayCreator(post).authorId
    }
    val isOwn = resolvedCurrentUserId != null && post.authorId == resolvedCurrentUserId
    val showFollow = !isOwn && followId.isNotBlank() && followId != resolvedCurrentUserId && onToggleFollow != null

    val sharedByLine = remember(post.id, isFeedReshare) {
        if (!isFeedReshare) null
        else originChannelDisplayName(post)?.let { "Shared from $it" }
    }

    val captionBody = ContentSanitizer.rebrandCompetitorNames(
        ContentSanitizer.stripInternalMarkers(post.displayBody),
    )
    val captionExcerpt = ContentSanitizer.rebrandCompetitorNames(
        ContentSanitizer.stripInternalMarkers(post.displayExcerpt),
    )

    val sparkPresentation = remember(post.id, post.mediaUrl) {
        sparkCardPresentationPost(post)
    }

    LaunchedEffect(post.id) {
        loadedCommentCount = maxOf(loadedCommentCount, post.displayCommentCount)
        if (commentsInitiallyExpanded) commentsExpanded = true
        // Soft-hydrate comment count for shares with 0 on the share row.
        if (post.displayCommentCount == 0 &&
            (post.isSparkFeedShare || post.sharedPostId != null)
        ) {
            val loaded = runCatching {
                postsService.listComments(
                    postId = post.id,
                    limit = 200,
                    body = post.body,
                    sharedPostId = post.sharedPostId,
                    originPostId = post.originPostId,
                )
            }.getOrDefault(emptyList())
            if (loaded.isNotEmpty()) {
                loadedCommentCount = maxOf(loadedCommentCount, loaded.size)
            }
        }
    }

    Column(
        modifier
            .fillMaxWidth()
            .background(if (edgeToEdge) MatteryaColors.canvas else MatteryaColors.surface),
    ) {
        // ── 1. Header — iOS: authorHeader OR journalHeader ───────────
        // Home feed: showsAuthorHeader=false, showsAuthorInJournal=true.
        if (showsAuthorHeader) {
            AuthorHeader(
                primaryName = ContentSanitizer.displayName(
                    primaryName, null, primaryName,
                ),
                avatarUrl = primaryAvatar,
                avatarSeed = primarySeed.ifEmpty { primaryName },
                sharedByLine = sharedByLine,
                locationLabel = if (sharedByLine == null) post.authorLocationLabel else null,
                relativeTime = post.relativeTime,
                showFollow = showFollow,
                isFollowing = isFollowingAuthor,
                onFollow = onToggleFollow,
                followId = followId,
                isOwn = isOwn,
                menuOpen = menuOpen,
                onMenuOpenChange = { menuOpen = it },
                onOpenAuthor = onOpenAuthor,
                onOpenPrimary = {
                    if (opensAsSpark) onOpenReel() else onOpenPost()
                },
                postedFromLabel = postedFromLabel(post, viewingCountryIso),
            )
        } else {
            JournalHeader(
                showAuthor = showsAuthorInJournal,
                primaryName = ContentSanitizer.displayName(
                    primaryName, null, primaryName,
                ),
                avatarUrl = primaryAvatar,
                avatarSeed = primarySeed.ifEmpty { primaryName },
                sharedByLine = sharedByLine,
                locationLabel = if (sharedByLine == null) post.authorLocationLabel else null,
                relativeTime = post.relativeTime,
                isEdited = post.isEdited,
                showFollow = showFollow,
                isFollowing = isFollowingAuthor,
                onFollow = onToggleFollow,
                followId = followId,
                isOwn = isOwn,
                menuOpen = menuOpen,
                onMenuOpenChange = { menuOpen = it },
                onOpenAuthor = onOpenAuthor,
                onOpenPrimary = {
                    if (opensAsSpark) onOpenReel() else onOpenPost()
                },
                postedFromLabel = postedFromLabel(post, viewingCountryIso),
                displayTitle = post.displayTitle,
                hubChannelLine = hubChannelAttributionLine(post, isFeedReshare, sharedByLine, showsPlayLink),
                hasBottomContent = post.displayTitle != null || showsPlayLink || isImageOnly,
            )
        }

        // ── 2. Image-only caption above media ────────────────────────
        if (isImageOnly && captionBody.isNotEmpty()) {
            CaptionBlock(
                text = captionBody,
                top = 4.dp,
                bottom = 10.dp,
                onTap = onOpenPost,
            )
        }

        // ── 3. Media branches (iOS order) ─────────────────────────────
        when {
            opensAsSpark -> {
                SparkFeedCard(
                    post = sparkPresentation,
                    edgeToEdge = edgeToEdge,
                    feedVideosMuted = feedVideosMuted,
                    onFeedVideosMutedChange = onFeedVideosMutedChange,
                    surfaceLive = surfaceLive,
                    reelsOpen = reelsOpen,
                    hubPlaying = hubPlaying,
                    onOpen = onOpenReel,
                )
            }
            post.sharedPost != null && !showsPlayLink -> {
                // Shared original embed — iOS SharedPostEmbedView branches
                val embed = post.sharedPost!!.asCountryPost
                when {
                    PlayPlatformBridge.isSparkFeedCard(embed) || embed.isReel -> {
                        SparkFeedCard(
                            post = embed,
                            edgeToEdge = edgeToEdge,
                            feedVideosMuted = feedVideosMuted,
                            onFeedVideosMutedChange = onFeedVideosMutedChange,
                            surfaceLive = surfaceLive,
                            reelsOpen = reelsOpen,
                            hubPlaying = hubPlaying,
                            onOpen = onOpenReel,
                        )
                    }
                    PlayPlatformBridge.isHubFeedCardVideo(embed) ||
                        (PlayPlatformBridge.isLongFormVideo(embed) &&
                            PlayPlatformBridge.isHubCatalogContent(embed)) -> {
                        PlayFeedLinkCard(
                            post = embed,
                            edgeToEdge = edgeToEdge,
                            forceHubsBadge = true,
                            feedVideosMuted = feedVideosMuted,
                            onFeedVideosMutedChange = onFeedVideosMutedChange,
                            surfaceLive = surfaceLive,
                            reelsOpen = reelsOpen,
                            hubPlaying = hubPlaying,
                            onOpen = onOpenVideo,
                        )
                    }
                    PlayPlatformBridge.isLongFormVideo(embed) -> {
                        PlayFeedLinkCard(
                            post = embed,
                            edgeToEdge = edgeToEdge,
                            forceHubsBadge = false,
                            feedVideosMuted = feedVideosMuted,
                            onFeedVideosMutedChange = onFeedVideosMutedChange,
                            surfaceLive = surfaceLive,
                            reelsOpen = reelsOpen,
                            hubPlaying = hubPlaying,
                            onOpen = onOpenVideo,
                        )
                    }
                    else -> {
                        FeedMediaBlock(
                            post = embed,
                            edgeToEdge = edgeToEdge,
                            feedVideosMuted = feedVideosMuted,
                            onFeedVideosMutedChange = onFeedVideosMutedChange,
                            surfaceLive = surfaceLive,
                            reelsOpen = reelsOpen,
                            hubPlaying = hubPlaying,
                            onOpen = onOpenPost,
                            onOpenVideo = onOpenVideo,
                        )
                    }
                }
            }
            showsPlayLink -> {
                PlayFeedLinkCard(
                    post = post,
                    edgeToEdge = edgeToEdge,
                    forceHubsBadge = PlayPlatformBridge.isHubCatalogContent(post),
                    feedVideosMuted = feedVideosMuted,
                    onFeedVideosMutedChange = onFeedVideosMutedChange,
                    surfaceLive = surfaceLive,
                    reelsOpen = reelsOpen,
                    hubPlaying = hubPlaying,
                    onOpen = onOpenVideo,
                )
            }
            post.hasMedia || post.hasVideo || post.thumbUrl != null || post.mediaUrl != null -> {
                FeedMediaBlock(
                    post = post,
                    edgeToEdge = edgeToEdge,
                    feedVideosMuted = feedVideosMuted,
                    onFeedVideosMutedChange = onFeedVideosMutedChange,
                    surfaceLive = surfaceLive,
                    reelsOpen = reelsOpen,
                    hubPlaying = hubPlaying,
                    onOpen = onOpenPost,
                    onOpenVideo = onOpenVideo,
                )
            }
        }

        // ── 4. Caption below media (non image-only) ──────────────────
        if (!isImageOnly && captionExcerpt.isNotEmpty()) {
            val topPad = if (
                post.hasMedia || opensAsSpark || showsPlayLink || post.sharedPost != null
            ) 12.dp else 10.dp
            CaptionBlock(
                text = captionExcerpt,
                top = topPad,
                bottom = 4.dp,
                onTap = { if (opensAsSpark) onOpenReel() else onOpenPost() },
            )
        }

        // ── 5. Actions ───────────────────────────────────────────────
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.feedTextInset, vertical = 0.dp)
                .padding(top = 10.dp, bottom = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // iOS action icons are ~22pt (not 26) — oversized icons look "off".
            Icon(
                if (post.likedByMe) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                contentDescription = "Like",
                tint = if (post.likedByMe) MatteryaColors.like else MatteryaColors.ink,
                modifier = Modifier
                    .size(22.dp)
                    .clickable(onClick = onLike),
            )
            Icon(
                if (commentsExpanded) Icons.Filled.ChatBubble else Icons.Outlined.ChatBubbleOutline,
                contentDescription = "Comments",
                tint = if (commentsExpanded) MatteryaColors.ink else MatteryaColors.inkMuted,
                modifier = Modifier
                    .size(22.dp)
                    .clickable { commentsExpanded = !commentsExpanded },
            )
            Icon(
                Icons.AutoMirrored.Outlined.Reply,
                contentDescription = "Share",
                tint = MatteryaColors.ink,
                modifier = Modifier
                    .size(21.dp)
                    .clickable(onClick = onShare),
            )
            Icon(
                if (isPostSaved) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                contentDescription = "Save",
                tint = if (isPostSaved) MatteryaColors.ink else MatteryaColors.inkMuted,
                modifier = Modifier
                    .size(21.dp)
                    .clickable(onClick = onSave),
            )
            Spacer(Modifier.weight(1f))
        }

        // ── 6. Meta ──────────────────────────────────────────────────
        Column(
            Modifier.padding(
                horizontal = MatteryaDimens.feedTextInset,
                vertical = 0.dp,
            ).padding(bottom = if (commentsExpanded) 4.dp else 14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (effectiveLikeCount > 0) {
                Text(
                    if (effectiveLikeCount == 1) "1 like" else "$effectiveLikeCount likes",
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                    color = MatteryaColors.ink,
                )
            }
            if (effectiveCommentCount > 0 && !commentsExpanded) {
                Text(
                    if (effectiveCommentCount == 1) {
                        "View 1 comment"
                    } else {
                        "View $effectiveCommentCount comments"
                    },
                    fontSize = 15.sp,
                    color = MatteryaColors.inkMuted,
                    modifier = Modifier.clickable { commentsExpanded = true },
                )
            }
        }

        // ── 7. Inline comments ───────────────────────────────────────
        if (commentsExpanded) {
            HorizontalDivider(
                thickness = 0.5.dp,
                color = MatteryaColors.divider,
                modifier = Modifier.padding(top = 8.dp),
            )
            PostCommentsView(
                post = post,
                maxVisibleComments = 3,
                currentProfile = currentProfile,
                onCommentCountDelta = { delta ->
                    loadedCommentCount = maxOf(loadedCommentCount + delta, effectiveCommentCount + delta)
                    onUpdated(post.copyEngagement(commentCount = post.displayCommentCount + delta))
                },
                onOpenProfile = { _, _ -> onOpenAuthor() },
            )
        }

        // ── 8. Edge divider ──────────────────────────────────────────
        if (edgeToEdge) {
            HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
            Spacer(Modifier.height(10.dp))
        }
    }
}

// ── Header (iOS journalHeader) — home feed path ────────────────────────────

@Composable
private fun JournalHeader(
    showAuthor: Boolean,
    primaryName: String,
    avatarUrl: String?,
    avatarSeed: String,
    sharedByLine: String?,
    locationLabel: String?,
    relativeTime: String,
    isEdited: Boolean,
    showFollow: Boolean,
    isFollowing: Boolean,
    onFollow: (suspend () -> Unit)?,
    followId: String,
    isOwn: Boolean,
    menuOpen: Boolean,
    onMenuOpenChange: (Boolean) -> Unit,
    onOpenAuthor: () -> Unit,
    onOpenPrimary: () -> Unit,
    postedFromLabel: String?,
    displayTitle: String?,
    hubChannelLine: String?,
    hasBottomContent: Boolean,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = 16.dp, bottom = if (hasBottomContent) 12.dp else 10.dp),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.feedTextInset),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (showAuthor) {
                Box(Modifier.clickable(onClick = onOpenAuthor)) {
                    AvatarView(url = avatarUrl, seed = avatarSeed, size = 36.dp)
                }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            primaryName,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = MatteryaColors.ink,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier
                                .weight(1f, fill = false)
                                .clickable(onClick = onOpenAuthor),
                        )
                        if (showFollow && onFollow != null) {
                            Spacer(Modifier.width(8.dp))
                            FollowButton(
                                userId = followId,
                                isFollowing = isFollowing,
                                isSelf = isOwn,
                                onToggle = onFollow,
                                compact = true,
                            )
                        }
                    }
                    if (sharedByLine != null) {
                        Text(sharedByLine, fontSize = 12.sp, color = MatteryaColors.inkMuted, maxLines = 1)
                    } else if (locationLabel != null) {
                        Text(locationLabel, fontSize = 12.sp, color = MatteryaColors.inkMuted, maxLines = 1)
                    }
                    if (postedFromLabel != null) {
                        Text(
                            postedFromLabel,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = MatteryaColors.accent,
                            maxLines = 1,
                            modifier = Modifier
                                .background(MatteryaColors.accentSoft, RoundedCornerShape(999.dp))
                                .padding(horizontal = 7.dp, vertical = 3.dp),
                        )
                    }
                }
            } else {
                Spacer(Modifier.weight(1f))
            }
            Spacer(Modifier.width(8.dp))
            // Trailing: options + timestamp (iOS journal header)
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box {
                    Icon(
                        Icons.Default.MoreHoriz,
                        contentDescription = "More",
                        tint = MatteryaColors.inkMuted,
                        modifier = Modifier
                            .size(28.dp)
                            .clickable { onMenuOpenChange(true) },
                    )
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { onMenuOpenChange(false) }) {
                        DropdownMenuItem(
                            text = { Text("Report") },
                            onClick = { onMenuOpenChange(false) },
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(relativeTime, fontSize = 11.sp, color = MatteryaColors.inkMuted)
                    if (isEdited) {
                        Text(
                            "Edited",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = MatteryaColors.inkMuted,
                        )
                    }
                }
            }
        }
        // Explicit post title full-width under author row (never body prefix).
        val title = displayTitle?.trim()?.takeIf { it.isNotEmpty() }
        if (title != null) {
            Text(
                title,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
                maxLines = 4,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = MatteryaDimens.feedTextInset)
                    .padding(top = 10.dp)
                    .clickable(onClick = onOpenPrimary),
            )
        }
        if (hubChannelLine != null) {
            Text(
                hubChannelLine,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.inkMuted,
                maxLines = 1,
                modifier = Modifier
                    .padding(horizontal = MatteryaDimens.feedTextInset)
                    .padding(top = if (title != null) 2.dp else 0.dp),
            )
        }
    }
}

// ── Header (iOS authorHeader) ──────────────────────────────────────────────

@Composable
private fun AuthorHeader(
    primaryName: String,
    avatarUrl: String?,
    avatarSeed: String,
    sharedByLine: String?,
    locationLabel: String?,
    relativeTime: String,
    showFollow: Boolean,
    isFollowing: Boolean,
    onFollow: (suspend () -> Unit)?,
    followId: String,
    isOwn: Boolean,
    menuOpen: Boolean,
    onMenuOpenChange: (Boolean) -> Unit,
    onOpenAuthor: () -> Unit,
    onOpenPrimary: () -> Unit,
    postedFromLabel: String?,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MatteryaDimens.feedTextInset)
            .padding(top = 14.dp, bottom = 10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(Modifier.clickable(onClick = onOpenAuthor)) {
            AvatarView(url = avatarUrl, seed = avatarSeed, size = 36.dp)
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    primaryName,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .clickable(onClick = onOpenAuthor),
                )
                if (showFollow && onFollow != null) {
                    Spacer(Modifier.width(8.dp))
                    FollowButton(
                        userId = followId,
                        isFollowing = isFollowing,
                        isSelf = isOwn,
                        onToggle = onFollow,
                        compact = true,
                    )
                }
            }
            if (sharedByLine != null) {
                Text(sharedByLine, fontSize = 12.sp, color = MatteryaColors.inkMuted, maxLines = 1)
            } else if (locationLabel != null) {
                Text(locationLabel, fontSize = 12.sp, color = MatteryaColors.inkMuted, maxLines = 1)
            }
            Text(relativeTime, fontSize = 11.sp, color = MatteryaColors.inkMuted)
            if (postedFromLabel != null) {
                Text(
                    postedFromLabel,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.accent,
                    maxLines = 1,
                    modifier = Modifier
                        .background(MatteryaColors.accentSoft, RoundedCornerShape(999.dp))
                        .padding(horizontal = 7.dp, vertical = 3.dp),
                )
            }
        }
        Spacer(Modifier.width(8.dp))
        Box {
            Icon(
                Icons.Default.MoreHoriz,
                contentDescription = "More",
                tint = MatteryaColors.inkMuted,
                modifier = Modifier
                    .size(28.dp)
                    .clickable { onMenuOpenChange(true) },
            )
            DropdownMenu(expanded = menuOpen, onDismissRequest = { onMenuOpenChange(false) }) {
                DropdownMenuItem(
                    text = { Text("Report") },
                    onClick = { onMenuOpenChange(false) },
                )
            }
        }
        Icon(
            Icons.Default.NorthEast,
            contentDescription = "Open",
            tint = MatteryaColors.inkMuted,
            modifier = Modifier
                .padding(start = 4.dp)
                .size(18.dp)
                .clickable(onClick = onOpenPrimary),
        )
    }
}

@Composable
private fun CaptionBlock(
    text: String,
    top: androidx.compose.ui.unit.Dp,
    bottom: androidx.compose.ui.unit.Dp,
    onTap: () -> Unit,
) {
    Box(
        Modifier
            .padding(horizontal = MatteryaDimens.feedTextInset)
            .padding(top = top, bottom = bottom)
            .clickable(onClick = onTap),
    ) {
        ExpandableBodyText(
            text = text,
            collapsedLineLimit = 4,
            fontSize = 16.sp,
            color = MatteryaColors.inkSecondary,
        )
    }
}

@Composable
private fun FeedMediaBlock(
    post: CountryPost,
    edgeToEdge: Boolean,
    feedVideosMuted: Boolean = false,
    onFeedVideosMutedChange: (Boolean) -> Unit = {},
    surfaceLive: Boolean = true,
    reelsOpen: Boolean = false,
    hubPlaying: Boolean = false,
    onOpen: () -> Unit,
    onOpenVideo: () -> Unit,
) {
    val config = androidx.compose.ui.platform.LocalConfiguration.current
    val density = androidx.compose.ui.platform.LocalDensity.current
    val playUrl = post.playableVideoUrl
        ?: com.matterya.matterya.data.media.MediaUrlResolver.videoUrl(post)
    BoxWithConstraintsFeed { widthPx, _ ->
        val screenH = with(density) { config.screenHeightDp.dp.toPx() }
        // iOS dominantFeedVideoHeight for feed video; photo uses aspect box.
        val h = FacebookMediaLayout.mediaHeight(widthPx, screenH, post)
        val heightDp = with(density) { h.toDp() }
        Box(
            Modifier
                .fillMaxWidth()
                .height(heightDp)
                .clipToBounds()
                .background(MatteryaColors.canvasMuted),
        ) {
            // iOS: feed autoplay video when hasVideo && playable (not spark — those use SparkFeedCard).
            if (post.hasVideo && playUrl != null) {
                InFrameVideoPlayer(
                    post = post,
                    url = playUrl,
                    posterUrl = post.posterImageUrl,
                    loops = true,
                    showsControls = true,
                    muteOnlyControls = false,
                    sharesFeedMute = true,
                    feedVideosMuted = feedVideosMuted,
                    onFeedVideosMutedChange = onFeedVideosMutedChange,
                    surfaceLive = surfaceLive,
                    reelsOpen = reelsOpen,
                    hubPlaying = hubPlaying,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                VideoThumbnailView(
                    post = post,
                    maxLogicalPx = 420,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxSize()
                        .clickable {
                            if (post.hasVideo) onOpenVideo() else onOpen()
                        },
                )
                if (post.hasVideo) {
                    HandDrawnBrushPlayButton(
                        size = 52.dp,
                        modifier = Modifier.align(Alignment.Center),
                    )
                } else {
                    Box(
                        Modifier
                            .align(Alignment.BottomCenter)
                            .fillMaxWidth()
                            .height(60.dp)
                            .background(
                                Brush.verticalGradient(
                                    listOf(Color.Transparent, MatteryaColors.ink.copy(alpha = 0.14f)),
                                ),
                            ),
                    )
                }
            }
        }
    }
}

@Composable
private fun BoxWithConstraintsFeed(content: @Composable (widthPx: Float, maxWidth: androidx.compose.ui.unit.Dp) -> Unit) {
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxWidth()) {
        val density = androidx.compose.ui.platform.LocalDensity.current
        val widthPx = with(density) { maxWidth.toPx() }
        content(widthPx, maxWidth)
    }
}

// ── iOS helpers ported ─────────────────────────────────────────────────────

private fun isFeedReshareCard(post: CountryPost): Boolean {
    if (PlayPlatformBridge.isHubOriginShare(post)) return true
    if (post.isSparkFeedShare || SparkShareMarker.isMarked(post.body)) return true
    if (PlayPlatformBridge.isFeedOnlyShare(post) &&
        PlayPlatformBridge.isLikelyLiveUserAuthor(post.authorId)
    ) {
        return true
    }
    return false
}

private fun originChannelDisplayName(post: CountryPost): String? {
    HubOriginShareMarker.originPresentation(post)?.authorDisplayName?.trim()
        ?.takeIf { it.isNotEmpty() }?.let { return it }
    SparkShareMarker.originChannelName(post.body)?.let { return it }
    post.sharedPost?.asCountryPost?.let { embed ->
        val n = embed.authorDisplayName.trim()
        if (n.isNotEmpty() && embed.authorId != post.authorId) return n
    }
    if (PlayPlatformBridge.isArchiveCatalogMedia(post) || post.isHubSeedVideo ||
        HubVideoSeedService.isArchiveChannelAuthor(post.authorId)
    ) {
        return HubVideoSeedService.ARCHIVE_CHANNEL_DISPLAY_NAME
    }
    if (PlayPlatformBridge.isHubOriginShare(post) || PlayPlatformBridge.showsPlayLinkInFeed(post)) {
        val creator = PlayPlatformBridge.displayCreator(post).name.trim()
        if (creator.isNotEmpty() && creator != post.authorDisplayName) return creator
        return MatteryaCopy.matteryaHubs
    }
    if (PlayPlatformBridge.isSparkFeedCard(post)) return MatteryaCopy.sparks
    return null
}

private fun sparkCardPresentationPost(post: CountryPost): CountryPost {
    if (post.playableVideoUrl != null) return post
    val embed = post.sharedPost?.asCountryPost
    if (embed?.playableVideoUrl != null) return embed
    return post
}

private fun postedFromLabel(post: CountryPost, viewingIso: String?): String? {
    val viewing = viewingIso?.uppercase() ?: return null
    val postIso = post.countryCode?.uppercase().orEmpty()
    if (postIso.isEmpty() || postIso == viewing) return null
    val country = post.countryName?.trim()?.takeIf { it.isNotEmpty() } ?: postIso
    val city = post.cityName?.trim()?.takeIf { it.isNotEmpty() }
    return if (city != null) "Posted from $city, $country" else "Posted from $country"
}

/** iOS `hubChannelAttributionLine` — under journal title for Hubs long-form. */
private fun hubChannelAttributionLine(
    post: CountryPost,
    isFeedReshare: Boolean,
    sharedByLine: String?,
    showsPlayLink: Boolean,
): String? {
    // Re-shares: only under the name once — never again under the title.
    if (isFeedReshare) return null
    if (sharedByLine != null) return null
    if (!showsPlayLink) return null
    if (HubVideoSeedService.isArchiveChannelAuthor(post.authorId)) return null
    post.displayCaption?.takeIf { it.isNotEmpty() }?.let { caption ->
        return if (caption.contains("from ", ignoreCase = true)) {
            caption
        } else {
            "From $caption · ${MatteryaCopy.matteryaHubs}"
        }
    }
    if (post.hubSlug != null || post.isHubSeedVideo) {
        return "From ${HubVideoSeedService.ARCHIVE_CHANNEL_DISPLAY_NAME} · ${MatteryaCopy.matteryaHubs}"
    }
    if (HubChannelPostMarker.isMarked(post.body)) {
        return "Shared from ${MatteryaCopy.matteryaHubs}"
    }
    return null
}

/** Lightweight embedded card. */
@Composable
fun CompactPostCard(
    post: CountryPost,
    onLike: () -> Unit,
    onOpenPost: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    PostCard(
        post = post,
        onLike = onLike,
        onOpenPost = onOpenPost,
        edgeToEdge = false,
        modifier = modifier,
    )
}
