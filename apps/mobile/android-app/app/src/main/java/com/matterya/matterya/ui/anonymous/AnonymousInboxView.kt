package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.messages.ConversationInboxStore
import com.matterya.matterya.data.messages.MessagesService
import com.matterya.matterya.model.Conversation
import com.matterya.matterya.model.PostAuthor
import com.matterya.matterya.model.RelativeTime
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

/**
 * iOS `AnonymousMessagesInboxView` — Masquerade-surface DM threads only
 * (official Matterya peer). Notifications stay on the header bell.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnonymousInboxView(store: AnonymousStore) {
    val scope = rememberCoroutineScope()
    val messagesService = remember { MessagesService.shared }
    var conversations by remember { mutableStateOf<List<Conversation>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val meId = AuthService.instance.currentUser?.id.orEmpty()

    suspend fun reload() {
        loading = conversations.isEmpty()
        try {
            val page = messagesService.listConversations(limit = 40, inbox = "masquerade")
            conversations = page.filter { conversation ->
                if (ConversationInboxStore.isHidden(conversation.id)) return@filter false
                if (meId.isEmpty()) return@filter false
                val other = conversation.otherMember(meId) ?: return@filter false
                isMasqueradeOfficialPeer(other)
            }
            error = null
            store.refreshMasqueradeMessageUnread()
        } catch (e: Exception) {
            if (conversations.isEmpty()) {
                error = e.message ?: "Inbox unavailable"
            }
        } finally {
            loading = false
        }
    }

    LaunchedEffect(Unit) { reload() }

    Column(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
        Text(
            "Messages",
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.ink,
            modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
        )
        PullToRefreshBox(
            isRefreshing = loading,
            onRefresh = { scope.launch { reload() } },
            modifier = Modifier.fillMaxSize(),
        ) {
            when {
                loading && conversations.isEmpty() -> AnonymousLoadingSkeleton()
                error != null && conversations.isEmpty() -> AnonymousEmptyState(
                    title = "Inbox unavailable",
                    message = error.orEmpty(),
                )
                conversations.isEmpty() -> AnonymousEmptyState(
                    title = MatteryaCopy.anonymousMessagesInboxTitle,
                    message = MatteryaCopy.anonymousMessagesInboxBody,
                )
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    items(conversations, key = { it.id }) { conversation ->
                        MasqueradeConversationRow(
                            conversation = conversation,
                            currentUserId = meId,
                            onOpen = {
                                messagesService.storeConversation(conversation)
                                store.pushConversation(conversation.id)
                            },
                        )
                    }
                    item {
                        Text(
                            MatteryaCopy.anonymousInboxPrivacyNote,
                            color = MatteryaColors.inkMuted,
                            fontSize = 12.sp,
                            modifier = Modifier.padding(MatteryaDimens.pagePadding),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MasqueradeConversationRow(
    conversation: Conversation,
    currentUserId: String,
    onOpen: () -> Unit,
) {
    val other = conversation.otherMember(currentUserId)
    val title = other?.displayName ?: other?.username ?: "Matterya"
    val preview = conversation.lastMessage?.previewText ?: "No messages yet"
    val unread = currentUserId.isNotEmpty() && conversation.hasUnread(currentUserId)
    val shape = RoundedCornerShape(MatteryaDimens.cardRadius)

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 5.dp)
            .clip(shape)
            .background(if (unread) MatteryaColors.danger.copy(alpha = 0.06f) else MatteryaColors.surface)
            .border(
                width = 0.5.dp,
                color = if (unread) MatteryaColors.danger.copy(alpha = 0.28f) else MatteryaColors.border,
                shape = shape,
            )
            .clickable(onClick = onOpen)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box {
            AvatarView(
                url = other?.avatarUrl,
                seed = other?.username ?: other?.userId ?: conversation.id,
                size = 48.dp,
            )
            if (unread) {
                Spacer(
                    Modifier
                        .align(Alignment.TopEnd)
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(MatteryaColors.danger),
                )
            }
        }
        Spacer(Modifier.size(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                title,
                fontWeight = if (unread) FontWeight.Bold else FontWeight.SemiBold,
                color = MatteryaColors.ink,
                fontSize = 14.sp,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                preview,
                fontWeight = if (unread) FontWeight.SemiBold else FontWeight.Normal,
                color = if (unread) MatteryaColors.inkSecondary else MatteryaColors.inkMuted,
                fontSize = 12.sp,
                maxLines = 2,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            val stamp = conversation.lastMessageAt ?: conversation.lastMessage?.createdAt
            if (!stamp.isNullOrBlank()) {
                Text(
                    RelativeTime.format(stamp),
                    color = MatteryaColors.inkMuted,
                    fontSize = 11.sp,
                )
            }
            if (unread) {
                Spacer(Modifier.height(6.dp))
                Spacer(
                    Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(MatteryaColors.danger),
                )
            }
        }
    }
}

private fun isMasqueradeOfficialPeer(other: PostAuthor): Boolean {
    if (other.showsVerifiedBadge) return true
    return other.username?.trim()?.equals("matterya", ignoreCase = true) == true
}
