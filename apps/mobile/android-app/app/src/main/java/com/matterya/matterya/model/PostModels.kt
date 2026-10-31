package com.matterya.matterya.model

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.media.MediaUrlResolver
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import java.time.Instant
import java.util.UUID
import kotlin.math.max

@Serializable
enum class PostVisibility {
    @SerialName("public")
    PUBLIC,

    @SerialName("followers")
    FOLLOWERS,

    @SerialName("private")
    PRIVATE,

    @SerialName("country")
    COUNTRY,
    ;

    val rawValue: String
        get() = when (this) {
            PUBLIC -> "public"
            FOLLOWERS -> "followers"
            PRIVATE -> "private"
            COUNTRY -> "country"
        }

    companion object {
        fun fromRaw(raw: String?): PostVisibility {
            return when (raw?.trim()?.lowercase()) {
                "followers" -> FOLLOWERS
                "private" -> PRIVATE
                "country" -> COUNTRY
                else -> PUBLIC
            }
        }
    }
}

@Serializable
data class PostAuthor(
    @SerialName("user_id") val userId: String = "",
    @SerialName("display_name") val displayName: String? = null,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("country_name") val countryName: String? = null,
    @SerialName("country_code") val countryCode: String? = null,
    @SerialName("last_read_at") val lastReadAt: String? = null,
    @SerialName("is_verified") val isVerified: Boolean? = null,
) {
    val id: String get() = userId

    val displayLabel: String
        get() = ContentSanitizer.displayName(displayName, username)

    val showsVerifiedBadge: Boolean
        get() = isVerified == true || username?.trim()?.equals("matterya", ignoreCase = true) == true
}

data class PostMediaPayload(
    val urls: List<String>,
    val types: List<String>,
    val isReel: Boolean = false,
    val isStory: Boolean = false,
    val expiresAt: Instant? = null,
) {
    val primaryUrl: String? get() = urls.firstOrNull()
    val primaryType: String? get() = types.firstOrNull()

    companion object {
        private val json = Json { ignoreUnknownKeys = true; isLenient = true }

        fun parse(fromMediaUrl: String?): PostMediaPayload? {
            val raw = fromMediaUrl?.trim().orEmpty()
            if (raw.isEmpty()) return null

            if (raw.startsWith("{") || raw.startsWith("[")) {
                val element = runCatching { json.parseToJsonElement(raw) }.getOrNull() ?: return null

                if (element is JsonArray) {
                    val urls = element.mapNotNull { it.jsonPrimitive.contentOrNull }
                        .filter { it.isNotEmpty() }
                    if (urls.isEmpty()) return null
                    return PostMediaPayload(
                        urls = urls,
                        types = urls.map { inferMediaType(it) },
                        isReel = false,
                        isStory = false,
                        expiresAt = null,
                    )
                }

                val obj = element as? JsonObject ?: return null

                val urls: List<String> = when {
                    obj["urls"] is JsonArray ->
                        obj["urls"]!!.jsonArray.mapNotNull { it.jsonPrimitive.contentOrNull }
                            .filter { it.isNotEmpty() }
                    else -> {
                        val single = obj["url"]?.jsonPrimitive?.contentOrNull
                        if (!single.isNullOrEmpty()) listOf(single) else emptyList()
                    }
                }

                val types: List<String> = run {
                    val list = (obj["types"] as? JsonArray)
                        ?.mapNotNull { it.jsonPrimitive.contentOrNull }
                        .orEmpty()
                    when {
                        list.isEmpty() -> urls.map { inferMediaType(it) }
                        list.size == urls.size -> list
                        else -> urls.mapIndexed { index, url ->
                            if (index < list.size && list[index].isNotEmpty()) list[index]
                            else inferMediaType(url)
                        }
                    }
                }

                val reel = boolValue(obj["reel"])
                val story = boolValue(obj["story"])
                val expiresAt = parseDate(obj["expires_at"]?.jsonPrimitive?.contentOrNull)
                return PostMediaPayload(
                    urls = urls,
                    types = types,
                    isReel = reel,
                    isStory = story,
                    expiresAt = expiresAt,
                )
            }

            return PostMediaPayload(
                urls = listOf(raw),
                types = listOf(inferMediaType(raw)),
                isReel = false,
                isStory = false,
                expiresAt = null,
            )
        }

        fun encode(
            urls: List<String>,
            types: List<String>,
            reel: Boolean = false,
            story: Boolean = false,
            expiresAt: Instant? = null,
        ): String? {
            if (urls.isEmpty()) return null
            val obj = buildJsonObject {
                putJsonArray("urls") { urls.forEach { add(JsonPrimitive(it)) } }
                putJsonArray("types") { types.forEach { add(JsonPrimitive(it)) } }
                if (reel) put("reel", true)
                if (story) put("story", true)
                if (expiresAt != null) {
                    put("expires_at", DateTimeFormatterIso.format(expiresAt))
                }
            }
            return obj.toString()
        }

        private fun boolValue(value: kotlinx.serialization.json.JsonElement?): Boolean {
            if (value == null) return false
            val prim = value as? JsonPrimitive ?: return false
            prim.booleanOrNull?.let { return it }
            prim.intOrNull?.let { return it != 0 }
            prim.doubleOrNull?.let { return it != 0.0 }
            val text = prim.contentOrNull?.trim()?.lowercase().orEmpty()
            return text == "true" || text == "1" || text == "yes"
        }

        private fun parseDate(value: String?): Instant? {
            if (value.isNullOrEmpty()) return null
            return RelativeTime.parseDate(value)
        }

        private fun inferMediaType(fromUrl: String): String {
            val lower = fromUrl.lowercase()
            if (Regex("""\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)""").containsMatchIn(lower) ||
                lower.contains("/video") ||
                lower.contains("video%")
            ) {
                return "video"
            }
            return "image"
        }

        private object DateTimeFormatterIso {
            fun format(instant: Instant): String = instant.toString()
        }
    }
}

