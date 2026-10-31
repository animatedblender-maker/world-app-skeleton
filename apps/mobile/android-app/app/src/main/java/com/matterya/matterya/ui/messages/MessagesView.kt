package com.matterya.matterya.ui.messages

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.Message
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.UnreadBadge
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

data class ConversationItem(
    val id: String,
    val title: String,
    val subtitle: String = "",
    val avatarUrl: String? = null,
    val peerUserId: String = "",
    val unreadCount: Int = 0,
    val relativeTime: String = "",
)

/**
 * Messages inbox — 1:1 with iOS `MessagesView`.
 * Top bar (menu spacer + title + compose), list cells match iOS `ConversationRow`.
 */
@Composable
fun MessagesView(
    conversations: List<ConversationItem> = emptyList(),
    isLoading: Boolean = false,
    errorMessage: String? = null,
    onMenu: () -> Unit = {},
    onPeople: () -> Unit = {},
    onOpenConversation: (ConversationItem) -> Unit = {},
    onArchive: (ConversationItem) -> Unit = {},
    onDelete: (ConversationItem) -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        // iOS messagesTopBar — height 44, surface bg
        Row(
            Modifier
                .fillMaxWidth()
                .height(44.dp)
                .background(MatteryaColors.surface)
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Spacer(Modifier.width(44.dp)) // MenuToolbarButton reserved width
            Spacer(Modifier.weight(1f))
            Text(
                "Messages",
                fontWeight = FontWeight.SemiBold,
                fontSize = 17.sp,
                color = MatteryaColors.ink,
            )
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onPeople, modifier = Modifier.size(44.dp)) {
                Icon(Icons.Default.Edit, contentDescription = "New chat", tint = MatteryaColors.ink)
            }
        }
        when {
            isLoading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(color = MatteryaColors.accentBright)
                        Spacer(Modifier.height(12.dp))
                        Text("Loading conversations…", color = MatteryaColors.inkMuted, fontSize = 14.sp)
                    }
                }
            }
            errorMessage != null -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(errorMessage, color = MatteryaColors.danger, fontSize = 14.sp)
                }
            }
            conversations.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("No conversations", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "Start chatting from a profile.",
                            color = MatteryaColors.inkMuted,
                            fontSize = 14.sp,
                        )
                    }
                }
            }
            else -> {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(conversations, key = { it.id }) { conv ->
                        // iOS swipeActions: Archive + Delete (trailing).
                        SwipeableConversationRow(
                            conversation = conv,
                            onOpen = { onOpenConversation(conv) },
                            onArchive = { onArchive(conv) },
                            onDelete = { onDelete(conv) },
                        )
                    }
                }
            }
        }
    }
}

