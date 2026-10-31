package com.matterya.matterya.ui.messages

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.calls.CallKind
import com.matterya.matterya.data.calls.CallSessionManager
import com.matterya.matterya.data.media.MediaService
import com.matterya.matterya.data.media.PhotosPickerMediaLoader
import com.matterya.matterya.data.messages.MessagesService
import com.matterya.matterya.model.Conversation
import com.matterya.matterya.model.Message
import com.matterya.matterya.model.RelativeTime
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.viewmodel.AppState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Tracks which conversation chat screen is currently visible
 * (suppresses push banners for that chat) — iOS `ActiveConversationFocus`.
 */
object ActiveConversationFocus {
    @Volatile
    var currentId: String? = null
        private set

    fun set(conversationId: String?) {
        currentId = conversationId
    }

    fun isViewing(conversationId: String): Boolean = currentId == conversationId
}

/**
 * Local hide store — iOS `HiddenMessagesStore` (UserDefaults-backed).
 * Persists via SharedPreferences as JSON: `{ conversationId: [messageId, ...] }`.
 */
private object HiddenMessagesStore {
    private const val PREFS = "matterya_hidden_messages"
    private val memory = mutableMapOf<String, MutableSet<String>>()
    @Volatile private var prefs: android.content.SharedPreferences? = null
    @Volatile private var loadedKey: String? = null

    private fun storageKey(): String {
        val uid = runCatching { AuthService.instance.currentUser?.id }.getOrNull() ?: "anonymous"
        return "conversation.hiddenMessages.$uid"
    }

    fun ensure(context: Context) {
        if (prefs == null) {
            prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        }
        val key = storageKey()
        if (loadedKey != key) {
            memory.clear()
            load(key)
            loadedKey = key
        }
    }

    fun isHidden(conversationId: String, messageId: String): Boolean =
        memory[conversationId]?.contains(messageId) == true

    fun hide(conversationId: String, messageId: String) {
        memory.getOrPut(conversationId) { mutableSetOf() }.add(messageId)
        save()
    }

    fun unhide(conversationId: String, messageId: String) {
        memory[conversationId]?.remove(messageId)
        if (memory[conversationId]?.isEmpty() == true) memory.remove(conversationId)
        save()
    }

    private fun load(key: String) {
        val raw = prefs?.getString(key, null) ?: return
        runCatching {
            val obj = JSONObject(raw)
            val keys = obj.keys()
            while (keys.hasNext()) {
                val convId = keys.next()
                val arr = obj.optJSONArray(convId) ?: continue
                val set = mutableSetOf<String>()
                for (i in 0 until arr.length()) {
                    arr.optString(i)?.takeIf { it.isNotBlank() }?.let { set.add(it) }
                }
                if (set.isNotEmpty()) memory[convId] = set
            }
        }
    }

    private fun save() {
        val key = storageKey()
        val obj = JSONObject()
        for ((convId, ids) in memory) {
            if (ids.isEmpty()) continue
            obj.put(convId, JSONArray(ids.toList()))
        }
        prefs?.edit()?.putString(key, obj.toString())?.apply()
        loadedKey = key
    }
}

/**
 * iOS `ConversationRouteView` + deep `ConversationView` chrome:
 * reply target, long-press menu, image send via MediaService, share open routing.
 */
