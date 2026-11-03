package com.matterya.matterya.model

/**
 * Mirrors iOS `ContentSanitizer.swift` — used by model display helpers.
 */
object ContentSanitizer {

    fun looksLikeId(value: String): Boolean {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return false

        if (Regex(
                """^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$""",
                RegexOption.IGNORE_CASE,
            ).matches(trimmed)
        ) {
            return true
        }

        if (trimmed.length == 32 && trimmed.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) {
            return true
        }

        if (Regex("""^\d{8,}$""").matches(trimmed)) return true

        if (trimmed.startsWith("user_") && trimmed.length > 12) return true

        if (trimmed.contains("__call__")) return true

        if (trimmed.startsWith("post_") || trimmed.startsWith("conv_") || trimmed.startsWith("msg_")) {
            return true
        }

        val segments = trimmed.split("/")
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
     * User-facing copy: TikTok / YouTube / Facebook / Instagram → matterya;
     * subreddit → space, reddit → masquerade. Mirrors theme.ContentSanitizer.
     */
    fun rebrandCompetitorNames(value: String): String {
        var out = value
        val pairs = listOf(
            Regex("tik\\s*tok", RegexOption.IGNORE_CASE) to "matterya",
            Regex("you\\s*tube", RegexOption.IGNORE_CASE) to "matterya",
            Regex("subreddits", RegexOption.IGNORE_CASE) to "spaces",
            Regex("subreddit", RegexOption.IGNORE_CASE) to "space",
            Regex("\\binstagram\\b", RegexOption.IGNORE_CASE) to "matterya",
            Regex("\\bfacebook\\b", RegexOption.IGNORE_CASE) to "matterya",
            Regex("\\byoutube\\b", RegexOption.IGNORE_CASE) to "matterya",
            Regex("\\breddit\\b", RegexOption.IGNORE_CASE) to "masquerade",
            Regex("\\btiktok\\b", RegexOption.IGNORE_CASE) to "matterya",
            Regex("\\br/", RegexOption.IGNORE_CASE) to "space/",
            Regex("\\bu/", RegexOption.IGNORE_CASE) to "@",
        )
        for ((regex, replacement) in pairs) {
            out = out.replace(regex, replacement)
        }
        return out
    }

    /**
     * Removes client-only body markers so cards never show raw tokens.
     * Keeps real caption text that sits on the same line after a marker.
     */
    fun stripInternalMarkers(value: String): String {
        val markerPrefixes = listOf(
            "__story__|",
            "__hub_channel__|",
            "__hub_channel__",
            "__hub_origin__|",
            "__hub_origin__",
            "__spark_share__|",
            "__spark__|",
            "__reel__|",
        )
        val fakeShareCaptions = setOf(
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

        val kept = value.lines().mapNotNull { raw ->
            var line = raw.trim()
            if (line.isEmpty()) return@mapNotNull null

            for (prefix in markerPrefixes) {
                if (!line.startsWith(prefix)) continue
                line = line.removePrefix(prefix).trim()
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
        clean(displayName)?.takeIf { !DemoPersonNames.isPlaceholderDisplayName(it) }?.let { return it }
        clean(username)?.takeIf { !DemoPersonNames.isPlaceholderDisplayName(it) }?.let { return it }
        return fallback
    }

    fun displayName(
        forAuthor: PostAuthor?,
        authorId: String,
        fallback: String = "Member",
    ): String {
        clean(forAuthor?.displayName)
            ?.takeIf { !DemoPersonNames.isPlaceholderDisplayName(it) }
            ?.let { return it }
        clean(forAuthor?.username)
            ?.takeIf { !DemoPersonNames.isPlaceholderDisplayName(it) }
            ?.let { return it }
        if (authorId.startsWith("user_")) {
            return DemoPersonNames.fullName(authorId, forAuthor?.countryCode)
        }
        return fallback
    }
}

/** Minimal port of iOS `DemoPersonNames` for sanitizer / author labels. */
object DemoPersonNames {
    fun isPlaceholderDisplayName(value: String?): Boolean {
        val raw = value?.trim().orEmpty()
        if (raw.isEmpty()) return true
        if (Regex("""^User\s+\d+$""").matches(raw)) return true
        if (Regex("""^user\d+$""", RegexOption.IGNORE_CASE).matches(raw)) return true
        if (raw.lowercase().startsWith("user_")) return true
        if (raw.equals("Member", ignoreCase = true)) return true
        return false
    }

    fun fullName(forAuthorId: String, countryCode: String? = null): String {
        val seed = hashSeed(forAuthorId)
        val first = FIRST_NAMES[seed % FIRST_NAMES.size]
        val last = LAST_NAMES[(seed / 7) % LAST_NAMES.size]
        return "$first $last"
    }

    private fun hashSeed(value: String): Int {
        var hash = 2166136261L
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            hash = hash xor (byte.toLong() and 0xffL)
            hash *= 16777619L
        }
        return (hash and 0x7fff_ffffL).toInt()
    }

    private val FIRST_NAMES = listOf(
        "Alex", "Sam", "Jordan", "Taylor", "Casey", "Riley", "Morgan", "Avery",
        "Quinn", "Jamie", "Cameron", "Reese", "Drew", "Blake", "Hayden", "Parker",
    )
    private val LAST_NAMES = listOf(
        "Lee", "Nguyen", "Patel", "Garcia", "Kim", "Chen", "Singh", "Brown",
        "Wilson", "Martinez", "Anderson", "Thomas", "Jackson", "White", "Harris", "Clark",
    )
}
