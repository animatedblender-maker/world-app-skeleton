package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.hubs.HubEngagementStore
import com.matterya.matterya.data.posts.PostsService
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.PostAuthor
import com.matterya.matterya.model.PostComment
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.RelativeTime
import com.matterya.matterya.theme.ContentSanitizer
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens
import kotlinx.coroutines.launch

/** Thread layout constants — iOS `CommentThreadLayout`. */
object CommentThreadLayout {
    val indentPerLevel = 44.dp
    const val maxDepth = 1
}

data class CommentThreadItem(val comment: PostComment, val depth: Int)

object CommentThreadBuilder {
    fun ordered(comments: List<PostComment>): List<CommentThreadItem> {
        fun norm(id: String?) = id?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        fun isRoot(c: PostComment) = norm(c.parentId) == null

        val byId = comments.associateBy { norm(it.id) ?: it.id }
        fun threadRoot(c: PostComment): String {
            var current = c
            val visited = mutableSetOf<String>()
            while (true) {
                val pid = norm(current.parentId) ?: break
                if (!visited.add(pid)) break
                current = byId[pid] ?: break
            }
            return current.id
        }

        val roots = comments.filter(::isRoot).sortedBy { it.createdAt }
        val replies = comments.filter { !isRoot(it) }
        val items = mutableListOf<CommentThreadItem>()
        val included = mutableSetOf<String>()

        for (root in roots) {
            val rootKey = norm(root.id) ?: root.id
            items += CommentThreadItem(root, 0)
            included += rootKey
            replies
                .filter { (norm(threadRoot(it)) ?: threadRoot(it)) == rootKey }
                .sortedBy { it.createdAt }
                .forEach { reply ->
                    items += CommentThreadItem(reply, 1)
                    included += norm(reply.id) ?: reply.id
                }
        }
        comments.filter { (norm(it.id) ?: it.id) !in included }
            .sortedBy { it.createdAt }
            .forEach { orphan ->
                items += CommentThreadItem(orphan, if (isRoot(orphan)) 0 else 1)
            }
        return items
    }

    fun threadRootId(comment: PostComment, comments: List<PostComment>): String {
        fun norm(id: String?) = id?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        val byId = comments.associateBy { norm(it.id) ?: it.id }
        var current = comment
        val visited = mutableSetOf<String>()
        while (true) {
            val pid = norm(current.parentId) ?: break
            if (!visited.add(pid)) break
            current = byId[pid] ?: break
        }
        return current.id
    }
}

/**
 * Inline post comments — full parity with iOS `PostCommentsView` / `FacebookCommentRow`.
 * Loads via [PostsService.listComments] (origin merge for shares).
 */
