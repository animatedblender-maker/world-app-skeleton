package com.matterya.matterya.model

import com.matterya.matterya.theme.MatteryaCopy
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Profile(
    @SerialName("user_id") val userId: String = "",
    val email: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("country_name") val countryName: String? = null,
    @SerialName("country_code") val countryCode: String? = null,
    @SerialName("city_name") val cityName: String? = null,
    val bio: String? = null,
    @SerialName("followers_count") val followersCount: Int? = null,
    @SerialName("following_count") val followingCount: Int? = null,
    /** active | deactivated | deleted */
    @SerialName("account_status") val accountStatus: String? = null,
    @SerialName("deactivated_at") val deactivatedAt: String? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
) {
    val id: String get() = userId

    val isComplete: Boolean
        get() {
            val name = displayName?.trim().orEmpty()
            val country = countryName?.trim().orEmpty()
            return name.isNotEmpty() && country.isNotEmpty() && country != "Unknown"
        }

    val isDemoUser: Boolean get() = userId.startsWith("user_")

    val isDeactivated: Boolean
        get() = (accountStatus ?: "active").lowercase() == "deactivated"

    val isDeleted: Boolean
        get() = (accountStatus ?: "active").lowercase() == "deleted"

    val displayLabel: String
        get() = ContentSanitizer.displayName(displayName, username)
}

data class Country(
    val id: String,
    val name: String,
    val iso: String,
    val continent: String? = null,
    val centerLat: Double? = null,
    val centerLng: Double? = null,
)

data class DetectedLocation(
    val countryCode: String,
    val countryName: String,
    val cityName: String? = null,
    val source: String,
)

data class FollowCounts(
    val followers: Int,
    val following: Int,
)

enum class ProfileLibrarySection {
    POSTS,
    SAVED_POSTS,
    SAVED_VIDEOS,
    SAVED_REELS,
    ;

    val rawValue: String
        get() = when (this) {
            POSTS -> "posts"
            SAVED_POSTS -> "savedPosts"
            SAVED_VIDEOS -> "savedVideos"
            SAVED_REELS -> "savedReels"
        }

    val id: String get() = rawValue

    val title: String
        get() = when (this) {
            POSTS -> "Posts"
            SAVED_POSTS -> "Saved posts"
            SAVED_VIDEOS -> "Saved videos"
            SAVED_REELS -> MatteryaCopy.savedSparks
        }
}
