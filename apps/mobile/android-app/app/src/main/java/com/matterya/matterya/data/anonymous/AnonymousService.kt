package com.matterya.matterya.data.anonymous

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.model.AnonymousComment
import com.matterya.matterya.model.AnonymousCreateCommentInput
import com.matterya.matterya.model.AnonymousCreatePostInput
import com.matterya.matterya.model.AnonymousCreateSpaceInput
import com.matterya.matterya.model.AnonymousError
import com.matterya.matterya.model.AnonymousFeedSort
import com.matterya.matterya.model.AnonymousMembership
import com.matterya.matterya.model.AnonymousNotification
import com.matterya.matterya.model.AnonymousNotificationsPage
import com.matterya.matterya.model.AnonymousPage
import com.matterya.matterya.model.AnonymousPost
import com.matterya.matterya.model.AnonymousProfile
import com.matterya.matterya.model.AnonymousPublicProfilePayload
import com.matterya.matterya.model.AnonymousSearchResults
import com.matterya.matterya.model.AnonymousSession
import com.matterya.matterya.model.AnonymousSpace
import com.matterya.matterya.model.AnonymousSpaceAdmission
import com.matterya.matterya.model.AnonymousSpaceFilter
import com.matterya.matterya.model.AnonymousSpaceVisibility
import com.matterya.matterya.model.AnonymousVoteResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/**
 * REST client for /v1/anonymous — mirrors iOS AnonymousService.swift.
 * Base: [AppConfig.apiBaseURL] (https://api.matterya.com).
 */
object AnonymousService {
    const val feedPageLimit = 16
    const val feedSoftCap = 180
    const val feedPrefetchRemaining = 6
    const val spacePostsPageLimit = 16
    private const val feedFirstLimit = 16
    private const val timeoutSeconds = 45L

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val http = OkHttpClient.Builder()
        .connectTimeout(timeoutSeconds, TimeUnit.SECONDS)
        .readTimeout(timeoutSeconds, TimeUnit.SECONDS)
        .writeTimeout(timeoutSeconds, TimeUnit.SECONDS)
        .callTimeout(timeoutSeconds, TimeUnit.SECONDS)
        .build()
    private val JSON_MEDIA = "application/json".toMediaType()

    // MARK: - Session / identity

    suspend fun session(): AnonymousSession =
        get("/v1/anonymous/session") { parseSession(it) }

    suspend fun attest(): AnonymousSession =
        post("/v1/anonymous/attest", buildJsonObject { put("attest", true) }) { parseSession(it) }

    suspend fun claimProfile(username: String? = null): AnonymousProfile {
        val body = buildJsonObject {
            if (!username.isNullOrBlank()) put("username", username)
        }
        return post("/v1/anonymous/profile", body) { root ->
            val profileObj = root.obj("profile") ?: root
            parseProfile(profileObj) ?: throw AnonymousError.Decoding
        }
    }

    suspend fun me(): AnonymousProfile =
        get("/v1/anonymous/profile/me") { parseProfile(it) ?: throw AnonymousError.Decoding }

    suspend fun suggestUsername(): String {
        return get("/v1/anonymous/username/suggest") { root ->
            val u = root.str("username") ?: root.str("suggestedUsername") ?: root.str("suggested_username")
            if (u.isNullOrBlank()) throw AnonymousError.Server("No username suggestion available.")
            u
        }
    }

    // MARK: - Spaces

    suspend fun listSpaces(
        filter: AnonymousSpaceFilter = AnonymousSpaceFilter.ForYou,
        cursor: String? = null,
        limit: Int = 24,
    ): AnonymousPage<AnonymousSpace> {
        val q = mutableMapOf(
            "filter" to filter.rawValue,
            "limit" to "${limit.coerceIn(1, 48)}",
        )
        if (!cursor.isNullOrBlank()) q["cursor"] = cursor
        return getPage("/v1/anonymous/spaces", q, listOf("spaces", "items")) { parseSpace(it) }
    }

