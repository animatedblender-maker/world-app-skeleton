package com.matterya.matterya.data.media

/**
 * Minimal port surface of iOS `ArchiveVideoPlayback` used by PlayPlatform / MediaURLResolver.
 * Full CDN resolve can be layered later; identity helpers match iOS.
 */
object ArchiveVideoPlayback {
    fun isArchiveUrl(url: String?): Boolean {
        val lower = url?.lowercase().orEmpty()
        return lower.contains("archive.org")
    }

    suspend fun resolvedPlaybackUrl(url: String): String {
        // iOS resolves 302 CDN; for now return original (ExoPlayer follows redirects).
        return url
    }

    fun warmResolve(url: String) {
        // no-op warm on Android until full archive player lands
    }
}