@Serializable
data class SharedPostPreview(
    val id: String = "",
    val title: String? = null,
    val body: String = "",
    @SerialName("media_type") val mediaType: String? = null,
    @SerialName("media_url") val mediaUrl: String? = null,
    @SerialName("thumb_url") val thumbUrl: String? = null,
    @SerialName("author_id") val authorId: String = "",
    val author: PostAuthor? = null,
    /** Origin thread size — share rows often have 0 local comments while origin has the full R2 set. */
    @SerialName("comment_count") val commentCount: Int = 0,
    @SerialName("like_count") val likeCount: Int = 0,
    /** Preserved so hub-seed shares still resolve as Hubs content in the feed. */
    @SerialName("external_ref_type") val externalRefType: String? = null,
    @SerialName("external_ref_id") val externalRefId: String? = null,
) {
    val asCountryPost: CountryPost
        get() = CountryPost(
            id = id,
            title = title,
            body = body,
            mediaType = mediaType,
            mediaUrl = mediaUrl,
            thumbUrl = thumbUrl,
            likeCount = likeCount,
            commentCount = commentCount,
            createdAt = "",
            updatedAt = "",
            authorId = authorId,
            author = author,
            externalRefType = externalRefType,
            externalRefId = externalRefId,
        )

    val displayExcerpt: String get() = asCountryPost.displayExcerpt
    val hasMedia: Boolean get() = asCountryPost.hasMedia
    val hasVideo: Boolean get() = asCountryPost.hasVideo
    val feedImageUrl: String? get() = asCountryPost.feedImageUrl

    val authorDisplayName: String
        get() = ContentSanitizer.displayName(
            displayName = author?.displayName,
            username = author?.username,
        )
}

