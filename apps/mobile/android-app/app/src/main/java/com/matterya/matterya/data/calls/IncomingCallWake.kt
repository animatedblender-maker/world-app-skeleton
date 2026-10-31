package com.matterya.matterya.data.calls

import com.matterya.matterya.data.auth.AuthService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * iOS `IncomingCallWake.swift`.
 * Presents incoming calls immediately when a push wakes the app.
 */
object IncomingCallWake {
    data class Payload(
        val conversationId: String,
        val from: String,
        val callType: String,
        val callId: String?,
        val roomName: String?,
        val displayName: String,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** True when a remote payload is an incoming call. */
    fun looksLikeIncomingCall(userInfo: Map<String, Any?>?): Boolean {
        if (userInfo == null) return false
        return parse(userInfo) != null
    }

    fun handleIfNeeded(userInfo: Map<String, Any?>): Boolean {
        val payload = parse(userInfo) ?: return false
        return present(payload)
    }

    private fun present(payload: Payload): Boolean {
        val me = AuthService.instance.currentUser?.id
        if (me != null && payload.from == me) return false

        // When app process is active, use in-app UI; otherwise system/Telecom path.
        val appActive = CallSessionManager.isAppInForeground
        return if (appActive) presentInApp(payload) else presentWithTelecom(payload)
    }

    private fun presentInApp(payload: Payload): Boolean {
        CallSessionManager.shared.bootstrapForIncomingCall()
        val staged = CallSessionManager.shared.stageIncomingCall(
            conversationId = payload.conversationId,
            fromUserId = payload.from,
            callType = payload.callType,
            callId = payload.callId,
            roomName = payload.roomName,
            callerName = payload.displayName,
        )
        if (!staged) return false
        scope.launch {
            CallSessionManager.shared.finalizeIncomingCallPresentation(
                conversationId = payload.conversationId,
                fromUserId = payload.from,
                reportToTelecom = false,
            )
        }
        return true
    }

    private fun presentWithTelecom(payload: Payload): Boolean {
        TelecomCallManager.shared
        CallSessionManager.shared.bootstrapForIncomingCall()
        TelecomCallManager.shared.reportIncomingCall(
            conversationId = payload.conversationId,
            callerName = payload.displayName,
            hasVideo = payload.callType == "video",
        ) { }

        val staged = CallSessionManager.shared.stageIncomingCall(
            conversationId = payload.conversationId,
            fromUserId = payload.from,
            callType = payload.callType,
            callId = payload.callId,
            roomName = payload.roomName,
            callerName = payload.displayName,
        )
        if (staged) {
            scope.launch {
                CallSessionManager.shared.finalizeIncomingCallPresentation(
                    conversationId = payload.conversationId,
                    fromUserId = payload.from,
                    reportToTelecom = false,
                )
            }
        } else {
            TelecomCallManager.shared.requestEndCall(payload.conversationId)
        }
        return staged
    }

    fun parse(userInfo: Map<String, Any?>): Payload? {
        val merged = userInfo.toMutableMap()
        @Suppress("UNCHECKED_CAST")
        (merged["custom"] as? Map<String, Any?>)?.forEach { (k, v) ->
            if (merged[k] == null) merged[k] = v
        }
        @Suppress("UNCHECKED_CAST")
        (merged["data"] as? Map<String, Any?>)?.forEach { (k, v) ->
            if (merged[k] == null) merged[k] = v
        }

        val type = ((merged["type"] as? String) ?: (merged["category"] as? String) ?: "").lowercase()
        @Suppress("UNCHECKED_CAST")
        val apsCategory = (merged["aps"] as? Map<String, Any?>)?.get("category") as? String
        val isCall = type == "call" || type == "incoming_call" ||
            apsCategory?.lowercase() == "call"
        if (!isCall) return null

        val conversationId = stringValue(merged["conversationId"])
            ?: stringValue(merged["conversationID"])
            ?: stringValue(merged["conversation_id"])
            ?: return null
        val from = stringValue(merged["from"])
            ?: stringValue(merged["callerId"])
            ?: stringValue(merged["callerID"])
            ?: stringValue(merged["senderId"])
            ?: return null

        return Payload(
            conversationId = conversationId,
            from = from,
            callType = stringValue(merged["callType"]) ?: "audio",
            callId = stringValue(merged["callId"]) ?: stringValue(merged["callID"]),
            roomName = stringValue(merged["roomName"]) ?: stringValue(merged["room"]),
            displayName = stringValue(merged["title"])
                ?: stringValue(merged["callerName"])
                ?: "Incoming call",
        )
    }

    private fun stringValue(value: Any?): String? {
        return when (value) {
            is String -> value.trim().takeIf { it.isNotEmpty() }
            is Number -> value.toString()
            else -> null
        }
    }
}
