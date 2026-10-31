package com.matterya.matterya.data.push

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.calls.CallSessionManager
import com.matterya.matterya.data.calls.IncomingCallWake
import com.matterya.matterya.data.calls.TelecomCallManager
import com.matterya.matterya.data.system.NotificationNames
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * iOS `PushNotificationService.swift` → Android FCM registration surface.
 *
 * Uses Android/iOS push register endpoints when available; falls back to the same
 * payload routing algorithms as iOS for deep links + incoming calls.
 */
class PushNotificationService private constructor(
    private val appContext: Context?,
) {
    private val auth = AuthService.instance
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val http = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build()

    private val prefs by lazy {
        appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    private var deviceToken: String? = null
    private var highPriorityCallToken: String? = null
    private var lastRegisteredToken: String? = null
    private var lastRegisteredCallToken: String? = null

    @Volatile var lastRegistrationError: String? = null
        private set
    @Volatile var lastCallRegistrationError: String? = null
        private set
    @Volatile var serverRegistrationSucceeded = false
        private set
    @Volatile var callServerRegistrationSucceeded = false
        private set

    data class ServerPushStatus(
        val endpointsAvailable: Boolean,
        val fcmConfigured: Boolean,
        val packageName: String,
        val alertTokenCount: Int,
        val callTokenCount: Int,
        val environments: List<String>,
        val statusMessage: String?,
    )

    @Volatile var lastServerPushStatus: ServerPushStatus? = null
        private set

    private val _deepLinks = MutableSharedFlow<Map<String, Any?>>(extraBufferCapacity = 8)
    val deepLinks: SharedFlow<Map<String, Any?>> = _deepLinks.asSharedFlow()

    private val _events = MutableSharedFlow<String>(extraBufferCapacity = 16)
    val events: SharedFlow<String> = _events.asSharedFlow()

    val hasHighPriorityCallToken: Boolean
        get() {
            loadPersistedTokens()
            return !highPriorityCallToken.isNullOrEmpty()
        }

    val hasAlertToken: Boolean
        get() {
            loadPersistedTokens()
            return !deviceToken.isNullOrEmpty()
        }

    val registrationSummary: String
        get() {
            if (serverRegistrationSucceeded) return "Alert push registered with Matterya servers."
            lastRegistrationError?.let { return it }
            if (deviceToken == null) return "Waiting for FCM device token…"
            return "Alert push not registered yet."
        }

    val callingRegistrationSummary: String
        get() {
            if (callServerRegistrationSucceeded) {
                return "High-priority call channel registered — incoming calls can ring when Matterya is closed."
            }
            lastCallRegistrationError?.let { return it }
            VoIPPushService.shared.lastStatusMessage?.let { return it }
            if (!hasHighPriorityCallToken) {
                return "Waiting for FCM high-priority call token…"
            }
            if (!auth.isAuthenticated) {
                return "Sign in so Matterya can register this device for calls."
            }
            return "Call token received but not registered with server yet."
        }

    val isReadyForIncomingCalls: Boolean
        get() = callServerRegistrationSucceeded && hasHighPriorityCallToken

    init {
        loadPersistedTokens()
    }

    fun configure() {
        // Notification channel setup is handled by the host FirebaseMessagingService / Application.
        VoIPPushService.shared.bootstrap()
    }

    suspend fun requestAuthorizationAndRegister(
        launcher: (suspend (Array<String>) -> Map<String, Boolean>)? = null,
    ) {
        configure()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && appContext != null) {
            val granted = ContextCompat.checkSelfPermission(
                appContext,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                if (launcher != null) {
                    val result = launcher(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
                    if (result[Manifest.permission.POST_NOTIFICATIONS] != true) {
                        lastRegistrationError = "Notification permission denied."
                        return
                    }
                } else {
                    lastRegistrationError = "Notification permission not determined."
                    return
                }
            }
        }
        requestFcmTokenRefresh()
    }

    fun requestFcmTokenRefresh() {
        // Host app should call updateDeviceToken / registerHighPriorityCallToken
        // when FirebaseMessaging.getInstance().token completes.
        // Without Firebase BOM: no-op reflection probe (see MatteryaFirebaseMessagingHost).
        _events.tryEmit("request_fcm_token")
        MatteryaFirebaseMessagingHost.tryRequestFirebaseTokenRefresh()
    }

    fun updateDeviceToken(token: String) {
        deviceToken = token
        prefs?.edit()?.putString(KEY_ALERT, token)?.apply()
        // Reuse alert FCM token as high-priority call token surface when separate
        // topic/token is not provisioned yet (same device registration).
        if (highPriorityCallToken.isNullOrEmpty()) {
            highPriorityCallToken = token
            prefs?.edit()?.putString(KEY_CALL, token)?.apply()
        }
        VoIPPushService.shared.bootstrap()
        // Fire-and-forget registration
        scope.launch {
            runCatching {
                registerTokenIfNeeded(token, kind = "alert", force = true)
                VoIPPushService.shared.ensureToken()
                highPriorityCallToken?.let {
                    registerTokenIfNeeded(it, kind = "call", force = true)
                }
            }
        }
    }

    suspend fun registerHighPriorityCallToken(token: String) {
        highPriorityCallToken = token
        prefs?.edit()?.putString(KEY_CALL, token)?.apply()
        registerTokenIfNeeded(token, kind = "call", force = true)
    }

    fun handleRegistrationFailure() {
        deviceToken = null
        prefs?.edit()?.remove(KEY_ALERT)?.apply()
        lastRegistrationError = "FCM registration failed. Check Google Play Services."
        serverRegistrationSucceeded = false
    }

    suspend fun unregisterFromServer() {
        loadPersistedTokens()
        val tokens = listOfNotNull(deviceToken, highPriorityCallToken).filter { it.isNotEmpty() }.toSet()
        if (tokens.isEmpty()) return
        val accessToken = runCatching { auth.ensureValidToken() }.getOrNull()
        for (token in tokens) {
            for (path in listOf("/push/android/unregister", "/push/ios/unregister")) {
                runCatching {
                    val body = JSONObject().put("deviceToken", token).toString()
                    val builder = Request.Builder()
                        .url("${AppConfig.apiBaseURL}$path")
                        .post(body.toRequestBody(JSON))
                        .header("Content-Type", "application/json")
                    if (accessToken != null) {
                        builder.header("Authorization", "Bearer $accessToken")
                    }
                    http.newCall(builder.build()).execute().close()
                }
            }
        }
        deviceToken = null
        lastRegisteredToken = null
        lastRegisteredCallToken = null
        serverRegistrationSucceeded = false
        callServerRegistrationSucceeded = false
        lastCallRegistrationError = null
        prefs?.edit()?.remove(KEY_ALERT)?.apply()
    }

    suspend fun syncWithServer(force: Boolean = false) {
        configure()
        loadPersistedTokens()
        if (force) {
            lastRegisteredToken = null
            lastRegisteredCallToken = null
        }
        VoIPPushService.shared.bootstrap()
        VoIPPushService.shared.ensureToken()
        highPriorityCallToken?.let { registerTokenIfNeeded(it, kind = "call", force = force) }
        val token = deviceToken
        if (token != null) {
            registerTokenIfNeeded(token, kind = "alert", force = force)
        } else {
            requestFcmTokenRefresh()
        }
    }

    suspend fun fetchServerCapabilities(): Triple<Boolean, Boolean, Boolean> =
        withContext(Dispatchers.IO) {
            for (path in listOf("/push/capabilities", "/health")) {
                val req = Request.Builder().url("${AppConfig.apiBaseURL}$path").get().build()
                val response = runCatching { http.newCall(req).execute() }.getOrNull() ?: continue
                val raw = response.body?.string().orEmpty()
                if (!response.isSuccessful) continue
                val root = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull()
                    ?: continue
                val features = root["features"]?.jsonObject
                val androidRoutes = root["androidPushRoutes"]?.jsonPrimitive?.booleanOrNull
                    ?: features?.get("androidPushRoutes")?.jsonPrimitive?.booleanOrNull
                    ?: root["iosPushRoutes"]?.jsonPrimitive?.booleanOrNull
                    ?: features?.get("iosPushRoutes")?.jsonPrimitive?.booleanOrNull
                    ?: (path == "/push/capabilities")
                val fcmConfigured = root["fcmConfigured"]?.jsonPrimitive?.booleanOrNull
                    ?: root["apnsConfigured"]?.jsonPrimitive?.booleanOrNull
                    ?: false
                val webPush = root["webPushConfigured"]?.jsonPrimitive?.booleanOrNull ?: false
                return@withContext Triple(androidRoutes, fcmConfigured, webPush)
            }
            Triple(false, false, false)
        }

    suspend fun fetchServerPushStatus(): ServerPushStatus? {
        val capabilities = fetchServerCapabilities()
        if (!capabilities.first) {
            val status = ServerPushStatus(
                endpointsAvailable = false,
                fcmConfigured = capabilities.second,
                packageName = appContext?.packageName ?: "com.matterya.matterya",
                alertTokenCount = 0,
                callTokenCount = 0,
                environments = emptyList(),
                statusMessage = "api.matterya.com is missing push routes. Deploy the latest apps/api build.",
            )
            lastServerPushStatus = status
            return status
        }
        if (!auth.isAuthenticated) return null
        return withContext(Dispatchers.IO) {
            val accessToken = runCatching { auth.ensureValidToken() }.getOrNull() ?: return@withContext null
            for (path in listOf("/push/android/status", "/push/ios/status")) {
                val req = Request.Builder()
                    .url("${AppConfig.apiBaseURL}$path")
                    .get()
                    .header("Authorization", "Bearer $accessToken")
                    .build()
                val response = runCatching { http.newCall(req).execute() }.getOrNull() ?: continue
                val raw = response.body?.string().orEmpty()
                if (response.code == 404) continue
                if (!response.isSuccessful) continue
                val root = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull()
                    ?: continue
                val tokens = root["tokens"]?.jsonObject
                val environments = tokens?.get("environments")?.jsonArray
                    ?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty()
                val status = ServerPushStatus(
                    endpointsAvailable = true,
                    fcmConfigured = root["fcmConfigured"]?.jsonPrimitive?.booleanOrNull
                        ?: root["apnsConfigured"]?.jsonPrimitive?.booleanOrNull
                        ?: capabilities.second,
                    packageName = root["packageName"]?.jsonPrimitive?.contentOrNull
                        ?: root["bundleId"]?.jsonPrimitive?.contentOrNull
                        ?: (appContext?.packageName ?: "com.matterya.matterya"),
                    alertTokenCount = tokens?.get("alert")?.jsonPrimitive?.intOrNull ?: 0,
                    callTokenCount = tokens?.get("voip")?.jsonPrimitive?.intOrNull
                        ?: tokens?.get("call")?.jsonPrimitive?.intOrNull
                        ?: 0,
                    environments = environments,
                    statusMessage = null,
                )
                lastServerPushStatus = status
                return@withContext status
            }
            null
        }
    }

    suspend fun sendTestNotification(): String {
        if (!auth.isAuthenticated) return "Sign in first."
        if (!hasAlertToken) return "No FCM token on this device. Check Firebase setup, then refresh."
        if (!serverRegistrationSucceeded) return registrationSummary
        return withContext(Dispatchers.IO) {
            val accessToken = runCatching { auth.ensureValidToken() }.getOrElse {
                return@withContext it.message ?: "Auth failed"
            }
            for (path in listOf("/push/android/test", "/push/ios/test")) {
                val req = Request.Builder()
                    .url("${AppConfig.apiBaseURL}$path")
                    .post("{}".toRequestBody(JSON))
                    .header("Authorization", "Bearer $accessToken")
                    .header("Content-Type", "application/json")
                    .build()
                val response = runCatching { http.newCall(req).execute() }.getOrNull() ?: continue
                val raw = response.body?.string().orEmpty()
                if (response.isSuccessful) {
                    fetchServerPushStatus()
                    return@withContext "Test notification sent. Background the app to see it."
                }
                if (response.code != 404) {
                    fetchServerPushStatus()
                    return@withContext pushErrorMessage(raw, response.code)
                }
            }
            "Push test endpoint missing on api.matterya.com."
        }
    }

    suspend fun handleRemoteNotification(userInfo: Map<String, Any?>): Boolean {
        val payload = normalizedPayload(userInfo)
        return routePushPayload(payload)
    }

    fun presentIncomingCallForBackgroundWake(userInfo: Map<String, Any?>): Boolean =
        IncomingCallWake.handleIfNeeded(userInfo)

    suspend fun handleIncomingCallPayload(
        payload: Map<String, Any?>,
        completion: (() -> Unit)? = null,
    ) {
        routePushPayload(payload)
        completion?.invoke()
    }

    suspend fun clearDeliveredNotifications(forConversation: String) {
        // Host NotificationManager can cancel conversation-tagged notifications.
        _events.tryEmit("clear_conversation:$forConversation")
    }

    private fun loadPersistedTokens() {
        if (deviceToken == null) deviceToken = prefs?.getString(KEY_ALERT, null)
        if (highPriorityCallToken == null) highPriorityCallToken = prefs?.getString(KEY_CALL, null)
    }

    private suspend fun registerTokenIfNeeded(token: String, kind: String, force: Boolean = false) {
        val isCall = kind == "call" || kind == "voip"
        val last = if (isCall) lastRegisteredCallToken else lastRegisteredToken
        val already = if (isCall) callServerRegistrationSucceeded else serverRegistrationSucceeded
        if (!force && token == last && already) return
        if (!auth.isAuthenticated) {
            val message = "Sign in so Matterya can register this device for push."
            if (isCall) lastCallRegistrationError = message else lastRegistrationError = message
            return
        }
        withContext(Dispatchers.IO) {
            val accessToken = runCatching { auth.ensureValidToken() }.getOrElse {
                if (isCall) lastCallRegistrationError = it.message
                else lastRegistrationError = it.message
                return@withContext
            }
            val packageName = appContext?.packageName ?: "com.matterya.matterya"
            val body = JSONObject()
                .put("deviceToken", token)
                .put("bundleId", packageName)
                .put("packageName", packageName)
                .put("kind", if (isCall) "call" else "alert")
                .put("platform", "android")
                .put("environment", "production")
                .toString()

            var registered = false
            for (path in listOf("/push/android/register", "/push/ios/register")) {
                val req = Request.Builder()
                    .url("${AppConfig.apiBaseURL}$path")
                    .post(body.toRequestBody(JSON))
                    .header("Authorization", "Bearer $accessToken")
                    .header("Content-Type", "application/json")
                    .build()
                val response = runCatching { http.newCall(req).execute() }.getOrNull() ?: continue
                val raw = response.body?.string().orEmpty()
                if (response.isSuccessful) {
                    if (isCall) {
                        lastRegisteredCallToken = token
                        lastCallRegistrationError = null
                        callServerRegistrationSucceeded = true
                    } else {
                        lastRegisteredToken = token
                        lastRegistrationError = null
                        serverRegistrationSucceeded = true
                    }
                    registered = true
                    break
                }
                if (response.code != 404) {
                    val message = if (response.code == 404) {
                        "api.matterya.com does not have push routes yet."
                    } else {
                        "Registration failed (${response.code}): $raw"
                    }
                    if (isCall) {
                        lastCallRegistrationError = message
                        callServerRegistrationSucceeded = false
                    } else {
                        lastRegistrationError = message
                        serverRegistrationSucceeded = false
                    }
                }
            }
            if (!registered && lastRegistrationError == null && !isCall) {
                lastRegistrationError = "Push registration endpoints unavailable."
            }
        }
    }

    private suspend fun routePushPayload(
        payload: Map<String, Any?>,
        presentInAppUI: Boolean = false,
        openDestination: Boolean = true,
    ): Boolean {
        if (isCallPayload(payload)) {
            return routeIncomingCallPayload(payload, presentInAppUI)
        }
        val type = ((payload["type"] as? String) ?: (payload["category"] as? String) ?: "").lowercase()
        val conversationId = extractConversationId(payload)

        if (type == "message" && conversationId != null) {
            _events.tryEmit(NotificationNames.CONVERSATION_MESSAGES_DID_CHANGE)
            if (openDestination) postDeepLink(type, conversationId, null, null)
            return true
        }

        val postId = stringValue(payload["postId"])
            ?: stringValue(payload["post_id"])
            ?: stringValue(payload["entityId"])
            ?: stringValue(payload["entity_id"])
        val username = stringValue(payload["username"])
            ?: stringValue(payload["actorUsername"])
            ?: stringValue(payload["actor_username"])

        if (type in SOCIAL_TYPES || postId != null || type == "follow") {
            _events.tryEmit(NotificationNames.SOCIAL_NOTIFICATIONS_DID_CHANGE)
            if (openDestination) postDeepLink(type, null, postId, username)
            return true
        }
        return false
    }

    private suspend fun routeIncomingCallPayload(
        payload: Map<String, Any?>,
        presentInAppUI: Boolean,
    ): Boolean {
        val conversationId = stringValue(payload["conversationId"])
            ?: stringValue(payload["conversation_id"])
            ?: return false
        val from = stringValue(payload["from"])
            ?: stringValue(payload["callerId"])
            ?: return false
        val callType = stringValue(payload["callType"]) ?: "audio"
        val callId = stringValue(payload["callId"]) ?: stringValue(payload["callID"])
        val roomName = stringValue(payload["roomName"]) ?: stringValue(payload["room"])
        val displayName = stringValue(payload["title"])
            ?: stringValue(payload["callerName"])
            ?: "Incoming call"

        val me = auth.currentUser?.id
        if (me != null && from == me) return true

        CallSessionManager.shared.bootstrapForIncomingCall()
        val staged = CallSessionManager.shared.stageIncomingCall(
            conversationId = conversationId,
            fromUserId = from,
            callType = callType,
            callId = callId,
            roomName = roomName,
            callerName = displayName,
        )
        if (!staged) {
            if (!presentInAppUI) TelecomCallManager.shared.requestEndCall(conversationId)
            return true
        }
        CallSessionManager.shared.finalizeIncomingCallPresentation(
            conversationId = conversationId,
            fromUserId = from,
            reportToTelecom = !presentInAppUI,
        )
        if (presentInAppUI) CallSessionManager.shared.presentInAppIncomingUI()
        return true
    }

    private fun postDeepLink(
        type: String,
        conversationId: String?,
        postId: String?,
        username: String?,
    ) {
        val map = mapOf(
            "type" to type,
            "conversationId" to conversationId,
            "postId" to postId,
            "username" to username,
        )
        _deepLinks.tryEmit(map)
        _events.tryEmit(NotificationNames.PUSH_DEEP_LINK_REQUESTED)
    }

    private fun extractConversationId(payload: Map<String, Any?>): String? =
        stringValue(payload["conversationId"])
            ?: stringValue(payload["conversation_id"])
            ?: stringValue(payload["conversationID"])
            ?: stringValue(payload["entityId"])
            ?: stringValue(payload["entity_id"])

    private fun isCallPayload(payload: Map<String, Any?>): Boolean {
        val type = ((payload["type"] as? String) ?: (payload["category"] as? String) ?: "").lowercase()
        if (type == "call" || type == "incoming_call") return true
        @Suppress("UNCHECKED_CAST")
        val aps = payload["aps"] as? Map<String, Any?>
        if ((aps?.get("category") as? String)?.lowercase() == "call") return true
        return false
    }

    private fun normalizedPayload(userInfo: Map<String, Any?>): Map<String, Any?> {
        val merged = userInfo.toMutableMap()
        @Suppress("UNCHECKED_CAST")
        (merged["custom"] as? Map<String, Any?>)?.forEach { (k, v) ->
            if (merged[k] == null) merged[k] = v
        }
        @Suppress("UNCHECKED_CAST")
        (merged["data"] as? Map<String, Any?>)?.forEach { (k, v) ->
            if (merged[k] == null) merged[k] = v
        }
        return merged
    }

    private fun stringValue(value: Any?): String? = when (value) {
        is String -> value.trim().takeIf { it.isNotEmpty() }
        is Number -> value.toString()
        else -> null
    }

    private fun pushErrorMessage(body: String, statusCode: Int): String {
        if (statusCode == 404) {
            return "api.matterya.com does not have push routes yet."
        }
        runCatching {
            val o = JSONObject(body)
            val message = o.optString("message")
            if (message.isNotEmpty()) {
                val error = o.optString("error")
                return if (error.isNotEmpty()) "$message ($error)" else message
            }
        }
        return "Server error $statusCode: ${body.ifEmpty { "push_failed" }}"
    }

    companion object {
        private const val PREFS = "matterya_push"
        private const val KEY_ALERT = "push.alert.token"
        private const val KEY_CALL = "push.call.token"
        private val JSON = "application/json; charset=utf-8".toMediaType()
        private val SOCIAL_TYPES = setOf(
            "like", "comment", "comment_like", "comment_reply", "follow",
        )

        @Volatile private var instance: PushNotificationService? = null

        val shared: PushNotificationService
            get() = instance ?: PushNotificationService(null).also { instance = it }

        fun init(context: Context): PushNotificationService {
            return instance ?: synchronized(this) {
                instance ?: PushNotificationService(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): PushNotificationService = init(context)
    }
}
