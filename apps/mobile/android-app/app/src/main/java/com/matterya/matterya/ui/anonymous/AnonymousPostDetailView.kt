package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.AnonymousComment
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

@Composable
fun AnonymousPostDetailView(
    store: AnonymousStore,
    postId: String,
    onBack: () -> Unit,
) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    var draft by remember { mutableStateOf("") }
    var post by remember(postId) { mutableStateOf(store.postForId(postId)) }
    val comments = state.commentsByPostId[postId].orEmpty()
    val loadingComments = state.commentsLoading[postId] == true

    LaunchedEffect(postId) {
        if (post == null) {
            post = store.fetchPost(postId)
        }
        store.loadComments(postId, force = true)
        post = store.postForId(postId) ?: post
    }

    Column(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
        Row(
            Modifier.fillMaxWidth().background(MatteryaColors.surface).padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = MatteryaColors.ink)
            }
            Text("Thread", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
        }

        LazyColumn(Modifier.weight(1f)) {
            item {
                val current = post
                if (current != null) {
                    AnonymousPostCard(
                        post = current,
                        style = AnonymousPostCardStyle.Thread,
                        onOpen = {},
                        onOpenSpace = { current.spaceSlug?.let { store.pushSpace(it) } },
                        onOpenAuthor = { store.pushProfile(current.authorUsername) },
                        onVote = { v -> scope.launch { store.vote(current, v) } },
                    )
                } else {
                    AnonymousLoadingSkeleton()
                }
            }
            item {
                Text(
                    "Comments",
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.inkMuted,
                    modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
                )
            }
            if (loadingComments && comments.isEmpty()) {
                item { Text("Loading…", modifier = Modifier.padding(MatteryaDimens.pagePadding), color = MatteryaColors.inkMuted) }
            } else if (comments.isEmpty()) {
                item {
                    Text(
                        MatteryaCopy.anonymousNoComments,
                        modifier = Modifier.padding(MatteryaDimens.pagePadding),
                        color = MatteryaColors.inkMuted,
                    )
                }
            } else {
                items(flattenComments(comments), key = { it.id }) { comment ->
                    CommentRow(comment)
                }
            }
        }

        Row(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface)
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Add a comment") },
                singleLine = true,
            )
            IconButton(
                onClick = {
                    scope.launch {
                        val created = store.createComment(postId, draft)
                        if (created != null) draft = ""
                    }
                },
                enabled = draft.isNotBlank(),
            ) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send", tint = MatteryaColors.accent)
            }
        }
    }
}

@Composable
private fun CommentRow(comment: AnonymousComment) {
    val depth = (comment.depth ?: 0).coerceIn(0, 6)
    Column(
        Modifier
            .fillMaxWidth()
            .padding(start = (MatteryaDimens.pagePadding.value + depth * 12).dp, end = MatteryaDimens.pagePadding, top = 8.dp, bottom = 8.dp),
    ) {
        Text("@${comment.authorUsername}", color = MatteryaColors.inkMuted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(2.dp))
        Text(comment.displayBody, color = MatteryaColors.ink, fontSize = 14.sp)
        Text("${comment.score ?: 0} points", color = MatteryaColors.inkMuted, fontSize = 11.sp)
    }
}

private fun flattenComments(comments: List<AnonymousComment>, depth: Int = 0): List<AnonymousComment> {
    val out = mutableListOf<AnonymousComment>()
    for (c in comments) {
        out.add(c.copy(depth = c.depth ?: depth))
        c.replies?.let { out.addAll(flattenComments(it, depth + 1)) }
    }
    return out
}
