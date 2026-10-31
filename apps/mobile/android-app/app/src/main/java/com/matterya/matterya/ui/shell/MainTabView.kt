package com.matterya.matterya.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.core.app.NotificationManagerCompat
import com.matterya.matterya.data.ads.AdsService
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.calls.CallSignalingService
import com.matterya.matterya.data.letters.LettersService
import com.matterya.matterya.data.calls.TelecomCallManager
import com.matterya.matterya.data.media.NowPlayingService
import com.matterya.matterya.data.messages.ConversationInboxStore
import com.matterya.matterya.data.messages.MessagesService
import com.matterya.matterya.data.push.PushNotificationService
import com.matterya.matterya.data.push.VoIPPushService
import com.matterya.matterya.data.social.BlockService
import com.matterya.matterya.model.AppTab
import com.matterya.matterya.model.Conversation
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.CountryTab
import com.matterya.matterya.model.ExternalNewsItem
import com.matterya.matterya.model.Message
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.RelativeTime
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.ui.ads.AdsView
import com.matterya.matterya.model.GlobePanel
import com.matterya.matterya.theme.YouTubeMiniPlayerBar
import com.matterya.matterya.ui.anonymous.AnonymousRootView
import com.matterya.matterya.ui.components.AppMenuAction
import com.matterya.matterya.ui.components.AppMenuOverlay
import com.matterya.matterya.ui.components.BottomTabBar
import com.matterya.matterya.ui.components.CreateMenuAction
import com.matterya.matterya.ui.components.CreateMenuSheet
import com.matterya.matterya.ui.components.PostComposerView
import com.matterya.matterya.ui.components.ReelComposerView
import com.matterya.matterya.ui.components.StoriesViewerView
import com.matterya.matterya.ui.components.StoryComposerView
import com.matterya.matterya.ui.components.ToastBanner
import com.matterya.matterya.ui.components.ToastStyle
import com.matterya.matterya.ui.connected.ConnectedHubView
import com.matterya.matterya.ui.feed.FeedView
import com.matterya.matterya.ui.globe.CountryFeedView
import com.matterya.matterya.ui.globe.GlobeView
import com.matterya.matterya.ui.globe.NotificationsOverlay
import com.matterya.matterya.ui.globe.PresenceOverlay
import com.matterya.matterya.ui.hubs.MatteryaHubsView
import com.matterya.matterya.ui.letters.LetterComposeView
import com.matterya.matterya.ui.letters.LetterThreadItem
import com.matterya.matterya.ui.letters.LettersInboxView
import com.matterya.matterya.ui.living.YouTubeWatchView
import com.matterya.matterya.ui.messages.ConversationItem
import com.matterya.matterya.ui.messages.ConversationRouteView
import com.matterya.matterya.ui.messages.MessagesView
import com.matterya.matterya.ui.navigation.NavRoutes
import com.matterya.matterya.ui.news.NewsDetailView
import com.matterya.matterya.ui.people.PeopleView
import com.matterya.matterya.ui.post.PostDetailView
import com.matterya.matterya.ui.profile.EditProfileView
import com.matterya.matterya.ui.profile.ProfileView
import com.matterya.matterya.ui.profile.PublicProfileView
import com.matterya.matterya.ui.reels.ReelsView
import com.matterya.matterya.ui.reels.SparksScrollViewer
import com.matterya.matterya.ui.search.SearchView
import com.matterya.matterya.ui.settings.BlockedAccountsView
import com.matterya.matterya.ui.settings.SettingsView
import com.matterya.matterya.viewmodel.AnonymousStore
import com.matterya.matterya.viewmodel.AppUiState
import com.matterya.matterya.viewmodel.AppViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Main tab shell — mirrors iOS `MainTabView`.
 * Tabs: Feed | Globe | (create) | Hubs | Messages | Profile.
 */
