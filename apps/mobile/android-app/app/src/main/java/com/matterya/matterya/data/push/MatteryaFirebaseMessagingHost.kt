package com.matterya.matterya.data.push

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Compile-safe FCM host **without** Firebase BOM / `google-services.json`.
 *
 * iOS: `PushNotificationService` + `VoIPPushService` receive remote payloads via
 * APNs / PushKit. On Android the production entry is normally
 * `FirebaseMessagingService`, but that dependency breaks builds when Firebase is
 * not configured.
 *
 * **Usage when Firebase is added later:**
 * ```
 * class MyFcmService : FirebaseMessagingService() {
 *     override fun onNewToken(token: String) {
 *         MatteryaFirebaseMessagingHost.onNewToken(token)
 *     }
 *     override fun onMessageReceived(message: RemoteMessage) {
 *         MatteryaFirebaseMessagingHost.onMessageReceived(message.data)
 *     }
 * }
 * ```
 *
 * Until then this host is invoked from:
 * - [MatteryaMessagingService] (exported=false Service for debug/local delivery)
 * - [PushMessageReceiver] (local BroadcastReceiver stub)
 * - Optional reflection probes for `FirebaseMessaging` token refresh
 */
object MatteryaFirebaseMessagingHost {
    private const val TAG = "MatteryaFcmHost"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** Forward FCM registration token (alert + high-priority call surface). */
    fun onNewToken(token: String) {
        val trimmed = token.trim()
        if (trimmed.isEmpty()) return
        Log.d(TAG, "onNewToken (len=${trimmed.length})")
        runCatching {
            PushNotificationService.shared.updateDeviceToken(trimmed)
        }.onFailure { Log.w(TAG, "updateDeviceToken failed", it) }
    }

    /**
     * Forward a data payload map (FCM `RemoteMessage.data` or synthetic test intent).
     * Call payloads go to [VoIPPushService.onHighPriorityCallMessage]; everything else
     * to [PushNotificationService.handleRemoteNotification].
     */
    fun onMessageReceived(data: Map<String, String>, highPriority: Boolean = false) {
        if (data.isEmpty()) return
        val anyMap: Map<String, Any?> = data.mapValues { it.value }
        val looksLikeCall = isCallPayload(data)
        if (looksLikeCall || highPriority) {
            VoIPPushService.shared.onHighPriorityCallMessage(data)
            // Also let PushNotificationService stage deep links / call session.
            scope.launch {
                runCatching {
                    PushNotificationService.shared.handleRemoteNotification(anyMap)
                }
            }
            return
        }
        scope.launch {
            runCatching {
                PushNotificationService.shared.handleRemoteNotification(anyMap)
            }.onFailure { Log.w(TAG, "handleRemoteNotification failed", it) }
        }
    }

    /**
     * Best-effort token refresh via reflection when Firebase is on the classpath
     * but we don't compile against it. No-op if Firebase classes are absent.
     */
    fun tryRequestFirebaseTokenRefresh() {
        try {
            val messagingClass = Class.forName("com.google.firebase.messaging.FirebaseMessaging")
            val getInstance = messagingClass.getMethod("getInstance")
            val instance = getInstance.invoke(null)
            val getToken = messagingClass.getMethod("getToken")
            val task = getToken.invoke(instance) ?: return
            // com.google.android.gms.tasks.Task addOnSuccessListener
            val taskClass = task.javaClass
            val listenerClass = Class.forName("com.google.android.gms.tasks.OnSuccessListener")
            val proxy = java.lang.reflect.Proxy.newProxyInstance(
                listenerClass.classLoader,
                arrayOf(listenerClass),
            ) { _, method, args ->
                if (method.name == "onSuccess" && args != null && args.isNotEmpty()) {
                    val token = args[0] as? String
                    if (!token.isNullOrBlank()) onNewToken(token)
                }
                null
            }
            taskClass.getMethod("addOnSuccessListener", listenerClass).invoke(task, proxy)
        } catch (_: ClassNotFoundException) {
            // Firebase not on classpath — expected in default skeleton builds.
        } catch (t: Throwable) {
            Log.d(TAG, "Firebase token reflection skipped: ${t.message}")
        }
    }

