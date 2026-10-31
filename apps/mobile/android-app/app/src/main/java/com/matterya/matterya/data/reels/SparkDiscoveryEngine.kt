package com.matterya.matterya.data.reels

import android.content.Context
import com.matterya.matterya.model.CountryPost
import java.util.concurrent.ConcurrentHashMap

/**
 * Pre-launch stand-in for the official recommender — **1:1 iOS**
 * `PostsService.SparkDiscoveryEngine`.
 *
 * **Hard rule:** always prefer posts/Sparks the user has **not** already viewed.
 * Never interleave already-watched clips ahead of fresh ones.
 */
object SparkDiscoveryEngine {
    private const val DEFAULTS_KEY = "spark.discovery.impressions.v2"
    /** Keep enough history for a large R2 library (was 2.5k → recycled too early). */
    private const val MAX_PERSISTED = 20_000
    /** Viewed = suppressed for this long before eligible as last-resort recycle. */
    private const val IMPRESSION_TTL_DAYS = 90.0

    private val impressions = ConcurrentHashMap<String, Double>()
    private val sessionServed = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var appContext: Context? = null
    private val lock = Any()

    fun bind(context: Context) {
        appContext = context.applicationContext
        load()
    }

    fun markImpressed(postId: String) {
        if (postId.isEmpty()) return
        synchronized(lock) {
            sessionServed.add(postId)
            impressions[postId] = System.currentTimeMillis() / 1000.0
        }
        trimAndSave()
    }

    fun markImpressed(posts: List<CountryPost>) {
        val now = System.currentTimeMillis() / 1000.0
        synchronized(lock) {
            for (p in posts) {
                sessionServed.add(p.id)
                impressions[p.id] = now
            }
        }
        trimAndSave()
    }

    fun markWatched(postId: String) {
        markImpressed(postId)
        ReelsRankingEngine.markWatched(postId)
    }

    /** True if this user already viewed the post this session or within the TTL window. */
    fun isViewed(postId: String): Boolean {
        if (postId.isEmpty()) return false
        val now = System.currentTimeMillis() / 1000.0
        val ttl = IMPRESSION_TTL_DAYS * 24 * 3600
        synchronized(lock) {
            if (postId in sessionServed) return true
            val t = impressions[postId] ?: return false
            return now - t < ttl
        }
    }

    /** IDs to exclude from API discoverSparks / paging (newest watches first). */
    fun viewedIDList(limit: Int = 800): List<String> {
        val now = System.currentTimeMillis() / 1000.0
        val ttl = IMPRESSION_TTL_DAYS * 24 * 3600
        val pairs = mutableListOf<Pair<String, Double>>()
        synchronized(lock) {
            for (id in sessionServed) pairs.add(id to now)
            for ((id, t) in impressions) {
                if (now - t < ttl) pairs.add(id to t)
            }
        }
        val seen = mutableSetOf<String>()
        val out = mutableListOf<String>()
        for ((id, _) in pairs.sortedByDescending { it.second }) {
            if (!seen.add(id)) continue
            out.add(id)
            if (out.size >= limit) break
        }
        return out
    }

    /**
     * Keep durable impressions — only clear ranking session state if needed.
     * Do NOT wipe sessionServed mid-browse or the same Sparks reappear immediately.
     */
    fun resetSession() {
        ReelsRankingEngine.resetSession()
    }

    /** Call when the user explicitly starts a *new* Sparks session. */
    fun beginNewBrowseSession() {
        synchronized(lock) { sessionServed.clear() }
        ReelsRankingEngine.resetSession()
    }

    fun clearAllHistory() {
        synchronized(lock) {
            sessionServed.clear()
            impressions.clear()
        }
        appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            ?.edit()
            ?.remove(DEFAULTS_KEY)
            ?.remove("spark.discovery.impressions.v1")
            ?.apply()
        ReelsRankingEngine.resetSession()
    }