    suspend fun space(slug: String): AnonymousSpace {
        val encoded = URLEncoder.encode(slug, Charsets.UTF_8.name()).replace("+", "%20")
        return get("/v1/anonymous/spaces/$encoded") { parseSpace(it) ?: throw AnonymousError.Decoding }
    }

    suspend fun createSpace(input: AnonymousCreateSpaceInput): AnonymousSpace {
        val body = buildJsonObject {
            put("slug", input.slug)
            put("title", input.title)
            put("description", input.description)
            input.category?.let { put("category", it) }
            put("tags", JsonArray(input.tags.map { JsonPrimitive(it) }))
            put("rules", JsonArray(input.rules.map { JsonPrimitive(it) }))
            put("visibility", input.visibility)
            put("admission", input.admission)
        }
        return post("/v1/anonymous/spaces", body) { parseSpace(it) ?: throw AnonymousError.Decoding }
    }

    suspend fun join(spaceId: String): AnonymousMembership =
        post("/v1/anonymous/spaces/$spaceId/join", buildJsonObject {}) { parseMembership(it) }

    suspend fun leave(spaceId: String) {
        postAllowEmpty("/v1/anonymous/spaces/$spaceId/leave", buildJsonObject {})
    }

    // MARK: - Posts / comments

    suspend fun listPosts(
        spaceId: String,
        cursor: String? = null,
        sort: AnonymousFeedSort = AnonymousFeedSort.Hot,
        limit: Int = 24,
    ): AnonymousPage<AnonymousPost> {
        val q = mutableMapOf(
            "sort" to sort.rawValue,
            "limit" to "${limit.coerceIn(1, 48)}",
        )
        if (!cursor.isNullOrBlank()) q["cursor"] = cursor
        return getPage("/v1/anonymous/spaces/$spaceId/posts", q, listOf("posts", "items")) { parsePost(it) }
    }

    suspend fun createPost(spaceId: String, input: AnonymousCreatePostInput): AnonymousPost {
        val body = buildJsonObject {
            put("body", input.body)
            input.title?.trim()?.takeIf { it.isNotEmpty() }?.let { put("title", it) }
            input.mediaType?.trim()?.takeIf { it.isNotEmpty() }?.let {
                put("media_type", it)
                put("mediaType", it)
            }
            input.mediaURL?.trim()?.takeIf { it.isNotEmpty() }?.let {
                put("media_url", it)
                put("mediaUrl", it)
            }
            input.thumbURL?.trim()?.takeIf { it.isNotEmpty() }?.let {
                put("thumb_url", it)
                put("thumbUrl", it)
            }
        }
        return post("/v1/anonymous/spaces/$spaceId/posts", body) {
            parsePost(it) ?: throw AnonymousError.Decoding
        }
    }

    suspend fun getPost(id: String): AnonymousPost =
        get("/v1/anonymous/posts/$id") { parsePost(it) ?: throw AnonymousError.Decoding }

    suspend fun listComments(
        postId: String,
        cursor: String? = null,
        limit: Int = 500,
    ): AnonymousPage<AnonymousComment> {
        val q = mutableMapOf("limit" to "${limit.coerceIn(1, 500)}")
        if (!cursor.isNullOrBlank()) q["cursor"] = cursor
        return getPage(
            "/v1/anonymous/posts/$postId/comments",
            q,
            listOf("comments", "items"),
        ) { parseComment(it) }
    }

    suspend fun createComment(postId: String, input: AnonymousCreateCommentInput): AnonymousComment {
        val body = buildJsonObject {
            put("body", input.body)
            input.parentCommentId?.trim()?.takeIf { it.isNotEmpty() }?.let {
                put("parent_id", it)
            }
        }
        return post("/v1/anonymous/posts/$postId/comments", body) {
            parseComment(it) ?: throw AnonymousError.Decoding
        }
    }

