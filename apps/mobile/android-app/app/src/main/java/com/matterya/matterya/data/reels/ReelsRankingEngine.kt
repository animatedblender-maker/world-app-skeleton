package com.matterya.matterya.data.reels

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.HubChannelPostMarker
import com.matterya.matterya.model.SparkShareMarker

/** iOS `ReelsRankingEngine.swift`. */
object ReelsRankingEngine {
    private val sessionWatchedIds = mutableSetOf<String>()

    fun markWatched(postId: String) {
        sessionWatchedIds.add(postId)
    }

    fun resetSession() {
        sessionWatchedIds.clear()
    }

    fun isSparkEligible(post: CountryPost): Boolean {
        if (post.isStory) return false
        if (post.playableVideoUrl == null) return false
        if (SparkShareMarker.isMarked(post.body)) return false
        if (post.isSparkFeedShare) return false
        if (PlayPlatformBridge.isHubOriginShare(post)) return false
        if (!AppConfig.archiveContentEnabled &&
            (post.isArchiveSparkSource || PlayPlatformBridge.isArchiveCatalogMedia(post))
        ) return false
        if (post.isReel) return true
        if (post.isR2HostedMedia && post.hasVideo) {
            val path = (post.mediaUrl ?: "").lowercase() + (post.thumbUrl ?: "").lowercase()
            if (path.contains("longform")) return false
            if (HubChannelPostMarker.isMarked(post.body)) return false
            return true
        }
        return false
    }

    fun resolvePlayerStart(post: CountryPost): CountryPost {
        val embed = post.sharedPost?.asCountryPost
        if (embed != null && embed.playableVideoUrl != null &&
            (isSparkEligible(embed) || embed.isReel)
        ) return embed
        return post
    }

    fun nextBatch(
        from: List<CountryPost>,
        excluding: Set<String>,
        limit: Int,
        viewerCountry: String? = null,
        followingIds: Set<String> = emptySet(),
        tail: List<CountryPost> = emptyList(),
        allowRecycle: Boolean = false,
    ): List<CountryPost> {
        @Suppress("UNUSED_VARIABLE")
        val _v = viewerCountry
        @Suppress("UNUSED_VARIABLE")
        val _f = followingIds
        return SparkDiscoveryEngine.nextBatch(from, excluding, limit, tail, allowRecycle)
    }

    fun sessionFreshOrder(posts: List<CountryPost>): List<CountryPost> =
        SparkDiscoveryEngine.rankForDiscovery(posts.filter { isSparkEligible(it) })

    fun rank(
        posts: List<CountryPost>,
        viewerCountry: String? = null,
        followingIds: Set<String> = emptySet(),
        softenWatchedPenalty: Boolean = false,
    ): List<CountryPost> {
        @Suppress("UNUSED_VARIABLE")
        val _a = viewerCountry
        @Suppress("UNUSED_VARIABLE")
        val _b = followingIds
        @Suppress("UNUSED_VARIABLE")
        val _c = softenWatchedPenalty
        return sessionFreshOrder(posts)
    }

    fun prioritizeR2First(posts: List<CountryPost>): List<CountryPost> {
        val r2 = posts.filter { it.isR2HostedMedia }.shuffled()
        val live = posts.filter { !it.isR2HostedMedia && !it.isArchiveSparkSource }.shuffled()
        if (!AppConfig.archiveContentEnabled) return r2 + live
        val archive = posts.filter { it.isArchiveSparkSource }.shuffled()
        return r2 + live + archive
    }
}

data class ReelsFeedPage(
    val posts: List<CountryPost>,
    val nextCursor: String?,
    val hasMore: Boolean,
)
