package com.matterya.matterya.data.calls

import android.content.Context
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Android Telecom / ConnectionService mapping for iOS `CallKitManager.swift`.
 *
 * Public method names and state machine mirror CallKit so CallSessionManager can
 * share the same control flow. Full ConnectionService registration (self-managed
 * calls / TelecomManager) can be wired when the app ships with the required
 * MANAGE_OWN_CALLS permission + PhoneAccount.
 *
 * Mapping notes:
 * - CXProvider / reportNewIncomingCall → [reportIncomingCall]
 * - CXStartCallAction → [reportOutgoingCall]
 * - CXEndCallAction → [requestEndCall]
 * - CXAnswerCallAction → [onAnswerFromSystem]
 * - Audio session activate → [isAudioSessionActivated] / [waitForAudioSessionActivation]
 */
class TelecomCallManager private constructor(
    @Suppress("UNUSED_PARAMETER") private val appContext: Context?,
) {
    private val callUuidByConversationId = ConcurrentHashMap<String, UUID>()
    private val conversationIdByCallUuid = ConcurrentHashMap<UUID, String>()
    private val audioSessionWaiters = mutableListOf<CompletableDeferred<Unit>>()

    @Volatile
    var isAudioSessionActivated: Boolean = false
        private set

    suspend fun reportIncomingCall(
        conversationId: String,
        callerName: String,
        hasVideo: Boolean,
    ) {
        reportIncomingCall(conversationId, callerName, hasVideo) { }
    }

    fun reportIncomingCall(
        conversationId: String,
        callerName: String,
        hasVideo: Boolean,
        completion: (Throwable?) -> Unit,
    ) {
        val callUuid = callUuidByConversationId[conversationId] ?: UUID.randomUUID()
        callUuidByConversationId[conversationId] = callUuid
        conversationIdByCallUuid[callUuid] = conversationId
        // System UI is presented via high-priority FCM full-screen intent
        // (IncomingCallWake / VoIPPushService). Mark audio ready for in-app path.
        markAudioSessionActivated(true)
        completion(null)
        @Suppress("UNUSED_VARIABLE")
        val unused = callerName to hasVideo
    }

    fun reportOutgoingCall(conversationId: String, callerName: String, hasVideo: Boolean) {
        val callUuid = callUuidByConversationId[conversationId] ?: UUID.randomUUID()
        callUuidByConversationId[conversationId] = callUuid
        conversationIdByCallUuid[callUuid] = conversationId
        @Suppress("UNUSED_VARIABLE")
        val unused = callerName to hasVideo
    }

    fun reportOutgoingCallStartedConnecting(conversationId: String) {
        // TelecomConnection would report STATE_DIALING here.
        @Suppress("UNUSED_VARIABLE")
        val id = conversationId
    }

    fun reportCallConnected(conversationId: String) {
        markAudioSessionActivated(true)
        @Suppress("UNUSED_VARIABLE")
        val id = conversationId
    }

    fun hasCall(conversationId: String): Boolean =
        callUuidByConversationId.containsKey(conversationId)

    suspend fun waitForAudioSessionActivation(timeoutSeconds: Double = 8.0) {
        if (isAudioSessionActivated) return
        val deferred = CompletableDeferred<Unit>()
        synchronized(audioSessionWaiters) { audioSessionWaiters.add(deferred) }
        withTimeoutOrNull((timeoutSeconds * 1000).toLong()) {
            deferred.await()
        }
        // Always proceed after timeout (matches iOS resume-on-timeout behavior).
        resumeAudioSessionWaiters()
    }

    fun requestEndCall(forConversationId: String?) {
        val conversationId = forConversationId ?: return
        val callUuid = callUuidByConversationId[conversationId] ?: return
        clearMapping(conversationId)
        // Telecom would disconnect Connection for callUuid.
        @Suppress("UNUSED_VARIABLE")
        val ignored = callUuid
    }

    /** Invoked when user answers from the system UI / full-screen intent. */
    fun onAnswerFromSystem() {
        markAudioSessionActivated(true)
        // CallSessionManager.shared.acceptCall() is invoked by IncomingCallWake / activity.
    }

    /** Invoked when user declines from system UI. */
    fun onEndFromSystem(conversationId: String?) {
        val manager = CallSessionManager.shared
        if (!manager.hasEndedCurrentCall) {
            if (manager.isIncoming && !manager.isActive && !manager.isConnecting) {
                manager.declineCall(fromTelecom = true)
            } else {
                manager.endCall(fromTelecom = true)
            }
        }
        conversationId?.let { clearMapping(it) }
    }

    fun onMuteFromSystem(muted: Boolean) {
        CallSessionManager.shared.applyMute(muted = muted)
    }

    fun markAudioSessionActivated(activated: Boolean) {
        isAudioSessionActivated = activated
        if (activated) resumeAudioSessionWaiters()
    }

    fun reset() {
        callUuidByConversationId.clear()
        conversationIdByCallUuid.clear()
        isAudioSessionActivated = false
        resumeAudioSessionWaiters()
    }

    private fun resumeAudioSessionWaiters() {
        val waiters = synchronized(audioSessionWaiters) {
            audioSessionWaiters.toList().also { audioSessionWaiters.clear() }
        }
        waiters.forEach { it.complete(Unit) }
    }

    private fun clearMapping(conversationId: String) {
        callUuidByConversationId.remove(conversationId)?.let { uuid ->
            conversationIdByCallUuid.remove(uuid)
        }
    }

    companion object {
        @Volatile private var instance: TelecomCallManager? = null

        val shared: TelecomCallManager
            get() = instance ?: TelecomCallManager(null).also { instance = it }

        fun init(context: Context): TelecomCallManager {
            return instance ?: synchronized(this) {
                instance ?: TelecomCallManager(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): TelecomCallManager = init(context)
    }
}