@Composable
fun ConversationRouteView(
    conversationId: String,
    seed: Conversation? = null,
    messages: List<Message> = emptyList(),
    currentUserId: String? = null,
    isLoading: Boolean = false,
    draft: String = "",
    onDraftChange: (String) -> Unit = {},
    onMessagesChange: (List<Message>) -> Unit = {},
    onSend: () -> Unit = {},
    onRefresh: suspend () -> Conversation? = { null },
    hardError: String? = null,
    appState: AppState? = null,
    messagesService: MessagesService = MessagesService.shared,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mediaService = remember { MediaService.get(context) }
    val callManager = remember { CallSessionManager.shared }
    HiddenMessagesStore.ensure(context)

    var conversation by remember(conversationId) {
        mutableStateOf(
            seed ?: Conversation(
                id = conversationId,
                isDirect = true,
                createdAt = "",
                updatedAt = "",
            ),
        )
    }
    var error by remember(conversationId) { mutableStateOf(hardError) }
    var sendError by remember(conversationId) { mutableStateOf<String?>(null) }
    var isSending by remember(conversationId) { mutableStateOf(false) }
    var replyingTo by remember(conversationId) { mutableStateOf<Message?>(null) }
    var pendingImageUri by remember(conversationId) { mutableStateOf<Uri?>(null) }
    var hiddenTick by remember(conversationId) { mutableStateOf(0) }
    // Peer last_read_at — polled ~8s like iOS so "Read" updates while chat is open.
    var peerLastReadAt by remember(conversationId) {
        mutableStateOf(
            seed?.otherMember(currentUserId.orEmpty())?.lastReadAt,
        )
    }

    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent(),
    ) { uri ->
        pendingImageUri = uri
    }

    DisposableEffect(conversationId) {
        ActiveConversationFocus.set(conversationId)
        onDispose {
            if (ActiveConversationFocus.isViewing(conversationId)) {
                ActiveConversationFocus.set(null)
            }
        }
    }

    LaunchedEffect(conversationId) {
        runCatching {
            val fetched = onRefresh()
            if (fetched != null) {
                conversation = fetched
                val me = currentUserId.orEmpty()
                if (me.isNotEmpty()) {
                    peerLastReadAt = fetched.otherMember(me)?.lastReadAt ?: peerLastReadAt
                }
            } else if (conversation.members.isEmpty() && conversation.createdAt.isEmpty()) {
                error = "Conversation not found."
            }
        }.onFailure {
            if (conversation.members.isEmpty() && conversation.createdAt.isEmpty()) {
                error = it.message
            }
        }
        runCatching { callManager.ensureSignalingReady() }
    }

    // iOS pollPeerReadReceipts — gentle 8s interval while this chat is open.
    LaunchedEffect(conversationId, currentUserId) {
        val me = currentUserId ?: return@LaunchedEffect
        while (true) {
            delay(8_000)
            val refreshed = runCatching {
                messagesService.getConversationById(conversationId)
            }.getOrNull() ?: continue
            conversation = refreshed
            val peerRead = refreshed.otherMember(me)?.lastReadAt
            if (peerRead != peerLastReadAt) {
                peerLastReadAt = peerRead
            }
        }
    }

    when {
        error != null && conversation.members.isEmpty() -> {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(MatteryaColors.paper),
                contentAlignment = Alignment.Center,
            ) {
                Text(error ?: "Chat unavailable", color = MatteryaColors.danger)
            }
        }
        else -> {
            val peer = conversation.otherMember(currentUserId.orEmpty())
            val title = peer?.let { it.displayName ?: it.username } ?: "Chat"
            val emptySnap = remember {
                kotlinx.coroutines.flow.MutableStateFlow(
                    com.matterya.matterya.viewmodel.AppStateSnapshot(),
                )
            }
            val appSnap by (appState?.snapshot ?: emptySnap).collectAsState()

            // Build reaction summaries from raw messages (including reaction-only rows).
            val reactionSummaries = remember(messages) {
                buildReactionSummaries(messages)
            }

            val visibleMessages = remember(messages, hiddenTick) {
                messages
                    .filter { it.isRenderableInChat }
                    .filter { !HiddenMessagesStore.isHidden(conversationId, it.id) }
            }

            // Latest of my messages the peer has read (date compare + 2s skew — iOS parity).
            val lastReadOwnId = remember(visibleMessages, peerLastReadAt, currentUserId) {
                val me = currentUserId ?: return@remember null
                val peerRead = peerLastReadAt?.takeIf { it.isNotBlank() } ?: return@remember null
                val readDate = RelativeTime.parseDate(peerRead) ?: return@remember null
                val skew = java.time.Duration.ofSeconds(2)
                visibleMessages
                    .filter {
                        it.senderId == me &&
                            !it.isCallLog &&
                            !it.id.startsWith("pending-")
                    }
                    .filter { msg ->
                        val created = RelativeTime.parseDate(msg.createdAt) ?: return@filter false
                        // readDate - created >= -2s  ⇒  created <= readDate + 2s
                        !created.isAfter(readDate.plus(skew))
                    }
                    .lastOrNull()
                    ?.id
            }

            fun toChatItem(msg: Message): ChatMessageItem {
                val reply = msg.replyInfo
                val replyAuthor = reply?.targetId?.let { tid ->
                    messages.firstOrNull { it.id == tid }
                        ?.sender
                        ?.let { it.displayName ?: it.username }
                        ?: "Message"
                }
                val reactions = reactionSummaries[msg.id]
                val reactionStrip = reactions?.entries
                    ?.sortedBy { it.key }
                    ?.joinToString(" ") { (emoji, count) ->
                        if (count > 1) "$emoji $count" else emoji
                    }
                return ChatMessageItem(
                    id = msg.id,
                    body = msg.displayText ?: msg.previewText,
                    isMine = msg.senderId == currentUserId,
                    share = msg.shareInfo,
                    imageUrl = if (msg.hasImage) msg.mediaUrl ?: msg.mediaPath else null,
                    isCallLog = msg.isCallLog,
                    isLastReadByPeer = msg.id == lastReadOwnId && msg.senderId == currentUserId,
                    replyQuote = reply?.quotedText,
                    replyAuthorName = replyAuthor,
                    reactionSummary = reactionStrip,
                    canUnsend = msg.senderId == currentUserId && !msg.id.startsWith("pending-"),
                    source = msg,
                )
            }

            val chatItems = visibleMessages.map { toChatItem(it) }
            val replyItem = replyingTo?.let { toChatItem(it) }

            fun sendTextOrImage() {
                val trimmed = draft.trim()
                val pendingUri = pendingImageUri
                if (trimmed.isEmpty() && pendingUri == null) return
                if (isSending) return

                scope.launch {
                    isSending = true
                    sendError = null
                    val body = if (replyingTo != null && trimmed.isNotEmpty()) {
                        Message.buildReplyBody(replyingTo!!, trimmed)
                    } else {
                        trimmed
                    }
                    val savedReply = replyingTo
                    replyingTo = null
                    onDraftChange("")
                    val savedUri = pendingUri
                    pendingImageUri = null

                    val usesPlaceholder = savedUri == null
                    val placeholderId = if (usesPlaceholder) "pending-${java.util.UUID.randomUUID()}" else null
                    if (usesPlaceholder && placeholderId != null) {
                        val now = java.time.Instant.now().toString()
                        val placeholder = Message(
                            id = placeholderId,
                            conversationId = conversationId,
                            senderId = currentUserId.orEmpty(),
                            body = body,
                            createdAt = now,
                            updatedAt = now,
                        )
                        onMessagesChange(messages + placeholder)
                    }

                    try {
                        val sent = if (savedUri != null) {
                            val jpeg = PhotosPickerMediaLoader.loadJpegData(
                                context,
                                savedUri,
                                compressionQuality = 86,
                                maxEdge = 1600,
                            )
                            val upload = mediaService.uploadMessageMedia(
                                data = jpeg,
                                conversationId = conversationId,
                                fileName = "image.jpg",
                                mimeType = "image/jpeg",
                            )
                            messagesService.sendMessage(
                                conversationId = conversationId,
                                body = body,
                                mediaType = "image",
                                mediaPath = upload.path,
                                mediaName = upload.name,
                                mediaMime = upload.mime,
                                mediaSize = upload.size,
                            )
                        } else {
                            messagesService.sendMessage(conversationId, body)
                        }
                        val withoutPlaceholder = if (placeholderId != null) {
                            messages.filter { it.id != placeholderId }
                        } else {
                            messages
                        }
                        onMessagesChange(withoutPlaceholder + sent)
                    } catch (e: Exception) {
                        if (placeholderId != null) {
                            onMessagesChange(messages.filter { it.id != placeholderId })
                        }
                        onDraftChange(body)
                        replyingTo = savedReply
                        pendingImageUri = savedUri
                        sendError = e.message ?: "Send failed"
                    } finally {
                        isSending = false
                    }
                }
            }

            fun toggleLike(item: ChatMessageItem) {
                val target = item.source ?: return
                if (target.id.startsWith("pending-")) return
                val liked = reactionSummaries[target.id]?.get("❤")?.let { it > 0 } == true ||
                    reactionSummaries[target.id]?.get("❤️")?.let { it > 0 } == true
                scope.launch {
                    val body = Message.buildReactionBody(target.id, "❤", active = !liked)
                    runCatching { messagesService.sendMessage(conversationId, body) }
                        .onSuccess { reaction -> onMessagesChange(messages + reaction) }
                        .onFailure { sendError = it.message }
                }
            }

            fun react(item: ChatMessageItem, emoji: String) {
                val target = item.source ?: return
                if (target.id.startsWith("pending-")) return
                val normalized = if (emoji == "❤️") "❤" else emoji
                scope.launch {
                    val body = Message.buildReactionBody(target.id, normalized, active = true)
                    runCatching { messagesService.sendMessage(conversationId, body) }
                        .onSuccess { reaction -> onMessagesChange(messages + reaction) }
                        .onFailure { sendError = it.message }
                }
            }

            fun unsend(item: ChatMessageItem) {
                val target = item.source ?: return
                if (target.senderId != currentUserId || target.id.startsWith("pending-")) return
                scope.launch {
                    runCatching { messagesService.deleteMessage(target.id) }
                        .onSuccess { ok ->
                            if (ok) {
                                HiddenMessagesStore.unhide(conversationId, target.id)
                                onMessagesChange(messages.filter { it.id != target.id })
                            }
                        }
                        .onFailure { sendError = it.message }
                }
            }

            ConversationView(
                title = title,
                messages = chatItems,
                draft = draft,
                onDraftChange = onDraftChange,
                onSend = {
                    if (pendingImageUri != null || draft.isNotBlank()) {
                        sendTextOrImage()
                    } else {
                        onSend()
                    }
                },
                isLoading = isLoading && visibleMessages.isEmpty(),
                isSending = isSending,
                errorMessage = sendError,
                peerAvatarUrl = peer?.avatarUrl,
                peerName = title,
                onAudioCall = {
                    scope.launch {
                        callManager.startCall(
                            conversationId = conversationId,
                            kind = CallKind.Audio,
                            peer = peer,
                        )
                    }
                },
                onVideoCall = {
                    scope.launch {
                        callManager.startCall(
                            conversationId = conversationId,
                            kind = CallKind.Video,
                            peer = peer,
                        )
                    }
                },
                onPickImage = { imagePicker.launch("image/*") },
                pendingImageUri = pendingImageUri,
                onClearPendingImage = { pendingImageUri = null },
                replyingTo = replyItem,
                onCancelReply = { replyingTo = null },
                onReply = { item ->
                    replyingTo = item.source ?: messages.firstOrNull { it.id == item.id }
                },
                onLike = { toggleLike(it) },
                onReact = { item, emoji -> react(item, emoji) },
                onUnsend = { unsend(it) },
                onRemoveLocally = { item ->
                    HiddenMessagesStore.hide(conversationId, item.id)
                    hiddenTick++
                },
                onOpenShare = { share ->
                    appState?.let { ChatShareRouting.open(share, it) }
                },
                hubMiniPost = appSnap.hubPlaybackPost?.takeIf { !appSnap.hubPlaybackExpanded },
                hubMiniPlaying = appSnap.hubPlaybackPlaying,
                onHubMiniExpand = { appState?.expandHubPlayback() },
                onHubMiniClose = { appState?.stopHubPlayback() },
                onHubMiniTogglePlay = {
                    appState?.setHubPlaybackPlaying(!appSnap.hubPlaybackPlaying)
                },
            )
        }
    }
}

private fun buildReactionSummaries(
    messages: List<Message>,
): Map<String, Map<String, Int>> {
    // targetId -> userId -> (emoji, active)
    val byUser = mutableMapOf<String, MutableMap<String, Pair<String, Boolean>>>()
    for (message in messages) {
        val reaction = message.reactionInfo ?: continue
        val targetId = reaction.targetId
        val senderId = message.senderId
        if (targetId.isEmpty() || senderId.isEmpty()) continue
        byUser.getOrPut(targetId) { mutableMapOf() }[senderId] =
            reaction.emoji to reaction.isActive
    }
    val result = mutableMapOf<String, Map<String, Int>>()
    for ((targetId, userMap) in byUser) {
        val counts = mutableMapOf<String, Int>()
        for ((_, entry) in userMap) {
            if (!entry.second) continue
            val emoji = if (entry.first == "❤️") "❤" else entry.first
            counts[emoji] = (counts[emoji] ?: 0) + 1
        }
        if (counts.isNotEmpty()) result[targetId] = counts
    }
    return result
}
