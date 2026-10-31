package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.messages.MessagesService
import com.matterya.matterya.model.AnonymousPhase
import com.matterya.matterya.model.AnonymousRoute
import com.matterya.matterya.model.Message
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.theme.screenBackground
import com.matterya.matterya.ui.components.ToastBanner
import com.matterya.matterya.ui.components.ToastStyle
import com.matterya.matterya.ui.messages.ConversationRouteView
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

enum class AnonymousShellTab(val title: String) {
    Feed("Feed"),
    Spaces("Spaces"),
    Search("Search"),
    Inbox("Inbox"),
    Me("Me"),
    ;

    companion object {
        val chipTabs = listOf(Feed, Spaces, Inbox, Me)
    }
}

/** iOS `AnonymousRootView` — Masquerade shell with phase gates + nested navigation. */
@Composable
fun AnonymousRootView(
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val store = remember { AnonymousStore.get(context) }
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()

    var shellTab by remember { mutableStateOf(AnonymousShellTab.Feed) }
    var searchQuery by remember { mutableStateOf("") }
    var showCreateSpace by remember { mutableStateOf(false) }
    var showHeaderCreateMenu by remember { mutableStateOf(false) }
    var showNotificationsMenu by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf<String?>(null) }

    val isPushed = state.navigationPath.isNotEmpty()
    val route = state.navigationPath.lastOrNull()

    LaunchedEffect(Unit) {
        store.bootstrap()
    }

    LaunchedEffect(state.phase) {
        if (state.phase == AnonymousPhase.Ready) {
            store.loadInbox(force = false)
            store.refreshMasqueradeMessageUnread()
        }
    }

    LaunchedEffect(state.lastError) {
        val msg = state.lastError
        if (msg != null && state.shouldToastLastError) {
            toast = store.consumeError()
        }
    }

    Box(Modifier.fillMaxSize().screenBackground()) {
        when {
            showCreateSpace -> {
                AnonymousCreateSpaceView(
                    store = store,
                    onBack = { showCreateSpace = false },
                    onCreated = { slug ->
                        showCreateSpace = false
                        store.pushSpace(slug)
                    },
                )
            }
            route is AnonymousRoute.Space -> {
                AnonymousSpaceDetailView(
                    store = store,
                    slug = route.slug,
                    onBack = { store.popNavigation() },
                )
            }
            route is AnonymousRoute.Post -> {
                AnonymousPostDetailView(
                    store = store,
                    postId = route.id,
                    onBack = { store.popNavigation() },
                )
            }
            route is AnonymousRoute.Profile -> {
                AnonymousPublicProfileView(
                    store = store,
                    username = route.username,
                    onBack = { store.popNavigation() },
                )
            }
            route is AnonymousRoute.Conversation -> {
                // Stay inside Masquerade — Back returns to Inbox (never jumps to Messages tab).
                val conversationId = route.id
                val messagesService = remember { MessagesService.shared }
                val me = AuthService.instance.currentUser?.id
                var messages by remember(conversationId) { mutableStateOf<List<Message>>(emptyList()) }
                var draft by remember(conversationId) { mutableStateOf("") }
                var loading by remember(conversationId) { mutableStateOf(true) }
                val seed = remember(conversationId) { messagesService.cachedConversation(conversationId) }

                LaunchedEffect(conversationId) {
                    loading = true
                    messages = messagesService.cachedMessages(conversationId).orEmpty()
                    runCatching { messagesService.listMessages(conversationId) }
                        .onSuccess { messages = it }
                    loading = false
                    store.refreshMasqueradeMessageUnread()
                }

                Column(Modifier.fillMaxSize().statusBarsPadding()) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconButton(onClick = {
                            store.popNavigation()
                            scope.launch { store.refreshMasqueradeMessageUnread() }
                        }) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = MatteryaColors.ink)
                        }
                        Text(
                            "Masquerade chat",
                            fontWeight = FontWeight.SemiBold,
                            color = MatteryaColors.ink,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    ConversationRouteView(
                        conversationId = conversationId,
                        seed = seed,
                        messages = messages,
                        currentUserId = me,
                        isLoading = loading,
                        draft = draft,
                        onDraftChange = { draft = it },
                        onMessagesChange = { messages = it },
                        onSend = {
                            val text = draft.trim()
                            if (text.isEmpty()) return@ConversationRouteView
                            scope.launch {
                                runCatching {
                                    messagesService.sendMessage(conversationId, text)
                                }.onSuccess { sent ->
                                    messages = messages + sent
                                    draft = ""
                                }
                            }
                        },
                        onRefresh = {
                            messagesService.getConversationById(conversationId)
                                ?: messagesService.listConversations(inbox = "masquerade")
                                    .firstOrNull { it.id == conversationId }
                        },
                        messagesService = messagesService,
                    )
                }
            }
            else -> {
                Column(Modifier.fillMaxSize().statusBarsPadding()) {
                    // Header
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconButton(onClick = onClose) {
                            Icon(Icons.Default.Close, contentDescription = "Close", tint = MatteryaColors.ink)
                        }
                        MasqueradeBrandMark(compact = true, modifier = Modifier.weight(1f))
                        if (state.phase == AnonymousPhase.Ready) {
                            IconButton(onClick = {
                                showHeaderCreateMenu = false
                                showNotificationsMenu = !showNotificationsMenu
                                if (showNotificationsMenu) {
                                    scope.launch { store.loadInbox(force = true) }
                                }
                            }) {
                                Icon(
                                    Icons.Default.Notifications,
                                    contentDescription = "Notifications",
                                    tint = if (showNotificationsMenu) MatteryaColors.ink else MatteryaColors.inkMuted,
                                )
                            }
                            IconButton(onClick = {
                                showNotificationsMenu = false
                                showHeaderCreateMenu = !showHeaderCreateMenu
                            }) {
                                Icon(Icons.Default.Add, contentDescription = "Create", tint = MatteryaColors.ink)
                            }
                        }
                    }

                    if (state.phase == AnonymousPhase.Ready && !isPushed) {
                        OutlinedTextField(
                            value = searchQuery,
                            onValueChange = {
                                searchQuery = it
                                if (it.isNotBlank()) shellTab = AnonymousShellTab.Search
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = MatteryaDimens.pagePadding)
                                .padding(bottom = 6.dp),
                            placeholder = { Text(MatteryaCopy.anonymousSearchHint) },
                            leadingIcon = {
                                Icon(Icons.Default.Search, null, tint = MatteryaColors.inkMuted)
                            },
                            singleLine = true,
                            shape = RoundedCornerShape(12.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = MatteryaColors.border,
                                unfocusedBorderColor = MatteryaColors.border,
                            ),
                        )
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(horizontal = MatteryaDimens.pagePadding),
                        ) {
                            AnonymousShellTab.chipTabs.forEach { tab ->
                                FilterChip(
                                    selected = shellTab == tab ||
                                        (shellTab == AnonymousShellTab.Search && tab == AnonymousShellTab.Feed && searchQuery.isBlank()),
                                    onClick = {
                                        searchQuery = ""
                                        shellTab = tab
                                        store.resetNavigation()
                                    },
                                    label = {
                                        val badge = when (tab) {
                                            AnonymousShellTab.Inbox -> state.totalMasqueradeUnread
                                            else -> 0
                                        }
                                        Text(if (badge > 0) "${tab.title} ($badge)" else tab.title)
                                    },
                                    modifier = Modifier.padding(end = 6.dp),
                                )
                            }
                        }
                        Spacer(Modifier.height(4.dp))
                    }

                    Box(Modifier.weight(1f)) {
                        when (state.phase) {
                            AnonymousPhase.Loading -> AnonymousLoadingSkeleton()
                            AnonymousPhase.GatedUnder18 -> AnonymousAgeGateView(
                                mode = if (state.session.birthdateMissing && state.session.eligibleAdult.not() &&
                                    state.session.gateCode != "under_18"
                                ) {
                                    AnonymousAgeGateMode.MissingBirthdate
                                } else {
                                    AnonymousAgeGateMode.Under18
                                },
                                store = store,
                            )
                            AnonymousPhase.NeedAttest -> AnonymousAgeGateView(
                                mode = AnonymousAgeGateMode.Attest,
                                store = store,
                            )
                            AnonymousPhase.NeedUsername -> AnonymousUsernameClaimView(store)
                            AnonymousPhase.WelcomeLetter -> AnonymousWelcomeLetterView(store)
                            AnonymousPhase.PickSpaces -> AnonymousSpacesOnboardingView(store)
                            AnonymousPhase.Suspended -> AnonymousEmptyState(
                                title = MatteryaCopy.anonymousSuspendedTitle,
                                message = MatteryaCopy.anonymousSuspendedBody,
                            )
                            AnonymousPhase.Offline -> AnonymousEmptyState(
                                title = MatteryaCopy.anonymousOfflineTitle,
                                message = MatteryaCopy.anonymousOfflineBody,
                                actionTitle = "Retry",
                                onAction = { scope.launch { store.refreshSession() } },
                            )
                            AnonymousPhase.Ready -> {
                                when {
                                    searchQuery.isNotBlank() || shellTab == AnonymousShellTab.Search ->
                                        AnonymousSearchView(store, searchQuery)
                                    shellTab == AnonymousShellTab.Spaces ->
                                        AnonymousSpacesDirectoryView(
                                            store = store,
                                            onCreateSpace = { showCreateSpace = true },
                                        )
                                    shellTab == AnonymousShellTab.Inbox -> AnonymousInboxView(store)
                                    shellTab == AnonymousShellTab.Me -> AnonymousMeView(store)
                                    else -> AnonymousFeedView(store)
                                }
                            }
                        }

                        if (state.showWildeEpigraph &&
                            state.phase in setOf(
                                AnonymousPhase.NeedUsername,
                                AnonymousPhase.WelcomeLetter,
                                AnonymousPhase.PickSpaces,
                                AnonymousPhase.NeedAttest,
                            )
                        ) {
                            WildeEpigraph(
                                onDismiss = { store.markWildeSeenIfReady() },
                            )
                        }
                    }
                }

                if (showHeaderCreateMenu && state.phase == AnonymousPhase.Ready) {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .clickable { showHeaderCreateMenu = false },
                    ) {
                        Column(
                            Modifier
                                .align(Alignment.TopEnd)
                                .padding(top = 56.dp, end = MatteryaDimens.pagePadding)
                                .background(MatteryaColors.surface, RoundedCornerShape(12.dp))
                                .padding(8.dp)
                                .clickable(enabled = false) {},
                        ) {
                            Text(
                                MatteryaCopy.anonymousCreateMenuTitle,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.padding(8.dp),
                                color = MatteryaColors.ink,
                            )
                            TextButton(onClick = {
                                showHeaderCreateMenu = false
                                showCreateSpace = true
                            }) {
                                Text(MatteryaCopy.anonymousCreateSpace, color = MatteryaColors.ink)
                            }
                            TextButton(onClick = {
                                showHeaderCreateMenu = false
                                shellTab = AnonymousShellTab.Spaces
                            }) {
                                Text(MatteryaCopy.anonymousCreatePost, color = MatteryaColors.ink)
                            }
                        }
                    }
                }

                if (showNotificationsMenu && state.phase == AnonymousPhase.Ready) {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .background(MatteryaColors.ink.copy(alpha = 0.18f))
                            .clickable { showNotificationsMenu = false },
                    ) {
                        Column(
                            Modifier
                                .align(Alignment.TopEnd)
                                .padding(top = 52.dp, end = MatteryaDimens.pagePadding, start = MatteryaDimens.pagePadding)
                                .fillMaxWidth(0.92f)
                                .background(MatteryaColors.surface, RoundedCornerShape(12.dp))
                                .padding(12.dp)
                                .height(320.dp)
                                .clickable(enabled = false) {},
                        ) {
                            Text("Notifications", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                            Spacer(Modifier.height(8.dp))
                            if (state.inbox.isEmpty()) {
                                Text(MatteryaCopy.anonymousNotificationsBody, color = MatteryaColors.inkMuted, fontSize = 13.sp)
                            } else {
                                state.inbox.take(8).forEach { item ->
                                    Column(
                                        Modifier
                                            .fillMaxWidth()
                                            .clickable {
                                                showNotificationsMenu = false
                                                scope.launch { store.markNotificationRead(item) }
                                                item.postId?.let { store.pushPostId(it) }
                                                    ?: item.spaceId?.let { /* open via slug if known */ }
                                            }
                                            .padding(vertical = 8.dp),
                                    ) {
                                        Text(item.displayTitle, fontWeight = FontWeight.Medium, color = MatteryaColors.ink)
                                        Text(item.displayBody, color = MatteryaColors.inkMuted, fontSize = 12.sp)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        toast?.let { msg ->
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(top = 48.dp),
                contentAlignment = Alignment.TopCenter,
            ) {
                ToastBanner(message = msg, style = ToastStyle.Error)
            }
            LaunchedEffect(msg) {
                kotlinx.coroutines.delay(2800)
                toast = null
            }
        }
    }
}

@Composable
private fun WildeEpigraph(onDismiss: () -> Unit) {
    Box(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper.copy(alpha = 0.96f))
            .clickable(onClick = onDismiss),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier.padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                MatteryaCopy.anonymousWildeQuote,
                fontWeight = FontWeight.Medium,
                fontSize = 18.sp,
                color = MatteryaColors.ink,
            )
            Spacer(Modifier.height(12.dp))
            Text(MatteryaCopy.anonymousWildeAttribution, color = MatteryaColors.inkMuted, fontSize = 13.sp)
            Spacer(Modifier.height(8.dp))
            Text(MatteryaCopy.anonymousTagline, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
        }
    }
}
