package com.matterya.matterya.data.posts

import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.graphql.GqlOps
import com.matterya.matterya.data.graphql.GraphQlClient
import com.matterya.matterya.data.graphql.GraphQlException
import com.matterya.matterya.data.reels.ReelsRankingEngine
import com.matterya.matterya.data.reels.SparkDiscoveryEngine
import com.matterya.matterya.data.social.FollowService
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.GraphQLComment
import com.matterya.matterya.model.GraphQLPost
import com.matterya.matterya.model.HubChannelPostMarker
import com.matterya.matterya.model.HubOriginShareMarker
import com.matterya.matterya.model.PostComment
import com.matterya.matterya.model.PostMediaPayload
import com.matterya.matterya.model.PostStoryMarker
import com.matterya.matterya.model.PostVisibility
import com.matterya.matterya.model.SparkShareMarker
import com.matterya.matterya.model.StoryGroup
import com.matterya.matterya.model.excludingSparks
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * GraphQL posts service — full parity with iOS `PostsService.swift`
 * (queries/mutations + feed helpers that do not depend on iOS-only seed services).
 */
class PostsService(
    private val gql: GraphQlClient = GraphQlClient(),
    private val auth: AuthService = AuthService.instance,
    private val follow: FollowService = FollowService(gql),
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val viewedPostIds = ConcurrentHashMap.newKeySet<String>()
    var hubsSessionCatalog: List<CountryPost> = emptyList()
        private set
    private var sparksSessionCatalog: List<CountryPost> = emptyList()
    private var sparksCatalogWarmAt: Long = 0L
    private val profileCountryCode = AtomicReferenceLike<String?>(null)
    private var profilePostsCache: List<CountryPost> = emptyList()

    // ── Country / author / search ──────────────────────────────────────

    suspend fun listByCountry(countryCode: String, limit: Int = 25): List<CountryPost> {
        val code = countryCode.uppercase()
        return fetchRealPostsByCountry(code, limit)
    }

    suspend fun listForAuthor(authorId: String, limit: Int = 25): List<CountryPost> {
        val data = gql.request(
            GqlOps.postsByAuthor(),
            mapOf(
                "authorId" to JsonPrimitive(authorId),
                "limit" to JsonPrimitive(limit),
            ),
        )
        return mapPosts(data["postsByAuthor"])
    }

    suspend fun loadFollowingFeed(limitPerAuthor: Int = 4, maxAuthors: Int = 12): List<CountryPost> {
        val followingIds = follow.followingIds().toList().take(maxAuthors)
        if (followingIds.isEmpty()) return emptyList()
        return coroutineScope {
            followingIds.map { id ->
                async { runCatching { listForAuthor(id, limitPerAuthor) }.getOrDefault(emptyList()) }
            }.awaitAll().flatten()
                .sortedByDescending { it.createdAt }
        }
    }

    suspend fun loadCountryFeedPosts(
        countryIso: String,
        localLimit: Int = 30,
        followingLimitPerAuthor: Int = 5,
        maxAuthors: Int = 24,
    ): List<CountryPost> {
        val iso = countryIso.uppercase()
        return coroutineScope {
            val localDeferred = async { listByCountry(iso, localLimit) }
            val followingDeferred = async {
                loadFollowingFeed(followingLimitPerAuthor, maxAuthors)
            }
            val local = localDeferred.await()
            val following = followingDeferred.await()
            val localIds = local.map { it.id }.toSet()
            val abroad = following.filter { post ->
                val postIso = post.countryCode?.uppercase().orEmpty()
                postIso.isNotEmpty() && postIso != iso && post.id !in localIds
            }
            chronologicalNewestFirst(local + abroad)
        }
    }

    suspend fun searchPosts(query: String, limit: Int = 20): List<CountryPost> {
        val data = gql.request(
            GqlOps.searchPosts(),
            mapOf(
                "query" to JsonPrimitive(query),
                "limit" to JsonPrimitive(limit),
            ),
        )
        return mapPosts(data["searchPosts"]).excludingSparks()
    }

    suspend fun getPostById(postId: String): CountryPost? {
        val data = gql.request(
            GqlOps.postById(),
            mapOf("postId" to JsonPrimitive(postId)),
        )
        val row = data["postById"] ?: return null
        return runCatching { json.decodeFromJsonElement<GraphQLPost>(row).toModel }.getOrNull()
    }

    // ── Home / recent feed ─────────────────────────────────────────────

    suspend fun fetchRecentPosts(limit: Int = 40, before: String? = null): List<CountryPost> {
        val vars = buildMap {
            put("limit", JsonPrimitive(limit))
            if (!before.isNullOrEmpty()) put("before", JsonPrimitive(before))
        }
        var real: List<CountryPost> = emptyList()
        for (attempt in 0 until 2) {
            try {
                val data = gql.request(GqlOps.recentPosts(), vars)
                real = mapPosts(data["recentPosts"])
                break
            } catch (_: Exception) {
                if (attempt == 0) {
                    runCatching { auth.ensureValidToken() }
                    continue
                }
                real = emptyList()
            }
        }
        if (real.isEmpty()) {
            real = fallbackGlobalPosts(limit)
        }
        return real
    }

    suspend fun fetchFirstPaintHomePosts(limit: Int = 40): List<CountryPost> {
        val pageLimit = limit.coerceIn(24, 48)
        return coroutineScope {
            val recentDeferred = async { fetchRecentPosts(pageLimit) }
            val ownDeferred = async { fetchOwnPosts(12) }
            val recent = recentDeferred.await()
            val own = ownDeferred.await()
            var combined = (own + recent)
                .excludingSparks()
                .filter { !it.isStory }
                .filter { !it.isSeededOrSynthetic || it.isSparkFeedShare || it.isHubOriginFeedShare }
            combined = liveFeedFilter(combined)
            chronologicalNewestFirst(combined).take(limit)
        }
    }

    suspend fun fetchNetworkHomePosts(limit: Int = 80): List<CountryPost> {
        val cap = limit.coerceIn(40, 100)
        return coroutineScope {
            val ownDeferred = async { fetchOwnPosts(20) }
            val recentDeferred = async { fetchRecentFeedPosts(cap, preferSparkShares = true) }
            val focusDeferred = async { fetchFocusMarketPosts(cap / 2) }
            val own = ownDeferred.await()
            val recent = recentDeferred.await()
            val focus = focusDeferred.await()
            var combined = (own + recent + focus).excludingSparks()
            combined = liveFeedFilter(combined)
            var merged = chronologicalNewestFirst(combined)
            if (merged.isEmpty()) {
                merged = fallbackFeedPosts(cap).excludingSparks()
            }
            balanceFocusMarkets(rankFeedForSparkDensity(merged), cap)
        }
    }

    suspend fun loadHomeFeed(maxPosts: Int = 60, globalLimit: Int = 80): List<CountryPost> {
        val live = fetchNetworkHomePosts(max(globalLimit, maxPosts))
        return chronologicalNewestFirst(live).take(maxPosts)
    }

    data class HomeFeedPage(
        val items: List<CountryPost>,
        val nextCursor: String?,
    )

    suspend fun loadHomeFeedPage(limit: Int = 20, cursor: String? = null): HomeFeedPage {
        val network = fetchRecentPosts(maxOf(limit, 20), before = cursor)
        val items = chronologicalNewestFirst(network).excludingSparks().take(limit)
        val next = items.lastOrNull()?.createdAt
        return HomeFeedPage(items, next)
    }

    // ── Reels / Sparks ─────────────────────────────────────────────────

    suspend fun loadReelsFeed(limit: Int = 24, cursor: String? = null): List<CountryPost> {
        return loadReelsFeedPage(limit = limit, cursor = cursor).items
    }

    data class ReelsFeedPage(
        val items: List<CountryPost>,
        val nextCursor: String?,
        val hasMore: Boolean,
    )

    suspend fun loadReelsFeedPage(
        limit: Int = 24,
        cursor: String? = null,
        fetchLimit: Int = 40,
    ): ReelsFeedPage {
        val recent = fetchRecentPosts(minOf(maxOf(fetchLimit, 24), 60), before = cursor)
        var candidates = recent.filter { it.isSpark || it.isSparkFeedShare || (it.hasVideo && it.isReel) }
        if (cursor == null) {
            val own = fetchOwnPosts(12).filter { it.isSpark || it.hasVideo }
            candidates = own + candidates
        }
        val seen = LinkedHashSet<String>()
        candidates = candidates.filter { seen.add(it.id) }
        val batch = candidates.take(limit)
        val nextCursor = recent.lastOrNull()?.createdAt
        val hasMore = recent.size >= maxOf(8, fetchLimit / 4) || batch.isNotEmpty()
        return ReelsFeedPage(batch, nextCursor, hasMore)
    }

    suspend fun loadReelsNewerBatch(createdAfter: String, limit: Int = 12): List<CountryPost> {
        val recent = fetchRecentPosts(60)
        val newer = recent.filter { it.createdAt > createdAfter }
        val pool = loadReelsPool(followingLimitPerAuthor = 8, globalLimit = 40)
        val seen = LinkedHashSet<String>()
        return (newer + pool).filter { seen.add(it.id) }.take(limit)
    }

    suspend fun loadReelsPool(followingLimitPerAuthor: Int = 10, globalLimit: Int = 40): List<CountryPost> {
        val followingIds = follow.followingIds()
        val currentUserId = currentAuthorId()
        val videos = mutableListOf<CountryPost>()
        val seen = mutableSetOf<String>()

        fun appendVideos(batch: List<CountryPost>) {
            for (post in batch) {
                if (!post.hasVideo && !post.isSpark) continue
                if (!seen.add(post.id)) continue
                videos.add(post)
            }
        }

        if (currentUserId != null) {
            appendVideos(runCatching { listForAuthor(currentUserId, 20) }.getOrDefault(emptyList()))
        }
        coroutineScope {
            followingIds.take(12).map { id ->
                async {
                    runCatching { listForAuthor(id, followingLimitPerAuthor) }.getOrDefault(emptyList())
                }
            }.awaitAll().forEach { appendVideos(it) }
        }
        appendVideos(fetchRecentPosts(globalLimit).filter { it.hasVideo || it.isSpark })
        return videos
    }

    fun sparksCatalogSnapshot(): List<CountryPost> = sparksSessionCatalog

    fun invalidateSparksDiscoveryCatalog() {
        sparksSessionCatalog = emptyList()
        sparksCatalogWarmAt = 0L
    }

    val sparksCatalogIsWarm: Boolean
        get() = sparksSessionCatalog.size >= 40 &&
            System.currentTimeMillis() - sparksCatalogWarmAt < 3 * 60_000

    suspend fun loadSparksDiscoveryCatalog(
        forceRefresh: Boolean = false,
        deep: Boolean = false,
    ): List<CountryPost> {
        val minWarm = if (deep) 120 else 40
        val cacheTtl = if (deep) 8 * 60_000L else 3 * 60_000L
        if (!forceRefresh &&
            sparksSessionCatalog.size >= minWarm &&
            System.currentTimeMillis() - sparksCatalogWarmAt < cacheTtl
        ) {
            return sparksSessionCatalog
        }

        val recent = fetchRecentPosts(100)
        val sparks = recent.filter { it.isSpark || it.isSparkFeedShare || it.isReel }
        val following = loadFollowingFeed(4, 16).filter { it.isSpark || it.hasVideo }
        val merged = LinkedHashMap<String, CountryPost>()
        for (p in sparks + following) merged[p.id] = p
        sparksSessionCatalog = merged.values.shuffled()
        sparksCatalogWarmAt = System.currentTimeMillis()
        return sparksSessionCatalog
    }

    /**
     * iOS `fetchDiscoverSparks` — light random sample for queue fuel.
     * Uses recent posts filtered to spark-eligible when GraphQL discover isn't available.
     */
    suspend fun fetchDiscoverSparks(
        limit: Int = 40,
        excluding: Set<String> = emptySet(),
    ): List<CountryPost> {
        val recent = fetchRecentPosts(maxOf(limit * 3, 80))
        val ranked = SparkDiscoveryEngine.rankForDiscovery(
            recent.filter {
                it.id !in excluding &&
                    ReelsRankingEngine.isSparkEligible(it) &&
                    (it.playableVideoUrl != null || it.hasVideo)
            },
            excluding = excluding,
            limit = limit,
        )
        return ranked
    }

    suspend fun beginFreshSparksSession(preferStart: CountryPost? = null): List<CountryPost> {
        // iOS: beginNewBrowseSession so unviewed ranking resets for this open.
        SparkDiscoveryEngine.beginNewBrowseSession()
        var catalog = loadSparksDiscoveryCatalog(forceRefresh = true, deep = true).toMutableList()
        val discover = fetchDiscoverSparks(limit = 80, excluding = catalog.map { it.id }.toSet())
        val seen = LinkedHashSet<String>()
        val merged = mutableListOf<CountryPost>()
        val anchor = preferStart?.let { ReelsRankingEngine.resolvePlayerStart(it) }
        if (anchor != null) {
            merged.add(anchor)
            seen.add(anchor.id)
        }
        for (p in SparkDiscoveryEngine.rankForDiscovery(catalog + discover)) {
            if (seen.add(p.id)) merged.add(p)
            if (merged.size >= 120) break
        }
        sparksSessionCatalog = merged
        sparksCatalogWarmAt = System.currentTimeMillis()
        return merged
    }

    // ── Hubs / living videos ───────────────────────────────────────────

    fun rememberHubsSessionCatalog(posts: List<CountryPost>) {
        hubsSessionCatalog = posts
    }

    fun hubsSessionIsWarm(minLongForm: Int = 8): Boolean =
        hubsSessionCatalog.count { !it.isReel && it.hasVideo } >= minLongForm

    suspend fun loadLivingVideos(globalLimit: Int = 40, forceRefresh: Boolean = false): List<CountryPost> {
        if (!forceRefresh && hubsSessionIsWarm()) {
            return hubsSessionCatalog.filter { !it.isReel && it.hasVideo }
        }
        val recent = fetchRecentPosts(maxOf(globalLimit, 60))
            .filter { it.hasVideo && !it.isSpark && !it.isStory }
        val own = fetchOwnPosts(maxOf(globalLimit, 40))
            .filter { it.hasVideo && !it.isSpark }
        val merged = chronologicalNewestFirst(own + recent)
        hubsSessionCatalog = merged
        return merged.filter { !it.isReel }
    }

    suspend fun loadPlayCatalog(forceRefresh: Boolean = false): List<CountryPost> {
        val longForm = loadLivingVideos(forceRefresh = forceRefresh)
        val sparks = loadSparksDiscoveryCatalog(forceRefresh = forceRefresh)
        val seen = LinkedHashSet<String>()
        val out = mutableListOf<CountryPost>()
        for (p in longForm + sparks) {
            if (seen.add(p.id)) out.add(p)
        }
        return out
    }

    // ── Comments ───────────────────────────────────────────────────────

    /**
     * List comments with origin-thread merge for spark shares
     * (mirrors iOS listComments).
     */
    suspend fun listComments(
        postId: String,
        limit: Int = 2000,
        body: String? = null,
        sharedPostId: String? = null,
        originPostId: String? = null,
    ): List<PostComment> {
        var comments = fetchCommentsByPost(postId, limit)

        var originId = originPostId
            ?: SparkShareMarker.originId(body)
            ?: sharedPostId

        if (originId == null || originId == postId) {
            try {
                val post = getPostById(postId)
                originId = SparkShareMarker.originId(post?.body)
                    ?: post?.sharedPostId
                    ?: post?.sharedPost?.id
            } catch (_: Exception) {
            }
        }

        if (originId != null && originId != postId) {
            try {
                val origin = fetchCommentsByPost(originId, limit)
                if (origin.size > comments.size || (origin.isNotEmpty() && comments.isEmpty())) {
                    val seen = origin.map { it.id }.toMutableSet()
                    val merged = origin.toMutableList()
                    for (c in comments) {
                        if (seen.add(c.id)) merged.add(c)
                    }
                    comments = merged.take(limit)
                }
            } catch (_: Exception) {
            }
        }
        return comments
    }

    private suspend fun fetchCommentsByPost(postId: String, limit: Int): List<PostComment> {
        val data = gql.request(
            GqlOps.commentsByPost(),
            mapOf(
                "post_id" to JsonPrimitive(postId),
                "limit" to JsonPrimitive(limit),
            ),
        )
        val rows = data["commentsByPost"] as? JsonArray ?: return emptyList()
        return rows.mapNotNull {
            runCatching { json.decodeFromJsonElement<GraphQLComment>(it).toModel }.getOrNull()
        }
    }

    suspend fun addComment(postId: String, body: String, parentId: String? = null): PostComment {
        val vars = buildMap {
            put("post_id", JsonPrimitive(postId))
            put("body", JsonPrimitive(body))
            if (!parentId.isNullOrEmpty()) put("parent_id", JsonPrimitive(parentId))
        }
        val data = gql.request(GqlOps.addComment(), vars)
        val row = data["addComment"] ?: throw GraphQlException("addComment failed")
        return json.decodeFromJsonElement<GraphQLComment>(row).toModel
    }

    suspend fun likeComment(commentId: String): PostComment {
        val data = gql.request(
            GqlOps.likeComment(),
            mapOf("commentId" to JsonPrimitive(commentId)),
        )
        val row = data["likeComment"] ?: throw GraphQlException("likeComment failed")
        return json.decodeFromJsonElement<GraphQLComment>(row).toModel
    }

    suspend fun unlikeComment(commentId: String): PostComment {
        val data = gql.request(
            GqlOps.unlikeComment(),
            mapOf("commentId" to JsonPrimitive(commentId)),
        )
        val row = data["unlikeComment"] ?: throw GraphQlException("unlikeComment failed")
        return json.decodeFromJsonElement<GraphQLComment>(row).toModel
    }

    // ── Create / share ─────────────────────────────────────────────────

    /**
     * Create a Spark (reel). Accepts already-uploaded media URL
     * (upload is handled by MediaService when ported).
     */
    suspend fun createSpark(
        authorId: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = null,
        mediaUrl: String,
        thumbUrl: String? = null,
    ): CountryPost {
        val encoded = PostMediaPayload.encode(
            urls = listOf(mediaUrl),
            types = listOf("video"),
            reel = true,
        ) ?: mediaUrl
        val cleaned = body
            .replace("__spark__|", "")
            .replace("__reel__|", "")
            .trim()
        val bodyOut = "__spark__|${if (cleaned.isEmpty()) "Spark" else cleaned}"
        return createPost(
            authorId = authorId,
            body = bodyOut,
            countryName = countryName,
            countryCode = countryCode,
            cityName = cityName,
            mediaType = "video",
            mediaUrl = encoded,
            thumbUrl = thumbUrl,
        )
    }

    /** Alias matching iOS `createReel` (URL-based until MediaService lands). */
    suspend fun createReel(
        authorId: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = null,
        mediaUrl: String,
        thumbUrl: String? = null,
    ): CountryPost = createSpark(
        authorId, body, countryName, countryCode, cityName, mediaUrl, thumbUrl,
    )

    /** Long-form feed video (not Hubs channel). */
    suspend fun createFeedVideo(
        authorId: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = null,
        title: String? = null,
        mediaUrl: String,
        thumbUrl: String? = null,
    ): CountryPost = createLongFormVideo(
        authorId, body, countryName, countryCode, cityName, title,
        mediaUrl, thumbUrl, publishToHubChannel = false,
    )

    /** Long-form Hubs channel video. */
    suspend fun createHub(
        authorId: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = null,
        title: String? = null,
        mediaUrl: String,
        thumbUrl: String? = null,
    ): CountryPost = createLivingVideo(
        authorId, body, countryName, countryCode, cityName, title, mediaUrl, thumbUrl, true,
    )

    suspend fun createLivingVideo(
        authorId: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = null,
        title: String? = null,
        mediaUrl: String,
        thumbUrl: String? = null,
        publishToHubChannel: Boolean = true,
    ): CountryPost = createLongFormVideo(
        authorId, body, countryName, countryCode, cityName, title,
        mediaUrl, thumbUrl, publishToHubChannel,
    )

    private suspend fun createLongFormVideo(
        authorId: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String?,
        title: String?,
        mediaUrl: String,
        thumbUrl: String?,
        publishToHubChannel: Boolean,
    ): CountryPost {
        val encoded = PostMediaPayload.encode(
            urls = listOf(mediaUrl),
            types = listOf("video"),
            reel = false,
        ) ?: mediaUrl
        val bodyOut = if (publishToHubChannel) HubChannelPostMarker.markBody(body) else body
        return createPost(
            authorId = authorId,
            body = bodyOut,
            countryName = countryName,
            countryCode = countryCode,
            cityName = cityName,
            title = title,
            mediaType = "video",
            mediaUrl = encoded,
            thumbUrl = thumbUrl,
        )
    }

    suspend fun createStory(
        authorId: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = null,
        mediaUrl: String,
    ): CountryPost {
        val expiresAt = Instant.now().plusSeconds(86_400)
        val storyBody = PostStoryMarker.buildBody(caption = body, expiresAt = expiresAt)
        return createPost(
            authorId = authorId,
            body = storyBody,
            countryName = countryName,
            countryCode = countryCode,
            cityName = cityName,
            visibility = PostVisibility.COUNTRY,
            mediaType = "story",
            mediaUrl = mediaUrl,
        )
    }

    suspend fun createPost(
        authorId: String,
        body: String,
        countryName: String,
        countryCode: String,
        cityName: String? = null,
        title: String? = null,
        visibility: PostVisibility = PostVisibility.PUBLIC,
        mediaType: String? = null,
        mediaUrl: String? = null,
        thumbUrl: String? = null,
        sharedPostId: String? = null,
    ): CountryPost {
        val normalizedMediaType = (mediaType ?: "").lowercase()
        val resolvedVisibility =
            if (normalizedMediaType == "story" || body.contains("__story__|")) {
                PostVisibility.COUNTRY
            } else {
                visibility
            }
        val input = buildJsonObject {
            put("body", body)
            put("country_name", countryName)
            put("country_code", countryCode.uppercase())
            put("visibility", resolvedVisibility.rawValue)
            if (title != null) put("title", title)
            if (cityName != null) put("city_name", cityName)
            if (mediaType != null) put("media_type", mediaType)
            if (mediaUrl != null) put("media_url", mediaUrl)
            if (thumbUrl != null) put("thumb_url", thumbUrl)
            if (sharedPostId != null) put("shared_post_id", sharedPostId)
        }
        // authorId is session-derived server-side; kept for API parity with iOS signature.
        @Suppress("UNUSED_VARIABLE")
        val _author = authorId

        val data = gql.request(GqlOps.createPost(), mapOf("input" to input))
        val row = data["createPost"] ?: throw GraphQlException("createPost failed")
        return json.decodeFromJsonElement<GraphQLPost>(row).toModel
    }

    suspend fun sharePostToCountryFeed(
        post: CountryPost,
        countryName: String,
        countryCode: String,
        cityName: String? = null,
        caption: String? = null,
    ): CountryPost {
        if (post.isStory) {
            throw PostsServiceError("Moments cannot be shared as posts.")
        }
        if (post.sharedPost?.asCountryPost?.isStory == true) {
            throw PostsServiceError("Moments cannot be shared as posts.")
        }
        val originalId = post.sharedPostId ?: post.id
        val captionBody = (caption ?: "").trim()
        val isServerPost = runCatching { UUID.fromString(originalId) }.isSuccess
        val isHubCatalog = post.isHubSeedVideo || HubChannelPostMarker.isMarked(post.body)
        val isSpark = post.isReel ||
            post.isSparkFeedShare ||
            SparkShareMarker.isMarked(post.body) ||
            (post.sharedPost?.asCountryPost?.isReel == true)
        val isHubLongFormShare = isHubCatalog && !isSpark
        val shouldStampMedia = !isServerPost || isHubCatalog || isSpark

        val input = if (shouldStampMedia) {
            var mediaURL = post.mediaUrl ?: post.playableVideoUrl
            var thumb = post.thumbUrl
            val bodyValue: String
            val mediaTypeValue = "video"
            var titleValue: String? = null

            when {
                isSpark -> {
                    val originForStamp = post.sharedPost?.asCountryPost?.takeIf {
                        it.isReel || it.playableVideoUrl != null
                    } ?: post
                    bodyValue = SparkShareMarker.markBody(captionBody, originForStamp)
                    mediaURL = originForStamp.mediaUrl ?: originForStamp.playableVideoUrl ?: mediaURL
                    thumb = originForStamp.thumbUrl ?: thumb
                }
                isHubLongFormShare || isHubCatalog -> {
                    val origin = HubOriginShareMarker.originPresentation(post) ?: post
                    bodyValue = HubOriginShareMarker.markBody(captionBody, origin)
                    titleValue = origin.displayHeadline ?: origin.displayTitle
                        ?: post.displayHeadline ?: post.displayTitle
                    mediaURL = origin.mediaUrl ?: origin.playableVideoUrl ?: mediaURL
                    thumb = origin.thumbUrl ?: thumb
                }
                else -> {
                    bodyValue = captionBody
                    titleValue = post.displayHeadline ?: post.displayTitle
                }
            }

            if (mediaURL.isNullOrEmpty()) {
                if (isServerPost) {
                    buildJsonObject {
                        put("country_name", countryName)
                        put("country_code", countryCode.uppercase())
                        put("visibility", "public")
                        if (cityName != null) put("city_name", cityName)
                        put(
                            "body",
                            if (isSpark) SparkShareMarker.markBody(captionBody, post) else captionBody,
                        )
                        put("media_type", "none")
                        put("shared_post_id", originalId)
                    }
                } else {
                    throw PostsServiceError("This video has no playable media to share.")
                }
            } else {
                buildJsonObject {
                    put("country_name", countryName)
                    put("country_code", countryCode.uppercase())
                    put("visibility", "public")
                    if (cityName != null) put("city_name", cityName)
                    put("body", bodyValue)
                    put("media_type", mediaTypeValue)
                    put("media_url", mediaURL)
                    if (!thumb.isNullOrEmpty()) put("thumb_url", thumb)
                    if (!titleValue.isNullOrEmpty()) put("title", titleValue)
                }
            }
        } else {
            buildJsonObject {
                put("country_name", countryName)
                put("country_code", countryCode.uppercase())
                put("visibility", "public")
                if (cityName != null) put("city_name", cityName)
                put("body", captionBody)
                put("media_type", "none")
                put("shared_post_id", originalId)
            }
        }

        try {
            val data = gql.request(GqlOps.createPost(), mapOf("input" to input))
            val row = data["createPost"] ?: throw GraphQlException("createPost failed")
            return json.decodeFromJsonElement<GraphQLPost>(row).toModel
        } catch (e: Exception) {
            // UUID pointer share failed → retry as self-contained stamp.
            val mediaURL = post.mediaUrl ?: post.playableVideoUrl
            if (isServerPost && !shouldStampMedia && !mediaURL.isNullOrEmpty()) {
                val retry = buildJsonObject {
                    put("country_name", countryName)
                    put("country_code", countryCode.uppercase())
                    put("visibility", "public")
                    if (cityName != null) put("city_name", cityName)
                    put("media_type", "video")
                    put("media_url", mediaURL)
                    val thumb = post.thumbUrl
                    if (!thumb.isNullOrEmpty()) put("thumb_url", thumb)
                    when {
                        isSpark -> put("body", SparkShareMarker.markBody(captionBody, post))
                        isHubLongFormShare || isHubCatalog -> {
                            val origin = HubOriginShareMarker.originPresentation(post) ?: post
                            put("body", HubOriginShareMarker.markBody(captionBody, origin))
                            val t = origin.displayHeadline ?: origin.displayTitle ?: post.displayHeadline
                            if (!t.isNullOrEmpty()) put("title", t)
                        }
                        else -> {
                            put("body", captionBody)
                            val t = post.displayHeadline ?: post.displayTitle
                            if (!t.isNullOrEmpty()) put("title", t)
                        }
                    }
                }
                val data = gql.request(GqlOps.createPost(), mapOf("input" to retry))
                val row = data["createPost"] ?: throw GraphQlException("createPost failed")
                return json.decodeFromJsonElement<GraphQLPost>(row).toModel
            }
            throw e
        }
    }

    // ── Like / unlike ──────────────────────────────────────────────────

    suspend fun likePost(postId: String, baseLikeCount: Int = 0) {
        if (shouldEngageLocally(postId)) return
        try {
            gql.request(GqlOps.likePost(), mapOf("postId" to JsonPrimitive(postId)))
        } catch (_: Exception) {
            // local-first policy — never throw
        }
    }

    suspend fun unlikePost(postId: String, baseLikeCount: Int = 0) {
        if (shouldEngageLocally(postId)) return
        try {
            gql.request(GqlOps.unlikePost(), mapOf("postId" to JsonPrimitive(postId)))
        } catch (_: Exception) {
            // local-first
        }
    }

    suspend fun toggleLike(post: CountryPost): CountryPost {
        return if (post.likedByMe) {
            unlikePost(post.id, post.likeCount)
            post.copyEngagement(likedByMe = false, likeCount = (post.likeCount - 1).coerceAtLeast(0))
        } else {
            likePost(post.id, post.likeCount)
            post.copyEngagement(likedByMe = true, likeCount = post.likeCount + 1)
        }
    }

    suspend fun shouldEngageLocally(postId: String): Boolean {
        if (runCatching { UUID.fromString(postId) }.isFailure) return true
        val lower = postId.lowercase()
        return lower.startsWith("hub_") ||
            lower.startsWith("ia_") ||
            lower.startsWith("demo_") ||
            lower.startsWith("post_")
    }

    // ── Bookmarks ──────────────────────────────────────────────────────

    private var usesLocalBookmarksOnly: Boolean = false

    fun isUnsupportedBookmarkError(error: Throwable): Boolean {
        val message = error.message?.lowercase().orEmpty()
        return message.contains("savepost") ||
            message.contains("unsavepost") ||
            message.contains("savedposts") ||
            message.contains("saved_by_me") ||
            message.contains("post_bookmarks") ||
            message.contains("internal server error") ||
            message.contains("internal_server_error") ||
            message.contains("cannot query field") ||
            message.contains("graphql_validation_failed")
    }

    fun isMissingPostBookmarkError(error: Throwable): Boolean {
        val message = error.message?.lowercase().orEmpty()
        return message.contains("not found") ||
            message.contains("does not exist") ||
            message.contains("foreign key") ||
            message.contains("invalid input") ||
            message.contains("invalid uuid") ||
            message.contains("no rows") ||
            message.contains("pgrst") ||
            message.contains("22p02")
    }

    fun mustBookmarkLocally(post: CountryPost): Boolean {
        if (runCatching { UUID.fromString(post.id) }.isFailure) return true
        if (post.isHubSeedVideo || post.isSeededOrSynthetic) return true
        if (post.isArchiveSparkSource) return true
        val id = post.id.lowercase()
        if (id.startsWith("ia_") || id.startsWith("hub_") ||
            id.startsWith("demo_") || id.startsWith("post_")
        ) {
            return true
        }
        val author = post.authorId.lowercase()
        if (author.startsWith("hub_") || author.startsWith("hub_spark_") || author.startsWith("user_")) {
            return true
        }
        return false
    }

    suspend fun savedPosts(limit: Int = 80): List<CountryPost> {
        val data = gql.request(
            GqlOps.savedPosts(),
            mapOf("limit" to JsonPrimitive(limit)),
        )
        usesLocalBookmarksOnly = false
        return mapPosts(data["savedPosts"])
    }

    suspend fun savePost(postId: String): CountryPost {
        val data = gql.request(
            GqlOps.savePost(),
            mapOf("postId" to JsonPrimitive(postId)),
        )
        usesLocalBookmarksOnly = false
        val row = data["savePost"] ?: throw GraphQlException("savePost failed")
        return json.decodeFromJsonElement<GraphQLPost>(row).toModel
    }

    suspend fun unsavePost(postId: String): CountryPost {
        val data = gql.request(
            GqlOps.unsavePost(),
            mapOf("postId" to JsonPrimitive(postId)),
        )
        usesLocalBookmarksOnly = false
        val row = data["unsavePost"] ?: throw GraphQlException("unsavePost failed")
        return json.decodeFromJsonElement<GraphQLPost>(row).toModel
    }

    suspend fun toggleBookmark(post: CountryPost, saved: Boolean): CountryPost {
        if (usesLocalBookmarksOnly || mustBookmarkLocally(post)) {
            return post.withSavedByMe(saved)
        }
        if (shouldEngageLocally(post.id)) {
            return post.withSavedByMe(saved)
        }
        return try {
            if (saved) savePost(post.id) else unsavePost(post.id)
        } catch (e: Exception) {
            if (isUnsupportedBookmarkError(e)) {
                usesLocalBookmarksOnly = true
                return post.withSavedByMe(saved)
            }
            if (isMissingPostBookmarkError(e) || mustBookmarkLocally(post)) {
                return post.withSavedByMe(saved)
            }
            throw e
        }
    }

    suspend fun loadBookmarkedPosts(localIds: Set<String>, limit: Int = 100): List<CountryPost> {
        var server: List<CountryPost> = emptyList()
        if (!usesLocalBookmarksOnly) {
            try {
                server = savedPosts(limit)
            } catch (e: Exception) {
                if (isUnsupportedBookmarkError(e)) usesLocalBookmarksOnly = true
            }
        }
        val serverIds = server.map { it.id }.toSet()
        val missing = if (localIds.isEmpty() && server.isEmpty()) {
            emptySet()
        } else {
            localIds - serverIds
        }
        val byId = LinkedHashMap<String, CountryPost>()
        for (post in server) byId[post.id] = post.withSavedByMe(true)
        for (id in missing.take(limit)) {
            val post = runCatching { getPostById(id) }.getOrNull() ?: continue
            byId[id] = post.withSavedByMe(true)
        }
        return byId.values.sortedByDescending { it.createdAt }
    }

    // ── Update / delete / report ───────────────────────────────────────

    suspend fun updatePost(
        postId: String,
        title: String? = null,
        body: String? = null,
        visibility: PostVisibility? = null,
        mediaType: String? = null,
        mediaUrl: String? = null,
        thumbUrl: String? = null,
        clearMedia: Boolean = false,
    ): CountryPost {
        val input = buildJsonObject {
            if (title != null) put("title", title)
            if (body != null) put("body", body)
            if (visibility != null) put("visibility", visibility.rawValue)
            if (clearMedia) {
                put("clear_media", true)
            } else if (mediaUrl != null) {
                put("media_url", mediaUrl)
                if (mediaType != null) put("media_type", mediaType)
                if (thumbUrl != null) put("thumb_url", thumbUrl)
            }
        }
        val data = gql.request(
            GqlOps.updatePost(),
            mapOf(
                "postId" to JsonPrimitive(postId),
                "input" to input,
            ),
        )
        val row = data["updatePost"] ?: throw GraphQlException("updatePost failed")
        return json.decodeFromJsonElement<GraphQLPost>(row).toModel
    }

    suspend fun deletePost(postId: String): Boolean {
        val data = gql.request(
            GqlOps.deletePost(),
            mapOf("postId" to JsonPrimitive(postId)),
        )
        return data["deletePost"]?.jsonPrimitive?.booleanOrNull == true
    }

    suspend fun reportPost(postId: String, reason: String): Boolean {
        val data = gql.request(
            GqlOps.reportPost(),
            mapOf(
                "postId" to JsonPrimitive(postId),
                "reason" to JsonPrimitive(reason),
            ),
        )
        return data["reportPost"]?.jsonPrimitive?.booleanOrNull == true
    }

    // ── Stories ────────────────────────────────────────────────────────

    suspend fun loadActiveStoryGroups(
        countryCode: String?,
        followingIds: Set<String>,
        viewedStoryIds: Set<String>,
        currentUserId: String?,
    ): List<StoryGroup> {
        val pool = mutableListOf<CountryPost>()
        val seen = mutableSetOf<String>()

        fun append(batch: List<CountryPost>) {
            for (post in batch) {
                if (post.isStory && post.isStoryActive && seen.add(post.id)) {
                    pool.add(post)
                }
            }
        }

        if (!countryCode.isNullOrBlank()) {
            append(runCatching { listByCountry(countryCode, 80) }.getOrDefault(emptyList()))
        }
        if (followingIds.isNotEmpty()) {
            coroutineScope {
                followingIds.map { id ->
                    async { runCatching { listForAuthor(id, 20) }.getOrDefault(emptyList()) }
                }.awaitAll().forEach { append(it) }
            }
        }
        if (!currentUserId.isNullOrBlank()) {
            append(runCatching { listForAuthor(currentUserId, 20) }.getOrDefault(emptyList()))
        }

        return pool.groupBy { it.authorId }.map { (authorId, stories) ->
            val sorted = stories.sortedByDescending { it.createdAt }
            StoryGroup(
                authorId = authorId,
                author = sorted.firstOrNull()?.author,
                stories = sorted,
                hasUnviewed = sorted.any { it.id !in viewedStoryIds },
            )
        }.sortedWith(
            compareByDescending<StoryGroup> { it.authorId == currentUserId }
                .thenByDescending { it.hasUnviewed }
                .thenBy { it.displayName.lowercase() },
        )
    }

    // ── Misc ───────────────────────────────────────────────────────────

    suspend fun videoPosts(countryCode: String, limit: Int = 40): List<CountryPost> =
        listByCountry(countryCode, limit).filter { it.hasVideo }

    fun recordView(post: CountryPost) {
        if (post.id.isEmpty() || !viewedPostIds.add(post.id)) return
    }

    fun setHomeCountryCode(code: String?) {
        profileCountryCode.set(code?.uppercase())
    }

    // ── Internals ──────────────────────────────────────────────────────

    private suspend fun fetchRealPostsByCountry(code: String, limit: Int): List<CountryPost> {
        val data = gql.request(
            GqlOps.postsByCountry(),
            mapOf(
                "code" to JsonPrimitive(code),
                "limit" to JsonPrimitive(limit),
            ),
        )
        return mapPosts(data["postsByCountry"])
    }

    private suspend fun fetchRecentFeedPosts(limit: Int, preferSparkShares: Boolean): List<CountryPost> {
        val collected = mutableListOf<CountryPost>()
        val seen = mutableSetOf<String>()
        var before: String? = null
        val stopAt = maxOf(limit, 80)
        repeat(2) {
            val batch = fetchRecentPosts(minOf(60, stopAt), before = before)
            if (batch.isEmpty()) return@repeat
            for (p in batch) {
                if (seen.add(p.id)) collected.add(p)
            }
            before = batch.lastOrNull()?.createdAt
            if (collected.size >= stopAt) return@repeat
        }
        var merged = chronologicalNewestFirst(collected)
        if (preferSparkShares) {
            // Keep spark shares + non-spark; drop pure spark originals from home feed.
            merged = merged.excludingSparks()
        }
        return merged
    }

    private suspend fun fetchFocusMarketPosts(limit: Int): List<CountryPost> {
        val per = maxOf(10, minOf(20, limit / maxOf(FOCUS_MARKET_CODES.size, 1)))
        return coroutineScope {
            FOCUS_MARKET_CODES.map { code ->
                async {
                    runCatching { listByCountry(code, per) }.getOrDefault(emptyList()).excludingSparks()
                }
            }.awaitAll().flatten()
        }
    }

    private fun rankFeedForSparkDensity(posts: List<CountryPost>): List<CountryPost> {
        if (posts.size <= 12) return posts
        val out = mutableListOf<CountryPost>()
        val window = 12
        var i = 0
        while (i < posts.size) {
            val end = minOf(posts.size, i + window)
            val slice = posts.subList(i, end).sortedWith(
                compareByDescending<CountryPost> {
                    it.isSparkFeedShare || it.isHubOriginFeedShare || (it.hasVideo && !it.isSpark)
                },
            )
            out.addAll(slice)
            i = end
        }
        return out
    }

    private fun balanceFocusMarkets(posts: List<CountryPost>, limit: Int): List<CountryPost> {
        if (posts.isEmpty()) return posts
        val buckets = FOCUS_MARKET_CODES.associateWith { mutableListOf<CountryPost>() }.toMutableMap()
        val other = mutableListOf<CountryPost>()
        for (post in posts) {
            val code = post.countryCode?.uppercase().orEmpty()
            if (code in buckets) buckets.getValue(code).add(post) else other.add(post)
        }
        val out = mutableListOf<CountryPost>()
        val indices = FOCUS_MARKET_CODES.associateWith { 0 }.toMutableMap()
        while (out.size < limit) {
            var added = false
            for (code in FOCUS_MARKET_CODES) {
                val list = buckets[code].orEmpty()
                val i = indices[code] ?: 0
                if (i < list.size) {
                    out.add(list[i])
                    indices[code] = i + 1
                    added = true
                    if (out.size >= limit) break
                }
            }
            if (!added) break
        }
        if (out.size < limit) {
            val seen = out.map { it.id }.toMutableSet()
            for (p in other) {
                if (seen.add(p.id)) out.add(p)
                if (out.size >= limit) break
            }
        }
        return out.take(limit)
    }

    private suspend fun fetchOwnPosts(limit: Int): List<CountryPost> {
        val userId = currentAuthorId() ?: return profilePostsCache
        for (attempt in 0 until 2) {
            try {
                val posts = listForAuthor(userId, limit).excludingSparks()
                profilePostsCache = posts
                return posts
            } catch (_: Exception) {
                if (attempt == 0) {
                    runCatching { auth.ensureValidToken() }
                    continue
                }
            }
        }
        return profilePostsCache
    }

    private suspend fun fallbackFeedPosts(limit: Int): List<CountryPost> {
        val batches = mutableListOf<List<CountryPost>>()
        val own = fetchOwnPosts(limit)
        if (own.isNotEmpty()) batches.add(own)
        val home = fetchHomeCountryPosts(limit)
        if (home.isNotEmpty()) batches.add(home)
        if (batches.isEmpty() && profilePostsCache.isNotEmpty()) batches.add(profilePostsCache)
        if (batches.isEmpty()) return emptyList()
        return mergeFeedSources(batches, limit)
    }

    private suspend fun fallbackGlobalPosts(limit: Int): List<CountryPost> =
        fallbackFeedPosts(limit)

    private suspend fun fetchHomeCountryPosts(limit: Int): List<CountryPost> {
        val code = profileCountryCode.get() ?: return emptyList()
        return runCatching { listByCountry(code, limit) }.getOrDefault(emptyList())
    }

    private fun currentAuthorId(): String? =
        auth.currentUser?.id?.takeIf { it.isNotEmpty() }

    fun mergeFeedSources(batches: List<List<CountryPost>>, limit: Int): List<CountryPost> {
        val seen = mutableSetOf<String>()
        val merged = mutableListOf<CountryPost>()
        val sorted = batches.map { chronologicalNewestFirst(it) }
        val indices = IntArray(sorted.size)
        while (merged.size < limit) {
            var appended = false
            for (bi in sorted.indices) {
                val batch = sorted[bi]
                while (indices[bi] < batch.size) {
                    val post = batch[indices[bi]]
                    indices[bi]++
                    if (post.id in seen || post.isStory) continue
                    seen.add(post.id)
                    merged.add(post)
                    appended = true
                    break
                }
                if (merged.size >= limit) break
            }
            if (!appended) break
        }
        return merged
    }

    fun mergePosts(real: List<CountryPost>, demo: List<CountryPost>, limit: Int): List<CountryPost> =
        mergeFeedSources(listOf(real, demo), limit)

    fun chronologicalNewestFirst(posts: List<CountryPost>): List<CountryPost> =
        // Dedupe after sort — LazyColumn keys crash on duplicate post ids when
        // bootstrap merges live + cache without uniqueness (see dropbox 00:10:36).
        posts.sortedByDescending { it.createdAt }.distinctBy { it.id }

    fun sessionFreshOrder(posts: List<CountryPost>, preferIds: Set<String> = emptySet()): List<CountryPost> {
        if (preferIds.isEmpty()) return chronologicalNewestFirst(posts)
        val preferred = posts.filter { it.id in preferIds }
        val rest = posts.filter { it.id !in preferIds }
        return chronologicalNewestFirst(preferred) + chronologicalNewestFirst(rest)
    }

    private fun mapPosts(element: kotlinx.serialization.json.JsonElement?): List<CountryPost> {
        val rows = element as? JsonArray ?: return emptyList()
        return rows.mapNotNull {
            runCatching { json.decodeFromJsonElement<GraphQLPost>(it).toModel }.getOrNull()
        }
    }

    private fun liveFeedFilter(posts: List<CountryPost>): List<CountryPost> {
        return posts.filter { post ->
            if (post.isStory) return@filter false
            if (post.isSpark && !post.isSparkFeedShare) return@filter false
            if (post.authorId.startsWith("user_") || post.id.startsWith("post_")) return@filter false
            if (post.id.startsWith("demo_")) return@filter false
            true
        }
    }

    private fun max(a: Int, b: Int) = if (a > b) a else b

    private class AtomicReferenceLike<T>(initial: T) {
        @Volatile private var value: T = initial
        fun get(): T = value
        fun set(v: T) {
            value = v
        }
    }

    companion object {
        private val FOCUS_MARKET_CODES = listOf("US", "GB", "CA", "AU", "DE", "FR", "JP", "BR", "IN", "NG")
    }
}

class PostsServiceError(message: String) : Exception(message)
