package com.matterya.matterya.data.media

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.hubs.HubVideoSeedService
import com.matterya.matterya.data.posts.PostsService
import com.matterya.matterya.data.reels.ReelsRankingEngine
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.HubChannelPostMarker
import com.matterya.matterya.model.HubOriginShareMarker
import com.matterya.matterya.model.PostAuthor
import com.matterya.matterya.model.SparkShareMarker
import java.util.UUID

/** Routes content between Matterya Feed/Messages/Profile and Matterya Hubs. iOS `PlayPlatformBridge.swift`. */
object PlayPlatformBridge {

    fun isHubCatalogContent(post: CountryPost): Boolean {
        if (post.isStory) return false
        if (post.isHubSeedVideo) return true
        if (HubChannelPostMarker.isMarked(post.body)) return true
        if (HubOriginShareMarker.isMarked(post.body)) return true
        if (HubVideoSeedService.isArchiveChannelAuthor(post.authorId)) return true
        if (isArchiveCatalogMedia(post)) return true
        val id = post.id.lowercase()
        if (id.startsWith("ia_") || id.startsWith("hub_") || id.startsWith("hub_spark_")) return true
        return false
    }

    fun isArchiveCatalogMedia(post: CountryPost): Boolean {
        if (post.isHubSeedVideo) return true
        post.playableVideoUrl?.let { if (ArchiveVideoPlayback.isArchiveUrl(it)) return true }
        val media = (post.mediaUrl ?: "").lowercase()
        if (media.contains("archive.org")) return true
        val thumb = (post.thumbUrl ?: "").lowercase()
        if (thumb.contains("archive.org")) return true
        val id = post.id.lowercase()
        if (id.startsWith("ia_") || id.startsWith("hub_spark_")) return true
        val ext = post.externalRefId?.lowercase()
        if (ext != null && (ext.startsWith("ia_") || ext.startsWith("hub_"))) return true
        return false
    }

    fun isHubFeedReshare(post: CountryPost): Boolean = isFeedOnlyShare(post)

    fun isFeedOnlyShare(post: CountryPost): Boolean {
        if (post.isStory) return false
        if (isHubOriginShare(post)) return true
        if (SparkShareMarker.isMarked(post.body)) return true
        if (post.isSparkFeedShare) return true
        val shared = post.sharedPostId
        if (!shared.isNullOrEmpty() && !HubChannelPostMarker.isMarked(post.body)) return true
        if (isArchiveCatalogMedia(post) &&
            !HubVideoSeedService.isArchiveChannelAuthor(post.authorId) &&
            !post.isHubSeedVideo
        ) return true
        if (isLikelyLiveUserAuthor(post.authorId) &&
            post.hasVideo &&
            !HubChannelPostMarker.isMarked(post.body) &&
            !post.isHubSeedVideo &&
            !HubVideoSeedService.isArchiveChannelAuthor(post.authorId)
        ) return true
        return false
    }

    fun isLikelyLiveUserAuthor(authorId: String): Boolean {
        val id = authorId.trim()
        if (id.isEmpty()) return false
        if (HubVideoSeedService.isArchiveChannelAuthor(id)) return false
        if (id.startsWith("hub_") || id.startsWith("user_") || id.startsWith("demo_")) return false
        return try {
            UUID.fromString(id); true
        } catch (_: Exception) {
            false
        }
    }

    fun isHubChannelUpload(post: CountryPost): Boolean {
        if (!post.hasVideo || post.isStory) return false
        if (isFeedOnlyShare(post)) return false
        if (post.sharedPostId != null) return false
        if (isArchiveCatalogMedia(post)) return false
        return HubChannelPostMarker.isMarked(post.body)
    }

    fun isHubOriginShare(post: CountryPost): Boolean = HubOriginShareMarker.isMarked(post.body)

    fun belongsInHubsCatalog(post: CountryPost): Boolean {
        if (post.isStory) return false
        val archiveOn = AppConfig.archiveContentEnabled
        if (post.isHubSeedVideo) {
            if (!archiveOn) return false
            return post.hasVideo || post.playableVideoUrl != null
        }
        if (HubVideoSeedService.isArchiveChannelAuthor(post.authorId)) {
            if (!archiveOn) return false
            return post.hasVideo || post.playableVideoUrl != null
        }
        val id = post.id.lowercase()
        if ((id.startsWith("ia_") || id.startsWith("hub_spark_")) && !isLikelyLiveUserAuthor(post.authorId)) {
            if (!archiveOn) return false
            return post.hasVideo || post.playableVideoUrl != null
        }
        if (!archiveOn && isArchiveCatalogMedia(post)) return false
        if (!post.hasVideo) return false
        if (isHubOriginShare(post)) return true
        if (isFeedOnlyShare(post)) return false
        if (isHubChannelUpload(post)) return true
        val media = (post.mediaUrl ?: post.playableVideoUrl)?.lowercase()
        if (media != null) {
            if (media.contains("longform/") || media.contains("/longform")) {
                return !post.isReel
            }
            if (media.contains("matterya-sparks") && !post.isReel &&
                !media.contains("/spark") && !media.contains("/sparks/")
            ) {
                return true
            }
        }
        return false
    }