    private fun isCallPayload(data: Map<String, String>): Boolean {
        val type = (data["type"] ?: data["category"] ?: "").lowercase()
        if (type == "call" || type == "incoming_call") return true
        return data.containsKey("callId") || data.containsKey("callID") ||
            (data.containsKey("conversationId") || data.containsKey("conversation_id")) &&
            (data.containsKey("from") || data.containsKey("callerId"))
    }
}

/**
 * Manifest-registered no-op host Service. Receives explicit start intents for
 * local/debug push delivery without Firebase.
 *
 * Intent extras:
 * - `fcm_token` → [MatteryaFirebaseMessagingHost.onNewToken]
 * - `data_*` string extras → data map for [MatteryaFirebaseMessagingHost.onMessageReceived]
 * - `high_priority` boolean
 */
class MatteryaMessagingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.getStringExtra(EXTRA_TOKEN)?.let { MatteryaFirebaseMessagingHost.onNewToken(it) }
        val data = intent?.extras
            ?.keySet()
            ?.filter { it.startsWith(EXTRA_DATA_PREFIX) }
            ?.associate { key ->
                key.removePrefix(EXTRA_DATA_PREFIX) to (intent.getStringExtra(key) ?: "")
            }
            .orEmpty()
        if (data.isNotEmpty()) {
            val highPriority = intent?.getBooleanExtra(EXTRA_HIGH_PRIORITY, false) == true
            MatteryaFirebaseMessagingHost.onMessageReceived(data, highPriority = highPriority)
        }
        stopSelf(startId)
        return START_NOT_STICKY
    }

    companion object {
        const val EXTRA_TOKEN = "fcm_token"
        const val EXTRA_HIGH_PRIORITY = "high_priority"
        const val EXTRA_DATA_PREFIX = "data_"

        fun deliverToken(context: Context, token: String) {
            context.startService(
                Intent(context, MatteryaMessagingService::class.java)
                    .putExtra(EXTRA_TOKEN, token),
            )
        }

        fun deliverData(
            context: Context,
            data: Map<String, String>,
            highPriority: Boolean = false,
        ) {
            val intent = Intent(context, MatteryaMessagingService::class.java)
                .putExtra(EXTRA_HIGH_PRIORITY, highPriority)
            data.forEach { (k, v) -> intent.putExtra("$EXTRA_DATA_PREFIX$k", v) }
            context.startService(intent)
        }
    }
}

/**
 * Local BroadcastReceiver stub for debug/test push injection.
 * Action: [ACTION_PUSH]
 */
class PushMessageReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        if (intent.action != ACTION_PUSH && intent.action != Intent.ACTION_BOOT_COMPLETED) return
        intent.getStringExtra(MatteryaMessagingService.EXTRA_TOKEN)?.let {
            MatteryaFirebaseMessagingHost.onNewToken(it)
        }
        val data = intent.extras
            ?.keySet()
            ?.filter { it.startsWith(MatteryaMessagingService.EXTRA_DATA_PREFIX) }
            ?.associate { key ->
                key.removePrefix(MatteryaMessagingService.EXTRA_DATA_PREFIX) to
                    (intent.getStringExtra(key) ?: "")
            }
            .orEmpty()
        if (data.isNotEmpty()) {
            val highPriority =
                intent.getBooleanExtra(MatteryaMessagingService.EXTRA_HIGH_PRIORITY, false)
            MatteryaFirebaseMessagingHost.onMessageReceived(data, highPriority = highPriority)
        }
    }

    companion object {
        const val ACTION_PUSH = "com.matterya.matterya.action.PUSH_MESSAGE"
    }
}
