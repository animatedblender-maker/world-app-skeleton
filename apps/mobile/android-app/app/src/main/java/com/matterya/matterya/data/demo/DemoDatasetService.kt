package com.matterya.matterya.data.demo

import android.content.Context
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.search.MatteryaSearchEngine
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.PostAuthor
import com.matterya.matterya.model.PostComment
import com.matterya.matterya.model.RelativeTime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * iOS `DemoDatasetService.swift`.
 * Respects [AppConfig.useDemoDataset] = false (returns empty by default).
 */
class DemoDatasetService private constructor(
    private val appContext: Context?,
) {
    private val mutex = Mutex()
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    private var posts: List<CountryPost> = emptyList()
    private var postsByCountry: Map<String, List<CountryPost>> = emptyMap()
    private var postsByAuthor: Map<String, List<CountryPost>> = emptyMap()
    private var commentsByPost: MutableMap<String, MutableList<PostComment>> = mutableMapOf()
    private var authorCountry: Map<String, Pair<String?, String?>> = emptyMap()
    private var loaded = false

    suspend fun listByCountry(code: String, limit: Int): List<CountryPost> {
        ensureLoaded()
        val slice = postsByCountry[code.uppercase()].orEmpty()
        return slice.take(limit)
    }

    suspend fun listForAuthor(authorId: String, limit: Int): List<CountryPost> {
        ensureLoaded()
        return postsByAuthor[authorId].orEmpty().take(limit)
    }

    suspend fun searchPosts(query: String, limit: Int): List<CountryPost> {
        ensureLoaded()
        return MatteryaSearchEngine.rankContent(posts, query, limit)
    }

    suspend fun getPostById(id: String): CountryPost? {
        ensureLoaded()
        return posts.firstOrNull { it.id == id }
    }

    suspend fun isDemoPostId(id: String): Boolean {
        ensureLoaded()
        return posts.any { it.id == id }
    }

    suspend fun sampleGlobalPosts(limit: Int): List<CountryPost> {
        ensureLoaded()
        return posts.take(limit)
    }

    suspend fun listComments(postId: String, limit: Int): List<PostComment> {
        ensureLoaded()
        return (commentsByPost[postId] ?: emptyList()).take(limit)
    }

    suspend fun seededCommentCount(forPostId: String): Int {
        ensureLoaded()
        return commentsByPost[forPostId]?.size ?: 0
    }

    suspend fun addComment(postId: String, body: String, parentId: String?): PostComment {
        ensureLoaded()
        val authorId = "demo_local"
        val now = isoNow()
        val comment = PostComment(
            id = "cmt_local_${UUID.randomUUID()}",
            postId = postId,
            parentId = parentId,
            authorId = authorId,
            body = body,
            likeCount = 0,
            likedByMe = false,
            createdAt = now,
            updatedAt = now,
            author = PostAuthor(
                userId = authorId,
                displayName = "You",
                username = "you",
                avatarUrl = null,
                countryName = null,
                countryCode = null,
                lastReadAt = null,
            ),
        )
        commentsByPost.getOrPut(postId) { mutableListOf() }.add(comment)
        posts = posts.map { p ->
            if (p.id != postId) p
            else p.copyEngagement(
                likedByMe = p.likedByMe,
                likeCount = p.likeCount,
                commentCount = commentsByPost[postId]?.size ?: 0,
            )
        }
        return comment
    }

    suspend fun likeComment(commentId: String): PostComment? = mutex.withLock {
        updateComment(commentId) { c ->
            c.copy(
                likeCount = if (c.likedByMe) c.likeCount else c.likeCount + 1,
                likedByMe = true,
            )
        }
    }

    suspend fun unlikeComment(commentId: String): PostComment? = mutex.withLock {
        updateComment(commentId) { c ->
            c.copy(
                likeCount = if (c.likedByMe) maxOf(0, c.likeCount - 1) else c.likeCount,
                likedByMe = false,
            )
        }
    }

    private fun updateComment(
        commentId: String,
        transform: (PostComment) -> PostComment,
    ): PostComment? {
        for ((postId, list) in commentsByPost) {
            val index = list.indexOfFirst { it.id == commentId }
            if (index < 0) continue
            val updated = transform(list[index])
            list[index] = updated
            commentsByPost[postId] = list
            return updated
        }
        return null
    }

    private suspend fun ensureLoaded() = mutex.withLock {
        if (loaded) return
        loaded = true

        // Production flag: demo dataset off.
        if (!AppConfig.useDemoDataset) {
            posts = emptyList()
            commentsByPost = mutableMapOf()
            return
        }

        val seed = withContext(Dispatchers.IO) { loadBundledSeedTexts() }
        val postsText: String
        val commentsText: String
        if (seed != null) {
            postsText = seed.first
            commentsText = seed.second
        } else if (AppConfig.demoDatasetAllowRemoteDownload) {
            val remote = withContext(Dispatchers.IO) {
                runCatching {
                    val postsUrl = "${AppConfig.demoDatasetBaseURL}/demo_social_dataset_30k/posts.jsonl"
                    val commentsUrl = "${AppConfig.demoDatasetBaseURL}/demo_social_dataset_30k/comments.jsonl"
                    val p = http.newCall(Request.Builder().url(postsUrl).build()).execute()
                        .body?.string().orEmpty()
                    val c = http.newCall(Request.Builder().url(commentsUrl).build()).execute()
                        .body?.string().orEmpty()
                    p to c
                }.getOrNull()
            }
            if (remote == null) {
                posts = emptyList()
                commentsByPost = mutableMapOf()
                return
            }
            postsText = remote.first
            commentsText = remote.second
        } else {
            posts = emptyList()
            commentsByPost = mutableMapOf()
            return
        }

        val maxPosts = maxOf(24, AppConfig.demoDatasetMaxPosts)
        val parsed = parseSeed(postsText, commentsText, maxPosts)
        posts = parsed.posts
        postsByCountry = parsed.postsByCountry
        postsByAuthor = parsed.postsByAuthor
        commentsByPost = parsed.commentsByPost.mapValues { it.value.toMutableList() }.toMutableMap()
        authorCountry = parsed.authorCountry
    }

    private fun loadBundledSeedTexts(): Pair<String, String>? {
        val candidates = mutableListOf<Pair<File, File>>()
        val monoRoots = listOf(
            "/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton/demo_social_dataset_30k",
            "/Users/animated/Development/world-app-skeleton/demo_social_dataset_30k",
        )
        for (root in monoRoots) {
            val p = File(root, "posts.jsonl")
            val c = File(root, "comments.jsonl")
            if (p.exists() && c.exists()) candidates.add(p to c)
        }
        appContext?.let { ctx ->
            for (name in listOf("demo_social_seed/posts.jsonl", "posts.jsonl")) {
                val postsAsset = runCatching {
                    ctx.assets.open(name).bufferedReader().use { it.readText() }
                }.getOrNull()
                val commentsName = name.replace("posts.jsonl", "comments.jsonl")
                val commentsAsset = runCatching {
                    ctx.assets.open(commentsName).bufferedReader().use { it.readText() }
                }.getOrNull()
                if (postsAsset != null && commentsAsset != null && postsAsset.isNotEmpty()) {
                    return postsAsset to commentsAsset
                }
            }
        }

        val ranked = candidates.mapNotNull { (p, c) ->
            val size = p.length().toInt()
            if (size > 100) Triple(p, c, size) else null
        }.sortedByDescending { it.third }

        for ((postsFile, commentsFile, _) in ranked) {
            val postsText = runCatching { postsFile.readText() }.getOrNull() ?: continue
            val commentsText = runCatching { commentsFile.readText() }.getOrNull() ?: continue
            if (postsText.isEmpty()) continue
            return postsText to commentsText
        }
        return null
    }

    private data class ParsedSeed(
        val posts: List<CountryPost>,
        val postsByCountry: Map<String, List<CountryPost>>,
        val postsByAuthor: Map<String, List<CountryPost>>,
        val commentsByPost: Map<String, List<PostComment>>,
        val authorCountry: Map<String, Pair<String?, String?>>,
    )

    private fun parseSeed(postsText: String, commentsText: String, maxPosts: Int): ParsedSeed {
        var postRows = parseJsonl(postsText)
        val expandWindow = minOf(postRows.size, maxOf(maxPosts * 4, maxPosts))
        if (postRows.size > expandWindow) postRows = postRows.take(expandWindow)

        val authorCountryMap = mutableMapOf<String, Pair<String?, String?>>()
        for (row in postRows) {
            val authorId = DemoPersonNames.normalizeAuthorId(row.str("author_id") ?: "user_unknown")
            val code = row.str("country_code")?.uppercase()
            val name = row.str("country_name")
            if (authorId !in authorCountryMap) {
                authorCountryMap[authorId] = name to code
            }
        }

        val keepIds = postRows.mapNotNull { it.str("id") }.toSet()
        val rawCommentsByPost = mutableMapOf<String, MutableList<PostComment>>()
        for (row in parseJsonl(commentsText)) {
            val comment = mapDemoComment(row, authorCountryMap) ?: continue
            if (comment.postId !in keepIds) continue
            rawCommentsByPost.getOrPut(comment.postId) { mutableListOf() }.add(comment)
        }
        for (key in rawCommentsByPost.keys) {
            rawCommentsByPost[key] = rawCommentsByPost[key]!!.sortedBy { it.createdAt }.toMutableList()
        }

        val allMappedPosts = postRows.map { row ->
            val id = row.str("id") ?: UUID.randomUUID().toString()
            mapDemoPost(row, commentCount = rawCommentsByPost[id]?.size ?: 0)
        }

        val utteranceAuthorByBody = mutableMapOf<String, Pair<String, PostAuthor?>>()
        for (post in allMappedPosts) {
            val key = normalizeThreadBody(post.body)
            if (key.isEmpty() || key in utteranceAuthorByBody) continue
            utteranceAuthorByBody[key] = post.authorId to post.author
        }

        val rebuilt = rebuildConversationThreads(
            allPosts = allMappedPosts,
            rawCommentsByPost = rawCommentsByPost,
            utteranceAuthorByBody = utteranceAuthorByBody,
            maxRootPosts = maxPosts,
        )

        val byCountry = mutableMapOf<String, MutableList<CountryPost>>()
        val byAuthor = mutableMapOf<String, MutableList<CountryPost>>()
        for (post in rebuilt.first) {
            val code = post.countryCode?.uppercase() ?: "XX"
            byCountry.getOrPut(code) { mutableListOf() }.add(post)
            byAuthor.getOrPut(post.authorId) { mutableListOf() }.add(post)
        }
        for (key in byCountry.keys) {
            byCountry[key] = byCountry[key]!!.sortedByDescending {
                RelativeTime.parseDate(it.createdAt)?.epochSecond ?: 0L
            }.toMutableList()
        }

        return ParsedSeed(
            posts = rebuilt.first,
            postsByCountry = byCountry,
            postsByAuthor = byAuthor,
            commentsByPost = rebuilt.second,
            authorCountry = authorCountryMap,
        )
    }

    private fun rebuildConversationThreads(
        allPosts: List<CountryPost>,
        rawCommentsByPost: Map<String, List<PostComment>>,
        utteranceAuthorByBody: Map<String, Pair<String, PostAuthor?>>,
        maxRootPosts: Int,
    ): Pair<List<CountryPost>, Map<String, List<PostComment>>> {
        val bodyToPostId = mutableMapOf<String, String>()
        val postById = linkedMapOf<String, CountryPost>()
        for (post in allPosts.sortedBy { it.id }) {
            postById[post.id] = post
            val key = normalizeThreadBody(post.body)
            if (key.isNotEmpty() && key !in bodyToPostId) bodyToPostId[key] = post.id
        }

        val replyPostIds = mutableSetOf<String>()
        for (comments in rawCommentsByPost.values) {
            for (comment in comments) {
                val key = normalizeThreadBody(comment.body)
                bodyToPostId[key]?.let { replyPostIds.add(it) }
            }
        }

        val rootCandidates = allPosts
            .filter { it.id !in replyPostIds }
            .sortedByDescending { RelativeTime.parseDate(it.createdAt)?.epochSecond ?: 0L }
        val roots = rootCandidates.take(maxOf(1, maxRootPosts))

        val expandedByRoot = mutableMapOf<String, List<PostComment>>()
        for (root in roots) {
            val visiting = mutableSetOf<String>()
            val seenCommentIds = mutableSetOf<String>()
            val tree = expandComments(
                postId = root.id,
                rootPostId = root.id,
                reparentTo = null,
                rawCommentsByPost = rawCommentsByPost,
                bodyToPostId = bodyToPostId,
                postById = postById,
                visiting = visiting,
                seenCommentIds = seenCommentIds,
            )
            expandedByRoot[root.id] = stabilizeThreadAuthors(root, tree, utteranceAuthorByBody)
        }

        val posts = roots.map { root ->
            val count = expandedByRoot[root.id]?.size ?: 0
            root.copyEngagement(
                likedByMe = root.likedByMe,
                likeCount = root.likeCount,
                commentCount = count,
            )
        }
        return posts to expandedByRoot
    }

    private fun expandComments(
        postId: String,
        rootPostId: String,
        reparentTo: String?,
        rawCommentsByPost: Map<String, List<PostComment>>,
        bodyToPostId: Map<String, String>,
        postById: Map<String, CountryPost>,
        visiting: MutableSet<String>,
        seenCommentIds: MutableSet<String>,
    ): List<PostComment> {
        if (!visiting.add(postId)) return emptyList()
        try {
            val out = mutableListOf<PostComment>()
            val raw = rawCommentsByPost[postId].orEmpty()
            for (comment in raw) {
                if (!seenCommentIds.add(comment.id)) continue
                val parentId = if (reparentTo != null && comment.parentId == null) reparentTo else comment.parentId
                var remapped = comment.withPostAndParent(rootPostId, parentId)
                val key = normalizeThreadBody(comment.body)
                val linkedPostId = bodyToPostId[key]
                val linkedPost = linkedPostId?.let { postById[it] }
                if (linkedPost != null) {
                    remapped = remapped.withAuthor(linkedPost.authorId, linkedPost.author)
                }
                out.add(remapped)
                if (linkedPostId != null && linkedPostId != postId && linkedPostId != rootPostId) {
                    out.addAll(
                        expandComments(
                            postId = linkedPostId,
                            rootPostId = rootPostId,
                            reparentTo = comment.id,
                            rawCommentsByPost = rawCommentsByPost,
                            bodyToPostId = bodyToPostId,
                            postById = postById,
                            visiting = visiting,
                            seenCommentIds = seenCommentIds,
                        ),
                    )
                }
            }
            return out
        } finally {
            visiting.remove(postId)
        }
    }

    private fun stabilizeThreadAuthors(
        root: CountryPost,
        comments: List<PostComment>,
        utteranceAuthorByBody: Map<String, Pair<String, PostAuthor?>>,
    ): List<PostComment> {
        if (comments.isEmpty()) return comments
        val opId = DemoPersonNames.normalizeAuthorId(root.authorId)
        val opAuthor = root.author ?: DemoPersonNames.author(
            id = opId,
            countryName = root.countryName,
            countryCode = root.countryCode,
        )
        val partnerId = stablePartnerAuthorId(root.id)
        val partnerAuthor = DemoPersonNames.author(
            id = partnerId,
            countryName = root.countryName,
            countryCode = root.countryCode,
        )
        val ordered = comments.sortedBy { it.createdAt }
        val speakerOfComment = mutableMapOf<String, String>()
        val rewritten = mutableMapOf<String, PostComment>()
        for (comment in ordered) {
            val bodyKey = normalizeThreadBody(comment.body)
            val utterance = utteranceAuthorByBody[bodyKey]
            val speakerId: String
            val speakerAuthor: PostAuthor?
            when {
                utterance != null -> {
                    speakerId = DemoPersonNames.normalizeAuthorId(utterance.first)
                    speakerAuthor = utterance.second ?: DemoPersonNames.author(
                        id = speakerId,
                        countryName = root.countryName,
                        countryCode = root.countryCode,
                    )
                }
                comment.parentId != null && speakerOfComment[comment.parentId] != null -> {
                    val parentSpeaker = speakerOfComment[comment.parentId]!!
                    if (parentSpeaker == opId) {
                        speakerId = partnerId
                        speakerAuthor = partnerAuthor
                    } else {
                        speakerId = opId
                        speakerAuthor = opAuthor
                    }
                }
                else -> {
                    speakerId = partnerId
                    speakerAuthor = partnerAuthor
                }
            }
            speakerOfComment[comment.id] = speakerId
            rewritten[comment.id] = comment.withAuthor(speakerId, speakerAuthor)
        }
        return comments.mapNotNull { rewritten[it.id] }
    }

    private fun stablePartnerAuthorId(rootPostId: String): String {
        val seed = hashSeed("partner|$rootPostId")
        val number = (seed % 90_000uL).toInt() + 1_000
        return String.format("user_%06d", number)
    }

    private fun mapDemoPost(row: JsonObject, commentCount: Int): CountryPost {
        val media = row["media"]?.jsonObject
        val authorId = DemoPersonNames.normalizeAuthorId(row.str("author_id") ?: "user_unknown")
        val countryCode = (row.str("country_code") ?: "XX").uppercase()
        val body = normalizeBody(row.str("body").orEmpty(), countryCode)
        val createdAt = row.str("created_at") ?: isoNow()
        val seed = hashSeed(row.str("id") ?: authorId)
        return CountryPost(
            id = row.str("id") ?: UUID.randomUUID().toString(),
            title = row.str("title"),
            body = body,
            mediaType = media?.str("type"),
            mediaUrl = media?.str("url"),
            thumbUrl = media?.str("thumb_url"),
            mediaCaption = null,
            sharedPostId = null,
            visibility = "public",
            likeCount = (seed % 420uL).toInt() + 3,
            commentCount = commentCount,
            viewCount = (seed % 5000uL).toInt() + 50,
            likedByMe = false,
            savedByMe = false,
            createdAt = createdAt,
            updatedAt = createdAt,
            authorId = authorId,
            countryName = row.str("country_name"),
            countryCode = countryCode,
            cityName = null,
            author = DemoPersonNames.author(
                id = authorId,
                countryName = row.str("country_name"),
                countryCode = countryCode,
            ),
        )
    }

    private fun mapDemoComment(
        row: JsonObject,
        authorCountry: Map<String, Pair<String?, String?>>,
    ): PostComment? {
        val id = row.str("id")?.takeIf { it.isNotEmpty() } ?: return null
        val postId = row.str("post_id")?.takeIf { it.isNotEmpty() } ?: return null
        val body = row.str("body") ?: return null
        val authorId = DemoPersonNames.normalizeAuthorId(row.str("author_id") ?: "user_unknown")
        val createdAt = row.str("created_at") ?: isoNow()
        val country = authorCountry[authorId]
        val seed = hashSeed(id)
        return PostComment(
            id = id,
            postId = postId,
            parentId = row.str("parent_id"),
            authorId = authorId,
            body = body,
            likeCount = (seed % 24uL).toInt(),
            likedByMe = false,
            createdAt = createdAt,
            updatedAt = createdAt,
            author = DemoPersonNames.author(
                id = authorId,
                countryName = country?.first,
                countryCode = country?.second,
            ),
        )
    }

    private fun parseJsonl(text: String): List<JsonObject> =
        text.lineSequence().mapNotNull { line ->
            val trimmed = line.trim()
            if (trimmed.isEmpty()) return@mapNotNull null
            runCatching { json.parseToJsonElement(trimmed).jsonObject }.getOrNull()
        }.toList()

    private fun normalizeThreadBody(body: String): String =
        body.trim().replace(Regex("\\s+"), " ").lowercase()

    private fun normalizeBody(body: String, countryCode: String): String {
        val prefix = "[$countryCode] "
        return if (body.startsWith(prefix)) body.removePrefix(prefix) else body
    }

    private fun hashSeed(value: String): ULong {
        var hash = 2166136261uL
        for (byte in value.encodeToByteArray()) {
            hash = hash xor byte.toUByte().toULong()
            hash *= 16777619uL
        }
        return hash
    }

    private fun isoNow(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }

    private fun JsonObject.str(key: String): String? =
        this[key]?.jsonPrimitive?.contentOrNull

    companion object {
        @Volatile private var instance: DemoDatasetService? = null

        val shared: DemoDatasetService
            get() = instance ?: DemoDatasetService(null).also { instance = it }

        fun init(context: Context): DemoDatasetService {
            return instance ?: synchronized(this) {
                instance ?: DemoDatasetService(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): DemoDatasetService = init(context)
    }
}