@Serializable
data class CountryPost(
    val id: String = "",
    val title: String? = null,
    val body: String = "",
    @SerialName("media_type") val mediaType: String? = null,
    @SerialName("media_url") val mediaUrl: String? = null,
    @SerialName("thumb_url") val thumbUrl: String? = null,
    @SerialName("media_caption") val mediaCaption: String? = null,
    @SerialName("shared_post_id") val sharedPostId: String? = null,
    @SerialName("shared_post") val sharedPost: SharedPostPreview? = null,
    val visibility: String = "public",
    @SerialName("like_count") val likeCount: Int = 0,
    @SerialName("comment_count") val commentCount: Int = 0,
    @SerialName("view_count") val viewCount: Int = 0,
    @SerialName("liked_by_me") val likedByMe: Boolean = false,
    @SerialName("saved_by_me") val savedByMe: Boolean = false,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
    @SerialName("author_id") val authorId: String = "",
    @SerialName("country_name") val countryName: String? = null,
    @SerialName("country_code") val countryCode: String? = null,
    @SerialName("city_name") val cityName: String? = null,
    val author: PostAuthor? = null,
    @SerialName("link_url") val linkUrl: String? = null,
    @SerialName("link_title") val linkTitle: String? = null,
    @SerialName("external_ref_type") val externalRefType: String? = null,
    @SerialName("external_ref_id") val externalRefId: String? = null,
) {
    val visibilityEnum: PostVisibility get() = PostVisibility.fromRaw(visibility)

    val createdDate: Instant? get() = RelativeTime.parseDate(createdAt)
    val updatedDate: Instant? get() = RelativeTime.parseDate(updatedAt)

    val isEdited: Boolean
        get() {
            val created = createdDate ?: return false
            val updated = updatedDate ?: return false
            return updated.epochSecond - created.epochSecond > 1
        }

    val privacyLabel: String
        get() = when (visibilityEnum) {
            PostVisibility.PUBLIC -> "Public"
            PostVisibility.FOLLOWERS -> "Followers"
            PostVisibility.PRIVATE -> "Only me"
            PostVisibility.COUNTRY -> "Country"
        }

    /**
     * Feed/share cards: use the fuller of local + origin thread sizes.
     * Spark/hub *shares* often store 0 comments on the share row while R2 comments live on the origin.
     */
    val displayCommentCount: Int
        get() = max(
            commentCount,
            max(
                sharedPost?.commentCount ?: 0,
                sharedPost?.asCountryPost?.commentCount ?: 0,
            ),
        )

    val displayLikeCount: Int
        get() = max(likeCount, sharedPost?.likeCount ?: 0)

    /** Origin post for comments / engagement (spark share sid, shared_post_id, or embed id). */
    val originPostId: String?
        get() = SparkShareMarker.originId(body)
            ?: HubOriginShareMarker.parseFields(body)?.get("sid")
            ?: sharedPostId
            ?: sharedPost?.id

    /** Stamp media_type when Keep from Sparks player so profile Saved Sparks keeps the row. */
    fun withMediaTypeForSave(type: String): CountryPost = copy(mediaType = type)

    fun withSavedByMe(saved: Boolean): CountryPost = copy(savedByMe = saved)

    fun copyEngagement(
        likedByMe: Boolean = this.likedByMe,
        likeCount: Int = this.likeCount,
        commentCount: Int = this.commentCount,
        savedByMe: Boolean = this.savedByMe,
    ): CountryPost = copy(
        likedByMe = likedByMe,
        likeCount = likeCount,
        commentCount = commentCount,
        savedByMe = savedByMe,
    )

    val primaryMediaUrl: String?
        get() = resolvedMediaUrls.firstOrNull() ?: mediaUrl ?: thumbUrl

    val hasVideo: Boolean
        get() {
            val type = (mediaType ?: "").lowercase()
            if (type == "video" || type == "reel") return true
            if (mediaPayload?.types?.any { it.lowercase() == "video" } == true) return true
            val url = primaryMediaUrl?.lowercase() ?: return false
            return Regex("""\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)""").containsMatchIn(url) ||
                url.contains("/video") ||
                url.contains("video%")
        }

    val hasImage: Boolean
        get() {
            if (hasVideo || isStory || isReel) return false
            val type = (mediaType ?: "").lowercase()
            if (type == "image") return primaryMediaUrl != null
            if (mediaPayload?.types?.any { it.lowercase() == "image" } == true) return true
            return hasMedia && !hasVideo
        }

    val hasMedia: Boolean
        get() {
            if (isStory || isReel) return primaryMediaUrl != null
            val type = (mediaType ?: "").lowercase()
            return type != "none" && type != "" && primaryMediaUrl != null
        }

    val isDemoPost: Boolean get() = authorId.startsWith("user_")

    /** Seeded Reddit / hub catalog / synthetic rows — not a live Matterya member post. */
    val isSeededOrSynthetic: Boolean
        get() {
            if (isDemoPost || isHubSeedVideo) return true
            val pid = id.lowercase()
            val aid = authorId.lowercase()
            if (pid.startsWith("post_") || pid.startsWith("demo_") ||
                pid.startsWith("ia_") || pid.startsWith("hub_")
            ) {
                return true
            }
            if (aid.startsWith("user_") || aid.startsWith("hub_") || aid.startsWith("hub_spark_")) {
                return true
            }
            return false
        }

    /** Live people on Matterya (GraphQL / Supabase) — feed should surface these first. */
    val isRealPersonFeedPost: Boolean
        get() = !isSeededOrSynthetic && !isStory && !isSpark

    val mediaPayload: PostMediaPayload? get() = PostMediaPayload.parse(mediaUrl)

    val resolvedMediaUrls: List<String>
        get() {
            val payload = mediaPayload
            if (payload != null && payload.urls.isNotEmpty()) return payload.urls
            if (!mediaUrl.isNullOrEmpty()) return listOf(mediaUrl)
            return emptyList()
        }

    /**
     * True only for **original** Sparks (short vertical reels) — never long-form,
     * hub watch videos, or **feed shares** of Sparks (`SparkShareMarker`).
     */
    val isReel: Boolean
        get() {
            if (SparkShareMarker.isMarked(body)) return false
            val type = (mediaType ?: "").lowercase()
            if (type == "reel" || type == "spark") return true
            if (mediaPayload?.isReel == true) return true
            if (mediaUrl != null) {
                val normalized = mediaUrl.lowercase()
                if (normalized.contains("\"reel\":true") || normalized.contains("\"reel\": true")) {
                    return true
                }
            }
            if (bodyHasSparkMarker(body)) return true
            return false
        }

    /** Feed card should render Spark chrome without being a swipe-pool Spark. */
    val isSparkFeedShare: Boolean
        get() = SparkShareMarker.isMarked(body) ||
            (sharedPost?.asCountryPost?.isReel == true)

    val isStory: Boolean
        get() {
            if (body.contains("__story__|")) return true
            if ((mediaType ?: "").lowercase() == "story") return true
            return mediaPayload?.isStory == true
        }

    /** Sparks belong in the vertical sparks scroll only — not the home feed or profile grids. */
    val isSpark: Boolean get() = isReel

    /** Cloudflare R2 focus packs — preferred Sparks source. */
    val isR2HostedMedia: Boolean
        get() {
            val media = (mediaUrl ?: "").lowercase()
            if (media.contains("r2.cloudflarestorage.com")) return true
            if (media.contains("matterya-sparks")) return true
            if (media.contains("\"r2_key\"") || media.contains("r2_key")) return true
            if (media.contains("r2_focus_seed") || media.contains("r2_spark")) return true
            if (media.contains("\"source\":\"r2")) return true
            val thumb = (thumbUrl ?: "").lowercase()
            if (thumb.contains("r2.cloudflarestorage.com") || thumb.contains("matterya-sparks")) {
                return true
            }
            return false
        }

    /** Internet Archive / local hub seed catalog — lowest priority in Sparks player. */
    val isArchiveSparkSource: Boolean
        get() {
            if (isHubSeedVideo) return true
            if (HubArchiveIdentity.isArchiveChannelAuthor(authorId)) return true
            val postId = id.lowercase()
            if (postId.startsWith("ia_") || postId.startsWith("hub_spark_")) return true
            if (ArchiveCatalogMedia.isArchiveCatalogMedia(this)) return true
            return false
        }

    val storyExpiresAt: Instant?
        get() {
            mediaPayload?.expiresAt?.let { return it }
            PostStoryMarker.expiresAt(body)?.let { return it }
            if (!isStory) return null
            val created = createdDate ?: return null
            return created.plusSeconds(86_400)
        }

    val isStoryActive: Boolean
        get() {
            if (!isStory) return false
            val expiresAt = storyExpiresAt ?: return true
            return expiresAt.isAfter(Instant.now())
        }

    val displayTitle: String? get() = ContentSanitizer.clean(title)

    val displayBody: String get() = ContentSanitizer.clean(body) ?: ""

    val displayCaption: String?
        get() {
            if (isReel || isSparkFeedShare) {
                val fromBody = displayBody
                if (fromBody.isNotEmpty()) return fromBody
                val origin = sharedPost?.asCountryPost
                if (origin != null) {
                    val originBody = origin.displayBody
                    if (originBody.isNotEmpty()) return originBody
                    origin.displayTitle?.let { return it }
                    ContentSanitizer.clean(origin.mediaCaption)?.takeIf { it.isNotEmpty() }?.let { return it }
                }
                ContentSanitizer.clean(mediaCaption)?.let { return it }
                return null
            }
            return ContentSanitizer.clean(mediaCaption)
        }

    /** Caption line for Sparks player / feed Spark cards — R2 meta text, never seeder fluff. */
    val sparkDisplayCaption: String?
        get() {
            displayCaption?.takeIf { it.isNotEmpty() }?.let { return it }
            if (isSparkFeedShare) {
                val origin = sharedPost?.asCountryPost
                if (origin != null) {
                    origin.displayCaption?.takeIf { it.isNotEmpty() }?.let { return it }
                    origin.displayTitle?.let { return it }
                }
            }
            return displayHeadline
        }

    /** Feed share of a Hubs channel video (`__hub_origin__|…`). */
    val isHubOriginFeedShare: Boolean get() = HubOriginShareMarker.isMarked(body)

    val displayHeadline: String?
        get() {
            displayTitle?.let { return it }
            if (isSparkFeedShare) {
                val origin = sharedPost?.asCountryPost
                if (origin != null) {
                    origin.displayTitle?.let { return it }
                    val originBody = origin.displayBody
                    if (originBody.isNotEmpty()) return originBody.take(120)
                }
            }
            val text = displayBody
            if (text.isEmpty()) return null
            return text.take(120)
        }

    val displayExcerpt: String
        get() {
            val text = displayBody
            val t = displayTitle
            if (t.isNullOrEmpty()) return text
            if (text == t) return ""
            return text
        }

    /**
     * True when a feed/profile card would show something meaningful (text, media, or share).
     */
    val hasFeedVisibleContent: Boolean
        get() {
            if (isStory) return false
            if (hasMedia) return true
            if (playableVideoUrl != null) return true
            if (sharedPost != null) return true
            if (!sharedPostId.isNullOrEmpty()) return true
            if (!displayTitle.isNullOrEmpty()) return true
            if (displayBody.isNotEmpty()) return true
            if (!displayCaption.isNullOrEmpty()) return true
            return false
        }

    /** Subtle location line for post cards (country name or ISO). */
    val authorLocationLabel: String?
        get() {
            val name = (author?.countryName ?: countryName)?.trim()
            val code = (author?.countryCode ?: countryCode)?.trim()?.uppercase()
            if (!name.isNullOrEmpty() && name.uppercase() != "XX") return name
            if (!code.isNullOrEmpty() && code != "XX") return code
            return null
        }

    /** ISO regional-indicator flag for the post author location (null if unknown). */
    val authorLocationFlag: String?
        get() {
            val code = (author?.countryCode ?: countryCode)?.trim()?.uppercase()
            if (code == null || code.length != 2 || code == "XX") return null
            val base = 0x1F1E6 - 'A'.code
            return buildString {
                for (ch in code) {
                    appendCodePoint(base + ch.code)
                }
            }
        }

    val authorDisplayName: String
        get() = ContentSanitizer.displayName(
            displayName = author?.displayName,
            username = author?.username,
        )

    /** Seeded hub catalog row (`external_ref_type == "hub"`). */
    val isHubSeedVideo: Boolean
        get() {
            if (externalRefType == "hub") return true
            val idLower = id.lowercase()
            val author = authorId.lowercase()
            return idLower.startsWith("hub_") || idLower.startsWith("ia_") ||
                author.startsWith("hub_") || author.startsWith("hub_spark_")
        }

    val hubSlug: String?
        get() = if (externalRefType == "hub") externalRefId?.lowercase() else null

    val playableVideoUrl: String? get() = MediaUrlResolver.videoUrl(this)
    val posterImageUrl: String? get() = MediaUrlResolver.posterUrl(this)
    val feedImageUrl: String?
        get() = MediaUrlResolver.posterUrl(this) ?: MediaUrlResolver.imageUrl(this)

    val relativeTime: String get() = RelativeTime.format(createdAt)

    companion object {
        /** `__spark__|` / `__reel__|` only when used as a control line (start or after newline). */
        private fun bodyHasSparkMarker(body: String): Boolean {
            if (body.isEmpty()) return false
            if (SparkShareMarker.isMarked(body)) return false
            if (body.startsWith("__spark__|") || body.startsWith("__reel__|")) return true
            if (body.contains("\n__spark__|") || body.contains("\n__reel__|")) return true
            return false
        }
    }
}

