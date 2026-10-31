package com.matterya.matterya.data.hubs

import android.content.Context
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.data.reels.SparkDiscoveryEngine
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.LivingChannelMarker
import com.matterya.matterya.model.PostAuthor
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaCopy

enum class YouTubeMainTab {
    Home, Subscriptions, Library;

    val label: String
        get() = when (this) {
            Home -> "Home"
            Subscriptions -> "Subscriptions"
            Library -> "Library"
        }
}

enum class YouTubeHomeFilter {
    All, Social, Travel, Nature, Music, Food, Sports,
    Tech, Fitness, Film, Culture, Daily, Trending, Recent;

    val title: String
        get() = when (this) {
            All -> "For you"
            Social -> "Social"
            Travel -> "Travel"
            Nature -> "Nature"
            Music -> "Music"
            Food -> "Food"
            Sports -> "Sports"
            Tech -> "Tech"
            Fitness -> "Fitness"
            Film -> "Film"
            Culture -> "Culture"
            Daily -> "Daily"
            Trending -> "Trending"
            Recent -> "Latest"
        }

    val hubSlug: String?
        get() = when (this) {
            All, Trending, Recent -> null
            else -> name.lowercase()
        }

    companion object {
        val hubCategories = listOf(
            Social, Travel, Nature, Music, Food, Sports,
            Tech, Fitness, Film, Culture, Daily, Trending, Recent,
        )
    }
}

enum class YouTubeLibrarySection {
    History, Reels, WatchLater, Liked, Uploads;

    val title: String
        get() = when (this) {
            History -> "History"
            Reels -> MatteryaCopy.sparks
            WatchLater -> "Saved videos"
            Liked -> "Liked videos"
            Uploads -> "Your videos"
        }
}

data class YouTubeChannel(
    val id: String,
    val authorId: String,
    val title: String,
    val handle: String?,
    val author: PostAuthor?,
    val videos: List<CountryPost>,
    val reels: List<CountryPost>,
    val hasCustomChannelName: Boolean,
) {
    val videoCount: Int get() = videos.size
    val reelCount: Int get() = reels.size
    val latestVideo: CountryPost? get() = videos.firstOrNull()
    val totalViews: Int get() = videos.sumOf { it.viewCount }
}

/** iOS `YouTubeCatalogService.swift` — structure + ranking filters + per-user watch history. */
class YouTubeCatalogService private constructor(context: Context) {
    private val prefs = context.getSharedPreferences("matterya_play_catalog", Context.MODE_PRIVATE)
    private var activeUserId: String? = null
    private var playbackPositions = mutableMapOf<String, Double>()
    private var livePlaybackPositions = mutableMapOf<String, Double>()
    private val lastDiskPersistAt = mutableMapOf<String, Long>()

    fun bindToUser(userId: String?) {
        val next = userId?.trim()?.takeIf { it.isNotEmpty() }
        if (next == activeUserId) return
        activeUserId = next
        lastDiskPersistAt.clear()
        livePlaybackPositions.clear()
        playbackPositions.clear()
        if (next != null) {
            val key = positionsKey(next)
            // stored as "id=sec,id=sec"
            val raw = prefs.getString(key, null)
            if (raw != null) {
                for (part in raw.split(",")) {
                    val eq = part.indexOf('=')
                    if (eq <= 0) continue
                    val id = part.substring(0, eq)
                    val sec = part.substring(eq + 1).toDoubleOrNull() ?: continue
                    playbackPositions[id] = sec
                    livePlaybackPositions[id] = sec
                }
            }
        }
    }

    private fun historyKey(userId: String) = "matterya.play.watch_history_v1.$userId"
    private fun positionsKey(userId: String) = "matterya.play.playback_positions_v1.$userId"

    fun livingEligible(post: CountryPost): Boolean = post.hasVideo && !post.isStory