    /**
     * **Unviewed only** while any remain; otherwise least-recently-viewed recycle.
     * Never interleave already-watched clips ahead of fresh ones.
     */
    fun rankForDiscovery(
        candidates: List<CountryPost>,
        excluding: Set<String> = emptySet(),
        limit: Int? = null,
    ): List<CountryPost> {
        val seen = mutableSetOf<String>()
        val pool = candidates.filter { post ->
            seen.add(post.id) && post.id !in excluding
        }
        if (pool.isEmpty()) return emptyList()

        val now = System.currentTimeMillis() / 1000.0
        val ttl = IMPRESSION_TTL_DAYS * 24 * 3600
        val sessionSnap: Set<String>
        val impSnap: Map<String, Double>
        synchronized(lock) {
            sessionSnap = sessionServed.toSet()
            impSnap = impressions.toMap()
        }

        val unviewed = mutableListOf<CountryPost>()
        val viewed = mutableListOf<Pair<CountryPost, Double>>()

        for (post in pool) {
            if (post.id in sessionSnap) {
                viewed.add(post to now)
                continue
            }
            val t = impSnap[post.id]
            if (t != null && now - t < ttl) {
                viewed.add(post to t)
            } else {
                unviewed.add(post)
            }
        }

        fun diversityShuffle(items: List<CountryPost>): List<CountryPost> {
            if (items.size <= 2) return items.shuffled()
            val r2 = items.filter { it.isR2HostedMedia }.shuffled()
            val rest = items.filter { !it.isR2HostedMedia }.shuffled()
            return spacedPick(r2 + rest, items.size)
        }

        // HARD RULE: if anything unviewed exists, only suggest those.
        var out = if (unviewed.isNotEmpty()) {
            diversityShuffle(unviewed)
        } else {
            // Last resort: oldest view first (longest since last watch).
            diversityShuffle(viewed.sortedBy { it.second }.map { it.first })
        }
        out = spacedPick(out, out.size)
        return if (limit != null && limit > 0) out.take(limit) else out
    }

    /**
     * Home feed open / reload order — iOS `sessionHomeFeedOrder`.
     * Hard rule: viewed posts only after all unviewed exhausted.
     * Priority while unviewed remain:
     * 1) Your unviewed posts
     * 2) Unviewed posts from people you follow (newest first)
     * 3) Other unviewed (session-seeded shuffle)
     */
    fun sessionHomeFeedOrder(
        posts: List<CountryPost>,
        followingIds: Set<String>,
        myUserId: String?,
        sessionSeed: Long = 0L,
    ): List<CountryPost> {
        val seen = mutableSetOf<String>()
        val unique = posts.filter { seen.add(it.id) && !it.isStory }
        if (unique.isEmpty()) return emptyList()

        val me = myUserId?.trim().orEmpty()
        fun isMine(p: CountryPost) = me.isNotEmpty() && p.authorId == me
        fun isFollow(p: CountryPost) = p.authorId in followingIds

        val mineUnviewed = mutableListOf<CountryPost>()
        val followUnviewed = mutableListOf<CountryPost>()
        val otherUnviewed = mutableListOf<CountryPost>()
        val viewedPool = mutableListOf<Pair<CountryPost, Double>>()

        val now = System.currentTimeMillis() / 1000.0
        val impSnap: Map<String, Double>
        synchronized(lock) { impSnap = impressions.toMap() }

        for (p in unique) {
            if (isViewed(p.id)) {
                viewedPool.add(p to (impSnap[p.id] ?: now))
                continue
            }
            when {
                isMine(p) -> mineUnviewed.add(p)
                isFollow(p) -> followUnviewed.add(p)
                else -> otherUnviewed.add(p)
            }
        }

        fun newestFirst(items: List<CountryPost>) =
            items.sortedByDescending { it.createdAt }

        // Following unviewed = hard priority, newest first.
        val followFresh = newestFirst(followUnviewed)
        val mineFresh = newestFirst(mineUnviewed)
        // Other unviewed: seeded shuffle when seed provided.
        val others = if (sessionSeed != 0L) {
            otherUnviewed.shuffled(java.util.Random(sessionSeed))
        } else {
            otherUnviewed.shuffled()
        }

        val unviewedOut = mineFresh + followFresh + others
        if (unviewedOut.isNotEmpty()) return spacedPick(unviewedOut, unviewedOut.size)

        // Exhausted unviewed → least-recently-viewed recycle.
        val recycled = viewedPool.sortedBy { it.second }.map { it.first }
        return spacedPick(recycled, recycled.size)
    }

