package com.matterya.matterya.data.calls

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.messages.MessagesService
import com.matterya.matterya.data.push.VoIPPushService
import com.matterya.matterya.data.system.NotificationNames
import com.matterya.matterya.model.Message
import com.matterya.matterya.model.PostAuthor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.Date
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

enum class CallKind(val rawValue: String) {
    Audio("audio"),
    Video("video"),
}

enum class OutgoingCallPhase {
    Calling,
    Ringing,
    TryingToReach,
}

/**
 * iOS `CallSessionManager.swift`.
 *
 * Full signaling + UI state machine. LiveKit media room is prepared via
 * `/livekit/token`; actual WebRTC attach lands when the LiveKit Android SDK
 * is added. Until then, connectRoom stores credentials and marks active on
 * peer accept / remote participant presence signals.
 */
class CallSessionManager private constructor(
    private val auth: AuthService = AuthService.instance,
    private val messages: MessagesService = MessagesService(),
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val http = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build()

    var showUI = false
    var isMinimized = false
    var isIncoming = false
    var isConnecting = false
    var isActive = false
    var isMuted = false
        private set
    var isCameraOff = false
    var errorMessage: String? = null
    var timerSeconds = 0

    var callKind: CallKind? = null
    var conversationId: String? = null
    var peerName = "Member"
    var peerAvatarUrl: String? = null
    var outgoingPhase: OutgoingCallPhase = OutgoingCallPhase.Calling

    private val _isSignalingConnected = MutableStateFlow(false)
    val isSignalingConnected: StateFlow<Boolean> = _isSignalingConnected.asStateFlow()

    private var sessionId: String? = null
    private var roomName: String? = null
    private var fromUserId: String? = null
    private var peerUserId: String? = null
    private var incomingOffer: CallSignal? = null
    private var callStartAt: Date? = null
    private var callLogSent = false
    private var timerJob: Job? = null
    private var incomingTimeoutJob: Job? = null
    private var outgoingTimeoutJob: Job? = null
    private var sentCallAccept = false
    private var incomingPresentedViaTelecom = false
    private val endedFlag = AtomicBoolean(false)
    val hasEndedCurrentCall: Boolean get() = endedFlag.get()

    private var liveKitUrl: String? = null
    private var liveKitToken: String? = null
    private var roomConnected = false

    init {
        CallSignalingService.shared.onSignal = { signal ->
            scope.launch { handle(signal) }
        }
        CallSignalingService.shared.onConnectionChange = { connected ->
            _isSignalingConnected.value = connected
        }
        _isSignalingConnected.value = CallSignalingService.shared.isConnected.value
    }

    fun bootstrap() = bootstrapForIncomingCall()

    fun bootstrapForIncomingCall() {
        VoIPPushService.shared.bootstrap()
        CallSignalingService.shared.connect()
        _isSignalingConnected.value = CallSignalingService.shared.isConnected.value
    }

    suspend fun ensureSignalingReady() {
        _isSignalingConnected.value = CallSignalingService.shared.ensureConnected()
    }

    fun teardown() {
        cleanup(notifyRemote = isActive || isConnecting)
    }

    val canStartCall: Boolean
        get() = !isActive && !isConnecting && !isIncoming && _isSignalingConnected.value

    val showFullCallUI: Boolean get() = showUI && !isMinimized
    val showCompactCallBar: Boolean get() = isMinimized && (isActive || isConnecting)

    fun minimizeCall() {
        if (!(isActive || isConnecting)) return
        isMinimized = true
    }

    fun expandCall() {
        isMinimized = false
        showUI = true
    }

    fun presentActiveCallUIIfNeeded() {
        if (!isAppInForeground) return
        if (!(isActive || isConnecting || (isIncoming && !incomingPresentedViaTelecom))) return
        if (isMinimized) return
        showUI = true
    }

    fun handleAppWillResignActive() = autoMinimizeCallIfNeeded()
    fun handleAppDidBecomeActive() = autoMinimizeCallIfNeeded()

    private fun autoMinimizeCallIfNeeded() {
        if (!(isActive || isConnecting)) return
        if (isIncoming) return
        showUI = true
        isMinimized = true
    }

    fun configurePeer(author: PostAuthor?) {
        peerName = author?.displayName ?: author?.username ?: "Member"
        peerAvatarUrl = author?.avatarUrl
        peerUserId = author?.userId
    }

    val titleText: String
        get() {
            val kind = if (callKind == CallKind.Video) "Video call" else "Voice call"
            return "$peerName · $kind"
        }

    val statusText: String
        get() {
            errorMessage?.let { return it }
            if (isIncoming) {
                return if (callKind == CallKind.Video) "Incoming video call" else "Incoming voice call"
            }
            if (isActive) return "In call"
            if (isOutgoingCaller) {
                return when (outgoingPhase) {
                    OutgoingCallPhase.Ringing -> "Ringing…"
                    OutgoingCallPhase.TryingToReach -> "Trying to reach…"
                    OutgoingCallPhase.Calling -> if (isConnecting) "Connecting…" else "Calling…"
                }
            }
            if (isConnecting) return "Connecting…"
            return "Calling…"
        }

    val isOutgoingCaller: Boolean
        get() {
            val me = auth.currentUser?.id ?: return false
            return fromUserId == me && !isIncoming
        }

    val subtitleText: String
        get() = when (callKind) {
            CallKind.Video -> "Video call"
            CallKind.Audio -> "Voice call"
            null -> "Call"
        }

    val timerLabel: String
        get() {
            if (callStartAt == null) return "00:00"
            return Message.formatDuration(timerSeconds)
        }

    suspend fun startCall(conversationId: String, kind: CallKind, peer: PostAuthor?) {
        val me = auth.currentUser?.id ?: return
        if (isActive || isConnecting || isIncoming) return

        _isSignalingConnected.value = CallSignalingService.shared.ensureConnected()
        if (!_isSignalingConnected.value) {
            errorMessage = "Calling is offline. Check your connection and try again."
            return
        }

        configurePeer(peer)
        this.conversationId = conversationId
        callKind = kind
        fromUserId = me
        sessionId = UUID.randomUUID().toString()
        roomName = "call_${conversationId}_$sessionId"
        isConnecting = true
        isIncoming = false
        isActive = false
        errorMessage = null
        showUI = true
        isMinimized = false
        callStartAt = null
        callLogSent = false
        outgoingPhase = OutgoingCallPhase.Calling
        endedFlag.set(false)

        try {
            TelecomCallManager.shared.reportOutgoingCall(
                conversationId = conversationId,
                callerName = peerName,
                hasVideo = kind == CallKind.Video,
            )
            TelecomCallManager.shared.reportOutgoingCallStartedConnecting(conversationId)
            prepareAudioForCall(usesTelecom = shouldUseTelecomAudio(conversationId))
            connectRoom(video = kind == CallKind.Video)
            CallSignalingService.shared.send(
                type = "call-offer",
                conversationId = conversationId,
                from = me,
                callType = kind.rawValue,
                callId = sessionId,
                roomName = roomName,
            )
            beginOutgoingFeedback()
            scheduleOutgoingCallTimeout()
        } catch (e: Exception) {
            errorMessage = e.message
            cleanup(notifyRemote = false)
        }
    }

    fun stageIncomingCall(
        conversationId: String,
        fromUserId: String,
        callType: String,
        callId: String?,
        roomName: String?,
        callerName: String? = null,
    ): Boolean {
        val me = auth.currentUser?.id
        if (me != null && fromUserId == me) return false
        if (isActive) return false
        if (isIncoming && this.conversationId == conversationId) return true
        if (isIncoming || isConnecting) return false

        val normalizedCallId = nonEmpty(callId)
        val normalizedRoom = nonEmpty(roomName)
            ?: normalizedCallId?.let { "call_${conversationId}_$it" }
            ?: "call_${conversationId}_$fromUserId"

        incomingOffer = CallSignal(
            type = "call-offer",
            conversationId = conversationId,
            from = fromUserId,
            callType = callType,
            callId = normalizedCallId,
            roomName = normalizedRoom,
            connectedAt = null,
        )
        this.conversationId = conversationId
        callKind = if (callType == "video") CallKind.Video else CallKind.Audio
        this.fromUserId = fromUserId
        sessionId = normalizedCallId
        this.roomName = normalizedRoom
        isIncoming = true
        isConnecting = false
        isActive = false
        errorMessage = null
        endedFlag.set(false)

        val appIsActive = isAppInForeground
        incomingPresentedViaTelecom = !appIsActive
        isMinimized = false
        showUI = appIsActive
        if (appIsActive) {
            CallSoundService.shared.start(CallSoundService.Pattern.IncomingRing)
        }

        nonEmpty(callerName)?.let { peerName = it }

        sendCallRinging(conversationId, fromUserId, normalizedCallId)
        scheduleIncomingCallTimeout()
        return true
    }

    fun presentInAppIncomingUI() {
        if (!isIncoming) return
        isMinimized = false
        showUI = true
        CallSoundService.shared.start(CallSoundService.Pattern.IncomingRing)
    }

    private fun sendCallRinging(conversationId: String, toUserId: String, callId: String?) {
        val me = auth.currentUser?.id
        if (me == null) {
            scope.launch {
                CallSignalingService.shared.ensureConnected()
                val id = auth.currentUser?.id ?: return@launch
                CallSignalingService.shared.send(
                    type = "call-ringing",
                    conversationId = conversationId,
                    from = id,
                    callId = callId,
                    to = toUserId,
                )
            }
            return
        }
        CallSignalingService.shared.send(
            type = "call-ringing",
            conversationId = conversationId,
            from = me,
            callId = callId,
            to = toUserId,
        )
    }

    suspend fun finalizeIncomingCallPresentation(
        conversationId: String,
        fromUserId: String,
        reportToTelecom: Boolean,
    ) {
        if (!isIncoming || this.conversationId != conversationId) return
        if (reportToTelecom) {
            incomingPresentedViaTelecom = true
            CallSoundService.shared.stop()
            TelecomCallManager.shared.reportIncomingCall(
                conversationId = conversationId,
                callerName = peerName,
                hasVideo = callKind == CallKind.Video,
            )
        }
        resolvePeer(fromUserId, conversationId)
    }

    suspend fun prepareIncomingCall(
        conversationId: String,
        fromUserId: String,
        callType: String,
        callId: String?,
        roomName: String?,
        callerName: String? = null,
        reportToTelecom: Boolean = true,
    ) {
        if (!stageIncomingCall(conversationId, fromUserId, callType, callId, roomName, callerName)) return
        finalizeIncomingCallPresentation(conversationId, fromUserId, reportToTelecom)
    }

    suspend fun acceptCall(): Boolean {
        if (isConnecting || isActive) return isActive || isConnecting
        if (!isIncoming) return false

        incomingTimeoutJob?.cancel()
        incomingTimeoutJob = null
        sentCallAccept = false
        bootstrapForIncomingCall()
        _isSignalingConnected.value = CallSignalingService.shared.ensureConnected(15.0)

        val offer = incomingOffer ?: pendingIncomingSignal()
        val me = auth.currentUser?.id
        if (offer == null || me == null) {
            errorMessage = "Could not join call."
            cleanup(notifyRemote = false)
            return false
        }

        CallSoundService.shared.stop()
        conversationId = offer.conversationId
        callKind = if (offer.callType == "video") CallKind.Video else CallKind.Audio
        fromUserId = offer.from
        sessionId = offer.callId
        roomName = resolvedRoomName(offer)
        isIncoming = false
        isConnecting = true
        showUI = true
        isMinimized = false
        errorMessage = null
        endedFlag.set(false)

        return try {
            val usesTelecom = shouldUseTelecomAudio(offer.conversationId)
            prepareAudioForCall(usesTelecom)
            connectRoom(video = callKind == CallKind.Video)
            incomingOffer = null
            sentCallAccept = true
            val connectedAt = System.currentTimeMillis() / 1000.0
            applySynchronizedCallStart(connectedAt)
            CallSignalingService.shared.send(
                type = "call-accept",
                conversationId = offer.conversationId,
                from = me,
                callType = callKind?.rawValue,
                callId = sessionId,
                roomName = roomName,
                to = offer.from,
                connectedAt = connectedAt,
            )
            // Without LiveKit peer presence, accept marks active so UI advances.
            markActive()
            isMinimized = false
            showUI = true
            presentActiveCallUIIfNeeded()
            isActive || isConnecting
        } catch (e: Exception) {
            errorMessage = e.message
            incomingOffer = offer
            cleanup(notifyRemote = false, endTelecom = true)
            false
        }
    }

    fun declineCall(fromTelecom: Boolean = false) {
        if (conversationId == null) return
        CallSoundService.shared.stop()
        val conv = conversationId
        val me = auth.currentUser?.id
        if (conv != null && me != null) {
            CallSignalingService.shared.send(
                type = "call-decline",
                conversationId = conv,
                from = me,
                callId = sessionId,
            )
        }
        scope.launch {
            sendCallLog(status = "missed")
            cleanup(notifyRemote = false, endTelecom = !fromTelecom)
        }
    }

    fun endCall(fromTelecom: Boolean = false) {
        if (endedFlag.get()) return
        val status = if (isActive || callStartAt != null) "ended" else "missed"
        scope.launch {
            sendCallLog(status = status)
            cleanup(notifyRemote = true, endTelecom = !fromTelecom)
        }
    }

    fun toggleMute() {
        isMuted = !isMuted
    }

    fun applyMute(muted: Boolean) {
        isMuted = muted
    }

    fun toggleCamera() {
        isCameraOff = !isCameraOff
    }

    private suspend fun resolvePeer(userId: String, conversationId: String) {
        val conversations = runCatching { messages.listConversations(limit = 100) }.getOrNull()
        val conversation = conversations?.firstOrNull { it.id == conversationId }
        val member = conversation?.members?.firstOrNull { it.userId == userId }
        if (member != null) {
            configurePeer(member)
            return
        }
        peerUserId = userId
        if (peerName == "Member") peerName = "Incoming call"
    }

    private fun pendingIncomingSignal(): CallSignal? {
        if (!isIncoming) return null
        val conv = conversationId ?: return null
        val fromUserId = fromUserId ?: return null
        return CallSignal(
            type = "call-offer",
            conversationId = conv,
            from = fromUserId,
            callType = callKind?.rawValue,
            callId = sessionId,
            roomName = roomName,
            connectedAt = null,
        )
    }

    private suspend fun handle(signal: CallSignal) {
        val me = auth.currentUser?.id ?: return
        if (signal.from == me) return

        when (signal.type) {
            "call-offer" -> {
                if (isIncoming && conversationId == signal.conversationId) return
                if (isActive || isIncoming || (isConnecting && fromUserId == me)) {
                    CallSignalingService.shared.send(
                        type = "call-busy",
                        conversationId = signal.conversationId,
                        from = me,
                        callId = signal.callId,
                    )
                    return
                }
                prepareIncomingCall(
                    conversationId = signal.conversationId,
                    fromUserId = signal.from,
                    callType = signal.callType ?: "audio",
                    callId = signal.callId,
                    roomName = signal.roomName,
                    reportToTelecom = shouldUseTelecomForIncomingRing,
                )
            }
            "call-ringing" -> {
                if (!isOutgoingCaller || conversationId != signal.conversationId) return
                outgoingPhase = OutgoingCallPhase.Ringing
                if (!isConnecting && !isActive) {
                    CallSoundService.shared.start(CallSoundService.Pattern.OutgoingRing)
                }
            }
            "call-unreachable" -> {
                if (!isOutgoingCaller || conversationId != signal.conversationId) return
                if (outgoingPhase == OutgoingCallPhase.Ringing) return
                outgoingPhase = OutgoingCallPhase.TryingToReach
                if (!isConnecting && !isActive) {
                    CallSoundService.shared.start(CallSoundService.Pattern.TryingToReach)
                }
            }
            "call-accept" -> {
                if (fromUserId != me || !matchesCurrentCall(signal)) return
                signal.roomName?.let { roomName = it }
                outgoingPhase = OutgoingCallPhase.Ringing
                signal.connectedAt?.let { applySynchronizedCallStart(it) }
                markActive()
            }
            "call-decline", "call-busy" -> {
                if (!matchesCurrentCall(signal)) return
                if (fromUserId == me) sendCallLog(status = "missed")
                cleanup(notifyRemote = false)
            }
            "call-end" -> {
                if (!matchesCurrentCall(signal)) return
                when {
                    isActive || callStartAt != null -> sendCallLog(status = "ended")
                    isIncoming || isConnecting -> sendCallLog(status = "missed")
                }
                cleanup(notifyRemote = false)
            }
        }
    }

    private fun shouldUseTelecomAudio(conversationId: String): Boolean {
        if (TelecomCallManager.shared.isAudioSessionActivated) return true
        if (TelecomCallManager.shared.hasCall(conversationId)) return true
        if (!isAppInForeground) return incomingPresentedViaTelecom
        return false
    }

    private fun matchesCurrentCall(signal: CallSignal): Boolean {
        val conv = conversationId ?: return false
        if (signal.conversationId != conv) return false
        val currentId = sessionId
        val signalId = nonEmpty(signal.callId)
        if (currentId != null && signalId != null && currentId != signalId) return false
        return true
    }

    private fun applySynchronizedCallStart(unixTime: Double) {
        val startDate = Date((unixTime * 1000).toLong())
        val existing = callStartAt
        if (existing != null) {
            callStartAt = if (existing.before(startDate)) existing else startDate
        } else {
            callStartAt = startDate
            startTimer()
        }
    }

    private fun remotePeerUserId(): String? {
        val me = auth.currentUser?.id ?: return null
        return if (fromUserId == me) peerUserId else fromUserId
    }

    private fun resolvedRoomName(offer: CallSignal): String {
        nonEmpty(offer.roomName)?.let { return it }
        nonEmpty(offer.callId)?.let { return "call_${offer.conversationId}_$it" }
        return "call_${offer.conversationId}_${offer.from}"
    }

    private suspend fun prepareAudioForCall(usesTelecom: Boolean) {
        CallSoundService.shared.stop()
        if (usesTelecom) {
            TelecomCallManager.shared.waitForAudioSessionActivation()
        }
        TelecomCallManager.shared.markAudioSessionActivated(true)
    }

    /**
     * Fetches LiveKit credentials. Full room join is deferred to LiveKit SDK integration;
     * credentials are retained for when media is attached.
     */
    private suspend fun connectRoom(video: Boolean) {
        val name = roomName ?: throw CallError.MissingRoom
        val tokenInfo = fetchLiveKitToken(roomName = name)
        if (tokenInfo.second.isEmpty()) throw CallError.LiveKitNotConfigured
        liveKitToken = tokenInfo.first
        liveKitUrl = tokenInfo.second
        isCameraOff = !video
        isMuted = false
        roomConnected = true
    }

    private suspend fun fetchLiveKitToken(roomName: String): Pair<String, String> =
        withContext(Dispatchers.IO) {
            val token = runCatching { auth.ensureValidToken() }.getOrElse {
                throw CallError.NotAuthenticated
            }
            val body = """{"room":"$roomName","name":"${auth.currentUser?.id ?: "member"}"}"""
            val req = Request.Builder()
                .url("${AppConfig.apiBaseURL}/livekit/token")
                .post(body.toRequestBody("application/json".toMediaType()))
                .header("Authorization", "Bearer $token")
                .header("Content-Type", "application/json")
                .build()
            val response = http.newCall(req).execute()
            val raw = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                val msg = runCatching {
                    json.parseToJsonElement(raw).jsonObject["error"]?.jsonPrimitive?.contentOrNull
                }.getOrNull()
                throw CallError.TokenFailed(msg ?: "LiveKit auth failed.")
            }
            val obj = json.parseToJsonElement(raw).jsonObject
            val lkToken = obj["token"]?.jsonPrimitive?.contentOrNull
                ?: throw CallError.TokenFailed("LiveKit auth failed.")
            val serverUrl = obj["url"]?.jsonPrimitive?.contentOrNull.orEmpty()
            lkToken to serverUrl
        }

    private fun markActive() {
        if (isActive) return
        CallSoundService.shared.stop()
        incomingTimeoutJob?.cancel()
        incomingTimeoutJob = null
        outgoingTimeoutJob?.cancel()
        outgoingTimeoutJob = null
        isConnecting = false
        isActive = true
        isIncoming = false
        showUI = true
        outgoingPhase = OutgoingCallPhase.Calling
        conversationId?.let { TelecomCallManager.shared.reportCallConnected(it) }
        presentActiveCallUIIfNeeded()
        if (callStartAt == null) {
            callStartAt = Date()
            startTimer()
        }
    }

    private fun beginOutgoingFeedback() {
        if (!isOutgoingCaller) return
        scope.launch {
            delay(8_000)
            if (!(isOutgoingCaller && !isActive && !isConnecting && !isIncoming && showUI)) return@launch
            if (outgoingPhase == OutgoingCallPhase.Calling) {
                outgoingPhase = OutgoingCallPhase.TryingToReach
                CallSoundService.shared.start(CallSoundService.Pattern.TryingToReach)
            }
        }
    }

    private fun scheduleIncomingCallTimeout() {
        incomingTimeoutJob?.cancel()
        incomingTimeoutJob = scope.launch {
            delay(45_000)
            missUnansweredIncomingCall()
        }
    }

    private fun scheduleOutgoingCallTimeout() {
        outgoingTimeoutJob?.cancel()
        outgoingTimeoutJob = scope.launch {
            delay(60_000)
            if (isOutgoingCaller && !isActive && (showUI || isConnecting)) {
                endCall()
            }
        }
    }

    private suspend fun missUnansweredIncomingCall() {
        if (!isIncoming || isActive || isConnecting) return
        val conv = conversationId
        val me = auth.currentUser?.id
        val peer = fromUserId
        if (conv != null && me != null && peer != null) {
            CallSignalingService.shared.send(
                type = "call-decline",
                conversationId = conv,
                from = me,
                callId = sessionId,
                to = peer,
            )
        }
        sendCallLog(status = "missed")
        cleanup(notifyRemote = false)
    }

    private fun startTimer() {
        timerJob?.cancel()
        timerJob = scope.launch {
            while (true) {
                delay(1_000)
                val start = callStartAt ?: continue
                timerSeconds = maxOf(0, ((System.currentTimeMillis() - start.time) / 1000).toInt())
            }
        }
    }

    private suspend fun sendCallLog(status: String) {
        if (callLogSent) return
        val conv = conversationId ?: return
        val kind = callKind ?: return
        val duration = callStartAt?.let {
            maxOf(0, ((System.currentTimeMillis() - it.time) / 1000).toInt())
        } ?: 0
        val body = Message.callLogBody(status, kind.rawValue, duration)
        runCatching { messages.sendMessage(conv, body) }
        callLogSent = true
    }

    suspend fun handleIncomingPushCall(
        conversationId: String,
        fromUserId: String,
        callType: String,
        callId: String?,
        roomName: String?,
        callerName: String? = null,
    ) {
        if (isIncoming && this.conversationId == conversationId) return
        prepareIncomingCall(
            conversationId = conversationId,
            fromUserId = fromUserId,
            callType = callType,
            callId = callId,
            roomName = roomName,
            callerName = callerName,
            reportToTelecom = false,
        )
    }

    private fun cleanup(notifyRemote: Boolean, endTelecom: Boolean = true) {
        if (!endedFlag.compareAndSet(false, true)) return

        incomingTimeoutJob?.cancel()
        incomingTimeoutJob = null
        outgoingTimeoutJob?.cancel()
        outgoingTimeoutJob = null
        val endedConversationId = conversationId
        val shouldNotifyRemote = notifyRemote || sentCallAccept || isActive
        CallSoundService.shared.stop()
        if (endTelecom) {
            TelecomCallManager.shared.requestEndCall(endedConversationId)
        }
        if (shouldNotifyRemote) {
            val conv = conversationId
            val me = auth.currentUser?.id
            if (conv != null && me != null) {
                scope.launch {
                    CallSignalingService.shared.ensureConnected(2.0)
                    CallSignalingService.shared.send(
                        type = "call-end",
                        conversationId = conv,
                        from = me,
                        callId = sessionId,
                        to = remotePeerUserId(),
                    )
                }
            }
        }
        sentCallAccept = false
        incomingPresentedViaTelecom = false
        timerJob?.cancel()
        timerJob = null
        roomConnected = false
        liveKitToken = null
        liveKitUrl = null

        showUI = false
        isMinimized = false
        outgoingPhase = OutgoingCallPhase.Calling
        isIncoming = false
        isConnecting = false
        isActive = false
        isMuted = false
        isCameraOff = false
        errorMessage = null
        timerSeconds = 0
        callKind = null
        conversationId = null
        fromUserId = null
        sessionId = null
        roomName = null
        incomingOffer = null
        callStartAt = null
    }

    sealed class CallError(message: String) : Exception(message) {
        data object NotAuthenticated : CallError("Not authenticated.")
        data object InvalidUrl : CallError("Invalid LiveKit URL.")
        data object MissingRoom : CallError("Missing call room.")
        data object LiveKitNotConfigured : CallError("Calling is not configured on the server.")
        class TokenFailed(msg: String) : CallError(msg)
    }

    private fun nonEmpty(value: String?): String? {
        if (value == null) return null
        val trimmed = value.trim()
        return trimmed.ifEmpty { null }
    }

    companion object {
        val shared by lazy { CallSessionManager() }

        /** Foreground → in-app overlay. Background → Telecom/system UI only. */
        val shouldUseTelecomForIncomingRing: Boolean
            get() = !isAppInForeground

        @Volatile
        var isAppInForeground: Boolean = true
    }
}
