package com.matterya.matterya.data.push

import android.content.Context
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.calls.CallSessionManager
import com.matterya.matterya.data.calls.IncomingCallWake
import com.matterya.matterya.data.calls.TelecomCallManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

data class IncomingCallPushPayload(
    val conversationId: String,
    val from: String,
    val callType: String,
    val callId: String?,
    val roomName: String?,
    val displayName: String,
)

/**
 * iOS `VoIPPushService.swift` → Android FCM high-priority channel surface.
 *
 * PushKit VoIP is iOS-only. On Android:
 * - FCM data messages with high priority + full-screen intent channel
 * - [onHighPriorityCallMessage] is the entry point from FirebaseMessagingService
 * - Same parse / CallSessionManager wiring as iOS VoIP
 */
class VoIPPushService private constructor(
    private val appContext: Context?,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @Volatile
    var lastStatusMessage: String? = null
        private set

    @Volatile
    var isRegistryActive: Boolean = false
        private set

    val isSupportedOnThisDevice: Boolean = true

    private val unsupportedDeviceMessage =
        "High-priority FCM call channel requires Google Play Services."

    fun bootstrap() {
        isRegistryActive = true
        lastStatusMessage = null
    }

    fun refreshRegistry() {
        isRegistryActive = true
    }

    fun teardown() {
        isRegistryActive = false
    }

    suspend fun ensureToken(maxAttempts: Int = 15) {
        bootstrap()
        if (PushNotificationService.shared.hasHighPriorityCallToken) {
            lastStatusMessage = null
            return
        }
        PushNotificationService.shared.requestFcmTokenRefresh()
        repeat(maxAttempts) { attempt ->
            delay(2_000)
            if (PushNotificationService.shared.hasHighPriorityCallToken) {
                lastStatusMessage = null
                return
            }
            if (attempt == 3 || attempt == 8 || attempt == 13) {
                refreshRegistry()
                PushNotificationService.shared.requestFcmTokenRefresh()
            }
        }
        if (!PushNotificationService.shared.hasHighPriorityCallToken) {
            lastStatusMessage =
                "Waiting for FCM high-priority call token. Ensure Firebase is configured and Google Play Services is available."
        }
    }

    /**
     * Entry from FirebaseMessagingService when a high-priority data message
     * carries an incoming call payload.
     */
    fun onHighPriorityCallMessage(data: Map<String, String>, finish: () -> Unit = {}) {
        val anyMap: Map<String, Any?> = data.mapValues { it.value }
        val callPayload = parseIncomingCallPayload(anyMap)
        if (callPayload == null) {
            finish()
            return
        }
        scope.launch {
            handleIncomingVoIPPush(callPayload)
            finish()
        }
    }

    fun handleIncomingVoIPPush(callPayload: IncomingCallPushPayload) {
        val me = AuthService.instance.currentUser?.id
        if (me != null && callPayload.from == me) return

        CallSessionManager.shared.bootstrapForIncomingCall()
        val useTelecom = CallSessionManager.shouldUseTelecomForIncomingRing
        if (useTelecom) {
            TelecomCallManager.shared.reportIncomingCall(
                conversationId = callPayload.conversationId,
                callerName = callPayload.displayName,
                hasVideo = callPayload.callType == "video",
            ) { }
        }

        val staged = CallSessionManager.shared.stageIncomingCall(
            conversationId = callPayload.conversationId,
            fromUserId = callPayload.from,
            callType = callPayload.callType,
            callId = callPayload.callId,
            roomName = callPayload.roomName,
            callerName = callPayload.displayName,
        )
        if (staged) {
            scope.launch {
                CallSessionManager.shared.finalizeIncomingCallPresentation(
                    conversationId = callPayload.conversationId,
                    fromUserId = callPayload.from,
                    reportToTelecom = false,
                )
                if (!useTelecom) {
                    CallSessionManager.shared.presentInAppIncomingUI()
                }
            }
        } else if (useTelecom) {
            TelecomCallManager.shared.requestEndCall(callPayload.conversationId)
        }
    }

    companion object {
        @Volatile private var instance: VoIPPushService? = null

        val shared: VoIPPushService
            get() = instance ?: VoIPPushService(null).also { instance = it }

        fun init(context: Context): VoIPPushService {
            return instance ?: synchronized(this) {
                instance ?: VoIPPushService(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): VoIPPushService = init(context)

        fun parseIncomingCallPayload(dictionary: Map<String, Any?>): IncomingCallPushPayload? {
            val payload = IncomingCallWake.parse(dictionary) ?: return null
            return IncomingCallPushPayload(
                conversationId = payload.conversationId,
                from = payload.from,
                callType = payload.callType,
                callId = payload.callId,
                roomName = payload.roomName,
                displayName = payload.displayName,
            )
        }
    }
}
