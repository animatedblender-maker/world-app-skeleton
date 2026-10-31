package com.matterya.matterya.model

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Body marker tokens — mirror iOS Models.swift exactly.
 * Token strings must never change.
 */

/** Living channel name embedded in profile bio. */
object LivingChannelMarker {
    private const val PREFIX = "__living_channel__|"

    fun parse(fromBio: String?): String? {
        if (fromBio == null) return null
        for (line in fromBio.lines()) {
            val trimmed = line.trim()
            if (!trimmed.startsWith(PREFIX)) continue
            val rest = trimmed.removePrefix(PREFIX)
            for (part in rest.split("|")) {
                if (part.startsWith("name=")) {
                    val name = part.removePrefix("name=").trim()
                    return name.ifEmpty { null }
                }
            }
        }
        return null
    }

    fun displayBio(fromRawBio: String?): String {
        if (fromRawBio == null) return ""
        return fromRawBio.lines()
            .filter { !it.trim().startsWith(PREFIX) }
            .joinToString("\n")
            .trim()
    }

    fun buildBio(displayBio: String, channelName: String?): String {
        val lines = mutableListOf<String>()
        val cleaned = displayBio.trim()
        if (cleaned.isNotEmpty()) lines.add(cleaned)
        if (channelName != null) {
            val trimmed = channelName.trim()
            if (trimmed.isNotEmpty()) {
                lines.add("${PREFIX}name=$trimmed")
            }
        }
        return lines.joinToString("\n")
    }

    /** True when the profile bio embeds a Living channel name marker. */
    fun hasChannel(profile: Profile?): Boolean = parse(profile?.bio) != null
}

/**
 * Marks long-form uploads that belong on a user's **own** Hubs channel
 * (intentional Hubs publish only — never used for feed shares).
 */
object HubChannelPostMarker {
    const val TOKEN = "__hub_channel__|"

    fun markBody(caption: String): String {
        val trimmed = caption.trim()
        if (trimmed.contains(TOKEN)) return trimmed
        if (trimmed.isEmpty()) return TOKEN
        return "$TOKEN\n$trimmed"
    }

    fun strip(body: String): String {
        return body.lines()
            .map { it.trim() }
            .filter { !it.startsWith(TOKEN) && it != TOKEN.trim() }
            .joinToString("\n")
            .trim()
    }

    fun isMarked(body: String?): Boolean {
        if (body == null) return false
        return body.contains(TOKEN)
    }
}

/**
 * Feed share of a **Spark** — shows as a Spark card on the home feed only.
 * Must **never** use `__spark__|` (that would enter the Sparks swipe pool as an original).
 *
 * Header line: `__spark_share__|sid=…`
 * Optional caption lines follow.
 */
object SparkShareMarker {
    const val TOKEN = "__spark_share__|"

    fun isMarked(body: String?): Boolean {
        if (body == null) return false
        return body.contains(TOKEN)
    }

    /** Stamp original Spark id + channel so feed cards can show attribution. */
    fun markBody(caption: String, origin: CountryPost): String {
        val sid = (origin.sharedPostId ?: origin.id).replace("|", "")
        val aid = origin.authorId.replace("|", "")
        val an = (origin.author?.displayName ?: origin.authorDisplayName)
            .replace("|", " ")
            .trim()
        var header = "${TOKEN}sid=$sid"
        if (aid.isNotEmpty()) header += "|aid=$aid"
        if (an.isNotEmpty()) header += "|an=$an"
        val cap = caption.trim()
        if (cap.isEmpty()) return header
        return "$header\n$cap"
    }

    fun strip(body: String): String {
        return body.lines()
            .map { it.trim() }
            .filter { !it.startsWith(TOKEN) }
            .joinToString("\n")
            .trim()
    }

    /** Original spark id when this post is a feed re-share of a Spark. */
    fun originId(fromBody: String?): String? = parseFields(fromBody)?.get("sid")

    /** Channel / creator name the Spark came from (for feed attribution). */
    fun originChannelName(fromBody: String?): String? {
        val an = parseFields(fromBody)?.get("an")?.trim()
        return an?.takeIf { it.isNotEmpty() }
    }

    private fun parseFields(fromBody: String?): Map<String, String>? {
        if (fromBody == null) return null
        for (line in fromBody.lines()) {
            val trimmed = line.trim()
            if (!trimmed.startsWith(TOKEN)) continue
            val rest = trimmed.removePrefix(TOKEN)
            val out = linkedMapOf<String, String>()
            for (part in rest.split("|")) {
                val eq = part.indexOf('=')
                if (eq <= 0) continue
                val key = part.substring(0, eq)
                val value = part.substring(eq + 1)
                if (key.isNotEmpty()) out[key] = value
            }
            return out.ifEmpty { null }
        }
        return null
    }
}

/**
 * Feed share of a Hubs video — **does not** create a channel for the sharer.
 * Preserves original channel/author so Hubs watch shows the real creator.
 *
 * Header line: `__hub_origin__|sid=…|aid=…|an=…|au=…`
 */
object HubOriginShareMarker {
    const val TOKEN = "__hub_origin__|"

    fun isMarked(body: String?): Boolean {
        if (body == null) return false
        return body.contains(TOKEN)
    }

