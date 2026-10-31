package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Icon
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
import com.matterya.matterya.data.anonymous.AnonymousService
import com.matterya.matterya.model.AnonymousSpace
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.theme.MatteryaReportCategories
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
    var showReport by remember { mutableStateOf(false) }
    var preparingComposer by remember { mutableStateOf(false) }
    val space = state.currentSpace?.takeIf { it.slug == slug }

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
        MasqueradePushChrome(title = space?.title ?: slug, onBack = onBack)

        when {
            state.spacePostsLoading && state.spacePosts.isEmpty() && space == null ->
                AnonymousLoadingSkeleton()
            space == null && !state.spacePostsLoading -> AnonymousEmptyState(
                title = MatteryaCopy.anonymousSpaceMissing,
                message = MatteryaCopy.anonymousSpaceMissingBody,
                actionTitle = "Back",
                onAction = onBack,
            )
            else -> LazyColumn(Modifier.fillMaxSize()) {
                item {
                    if (space != null) {
                        SpaceAboutCard(space, store)
                        Spacer(Modifier.height(12.dp))
                        SpaceActionsRow(
                            space = space,
                            store = store,
                            preparingComposer = preparingComposer,
                            onNewPost = {
                                scope.launch {
                                    preparingComposer = true
                                    if (!store.isJoined(space) && !space.isPaid) {
                                        store.joinCurrentSpace()
                                    }
                                    preparingComposer = false
                                    if (!space.isPaid) showComposer = true
                                }
                            },
                            onToggleJoin = {
                                scope.launch {
                                    if (store.isJoined(space)) store.leaveCurrentSpace()
                                    else store.joinCurrentSpace()
                                }
                            },
                            onMod = { showModPanel = true },
                            onReport = { showReport = true },
                        )
                        Spacer(Modifier.height(16.dp))
                        Text(
                            "Posts",
                            fontWeight = FontWeight.SemiBold,
                            color = MatteryaColors.ink,
                            fontSize = 14.sp,
                            modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding),
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                }
                if (state.spacePosts.isEmpty() && !state.spacePostsLoading) {
                    item {
                        AnonymousEmptyState(
                            title = MatteryaCopy.anonymousSpaceEmptyPosts,
                            message = "",
                            actionTitle = if (space?.isPaid != true) "Write a post" else null,
                            onAction = if (space?.isPaid != true) {
                                { showComposer = true }
                            } else null,
                        )
                    }
                } else {
                    itemsIndexed(state.spacePosts, key = { _, p -> p.id }) { index, post ->
                        AnonymousPostCard(
                            post = post,
                            style = AnonymousPostCardStyle.Space,
                            onOpen = { store.pushPost(post) },
                            onOpenAuthor = { store.pushProfile(post.authorUsername) },
                            onVote = { v -> scope.launch { store.vote(post, v) } },
                            onReport = { reason ->
                                scope.launch { store.report("post", post.id, reason) }
                            },
                            onBlockAuthor = {
                                scope.launch { store.block(post.authorProfileId) }
                            },
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

    if (showReport && space != null) {
        MatteryaReportDialog(
            title = "Report Space",
            onDismiss = { showReport = false },
            onReason = { label ->
                showReport = false
                scope.launch {
                    store.report("space", space.id, MatteryaReportCategories.slugForLabel(label))
                }
            },
        )
    }
}

@Composable
private fun SpaceAboutCard(space: AnonymousSpace, store: AnonymousStore) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(MatteryaDimens.pagePadding)
            .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
            .padding(14.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("About this space", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            Spacer(Modifier.weight(1f))
            if (space.isPaid) {
                Text(
                    "Paid",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .background(MatteryaColors.matteDeep, RoundedCornerShape(50))
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    color = MatteryaColors.ink,
                )
            }
        }
        space.description?.takeIf { it.isNotBlank() }?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, color = MatteryaColors.inkSecondary, fontSize = 15.sp)
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("${space.memberCount ?: 0} members", color = MatteryaColors.inkMuted, fontSize = 12.sp)
            Text("${space.postCount ?: 0} posts", color = MatteryaColors.inkMuted, fontSize = 12.sp)
            space.ownerUsername?.let { owner ->
                Text(
                    "Owner @$owner",
                    color = MatteryaColors.inkMuted,
                    fontSize = 12.sp,
                    modifier = Modifier.clickable { store.pushProfile(owner) },
                )
            }
        }
        space.rules?.takeIf { it.isNotEmpty() }?.let { rules ->
            Spacer(Modifier.height(12.dp))
            Text("Rules", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink, fontSize = 14.sp)
            rules.forEachIndexed { idx, rule ->
                Text(
                    "${idx + 1}. $rule",
                    color = MatteryaColors.inkSecondary,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun SpaceActionsRow(
    space: AnonymousSpace,
    store: AnonymousStore,
    preparingComposer: Boolean,
    onNewPost: () -> Unit,
    onToggleJoin: () -> Unit,
    onMod: () -> Unit,
    onReport: () -> Unit,
) {
    val joined = store.isJoined(space)
    val busy = store.isMembershipBusy(space.id)
    Column(Modifier.padding(horizontal = MatteryaDimens.pagePadding)) {
        if (space.isPaid) {
            Text(MatteryaCopy.anonymousPaidJoinDisabled, color = MatteryaColors.inkMuted, fontSize = 12.sp)
            Spacer(Modifier.height(8.dp))
            SpaceChip("Join soon", quiet = true, enabled = false)
        } else {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SpaceChip(
                    if (preparingComposer) "Joining…" else "New post",
                    primary = true,
                    icon = { Icon(Icons.Default.Edit, null, Modifier.height(14.dp), tint = MatteryaColors.paper) },
                    onClick = onNewPost,
                    enabled = !preparingComposer,
                )
                SpaceChip(
                    when {
                        busy && joined -> "Leaving…"
                        busy -> "Joining…"
                        joined -> "Leave"
                        else -> "Join"
                    },
                    outline = !joined,
                    quiet = joined,
                    icon = if (!joined) {
                        { Icon(Icons.Default.PersonAdd, null, Modifier.height(14.dp), tint = MatteryaColors.ink) }
                    } else null,
                    onClick = onToggleJoin,
                    enabled = !busy,
                )
                Spacer(Modifier.weight(1f))
                if (space.isOwner == true || space.isModerator == true) {
                    SpaceChip(
                        "Mod",
                        quiet = true,
                        icon = { Icon(Icons.Default.Shield, null, Modifier.height(14.dp), tint = MatteryaColors.inkMuted) },
                        onClick = onMod,
                    )
                }
                SpaceChip("Report", subtle = true, onClick = onReport)
            }
        }
    }
}

@Composable
private fun SpaceChip(
    title: String,
    primary: Boolean = false,
    outline: Boolean = false,
    quiet: Boolean = false,
    subtle: Boolean = false,
    enabled: Boolean = true,
    icon: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val bg = when {
        primary -> MatteryaColors.ink
        quiet || subtle -> MatteryaColors.canvasMuted
        outline -> MatteryaColors.surface
        else -> MatteryaColors.canvasMuted
    }
    val fg = when {
        primary -> MatteryaColors.paper
        subtle -> MatteryaColors.inkMuted
        else -> MatteryaColors.ink
    }
    Row(
        Modifier
            .then(if (onClick != null && enabled) Modifier.clickable(onClick = onClick) else Modifier)
            .background(bg, RoundedCornerShape(50))
            .then(
                if (outline) Modifier.border(0.5.dp, MatteryaColors.border, RoundedCornerShape(50))
                else Modifier,
            )
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        icon?.invoke()
        Text(title, color = fg, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}