    fun buildChannels(from: List<CountryPost>, profiles: Map<String, Profile> = emptyMap()): List<YouTubeChannel> {
        val eligible = from.filter { livingEligible(it) }
        val grouped = eligible.groupBy { post ->
            when {
                post.isHubSeedVideo || HubVideoSeedService.isArchiveChannelAuthor(post.authorId) ->
                    HubVideoSeedService.ARCHIVE_CHANNEL_AUTHOR_ID
                PlayPlatformBridge.isArchiveCatalogMedia(post) &&
                    !PlayPlatformBridge.isHubChannelUpload(post) ->
                    HubVideoSeedService.ARCHIVE_CHANNEL_AUTHOR_ID
                else -> post.authorId
            }
        }
        val channels = mutableListOf<YouTubeChannel>()
        for ((authorId, posts) in grouped) {
            val isArchive = authorId == HubVideoSeedService.ARCHIVE_CHANNEL_AUTHOR_ID
            val channelPosts = if (isArchive) {
                posts.filter { post ->
                    if (PlayPlatformBridge.isHubFeedReshare(post)) return@filter false
                    if (PlayPlatformBridge.isHubOriginShare(post)) return@filter false
                    post.isHubSeedVideo ||
                        HubVideoSeedService.isArchiveChannelAuthor(post.authorId) ||
                        (PlayPlatformBridge.isArchiveCatalogMedia(post) &&
                            HubVideoSeedService.isArchiveChannelAuthor(post.authorId))
                }
            } else {
                posts.filter { PlayPlatformBridge.isHubChannelUpload(it) }
            }
            val longForm = channelPosts.filter { !it.isReel }.sortedByDescending { it.createdAt }
            val reels = channelPosts.filter { it.isReel }.sortedByDescending { it.createdAt }
            if (longForm.isEmpty() && reels.isEmpty()) continue
            val profile = profiles[authorId]
            val customName = LivingChannelMarker.parse(profile?.bio)
            val author: PostAuthor? = if (isArchive) {
                PostAuthor(
                    userId = HubVideoSeedService.ARCHIVE_CHANNEL_AUTHOR_ID,
                    displayName = HubVideoSeedService.ARCHIVE_CHANNEL_DISPLAY_NAME,
                    username = HubVideoSeedService.ARCHIVE_CHANNEL_USERNAME,
                )
            } else {
                longForm.firstOrNull()?.author ?: reels.firstOrNull()?.author
            }
            val title = if (isArchive) {
                HubVideoSeedService.ARCHIVE_CHANNEL_DISPLAY_NAME
            } else {
                customName ?: author?.displayName ?: author?.username ?: "Channel"
            }
            val handle = if (isArchive) {
                "@${HubVideoSeedService.ARCHIVE_CHANNEL_USERNAME}"
            } else {
                author?.username?.let { "@$it" }
            }
            channels.add(
                YouTubeChannel(
                    id = authorId,
                    authorId = authorId,
                    title = title,
                    handle = handle,
                    author = author,
                    videos = longForm,
                    reels = reels,
                    hasCustomChannelName = isArchive || customName != null,
                ),
            )
        }
        return channels.sortedWith(
            compareByDescending<YouTubeChannel> { it.totalViews }
                .thenByDescending { it.latestVideo?.createdAt ?: "" },
        )
    }

    fun channel(forAuthorId: String, inChannels: List<YouTubeChannel>): YouTubeChannel? =
        inChannels.firstOrNull { it.authorId == forAuthorId }

    fun filterVideos(
        videos: List<CountryPost>,
        homeFilter: YouTubeHomeFilter,
        followingIds: Set<String>,
        viewerCountry: String?,
    ): List<CountryPost> {
        @Suppress("UNUSED_VARIABLE")
        val _f = followingIds
        @Suppress("UNUSED_VARIABLE")
        val _v = viewerCountry
        val base = videos.filter { PlayPlatformBridge.isHubsForYouLongForm(it) }
        return when (homeFilter) {
            YouTubeHomeFilter.All -> base
            YouTubeHomeFilter.Trending -> base.sortedWith(
                compareByDescending<CountryPost> { it.viewCount }.thenByDescending { it.createdAt },
            )
            YouTubeHomeFilter.Recent -> base.sortedByDescending { it.createdAt }
            else -> {
                val slug = homeFilter.hubSlug ?: homeFilter.name.lowercase()
                base.filter { post ->
                    val postSlug = (post.hubSlug ?: post.externalRefId ?: "").lowercase()
                    if (postSlug == slug || postSlug.startsWith("${slug}_")) return@filter true
                    HubCategoryClassifier.parentCategory(postSlug) == slug
                }
            }
        }
    }