    fun markBody(caption: String, origin: CountryPost): String {
        val sid = (origin.sharedPostId ?: origin.id).replace("|", "")
        val aid = origin.authorId.replace("|", "")
        val an = (origin.author?.displayName ?: origin.authorDisplayName)
            .replace("|", " ")
            .trim()
        val au = (origin.author?.username ?: "").replace("|", "")
        var header = "${TOKEN}sid=$sid|aid=$aid|an=$an"
        if (au.isNotEmpty()) header += "|au=$au"
        val cap = caption.trim()
        if (cap.isEmpty()) return header
        return "$header\n$cap"
    }

    fun strip(body: String): String {
        return body.lines()
            .map { it.trim() }
            .filter { !it.startsWith(TOKEN) && !it.startsWith("__hub_channel__") }
            .joinToString("\n")
            .trim()
    }

    /** Rebuild a presentation post for Hubs watch: same media as the share, original channel author. */
    fun originPresentation(fromShare: CountryPost): CountryPost? {
        val fields = parseFields(fromShare.body) ?: return null
        val originAuthorId = fields["aid"]?.trim()
        if (originAuthorId.isNullOrEmpty()) return null
        val name = fields["an"]?.trim()
        val username = fields["au"]?.trim()
        val sourceId = fields["sid"]?.trim()

        val channelName = when {
            !name.isNullOrEmpty() -> name
            HubArchiveIdentity.isArchiveChannelAuthor(originAuthorId) ->
                HubArchiveIdentity.archiveChannelDisplayName
            else -> {
                val embed = fromShare.sharedPost?.asCountryPost
                if (embed != null && embed.authorId == originAuthorId) {
                    embed.authorDisplayName
                } else {
                    HubArchiveIdentity.archiveChannelDisplayName
                }
            }
        }
        val channelAvatar: String? = run {
            val embed = fromShare.sharedPost?.asCountryPost
            if (embed != null && embed.authorId == originAuthorId) embed.author?.avatarUrl else null
        }
        val author = PostAuthor(
            userId = originAuthorId,
            displayName = channelName,
            username = username?.takeIf { it.isNotEmpty() },
            avatarUrl = channelAvatar,
            countryName = null,
            countryCode = null,
            lastReadAt = null,
        )
        return CountryPost(
            id = if (!sourceId.isNullOrEmpty()) sourceId else fromShare.id,
            title = fromShare.title,
            body = strip(fromShare.body),
            mediaType = fromShare.mediaType,
            mediaUrl = fromShare.mediaUrl,
            thumbUrl = fromShare.thumbUrl,
            mediaCaption = fromShare.mediaCaption,
            sharedPostId = fromShare.sharedPostId,
            sharedPost = fromShare.sharedPost,
            visibility = fromShare.visibility,
            likeCount = fromShare.likeCount,
            commentCount = fromShare.commentCount,
            viewCount = fromShare.viewCount,
            likedByMe = fromShare.likedByMe,
            savedByMe = fromShare.savedByMe,
            createdAt = fromShare.createdAt,
            updatedAt = fromShare.updatedAt,
            authorId = originAuthorId,
            countryName = fromShare.countryName,
            countryCode = fromShare.countryCode,
            cityName = fromShare.cityName,
            author = author,
            externalRefType = fromShare.externalRefType ?: "hub",
            externalRefId = fromShare.externalRefId ?: sourceId,
        )
    }

    fun parseFields(fromBody: String?): Map<String, String>? {
        if (fromBody == null) return null
        val line = fromBody.lines()
            .map { it.trim() }
            .firstOrNull { it.startsWith(TOKEN) }
            ?: return null
        val payload = line.removePrefix(TOKEN)
        val out = linkedMapOf<String, String>()
        for (part in payload.split("|")) {
            val eq = part.indexOf('=')
            if (eq <= 0) continue
            val key = part.substring(0, eq)
            val value = part.substring(eq + 1)
            if (key.isNotEmpty()) out[key] = value
        }
        return out.ifEmpty { null }
    }
}

object PostStoryMarker {
    fun buildBody(caption: String, expiresAt: Instant): String {
        val marker = markerLine(expiresAt)
        val trimmed = caption.trim()
        if (trimmed.isEmpty()) return marker
        return "$trimmed\n$marker"
    }

    fun expiresAt(fromBody: String): Instant? {
        for (line in fromBody.lines()) {
            val trimmed = line.trim()
            if (!trimmed.startsWith("__story__|expires=")) continue
            val iso = trimmed.removePrefix("__story__|expires=")
            return RelativeTime.parseDate(iso)
        }
        return null
    }

    private fun markerLine(expiresAt: Instant): String {
        val formatter = DateTimeFormatter.ISO_INSTANT
        return "__story__|expires=${formatter.format(expiresAt)}"
    }
}

/**
 * Archive / hub-seed identity constants (from iOS `HubVideoSeedService`).
 * Full seed service lives elsewhere; models only need these identifiers.
 */
object HubArchiveIdentity {
    const val archiveChannelAuthorId = "hub_archive"
    const val archiveChannelDisplayName = "The Archive"
    const val archiveChannelUsername = "the_archive"

    fun isArchiveChannelAuthor(authorId: String?): Boolean {
        val raw = authorId?.trim()?.lowercase().orEmpty()
        if (raw.isEmpty()) return false
        if (raw == archiveChannelAuthorId) return true
        if (raw.startsWith("hub_spark_")) return true
        if (raw.startsWith("hub_")) return true
        return false
    }
}