    suspend fun vote(targetType: String, targetId: String, value: Int): AnonymousVoteResult {
        val body = buildJsonObject {
            put("target_type", targetType)
            put("target_id", targetId)
            put("value", value)
            put("targetType", targetType)
            put("targetId", targetId)
        }
        return postAllowEmpty("/v1/anonymous/votes", body) { root ->
            AnonymousVoteResult(
                value = root.int("value"),
                score = root.int("score"),
            )
        }
    }

    suspend fun report(targetType: String, targetId: String, reason: String) {
        val body = buildJsonObject {
            put("target_type", targetType)
            put("target_id", targetId)
            put("reason", reason)
            put("targetType", targetType)
            put("targetId", targetId)
        }
        postAllowEmpty("/v1/anonymous/reports", body)
    }

    suspend fun block(profileId: String) {
        val body = buildJsonObject {
            put("blocked_profile_id", profileId)
            put("blockedProfileId", profileId)
        }
        postAllowEmpty("/v1/anonymous/blocks", body)
    }

    suspend fun feed(
        sort: AnonymousFeedSort = AnonymousFeedSort.ForYou,
        cursor: String? = null,
        limit: Int? = null,
    ): AnonymousPage<AnonymousPost> {
        val resolved = (limit ?: feedFirstLimit).coerceIn(1, 50)
        val q = mutableMapOf(
            "sort" to sort.rawValue,
            "limit" to "$resolved",
        )
        if (!cursor.isNullOrBlank()) q["cursor"] = cursor
        return getPage("/v1/anonymous/feed", q, listOf("posts", "items")) { parsePost(it) }
    }

    suspend fun notifications(
        cursor: String? = null,
        limit: Int = 40,
    ): AnonymousNotificationsPage {
        val q = mutableMapOf("limit" to "${limit.coerceIn(1, 80)}")
        if (!cursor.isNullOrBlank()) q["cursor"] = cursor
        val root = getRaw("/v1/anonymous/notifications", q)
        val payload = root.obj("data") ?: root
        val rawItems = payload.arr("notifications") ?: payload.arr("items") ?: emptyList()
        val items = rawItems.mapNotNull { el -> el.jsonObjectOrNull()?.let { parseNotification(it) } }
        val cursorOut = payload.str("nextCursor") ?: payload.str("next_cursor")
        val unread = payload.int("unread_count")
            ?: payload.int("unreadCount")
            ?: items.count { it.isUnread }
        return AnonymousNotificationsPage(items = items, nextCursor = cursorOut, unreadCount = unread)
    }

    suspend fun markNotificationRead(id: String): Boolean {
        val trimmed = id.trim()
        if (trimmed.isEmpty()) return false
        return postAllowEmpty("/v1/anonymous/notifications/$trimmed/read", buildJsonObject {}) { root ->
            root.bool("updated") ?: root.bool("ok") ?: true
        }
    }

    suspend fun markAllNotificationsRead(): Int =
        postAllowEmpty("/v1/anonymous/notifications/read-all", buildJsonObject {}) { root ->
            root.int("updated") ?: 0
        }

    suspend fun search(query: String, limit: Int = 12): AnonymousSearchResults {
        val q = query.trim()
        if (q.isEmpty()) return AnonymousSearchResults()
        return get(
            "/v1/anonymous/search",
            mapOf("q" to q, "limit" to "${limit.coerceIn(1, 24)}"),
        ) { root ->
            val payload = root.obj("data") ?: root
            val people = (payload.arr("people") ?: payload.arr("profiles") ?: emptyList())
                .mapNotNull { it.jsonObjectOrNull()?.let(::parseProfile) }
            val spaces = (payload.arr("spaces") ?: emptyList())
                .mapNotNull { it.jsonObjectOrNull()?.let(::parseSpace) }
            val posts = (payload.arr("posts") ?: emptyList())
                .mapNotNull { it.jsonObjectOrNull()?.let(::parsePost) }
            AnonymousSearchResults(people = people, spaces = spaces, posts = posts)
        }
    }