@Composable
fun PostCommentsView(
    post: CountryPost,
    modifier: Modifier = Modifier,
    showsComposer: Boolean = true,
    maxVisibleComments: Int? = 3,
    currentProfile: Profile? = null,
    onCommentCountDelta: (Int) -> Unit = {},
    onError: (String?) -> Unit = {},
    onOpenProfile: (userId: String, username: String?) -> Unit = { _, _ -> },
    onViewAllComments: (() -> Unit)? = null,
) {
    val posts = remember { PostsService() }
    val scope = rememberCoroutineScope()
    var comments by remember(post.id) { mutableStateOf<List<PostComment>>(emptyList()) }
    var loading by remember(post.id) { mutableStateOf(true) }
    var draft by remember { mutableStateOf("") }
    var submitting by remember { mutableStateOf(false) }
    var replyTarget by remember { mutableStateOf<ReplyTarget?>(null) }
    var likingIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var visibleLimit by remember(post.id) {
        mutableIntStateOf(maxVisibleComments ?: Int.MAX_VALUE)
    }

    LaunchedEffect(post.id) {
        loading = comments.isEmpty()
        comments = try {
            posts.listComments(
                postId = post.id,
                limit = 2000,
                body = post.body,
                sharedPostId = post.sharedPostId,
                originPostId = post.originPostId,
            )
        } catch (_: Exception) {
            HubEngagementStore.shared.listComments(post.id, 2000)
        }
        loading = false
    }

    val threaded = remember(comments) { CommentThreadBuilder.ordered(comments) }
    val visibleCap = if (maxVisibleComments != null) {
        minOf(visibleLimit, maxVisibleComments.coerceAtLeast(visibleLimit))
        // When parent expands via "load more", visibleLimit grows past initial max
        visibleLimit
    } else {
        threaded.size
    }
    val visible = threaded.take(visibleCap)

    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = MatteryaDimens.feedTextInset, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        when {
            loading && threaded.isEmpty() -> {
                CircularProgressIndicator(
                    Modifier
                        .size(20.dp)
                        .align(Alignment.CenterHorizontally)
                        .padding(vertical = 8.dp),
                    color = MatteryaColors.accent,
                    strokeWidth = 2.dp,
                )
            }
            threaded.isEmpty() -> {
                Text(
                    "No comments yet. Be the first to comment.",
                    color = MatteryaColors.inkMuted,
                    fontSize = 14.sp, // subheadline
                )
            }
            else -> {
                visible.forEach { item ->
                    FacebookCommentRow(
                        comment = item.comment,
                        depth = item.depth,
                        isLiking = likingIds.contains(item.comment.id),
                        onReply = {
                            replyTarget = ReplyTarget(
                                threadRootId = CommentThreadBuilder.threadRootId(item.comment, comments),
                                authorName = item.comment.author?.username
                                    ?: item.comment.authorDisplayName,
                            )
                        },
                        onToggleLike = {
                            if (likingIds.contains(item.comment.id)) return@FacebookCommentRow
                            scope.launch {
                                likingIds = likingIds + item.comment.id
                                val c = item.comment
                                val liked = !c.likedByMe
                                // Optimistic
                                comments = comments.map {
                                    if (it.id != c.id) it
                                    else it.copy(
                                        likedByMe = liked,
                                        likeCount = if (liked) it.likeCount + 1 else maxOf(0, it.likeCount - 1),
                                    )
                                }
                                runCatching {
                                    if (c.likedByMe) posts.unlikeComment(c.id)
                                    else posts.likeComment(c.id)
                                }.onSuccess { updated ->
                                    comments = comments.map { if (it.id == updated.id) updated else it }
                                }
                                likingIds = likingIds - item.comment.id
                            }
                        },
                        onOpenProfile = {
                            val uid = item.comment.authorId.trim()
                            val un = item.comment.author?.username
                            if (uid.isNotEmpty() || !un.isNullOrEmpty()) {
                                onOpenProfile(uid, un)
                            }
                        },
                    )
                }
                if (maxVisibleComments != null && threaded.size > visibleLimit) {
                    val remaining = maxOf(0, (threaded.size) - visibleLimit)
                    Text(
                        if (remaining > 0) "Load more comments ($remaining more)"
                        else "Load more comments",
                        color = MatteryaColors.inkMuted,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .padding(top = 2.dp)
                            .clickable {
                                if (onViewAllComments != null) {
                                    onViewAllComments()
                                } else {
                                    visibleLimit = minOf(visibleLimit + 25, threaded.size)
                                }
                            },
                    )
                }
            }
        }

        if (showsComposer) {
            CommentComposer(
                draft = draft,
                onDraftChange = { draft = it },
                submitting = submitting,
                replyTarget = replyTarget,
                onCancelReply = { replyTarget = null },
                currentProfile = currentProfile,
                onSubmit = {
                    val body = draft.trim()
                    if (body.isEmpty()) return@CommentComposer
                    scope.launch {
                        submitting = true
                        val parentId = replyTarget?.threadRootId
                        try {
                            val created = posts.addComment(post.id, body, parentId)
                            var refreshed = runCatching {
                                posts.listComments(
                                    postId = post.id,
                                    limit = 2000,
                                    body = post.body,
                                    sharedPostId = post.sharedPostId,
                                    originPostId = post.originPostId,
                                )
                            }.getOrDefault(comments)
                            if (refreshed.none { it.id == created.id }) {
                                refreshed = refreshed + created
                            }
                            if (!parentId.isNullOrEmpty()) {
                                refreshed = refreshed.map { c ->
                                    if (c.id == created.id && c.parentId == null) {
                                        c.withParentId(parentId)
                                    } else {
                                        c
                                    }
                                }
                            }
                            comments = refreshed
                            draft = ""
                            replyTarget = null
                            onCommentCountDelta(1)
                            onError(null)
                        } catch (_: Exception) {
                            // Offline / GraphQL failure — keep comment on-device
                            val author = currentProfile?.let {
                                PostAuthor(
                                    userId = it.userId,
                                    displayName = it.displayName ?: it.username ?: "You",
                                    username = it.username,
                                    avatarUrl = it.avatarUrl,
                                    countryName = it.countryName,
                                    countryCode = it.countryCode,
                                )
                            }
                            val created = HubEngagementStore.shared.addComment(
                                postId = post.id,
                                body = body,
                                parentId = parentId,
                                author = author,
                            )
                            comments = comments + created
                            draft = ""
                            replyTarget = null
                            onCommentCountDelta(1)
                        }
                        submitting = false
                    }
                },
            )
        }
    }
}

private data class ReplyTarget(val threadRootId: String, val authorName: String)

