package com.matterya.matterya.data.media

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.model.CountryPost

data class MediaPlaybackConfiguration(
    val url: String,
    val headers: Map<String, String>? = null,
)

object SupabaseStorageAccess {
    fun isPostsBucketUrl(url: String): Boolean =
        url.contains("/storage/v1/object/") && url.contains("/posts/")

    fun authenticatedUrl(from: String): String? {
        var value = from
        value = when {
            value.contains("/object/public/posts/") ->
                value.replace("/object/public/posts/", "/object/authenticated/posts/")
            value.contains("/object/sign/posts/") -> return from
            value.contains("/object/authenticated/posts/") -> return from
            else -> value
        }
        return value
    }

    fun publicUrl(from: String): String? {
        if (!from.contains("/object/authenticated/posts/")) return from
        return from.replace("/object/authenticated/posts/", "/object/public/posts/")
    }

    suspend fun requestHeaders(): Map<String, String>? {
        if (!AuthService.instance.isAuthenticated) return null
        val token = AuthService.instance.ensureValidTokenOrNull() ?: return null
        return mapOf(
            "Authorization" to "Bearer $token",
            "apikey" to AppConfig.supabaseAnonKey,
        )
    }
}

/** Mirrors iOS `MediaURLResolver.swift` — 100% parity on resolve / poster / video / playback. */
object MediaUrlResolver {

    fun videoUrl(post: CountryPost): String? {
        val payload = post.mediaPayload
        if (payload != null) {
            payload.urls.forEachIndexed { i, u ->
                val type = payload.types.getOrNull(i)?.lowercase().orEmpty()
                if (type == "video") resolve(u)?.let { return it }
            }
            if (post.hasVideo && payload.urls.isNotEmpty()) {
                return resolve(payload.urls.first())
            }
        }
        if (post.hasVideo) {
            return resolve(post.mediaUrl) ?: resolve(post.thumbUrl)
        }
        return null
    }

    fun imageUrl(post: CountryPost): String? {
        val payload = post.mediaPayload
        if (payload != null) {
            payload.urls.forEachIndexed { i, u ->
                val type = payload.types.getOrNull(i)?.lowercase().orEmpty()
                val resolved = resolve(u) ?: return@forEachIndexed
                if (type == "image" && !isVideoUrl(resolved)) return resolved
            }
            payload.urls.forEach { u ->
                val resolved = resolve(u)
                if (resolved != null && !isVideoUrl(resolved)) return resolved
            }
        }
        resolve(post.mediaUrl)?.takeUnless { isVideoUrl(it) }?.let { return it }
        resolve(post.thumbUrl)?.takeUnless { isVideoUrl(it) }?.let { return it }
        return null
    }

    fun posterUrl(post: CountryPost): String? {
        // iOS: archive services/img first, then thumb, then R2 YouTube poster, then image
        archiveServicesImg(post)?.let { return it }
        resolve(post.thumbUrl)?.takeUnless { isVideoUrl(it) }?.let { return it }
        r2LongformYouTubePoster(post)?.let { return it }
        return imageUrl(post)
    }

    fun hubsListPosterUrl(post: CountryPost): String? = posterUrl(post)

    fun r2LongformYouTubePoster(post: CountryPost): String? {
        listOfNotNull(post.thumbUrl, post.mediaUrl, post.linkUrl).forEach { raw ->
            youtubeIdFromR2LongformPath(raw)?.let { id ->
                return "https://i.ytimg.com/vi/$id/hqdefault.jpg"
            }
        }
        return null
    }

    fun youtubeIdFromR2LongformPath(raw: String): String? {
        val patterns = listOf(
            Regex("""[Ll]ong[Ff]orm/[^/"'\\]+/([A-Za-z0-9_-]{6,20})(?:/|\.mp4|"|'|\?|$)"""),
            Regex("""[Ll]ong[Ff]orm%2F[^/%]+%2F([A-Za-z0-9_-]{6,20})"""),
        )
        for (p in patterns) {
            val m = p.find(raw) ?: continue
            val id = m.groupValues[1]
            if (id.length >= 15 && id.all { it.isDigit() }) continue
            if (id.length in 6..20) return id
        }
        return null
    }