    fun preferUnviewedFeedOrder(posts: List<CountryPost>): List<CountryPost> =
        sessionHomeFeedOrder(posts, emptySet(), null, 0)

    fun nextBatch(
        from: List<CountryPost>,
        excluding: Set<String>,
        limit: Int,
        tail: List<CountryPost> = emptyList(),
        allowRecycle: Boolean = false,
    ): List<CountryPost> {
        if (limit <= 0) return emptyList()
        var pool = from.filter {
            it.id !in excluding && ReelsRankingEngine.isSparkEligible(it) && !isViewed(it.id)
        }
        if (pool.isEmpty() && allowRecycle) {
            pool = from.filter {
                it.id !in excluding && ReelsRankingEngine.isSparkEligible(it)
            }
        }
        if (pool.isEmpty()) return emptyList()

        val ranked = rankForDiscovery(pool, excluding)
        val picked = mutableListOf<CountryPost>()
        val context = tail.toMutableList()
        val remaining = ranked.toMutableList()

        while (picked.size < limit && remaining.isNotEmpty()) {
            val recentAuthors = context.takeLast(3).map { it.authorId }.toSet()
            val recentCountries = context.takeLast(2).mapNotNull { it.countryCode?.uppercase() }.toSet()
            val idx = remaining.indexOfFirst { post ->
                post.authorId !in recentAuthors &&
                    post.countryCode?.uppercase()?.let { it !in recentCountries } != false
            }.takeIf { it >= 0 } ?: 0
            val post = remaining.removeAt(idx)
            picked.add(post)
            context.add(post)
        }
        return picked
    }

    private fun spacedPick(items: List<CountryPost>, limit: Int): List<CountryPost> {
        if (items.isEmpty()) return emptyList()
        val out = mutableListOf<CountryPost>()
        val remaining = items.toMutableList()
        val recentAuthors = ArrayDeque<String>()
        while (out.size < limit && remaining.isNotEmpty()) {
            val idx = remaining.indexOfFirst { it.authorId !in recentAuthors }.takeIf { it >= 0 } ?: 0
            val post = remaining.removeAt(idx)
            out.add(post)
            recentAuthors.addLast(post.authorId)
            if (recentAuthors.size > 3) recentAuthors.removeFirst()
        }
        return out
    }

    private fun load() {
        val ctx = appContext ?: return
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // Migrate v1 if present
        val raw = prefs.getString(DEFAULTS_KEY, null)
            ?: prefs.getString("spark.discovery.impressions.v1", null)
            ?: return
        val now = System.currentTimeMillis() / 1000.0
        val ttl = IMPRESSION_TTL_DAYS * 24 * 3600
        for (part in raw.split(",")) {
            val eq = part.indexOf('=')
            if (eq <= 0) continue
            val id = part.substring(0, eq)
            val t = part.substring(eq + 1).toDoubleOrNull() ?: continue
            if (now - t < ttl) impressions[id] = t
        }
    }

    private fun trimAndSave() {
        synchronized(lock) {
            if (impressions.size > MAX_PERSISTED) {
                val keep = impressions.entries
                    .sortedByDescending { it.value }
                    .take(MAX_PERSISTED)
                impressions.clear()
                for (e in keep) impressions[e.key] = e.value
            }
            val snap = impressions.entries.joinToString(",") { "${it.key}=${it.value}" }
            appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                ?.edit()
                ?.putString(DEFAULTS_KEY, snap)
                ?.apply()
        }
    }

    private const val PREFS = "matterya_spark_discovery"
}