    /**
     * iOS `rankForYouBySlugs` — round-robin hub diversity, unviewed/follow/mine first.
     * Replaces pure shuffle on Hubs home.
     */
    fun rankForYouBySlugs(
        videos: List<CountryPost>,
        followingIds: Set<String>,
        myUserId: String?,
        sessionSeed: Long,
        focusSlug: String? = null,
    ): List<CountryPost> {
        val longForm = videos.filter { PlayPlatformBridge.isHubsForYouLongForm(it) }
        if (longForm.isEmpty()) return emptyList()

        val me = myUserId?.trim().orEmpty()
        fun isFollow(p: CountryPost) = p.authorId in followingIds
        fun isMine(p: CountryPost) = me.isNotEmpty() && p.authorId == me

        val buckets = linkedMapOf<String, MutableList<CountryPost>>()
        for (post in longForm) {
            val slug = parentHubSlug(post)
            val focus = focusSlug?.lowercase().orEmpty()
            if (focus.isNotEmpty()) {
                val parent = HubCategoryClassifier.parentCategory(focus)
                if (slug != focus && slug != parent) continue
            }
            buckets.getOrPut(slug) { mutableListOf() }.add(post)
        }

        fun newest(items: List<CountryPost>) = items.sortedByDescending { it.createdAt }

        fun rankSlugQueue(items: List<CountryPost>, salt: Long): List<CountryPost> {
            val followFresh = mutableListOf<CountryPost>()
            val mineFresh = mutableListOf<CountryPost>()
            val otherFresh = mutableListOf<CountryPost>()
            val viewed = mutableListOf<CountryPost>()
            for (p in items) {
                when {
                    SparkDiscoveryEngine.isViewed(p.id) -> viewed.add(p)
                    isMine(p) -> mineFresh.add(p)
                    isFollow(p) -> followFresh.add(p)
                    else -> otherFresh.add(p)
                }
            }
            val others = if (salt == 0L) newest(otherFresh) else seededInterleave(newest(otherFresh), salt)
            return newest(mineFresh) + newest(followFresh) + others + newest(viewed)
        }

        val slugOrder: List<String> = if (!focusSlug.isNullOrBlank()) {
            listOf(HubCategoryClassifier.parentCategory(focusSlug.lowercase()))
        } else {
            var order = HubVideoSeedService.HUB_ORDER.toMutableList()
            if (sessionSeed != 0L && order.size > 1) {
                val rot = (sessionSeed % order.size).toInt()
                order = (order.drop(rot) + order.take(rot)).toMutableList()
            }
            val extras = buckets.keys.filter { it !in order }.sorted()
            order + extras
        }

        val queues = linkedMapOf<String, ArrayDeque<CountryPost>>()
        slugOrder.forEachIndexed { i, slug ->
            val raw = buckets[slug] ?: return@forEachIndexed
            if (raw.isEmpty()) return@forEachIndexed
            val salt = sessionSeed + i * 0x9E37L
            queues[slug] = ArrayDeque(rankSlugQueue(raw, salt))
        }

        // Round-robin across slugs.
        val out = mutableListOf<CountryPost>()
        val seen = mutableSetOf<String>()
        var progressed = true
        while (progressed) {
            progressed = false
            for (slug in slugOrder) {
                val q = queues[slug] ?: continue
                val next = q.removeFirstOrNull() ?: continue
                queues[slug] = q
                if (seen.add(next.id)) {
                    out.add(next)
                    progressed = true
                }
            }
        }
        return out
    }

    private fun parentHubSlug(post: CountryPost): String {
        val raw = (post.hubSlug ?: post.externalRefId ?: "").lowercase()
        if (raw.isEmpty()) return "daily"
        return HubCategoryClassifier.parentCategory(raw)
    }

    private fun seededInterleave(items: List<CountryPost>, seed: Long): List<CountryPost> {
        if (items.size <= 2) return items
        val arr = items.toMutableList()
        var state = if (seed == 0L) 0xC0FFEEL else seed
        val swaps = minOf(arr.size, 8)
        for (i in 0 until swaps) {
            state = state * 6364136223846793005L + 1
            val j = (state.mod(arr.size.toLong())).toInt().coerceIn(0, arr.lastIndex)
            val tmp = arr[i % arr.size]
            arr[i % arr.size] = arr[j]
            arr[j] = tmp
        }
        return arr
    }

    fun reels(from: List<CountryPost>): List<CountryPost> =
        from.filter {
            livingEligible(it) && it.isReel && PlayPlatformBridge.belongsInHubsCatalog(it)
        }.sortedByDescending { it.createdAt }

    fun subscriptionFeed(
        videos: List<CountryPost>,
        channels: List<YouTubeChannel>,
        followingIds: Set<String>,
    ): List<CountryPost> {
        @Suppress("UNUSED_VARIABLE")
        val _c = channels
        return videos.filter {
            livingEligible(it) && it.authorId in followingIds && PlayPlatformBridge.belongsInHubsCatalog(it)
        }.sortedByDescending { it.createdAt }
    }

    fun subscriptionChannels(channels: List<YouTubeChannel>, followingIds: Set<String>): List<YouTubeChannel> =
        channels.filter { it.authorId in followingIds }