@Composable
fun MainTabView(
    state: AppUiState,
    vm: AppViewModel,
) {
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val route = backStack?.destination?.route
    val onTabsRoot = route == null || route == NavRoutes.tabs
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val messagesService = remember { MessagesService.shared }
    val adsService = remember { AdsService() }
    val lettersService = remember { LettersService.get(context) }

    var showAppMenu by remember { mutableStateOf(false) }
    var showCreateMenu by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf<String?>(null) }

    // Search
    var searchProfiles by remember { mutableStateOf<List<Profile>>(emptyList()) }
    var searchContent by remember { mutableStateOf<List<CountryPost>>(emptyList()) }
    var searchBusy by remember { mutableStateOf(false) }
    var searchError by remember { mutableStateOf<String?>(null) }

    // People
    var people by remember { mutableStateOf<List<Profile>>(emptyList()) }
    var peopleLoading by remember { mutableStateOf(false) }
    var peopleLoadingMore by remember { mutableStateOf(false) }
    var peopleHasMore by remember { mutableStateOf(true) }
    var peopleError by remember { mutableStateOf<String?>(null) }
    var peopleOffset by remember { mutableIntStateOf(0) }

    // Messages list
    var conversations by remember { mutableStateOf<List<ConversationItem>>(emptyList()) }
    var messagesLoading by remember { mutableStateOf(false) }
    var messagesError by remember { mutableStateOf<String?>(null) }

    // Ads
    var campaigns by remember { mutableStateOf(emptyList<com.matterya.matterya.model.AdCampaign>()) }
    var adsLoading by remember { mutableStateOf(false) }
    var adsError by remember { mutableStateOf<String?>(null) }

    // Letters
    val letterThreads by lettersService.threads.collectAsState()
    val letterQuota by lettersService.quota.collectAsState()

    LaunchedEffect(toast) {
        if (toast != null) {
            delay(2800)
            toast = null
        }
    }

    fun navigate(path: String) {
        showAppMenu = false
        showCreateMenu = false
        navController.navigate(path) { launchSingleTop = true }
    }

    fun homeCountry(): Country {
        val p = state.profile
        return Country(
            id = p?.countryCode ?: "XX",
            name = p?.countryName ?: "Home",
            iso = p?.countryCode ?: "XX",
        )
    }

    fun mapConversations(list: List<Conversation>): List<ConversationItem> {
        val me = state.profile?.userId.orEmpty()
        return list.map { c ->
            val other = c.otherMember(me)
            ConversationItem(
                id = c.id,
                title = other?.displayName ?: other?.username ?: "Chat",
                subtitle = c.lastMessage?.previewText.orEmpty(),
                avatarUrl = other?.avatarUrl,
                peerUserId = other?.userId.orEmpty(),
                unreadCount = 0,
                relativeTime = RelativeTime.format(c.lastMessageAt ?: c.updatedAt),
            )
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f)) {
                NavHost(
                    navController = navController,
                    startDestination = NavRoutes.tabs,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    composable(NavRoutes.tabs) {
                        TabContent(
                            state = state,
                            vm = vm,
                            conversations = conversations,
                            messagesLoading = messagesLoading,
                            messagesError = messagesError,
                            onLoadMessages = {
                                scope.launch {
                                    messagesLoading = true
                                    messagesError = null
                                    runCatching { messagesService.listConversations() }
                                        .onSuccess { list ->
                                            // iOS ConversationInboxStore — hide archived/deleted prefs.
                                            conversations = mapConversations(
                                                list.filter { !ConversationInboxStore.isHidden(it.id) },
                                            )
                                        }
                                        .onFailure { messagesError = it.message ?: "Failed to load messages" }
                                    messagesLoading = false
                                }
                            },
                            onArchiveConversation = { item ->
                                // Optimistic hide + toast (iOS "Chat archived"; no undo on iOS).
                                conversations = conversations.filter { it.id != item.id }
                                vm.appState.closeConversation(item.id)
                                toast = "Chat archived"
                                vm.appState.showToast("Chat archived", ToastStyle.Info)
                                scope.launch {
                                    val ok = runCatching {
                                        messagesService.archiveConversation(item.id)
                                    }.getOrDefault(false)
                                    if (ok) {
                                        ConversationInboxStore.clear(item.id)
                                    } else {
                                        ConversationInboxStore.markArchived(item.id)
                                    }
                                    vm.appState.refreshUnreadCounts()
                                }
                            },
                            onDeleteConversation = { item ->
                                conversations = conversations.filter { it.id != item.id }
                                vm.appState.closeConversation(item.id)
                                toast = "Chat removed"
                                vm.appState.showToast("Chat removed", ToastStyle.Info)
                                scope.launch {
                                    val ok = runCatching {
                                        messagesService.deleteConversation(item.id)
                                    }.getOrDefault(false)
                                    if (ok) {
                                        ConversationInboxStore.clear(item.id)
                                    } else {
                                        ConversationInboxStore.markDeleted(item.id)
                                    }
                                    vm.appState.refreshUnreadCounts()
                                }
                            },
                            onMenu = {
                                showAppMenu = true
                                scope.launch { vm.appState.refreshUnreadCounts() }
                            },
                            onSearch = { navigate(NavRoutes.search) },
                            onNotifications = { vm.appState.toggleNotificationsPanel() },
                            onPeople = { navigate(NavRoutes.people) },
                            onSettings = { navigate(NavRoutes.settings) },
                            onEditProfile = { navigate(NavRoutes.editProfile) },
                            onOpenPost = { navigate(NavRoutes.post(it)) },
                            onOpenReels = { post ->
                                vm.appState.openGlobalSparksViewer(post)
                            },
                            onOpenCountry = { iso -> navigate(NavRoutes.country(iso)) },
                            onOpenChat = { id -> navigate(NavRoutes.chat(id)) },
                            onOpenHubsWatch = { post ->
                                vm.appState.openPost(post)
                            },
                            onOpenAuthor = { post ->
                                vm.appState.openPublicProfile(
                                    username = post.author?.username,
                                    userId = post.authorId,
                                )
                            },
                        )
                    }
                    composable(NavRoutes.search) {
                        SearchView(
                            profiles = searchProfiles,
                            content = searchContent,
                            isSearching = searchBusy,
                            searchError = searchError,
                            currentUserId = state.profile?.userId,
                            isFollowing = { uid -> vm.appState.isFollowing(uid) },
                            onQueryChange = { q ->
                                scope.launch {
                                    if (q.isBlank()) {
                                        searchProfiles = emptyList()
                                        searchContent = emptyList()
                                        searchError = null
                                        searchBusy = false
                                        return@launch
                                    }
                                    searchBusy = true
                                    searchError = null
                                    delay(280) // debounce
                                    runCatching { vm.searchPeopleAndContent(q) }
                                        .onSuccess { (peopleResult, contentResult) ->
                                            searchProfiles = peopleResult
                                            searchContent = contentResult
                                        }
                                        .onFailure {
                                            searchError = it.message
                                            // Fallback: rank local feed
                                            searchProfiles = emptyList()
                                            searchContent = emptyList()
                                        }
                                    searchBusy = false
                                }
                            },
                            onOpenProfile = { p ->
                                val username = p.username
                                if (!username.isNullOrBlank()) navigate(NavRoutes.profile(username))
                                else navigate(NavRoutes.profileId(p.userId))
                            },
                            onOpenContent = { post ->
                                navigate(NavRoutes.post(post.id))
                            },
                            onOpenHubsChannel = {
                                navController.popBackStack(NavRoutes.tabs, inclusive = false)
                                vm.selectTab(AppTab.Hubs)
                            },
                            onFollowToggle = { uid -> vm.toggleFollow(uid) },
                            onLike = vm::toggleLike,
                        )
                    }
                    composable(NavRoutes.people) {
                        LaunchedEffect(Unit) {
                            if (people.isEmpty()) {
                                peopleLoading = true
                                peopleError = null
                                runCatching { vm.browsePeople(30, 0) }
                                    .onSuccess {
                                        people = it
                                        peopleOffset = it.size
                                        peopleHasMore = it.size >= 30
                                    }
                                    .onFailure { peopleError = it.message }
                                peopleLoading = false
                            }
                        }
                        PeopleView(
                            people = people,
                            isLoading = peopleLoading,
                            loadingMore = peopleLoadingMore,
                            hasMore = peopleHasMore,
                            errorMessage = peopleError,
                            currentUserId = state.profile?.userId,
                            isFollowing = { uid -> vm.appState.isFollowing(uid) },
                            onOpenProfile = { p ->
                                val username = p.username
                                if (!username.isNullOrBlank()) {
                                    navigate(NavRoutes.profile(username))
                                } else {
                                    navigate(NavRoutes.profileId(p.userId))
                                }
                            },
                            onFollow = { p -> vm.toggleFollow(p.userId) },
                            onFollowToggle = { uid -> vm.toggleFollow(uid) },
                            onLoadMore = {
                                scope.launch {
                                    peopleLoadingMore = true
                                    runCatching { vm.browsePeople(30, peopleOffset) }
                                        .onSuccess { page ->
                                            people = people + page.filter { next ->
                                                people.none { it.userId == next.userId }
                                            }
                                            peopleOffset += page.size
                                            peopleHasMore = page.size >= 30
                                        }
                                    peopleLoadingMore = false
                                }
                            },
                        )
                    }
                    composable(NavRoutes.settings) {
                        val push = remember { PushNotificationService.shared }
                        val voip = remember { VoIPPushService.shared }
                        val blockService = remember { BlockService.get(context) }
                        var pushEnabled by remember {
                            mutableStateOf(NotificationManagerCompat.from(context).areNotificationsEnabled())
                        }
                        var alertTokenStatus by remember { mutableStateOf("Checking…") }
                        var alertServerStatus by remember { mutableStateOf("Checking…") }
                        var pushRoutesStatus by remember { mutableStateOf("Checking…") }
                        var apnsStatus by remember { mutableStateOf("Checking…") }
                        var serverTokenSummary by remember { mutableStateOf("") }
                        var registrationSummary by remember { mutableStateOf("") }
                        var statusMessage by remember { mutableStateOf<String?>(null) }
                        var isRequestingPush by remember { mutableStateOf(false) }
                        var isSendingTest by remember { mutableStateOf(false) }
                        var isRefreshingPush by remember { mutableStateOf(false) }
                        var voipTokenStatus by remember { mutableStateOf("Checking…") }
                        var voipServerStatus by remember { mutableStateOf("Checking…") }
                        var signalingStatus by remember { mutableStateOf("Checking…") }
                        var incomingCallsReady by remember { mutableStateOf(false) }
                        var pushEnvironmentLabel by remember { mutableStateOf("Android FCM") }
                        var callingSummary by remember { mutableStateOf("") }
                        var isRefreshingCalling by remember { mutableStateOf(false) }
                        var blockedCount by remember { mutableStateOf(blockService.blocked.size) }

                        // Android 13+ POST_NOTIFICATIONS runtime prompt (Settings enable toggle).
                        var permissionContinuation by remember {
                            mutableStateOf<((Map<String, Boolean>) -> Unit)?>(null)
                        }
                        val notificationPermissionLauncher =
                            androidx.activity.compose.rememberLauncherForActivityResult(
                                androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions(),
                            ) { result ->
                                permissionContinuation?.invoke(result)
                                permissionContinuation = null
                            }
                        val requestPermissions: suspend (Array<String>) -> Map<String, Boolean> = { perms ->
                            kotlinx.coroutines.suspendCancellableCoroutine { cont ->
                                permissionContinuation = { result ->
                                    if (cont.isActive) {
                                        cont.resumeWith(Result.success(result))
                                    }
                                }
                                notificationPermissionLauncher.launch(perms)
                                cont.invokeOnCancellation { permissionContinuation = null }
                            }
                        }

                        suspend fun refreshPushStatus() {
                            isRefreshingPush = true
                            try {
                                pushEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
                                voip.bootstrap()
                                push.syncWithServer(force = true)
                                registrationSummary = push.registrationSummary
                                alertTokenStatus = if (push.hasAlertToken) "Received" else "Waiting"
                                alertServerStatus =
                                    if (push.serverRegistrationSucceeded) "Registered" else "Not registered"
                                val serverStatus = push.fetchServerPushStatus()
                                if (serverStatus != null) {
                                    pushRoutesStatus =
                                        if (serverStatus.endpointsAvailable) "Deployed" else "Missing"
                                    apnsStatus =
                                        if (serverStatus.fcmConfigured) "Configured" else "Not configured"
                                    serverTokenSummary = serverStatus.statusMessage
                                        ?: buildString {
                                            append("${serverStatus.alertTokenCount} alert")
                                            if (serverStatus.callTokenCount > 0) {
                                                append(" · ${serverStatus.callTokenCount} call")
                                            }
                                            if (serverStatus.environments.isNotEmpty()) {
                                                append(" · ${serverStatus.environments.joinToString(", ")}")
                                            }
                                        }
                                } else {
                                    pushRoutesStatus = "Unknown"
                                    apnsStatus = "Unknown"
                                    serverTokenSummary = "Could not load server push status."
                                }
                            } finally {
                                isRefreshingPush = false
                            }
                        }

                        suspend fun refreshCallingStatus() {
                            isRefreshingCalling = true
                            try {
                                voip.bootstrap()
                                CallSignalingService.shared.ensureConnected()
                                voip.ensureToken()
                                push.syncWithServer(force = true)
                                voipTokenStatus = when {
                                    push.hasHighPriorityCallToken -> "Received"
                                    else -> "Waiting"
                                }
                                voipServerStatus =
                                    if (push.callServerRegistrationSucceeded) "Registered" else "Not registered"
                                signalingStatus =
                                    if (CallSignalingService.shared.isConnected.value) "Connected" else "Offline"
                                incomingCallsReady = push.isReadyForIncomingCalls
                                pushEnvironmentLabel = "Android FCM"
                                callingSummary = push.callingRegistrationSummary
                            } finally {
                                isRefreshingCalling = false
                            }
                        }

                        LaunchedEffect(Unit) {
                            refreshPushStatus()
                            refreshCallingStatus()
                            blockedCount = blockService.blocked.size
                        }

                        // Keep TelecomCallManager + NowPlayingService warm from Settings path
                        // (AppState also holds strong refs — no "missing service" gap).
                        val telecom = remember { TelecomCallManager.shared }
                        val nowPlaying = remember { NowPlayingService.shared }
                        @Suppress("UNUSED_VARIABLE")
                        val telecomWarm = telecom.isAudioSessionActivated
                        @Suppress("UNUSED_VARIABLE")
                        val nowPlayingWarm = nowPlaying.localSnapshot

                        SettingsView(
                            profile = state.profile,
                            pushEnabled = pushEnabled,
                            alertTokenStatus = alertTokenStatus,
                            alertServerStatus = alertServerStatus,
                            pushRoutesStatus = pushRoutesStatus,
                            apnsStatus = apnsStatus,
                            serverTokenSummary = serverTokenSummary,
                            registrationSummary = registrationSummary,
                            statusMessage = statusMessage,
                            isRequestingPush = isRequestingPush,
                            isSendingTest = isSendingTest,
                            isRefreshingPush = isRefreshingPush,
                            voipTokenStatus = voipTokenStatus,
                            voipServerStatus = voipServerStatus,
                            signalingStatus = signalingStatus,
                            incomingCallsReady = incomingCallsReady,
                            pushEnvironmentLabel = pushEnvironmentLabel,
                            callingSummary = callingSummary,
                            isRefreshingCalling = isRefreshingCalling,
                            telecomStatus = vm.appState.telecomStatusSummary,
                            nowPlayingStatus = vm.appState.nowPlayingStatusSummary,
                            blockedCount = blockedCount,
                            onEditProfile = { navigate(NavRoutes.editProfile) },
                            onLogout = vm::logout,
                            onDeactivate = {
                                scope.launch {
                                    runCatching { vm.appState.deactivateAccount() }
                                        .onFailure { toast = it.message ?: "Deactivate failed" }
                                }
                            },
                            onDelete = { confirmation ->
                                scope.launch {
                                    runCatching { vm.appState.deleteAccount(confirmation) }
                                        .onFailure { toast = it.message ?: "Delete failed" }
                                }
                            },
                            onPushToggle = { enabled ->
                                if (enabled) {
                                    scope.launch {
                                        isRequestingPush = true
                                        statusMessage = null
                                        runCatching {
                                            // Runtime dialog on Android 13+; no-op launcher path below 33.
                                            push.requestAuthorizationAndRegister(requestPermissions)
                                            push.syncWithServer(force = true)
                                        }.onFailure {
                                            statusMessage = it.message
                                                ?: "Could not enable notifications."
                                        }
                                        refreshPushStatus()
                                        if (statusMessage == null) {
                                            statusMessage = if (pushEnabled) {
                                                "Notifications enabled for calls and messages."
                                            } else {
                                                // Denied or channel off — open system Settings as fallback.
                                                runCatching {
                                                    context.startActivity(
                                                        android.content.Intent(
                                                            android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS,
                                                        ).apply {
                                                            putExtra(
                                                                android.provider.Settings.EXTRA_APP_PACKAGE,
                                                                context.packageName,
                                                            )
                                                        },
                                                    )
                                                }
                                                "Enable notifications in system Settings to receive calls while away."
                                            }
                                        }
                                        isRequestingPush = false
                                    }
                                }
                            },
                            onSendTestPush = {
                                scope.launch {
                                    isSendingTest = true
                                    statusMessage = push.sendTestNotification()
                                    refreshPushStatus()
                                    isSendingTest = false
                                }
                            },
                            onRefreshPush = {
                                scope.launch { refreshPushStatus() }
                            },
                            onRefreshCalling = {
                                scope.launch { refreshCallingStatus() }
                            },
                            onOpenBlocked = { navigate(NavRoutes.blockedAccounts) },
                        )
                    }
                    composable(NavRoutes.blockedAccounts) {
                        val blockService = remember { BlockService.get(context) }
                        var blocked by remember { mutableStateOf(blockService.blocked) }
                        BlockedAccountsView(
                            blocked = blocked,
                            onUnblock = { userId ->
                                vm.appState.unblockUser(userId)
                                blocked = blockService.blocked
                            },
                        )
                    }
                    composable(NavRoutes.editProfile) {
                        var editBusy by remember { mutableStateOf(false) }
                        var uploadingAvatar by remember { mutableStateOf(false) }
                        var detectingLocation by remember { mutableStateOf(false) }
                        var locationStatus by remember { mutableStateOf("") }
                        var editError by remember { mutableStateOf<String?>(null) }
                        var editSuccess by remember { mutableStateOf<String?>(null) }
                        var countryName by remember(state.profile?.userId) {
                            mutableStateOf(state.profile?.countryName.orEmpty())
                        }
                        var countryCode by remember(state.profile?.userId) {
                            mutableStateOf(state.profile?.countryCode.orEmpty())
                        }
                        var cityName by remember(state.profile?.userId) {
                            mutableStateOf(state.profile?.cityName.orEmpty())
                        }
                        var avatarOverride by remember { mutableStateOf<String?>(null) }

                        LaunchedEffect(state.profile?.userId) {
                            // Auto-detect location on open (iOS EditProfileView.loadProfile).
                            detectingLocation = true
                            locationStatus = ""
                            runCatching { vm.detectAndApplyLocation() }
                                .onSuccess { detected ->
                                    countryName = detected.countryName
                                    countryCode = detected.countryCode
                                    cityName = detected.cityName.orEmpty()
                                    locationStatus = "Detected: ${detected.countryName}"
                                }
                                .onFailure {
                                    locationStatus = it.message
                                        ?: "Location unavailable. Enable Location for Matterya in Settings, then try again."
                                }
                            detectingLocation = false
                        }

                        EditProfileView(
                            profile = state.profile,
                            busy = editBusy,
                            uploadingAvatar = uploadingAvatar,
                            detectingLocation = detectingLocation,
                            locationStatus = locationStatus,
                            error = editError,
                            successMessage = editSuccess,
                            countryName = countryName,
                            countryCode = countryCode,
                            cityName = cityName,
                            avatarUrlOverride = avatarOverride,
                            onPickAvatarUri = { uri ->
                                scope.launch {
                                    uploadingAvatar = true
                                    editError = null
                                    editSuccess = null
                                    runCatching { vm.uploadAvatarAndApply(uri) }
                                        .onSuccess { updated ->
                                            avatarOverride = updated.avatarUrl
                                            editSuccess = "Profile photo updated."
                                        }
                                        .onFailure {
                                            editError = "Avatar upload failed: ${it.message}"
                                        }
                                    uploadingAvatar = false
                                }
                            },
                            onDetectLocation = {
                                scope.launch {
                                    detectingLocation = true
                                    locationStatus = ""
                                    editError = null
                                    runCatching { vm.detectAndApplyLocation() }
                                        .onSuccess { detected ->
                                            countryName = detected.countryName
                                            countryCode = detected.countryCode
                                            cityName = detected.cityName.orEmpty()
                                            locationStatus = "Detected: ${detected.countryName}"
                                        }
                                        .onFailure {
                                            locationStatus = it.message
                                                ?: "Could not detect location. Check your connection and try again."
                                        }
                                    detectingLocation = false
                                }
                            },
                            onSave = { name, username, bio, cName, cCode, cCity ->
                                scope.launch {
                                    editBusy = true
                                    editError = null
                                    editSuccess = null
                                    runCatching {
                                        vm.saveEditProfile(
                                            displayName = name,
                                            username = username,
                                            countryName = cName,
                                            countryCode = cCode,
                                            cityName = cCity,
                                            bio = bio,
                                            avatarUrl = avatarOverride ?: state.profile?.avatarUrl,
                                        )
                                    }.onSuccess {
                                        toast = "Profile saved."
                                        navController.popBackStack()
                                    }.onFailure {
                                        editError = "Save failed: ${it.message}"
                                    }
                                    editBusy = false
                                }
                            },
                        )
                    }
                    composable(NavRoutes.ads) {
                        LaunchedEffect(Unit) {
                            adsLoading = true
                            adsError = null
                            runCatching { adsService.myCampaigns() }
                                .onSuccess { campaigns = it }
                                .onFailure { adsError = it.message }
                            adsLoading = false
                        }
                        AdsView(
                            campaigns = campaigns,
                            isLoading = adsLoading,
                            errorMessage = adsError,
                            onBack = { navController.popBackStack() },
                            onCreate = { toast = "Campaign editor coming soon" },
                        )
                    }
                    composable(NavRoutes.masquerade) {
                        LaunchedEffect(Unit) {
                            AnonymousStore.get(context)
                        }
                        AnonymousRootView(
                            onClose = { navController.popBackStack() },
                        )
                    }
                    composable(NavRoutes.letters) {
                        val threads = letterThreads.map { t ->
                            LetterThreadItem(
                                id = t.id,
                                peerName = t.destinationCountryName.ifEmpty { "Pen friend" },
                                preview = t.latestMessage?.body.orEmpty(),
                                destinationCountry = t.destinationCountryName,
                                isInFlight = t.deliveryStatus.name == "InFlight" || t.awaitingTheirReply,
                                isPenFriend = t.isPenFriend,
                            )
                        }
                        LettersInboxView(
                            threads = threads,
                            remainingToday = letterQuota.remaining,
                            onBack = { navController.popBackStack() },
                            onWrite = { navigate(NavRoutes.composeLetter) },
                            onOpenThread = { toast = "Letter thread: ${it.peerName}" },
                        )
                    }
                    composable(NavRoutes.composeLetter) {
                        LetterComposeView(
                            remainingToday = letterQuota.remaining,
                            onCancel = { navController.popBackStack() },
                            onSend = { body, _ ->
                                runCatching {
                                    lettersService.sendNewLetter(
                                        body = body,
                                        myCountryCode = state.profile?.countryCode,
                                        myCountryName = state.profile?.countryName,
                                    )
                                }.onSuccess {
                                    toast = "Letter sealed — on its way"
                                    navController.popBackStack()
                                }.onFailure {
                                    toast = it.message ?: "Could not send letter"
                                }
                            },
                        )
                    }
                    composable(NavRoutes.connected) {
                        // Warm NowPlayingService (Apple Music parity) from Connected surface.
                        val nowPlayingSvc = remember { NowPlayingService.shared }
                        val liveSnap = remember { nowPlayingSvc.localSnapshot }
                        ConnectedHubView(
                            nowPlaying = liveSnap?.let { snap ->
                                com.matterya.matterya.ui.connected.YourNowPlaying(
                                    id = snap.contentId ?: "local",
                                    platform = com.matterya.matterya.ui.connected.StreamingPlatform.AppleMusic,
                                    title = snap.title,
                                    subtitle = snap.subtitle,
                                    progressLabel = "",
                                    progress = if (snap.durationMs > 0) {
                                        snap.progressMs.toDouble() / snap.durationMs
                                    } else {
                                        0.0
                                    },
                                    isSharing = snap.isPlaying,
                                )
                            },
                            onBack = { navController.popBackStack() },
                            onUpdateNowPlaying = {
                                scope.launch {
                                    runCatching {
                                        nowPlayingSvc.readCurrentPlayback()
                                        nowPlayingSvc.syncNowPlayingToHub(sharingEnabled = true, force = true)
                                    }.onFailure {
                                        toast = it.message ?: "Nothing playing right now."
                                    }
                                }
                            },
                        )
                    }
                    composable(NavRoutes.composePost) {
                        PostComposerView(
                            country = homeCountry(),
                            profile = state.profile,
                            canPostHere = !state.profile?.countryCode.isNullOrBlank(),
                            onCancel = { navController.popBackStack() },
                            onPublish = { title, body, visibility, imageUri ->
                                vm.publishPost(title, body, visibility, imageUri)
                            },
                            onPosted = {
                                navController.popBackStack()
                                toast = "Published"
                                vm.refreshFeed()
                            },
                        )
                    }
                    composable(NavRoutes.composeSpark) {
                        ReelComposerView(
                            country = homeCountry(),
                            publishAsReel = true,
                            canPostHere = !state.profile?.countryCode.isNullOrBlank(),
                            onCancel = { navController.popBackStack() },
                            onPublish = { caption, _, videoUri, onPhase, onProgress ->
                                vm.publishSpark(caption, videoUri, onPhase, onProgress)
                            },
                            onPosted = {
                                navController.popBackStack()
                                toast = "Spark published"
                                vm.refreshFeed()
                            },
                        )
                    }
                    composable(NavRoutes.composeHubVideo) {
                        ReelComposerView(
                            country = homeCountry(),
                            publishAsReel = false,
                            publishToHubChannel = true,
                            canPostHere = !state.profile?.countryCode.isNullOrBlank(),
                            onCancel = { navController.popBackStack() },
                            onPublish = { caption, videoTitle, videoUri, onPhase, onProgress ->
                                vm.publishHubVideo(caption, videoTitle, videoUri, onPhase, onProgress)
                            },
                            onPosted = {
                                navController.popBackStack()
                                toast = "Video published"
                                vm.refreshFeed()
                            },
                        )
                    }
                    composable(NavRoutes.composeStory) {
                        StoryComposerView(
                            country = homeCountry(),
                            canPostHere = !state.profile?.countryCode.isNullOrBlank(),
                            onCancel = { navController.popBackStack() },
                            onPublish = { caption, mediaUri, isVideo, onPhase, onProgress ->
                                vm.publishStory(caption, mediaUri, isVideo, onPhase, onProgress)
                            },
                            onPosted = {
                                navController.popBackStack()
                                toast = "Moment shared"
                            },
                        )
                    }
                    composable(
                        NavRoutes.post,
                        arguments = listOf(navArgument("postId") { type = NavType.StringType }),
                    ) { entry ->
                        val id = entry.arguments?.getString("postId").orEmpty()
                        val cached = state.feedPosts.firstOrNull { it.id == id }
                        PostDetailView(
                            postId = id,
                            initialPost = cached,
                            onLike = vm::toggleLike,
                            onUpdated = vm::applyPostUpdate,
                            onOpenHubs = { navigate(NavRoutes.hubsWatch(it.id)) },
                            onOpenSpark = {
                                navigate(NavRoutes.reels(it.countryCode ?: "XX"))
                            },
                        )
                    }
                    composable(
                        NavRoutes.hubsWatch,
                        arguments = listOf(navArgument("postId") { type = NavType.StringType }),
                    ) { entry ->
                        val id = entry.arguments?.getString("postId").orEmpty()
                        val post = state.feedPosts.firstOrNull { it.id == id }
                            ?: state.hubStrip.firstOrNull { it.id == id }
                        if (post != null) {
                            YouTubeWatchView(
                                post = post,
                                related = state.hubStrip.filter { it.id != post.id },
                                onBack = { navController.popBackStack() },
                                onOpenVideo = { navigate(NavRoutes.hubsWatch(it.id)) },
                                onLike = vm::toggleLike,
                            )
                        }
                    }
                    composable(
                        NavRoutes.profile,
                        arguments = listOf(navArgument("username") { type = NavType.StringType }),
                    ) { entry ->
                        val username = entry.arguments?.getString("username").orEmpty()
                        var profile by remember(username) { mutableStateOf<Profile?>(null) }
                        var posts by remember(username) { mutableStateOf<List<CountryPost>>(emptyList()) }
                        var loading by remember(username) { mutableStateOf(true) }
                        var hasHubsChannel by remember(username) { mutableStateOf(false) }
                        val blockService = remember { BlockService.get(context) }
                        LaunchedEffect(username) {
                            loading = true
                            profile = runCatching { vm.loadProfileByUsername(username) }.getOrNull()
                            profile?.userId?.let { uid ->
                                posts = runCatching { vm.loadPostsForAuthor(uid) }.getOrDefault(emptyList())
                            }
                            hasHubsChannel = profile?.let { p ->
                                runCatching { vm.resolveHasHubsChannel(p, posts) }.getOrDefault(false)
                            } == true
                            loading = false
                        }
                        PublicProfileView(
                            profile = profile,
                            posts = posts,
                            loading = loading,
                            isOwner = profile?.userId == state.profile?.userId,
                            isFollowing = profile?.userId?.let { vm.appState.isFollowing(it) } == true,
                            hasHubsChannel = hasHubsChannel,
                            currentUserId = state.profile?.userId,
                            isBlocked = profile?.userId?.let { blockService.isBlocked(it) } == true,
                            onFollowToggle = { profile?.userId?.let(vm::toggleFollow) },
                            onMessage = {
                                val uid = profile?.userId ?: return@PublicProfileView
                                scope.launch {
                                    runCatching { messagesService.startConversation(uid) }
                                        .onSuccess { navigate(NavRoutes.chat(it.id)) }
                                        .onFailure { toast = it.message ?: "Could not start chat" }
                                }
                            },
                            onEditProfile = { navigate(NavRoutes.editProfile) },
                            onSettings = { navigate(NavRoutes.settings) },
                            onOpenHubs = {
                                val uname = profile?.username
                                if (!uname.isNullOrBlank()) {
                                    vm.appState.openPlayChannel(username = uname)
                                }
                                navController.popBackStack(NavRoutes.tabs, inclusive = false)
                                vm.selectTab(AppTab.Hubs)
                            },
                            onBlock = {
                                profile?.let { p ->
                                    vm.appState.blockUser(p.userId, p.username, p.displayName)
                                }
                            },
                            onUnblock = {
                                profile?.userId?.let { vm.appState.unblockUser(it) }
                            },
                            onLike = vm::toggleLike,
                            onOpenPost = { navigate(NavRoutes.post(it.id)) },
                        )
                    }
                    composable(
                        NavRoutes.profileId,
                        arguments = listOf(navArgument("userId") { type = NavType.StringType }),
                    ) { entry ->
                        val userId = entry.arguments?.getString("userId").orEmpty()
                        var profile by remember(userId) { mutableStateOf<Profile?>(null) }
                        var posts by remember(userId) { mutableStateOf<List<CountryPost>>(emptyList()) }
                        var loading by remember(userId) { mutableStateOf(true) }
                        var hasHubsChannel by remember(userId) { mutableStateOf(false) }
                        val blockService = remember { BlockService.get(context) }
                        LaunchedEffect(userId) {
                            loading = true
                            profile = runCatching { vm.loadProfileById(userId) }.getOrNull()
                            posts = runCatching { vm.loadPostsForAuthor(userId) }.getOrDefault(emptyList())
                            hasHubsChannel = profile?.let { p ->
                                runCatching { vm.resolveHasHubsChannel(p, posts) }.getOrDefault(false)
                            } == true
                            loading = false
                        }
                        PublicProfileView(
                            profile = profile,
                            posts = posts,
                            loading = loading,
                            isOwner = userId == state.profile?.userId,
                            isFollowing = vm.appState.isFollowing(userId),
                            hasHubsChannel = hasHubsChannel,
                            currentUserId = state.profile?.userId,
                            isBlocked = blockService.isBlocked(userId),
                            onFollowToggle = { vm.toggleFollow(userId) },
                            onMessage = {
                                scope.launch {
                                    runCatching { messagesService.startConversation(userId) }
                                        .onSuccess { navigate(NavRoutes.chat(it.id)) }
                                        .onFailure { toast = it.message ?: "Could not start chat" }
                                }
                            },
                            onEditProfile = { navigate(NavRoutes.editProfile) },
                            onSettings = { navigate(NavRoutes.settings) },
                            onOpenHubs = {
                                val uname = profile?.username
                                if (!uname.isNullOrBlank()) {
                                    vm.appState.openPlayChannel(username = uname)
                                }
                                navController.popBackStack(NavRoutes.tabs, inclusive = false)
                                vm.selectTab(AppTab.Hubs)
                            },
                            onBlock = {
                                profile?.let { p ->
                                    vm.appState.blockUser(p.userId, p.username, p.displayName)
                                }
                            },
                            onUnblock = { vm.appState.unblockUser(userId) },
                            onLike = vm::toggleLike,
                            onOpenPost = { navigate(NavRoutes.post(it.id)) },
                        )
                    }
                    composable(
                        NavRoutes.reels,
                        arguments = listOf(navArgument("iso") { type = NavType.StringType }),
                    ) {
                        ReelsView(
                            posts = state.sparkStrip.ifEmpty {
                                state.feedPosts.filter { it.isSpark || it.hasVideo }
                            },
                            onBack = { navController.popBackStack() },
                            onLike = vm::toggleLike,
                            onSave = { vm.toggleSave(it) },
                            currentUserId = state.profile?.userId,
                            currentProfile = state.profile,
                            isFollowing = { uid -> vm.appState.isFollowing(uid) },
                            onToggleFollow = { uid -> vm.toggleFollow(uid) },
                            onOpenProfile = { post ->
                                val username = post.author?.username
                                if (!username.isNullOrBlank()) navigate(NavRoutes.profile(username))
                                else if (post.authorId.isNotBlank()) navigate(NavRoutes.profileId(post.authorId))
                            },
                            onOpenPost = { navigate(NavRoutes.post(it.id)) },
                        )
                    }
                    composable(
                        NavRoutes.country,
                        arguments = listOf(navArgument("iso") { type = NavType.StringType }),
                    ) { entry ->
                        val iso = entry.arguments?.getString("iso").orEmpty().uppercase()
                        var countryName by remember(iso) { mutableStateOf(iso) }
                        var selectedTab by remember(iso) { mutableStateOf(CountryTab.POSTS) }
                        var posts by remember(iso) { mutableStateOf<List<CountryPost>>(emptyList()) }
                        var followingPosts by remember(iso) { mutableStateOf<List<CountryPost>>(emptyList()) }
                        var newsItems by remember(iso) { mutableStateOf<List<ExternalNewsItem>>(emptyList()) }
                        var isLoading by remember(iso) { mutableStateOf(true) }
                        var loadError by remember(iso) { mutableStateOf<String?>(null) }
                        var newsError by remember(iso) { mutableStateOf<String?>(null) }
                        var countryStatsUsers by remember(iso) { mutableStateOf<Int?>(null) }
                        var countryStatsOnline by remember(iso) { mutableStateOf<Int?>(null) }
                        var globalStatsUsers by remember(iso) { mutableStateOf<Int?>(null) }
                        var globalStatsOnline by remember(iso) { mutableStateOf<Int?>(null) }

                        LaunchedEffect(iso) {
                            // Resolve country display name from network catalog.
                            runCatching {
                                com.matterya.matterya.data.posts.ProfileService().countries()
                            }.getOrNull()
                                ?.firstOrNull { it.iso.equals(iso, ignoreCase = true) }
                                ?.let { countryName = it.name }
                        }

                        LaunchedEffect(iso, selectedTab) {
                            isLoading = true
                            loadError = null
                            when (selectedTab) {
                                CountryTab.POSTS, CountryTab.MEDIA -> {
                                    runCatching { vm.loadCountryFeedPosts(iso) }
                                        .onSuccess { posts = it }
                                        .onFailure {
                                            posts = emptyList()
                                            loadError = it.message
                                        }
                                }
                                CountryTab.FOLLOWING -> {
                                    runCatching { vm.loadFollowingFeedPosts() }
                                        .onSuccess { followingPosts = it }
                                        .onFailure {
                                            followingPosts = emptyList()
                                            loadError = it.message
                                        }
                                }
                                CountryTab.NEWS -> {
                                    newsError = null
                                    runCatching { vm.loadCountryNews(iso) }
                                        .onSuccess { newsItems = it }
                                        .onFailure {
                                            newsItems = emptyList()
                                            newsError = it.message
                                        }
                                }
                                CountryTab.STATS -> {
                                    runCatching { vm.loadCountryStats(iso) }
                                        .onSuccess {
                                            countryStatsUsers = it.totalUsers
                                            countryStatsOnline = it.onlineUsers
                                        }
                                    runCatching { vm.loadGlobalStats() }
                                        .onSuccess {
                                            globalStatsUsers = it.totalUsers
                                            globalStatsOnline = it.onlineUsers
                                        }
                                }
                            }
                            isLoading = false
                        }

                        val feedSnap by vm.appState.snapshot.collectAsState()
                        CountryFeedView(
                            countryName = countryName,
                            countryIso = iso,
                            posts = posts,
                            followingPosts = followingPosts,
                            newsItems = newsItems,
                            isLoading = isLoading,
                            loadError = loadError,
                            newsError = newsError,
                            selectedTab = selectedTab,
                            onTabChange = { selectedTab = it },
                            onLike = vm::toggleLike,
                            onOpenPost = { navigate(NavRoutes.post(it.id)) },
                            onOpenSparks = { navigate(NavRoutes.reels(iso)) },
                            onCompose = { navigate(NavRoutes.composePost) },
                            onGoHomeToCompose = {
                                // Reliable go-home: resolve home → selectCountry → NavHost country
                                // route with openComposer flag (AppState.navigate(CountryFeed) is a
                                // no-op by design — same as iOS "country feeds on main feed").
                                scope.launch {
                                    val home = vm.appState.resolveHomeCountry()
                                    if (home == null) {
                                        toast = "Set your home country in profile before posting."
                                        vm.appState.showToast(
                                            "Set your home country in profile before posting.",
                                            ToastStyle.Error,
                                        )
                                        return@launch
                                    }
                                    vm.appState.selectCountry(home)
                                    vm.appState.requestOpenComposerOnCountryFeed()
                                    val homeIso = home.iso.uppercase()
                                    if (homeIso.equals(iso, ignoreCase = true)) {
                                        // Already on home country feed — composer request consumed by
                                        // CountryFeedView LaunchedEffect(openComposerRequested).
                                        return@launch
                                    }
                                    navController.navigate(NavRoutes.country(homeIso)) {
                                        launchSingleTop = true
                                        // Drop stacked foreign country feeds so back lands on tabs.
                                        popUpTo(NavRoutes.tabs) { inclusive = false }
                                        restoreState = false
                                    }
                                }
                            },
                            canPost = state.profile?.countryCode.equals(iso, ignoreCase = true),
                            homeCountryLabel = state.profile?.countryName ?: "your country",
                            profileAvatarUrl = state.profile?.avatarUrl,
                            profileSeed = state.profile?.userId ?: "me",
                            profile = state.profile,
                            openComposerRequested = feedSnap.openComposerOnCountryFeed &&
                                state.profile?.countryCode.equals(iso, ignoreCase = true),
                            onComposerRequestConsumed = {
                                vm.appState.clearOpenComposerOnCountryFeed()
                            },
                            onPublishPost = { title, body, visibility, imageUri ->
                                vm.publishPost(title, body, visibility, imageUri)
                            },
                            onPostPublished = {
                                posts = listOf(it) + posts.filter { p -> p.id != it.id }
                                toast = "Published"
                                vm.refreshFeed()
                            },
                            countryStatsUsers = countryStatsUsers,
                            countryStatsOnline = countryStatsOnline,
                            globalStatsUsers = globalStatsUsers,
                            globalStatsOnline = globalStatsOnline,
                            onOpenNews = { navigate(NavRoutes.news(it.id)) },
                        )
                    }
                    composable(
                        NavRoutes.news,
                        arguments = listOf(navArgument("newsId") { type = NavType.StringType }),
                    ) { entry ->
                        val id = entry.arguments?.getString("newsId").orEmpty()
                        NewsDetailView(newsId = id)
                    }
                    composable(
                        NavRoutes.chat,
                        arguments = listOf(
                            navArgument("conversationId") { type = NavType.StringType },
                        ),
                    ) { entry ->
                        val conversationId = entry.arguments?.getString("conversationId").orEmpty()
                        val me = state.profile?.userId
                            ?: AuthService.instance.currentUser?.id
                        var messages by remember(conversationId) { mutableStateOf<List<Message>>(emptyList()) }
                        var draft by remember(conversationId) { mutableStateOf("") }
                        var loading by remember(conversationId) { mutableStateOf(true) }
                        val seed = messagesService.cachedConversation(conversationId)

                        LaunchedEffect(conversationId) {
                            loading = true
                            messages = messagesService.cachedMessages(conversationId).orEmpty()
                            runCatching { messagesService.listMessages(conversationId) }
                                .onSuccess { messages = it }
                            loading = false
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
                                    }.onFailure {
                                        toast = it.message ?: "Send failed"
                                    }
                                }
                            },
                            onRefresh = {
                                messagesService.getConversationById(conversationId)
                                    ?: messagesService.listConversations()
                                        .firstOrNull { it.id == conversationId }
                            },
                            appState = vm.appState,
                            messagesService = messagesService,
                        )
                    }
                }
            }

            if (onTabsRoot) {
                BottomTabBar(
                    selected = state.selectedTab,
                    profile = state.profile,
                    messagesUnread = state.messagesUnreadCount,
                    onSelect = { tab ->
                        vm.selectTab(tab)
                        navController.popBackStack(NavRoutes.tabs, inclusive = false)
                    },
                    onCreate = { showCreateMenu = true },
                )
            }
        }

        // Story viewer overlay from AppState
        val appSnap by vm.appState.snapshot.collectAsState()
        val storyCtx = appSnap.storyViewerContext
        if (storyCtx != null) {
            StoriesViewerView(
                context = storyCtx,
                currentUserId = state.profile?.userId,
                onDismiss = {
                    vm.appState.setStoryViewerContext(null)
                },
                onMarkViewed = { id -> vm.appState.markStoryViewed(id) },
                onDeleteMoment = { post ->
                    runCatching {
                        com.matterya.matterya.data.posts.PostsService().deletePost(post.id)
                    }
                    vm.appState.refreshStories()
                },
            )
        }

        // Global Sparks viewer — iOS ReelsScrollViewer (endless queue owner).
        val reelsCtx = appSnap.reelsViewerContext
        if (reelsCtx != null) {
            SparksScrollViewer(
                startingPost = reelsCtx.startingPost,
                seedPosts = reelsCtx.seedPosts,
                currentUserId = state.profile?.userId,
                currentProfile = state.profile,
                feedVideosMuted = appSnap.feedVideosMuted,
                onFeedVideosMutedChange = { vm.appState.setFeedVideosMuted(it) },
                isFollowing = { id -> vm.appState.isFollowing(id) },
                isPostSaved = { id -> vm.appState.isPostSaved(id) },
                onBack = { vm.appState.setReelsViewerContext(null) },
                onLike = vm::toggleLike,
                onSave = { vm.toggleSave(it) },
                onShare = { vm.appState.presentShareSheet(it) },
                onOpenProfile = { post ->
                    vm.appState.openPublicProfile(
                        username = post.author?.username,
                        userId = post.authorId,
                    )
                },
                onOpenPost = { post ->
                    vm.appState.setReelsViewerContext(null)
                    navigate(NavRoutes.post(post.id))
                },
                onToggleFollow = { userId -> vm.toggleFollow(userId) },
            )
        }

        // Notifications panel (iOS NotificationsOverlay from MatteryaTopBar)
        NotificationsOverlay(
            visible = appSnap.globePanel == GlobePanel.NOTIFICATIONS,
            notifications = appSnap.notifications,
            socialUnread = appSnap.effectiveNotificationsUnreadCount,
            messagesUnread = appSnap.messagesUnreadCount,
            onDismiss = { vm.appState.setGlobePanel(null) },
            onMarkAllRead = {
                scope.launch { vm.appState.markAllNotificationsRead() }
            },
            onOpen = { n ->
                scope.launch { vm.appState.openNotification(n) }
            },
            onRefresh = {
                scope.launch { vm.appState.refreshNotifications() }
            },
        )

        // Presence panel (iOS PresencePanelView)
        PresenceOverlay(
            visible = appSnap.globePanel == GlobePanel.PRESENCE,
            countryName = appSnap.currentProfile?.countryName,
            countryCode = appSnap.currentProfile?.countryCode,
            cityName = appSnap.currentProfile?.cityName,
            globalOnline = appSnap.globalStats?.onlineUsers,
            globalTotal = appSnap.globalStats?.totalUsers,
            onDismiss = { vm.appState.setGlobePanel(null) },
        )

        // Continuous mini player bar when hubs playback is minimized (iOS MainTabView)
        val hubPost = appSnap.hubPlaybackPost
        if (
            hubPost != null &&
            !appSnap.hubPlaybackExpanded &&
            reelsCtx == null &&
            storyCtx == null
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(bottom = if (onTabsRoot) 56.dp else 0.dp),
                contentAlignment = Alignment.BottomCenter,
            ) {
                YouTubeMiniPlayerBar(
                    post = hubPost,
                    isPlaying = appSnap.hubPlaybackPlaying,
                    isMuted = appSnap.hubPlaybackMuted,
                    onExpand = { vm.appState.expandHubPlayback() },
                    onClose = { vm.appState.stopHubPlayback() },
                    onTogglePlay = {
                        vm.appState.setHubPlaybackPlaying(!appSnap.hubPlaybackPlaying)
                    },
                )
            }
        }

        AppMenuOverlay(
            visible = showAppMenu,
            profile = state.profile,
            onDismiss = { showAppMenu = false },
            onAction = { action ->
                showAppMenu = false
                when (action) {
                    AppMenuAction.Profile -> vm.appState.openProfileFromMenu()
                    AppMenuAction.Hubs -> vm.appState.openPlayFromMenu()
                    AppMenuAction.People -> {
                        vm.appState.openFromMenu(com.matterya.matterya.model.AppDestination.People)
                        navigate(NavRoutes.people)
                    }
                    AppMenuAction.Ads -> {
                        vm.appState.openFromMenu(com.matterya.matterya.model.AppDestination.Ads)
                        navigate(NavRoutes.ads)
                    }
                    AppMenuAction.Masquerade -> {
                        navigate(NavRoutes.masquerade)
                    }
                    AppMenuAction.Invite -> {
                        vm.appState.inviteFriendsFromMenu()
                        toast = "Invite friends coming soon"
                    }
                    AppMenuAction.Saved -> {
                        vm.appState.openSavedFromMenu()
                        toast = "Saved"
                    }
                    AppMenuAction.Settings -> {
                        vm.appState.openFromMenu(com.matterya.matterya.model.AppDestination.Settings)
                        navigate(NavRoutes.settings)
                    }
                    AppMenuAction.Logout -> vm.logout()
                }
            },
        )

        CreateMenuSheet(
            visible = showCreateMenu,
            onDismiss = { showCreateMenu = false },
            onAction = { action ->
                showCreateMenu = false
                when (action) {
                    CreateMenuAction.Post -> navigate(NavRoutes.composePost)
                    CreateMenuAction.HubsVideo -> navigate(NavRoutes.composeHubVideo)
                    CreateMenuAction.Spark -> navigate(NavRoutes.composeSpark)
                }
            },
        )

        toast?.let { msg ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(top = 48.dp),
                contentAlignment = Alignment.TopCenter,
            ) {
                ToastBanner(message = msg, style = ToastStyle.Info)
            }
        }
    }
}