/** Archive / seed catalog media detection (subset of iOS PlayPlatformBridge used by models). */
object ArchiveCatalogMedia {
    fun isArchiveCatalogMedia(post: CountryPost): Boolean {
        if (post.isHubSeedVideo) return true
        val playable = post.playableVideoUrl?.lowercase().orEmpty()
        if (playable.contains("archive.org")) return true
        val media = (post.mediaUrl ?: "").lowercase()
        if (media.contains("archive.org")) return true
        val thumb = (post.thumbUrl ?: "").lowercase()
        if (thumb.contains("archive.org")) return true
        val id = post.id.lowercase()
        if (id.startsWith("ia_") || id.startsWith("hub_spark_")) return true
        val ext = post.externalRefId?.lowercase()
        if (ext != null && (ext.startsWith("ia_") || ext.startsWith("hub_"))) return true
        return false
    }

    fun isHubCatalogContent(post: CountryPost): Boolean {
        if (post.isStory) return false
        if (post.isHubSeedVideo) return true
        if (HubChannelPostMarker.isMarked(post.body)) return true
        if (HubOriginShareMarker.isMarked(post.body)) return true
        if (HubArchiveIdentity.isArchiveChannelAuthor(post.authorId)) return true
        if (isArchiveCatalogMedia(post)) return true
        val id = post.id.lowercase()
        if (id.startsWith("ia_") || id.startsWith("hub_") || id.startsWith("hub_spark_")) return true
        return false
    }

