package com.matterya.matterya.ui.messages

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.matterya.matterya.data.media.MediaPlaybackCoordinator
import com.matterya.matterya.model.ContentSanitizer
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.Message
import com.matterya.matterya.model.SparkShareMarker
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.ui.components.VideoThumbnailView
import com.matterya.matterya.viewmodel.AppState

/**
 * iOS `ChatShareRouting` — open shared posts/sparks/hubs into the right player surface.
 */
object ChatShareRouting {
    fun isSpark(share: Message.ShareInfo): Boolean {
        if (share.kind == Message.ShareInfo.Kind.REEL) return true
        val type = (share.mediaType ?: "").lowercase()
        if (type == "reel" || type == "spark") return true
        if (share.asCountryPost.isReel) return true
        if (SparkShareMarker.isMarked(share.bodyText)) return true
        val body = (share.bodyText ?: "").lowercase()
        if (body.contains("__spark__|") || body.contains("__reel__|")) return true
        return false
    }

    fun hubPost(from: Message.ShareInfo): CountryPost {
        val base = from.asCountryPost
        return if (base.mediaType.isNullOrBlank() && from.isVideo) {
            base.copy(mediaType = "video")
        } else {
            base
        }
    }

    /** Card / arrow → Sparks, Hubs watch, or post detail. Never autoplay side-effects beyond open. */
    fun open(share: Message.ShareInfo, appState: AppState) {
        MediaPlaybackCoordinator.shared.pauseAll()

        if (isSpark(share)) {
            var post = share.asCountryPost
            if (!post.isReel) {
                val body = post.body
                post = post.copy(
                    body = if (body.startsWith("__spark__|") || body.startsWith("__reel__|")) {
                        body
                    } else {
                        "__spark__|${if (body.isEmpty()) "Spark" else body}"
                    },
                    mediaType = "reel",
                    mediaUrl = post.mediaUrl ?: share.mediaUrl,
                    thumbUrl = post.thumbUrl ?: share.posterUrl,
                )
            }
            appState.openGlobalSparksViewer(post)
            return
        }

        if (share.isHubContent || share.kind == Message.ShareInfo.Kind.HUB ||
            (share.isVideo && share.kind != Message.ShareInfo.Kind.POST)
        ) {
            val instant = hubPost(share)
            appState.openLivingVideo(postId = instant.id, tab = null, post = instant)
            return
        }

        // Regular feed post share
        val post = share.asCountryPost
        if (post.hasVideo) {
            appState.openPost(post)
        } else {
            appState.openPostInFeed(share.postId)
        }
    }
}

/**
 * iOS `ChatRichMedia` / `ChatShareCard` — quiet link card in chat.
 */
@Composable
fun ChatShareCard(
    share: Message.ShareInfo,
    isMine: Boolean = false,
    onOpen: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val isSpark = ChatShareRouting.isSpark(share)
    val cardWidth = 228.dp
    val mediaHeight = if (isSpark) cardWidth * 1.15f else cardWidth * 9f / 16f

    val headline = share.title?.trim()?.takeIf { it.isNotEmpty() }?.let { ContentSanitizer.clean(it) }
        ?: share.bodyText?.trim()?.takeIf { it.isNotEmpty() }?.let { raw ->
            val cleaned = raw
                .replace("__spark__|", "")
                .replace("__reel__|", "")
                .replace("__spark_share__|", "")
                .replace("__hub_origin__|", "")
                .trim()
            if (cleaned.isEmpty()) null else ContentSanitizer.clean(cleaned.take(100))
        }

    Column(
        modifier
            .fillMaxWidth()
            .clickable(enabled = onOpen != null) { onOpen?.invoke() },
        horizontalAlignment = if (isMine) Alignment.End else Alignment.Start,
    ) {
        if (share.note.isNotEmpty()) {
            Text(
                share.note,
                color = if (isMine) MatteryaColors.paper else MatteryaColors.ink,
                fontSize = 14.sp,
                modifier = Modifier
                    .background(
                        if (isMine) MatteryaColors.accentBright else MatteryaColors.surface,
                        RoundedCornerShape(14.dp),
                    )
                    .padding(horizontal = 12.dp, vertical = 8.dp)
                    .width(cardWidth + 12.dp),
            )
            Spacer(Modifier.height(6.dp))
        }

        Column(
            Modifier
                .width(cardWidth)
                .background(MatteryaColors.surface, RoundedCornerShape(12.dp))
                .border(0.5.dp, MatteryaColors.border.copy(alpha = 0.45f), RoundedCornerShape(12.dp))
                .clip(RoundedCornerShape(12.dp)),
        ) {
            val asPost = share.asCountryPost
            VideoThumbnailView(
                post = asPost,
                maxLogicalPx = 420,
                showsPlayIcon = isSpark || share.isVideo,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(mediaHeight),
                contentScale = ContentScale.Crop,
            )

            Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                headline?.let {
                    Text(
                        it,
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.ink,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        fontSize = 13.sp,
                    )
                }
                share.authorName?.takeIf { it.isNotBlank() }?.let {
                    Text(it, fontSize = 12.sp, color = MatteryaColors.inkMuted, maxLines = 1)
                }
            }
        }
    }
}

/** Image bubble in chat. */
@Composable
fun ChatImageBubble(
    url: String,
    isMine: Boolean,
    onClick: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    AsyncImage(
        model = url,
        contentDescription = "Photo",
        contentScale = ContentScale.Crop,
        modifier = modifier
            .width(220.dp)
            .height(220.dp)
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick),
    )
}

/** Call log row in chat. */
@Composable
fun ChatCallLogRow(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text,
        fontSize = 12.sp,
        color = MatteryaColors.inkMuted,
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
    )
}
