package com.matterya.matterya.data.calls

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.system.NotificationNames
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.resume

data class CallSignal(
    val type: String,
    val conversationId: String,
    val from: String,
    val callType: String? = null,
    val callId: String? = null,
    val roomName: String? = null,
    val connectedAt: Double? = null,
)

/** iOS `CallSignalingService.swift` — WebSocket signaling over Matterya API. */
class CallSignalingService private constructor(
    private val auth: AuthService = AuthService.instance,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val http = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _signals = MutableSharedFlow<CallSignal>(extraBufferCapacity = 32)
    val signals: SharedFlow<CallSignal> = _signals.asSharedFlow()

    var onSignal: ((CallSignal) -> Unit)? = null
    var onConnectionChange: ((Boolean) -> Unit)? = null

    private var webSocket: WebSocket? = null
    private var reconnectJob: Job? = null
    private var isDestroyed = false
    private val socketOpenGeneration = AtomicInteger(0)
    private val openLatch = AtomicBoolean(false)

    fun connect() {
        isDestroyed = false
        if (_isConnected.value && webSocket != null) return
        reconnectJob?.cancel()
        reconnectJob = scope.launch { openSocket() }
    }

    suspend fun ensureConnected(timeoutSeconds: Double = 6.0): Boolean {
        connect()
        if (_isConnected.value) return true
        val attempts = maxOf(1, (timeoutSeconds / 0.25).toInt())
        repeat(attempts) {
            delay(250)
            if (_isConnected.value) return true
        }
        return _isConnected.value
    }

    fun disconnect() {
        reconnectJob?.cancel()
        webSocket?.close(1001, "goingAway")
        webSocket = null
        setConnected(false)
    }

    fun shutdown() {
        isDestroyed = true
        disconnect()
    }

    fun send(
        type: String,
        conversationId: String,
        from: String,
        callType: String? = null,
        callId: String? = null,
        roomName: String? = null,
        to: String? = null,
        connectedAt: Double? = null,
    ) {
        val ws = webSocket ?: return
        if (!_isConnected.value) return
        val payload = buildJsonObject {
            put("type", type)
            put("conversationId", conversationId)
            put("from", from)
            callType?.let { put("callType", it) }
            callId?.let { put("callId", it) }
            roomName?.let { put("roomName", it) }
            to?.let { put("to", it) }
            connectedAt?.let { put("connectedAt", it) }
        }
        ws.send(payload.toString())
    }

    fun onAuthTokenRefreshed() {
        if (isDestroyed) return
        scope.launch {
            webSocket?.close(1001, "token-refresh")
            webSocket = null
            setConnected(false)
            openSocket()
        }
    }

    private suspend fun openSocket() {
        val generation = socketOpenGeneration.incrementAndGet()
        val token = runCatching { auth.ensureValidToken() }.getOrNull()
        if (token == null) {
            setConnected(false)
            scheduleReconnect()
            return
        }
        if (generation != socketOpenGeneration.get() || isDestroyed) return

        val wsBase = AppConfig.apiBaseURL
            .replace("https://", "wss://")
            .replace("http://", "ws://")
        val encoded = URLEncoder.encode(token, Charsets.UTF_8.name())
        val url = "$wsBase/ws?token=$encoded"

        webSocket?.close(1001, null)
        setConnected(false)
        openLatch.set(false)

        val request = Request.Builder().url(url).build()
        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                openLatch.set(true)
                if (generation == socketOpenGeneration.get() && !isDestroyed) {
                    setConnected(true)
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handle(text)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                setConnected(false)
                if (!isDestroyed && generation == socketOpenGeneration.get()) {
                    scheduleReconnect()
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                setConnected(false)
                if (!isDestroyed && generation == socketOpenGeneration.get()) {
                    scheduleReconnect()
                }
            }
        }

        val task = http.newWebSocket(request, listener)
        webSocket = task

        val opened = waitForSocketOpen(timeoutMs = 5_000)
        if (!opened || generation != socketOpenGeneration.get() || isDestroyed || webSocket !== task) {
            setConnected(false)
            if (!isDestroyed && generation == socketOpenGeneration.get()) {
                scheduleReconnect()
            }
        }
    }

    private suspend fun waitForSocketOpen(timeoutMs: Long): Boolean {
        val start = System.currentTimeMillis()
        while (System.currentTimeMillis() - start < timeoutMs) {
            if (openLatch.get()) return true
            delay(50)
        }
        return openLatch.get()
    }

    private fun handle(raw: String) {
        val root = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return
        val type = root["type"]?.jsonPrimitive?.contentOrNull ?: return
        val conversationId = root["conversationId"]?.jsonPrimitive?.contentOrNull ?: return
        val from = root["from"]?.jsonPrimitive?.contentOrNull ?: return
        val signal = CallSignal(
            type = type,
            conversationId = conversationId,
            from = from,
            callType = root["callType"]?.jsonPrimitive?.contentOrNull,
            callId = root["callId"]?.jsonPrimitive?.contentOrNull,
            roomName = root["roomName"]?.jsonPrimitive?.contentOrNull,
            connectedAt = root["connectedAt"]?.jsonPrimitive?.doubleOrNull,
        )
        onSignal?.invoke(signal)
        _signals.tryEmit(signal)
    }

    private fun scheduleReconnect() {
        if (isDestroyed) return
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            delay(3_000)
            openSocket()
        }
    }

    private fun setConnected(value: Boolean) {
        if (_isConnected.value == value) return
        _isConnected.value = value
        onConnectionChange?.invoke(value)
    }

    companion object {
        val shared by lazy { CallSignalingService() }
    }
}