    fun archiveServicesImg(post: CountryPost): String? {
        listOfNotNull(post.thumbUrl, post.mediaUrl, post.linkUrl).forEach { raw ->
            archiveItemId(raw)?.let { return "https://archive.org/services/img/$it" }
        }
        return null
    }

    fun archiveItemId(raw: String): String? {
        if (!raw.lowercase().contains("archive.org")) return null
        val patterns = listOf(
            Regex("""/download/([^/?#]+)""", RegexOption.IGNORE_CASE),
            Regex("""/details/([^/?#]+)""", RegexOption.IGNORE_CASE),
            Regex("""/services/img/([^/?#]+)""", RegexOption.IGNORE_CASE),
        )
        for (p in patterns) {
            val m = p.find(raw) ?: continue
            val id = m.groupValues[1].trim('/')
            if (id.isNotEmpty() && id != "download" && id != "details") return id
        }
        return null
    }

    fun resolve(raw: String?): String? {
        var value = raw?.trim().orEmpty()
        if (value.isEmpty()) return null
        if (value.startsWith("{") || value.startsWith("[")) return null
        if (value.startsWith("//")) value = "https:$value"
        else if (!value.contains("://") && value.startsWith("/")) {
            value = "${AppConfig.apiBaseURL}$value"
        } else if (!value.contains("://") && !value.startsWith("/")) {
            value = if (value.contains("/") && !value.contains(" ")) {
                val cleaned = value.trimStart('/')
                "${AppConfig.supabaseURL}/storage/v1/object/public/posts/$cleaned"
            } else {
                "https://$value"
            }
        }
        return value
    }

    fun normalizedAvatarUrl(url: String?): String? {
        var value = url?.trim().orEmpty()
        if (value.isEmpty()) return null
        if (value.startsWith("//")) value = "https:$value"
        if (!value.contains("://")) {
            val cleaned = value.trimStart('/')
            value = "${AppConfig.supabaseURL}/storage/v1/object/public/avatars/$cleaned"
        }
        value = value.replace("/object/authenticated/avatars/", "/object/public/avatars/")
        return value
    }

    fun isImageUrl(url: String): Boolean {
        val lower = url.lowercase()
        if (Regex("""\.(jpe?g|png|gif|webp|avif|bmp|heic)(\?|#|$)""").containsMatchIn(lower)) {
            return true
        }
        if (lower.contains("archive.org/services/img/")) return true
        if (lower.contains("/__ia_thumb.jpg") || lower.contains(".thumbs/")) return true
        return false
    }

    fun isVideoUrl(url: String): Boolean {
        if (isImageUrl(url)) return false
        val lower = url.lowercase()
        if (Regex("""\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)""").containsMatchIn(lower)) {
            return true
        }
        if (lower.contains("/video/") || lower.contains("/video.") || lower.contains("video%")) {
            return true
        }
        return false
    }

    suspend fun playbackUrl(from: String): String = playbackConfiguration(from).url

    suspend fun playbackConfiguration(forUrl: String): MediaPlaybackConfiguration {
        if (isImageUrl(forUrl)) {
            return MediaPlaybackConfiguration(forUrl, headers = null)
        }
        if (ArchiveVideoPlayback.isArchiveUrl(forUrl)) {
            val resolved = ArchiveVideoPlayback.resolvedPlaybackUrl(forUrl)
            return MediaPlaybackConfiguration(resolved, headers = null)
        }
        if (!SupabaseStorageAccess.isPostsBucketUrl(forUrl)) {
            return MediaPlaybackConfiguration(forUrl, headers = null)
        }
        val headers = SupabaseStorageAccess.requestHeaders()
        val authenticated = SupabaseStorageAccess.authenticatedUrl(forUrl)
        if (headers != null && authenticated != null) {
            return MediaPlaybackConfiguration(authenticated, headers)
        }
        val publicUrl = SupabaseStorageAccess.publicUrl(forUrl) ?: forUrl
        return MediaPlaybackConfiguration(publicUrl, headers = null)
    }

    fun playbackFallbackConfiguration(forUrl: String): MediaPlaybackConfiguration? {
        if (!SupabaseStorageAccess.isPostsBucketUrl(forUrl)) return null
        val publicUrl = SupabaseStorageAccess.publicUrl(forUrl) ?: return null
        if (publicUrl == forUrl) return null
        return MediaPlaybackConfiguration(publicUrl, headers = null)
    }
}