    suspend fun publicProfile(username: String): AnonymousPublicProfilePayload {
        val handle = username.trim().trimStart('@')
        val encoded = URLEncoder.encode(handle, Charsets.UTF_8.name()).replace("+", "%20")
        return get("/v1/anonymous/profiles/$encoded") { root ->
            val payload = root.obj("data") ?: root
            val profile = payload.obj("profile")?.let(::parseProfile)
                ?: parseProfile(payload)
                ?: throw AnonymousError.Decoding
            AnonymousPublicProfilePayload(
                profile = profile,
                postCount = payload.int("postCount") ?: payload.int("post_count"),
                spaceCount = payload.int("spaceCount") ?: payload.int("space_count"),
            )
        }
    }

    suspend fun authorPosts(
        username: String,
        cursor: String? = null,
        limit: Int = 24,
    ): AnonymousPage<AnonymousPost> {
        val handle = username.trim().trimStart('@')
        val encoded = URLEncoder.encode(handle, Charsets.UTF_8.name()).replace("+", "%20")
        val q = mutableMapOf("limit" to "${limit.coerceIn(1, 48)}")
        if (!cursor.isNullOrBlank()) q["cursor"] = cursor
        return getPage("/v1/anonymous/profiles/$encoded/posts", q, listOf("posts", "items")) { parsePost(it) }
    }

    // MARK: - HTTP

    private suspend fun <T> get(
        path: String,
        query: Map<String, String>? = null,
        decode: (JsonObject) -> T,
    ): T = withContext(Dispatchers.IO) {
        val req = makeRequest(path, "GET", query, body = null)
        perform(req, decode)
    }

    private suspend fun <T> getPage(
        path: String,
        query: Map<String, String>,
        itemKeys: List<String>,
        parseItem: (JsonObject) -> T?,
    ): AnonymousPage<T> = withContext(Dispatchers.IO) {
        val root = getRaw(path, query)
        if (root.bool("ok") == false) {
            throw AnonymousError.from(root.str("code"), apiMessage(root))
        }
        val payload = root.obj("data") ?: root
        val rawItems = itemKeys.firstNotNullOfOrNull { payload.arr(it) } ?: emptyList()
        val items = rawItems.mapNotNull { el -> el.jsonObjectOrNull()?.let(parseItem) }
        val cursor = payload.str("nextCursor") ?: payload.str("next_cursor")
        AnonymousPage(items = items, nextCursor = cursor)
    }

    private suspend fun getRaw(path: String, query: Map<String, String>? = null): JsonObject =
        withContext(Dispatchers.IO) {
            val req = makeRequest(path, "GET", query, body = null)
            val (code, data) = execute(req)
            handleStatus(code, data)
            parseObject(data)
        }

    private suspend fun <T> post(
        path: String,
        body: JsonObject,
        decode: (JsonObject) -> T,
    ): T = withContext(Dispatchers.IO) {
        val req = makeRequest(path, "POST", null, body)
        perform(req, decode)
    }

    private suspend fun postAllowEmpty(path: String, body: JsonObject) {
        postAllowEmpty(path, body) { }
    }

    private suspend fun <T> postAllowEmpty(
        path: String,
        body: JsonObject,
        decode: (JsonObject) -> T,
    ): T = withContext(Dispatchers.IO) {
        val req = makeRequest(path, "POST", null, body)
        val (code, data) = execute(req)
        if (code in 200..299) {
            if (data.isBlank() || data.length < 3) {
                return@withContext decode(JsonObject(emptyMap()))
            }
            val root = parseObject(data)
            if (root.bool("ok") == false) {
                throw AnonymousError.from(root.str("code"), apiMessage(root))
            }
            return@withContext decode(unwrapPayload(root))
        }
        throw mapHttpError(code, data)
    }