    fun isReelVideo(post: CountryPost): Boolean = post.isReel

    fun isSparkFeedCard(post: CountryPost): Boolean =
        post.isSparkFeedShare || post.isReel
}

fun List<CountryPost>.excludingArchiveContent(): List<CountryPost> {
    if (AppConfig.archiveContentEnabled) return this
    return filter {
        !it.isArchiveSparkSource && !ArchiveCatalogMedia.isArchiveCatalogMedia(it)
    }
}

/** Originals stay in Sparks player; spark *shares* pass through (iOS parity). */
fun List<CountryPost>.excludingSparks(): List<CountryPost> =
    filter { !it.isSpark || it.isSparkFeedShare }

fun List<CountryPost>.excludingMoments(): List<CountryPost> = filter { !it.isStory }

/** Profile / feed lists — no blank cards, moments, or sparks. */
fun List<CountryPost>.forProfileFeedGrid(): List<CountryPost> =
    excludingMoments()
        .excludingSparks()
        .filter { it.hasFeedVisibleContent }

data class LivingChannel(
    val id: String,
    val authorId: String,
    val title: String,
    val author: PostAuthor?,
    val videos: List<CountryPost>,
) {
    val videoCount: Int get() = videos.size
    val latestVideo: CountryPost? get() = videos.firstOrNull()
}