/**
 * Trailing swipe reveals Archive + Delete (iOS MessagesView swipeActions).
 * Long-press also opens a context menu for accessibility.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SwipeableConversationRow(
    conversation: ConversationItem,
    onOpen: () -> Unit,
    onArchive: () -> Unit,
    onDelete: () -> Unit,
) {
    val density = LocalDensity.current
    val actionWidthPx = with(density) { 72.dp.toPx() }
    val maxSwipePx = actionWidthPx * 2f
    val openThreshold = actionWidthPx * 0.55f
    val offsetX = remember(conversation.id) { Animatable(0f) }
    val scope = rememberCoroutineScope()
    var menuOpen by remember { mutableStateOf(false) }

    fun snapClosed() {
        scope.launch {
            offsetX.animateTo(0f, animationSpec = spring(dampingRatio = 0.85f, stiffness = 500f))
        }
    }

    fun snapOpen() {
        scope.launch {
            offsetX.animateTo(-maxSwipePx, animationSpec = spring(dampingRatio = 0.85f, stiffness = 500f))
        }
    }

    Box(Modifier.fillMaxWidth()) {
        // Action rail under the row (Archive + Delete).
        Row(
            Modifier
                .matchParentSize()
                .background(MatteryaColors.surface),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .width(72.dp)
                    .fillMaxSize()
                    .background(MatteryaColors.accentBright)
                    .clickable {
                        snapClosed()
                        onArchive()
                    },
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Archive, contentDescription = "Archive", tint = Color.White, modifier = Modifier.size(20.dp))
                    Text("Archive", fontSize = 11.sp, color = Color.White, fontWeight = FontWeight.SemiBold)
                }
            }
            Box(
                Modifier
                    .width(72.dp)
                    .fillMaxSize()
                    .background(MatteryaColors.danger)
                    .clickable {
                        snapClosed()
                        onDelete()
                    },
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Color.White, modifier = Modifier.size(20.dp))
                    Text("Delete", fontSize = 11.sp, color = Color.White, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        Box(
            Modifier
                .offset { IntOffset(offsetX.value.roundToInt(), 0) }
                .fillMaxWidth()
                .background(MatteryaColors.surface)
                .pointerInput(conversation.id) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            if (offsetX.value <= -openThreshold) snapOpen() else snapClosed()
                        },
                        onDragCancel = { snapClosed() },
                        onHorizontalDrag = { _, dragAmount ->
                            val next = (offsetX.value + dragAmount).coerceIn(-maxSwipePx, 0f)
                            scope.launch { offsetX.snapTo(next) }
                        },
                    )
                }
                .combinedClickable(
                    onClick = {
                        if (offsetX.value < -8f) snapClosed() else onOpen()
                    },
                    onLongClick = { menuOpen = true },
                ),
        ) {
            ConversationRowContent(conversation)
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text("Archive") },
                    onClick = {
                        menuOpen = false
                        onArchive()
                    },
                    leadingIcon = {
                        Icon(Icons.Default.Archive, contentDescription = null, tint = MatteryaColors.accentBright)
                    },
                )
                DropdownMenuItem(
                    text = { Text("Delete", color = MatteryaColors.danger) },
                    onClick = {
                        menuOpen = false
                        onDelete()
                    },
                    leadingIcon = {
                        Icon(Icons.Default.Delete, contentDescription = null, tint = MatteryaColors.danger)
                    },
                )
            }
        }
    }
}

/** iOS `ConversationRow` — avatar 48, subheadline title, caption preview, caption2 time. */
@Composable
private fun ConversationRowContent(conversation: ConversationItem) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AvatarView(
            url = conversation.avatarUrl,
            seed = conversation.peerUserId.ifEmpty { conversation.id },
            size = 48.dp,
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                conversation.title,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp, // subheadline
                color = MatteryaColors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                conversation.subtitle.ifEmpty { "No messages yet" },
                fontSize = 12.sp, // caption
                color = MatteryaColors.inkMuted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            if (conversation.relativeTime.isNotEmpty()) {
                Text(
                    conversation.relativeTime,
                    fontSize = 11.sp, // caption2
                    color = MatteryaColors.inkMuted,
                )
            }
            if (conversation.unreadCount > 0) {
                Spacer(Modifier.height(4.dp))
                UnreadBadge(count = conversation.unreadCount)
            }
        }
    }
}

data class ChatMessageItem(
    val id: String,
    val body: String,
    val isMine: Boolean = false,
    val share: Message.ShareInfo? = null,
    val imageUrl: String? = null,
    val isCallLog: Boolean = false,
    val isLastReadByPeer: Boolean = false,
    val replyQuote: String? = null,
    val replyAuthorName: String? = null,
    val reactionSummary: String? = null,
    val canUnsend: Boolean = false,
    val source: Message? = null,
)

private val QuickReactionEmojis = listOf("❤️", "😂", "👍", "😮", "😢", "🔥")

/**
 * Structure port of iOS `ConversationView` — bubbles, rich media, reply target,
 * long-press menu, image send chrome, composer, call actions.
 */