@Composable
private fun TabContent(
    state: AppUiState,
    vm: AppViewModel,
    conversations: List<ConversationItem>,
    messagesLoading: Boolean,
    messagesError: String?,
    onLoadMessages: () -> Unit,
    onArchiveConversation: (ConversationItem) -> Unit = {},
    onDeleteConversation: (ConversationItem) -> Unit = {},
    onMenu: () -> Unit,
    onSearch: () -> Unit,
    onNotifications: () -> Unit = {},
    onPeople: () -> Unit,
    onSettings: () -> Unit,
    onEditProfile: () -> Unit,
    onOpenPost: (String) -> Unit,
    onOpenReels: (CountryPost) -> Unit,
    onOpenCountry: (String) -> Unit,
    onOpenChat: (String) -> Unit,
    onOpenHubsWatch: (CountryPost) -> Unit,
    onOpenAuthor: (CountryPost) -> Unit = {},
) {
    val appSnap by vm.appState.snapshot.collectAsState()
    // iOS keeps Feed + Hubs mounted so strips/players survive tab switches.
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier.then(
                if (state.selectedTab == AppTab.Feed) Modifier.fillMaxSize()
                else Modifier.size(0.dp),
            ),
        ) {
            FeedView(
                posts = state.feedPosts,
                sparks = state.sparkStrip,
                hubs = state.hubStrip,
                continueWatching = state.continueWatching,
                loading = state.feedLoading,
                profile = state.profile,
                pendingUploads = state.pendingUploads,
                storyGroups = appSnap.storyGroups,
                followingIds = appSnap.followingIds,
                isPostSaved = { id -> vm.appState.isPostSaved(id) },
                sessionReady = state.sessionReady,
                authenticated = state.authenticated,
                onRefresh = vm::refreshFeed,
                onLike = vm::toggleLike,
                onPostUpdated = vm::applyPostUpdate,
                onMenu = onMenu,
                onSearch = onSearch,
                onNotifications = onNotifications,
                onOpenPost = { onOpenPost(it.id) },
                onOpenReel = onOpenReels,
                onOpenVideo = onOpenHubsWatch,
                onOpenHubs = { vm.selectTab(AppTab.Hubs) },
                onOpenAuthor = onOpenAuthor,
                onToggleFollow = { userId -> vm.toggleFollow(userId) },
                onSave = { post -> vm.toggleSave(post) },
                onShare = { vm.appState.presentShareSheet(it) },
                onYourStory = { vm.appState.openStoryComposerOrViewer() },
                onOpenStoryGroup = { vm.appState.openStoryViewer(it) },
                onRefreshStories = { vm.appState.refreshStories() },
                onRowAppear = vm::onFeedRowAppear,
                notificationsUnread = state.notificationsUnreadCount,
                feedVideosMuted = appSnap.feedVideosMuted,
                onFeedVideosMutedChange = { vm.appState.setFeedVideosMuted(it) },
                reelsOpen = appSnap.reelsViewerContext != null,
                hubPlaying = appSnap.hubPlaybackPost != null,
            )
        }

        if (state.selectedTab == AppTab.Globe) {
            GlobeView(
                onMenu = onMenu,
                onSearch = onSearch,
                notificationsUnread = state.notificationsUnreadCount,
                allowsCountrySelection = true,
                onSelectCountry = { onOpenCountry(it.iso) },
                onNotifications = onNotifications,
            )
        }

        Box(
            Modifier.then(
                if (state.selectedTab == AppTab.Hubs) Modifier.fillMaxSize()
                else Modifier.size(0.dp),
            ),
        ) {
            MatteryaHubsView(
                seedVideos = state.hubStrip.ifEmpty {
                    state.feedPosts.filter { it.hasVideo && !it.isSpark }
                },
                seedSparks = state.sparkStrip,
                seedContinueWatching = state.continueWatching,
                followingIds = appSnap.followingIds,
                viewerCountry = state.profile?.countryCode,
                currentUserId = state.profile?.userId,
                hubsFreshSessionToken = appSnap.hubsFreshSessionToken,
                notificationsUnread = state.notificationsUnreadCount,
                onSearch = onSearch,
                onNotifications = onNotifications,
                onOpenVideo = onOpenHubsWatch,
                onOpenSpark = onOpenReels,
                miniPlayerBottomInset = appSnap.hubPlaybackPost != null && !appSnap.hubPlaybackExpanded,
            )
        }

        if (state.selectedTab == AppTab.Messages) {
            LaunchedEffect(Unit) { onLoadMessages() }
            MessagesView(
                conversations = conversations,
                isLoading = messagesLoading,
                errorMessage = messagesError,
                onMenu = onMenu,
                onPeople = onPeople,
                onOpenConversation = { onOpenChat(it.id) },
                onArchive = onArchiveConversation,
                onDelete = onDeleteConversation,
            )
        }

        if (state.selectedTab == AppTab.Profile) {
            ProfileView(
                profile = state.profile,
                posts = state.feedPosts.filter { it.authorId == state.profile?.userId },
                savedPosts = state.savedJournalPosts,
                savedVideos = state.savedVideoPosts,
                savedSparks = state.savedReelPosts,
                followers = state.followersCount,
                following = state.followingCount,
                onMenu = onMenu,
                onSearch = onSearch,
                onEdit = onEditProfile,
                onSettings = onSettings,
                onLike = vm::toggleLike,
                onOpenPost = { onOpenPost(it.id) },
                onOpenReel = onOpenReels,
                onOpenVideo = onOpenHubsWatch,
            )
        }
    }
}

