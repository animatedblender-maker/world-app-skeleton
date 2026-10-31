package com.matterya.matterya.data.hubs

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.HubArchiveIdentity

/**
 * Structure port of iOS `HubVideoSeedService` — catalog APIs return empty while
 * [AppConfig.archiveContentEnabled] is false (same default as iOS).
 */
object HubVideoSeedService {
    const val SPARK_MAX_DURATION_SECONDS = 60.0
    const val ARCHIVE_CHANNEL_AUTHOR_ID = HubArchiveIdentity.archiveChannelAuthorId
    const val ARCHIVE_CHANNEL_DISPLAY_NAME = HubArchiveIdentity.archiveChannelDisplayName
    const val ARCHIVE_CHANNEL_USERNAME = HubArchiveIdentity.archiveChannelUsername

    /** iOS `HubVideoSeedService.hubOrder` — shelf / For you round-robin order. */
    val HUB_ORDER: List<String> = listOf(
        "social", "travel", "nature", "music", "food", "sports",
        "tech", "fitness", "film", "culture", "daily",
    )

    fun isArchiveChannelAuthor(authorId: String?): Boolean =
        HubArchiveIdentity.isArchiveChannelAuthor(authorId)

    suspend fun post(id: String): CountryPost? {
        if (!AppConfig.archiveContentEnabled) return null
        return null // seed catalog not loaded on Android yet
    }

    suspend fun postMatchingMediaUrl(media: String?): CountryPost? {
        if (!AppConfig.archiveContentEnabled) return null
        return null
    }

    suspend fun allVideos(): List<CountryPost> =
        if (AppConfig.archiveContentEnabled) emptyList() else emptyList()
}