    fun isHubCatalogOwnedContent(post: CountryPost): Boolean = belongsInHubsCatalog(post)

    fun hubWatchPresentation(post: CountryPost): CountryPost {
        val origin = HubOriginShareMarker.originPresentation(post)
        if (origin != null && (origin.authorId != post.authorId || origin.authorId.startsWith("hub_"))) {
            return origin
        }
        return post
    }

    data class DisplayCreator(
        val name: String,
        val avatarUrl: String?,
        val seed: String,
        val authorId: String,
        val username: String?,
    )

    fun displayCreator(post: CountryPost): DisplayCreator {
        HubOriginShareMarker.originPresentation(post)?.let { origin ->
            val name = origin.authorDisplayName.trim()
            val avatar = origin.author?.avatarUrl ?: post.sharedPost?.asCountryPost?.author?.avatarUrl
            return DisplayCreator(
                name = name.ifEmpty { HubVideoSeedService.ARCHIVE_CHANNEL_DISPLAY_NAME },
                avatarUrl = avatar,
                seed = origin.authorId,
                authorId = origin.authorId,
                username = origin.author?.username,
            )
        }
        if (isArchiveCatalogMedia(post) || HubVideoSeedService.isArchiveChannelAuthor(post.authorId)) {
            return DisplayCreator(
                name = HubVideoSeedService.ARCHIVE_CHANNEL_DISPLAY_NAME,
                avatarUrl = null,
                seed = HubVideoSeedService.ARCHIVE_CHANNEL_AUTHOR_ID,
                authorId = HubVideoSeedService.ARCHIVE_CHANNEL_AUTHOR_ID,
                username = HubVideoSeedService.ARCHIVE_CHANNEL_USERNAME,
            )
        }
        val embed = post.sharedPost?.asCountryPost
        if (embed != null && embed.authorId.isNotEmpty() && embed.authorId != post.authorId &&
            (embed.isHubSeedVideo || isHubCatalogContent(embed) || embed.authorId.startsWith("hub_"))
        ) {
            return DisplayCreator(
                name = embed.authorDisplayName,
                avatarUrl = embed.author?.avatarUrl,
                seed = embed.authorId,
                authorId = embed.authorId,
                username = embed.author?.username,
            )
        }
        return DisplayCreator(
            name = post.authorDisplayName,
            avatarUrl = post.author?.avatarUrl,
            seed = post.authorId,
            authorId = post.authorId,
            username = post.author?.username,
        )
    }

    fun withChannelIdentity(post: CountryPost, channel: CountryPost): CountryPost {
        if (channel.authorId.isEmpty()) return post
        val author = channel.author ?: PostAuthor(
            userId = channel.authorId,
            displayName = channel.authorDisplayName,
            username = channel.author?.username,
            avatarUrl = channel.author?.avatarUrl,
            countryName = channel.countryName,
            countryCode = channel.countryCode,
        )
        return post.copy(
            title = post.title ?: channel.title,
            mediaType = post.mediaType ?: channel.mediaType,
            mediaUrl = post.mediaUrl ?: channel.mediaUrl,
            thumbUrl = post.thumbUrl ?: channel.thumbUrl,
            mediaCaption = post.mediaCaption ?: channel.mediaCaption,
            authorId = channel.authorId,
            countryName = channel.countryName ?: post.countryName,
            countryCode = channel.countryCode ?: post.countryCode,
            author = author,
            linkUrl = post.linkUrl ?: channel.linkUrl,
            linkTitle = post.linkTitle ?: channel.linkTitle,
            externalRefType = post.externalRefType ?: channel.externalRefType,
            externalRefId = post.externalRefId ?: channel.externalRefId,
        )
    }

