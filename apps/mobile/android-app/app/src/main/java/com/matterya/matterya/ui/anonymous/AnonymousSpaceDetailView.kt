package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import com.matterya.matterya.data.anonymous.AnonymousService
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

@Composable
fun AnonymousSpaceDetailView(
    store: AnonymousStore,
    slug: String,
    onBack: () -> Unit,
) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    var showComposer by remember { mutableStateOf(false) }
    var showModPanel by remember { mutableStateOf(false) }
    val space = state.currentSpace

    LaunchedEffect(slug) { store.openSpace(slug) }

    if (showModPanel) {
        AnonymousModPanelView(
            spaceTitle = space?.title ?: slug,
            onDismiss = { showModPanel = false },
        )
        return
    }

    if (showComposer && space != null) {
        AnonymousComposerView(
            store = store,
            spaceId = space.id,
            spaceTitle = space.title,
            onBack = { showComposer = false },
            onPublished = { showComposer = false },
        )
        return
    }

    Column(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
        Row(
            Modifier.fillMaxWidth().background(MatteryaColors.surface).padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = MatteryaColors.ink)
            }
            Column(Modifier.weight(1f)) {
                Text(space?.title ?: slug, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink, maxLines = 1)
                Text(
                    "${space?.memberCount ?: 0} members · ${space?.postCount ?: 0} posts",
                    color = MatteryaColors.inkMuted,
                    fontSize = 12.sp,
                )
            }
            if (space != null) {
                val joined = store.isJoined(space)
                TextButton(
                    onClick = {
                        scope.launch {
                            if (joined) store.leaveCurrentSpace() else store.joinCurrentSpace()
                        }
                    },
                    enabled = !store.isMembershipBusy(space.id) && !space.isPaid,
                ) {
                    Text(
                        when {
                            space.isPaid -> "Paid"
                            joined -> "Leave"
                            else -> "Join"
                        },
                        color = MatteryaColors.accent,
                    )
                }
                if (space.isOwner == true || space.isModerator == true) {
                    IconButton(onClick = { showModPanel = true }) {
                        Icon(Icons.Default.Shield, contentDescription = "Mod tools", tint = MatteryaColors.ink)
                    }
                }
                IconButton(onClick = { showComposer = true }) {
                    Icon(Icons.Default.Add, contentDescription = "Post", tint = MatteryaColors.ink)
                }
            }
        }

        when {
            state.spacePostsLoading && state.spacePosts.isEmpty() && space == null -> AnonymousLoadingSkeleton()
            space == null && !state.spacePostsLoading -> AnonymousEmptyState(
                title = MatteryaCopy.anonymousSpaceMissing,
                message = MatteryaCopy.anonymousSpaceMissingBody,
            )
            state.spacePosts.isEmpty() && !state.spacePostsLoading -> {
                Column(Modifier.padding(MatteryaDimens.pagePadding)) {
                    space?.description?.takeIf { it.isNotBlank() }?.let {
                        Text(it, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
                        Spacer(Modifier.height(12.dp))
                    }
                    AnonymousEmptyState(
                        title = MatteryaCopy.anonymousSpaceEmptyPosts,
                        message = "",
                        actionTitle = "Write a post",
                        onAction = { showComposer = true },
                    )
                }
            }
            else -> LazyColumn(Modifier.fillMaxSize()) {
                item {
                    space?.description?.takeIf { it.isNotBlank() }?.let {
                        Text(
                            it,
                            color = MatteryaColors.inkSecondary,
                            fontSize = 14.sp,
                            modifier = Modifier.padding(MatteryaDimens.pagePadding),
                        )
                    }
                }
                itemsIndexed(state.spacePosts, key = { _, p -> p.id }) { index, post ->
                    AnonymousPostCard(
                        post = post,
                        style = AnonymousPostCardStyle.Space,
                        onOpen = { store.pushPost(post) },
                        onOpenAuthor = { store.pushProfile(post.authorUsername) },
                        onVote = { v -> scope.launch { store.vote(post, v) } },
                    )
                    LaunchedEffect(post.id, index) {
                        val remaining = state.spacePosts.size - index
                        if (remaining <= AnonymousService.feedPrefetchRemaining) {
                            store.loadMoreSpacePosts()
                        }
                    }
                }
            }
        }
    }
}
