package com.matterya.matterya.model

import android.util.Base64
import com.matterya.matterya.data.media.MediaUrlResolver
import com.matterya.matterya.theme.MatteryaCopy
import java.nio.charset.Charset
import java.util.regex.Pattern
import kotlin.math.max

data class CallLogInfo(
    val status: String,
    val kind: String,
    val duration: Int,
)

data class Message(
    val id: String,
    val conversationId: String,
    val senderId: String,
    val body: String,
    val mediaType: String? = null,
    val mediaPath: String? = null,
    val mediaUrl: String? = null,
    val mediaName: String? = null,
    val createdAt: String = "",
    val updatedAt: String = "",
    val sender: PostAuthor? = null,
) {
    val hasImage: Boolean
        get() {
            val type = (mediaType ?: "").lowercase()
            return type == "image" && (mediaPath != null || mediaUrl != null)
        }

    val hasVideoMedia: Boolean
        get() {
            val type = (mediaType ?: "").lowercase()
            return (type == "video" || type == "reel") && (mediaPath != null || mediaUrl != null)
        }

    val isReaction: Boolean get() = parseReaction(body) != null

    val reactionInfo: ReactionInfo? get() = parseReaction(body)

    val isCallLog: Boolean get() = parseCallLog(body) != null

    /** Shared hub video / feed post / reel card encoded in the message body. */
    val shareInfo: ShareInfo? get() = parseShare(body)

    val isShare: Boolean get() = shareInfo != null

    val isRenderableInChat: Boolean
        get() {
            if (isReaction) return false
            if (isCallLog) return true
            if (isShare) return true
            if (hasImage || hasVideoMedia) return true
            if (displayText != null) return true
            return false
        }

    val previewText: String
        get() {
            if (isReaction) return "Liked a message"
            parseCallLog(body)?.let { return formatCallLog(it) }
            shareInfo?.let { share ->
                if (share.note.isNotEmpty()) return share.note
                return when (share.kind) {
                    ShareInfo.Kind.REEL -> "Shared a ${MatteryaCopy.spark}"
                    ShareInfo.Kind.HUB -> if (share.isVideo) "Shared a video" else "Shared from Hubs"
                    ShareInfo.Kind.POST -> if (share.isVideo) "Shared a video" else "Shared a post"
                }
            }
            displayText?.takeIf { it.isNotEmpty() }?.let { return it }
            if (hasImage) return "Photo"
            if (hasVideoMedia || (mediaType ?: "").lowercase() == "video") return "Video"
            return "Media message"
        }

    val displayText: String?
        get() {
            if (isReaction) return null
            parseCallLog(body)?.let { return formatCallLog(it) }
            shareInfo?.let { share ->
                val note = share.note.trim()
                return if (note.isEmpty()) null else ContentSanitizer.clean(note)
            }
            parseReply(body)?.let { reply ->
                var replyBody = stripTrailingMeta(reply.body.trim())
                replyBody = stripIdOnlyLines(replyBody)
                return ContentSanitizer.clean(replyBody)
            }

            var text = body.trim()
            text = stripTrailingMeta(text)
            text = stripIdOnlyLines(text)
            val cleaned = ContentSanitizer.clean(text) ?: return null
            if (cleaned == id || cleaned == conversationId || cleaned == senderId) return null
            if (cleaned == mediaPath || cleaned == mediaName) return null
            return cleaned
        }

    val timestampLabel: String get() = RelativeTime.formatClock(createdAt)

    val isEdited: Boolean
        get() {
            val created = RelativeTime.parseDate(createdAt) ?: return false
            val updated = RelativeTime.parseDate(updatedAt) ?: return false
            return updated.epochSecond - created.epochSecond > 1
        }

    val replyInfo: ReplyInfo?
        get() {
            val parsed = parseReply(body) ?: return null
            return ReplyInfo(
                targetId = parsed.targetId,
                quotedText = parsed.text,
                body = parsed.body,
            )
        }

    /** Rich content shared into chat (hub video, feed post, reel). */
    data class ShareInfo(
        val kind: Kind,
        val postId: String,
        val title: String? = null,
        val bodyText: String? = null,
        val authorName: String? = null,
        val authorId: String? = null,
        val mediaUrl: String? = null,
        val posterUrl: String? = null,
        val mediaType: String? = null,
        /** Optional caption the sender typed with the share. */
        val note: String = "",
    ) {
        enum class Kind(val rawValue: String) {
            POST("post"),
            HUB("hub"),
            REEL("reel"),
            ;

            companion object {
                fun fromRaw(raw: String?): Kind = when (raw?.lowercase()) {
                    "hub" -> HUB
                    "reel" -> REEL
                    else -> POST
                }
            }
        }

        val isVideo: Boolean
            get() {
                val type = (mediaType ?: "").lowercase()
                if (type == "video" || type == "reel") return true
                if (kind == Kind.HUB || kind == Kind.REEL) return true
                if (playableVideoUrl != null) return true
                if (!mediaUrl.isNullOrEmpty()) {
                    val lower = mediaUrl.lowercase()
                    if (lower.contains(".mp4") || lower.contains(".m3u8") ||
                        lower.contains("archive.org") ||
                        lower.contains("\"video\"") || lower.contains("\"reel\"")
                    ) {
                        return true
                    }
                }
                return false
            }

        val isHubContent: Boolean
            get() {
                if (kind == Kind.REEL) return false
                val type = (mediaType ?: "").lowercase()
                if (type == "reel" || type == "spark") return false
                return kind == Kind.HUB ||
                    postId.lowercase().startsWith("ia_") ||
                    postId.lowercase().startsWith("hub_") ||
                    (mediaUrl?.lowercase()?.contains("archive.org") == true && kind != Kind.POST)
            }

        val playableVideoUrl: String?
            get() {
                MediaUrlResolver.videoUrl(mediaProbePost)?.let { return it }
                return MediaUrlResolver.resolve(mediaUrl)
            }

        val posterImageUrl: String?
            get() {
                MediaUrlResolver.posterUrl(mediaProbePost)?.let { resolved ->
                    if (!MediaUrlResolver.isVideoUrl(resolved)) return resolved
                }
                val raw = posterUrl
                if (!raw.isNullOrEmpty() && !looksLikeVideoUrl(raw)) {
                    val resolved = MediaUrlResolver.resolve(raw)
                    if (resolved != null && !MediaUrlResolver.isVideoUrl(resolved)) return resolved
                }
                return null
            }

        private val mediaProbePost: CountryPost
            get() {
                val type = mediaType
                    ?: when (kind) {
                        Kind.REEL -> "reel"
                        Kind.HUB -> "video"
                        Kind.POST -> "video"
                    }
                return CountryPost(
                    id = postId,
                    title = title,
                    body = bodyText ?: "",
                    mediaType = type,
                    mediaUrl = mediaUrl,
                    thumbUrl = posterUrl,
                    createdAt = "",
                    updatedAt = "",
                    authorId = authorId ?: "",
                )
            }

        val asCountryPost: CountryPost
            get() {
                val author: PostAuthor? = authorId?.takeIf { it.isNotEmpty() }?.let { aid ->
                    PostAuthor(
                        userId = aid,
                        displayName = authorName,
                        username = null,
                        avatarUrl = null,
                        countryName = null,
                        countryCode = null,
                        lastReadAt = null,
                    )
                }
                val plainMedia = playableVideoUrl ?: mediaUrl
                val isSpark = kind == Kind.REEL ||
                    (mediaType ?: "").lowercase() == "reel" ||
                    (mediaType ?: "").lowercase() == "spark"
                val body: String = run {
                    val raw = (bodyText ?: "").trim()
                    if (isSpark) {
                        if (raw.startsWith("__spark__|") || raw.startsWith("__reel__|")) raw
                        else "__spark__|${if (raw.isEmpty()) "Spark" else raw}"
                    } else {
                        raw
                    }
                }
                return CountryPost(
                    id = postId,
                    title = title,
                    body = body,
                    mediaType = if (isSpark) (mediaType ?: "reel") else (mediaType ?: if (isVideo) "video" else null),
                    mediaUrl = plainMedia,
                    thumbUrl = posterUrl ?: posterImageUrl,
                    createdAt = "",
                    updatedAt = "",
                    authorId = authorId ?: "",
                    author = author,
                )
            }

        val previewLabel: String
            get() {
                if (kind == Kind.REEL) return title?.takeIf { it.isNotEmpty() } ?: MatteryaCopy.spark
                if (isVideo) return title?.takeIf { it.isNotEmpty() } ?: "Video"
                return title?.takeIf { it.isNotEmpty() } ?: "Post"
            }
    }

    data class ReplyInfo(
        val targetId: String,
        val quotedText: String,
        val body: String,
    )

    private data class ParsedReply(
        val targetId: String,
        val text: String,
        val body: String,
    )

    data class ReactionInfo(
        val targetId: String,
        val emoji: String,
        val isActive: Boolean,
    )

    companion object {
        private const val REACTION_PREFIX = "__react__|"
        private const val REPLY_PREFIX = "__reply__|"
        private const val SHARE_PREFIX = "__share__|"

        fun callLogBody(status: String, kind: String, durationSeconds: Int): String {
            val duration = max(0, durationSeconds)
            return "__call__|status=$status|kind=$kind|duration=$duration"
        }

        fun parseCallLog(body: String): CallLogInfo? {
            var cleaned = body.replace("\uFEFF", "").trim()
            if ((cleaned.startsWith("\"") && cleaned.endsWith("\"")) ||
                (cleaned.startsWith("'") && cleaned.endsWith("'"))
            ) {
                cleaned = cleaned.substring(1, cleaned.length - 1)
            }
            val pattern = Pattern.compile(
                """__call__\|status=([^|]+)\|kind=(audio|video)\|duration=([0-9]+)""",
                Pattern.CASE_INSENSITIVE,
            )
            val matcher = pattern.matcher(cleaned)
            if (!matcher.find()) return null
            val status = matcher.group(1)?.trim()?.lowercase().orEmpty()
            val kind = if (matcher.group(2)?.lowercase() == "video") "video" else "audio"
            val duration = matcher.group(3)?.toIntOrNull() ?: 0
            if (status.isEmpty()) return null
            return CallLogInfo(status = status, kind = kind, duration = max(0, duration))
        }

        fun formatCallLog(log: CallLogInfo): String {
            val kindLabel = if (log.kind == "video") "Video call" else "Voice call"
            return when (log.status) {
                "ended" -> {
                    if (log.duration > 0) "$kindLabel · ${formatDuration(log.duration)}"
                    else "$kindLabel ended"
                }
                "missed", "busy" -> "Missed ${kindLabel.lowercase()}"
                "declined" -> "$kindLabel declined"
                "ringing", "trying" -> "$kindLabel ringing"
                else -> kindLabel
            }
        }

        fun buildReplyBody(target: Message, body: String): String {
            val quoted = target.displayText ?: target.previewText
            val encoded = encodeBase64(quoted.take(160))
            return "${REPLY_PREFIX}id=${target.id}|text=$encoded||$body"
        }

        /** Encodes a post/hub video / Spark so chat can render a rich card. */
        fun buildShareBody(post: CountryPost, note: String = ""): String {
            val kind: ShareInfo.Kind = when {
                post.isReel ||
                    post.isSparkFeedShare ||
                    ArchiveCatalogMedia.isSparkFeedCard(post) ||
                    ArchiveCatalogMedia.isReelVideo(post) -> ShareInfo.Kind.REEL
                ArchiveCatalogMedia.isHubCatalogContent(post) && post.hasVideo -> ShareInfo.Kind.HUB
                else -> ShareInfo.Kind.POST
            }

            val mediaType = post.mediaType
                ?: if (post.hasVideo) {
                    if (kind == ShareInfo.Kind.REEL) "reel" else "video"
                } else {
                    null
                }
            val title = post.displayHeadline ?: post.displayTitle
            val bodyText: String? = run {
                val b = post.displayBody.trim()
                if (b.isNotEmpty()) b else post.displayCaption
            }
            val author = post.authorDisplayName
            val media = post.playableVideoUrl
                ?: MediaUrlResolver.resolve(post.mediaUrl)
                ?: post.mediaUrl
            val poster: String? = run {
                post.posterImageUrl?.takeIf { it.isNotEmpty() && !looksLikeVideoUrl(it) }?.let { return@run it }
                post.feedImageUrl?.takeIf { it.isNotEmpty() && !looksLikeVideoUrl(it) }?.let { return@run it }
                post.thumbUrl?.takeIf { it.isNotEmpty() && !looksLikeVideoUrl(it) }?.let { return@run it }
                MediaUrlResolver.posterUrl(post)?.takeIf { !looksLikeVideoUrl(it) }
            }

            val parts = mutableListOf(
                "v=1",
                "kind=${kind.rawValue}",
                "id=${post.id}",
            )
            if (!title.isNullOrEmpty()) parts.add("title=${encodeBase64(title.take(180))}")
            if (!bodyText.isNullOrEmpty()) parts.add("body=${encodeBase64(bodyText.take(280))}")
            if (author.isNotEmpty()) parts.add("author=${encodeBase64(author.take(80))}")
            if (post.authorId.isNotEmpty()) parts.add("authorId=${post.authorId}")
            if (!media.isNullOrEmpty() && !media.startsWith("{")) {
                parts.add("media=${encodeBase64(media)}")
            } else {
                post.playableVideoUrl?.let { parts.add("media=${encodeBase64(it)}") }
            }
            if (!poster.isNullOrEmpty() && !poster.startsWith("{")) {
                parts.add("poster=${encodeBase64(poster)}")
            }
            if (!mediaType.isNullOrEmpty()) parts.add("type=$mediaType")

            val meta = parts.joinToString("|")
            val trimmedNote = note.trim()
            return if (trimmedNote.isEmpty()) {
                "$SHARE_PREFIX$meta||"
            } else {
                "$SHARE_PREFIX$meta||$trimmedNote"
            }
        }

        /** True when a string looks like a playable video URL (not a JPG/PNG poster). */
        fun looksLikeVideoUrl(raw: String): Boolean {
            val lower = raw.trim().lowercase()
            if (lower.isEmpty()) return false
            if (lower.startsWith("{")) return false
            if (Regex("""\.(mp4|webm|mov|m4v|m3u8|avi|mkv)(\?|#|$)""").containsMatchIn(lower)) {
                return true
            }
            if (lower.contains("/video/") || lower.contains("/video.")) return true
            val resolved = MediaUrlResolver.resolve(raw)
            if (resolved != null && MediaUrlResolver.isVideoUrl(resolved)) return true
            return false
        }

        fun parseShare(body: String): ShareInfo? {
            val trimmed = body.trim()
            if (trimmed.startsWith(SHARE_PREFIX)) {
                return parseStructuredShare(trimmed)
            }
            return parseLegacyShareLink(trimmed)
        }

        private fun parseStructuredShare(trimmed: String): ShareInfo? {
            val withoutPrefix = trimmed.removePrefix(SHARE_PREFIX)
            val parts = withoutPrefix.split("||")
            val meta = parts.firstOrNull() ?: ""
            val note = parts.drop(1).joinToString("||").trim()

            val id = metaValue(meta, "id")
            if (id.isEmpty()) return null

            val kind = ShareInfo.Kind.fromRaw(metaValue(meta, "kind"))
            val title = nonEmpty(decodeBase64(metaValue(meta, "title")))
            val bodyText = nonEmpty(decodeBase64(metaValue(meta, "body")))
            val authorName = nonEmpty(decodeBase64(metaValue(meta, "author")))
            val authorId = nonEmpty(metaValue(meta, "authorId"))
            val media = nonEmpty(decodeBase64(metaValue(meta, "media")))
            val poster = nonEmpty(decodeBase64(metaValue(meta, "poster")))
            val mediaType = nonEmpty(metaValue(meta, "type"))
                ?: nonEmpty(metaValue(meta, "mediaType"))

            return ShareInfo(
                kind = kind,
                postId = id,
                title = title,
                bodyText = bodyText,
                authorName = authorName,
                authorId = authorId,
                mediaUrl = media,
                posterUrl = poster,
                mediaType = mediaType,
                note = note,
            )
        }

        /** Older shares were plain "title\\nhttps://matterya.com/post|play/watch/…". */
        private fun parseLegacyShareLink(trimmed: String): ShareInfo? {
            val urlRegex = Regex(
                """https?://[^\s]+|matterya://[^\s]+""",
                RegexOption.IGNORE_CASE,
            )
            val match = urlRegex.find(trimmed) ?: return null
            val urlString = match.value
            val uri = runCatching { java.net.URI(urlString) }.getOrNull() ?: return null
            val host = (uri.host ?: "").lowercase()
            val scheme = (uri.scheme ?: "").lowercase()
            val isMatterya = host.contains("matterya.com") || scheme == "matterya"
            if (!isMatterya) return null

            var path = uri.path.trim('/')
            if (scheme == "matterya" && !host.contains(".")) {
                path = "$host/$path".trim('/')
            }
            val segments = path.split('/').filter { it.isNotEmpty() }
            val first = segments.firstOrNull()?.lowercase() ?: return null

            val postId: String
            val kind: ShareInfo.Kind
            when (first) {
                "post", "p" -> {
                    postId = segments.getOrNull(1)?.takeIf { it.isNotEmpty() } ?: return null
                    kind = ShareInfo.Kind.POST
                }
                "play" -> {
                    if (segments.size < 3 || segments[1].lowercase() != "watch") return null
                    postId = segments[2]
                    kind = ShareInfo.Kind.HUB
                }
                else -> return null
            }

            val before = trimmed.substring(0, match.range.first).trim()
            val title = before.lines()
                .map { it.trim() }
                .firstOrNull { it.isNotEmpty() }

            return ShareInfo(
                kind = kind,
                postId = postId,
                title = title,
                bodyText = null,
                authorName = null,
                authorId = null,
                mediaUrl = null,
                posterUrl = null,
                mediaType = if (kind == ShareInfo.Kind.HUB) "video" else null,
                note = "",
            )
        }

        fun buildReactionBody(targetId: String, emoji: String = "❤", active: Boolean): String {
            val normalized = emoji.trim()
            val resolved = if (normalized.isEmpty()) "❤" else normalized
            return "${REACTION_PREFIX}target=$targetId|emoji=$resolved|state=${if (active) 1 else 0}"
        }

        fun parseReaction(body: String): ReactionInfo? {
            val trimmed = body.trim()
            if (!trimmed.startsWith(REACTION_PREFIX)) return null
            val targetMatch = Regex("""target=([^|]+)""").find(trimmed) ?: return null
            val targetId = targetMatch.groupValues[1]
            if (targetId.isEmpty()) return null

            val emoji = Regex("""emoji=([^|]+)""").find(trimmed)?.groupValues?.get(1) ?: "❤"
            val state = Regex("""state=([01])""").find(trimmed)?.groupValues?.get(1)?.toIntOrNull() ?: 1

            return ReactionInfo(targetId = targetId, emoji = emoji, isActive = state == 1)
        }

        private fun parseReply(body: String): ParsedReply? {
            val trimmed = body.trim()
            if (!trimmed.startsWith(REPLY_PREFIX)) return null
            val parts = trimmed.split("||")
            val meta = parts.firstOrNull() ?: ""
            val rest = parts.drop(1).joinToString("||")
            val targetId = metaValue(meta, "id")
            val encodedText = metaValue(meta, "text")
            return ParsedReply(targetId = targetId, text = decodeBase64(encodedText), body = rest)
        }

        private fun metaValue(meta: String, key: String): String {
            val match = Regex("""$key=([^|]+)""").find(meta) ?: return ""
            return match.value.removePrefix("$key=")
        }

        private fun encodeBase64(value: String): String {
            return Base64.encodeToString(
                value.toByteArray(Charsets.UTF_8),
                Base64.NO_WRAP,
            )
        }

        private fun nonEmpty(value: String): String? {
            val trimmed = value.trim()
            return if (trimmed.isEmpty()) null else trimmed
        }

        fun stripTrailingMeta(value: String): String {
            var result = value.trim()
            val trailingUuid = Regex(
                """[ \t\n]+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[ \t\n]*$""",
                RegexOption.IGNORE_CASE,
            )

            while (true) {
                var changed = false

                val lastNl = result.lastIndexOf('\n')
                if (lastNl >= 0) {
                    val lastLine = result.substring(lastNl + 1).trim()
                    if (ContentSanitizer.looksLikeId(lastLine)) {
                        result = result.substring(0, lastNl).trim()
                        changed = true
                    }
                }

                val parts = result.split(" ")
                if (parts.size >= 2) {
                    val last = parts.last().trim()
                    if (ContentSanitizer.looksLikeId(last)) {
                        result = parts.dropLast(1).joinToString(" ").trim()
                        changed = true
                    }
                }

                val uuidMatch = trailingUuid.find(result)
                if (uuidMatch != null) {
                    result = result.substring(0, uuidMatch.range.first).trim()
                    changed = true
                }

                if (!changed) break
            }

            return result
        }

        fun stripIdOnlyLines(value: String): String {
            return value.lines()
                .map { it.trim() }
                .filter { it.isNotEmpty() && !ContentSanitizer.looksLikeId(it) }
                .joinToString("\n")
                .trim()
        }

        private fun decodeBase64(value: String): String {
            return try {
                val data = Base64.decode(value, Base64.DEFAULT)
                String(data, Charset.forName("UTF-8"))
            } catch (_: Exception) {
                ""
            }
        }

        fun formatDuration(totalSeconds: Int): String {
            val seconds = max(0, totalSeconds)
            val hours = seconds / 3600
            val minutes = (seconds % 3600) / 60
            val secs = seconds % 60
            return if (hours > 0) {
                String.format("%d:%02d:%02d", hours, minutes, secs)
            } else {
                String.format("%02d:%02d", minutes, secs)
            }
        }
    }
}

data class Conversation(
    val id: String,
    val isDirect: Boolean,
    val createdAt: String = "",
    val updatedAt: String = "",
    val lastMessageAt: String? = null,
    val isRequest: Boolean = false,
    val requestStatus: String? = null,
    val surface: String = "primary",
    val members: List<PostAuthor> = emptyList(),
    val lastMessage: Message? = null,
) {
    val isMasqueradeSurface: Boolean
        get() = surface.equals("masquerade", ignoreCase = true)

    fun otherMember(currentUserId: String): PostAuthor? =
        members.firstOrNull { it.userId != currentUserId }

    /** Viewer still has unread inbound messages in this thread (iOS Conversation.hasUnread). */
    fun hasUnread(currentUserId: String): Boolean {
        val last = lastMessage ?: return false
        if (last.senderId == currentUserId) return false
        val me = members.firstOrNull { it.userId == currentUserId } ?: return true
        val readAt = me.lastReadAt?.trim().orEmpty()
        if (readAt.isEmpty()) return true
        val readDate = RelativeTime.parseDate(readAt) ?: return true
        val msgDate = RelativeTime.parseDate(last.createdAt) ?: return true
        return msgDate > readDate
    }
}