    suspend fun resolveHubWatchPresentation(post: CountryPost, postsService: PostsService = PostsService()): CountryPost {
        val media = post.mediaUrl ?: post.playableVideoUrl
        HubVideoSeedService.postMatchingMediaUrl(media)?.let { return overlayShareMedia(post, it) }

        HubOriginShareMarker.parseFields(post.body)?.get("sid")?.takeIf { it.isNotEmpty() }?.let { sid ->
            HubVideoSeedService.post(sid)?.let { return overlayShareMedia(post, it) }
            runCatching { postsService.getPostById(sid) }.getOrNull()?.let { remote ->
                if (remote.authorId.startsWith("hub_") || remote.isHubSeedVideo) {
                    return overlayShareMedia(post, remote)
                }
                HubVideoSeedService.postMatchingMediaUrl(remote.mediaUrl ?: remote.playableVideoUrl)
                    ?.let { return overlayShareMedia(post, it) }
            }
        }

        HubVideoSeedService.post(post.id)?.let { return it }
        if (post.isHubSeedVideo) return post

        HubOriginShareMarker.originPresentation(post)?.let { origin ->
            if (origin.authorId != post.authorId) return origin
        }
        return post
    }

    private fun overlayShareMedia(share: CountryPost, origin: CountryPost): CountryPost =
        origin.copy(
            mediaType = share.mediaType ?: origin.mediaType,
            mediaUrl = share.mediaUrl ?: origin.mediaUrl,
            thumbUrl = share.thumbUrl ?: origin.thumbUrl,
            mediaCaption = origin.mediaCaption ?: share.mediaCaption,
            sharedPostId = share.sharedPostId,
            sharedPost = share.sharedPost,
            visibility = share.visibility,
            createdAt = origin.createdAt.ifEmpty { share.createdAt },
            updatedAt = origin.updatedAt.ifEmpty { share.updatedAt },
            countryName = origin.countryName ?: share.countryName,
            countryCode = origin.countryCode ?: share.countryCode,
            cityName = origin.cityName ?: share.cityName,
            externalRefType = origin.externalRefType ?: "hub",
            externalRefId = origin.externalRefId ?: origin.hubSlug,
        )

    fun isPlayEligible(post: CountryPost): Boolean = post.hasVideo && !post.isStory

    fun isLongFormVideo(post: CountryPost): Boolean =
        isPlayEligible(post) && !post.isReel && !post.isSpark && !isSparkFeedCard(post)

    fun isHubsForYouLongForm(post: CountryPost): Boolean {
        if (!isPlayEligible(post) || post.isStory) return false
        if (post.isReel || post.isSpark || isSparkFeedCard(post)) return false
        if (ReelsRankingEngine.isSparkEligible(post)) return false
        val type = (post.mediaType ?: "").lowercase()
        if (type == "reel" || type == "spark") return false
        if (post.isHubSeedVideo ||
            HubVideoSeedService.isArchiveChannelAuthor(post.authorId) ||
            post.id.lowercase().startsWith("ia_")
        ) return true
        return isHubCatalogContent(post) || isHubChannelUpload(post) ||
            isHubOriginShare(post) || isHubFeedCardVideo(post)
    }

    fun isHubFeedCardVideo(post: CountryPost): Boolean {
        if (!isHubCatalogContent(post) || !post.hasVideo || post.isStory) return false
        if (post.isReel || post.isSparkFeedShare || SparkShareMarker.isMarked(post.body)) return false
        return true
    }

    fun isReelVideo(post: CountryPost): Boolean = isPlayEligible(post) && post.isReel

    fun isSparkFeedCard(post: CountryPost): Boolean {
        if (post.isStory) return false
        if (post.isSparkFeedShare || SparkShareMarker.isMarked(post.body)) return true
        if (post.isReel || isReelVideo(post)) return true
        val embed = post.sharedPost?.asCountryPost
        if (embed != null && (embed.isReel || isReelVideo(embed))) return true
        return false
    }

    fun shareUrl(post: CountryPost): String {
        val id = post.sharedPostId ?: post.id
        if (isSparkFeedCard(post)) return "https://matterya.com/post/$id"
        if (isHubCatalogContent(post) && post.hasVideo) return "https://matterya.com/play/watch/$id"
        return "https://matterya.com/post/$id"
    }

    fun showsPlayLinkInFeed(post: CountryPost, context: MediaContext = MediaContext.Feed): Boolean {
        if (context != MediaContext.Feed) return false
        if (isSparkFeedCard(post)) return false
        return isHubFeedCardVideo(post)
    }

    fun channelUrl(authorId: String, username: String?): String {
        if (!username.isNullOrEmpty()) return "https://matterya.com/play/channel/$username"
        return "https://matterya.com/play/channel/id/$authorId"
    }
}

enum class MediaContext { Feed, Profile, Hubs, Chat }