/** iOS `FacebookCommentRow` — flat thread, Like / Reply / time / count. */
@Composable
fun FacebookCommentRow(
    comment: PostComment,
    depth: Int,
    isLiking: Boolean,
    onReply: () -> Unit,
    onToggleLike: () -> Unit,
    onOpenProfile: () -> Unit = {},
) {
    val isReply = depth > 0
    val avatarSize = if (isReply) 26.dp else 32.dp
    val indent = if (depth > 0) CommentThreadLayout.indentPerLevel else 0.dp
    val body = ContentSanitizer.clean(comment.body)
    val authorName = ContentSanitizer.displayName(
        comment.author?.displayName,
        comment.author?.username,
        comment.authorDisplayName,
    )

    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 2.dp, bottom = 2.dp),
        verticalAlignment = Alignment.Top,
    ) {
        if (indent > 0.dp) {
            Box(
                Modifier
                    .width(indent)
                    .padding(top = 4.dp, end = 6.dp),
                contentAlignment = Alignment.TopEnd,
            ) {
                if (isReply) {
                    Box(
                        Modifier
                            .width(2.dp)
                            .height(28.dp)
                            .background(MatteryaColors.accent.copy(alpha = 0.45f), RoundedCornerShape(1.dp)),
                    )
                }
            }
        }
        Row(
            Modifier.weight(1f),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(Modifier.clickable(onClick = onOpenProfile)) {
                AvatarView(
                    url = comment.author?.avatarUrl,
                    seed = comment.authorId.ifEmpty { authorName },
                    size = avatarSize,
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    authorName,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = if (isReply) 12.sp else 14.sp,
                    color = MatteryaColors.ink,
                    modifier = Modifier.clickable(onClick = onOpenProfile),
                )
                if (!body.isNullOrEmpty()) {
                    Text(
                        body,
                        fontSize = 14.sp, // subheadline
                        color = MatteryaColors.ink,
                    )
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        if (comment.likedByMe) "Liked" else "Like",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (comment.likedByMe) MatteryaColors.ink else MatteryaColors.inkMuted,
                        modifier = Modifier.clickable(enabled = !isLiking, onClick = onToggleLike),
                    )
                    Text(
                        "Reply",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.inkMuted,
                        modifier = Modifier.clickable(onClick = onReply),
                    )
                    Text(
                        RelativeTime.format(comment.createdAt),
                        fontSize = 12.sp,
                        color = MatteryaColors.inkMuted,
                    )
                    if (comment.likeCount > 0) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Icon(
                                Icons.Default.ThumbUp,
                                contentDescription = null,
                                tint = MatteryaColors.ink,
                                modifier = Modifier.size(10.dp),
                            )
                            Text(
                                "${comment.likeCount}",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = MatteryaColors.inkSecondary,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CommentComposer(
    draft: String,
    onDraftChange: (String) -> Unit,
    submitting: Boolean,
    replyTarget: ReplyTarget?,
    onCancelReply: () -> Unit,
    currentProfile: Profile?,
    onSubmit: () -> Unit,
) {
    val composerIndent = if (replyTarget != null) CommentThreadLayout.indentPerLevel else 0.dp
    Column(
        Modifier
            .fillMaxWidth()
            .padding(start = composerIndent, top = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (replyTarget != null) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Replying to", fontSize = 12.sp, color = MatteryaColors.inkMuted)
                Text(
                    "@${replyTarget.authorName}",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.accent,
                )
                Text(
                    "Cancel",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.inkMuted,
                    modifier = Modifier.clickable(onClick = onCancelReply),
                )
            }
        }
        Row(
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            AvatarView(
                url = currentProfile?.avatarUrl,
                seed = currentProfile?.userId ?: "me",
                size = if (replyTarget == null) 32.dp else 26.dp,
            )
            Row(
                Modifier
                    .weight(1f)
                    .background(MatteryaColors.surface, RoundedCornerShape(20.dp))
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                BasicTextField(
                    value = draft,
                    onValueChange = onDraftChange,
                    modifier = Modifier.weight(1f),
                    textStyle = TextStyle(fontSize = 14.sp, color = MatteryaColors.ink),
                    cursorBrush = SolidColor(MatteryaColors.accent),
                    maxLines = 4,
                    decorationBox = { inner ->
                        if (draft.isEmpty()) {
                            Text(
                                if (replyTarget == null) "Write a comment…" else "Write a reply…",
                                fontSize = 14.sp,
                                color = MatteryaColors.inkMuted,
                            )
                        }
                        inner()
                    },
                )
                if (draft.trim().isNotEmpty()) {
                    IconButton(
                        onClick = onSubmit,
                        enabled = !submitting,
                        modifier = Modifier.size(32.dp),
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.Send,
                            contentDescription = "Post",
                            tint = MatteryaColors.accent,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
        }
    }
}

/**
 * Full-screen / sheet comments — iOS `PostCommentsPageView` / `ReelsCommentsSheet` /
 * `SparksCommentsSheet` chrome.
 */
@Composable
fun PostCommentsPageView(
    post: CountryPost,
    currentProfile: Profile? = null,
    onError: (String?) -> Unit = {},
    onOpenProfile: (userId: String, username: String?) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .fillMaxWidth()
            .background(MatteryaColors.canvas)
            .padding(MatteryaDimens.pagePadding)
            .padding(bottom = 24.dp),
    ) {
        PostCommentsView(
            post = post,
            showsComposer = true,
            maxVisibleComments = null,
            currentProfile = currentProfile,
            onError = onError,
            onOpenProfile = onOpenProfile,
        )
    }
}
