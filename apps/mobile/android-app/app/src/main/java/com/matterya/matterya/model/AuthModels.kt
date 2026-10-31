package com.matterya.matterya.model

import com.matterya.matterya.theme.MatteryaCopy

data class AuthUser(
    val id: String,
    val email: String? = null,
)

data class AuthSession(
    val accessToken: String,
    val refreshToken: String,
    val expiresAt: Double,
    val user: AuthUser,
)

data class RegisterResult(
    val needsEmailConfirm: Boolean,
    val isExistingEmail: Boolean,
)

data class AccountActionResult(
    val ok: Boolean,
    val action: String = "",
    val message: String? = null,
    val accountStatus: String = "active",
)

data class GlobalStats(
    val totalUsers: Int,
    val onlineUsers: Int,
)

data class CountryStats(
    val countryCode: String,
    val totalUsers: Int,
    val onlineUsers: Int,
)

enum class GlobePanel {
    NOTIFICATIONS,
    PRESENCE,
    ;

    val rawValue: String
        get() = when (this) {
            NOTIFICATIONS -> "notifications"
            PRESENCE -> "presence"
        }

    val id: String get() = rawValue
}

enum class CountryTab {
    POSTS,
    FOLLOWING,
    MEDIA,
    STATS,
    NEWS,
    ;

    val rawValue: String
        get() = when (this) {
            POSTS -> "posts"
            FOLLOWING -> "following"
            MEDIA -> "media"
            STATS -> "stats"
            NEWS -> "news"
        }

    val id: String get() = rawValue
    val title: String get() = rawValue.uppercase()
}

enum class AppTab {
    Feed,
    Globe,
    Hubs,
    Messages,
    Profile,
    ;

    val rawValue: String
        get() = when (this) {
            Feed -> "feed"
            Globe -> "globe"
            Hubs -> "hubs"
            Messages -> "messages"
            Profile -> "profile"
        }

    val id: String get() = rawValue

    val title: String
        get() = when (this) {
            Feed -> "Feed"
            Globe -> "Globe"
            Hubs -> MatteryaCopy.matteryaHubs
            Messages -> "Messages"
            Profile -> "Profile"
        }

    /** Android Material icon names (iOS uses SF Symbols). */
    val systemImage: String
        get() = when (this) {
            Feed -> "house"
            Globe -> "globe.americas"
            Hubs -> "square.grid.2x2"
            Messages -> "bubble.left.and.bubble.right"
            Profile -> "person.circle"
        }
}

sealed class AppDestination {
    data class Post(val postId: String) : AppDestination() {
        companion object {
            fun from(postId: String) = "post/$postId"
            const val routePattern = "post/{postId}"
        }
    }

    data class News(val newsId: String) : AppDestination() {
        companion object {
            fun from(newsId: String) = "news/$newsId"
            const val routePattern = "news/{newsId}"
        }
    }

    data class Reels(val country: Country) : AppDestination() {
        companion object {
            fun from(iso: String) = "reels/$iso"
            const val routePattern = "reels/{iso}"
        }
    }

    data class CountryFeed(val country: Country) : AppDestination() {
        companion object {
            fun from(iso: String) = "country-feed/$iso"
            const val routePattern = "country-feed/{iso}"
        }
    }

    data object Search : AppDestination() {
        const val path = "search"
    }

    data class PublicProfile(val username: String) : AppDestination() {
        companion object {
            fun from(username: String) = "profile/$username"
            const val routePattern = "profile/{username}"
        }
    }

    data class PublicProfileByUserId(val userId: String) : AppDestination() {
        companion object {
            fun from(userId: String) = "profile-id/$userId"
            const val routePattern = "profile-id/{userId}"
        }
    }

    /** Alias used by some navigation call sites. */
    data class PublicProfileById(val userId: String) : AppDestination() {
        companion object {
            fun from(userId: String) = "profile-id/$userId"
            const val routePattern = "profile-id/{userId}"
        }
    }

    data class PlayWatch(val postId: String) : AppDestination() {
        companion object {
            fun from(postId: String) = "play-watch/$postId"
            const val routePattern = "play-watch/{postId}"
        }
    }

    data class PlayChannel(val username: String) : AppDestination() {
        companion object {
            fun from(username: String) = "play-channel/$username"
            const val routePattern = "play-channel/{username}"
        }
    }

    data class PlayChannelId(val channelId: String) : AppDestination() {
        companion object {
            fun from(channelId: String) = "play-channel-id/$channelId"
            const val routePattern = "play-channel-id/{channelId}"
        }
    }

    data object People : AppDestination() {
        const val path = "people"
    }

    data object Ads : AppDestination() {
        const val path = "ads"
    }

    data object EditProfile : AppDestination() {
        const val path = "edit-profile"
    }

    data object Settings : AppDestination() {
        const val path = "settings"
    }

    data object Premium : AppDestination() {
        const val path = "premium"
    }

    data class Conversation(val conversationId: String) : AppDestination() {
        companion object {
            fun from(conversationId: String) = "conversation/$conversationId"
            const val routePattern = "conversation/{conversationId}"
        }
    }

    data object Letters : AppDestination() {
        const val path = "letters"
    }

    data class LetterThread(val threadId: String) : AppDestination() {
        companion object {
            fun from(threadId: String) = "letter-thread/$threadId"
            const val routePattern = "letter-thread/{threadId}"
        }
    }

    val id: String
        get() = when (this) {
            is Post -> "post-$postId"
            is News -> "news-$newsId"
            is Reels -> "reels-${country.iso}"
            is CountryFeed -> "country-feed-${country.iso}"
            Search -> "search"
            is PublicProfile -> "profile-$username"
            is PublicProfileByUserId -> "profile-id-$userId"
            is PublicProfileById -> "profile-id-$userId"
            is PlayWatch -> "play-watch-$postId"
            is PlayChannel -> "play-channel-$username"
            is PlayChannelId -> "play-channel-id-$channelId"
            People -> "people"
            Ads -> "ads"
            EditProfile -> "edit-profile"
            Settings -> "settings"
            Premium -> "premium"
            is Conversation -> "conversation-$conversationId"
            Letters -> "letters"
            is LetterThread -> "letter-thread-$threadId"
        }
}