@Composable
fun ConversationView(
    title: String,
    messages: List<ChatMessageItem> = emptyList(),
    draft: String = "",
    onDraftChange: (String) -> Unit = {},
    onSend: () -> Unit = {},
    isLoading: Boolean = false,
    isSending: Boolean = false,
    errorMessage: String? = null,
    peerAvatarUrl: String? = null,
    peerName: String = title,
    onBack: () -> Unit = {},
    onAudioCall: () -> Unit = {},
    onVideoCall: () -> Unit = {},
    onPickImage: () -> Unit = {},
    pendingImageUri: android.net.Uri? = null,
    onClearPendingImage: () -> Unit = {},
    replyingTo: ChatMessageItem? = null,
    onCancelReply: () -> Unit = {},
    onReply: (ChatMessageItem) -> Unit = {},
    onLike: (ChatMessageItem) -> Unit = {},
    onReact: (ChatMessageItem, String) -> Unit = { _, _ -> },
    onUnsend: (ChatMessageItem) -> Unit = {},
    onRemoveLocally: (ChatMessageItem) -> Unit = {},
    onOpenShare: (Message.ShareInfo) -> Unit = {},
    hubMiniPost: com.matterya.matterya.model.CountryPost? = null,
    hubMiniPlaying: Boolean = false,
    onHubMiniExpand: () -> Unit = {},
    onHubMiniClose: () -> Unit = {},
    onHubMiniTogglePlay: () -> Unit = {},
) {
    val listState = rememberLazyListState()
    LaunchedEffect(messages.lastOrNull()?.id) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.lastIndex)
        }
    }

    val canSend = !isSending && (draft.isNotBlank() || pendingImageUri != null)

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        // Top bar
        Row(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface)
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AvatarView(url = peerAvatarUrl, seed = peerName, size = 34.dp)
            Spacer(Modifier.width(10.dp))
            Text(
                title,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            IconButton(onClick = onAudioCall) {
                Icon(Icons.Default.Call, contentDescription = "Audio call", tint = MatteryaColors.ink)
            }
            IconButton(onClick = onVideoCall) {
                Icon(Icons.Default.Videocam, contentDescription = "Video call", tint = MatteryaColors.ink)
            }
        }

        Box(Modifier.weight(1f)) {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                items(messages, key = { it.id }) { msg ->
                    MessageBubble(
                        message = msg,
                        onOpenShare = onOpenShare,
                        onReply = { onReply(msg) },
                        onLike = { onLike(msg) },
                        onReact = { emoji -> onReact(msg, emoji) },
                        onUnsend = { onUnsend(msg) },
                        onRemoveLocally = { onRemoveLocally(msg) },
                    )
                    Spacer(Modifier.height(8.dp))
                }
            }
            if (isLoading && messages.isEmpty()) {
                CircularProgressIndicator(
                    Modifier.align(Alignment.Center),
                    color = MatteryaColors.accentBright,
                )
            }
        }

        errorMessage?.let {
            Text(
                it,
                fontSize = 12.sp,
                color = MatteryaColors.danger,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }

        hubMiniPost?.let { post ->
            com.matterya.matterya.theme.YouTubeMiniPlayerBar(
                post = post,
                isPlaying = hubMiniPlaying,
                isMuted = false,
                onExpand = onHubMiniExpand,
                onClose = onHubMiniClose,
                onTogglePlay = onHubMiniTogglePlay,
            )
        }

        // Reply target banner (iOS composerBar replyingTo)
        replyingTo?.let { target ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(MatteryaColors.surface)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Box(
                    Modifier
                        .width(2.dp)
                        .height(36.dp)
                        .background(MatteryaColors.accent.copy(alpha = 0.45f), RoundedCornerShape(1.dp)),
                )
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        "Replying to ${target.replyAuthorName ?: if (target.isMine) "yourself" else peerName}",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.ink,
                    )
                    Text(
                        target.body.ifBlank { target.share?.previewLabel ?: "Message" },
                        fontSize = 12.sp,
                        color = MatteryaColors.inkSecondary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Text(
                    "Cancel",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.accent,
                    modifier = Modifier
                        .clickable(onClick = onCancelReply)
                        .padding(4.dp),
                )
            }
        }

        // Pending image preview
        pendingImageUri?.let { uri ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(MatteryaColors.surface)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                coil.compose.AsyncImage(
                    model = uri,
                    contentDescription = "Pending photo",
                    modifier = Modifier
                        .width(120.dp)
                        .height(80.dp)
                        .clip(RoundedCornerShape(10.dp)),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                )
                Spacer(Modifier.width(12.dp))
                Text(
                    "Remove",
                    color = MatteryaColors.danger,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    modifier = Modifier.clickable(onClick = onClearPendingImage),
                )
            }
        }

        // Composer
        Row(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface)
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onPickImage) {
                Icon(Icons.Default.Image, contentDescription = "Photo", tint = MatteryaColors.accentBright)
            }
            OutlinedTextField(
                value = draft,
                onValueChange = onDraftChange,
                modifier = Modifier.weight(1f),
                placeholder = {
                    Text(if (replyingTo != null) "Write a reply…" else "Message…")
                },
                singleLine = true,
            )
            IconButton(
                onClick = onSend,
                enabled = canSend,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.Send,
                    contentDescription = "Send",
                    tint = if (canSend) MatteryaColors.accentBright else MatteryaColors.inkMuted,
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageBubble(
    message: ChatMessageItem,
    onOpenShare: (Message.ShareInfo) -> Unit,
    onReply: () -> Unit,
    onLike: () -> Unit,
    onReact: (String) -> Unit,
    onUnsend: () -> Unit,
    onRemoveLocally: () -> Unit,
) {
    if (message.isCallLog) {
        ChatCallLogRow(text = message.body)
        return
    }

    var menuOpen by remember { mutableStateOf(false) }
    val density = LocalDensity.current
    val maxSwipePx = with(density) { 72.dp.toPx() }
    val replyThresholdPx = with(density) { 56.dp.toPx() }
    val swipeOffset = remember(message.id) { Animatable(0f) }
    val swipeScope = rememberCoroutineScope()
    val align = if (message.isMine) Alignment.CenterEnd else Alignment.CenterStart

    Box(Modifier.fillMaxWidth(), contentAlignment = align) {
        // iOS swipe-left "Reply" hint behind the bubble.
        if (swipeOffset.value < -18f) {
            Row(
                Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.Reply,
                    contentDescription = null,
                    tint = MatteryaColors.accent,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    "Reply",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.accent,
                )
            }
        }

        Column(
            horizontalAlignment = if (message.isMine) Alignment.End else Alignment.Start,
            modifier = Modifier
                .widthIn(max = 300.dp)
                .offset { IntOffset(swipeOffset.value.roundToInt(), 0) }
                .pointerInput(message.id) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            val triggered = swipeOffset.value <= -replyThresholdPx
                            swipeScope.launch {
                                if (triggered) onReply()
                                swipeOffset.animateTo(
                                    0f,
                                    animationSpec = spring(dampingRatio = 0.82f, stiffness = 400f),
                                )
                            }
                        },
                        onDragCancel = {
                            swipeScope.launch {
                                swipeOffset.animateTo(
                                    0f,
                                    animationSpec = spring(dampingRatio = 0.82f, stiffness = 400f),
                                )
                            }
                        },
                        onHorizontalDrag = { _, dragAmount ->
                            // Swipe left only (iOS: horizontal < 0), clamp to -72dp.
                            val next = (swipeOffset.value + dragAmount).coerceIn(-maxSwipePx, 0f)
                            swipeScope.launch { swipeOffset.snapTo(next) }
                        },
                    )
                }
                .combinedClickable(
                    onClick = {},
                    onLongClick = { menuOpen = true },
                    onDoubleClick = onLike,
                ),
        ) {
            message.replyQuote?.let { quote ->
                Text(
                    quote,
                    fontSize = 11.sp,
                    color = MatteryaColors.inkMuted,
                    maxLines = 2,
                    modifier = Modifier
                        .padding(bottom = 4.dp)
                        .background(MatteryaColors.canvasMuted, RoundedCornerShape(8.dp))
                        .padding(8.dp),
                )
            }
            message.share?.let { share ->
                ChatShareCard(share = share, isMine = message.isMine, onOpen = { onOpenShare(share) })
            }
            message.imageUrl?.let { url ->
                ChatImageBubble(url = url, isMine = message.isMine)
            }
            if (message.body.isNotBlank() && message.share == null && message.imageUrl == null) {
                Text(
                    message.body,
                    modifier = Modifier
                        .background(
                            if (message.isMine) MatteryaColors.accentBright else MatteryaColors.commentBubble,
                            RoundedCornerShape(16.dp),
                        )
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    color = if (message.isMine) Color.White else MatteryaColors.ink,
                )
            }
            message.reactionSummary?.takeIf { it.isNotBlank() }?.let { strip ->
                Text(
                    strip,
                    fontSize = 12.sp,
                    modifier = Modifier
                        .padding(top = 2.dp)
                        .background(MatteryaColors.surface, RoundedCornerShape(10.dp))
                        .padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
            if (message.isLastReadByPeer && message.isMine) {
                Text("Read", fontSize = 10.sp, color = MatteryaColors.inkMuted, modifier = Modifier.padding(top = 2.dp))
            }

            DropdownMenu(
                expanded = menuOpen,
                onDismissRequest = { menuOpen = false },
            ) {
                DropdownMenuItem(
                    text = { Text("Reply") },
                    onClick = {
                        menuOpen = false
                        onReply()
                    },
                )
                DropdownMenuItem(
                    text = { Text("Like ❤") },
                    onClick = {
                        menuOpen = false
                        onLike()
                    },
                )
                QuickReactionEmojis.forEach { emoji ->
                    DropdownMenuItem(
                        text = { Text(emoji) },
                        onClick = {
                            menuOpen = false
                            onReact(emoji)
                        },
                    )
                }
                if (message.canUnsend) {
                    DropdownMenuItem(
                        text = { Text("Unsend for Everyone", color = MatteryaColors.danger) },
                        onClick = {
                            menuOpen = false
                            onUnsend()
                        },
                    )
                }
                DropdownMenuItem(
                    text = {
                        Text("Remove from This Device", color = MatteryaColors.danger)
                    },
                    onClick = {
                        menuOpen = false
                        onRemoveLocally()
                    },
                )
            }
        }
    }
}
