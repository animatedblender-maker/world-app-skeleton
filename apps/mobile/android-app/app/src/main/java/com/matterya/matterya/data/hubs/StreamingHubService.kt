package com.matterya.matterya.data.hubs

import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.posts.ProfileService
import com.matterya.matterya.data.social.FollowService
import com.matterya.matterya.model.ConnectedAccount
import com.matterya.matterya.model.ConnectedHubContent
import com.matterya.matterya.model.ConnectedHubSnapshot
import com.matterya.matterya.model.FriendActivity
import com.matterya.matterya.model.MomentComment
import com.matterya.matterya.model.MomentRoom
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.StreamingPlatform
import com.matterya.matterya.model.YourNowPlaying
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/** iOS `StreamingHubService.swift`. */
class StreamingHubService(
    private val followService: FollowService = FollowService(),
    private val profileService: ProfileService = ProfileService(),
    private val rest: SupabaseRestClient = SupabaseRestClient.shared,
    private val auth: AuthService = AuthService.instance,
) {
    private val nowPlayingTtlMs = TimeUnit.MINUTES.toMillis(30)

    suspend fun loadHub(): ConnectedHubSnapshot = coroutineScope {
        val connections = async { fetchConnections() }
        val nowPlaying = async { fetchMyNowPlaying() }
        val friends = async { fetchFriendsActivity() }
        val mine = nowPlaying.await()
        val friendsList = friends.await()
        val rooms = buildMomentRooms(mine, friendsList)
        ConnectedHubSnapshot(
            accounts = ConnectedHubContent.mergedAccounts(connections.await()),
            nowPlaying = mine,
            friends = friendsList,
            momentRooms = rooms,
        )
    }

    suspend fun linkPlatform(platform: StreamingPlatform): ConnectedAccount {
        val userId = currentUserId()
        val now = isoNow()
        val rows = rest.upsert(
            table = "streaming_platform_connections",
            rows = listOf(
                mapOf(
                    "user_id" to JsonPrimitive(userId),
                    "platform" to JsonPrimitive(platform.apiSlug),
                    "is_linked" to JsonPrimitive(true),
                    "sharing_enabled" to JsonPrimitive(true),
                    "linked_at" to JsonPrimitive(now),
                    "updated_at" to JsonPrimitive(now),
                ),
            ),
            onConflict = "user_id,platform",
        )
        val first = rows.firstOrNull()?.jsonObject
        return ConnectedAccount(
            id = platform.rawValue,
            platform = platform,
            isLinked = first?.get("is_linked")?.jsonPrimitive?.booleanOrNull ?: true,
            sharingEnabled = first?.get("sharing_enabled")?.jsonPrimitive?.booleanOrNull ?: true,
        )
    }

    suspend fun unlinkPlatform(platform: StreamingPlatform) {
        val userId = currentUserId()
        rest.patchVoid(
            table = "streaming_platform_connections",
            filters = mapOf(
                "user_id" to "eq.$userId",
                "platform" to "eq.${platform.apiSlug}",
            ),
            body = mapOf(
                "is_linked" to JsonPrimitive(false),
                "sharing_enabled" to JsonPrimitive(false),
                "updated_at" to JsonPrimitive(isoNow()),
            ),
        )
        rest.delete(
            table = "now_playing_status",
            filters = mapOf(
                "user_id" to "eq.$userId",
                "platform" to "eq.${platform.apiSlug}",
            ),
        )
    }

    suspend fun setPlatformSharing(platform: StreamingPlatform, enabled: Boolean): ConnectedAccount {
        val userId = currentUserId()
        val now = isoNow()
        val rows = rest.upsert(
            table = "streaming_platform_connections",
            rows = listOf(
                mapOf(
                    "user_id" to JsonPrimitive(userId),
                    "platform" to JsonPrimitive(platform.apiSlug),
                    "is_linked" to JsonPrimitive(true),
                    "sharing_enabled" to JsonPrimitive(enabled),
                    "linked_at" to JsonPrimitive(now),
                    "updated_at" to JsonPrimitive(now),
                ),
            ),
            onConflict = "user_id,platform",
        )
        rest.patchVoid(
            table = "now_playing_status",
            filters = mapOf(
                "user_id" to "eq.$userId",
                "platform" to "eq.${platform.apiSlug}",
            ),
            body = mapOf(
                "is_sharing" to JsonPrimitive(enabled),
                "updated_at" to JsonPrimitive(now),
            ),
        )
        val first = rows.firstOrNull()?.jsonObject
        return ConnectedAccount(
            id = platform.rawValue,
            platform = platform,
            isLinked = first?.get("is_linked")?.jsonPrimitive?.booleanOrNull ?: true,
            sharingEnabled = first?.get("sharing_enabled")?.jsonPrimitive?.booleanOrNull ?: enabled,
        )
    }

    suspend fun fetchFriendsActivityOnly(): List<FriendActivity> = fetchFriendsActivity()

    suspend fun updateNowPlaying(
        platform: StreamingPlatform,
        title: String,
        subtitle: String?,
        momentLabel: String?,
        progressMinutes: Int,
        progressSeconds: Int,
        durationMinutes: Int,
        isSharing: Boolean,
        contentId: String? = null,
    ): YourNowPlaying {
        val progressMs = (progressMinutes * 60 + progressSeconds) * 1000
        val durationMs = maxOf(durationMinutes * 60 * 1000, progressMs + 60_000)
        return updateNowPlaying(
            platform = platform,
            title = title,
            subtitle = subtitle,
            momentLabel = momentLabel,
            progressMs = progressMs,
            durationMs = durationMs,
            isSharing = isSharing,
            contentId = contentId,
        )
    }

    suspend fun updateNowPlaying(
        platform: StreamingPlatform,
        title: String,
        subtitle: String?,
        momentLabel: String?,
        progressMs: Int,
        durationMs: Int,
        isSharing: Boolean,
        contentId: String? = null,
    ): YourNowPlaying {
        val userId = currentUserId()
        val now = isoNow()
        linkPlatform(platform)
        val row = mutableMapOf<String, JsonElement>(
            "user_id" to JsonPrimitive(userId),
            "platform" to JsonPrimitive(platform.apiSlug),
            "title" to JsonPrimitive(title),
            "progress_ms" to JsonPrimitive(progressMs),
            "duration_ms" to JsonPrimitive(durationMs),
            "is_sharing" to JsonPrimitive(isSharing),
            "updated_at" to JsonPrimitive(now),
        )
        if (!subtitle.isNullOrEmpty()) row["subtitle"] = JsonPrimitive(subtitle)
        if (!momentLabel.isNullOrEmpty()) row["moment_label"] = JsonPrimitive(momentLabel)
        if (!contentId.isNullOrEmpty()) row["content_id"] = JsonPrimitive(contentId)

        val rows = rest.upsert(
            table = "now_playing_status",
            rows = listOf(row),
            onConflict = "user_id,platform",
        )
        val saved = rows.firstOrNull()?.jsonObject
            ?: throw StreamingHubError.SaveFailed
        return parseNowPlaying(saved)
            ?: throw StreamingHubError.SaveFailed ?: throw StreamingHubError.SaveFailed
    }

    suspend fun clearNowPlaying(platform: StreamingPlatform) {
        val userId = currentUserId()
        rest.delete(
            table = "now_playing_status",
            filters = mapOf(
                "user_id" to "eq.$userId",
                "platform" to "eq.${platform.apiSlug}",
            ),
        )
    }

    suspend fun momentRoomComments(roomKey: String): List<MomentComment> {
        val userId = currentUserId()
        val rows = rest.select(
            table = "moment_room_comments",
            filters = mapOf(
                "room_key" to "eq.$roomKey",
                "order" to "created_at.asc",
                "limit" to "50",
            ),
        )
        return mapComments(rows.map { it.jsonObject }, userId)
    }

    suspend fun addMomentRoomComment(roomKey: String, body: String): MomentComment {
        val userId = currentUserId()
        val trimmed = body.trim()
        if (trimmed.isEmpty()) throw StreamingHubError.EmptyComment
        val rows = rest.insert(
            table = "moment_room_comments",
            rows = listOf(
                mapOf(
                    "room_key" to JsonPrimitive(roomKey),
                    "author_id" to JsonPrimitive(userId),
                    "body" to JsonPrimitive(trimmed),
                ),
            ),
        )
        val saved = rows.firstOrNull()?.jsonObject
            ?: throw StreamingHubError.SaveFailed
        return mapComments(listOf(saved), userId).first()
    }

    private fun currentUserId(): String =
        auth.currentUser?.id ?: throw StreamingHubError.NotAuthenticated

    private suspend fun fetchConnections(): List<ConnectedAccount> {
        val userId = currentUserId()
        val rows = rest.select(
            table = "streaming_platform_connections",
            filters = mapOf("user_id" to "eq.$userId"),
        )
        return rows.mapNotNull { el ->
            val o = el.jsonObject
            val slug = o["platform"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val platform = StreamingPlatform.fromApiSlug(slug) ?: return@mapNotNull null
            ConnectedAccount(
                id = platform.rawValue,
                platform = platform,
                isLinked = o["is_linked"]?.jsonPrimitive?.booleanOrNull ?: false,
                sharingEnabled = o["sharing_enabled"]?.jsonPrimitive?.booleanOrNull ?: false,
            )
        }
    }

    private suspend fun fetchMyNowPlaying(): List<YourNowPlaying> {
        val userId = currentUserId()
        val rows = rest.select(
            table = "now_playing_status",
            filters = mapOf(
                "user_id" to "eq.$userId",
                "order" to "updated_at.desc",
            ),
        )
        return rows.mapNotNull { parseNowPlaying(it.jsonObject) }
    }

    private suspend fun fetchFriendsActivity(): List<FriendActivity> {
        val following = followService.followingIds().filter { !it.startsWith("user_") }
        if (following.isEmpty()) return emptyList()
        val cutoff = isoCutoff()
        val idList = following.sorted().joinToString(",")
        val rows = rest.select(
            table = "now_playing_status",
            filters = mapOf(
                "user_id" to "in.($idList)",
                "is_sharing" to "eq.true",
                "updated_at" to "gte.$cutoff",
                "order" to "updated_at.desc",
                "limit" to "20",
            ),
        )
        val activities = mutableListOf<FriendActivity>()
        for (el in rows) {
            val o = el.jsonObject
            val userId = o["user_id"]?.jsonPrimitive?.contentOrNull ?: continue
            val profile = runCatching { profileService.profileById(userId) }.getOrNull() ?: continue
            val isLive = fetchIsLive(userId)
            activities.add(toFriendActivity(o, profile, isLive))
        }
        return activities
    }

    private suspend fun fetchIsLive(userId: String): Boolean {
        val rows = runCatching {
            rest.select(
                table = "user_presence",
                filters = mapOf(
                    "user_id" to "eq.$userId",
                    "select" to "is_online,last_seen_at",
                    "limit" to "1",
                ),
            )
        }.getOrNull() ?: return false
        val row = rows.firstOrNull()?.jsonObject ?: return false
        if (row["is_online"]?.jsonPrimitive?.booleanOrNull != true) return false
        val lastSeen = row["last_seen_at"]?.jsonPrimitive?.contentOrNull ?: return false
        val date = parseIso(lastSeen) ?: return false
        return System.currentTimeMillis() - date.time < 70_000
    }

    private suspend fun buildMomentRooms(
        mine: List<YourNowPlaying>,
        friends: List<FriendActivity>,
    ): List<MomentRoom> {
        @Suppress("UNUSED_VARIABLE")
        val unused = mine to friends
        val userId = currentUserId()
        val following = followService.followingIds().filter { !it.startsWith("user_") }
        val cutoff = isoCutoff()
        val filters = mutableMapOf(
            "is_sharing" to "eq.true",
            "updated_at" to "gte.$cutoff",
            "order" to "updated_at.desc",
        )
        var orClause = "user_id.eq.$userId"
        if (following.isNotEmpty()) {
            val idList = following.sorted().joinToString(",")
            orClause += ",user_id.in.($idList)"
        }
        filters["or"] = "($orClause)"

        val rows = rest.select(table = "now_playing_status", filters = filters)
        data class RoomAgg(
            val roomKey: String,
            val platform: String,
            val showTitle: String,
            val episodeLabel: String,
            val timestampLabel: String,
            var activeFriends: Int,
        )
        val roomMap = linkedMapOf<String, RoomAgg>()
        for (el in rows) {
            val o = el.jsonObject
            if (o["is_sharing"]?.jsonPrimitive?.booleanOrNull != true) continue
            val platform = o["platform"]?.jsonPrimitive?.contentOrNull ?: continue
            val title = o["title"]?.jsonPrimitive?.contentOrNull ?: continue
            val subtitle = o["subtitle"]?.jsonPrimitive?.contentOrNull
            val progressMs = o["progress_ms"]?.jsonPrimitive?.intOrNull ?: 0
            val built = StreamingHubRoomKey.build(platform, title, subtitle, progressMs)
            val existing = roomMap[built.roomKey]
            if (existing != null) {
                existing.activeFriends += 1
            } else {
                roomMap[built.roomKey] = RoomAgg(
                    roomKey = built.roomKey,
                    platform = platform,
                    showTitle = title,
                    episodeLabel = subtitle ?: "Now playing",
                    timestampLabel = built.timestampLabel,
                    activeFriends = 1,
                )
            }
        }

        val sorted = roomMap.values.sortedByDescending { it.activeFriends }.take(12)
        val rooms = mutableListOf<MomentRoom>()
        for (agg in sorted) {
            val commentRows = rest.select(
                table = "moment_room_comments",
                filters = mapOf(
                    "room_key" to "eq.${agg.roomKey}",
                    "order" to "created_at.desc",
                    "limit" to "3",
                ),
            )
            val comments = mapComments(
                commentRows.map { it.jsonObject }.reversed(),
                userId,
            )
            val heat = minOf(1.0, agg.activeFriends / 15.0 + comments.size / 10.0)
            val platform = StreamingPlatform.fromApiSlug(agg.platform) ?: StreamingPlatform.Netflix
            rooms.add(
                MomentRoom(
                    id = agg.roomKey,
                    roomKey = agg.roomKey,
                    platform = platform,
                    showTitle = agg.showTitle,
                    episodeLabel = agg.episodeLabel,
                    timestamp = agg.timestampLabel,
                    activeFriends = agg.activeFriends,
                    previewComments = comments,
                    heat = heat,
                ),
            )
        }
        return rooms
    }

    private suspend fun mapComments(
        rows: List<kotlinx.serialization.json.JsonObject>,
        viewerId: String,
    ): List<MomentComment> {
        val results = mutableListOf<MomentComment>()
        for (row in rows) {
            val authorId = row["author_id"]?.jsonPrimitive?.contentOrNull ?: continue
            val author = when {
                authorId == viewerId -> "You"
                else -> {
                    val profile = runCatching { profileService.profileById(authorId) }.getOrNull()
                    profile?.displayName ?: profile?.username ?: "Friend"
                }
            }
            results.add(
                MomentComment(
                    id = row["id"]?.jsonPrimitive?.contentOrNull ?: continue,
                    author = author,
                    body = row["body"]?.jsonPrimitive?.contentOrNull ?: "",
                    reactions = row["reactions"]?.jsonPrimitive?.intOrNull ?: 0,
                ),
            )
        }
        return results
    }

    private fun parseNowPlaying(o: kotlinx.serialization.json.JsonObject): YourNowPlaying? {
        val platformSlug = o["platform"]?.jsonPrimitive?.contentOrNull ?: return null
        val platform = StreamingPlatform.fromApiSlug(platformSlug) ?: StreamingPlatform.Netflix
        val progressMs = o["progress_ms"]?.jsonPrimitive?.intOrNull ?: 0
        val durationMs = maxOf(o["duration_ms"]?.jsonPrimitive?.intOrNull ?: 1, 1)
        val progress = (progressMs.toDouble() / durationMs.toDouble()).coerceIn(0.0, 1.0)
        return YourNowPlaying(
            id = o["id"]?.jsonPrimitive?.contentOrNull ?: return null,
            platform = platform,
            title = o["title"]?.jsonPrimitive?.contentOrNull ?: "",
            subtitle = o["subtitle"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            progressLabel = StreamingHubRoomKey.formatTimestamp(progressMs),
            progress = progress,
            isSharing = o["is_sharing"]?.jsonPrimitive?.booleanOrNull ?: false,
            momentLabel = o["moment_label"]?.jsonPrimitive?.contentOrNull,
            contentId = o["content_id"]?.jsonPrimitive?.contentOrNull,
            progressMs = progressMs,
            durationMs = durationMs,
            updatedAt = parseIso(o["updated_at"]?.jsonPrimitive?.contentOrNull) ?: Date(),
        )
    }

    private fun toFriendActivity(
        o: kotlinx.serialization.json.JsonObject,
        profile: Profile,
        isLive: Boolean,
    ): FriendActivity {
        val platformSlug = o["platform"]?.jsonPrimitive?.contentOrNull ?: "netflix"
        val platform = StreamingPlatform.fromApiSlug(platformSlug) ?: StreamingPlatform.Netflix
        val progressMs = o["progress_ms"]?.jsonPrimitive?.intOrNull ?: 0
        val stamp = StreamingHubRoomKey.formatTimestamp(progressMs)
        val subtitle = o["subtitle"]?.jsonPrimitive?.contentOrNull
        val detail = subtitle?.let { "$it · $stamp" } ?: stamp
        val isSharing = o["is_sharing"]?.jsonPrimitive?.booleanOrNull ?: false
        return FriendActivity(
            id = o["user_id"]?.jsonPrimitive?.contentOrNull ?: profile.userId,
            name = profile.displayName ?: profile.username ?: "Friend",
            avatarUrl = profile.avatarUrl,
            avatarSeed = o["user_id"]?.jsonPrimitive?.contentOrNull ?: profile.userId,
            platform = platform,
            title = o["title"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            subtitle = subtitle.orEmpty(),
            detail = detail,
            isLive = isLive && isSharing,
            contentId = o["content_id"]?.jsonPrimitive?.contentOrNull,
            progressMs = progressMs,
            durationMs = o["duration_ms"]?.jsonPrimitive?.intOrNull ?: 0,
            updatedAt = parseIso(o["updated_at"]?.jsonPrimitive?.contentOrNull) ?: Date(),
        )
    }

    private fun isoNow(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }

    private fun isoCutoff(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date(System.currentTimeMillis() - nowPlayingTtlMs))
    }

    private fun parseIso(value: String?): Date? {
        if (value.isNullOrBlank()) return null
        val formats = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
        )
        for (pattern in formats) {
            val fmt = SimpleDateFormat(pattern, Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("UTC")
            runCatching { fmt.parse(value) }.getOrNull()?.let { return it }
        }
        return null
    }

    companion object {
        val shared by lazy { StreamingHubService() }
    }
}

object StreamingHubRoomKey {
    data class Built(val roomKey: String, val timestampLabel: String)

    fun build(
        platform: String,
        title: String,
        subtitle: String?,
        progressMs: Int,
    ): Built {
        val bucketSizeMs = if (platform == "apple_music") 10_000 else 60_000
        val bucketMs = maxOf(0, progressMs / bucketSizeMs) * bucketSizeMs
        fun slug(value: String): String =
            value.lowercase()
                .replace(Regex("[^a-z0-9]+"), "-")
                .trim('-')
                .take(48)
        val roomKey = "$platform:${slug(title)}:${slug(subtitle.orEmpty())}:$bucketMs"
        return Built(roomKey, formatTimestamp(bucketMs))
    }

    fun formatTimestamp(progressMs: Int): String {
        val totalSec = maxOf(0, progressMs / 1000)
        return String.format("%d:%02d", totalSec / 60, totalSec % 60)
    }
}

sealed class StreamingHubError(message: String) : Exception(message) {
    data object NotAuthenticated : StreamingHubError("Please sign in again.")
    data object SaveFailed : StreamingHubError("Could not save your streaming status.")
    data object EmptyComment : StreamingHubError("Write a comment before sending.")
}