    fun likedVideos(videos: List<CountryPost>): List<CountryPost> =
        videos.filter { livingEligible(it) && it.likedByMe }.sortedByDescending { it.createdAt }

    fun myUploads(videos: List<CountryPost>, userId: String?): List<CountryPost> {
        if (userId == null) return emptyList()
        return videos.filter {
            livingEligible(it) && it.authorId == userId && PlayPlatformBridge.isHubChannelUpload(it)
        }.sortedByDescending { it.createdAt }
    }

    fun search(
        query: String,
        videos: List<CountryPost>,
        channels: List<YouTubeChannel>,
    ): Pair<List<CountryPost>, List<YouTubeChannel>> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList<CountryPost>() to emptyList()
        val matchedVideos = videos.filter { livingEligible(it) }.filter { post ->
            (post.displayHeadline?.lowercase()?.contains(q) == true) ||
                post.displayBody.lowercase().contains(q) ||
                post.authorDisplayName.lowercase().contains(q) ||
                (post.author?.username?.lowercase()?.contains(q) == true)
        }
        val matchedChannels = channels.filter {
            it.title.lowercase().contains(q) ||
                (it.handle?.lowercase()?.contains(q) == true) ||
                (it.author?.displayName?.lowercase()?.contains(q) == true)
        }
        return matchedVideos to matchedChannels
    }

    fun recordWatch(postId: String) {
        val userId = activeUserId ?: return
        val history = historyIds().toMutableList()
        history.removeAll { it == postId }
        history.add(0, postId)
        prefs.edit().putString(historyKey(userId), history.take(120).joinToString(",")).apply()
    }

    fun playbackPosition(forPostId: String): Double =
        livePlaybackPositions[forPostId] ?: playbackPositions[forPostId] ?: 0.0

    fun notePlaybackPosition(seconds: Double, forPostId: String, duration: Double? = null) {
        val clamped = maxOf(0.0, seconds)
        if (clamped < 0.5) return
        livePlaybackPositions[forPostId] = clamped
        val now = System.currentTimeMillis()
        val last = lastDiskPersistAt[forPostId]
        if (last != null && now - last < 2000) return
        lastDiskPersistAt[forPostId] = now
        savePlaybackPosition(clamped, forPostId, duration)
    }

    fun savePlaybackPosition(seconds: Double, forPostId: String, duration: Double? = null) {
        val clamped = maxOf(0.0, seconds)
        val prior = playbackPosition(forPostId)
        if (clamped < 1) {
            if (prior >= 1) return
            playbackPositions.remove(forPostId)
            livePlaybackPositions.remove(forPostId)
            persistPlaybackPositions()
            return
        }
        if (duration != null && duration > 0 && clamped >= duration - 2) {
            playbackPositions.remove(forPostId)
            livePlaybackPositions.remove(forPostId)
            persistPlaybackPositions()
            return
        }
        playbackPositions[forPostId] = clamped
        livePlaybackPositions[forPostId] = clamped
        persistPlaybackPositions()
    }

    private fun persistPlaybackPositions() {
        val userId = activeUserId ?: return
        val trimmed = playbackPositions.entries
            .sortedByDescending { it.value }
            .take(80)
            .associate { it.key to it.value }
        playbackPositions = trimmed.toMutableMap()
        prefs.edit().putString(
            positionsKey(userId),
            trimmed.entries.joinToString(",") { "${it.key}=${it.value}" },
        ).apply()
    }

    fun historyIds(): List<String> {
        val userId = activeUserId ?: return emptyList()
        val raw = prefs.getString(historyKey(userId), null) ?: return emptyList()
        return raw.split(",").filter { it.isNotEmpty() }
    }

    fun historyVideos(fromCatalog: List<CountryPost>): List<CountryPost> {
        val ids = historyIds()
        if (ids.isEmpty()) return emptyList()
        val map = fromCatalog.associateBy { it.id }
        return ids.mapNotNull { map[it] }
    }

    fun clearSessionState() {
        bindToUser(null)
    }

    fun relatedVideos(to: CountryPost, from: List<CountryPost>, limit: Int = 12): List<CountryPost> {
        val pool = from.filter { livingEligible(it) && it.id != to.id && !it.isReel }
        val sameAuthor = pool.filter { it.authorId == to.authorId }.shuffled()
        val others = pool.filter { it.authorId != to.authorId }.shuffled()
        return (sameAuthor + others).take(limit)
    }

    companion object {
        @Volatile private var instance: YouTubeCatalogService? = null
        fun get(context: Context): YouTubeCatalogService =
            instance ?: synchronized(this) {
                instance ?: YouTubeCatalogService(context.applicationContext).also { instance = it }
            }
    }
}
