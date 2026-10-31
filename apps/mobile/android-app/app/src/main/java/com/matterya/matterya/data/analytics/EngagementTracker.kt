package com.matterya.matterya.data.analytics

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.model.CountryPost
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit

/** iOS `EngagementTracker.swift` — batches attention signals to `/v1/engagement/batch`. */
class EngagementTracker private constructor() {
    private data class PendingEvent(
        val type: String,
        val contentId: String? = null,
        val authorId: String? = null,
        val countryCode: String? = null,
        val hubSlug: String? = null,
        val mediaType: String? = null,
        val isSpark: Boolean = false,
        val durationMs: Int? = null,
        val progress: Double? = null,
        val surface: String? = null,
        val occurredAt: Instant = Instant.now(),
        val meta: Map<String, String>? = null,
    )

    private data class VisiblePost(
        val post: CountryPost,
        val surface: String,
        val startedAt: Long = System.currentTimeMillis(),
    )

    private val lookThresholdMs = 1_200
    private val skipThresholdMs = 500
    private val sessionId = UUID.randomUUID().toString()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val queue = mutableListOf<PendingEvent>()
    private val visible = mutableMapOf<String, VisiblePost>()
    private var flushJob: Job? = null
    private var hubOpenedAt: Long? = null
    private var currentScreen: String? = null
    private var screenOpenedAt: Long? = null

    private val http = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    fun feedPostAppeared(post: CountryPost, surface: String = "home") {
        visible[post.id] = VisiblePost(post, surface)
        scheduleFlush()
    }

    fun feedPostDisappeared(post: CountryPost) {
        val entry = visible.remove(post.id) ?: return
        val ms = (System.currentTimeMillis() - entry.startedAt).toInt()
        if (ms < 80) return
        when {
            ms >= lookThresholdMs -> enqueue("scroll_dwell", entry.post, entry.surface, ms)
            ms <= skipThresholdMs -> enqueue("scroll_skip", entry.post, entry.surface, ms)
            else -> enqueue("scroll_dwell", entry.post, entry.surface, ms)
        }
    }

    fun videoProgress(post: CountryPost, progress: Double, durationMs: Int, surface: String) {
        val type = if (progress >= 0.92) "watch_complete" else "watch_partial"
        enqueue(type, post, surface, durationMs, progress.coerceIn(0.0, 1.0))
    }

    fun hubsOpened() {
        hubOpenedAt = System.currentTimeMillis()
        enqueue(type = "hub_open", surface = "hubs", meta = mapOf("place" to "hubs_tab"))
    }

    fun hubsLeft() {
        val opened = hubOpenedAt ?: return
        val ms = (System.currentTimeMillis() - opened).toInt()
        hubOpenedAt = null
        enqueue(type = "hub_leave", surface = "hubs", durationMs = ms, meta = mapOf("place" to "hubs_tab"))
    }

    fun enqueuePersonFollow(targetId: String, following: Boolean) {
        enqueue(
            type = if (following) "person_follow" else "person_unfollow",
            authorId = targetId,
            surface = "profile",
            meta = mapOf("targetUserId" to targetId),
        )
    }

    fun hubShelfSelected(name: String) {
        enqueue(type = "hub_shelf", surface = "hubs", hubSlug = name, meta = mapOf("shelf" to name))
    }

    fun hubVideoOpened(post: CountryPost) {
        enqueue(type = "hub_video_open", post = post, surface = "hubs")
    }

    fun enqueueLike(post: CountryPost, liked: Boolean) {
        enqueue(
            type = if (liked) "post_like" else "post_unlike",
            post = post,
            surface = "home",
            meta = mapOf("liked" to if (liked) "1" else "0"),
        )
    }

    fun profileOpened(userId: String, username: String?) {
        enqueue(
            type = "profile_open",
            authorId = userId,
            surface = "profile",
            meta = mapOf("targetUserId" to userId, "username" to (username ?: "")),
        )
    }

    fun screenOpened(name: String) {
        val prev = currentScreen
        val started = screenOpenedAt
        if (prev != null && started != null && prev != name) {
            val ms = (System.currentTimeMillis() - started).toInt()
            enqueue(type = "screen_leave", surface = prev, durationMs = ms, meta = mapOf("screen" to prev))
        }
        currentScreen = name
        screenOpenedAt = System.currentTimeMillis()
        enqueue(type = "screen_open", surface = name, meta = mapOf("screen" to name))
    }

    fun appBackgrounded() {
        val keys = visible.keys.toList()
        for (id in keys) {
            visible[id]?.post?.let { feedPostDisappeared(it) }
        }
        if (hubOpenedAt != null) hubsLeft()
        currentScreen?.let { screen ->
            val ms = screenOpenedAt?.let { (System.currentTimeMillis() - it).toInt() }
            enqueue(type = "screen_leave", surface = screen, durationMs = ms, meta = mapOf("screen" to screen))
            currentScreen = null
            screenOpenedAt = null
        }
        scope.launch { flushNow() }
    }

    private fun enqueue(
        type: String,
        post: CountryPost? = null,
        surface: String? = null,
        durationMs: Int? = null,
        progress: Double? = null,
        authorId: String? = null,
        hubSlug: String? = null,
        meta: Map<String, String>? = null,
    ) {
        queue.add(
            PendingEvent(
                type = type,
                contentId = post?.id,
                authorId = authorId ?: post?.authorId,
                countryCode = post?.countryCode,
                hubSlug = hubSlug,
                mediaType = post?.mediaType,
                isSpark = post?.isReel == true,
                durationMs = durationMs,
                progress = progress,
                surface = surface,
                meta = meta,
            ),
        )
        if (queue.size >= 12) scope.launch { flushNow() } else scheduleFlush()
    }

    private fun scheduleFlush() {
        flushJob?.cancel()
        flushJob = scope.launch {
            delay(3_500)
            flushNow()
        }
    }

    suspend fun flushNow() = mutex.withLock {
        flushJob?.cancel()
        flushJob = null
        if (queue.isEmpty()) return@withLock
        val batch = queue.toList()
        queue.clear()
        val token = try {
            AuthService.instance.ensureValidToken()
        } catch (_: Exception) {
            queue.addAll(0, batch)
            return@withLock
        }
        val events = JSONArray()
        for (e in batch) {
            val dict = JSONObject()
            dict.put("type", e.type)
            dict.put("occurredAt", e.occurredAt.toString())
            dict.put("deviceClass", "phone")
            e.contentId?.let { dict.put("contentId", it) }
            e.authorId?.let { dict.put("authorId", it) }
            e.countryCode?.let { dict.put("countryCode", it) }
            e.hubSlug?.let { dict.put("hubSlug", it) }
            e.mediaType?.let { dict.put("mediaType", it) }
            if (e.isSpark) dict.put("isSpark", true)
            e.durationMs?.let { dict.put("durationMs", it) }
            e.progress?.let { dict.put("progress", it) }
            e.surface?.let { dict.put("surface", it) }
            e.meta?.takeIf { it.isNotEmpty() }?.let {
                val m = JSONObject()
                it.forEach { (k, v) -> m.put(k, v) }
                dict.put("meta", m)
            }
            events.put(dict)
        }
        val body = JSONObject()
            .put("sessionId", sessionId)
            .put("events", events)
            .toString()
        val req = Request.Builder()
            .url("${AppConfig.apiBaseURL}/v1/engagement/batch")
            .post(body.toRequestBody("application/json".toMediaType()))
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .build()
        runCatching { http.newCall(req).execute().close() }
    }

    companion object {
        val shared = EngagementTracker()
    }
}
