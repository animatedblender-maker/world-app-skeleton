package com.matterya.matterya.data.hubs

import android.content.Context
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.PostAuthor
import com.matterya.matterya.model.PostComment
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/**
 * Local likes + comments for Internet Archive hub/spark videos.
 * iOS `HubEngagementStore.swift`.
 */
class HubEngagementStore private constructor(private val appContext: Context?) {
    @Serializable
    private data class LikeState(val likedByMe: Boolean, val likeCount: Int)

    @Serializable
    private data class StoredComment(
        val id: String,
        val postId: String,
        val parentId: String? = null,
        val authorId: String,
        val body: String,
        val likeCount: Int,
        val likedByMe: Boolean,
        val createdAt: String,
        val updatedAt: String,
        val displayName: String? = null,
        val username: String? = null,
        val avatarUrl: String? = null,
        val countryName: String? = null,
        val countryCode: String? = null,
    ) {
        constructor(from: PostComment) : this(
            id = from.id,
            postId = from.postId,
            parentId = from.parentId,
            authorId = from.authorId,
            body = from.body,
            likeCount = from.likeCount,
            likedByMe = from.likedByMe,
            createdAt = from.createdAt,
            updatedAt = from.updatedAt,
            displayName = from.author?.displayName,
            username = from.author?.username,
            avatarUrl = from.author?.avatarUrl,
            countryName = from.author?.countryName,
            countryCode = from.author?.countryCode,
        )

        fun toModel(): PostComment = PostComment(
            id = id,
            postId = postId,
            parentId = parentId,
            authorId = authorId,
            body = body,
            likeCount = likeCount,
            likedByMe = likedByMe,
            createdAt = createdAt,
            updatedAt = updatedAt,
            author = PostAuthor(
                userId = authorId,
                displayName = displayName ?: "You",
                username = username,
                avatarUrl = avatarUrl,
                countryName = countryName,
                countryCode = countryCode,
                lastReadAt = null,
            ),
        )
    }

    @Serializable
    private data class DiskPayload(
        val likes: Map<String, LikeState> = emptyMap(),
        val comments: Map<String, List<StoredComment>> = emptyMap(),
    )

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val prefs by lazy {
        appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    private var likes: MutableMap<String, LikeState> = mutableMapOf()
    private var comments: MutableMap<String, MutableList<PostComment>> = mutableMapOf()

    init {
        load()
    }

    fun applyLikeState(to: CountryPost): CountryPost {
        if (!isHubContentId(to.id)) return to
        val state = likes[to.id] ?: return to
        return to.copyEngagement(
            likedByMe = state.likedByMe,
            likeCount = state.likeCount,
            commentCount = to.commentCount,
        )
    }

    fun like(postId: String, baseLikeCount: Int) {
        val current = likes[postId]
        val wasLiked = current?.likedByMe ?: false
        val count = current?.likeCount ?: baseLikeCount
        likes[postId] = LikeState(
            likedByMe = true,
            likeCount = if (wasLiked) count else count + 1,
        )
        persist()
    }

    fun unlike(postId: String, baseLikeCount: Int) {
        val current = likes[postId]
        val wasLiked = current?.likedByMe ?: false
        val count = current?.likeCount ?: baseLikeCount
        likes[postId] = LikeState(
            likedByMe = false,
            likeCount = if (wasLiked) maxOf(0, count - 1) else count,
        )
        persist()
    }

    fun listComments(postId: String, limit: Int): List<PostComment> =
        (comments[postId] ?: emptyList()).take(maxOf(limit, 0))

    fun commentCount(postId: String, seed: Int = 0): Int =
        maxOf(seed, comments[postId]?.size ?: 0)

    fun addComment(
        postId: String,
        body: String,
        parentId: String?,
        author: PostAuthor?,
    ): PostComment {
        val now = isoNow()
        val userId = author?.userId
            ?: AuthService.instance.currentUser?.id
            ?: "local_user"
        val resolvedAuthor = author ?: PostAuthor(
            userId = userId,
            displayName = "You",
            username = "you",
            avatarUrl = null,
            countryName = null,
            countryCode = null,
            lastReadAt = null,
        )
        val comment = PostComment(
            id = "hub_cmt_${UUID.randomUUID()}",
            postId = postId,
            parentId = parentId,
            authorId = resolvedAuthor.userId,
            body = body.trim(),
            likeCount = 0,
            likedByMe = false,
            createdAt = now,
            updatedAt = now,
            author = resolvedAuthor,
        )
        comments.getOrPut(postId) { mutableListOf() }.add(comment)
        persist()
        return comment
    }

    fun likeComment(commentId: String): PostComment? = updateComment(commentId) { c ->
        c.copy(
            likeCount = if (c.likedByMe) c.likeCount else c.likeCount + 1,
            likedByMe = true,
        )
    }

    fun unlikeComment(commentId: String): PostComment? = updateComment(commentId) { c ->
        c.copy(
            likeCount = if (c.likedByMe) maxOf(0, c.likeCount - 1) else c.likeCount,
            likedByMe = false,
        )
    }

    private fun updateComment(
        commentId: String,
        transform: (PostComment) -> PostComment,
    ): PostComment? {
        for ((postId, list) in comments) {
            val index = list.indexOfFirst { it.id == commentId }
            if (index < 0) continue
            val updated = transform(list[index])
            list[index] = updated
            comments[postId] = list
            persist()
            return updated
        }
        return null
    }

    private fun load() {
        val raw = prefs?.getString(KEY, null) ?: return
        val payload = runCatching { json.decodeFromString<DiskPayload>(raw) }.getOrNull() ?: return
        likes = payload.likes.toMutableMap()
        comments = payload.comments.mapValues { (_, v) ->
            v.map { it.toModel() }.toMutableList()
        }.toMutableMap()
    }

    private fun persist() {
        val stored = comments.mapValues { (_, v) -> v.map { StoredComment(it) } }
        val payload = DiskPayload(likes = likes, comments = stored)
        prefs?.edit()?.putString(KEY, json.encodeToString(payload))?.apply()
    }

    private fun isoNow(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }

    companion object {
        private const val PREFS = "hub.engagement"
        private const val KEY = "hub.engagement.v1"

        @Volatile private var instance: HubEngagementStore? = null

        val shared: HubEngagementStore
            get() = instance ?: HubEngagementStore(null).also { instance = it }

        fun init(context: Context): HubEngagementStore {
            return instance ?: synchronized(this) {
                instance ?: HubEngagementStore(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): HubEngagementStore = init(context)

        fun isHubContentId(id: String): Boolean = usesLocalEngagement(postId = id)

        fun usesLocalEngagement(postId: String): Boolean {
            val id = postId.trim()
            if (id.isEmpty()) return true
            val lower = id.lowercase()
            if (lower.startsWith("ia_") ||
                lower.startsWith("hub_") ||
                lower.startsWith("archive_") ||
                lower.startsWith("post_") ||
                lower.startsWith("post_synth_") ||
                lower.startsWith("demo_") ||
                lower.startsWith("hub_cmt_") ||
                lower.startsWith("spark_") ||
                lower.contains("internet_archive") ||
                lower.contains("archive.org")
            ) {
                return true
            }
            // Comments share the same local-engagement rules as synthetic posts.
            if (lower.startsWith("local_cmt_")) return true
            if (runCatching { UUID.fromString(id) }.isSuccess) return false
            return true
        }
    }
}