    private fun <T> perform(request: Request, decode: (JsonObject) -> T): T {
        val (code, data) = execute(request)
        handleStatus(code, data)
        val root = parseObject(data)
        if (root.bool("ok") == false) {
            throw AnonymousError.from(root.str("code"), apiMessage(root))
        }
        // Try top-level, then nested resource keys.
        runCatching { return decode(root) }
        val payload = unwrapPayload(root)
        return decode(payload)
    }

    private fun unwrapPayload(root: JsonObject): JsonObject {
        root.obj("data")?.let { return it }
        for (key in listOf("session", "profile", "space", "post", "comment", "membership")) {
            root.obj(key)?.let { return it }
        }
        return root
    }

    private fun handleStatus(code: Int, data: String) {
        if (code in 200..299) return
        throw mapHttpError(code, data)
    }

    private fun mapHttpError(code: Int, data: String): AnonymousError {
        val root = runCatching { parseObject(data) }.getOrNull()
        val errCode = root?.str("code")
        val message = root?.let { apiMessage(it) }
        return when (code) {
            401, 403 -> AnonymousError.from(errCode ?: "forbidden", message)
            404 -> AnonymousError.NotFound
            409 -> AnonymousError.from(errCode ?: "username_taken", message)
            422 -> AnonymousError.from(errCode ?: "username_invalid", message)
            429 -> AnonymousError.RateLimited
            else -> AnonymousError.from(errCode, message ?: "HTTP $code")
        }
    }

    private fun execute(request: Request): Pair<Int, String> {
        return try {
            http.newCall(request).execute().use { resp ->
                resp.code to (resp.body?.string().orEmpty())
            }
        } catch (e: Exception) {
            throw AnonymousError.Network(e.message)
        }
    }

    private suspend fun makeRequest(
        path: String,
        method: String,
        query: Map<String, String>?,
        body: JsonObject?,
    ): Request {
        val base = "${AppConfig.apiBaseURL}$path".toHttpUrl().newBuilder()
        query?.forEach { (k, v) -> base.addQueryParameter(k, v) }
        val token = try {
            AuthService.instance.ensureValidToken()
        } catch (_: Exception) {
            throw AnonymousError.Network("Sign in again to open Masquerade.")
        }
        val builder = Request.Builder()
            .url(base.build())
            .header("Accept", "application/json")
            .header("Authorization", "Bearer $token")
        if (body != null) {
            builder.header("Content-Type", "application/json")
            builder.method(method, body.toString().toRequestBody(JSON_MEDIA))
        } else {
            builder.method(method, null)
        }
        return builder.build()
    }

    private fun parseObject(raw: String): JsonObject {
        if (raw.isBlank()) return JsonObject(emptyMap())
        return try {
            json.parseToJsonElement(raw).jsonObject
        } catch (_: Exception) {
            throw AnonymousError.Decoding
        }
    }

    private fun apiMessage(json: JsonObject): String? =
        json.str("reason") ?: json.str("message") ?: json.str("error")

    // MARK: - Parsers

    private fun parseSession(root: JsonObject): AnonymousSession {
        val payload = root.obj("data") ?: root.obj("session") ?: root
        val code = payload.str("code")
        val eligible = payload.bool("eligibleAdult")
            ?: payload.bool("eligible_adult")
            ?: payload.bool("eligible")
            ?: false
        val ageAttested = payload.bool("ageAttested")
            ?: payload.bool("age_attested")
            ?: false
        val birthdateMissing = payload.bool("birthdateMissing")
            ?: payload.bool("birthdate_missing")
            ?: (code == "birthdate_required" || code == "birthdate_missing" || code == "under_18")
        val profile = payload.obj("profile")?.let(::parseProfile)
        val suspended = payload.bool("suspended")
            ?: (profile?.state?.equals("suspended", ignoreCase = true) == true || code == "suspended")
        return AnonymousSession(
            eligibleAdult = eligible,
            ageAttested = ageAttested,
            birthdateMissing = birthdateMissing,
            suspended = suspended,
            profile = profile,
            suggestedUsername = payload.str("suggestedUsername") ?: payload.str("suggested_username"),
            privacyNoticeVersion = payload.str("privacyNoticeVersion")
                ?: payload.str("privacy_notice_version"),
            gateCode = code,
        )
    }

