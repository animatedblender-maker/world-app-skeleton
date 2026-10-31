package com.matterya.matterya.data.cache

import android.content.Context
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.Profile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.Date
import java.util.concurrent.ConcurrentHashMap

enum class ContentCacheKey(val raw: String) {
    HomeFeed("homeFeed.v6_backend_only_no_reddit"),
    LivingVideos("livingVideos"),
    SavedPosts("savedPosts"),
    ProfilePosts("profilePosts"),
    ProfileCountryCode("profileCountryCode"),
    CurrentProfile("currentProfile"),
}

/** Disk + memory cache for feeds — iOS `ContentCache.swift`. */
class ContentCache private constructor(context: Context) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val directory = File(context.cacheDir, "MatteryaContentCache").also { it.mkdirs() }

    private val memoryPosts = ConcurrentHashMap<ContentCacheKey, CachedPostList>()
    @Volatile private var memoryProfileCountryCode: String? = null
    @Volatile private var memoryProfile: Profile? = null
    private val memoryTimestamps = ConcurrentHashMap<ContentCacheKey, Long>()
    private val feedKeysLoadedFromDisk = ConcurrentHashMap.newKeySet<ContentCacheKey>()

    init {
        restoreProfileFromDisk()
        scope.launch { pruneOversizedFiles() }
    }

    fun cachedProfile(): Profile? = memoryProfile

    fun setProfile(profile: Profile?) {
        memoryProfile = profile
        setProfileCountryCode(profile?.countryCode)
        if (profile == null) {
            fileFor(ContentCacheKey.CurrentProfile).delete()
            return
        }
        persist(profile, ContentCacheKey.CurrentProfile)
    }

    fun profileCountryCode(): String? = memoryProfileCountryCode

    fun setProfileCountryCode(code: String?) {
        val normalized = code?.uppercase()
        memoryProfileCountryCode = normalized
        if (normalized == null) {
            fileFor(ContentCacheKey.ProfileCountryCode).delete()
            return
        }
        persist(normalized, ContentCacheKey.ProfileCountryCode)
    }

    fun posts(forKey: ContentCacheKey): List<CountryPost>? {
        ensureFeedLoaded(forKey)
        val posts = memoryPosts[forKey]?.posts
        return posts?.takeIf { it.isNotEmpty() }
    }

    fun setPosts(posts: List<CountryPost>, forKey: ContentCacheKey) {
        if (posts.isEmpty()) {
            invalidate(forKey)
            return
        }
        val trimmed = posts.take(MAX_CACHED_POSTS)
        val entry = CachedPostList(System.currentTimeMillis(), trimmed)
        memoryPosts[forKey] = entry
        memoryTimestamps[forKey] = entry.savedAt
        feedKeysLoadedFromDisk.add(forKey)
        val url = fileFor(forKey)
        scope.launch {
            runCatching { url.writeText(json.encodeToString(entry)) }
        }
    }

    fun isFresh(key: ContentCacheKey): Boolean {
        ensureFeedLoaded(key)
        val entry = memoryPosts[key] ?: return false
        if (entry.posts.isEmpty()) return false
        return System.currentTimeMillis() - entry.savedAt < FRESH_TTL_MS
    }

    fun hasStale(key: ContentCacheKey): Boolean {
        ensureFeedLoaded(key)
        val savedAt = memoryTimestamps[key] ?: memoryPosts[key]?.savedAt ?: return false
        return System.currentTimeMillis() - savedAt < STALE_TTL_MS
    }

    fun invalidate(vararg keys: ContentCacheKey) {
        for (key in keys) {
            memoryPosts.remove(key)
            memoryTimestamps.remove(key)
            feedKeysLoadedFromDisk.remove(key)
            fileFor(key).delete()
        }
    }

    fun invalidateAllFeeds() {
        invalidate(ContentCacheKey.HomeFeed, ContentCacheKey.LivingVideos, ContentCacheKey.ProfilePosts)
    }

    private fun restoreProfileFromDisk() {
        loadSync<Profile>(ContentCacheKey.CurrentProfile)?.let {
            memoryProfile = it
            memoryProfileCountryCode = it.countryCode?.uppercase()
        } ?: loadSync<String>(ContentCacheKey.ProfileCountryCode)?.let {
            memoryProfileCountryCode = it
        }
    }

    private fun ensureFeedLoaded(key: ContentCacheKey) {
        if (key !in listOf(
                ContentCacheKey.HomeFeed, ContentCacheKey.LivingVideos,
                ContentCacheKey.SavedPosts, ContentCacheKey.ProfilePosts,
            )
        ) return
        if (!feedKeysLoadedFromDisk.add(key)) return
        val file = fileFor(key)
        if (!file.exists()) return
        if (file.length() > 2_000_000) {
            file.delete()
            return
        }
        val entry = loadSync<CachedPostList>(key) ?: return
        if (entry.posts.isEmpty()) {
            file.delete()
            return
        }
        if (entry.posts.size > MAX_CACHED_POSTS) {
            val trimmed = CachedPostList(entry.savedAt, entry.posts.take(MAX_CACHED_POSTS))
            memoryPosts[key] = trimmed
            memoryTimestamps[key] = trimmed.savedAt
            setPosts(trimmed.posts, key)
            return
        }
        memoryPosts[key] = entry
        memoryTimestamps[key] = entry.savedAt
    }

    private fun fileFor(key: ContentCacheKey) = File(directory, "${key.raw}.json")

    private inline fun <reified T> persist(value: T, key: ContentCacheKey) {
        runCatching { fileFor(key).writeText(json.encodeToString(value)) }
    }

    private inline fun <reified T> loadSync(key: ContentCacheKey): T? {
        val file = fileFor(key)
        if (!file.exists()) return null
        return runCatching { json.decodeFromString<T>(file.readText()) }.getOrNull()
    }

    private fun pruneOversizedFiles() {
        for (key in listOf(
            ContentCacheKey.HomeFeed, ContentCacheKey.LivingVideos,
            ContentCacheKey.SavedPosts, ContentCacheKey.ProfilePosts,
        )) {
            val f = fileFor(key)
            if (f.exists() && f.length() > 2_000_000) f.delete()
        }
    }

    @Serializable
    private data class CachedPostList(val savedAt: Long, val posts: List<CountryPost>)

    companion object {
        const val MAX_CACHED_POSTS = 48
        private const val FRESH_TTL_MS = 5 * 60 * 1000L
        private const val STALE_TTL_MS = 24 * 60 * 60 * 1000L

        @Volatile private var instance: ContentCache? = null
        fun get(context: Context): ContentCache =
            instance ?: synchronized(this) {
                instance ?: ContentCache(context.applicationContext).also { instance = it }
            }
    }
}