/** Back-compat alias. */
@Composable
fun MainShell(
    selectedTab: AppTab,
    profile: Profile?,
    posts: List<CountryPost>,
    sparks: List<CountryPost>,
    hubs: List<CountryPost>,
    feedLoading: Boolean,
    onSelectTab: (AppTab) -> Unit,
    onRefreshFeed: () -> Unit,
    onLike: (CountryPost) -> Unit,
    onPostUpdated: (CountryPost) -> Unit,
    onLogout: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        Box(modifier = Modifier.weight(1f)) {
            when (selectedTab) {
                AppTab.Feed -> FeedView(
                    posts = posts,
                    sparks = sparks,
                    hubs = hubs,
                    loading = feedLoading,
                    profile = profile,
                    onRefresh = onRefreshFeed,
                    onLike = onLike,
                    onPostUpdated = onPostUpdated,
                )
                AppTab.Globe -> GlobeView()
                AppTab.Hubs -> MatteryaHubsView(seedVideos = hubs, seedSparks = sparks)
                AppTab.Messages -> MessagesView()
                AppTab.Profile -> ProfileView(profile = profile)
            }
        }
        BottomTabBar(
            selected = selectedTab,
            profile = profile,
            onSelect = onSelectTab,
            onCreate = {},
        )
    }
}