    private fun parseProfile(obj: JsonObject): AnonymousProfile? {
        val id = obj.str("id") ?: return null
        val username = obj.str("username") ?: return null
        return AnonymousProfile(
            id = id,
            username = username,
            avatarSeed = obj.str("avatarSeed") ?: obj.str("avatar_seed"),
            createdAt = obj.str("createdAt") ?: obj.str("created_at"),
            state = obj.str("state"),
        )
    }

    private fun parseSpace(obj: JsonObject): AnonymousSpace? {
        val id = obj.str("id") ?: return null
        val slug = obj.str("slug") ?: return null
        val title = obj.str("title") ?: return null
        val rules = obj.arr("rules")?.mapNotNull { it.jsonPrimitiveOrNull()?.contentOrNull }
        return AnonymousSpace(
            id = id,
            slug = slug,
            title = title,
            description = obj.str("description"),
            category = obj.str("category"),
            tags = obj.arr("tags")?.mapNotNull { it.jsonPrimitiveOrNull()?.contentOrNull },
            visibility = AnonymousSpaceVisibility.fromRaw(obj.str("visibility")),
            admission = AnonymousSpaceAdmission.fromRaw(obj.str("admission")),
            memberCount = obj.int("memberCount") ?: obj.int("member_count"),
            postCount = obj.int("postCount") ?: obj.int("post_count"),
            ownerUsername = obj.str("ownerUsername") ?: obj.str("owner_username"),
            rules = rules,
            isJoined = obj.bool("isJoined") ?: obj.bool("is_joined") ?: obj.bool("joined"),
            isOwner = obj.bool("isOwner") ?: obj.bool("is_owner"),
            isModerator = obj.bool("isModerator") ?: obj.bool("is_moderator"),
            priceCurrency = obj.str("priceCurrency") ?: obj.str("price_currency"),
            priceAmountMinor = obj.int("priceAmountMinor") ?: obj.int("price_amount_minor"),
            billingPeriod = obj.str("billingPeriod") ?: obj.str("billing_period"),
            status = obj.str("status"),
        )
    }

    private fun parseMembership(obj: JsonObject): AnonymousMembership {
        val payload = obj.obj("data") ?: obj.obj("membership") ?: obj
        val spaceId = payload.str("spaceId") ?: payload.str("space_id") ?: ""
        val id = payload.str("id") ?: spaceId
        return AnonymousMembership(
            id = id,
            spaceId = spaceId,
            state = payload.str("state") ?: "active",
            role = payload.str("role"),
            joinedAt = payload.str("joinedAt") ?: payload.str("joined_at"),
        )
    }

