package com.matterya.matterya.theme

/**
 * Mirrors iOS `ContentSanitizer.swift`.
 * Strips internal markers, rebrands competitor names, and cleans display strings.
 */
object ContentSanitizer {
    private val uuidRegex =
        Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", RegexOption.IGNORE_CASE)
    private val longDigits = Regex("^\\d{8,}$")

    private val markerPrefixes = listOf(
        "__story__|",
        "__hub_channel__|",
        "__hub_channel__",
        "__hub_origin__|",
        "__hub_origin__",
        "__spark_share__|",
        "__spark__|",
        "__reel__|",
    )

    private val fakeShareCaptions = setOf(
        "this one 🔥",
        "need this on loop",
        "sending this to everyone",
        "no notes",
        "how is this real",
        "ok wait",
        "the audio though",
        "I'm obsessed",
        "more of this please",
        "mood",
        "saw this and had to share",
        "too good",
        "watch till the end",
        "😂😂😂",
        "//",
    )

    fun looksLikeId(value: String): Boolean {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return false
        if (uuidRegex.matches(trimmed)) return true
        if (trimmed.length == 32 && trimmed.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) return true
        if (longDigits.matches(trimmed)) return true
        if (trimmed.startsWith("user_") && trimmed.length > 12) return true
        if (trimmed.contains("__call__")) return true
        if (trimmed.startsWith("post_") || trimmed.startsWith("conv_") || trimmed.startsWith("msg_")) return true
        val segments = trimmed.split('/')
        if (segments.size > 1 && segments.any { looksLikeId(it) }) return true
        return false
    }

    fun clean(value: String?): String? {
        if (value == null) return null
        val trimmed = rebrandCompetitorNames(stripInternalMarkers(value)).trim()
        if (trimmed.isEmpty() || looksLikeId(trimmed)) return null
        return trimmed
    }

    /**
     * User-facing copy: never show competitor / source-platform names.
     * `subreddit` → `space`, `reddit` → `masquerade`, TikTok → `matterya`.
     */
    fun rebrandCompetitorNames(value: String): String {
        var out = value
        val pairs = listOf(
            Regex("tik\\s*tok", RegexOption.IGNORE_CASE) to "matterya",
            Regex("subreddits", RegexOption.IGNORE_CASE) to "spaces",
            Regex("subreddit", RegexOption.IGNORE_CASE) to "space",
            Regex("\\breddit\\b", RegexOption.IGNORE_CASE) to "masquerade",
            Regex("\\btiktok\\b", RegexOption.IGNORE_CASE) to "matterya",
            Regex("\\br/", RegexOption.IGNORE_CASE) to "space/",
        )
        for ((regex, replacement) in pairs) {
            out = out.replace(regex, replacement)
        }
        return out
    }

    /** Always safe for UI — rebrands even when `clean` would drop the string. */
    fun displayText(value: String?): String {
        if (value == null) return ""
        clean(value)?.let { return it }
        return rebrandCompetitorNames(stripInternalMarkers(value)).trim()
    }

    /**
     * Removes client-only body markers so cards never show raw tokens.
     * Keeps caption text after a marker on the same line.
     */
    fun stripInternalMarkers(value: String): String {
        val kept = value.lines().mapNotNull { raw ->
            var line = raw.trim()
            if (line.isEmpty()) return@mapNotNull null

            for (prefix in markerPrefixes) {
                if (!line.startsWith(prefix)) continue
                line = line.drop(prefix.length).trim()
                if (prefix.startsWith("__spark_share__") && (line.startsWith("sid=") || line.isEmpty())) {
                    return@mapNotNull null
                }
                break
            }

            if (line.isEmpty()) return@mapNotNull null
            if (line.startsWith("__") && line.contains("|")) return@mapNotNull null
            if (line in fakeShareCaptions) return@mapNotNull null
            line
        }
        return kept.joinToString("\n")
    }

    fun stripStoryMarker(value: String): String = stripInternalMarkers(value)

    fun displayName(
        displayName: String?,
        username: String?,
        fallback: String = "Member",
    ): String {
        clean(displayName)?.let { return it }
        clean(username)?.let { return it }
        return fallback
    }
}