data class StoryGroup(
    val authorId: String,
    val author: PostAuthor?,
    val stories: List<CountryPost>,
    val hasUnviewed: Boolean,
) {
    val id: String get() = authorId

    val displayName: String
        get() = ContentSanitizer.displayName(
            displayName = author?.displayName,
            username = author?.username,
        )
}

data class StoryViewerContext(
    val groups: List<StoryGroup>,
    var groupIndex: Int,
    var storyIndex: Int,
    val id: String = UUID.randomUUID().toString(),
)

data class ReelsViewerContext(
    val startingPost: CountryPost,
    val seedPosts: List<CountryPost>,
    val id: String = UUID.randomUUID().toString(),
) {
    val startingPostId: String get() = startingPost.id
}

enum class CreateContentSheet {
    POST,
    VIDEO,
    REEL,
    STORY,

    /** Long-form video published to the user's Living channel (Hubs). */
    HUB_VIDEO,

    /** First-time channel name / about setup before hubVideo. */
    CHANNEL_SETUP,
    ;

    val rawValue: String
        get() = when (this) {
            POST -> "post"
            VIDEO -> "video"
            REEL -> "reel"
            STORY -> "story"
            HUB_VIDEO -> "hubVideo"
            CHANNEL_SETUP -> "channelSetup"
        }

    val id: String get() = rawValue
}