    private fun parsePost(obj: JsonObject): AnonymousPost? {
        val id = obj.str("id") ?: return null
        val spaceId = obj.str("spaceId") ?: obj.str("space_id") ?: return null
        val author = obj.obj("author")
        var flagged = obj.bool("flagged")
        val flaggedAt = obj.str("flaggedAt") ?: obj.str("flagged_at")
        if (flagged == null && !flaggedAt.isNullOrEmpty()) flagged = true
        return AnonymousPost(
            id = id,
            spaceId = spaceId,
            spaceSlug = obj.str("spaceSlug") ?: obj.str("space_slug"),
            spaceTitle = obj.str("spaceTitle") ?: obj.str("space_title"),
            authorUsername = obj.str("authorUsername")
                ?: obj.str("author_username")
                ?: author?.str("username")
                ?: "anonymous",
            authorProfileId = obj.str("authorProfileId")
                ?: obj.str("author_profile_id")
                ?: author?.str("id")
                ?: "",
            title = obj.str("title"),
            body = obj.str("body") ?: "",
            createdAt = obj.str("createdAt") ?: obj.str("created_at") ?: "",
            editedAt = obj.str("editedAt") ?: obj.str("edited_at"),
            score = obj.int("score"),
            commentCount = obj.int("commentCount") ?: obj.int("comment_count"),
            myVote = obj.int("myVote") ?: obj.int("my_vote"),
            isPinned = obj.bool("isPinned") ?: obj.bool("is_pinned"),
            isLocked = obj.bool("isLocked") ?: obj.bool("is_locked"),
            mediaType = obj.str("mediaType") ?: obj.str("media_type"),
            mediaURL = obj.str("mediaURL") ?: obj.str("media_url") ?: obj.str("mediaUrl"),
            thumbURL = obj.str("thumbURL") ?: obj.str("thumb_url") ?: obj.str("thumbUrl"),
            flagged = flagged,
            flaggedAt = flaggedAt,
            flagReason = obj.str("flagReason") ?: obj.str("flag_reason"),
        )
    }

    private fun parseComment(obj: JsonObject): AnonymousComment? {
        val id = obj.str("id") ?: return null
        val author = obj.obj("author")
        val replies = obj.arr("replies")?.mapNotNull {
            it.jsonObjectOrNull()?.let(::parseComment)
        }
        return AnonymousComment(
            id = id,
            postId = obj.str("postId") ?: obj.str("post_id") ?: "",
            parentCommentId = obj.str("parentCommentId")
                ?: obj.str("parent_comment_id")
                ?: obj.str("parent_id"),
            authorUsername = obj.str("authorUsername")
                ?: obj.str("author_username")
                ?: author?.str("username")
                ?: "anonymous",
            authorProfileId = obj.str("authorProfileId")
                ?: obj.str("author_profile_id")
                ?: author?.str("id")
                ?: "",
            body = obj.str("body") ?: "",
            createdAt = obj.str("createdAt") ?: obj.str("created_at") ?: "",
            depth = obj.int("depth"),
            score = obj.int("score"),
            myVote = obj.int("myVote") ?: obj.int("my_vote"),
            replies = replies,
        )
    }

    private fun parseNotification(obj: JsonObject): AnonymousNotification? {
        val id = obj.str("id") ?: return null
        return AnonymousNotification(
            id = id,
            kind = obj.str("kind"),
            title = obj.str("title"),
            body = obj.str("body"),
            spaceId = obj.str("spaceId") ?: obj.str("space_id"),
            spaceTitle = obj.str("spaceTitle") ?: obj.str("space_title"),
            postId = obj.str("postId") ?: obj.str("post_id"),
            actorUsername = obj.str("actorUsername") ?: obj.str("actor_username"),
            createdAt = obj.str("createdAt") ?: obj.str("created_at"),
            readAt = obj.str("readAt") ?: obj.str("read_at"),
        )
    }
}

// --- JsonObject helpers ---

private fun JsonObject.str(key: String): String? =
    (this[key] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }

private fun JsonObject.int(key: String): Int? {
    val p = this[key] as? JsonPrimitive ?: return null
    return p.contentOrNull?.toIntOrNull() ?: p.content.toIntOrNull()
}

private fun JsonObject.bool(key: String): Boolean? {
    val p = this[key] as? JsonPrimitive ?: return null
    return when {
        p.contentOrNull == "true" -> true
        p.contentOrNull == "false" -> false
        else -> p.content.toBooleanStrictOrNull()
    }
}

private fun JsonObject.obj(key: String): JsonObject? =
    this[key] as? JsonObject

private fun JsonObject.arr(key: String): List<JsonElement>? =
    (this[key] as? JsonArray)?.toList()

private fun JsonElement.jsonObjectOrNull(): JsonObject? = this as? JsonObject

private fun JsonElement.jsonPrimitiveOrNull(): JsonPrimitive? = this as? JsonPrimitive
