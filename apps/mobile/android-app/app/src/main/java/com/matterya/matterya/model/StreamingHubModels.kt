package com.matterya.matterya.model

import com.matterya.matterya.data.hubs.StreamingHubRoomKey
import java.util.Date

/** iOS `ConnectedHubModels.swift` + `LivePlaybackModels.swift`. */
enum class StreamingPlatform(val rawValue: String) {
    Netflix("netflix"),
    AppleMusic("appleMusic"),
    AppleTV("appleTV"),
    Spotify("spotify"),
    Disney("disney"),
    ;

    val id: String get() = rawValue

    val apiSlug: String
        get() = when (this) {
            Netflix -> "netflix"
            AppleMusic -> "apple_music"
            AppleTV -> "apple_tv"
            Spotify -> "spotify"
            Disney -> "disney"
        }

    val title: String
        get() = when (this) {
            Netflix -> "Netflix"
            AppleMusic -> "Apple Music"
            AppleTV -> "Apple TV+"
            Spotify -> "Spotify"
            Disney -> "Disney+"
        }

    val isAvailable: Boolean
        get() = when (this) {
            Netflix, AppleMusic, AppleTV -> true
            Spotify, Disney -> false
        }

    companion object {
        fun fromApiSlug(slug: String): StreamingPlatform? = when (slug.lowercase()) {
            "netflix" -> Netflix
            "apple_music" -> AppleMusic
            "apple_tv" -> AppleTV
            "spotify" -> Spotify
            "disney" -> Disney
            else -> null
        }

        val allCases: List<StreamingPlatform> = entries
    }
}

data class ConnectedAccount(
    val id: String,
    val platform: StreamingPlatform,
    val isLinked: Boolean,
    val sharingEnabled: Boolean,
)

data class YourNowPlaying(
    val id: String,
    val platform: StreamingPlatform,
    val title: String,
    val subtitle: String,
    val progressLabel: String,
    val progress: Double,
    val isSharing: Boolean,
    val momentLabel: String? = null,
    val contentId: String? = null,
    val progressMs: Int = 0,
    val durationMs: Int = 0,
    val updatedAt: Date = Date(),
) {
    val liveState: LivePlaybackState
        get() = LivePlaybackState(
            contentId = contentId,
            title = title,
            subtitle = subtitle,
            momentLabel = momentLabel,
            progressMs = progressMs,
            durationMs = durationMs,
            updatedAt = updatedAt,
            isPlaying = isSharing,
            platform = platform,
        )
}

data class FriendActivity(
    val id: String,
    val name: String,
    val avatarUrl: String?,
    val avatarSeed: String,
    val platform: StreamingPlatform,
    val title: String,
    val subtitle: String,
    val detail: String,
    val isLive: Boolean,
    val contentId: String? = null,
    val progressMs: Int = 0,
    val durationMs: Int = 0,
    val updatedAt: Date = Date(),
) {
    val liveState: LivePlaybackState
        get() = LivePlaybackState(
            contentId = contentId,
            title = title,
            subtitle = subtitle,
            momentLabel = null,
            progressMs = progressMs,
            durationMs = durationMs,
            updatedAt = updatedAt,
            isPlaying = isLive,
            platform = platform,
        )
}

data class MomentRoom(
    val id: String,
    val roomKey: String,
    val platform: StreamingPlatform,
    val showTitle: String,
    val episodeLabel: String,
    val timestamp: String,
    val activeFriends: Int,
    val previewComments: List<MomentComment>,
    val heat: Double,
)

data class MomentComment(
    val id: String,
    val author: String,
    val body: String,
    val reactions: Int,
)

data class ConnectedHubSnapshot(
    val accounts: List<ConnectedAccount>,
    val nowPlaying: List<YourNowPlaying>,
    val friends: List<FriendActivity>,
    val momentRooms: List<MomentRoom>,
)

data class LivePlaybackState(
    val contentId: String?,
    val title: String,
    val subtitle: String,
    val momentLabel: String?,
    val progressMs: Int,
    val durationMs: Int,
    val updatedAt: Date,
    val isPlaying: Boolean,
    val platform: StreamingPlatform,
) {
    val liveProgressMs: Int
        get() {
            if (!isPlaying) return progressMs
            val elapsed = ((System.currentTimeMillis() - updatedAt.time)).toInt().coerceAtLeast(0)
            return (progressMs + elapsed).coerceAtMost(durationMs)
        }

    val progress: Double
        get() {
            if (durationMs <= 0) return 0.0
            return (liveProgressMs.toDouble() / durationMs.toDouble()).coerceIn(0.0, 1.0)
        }

    val progressLabel: String
        get() = StreamingHubRoomKey.formatTimestamp(liveProgressMs)

    val canJoinSession: Boolean
        get() = platform == StreamingPlatform.AppleMusic && !contentId.isNullOrEmpty()
}

object ConnectedHubContent {
    val ecosystemTeasers: List<Pair<String, String>> = listOf(
        "shopping" to "Shopping with friends — vote on drops, split carts, share finds",
        "events" to "Live events — concerts & sports with a shared watch thread",
        "reading" to "Reading circles — same chapter, same reactions",
    )

    fun mergedAccounts(remote: List<ConnectedAccount>): List<ConnectedAccount> {
        val remoteByPlatform = remote.associateBy { it.platform }
        return StreamingPlatform.allCases.map { platform ->
            remoteByPlatform[platform] ?: ConnectedAccount(
                id = platform.rawValue,
                platform = platform,
                isLinked = false,
                sharingEnabled = false,
            )
        }
    }
}
