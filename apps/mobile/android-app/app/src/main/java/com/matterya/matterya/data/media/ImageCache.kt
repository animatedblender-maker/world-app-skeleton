package com.matterya.matterya.data.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.matterya.matterya.model.CountryPost
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * Fast image pipeline — iOS `ImageCache.swift`.
 * Memory first, disk/network off the main thread. Caps concurrent downloads.
 */
class ImageCache private constructor(private val appContext: Context?) {
    private val memory = ConcurrentHashMap<String, Bitmap>()
    private val inflight = ConcurrentHashMap<String, CompletableDeferred<Bitmap?>>()
    private val downloadGate = Semaphore(20)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val session = OkHttpClient.Builder()
        .connectTimeout(6, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .callTimeout(10, TimeUnit.SECONDS)
        .build()

    private val diskDirectory: File by lazy {
        val base = appContext?.cacheDir ?: File(System.getProperty("java.io.tmpdir") ?: "/tmp")
        File(base, "MatteryaImageCache").also { it.mkdirs() }
    }

    /** Memory only — safe during scroll. */
    fun imageIfCached(url: String, maxPixelSize: Int): Bitmap? {
        val fetchUrl = cacheableUrl(url)
        val primary = cacheKey(fetchUrl, maxPixelSize)
        memory[primary]?.let { return it }
        for (size in SIZE_BUCKETS) {
            if (size == maxPixelSize) continue
            memory[cacheKey(fetchUrl, size)]?.let { return it }
        }
        return null
    }

    fun prefetch(urls: List<String>, maxPixelSize: Int = 420, aggressive: Boolean = false) {
        val cap = if (aggressive) 48 else 24
        val unique = urls.distinct().take(cap)
        for (url in unique) {
            if (imageIfCached(url, maxPixelSize) != null) continue
            scope.launch { image(url, maxPixelSize) }
        }
    }

    fun prefetchPostThumbnails(
        posts: List<CountryPost>,
        maxPixelSize: Int = 420,
        aggressive: Boolean = false,
    ) {
        val urls = posts.mapNotNull { MediaUrlResolver.hubsListPosterUrl(it) }
        prefetch(urls, maxPixelSize, aggressive)
    }

    fun prefetchHubsWindow(
        posts: List<CountryPost>,
        around: Int,
        behind: Int = 6,
        ahead: Int = 24,
        maxPixelSize: Int = 420,
    ) {
        if (posts.isEmpty()) return
        val lo = maxOf(0, around - behind)
        val hi = minOf(posts.size, around + ahead + 1)
        if (lo >= hi) return
        prefetchPostThumbnails(posts.subList(lo, hi), maxPixelSize, aggressive = true)
    }

    fun prefetchHubSlug(
        slug: String,
        from: List<CountryPost>,
        limit: Int = 48,
        maxPixelSize: Int = 420,
    ) {
        val needle = slug.lowercase()
        val matched = from.filter { post ->
            val s = (post.externalRefId ?: "").lowercase()
            s == needle || s.startsWith("${needle}_")
        }
        prefetchPostThumbnails(matched.take(limit), maxPixelSize, aggressive = true)
    }

    fun prefetchFeedMedia(posts: List<CountryPost>, maxPixelSize: Int = 420) {
        val avatarMax = 72
        val mediaUrls = posts.mapNotNull {
            MediaUrlResolver.posterUrl(it)
                ?: MediaUrlResolver.imageUrl(it)
                ?: it.thumbUrl
        }
        val avatarUrls = posts.mapNotNull { post ->
            val raw = post.author?.avatarUrl ?: return@mapNotNull null
            MediaUrlResolver.normalizedAvatarUrl(raw) ?: raw
        }
        prefetch(avatarUrls, avatarMax)
        prefetch(mediaUrls, maxPixelSize)
    }

    suspend fun image(url: String, maxPixelSize: Int): Bitmap? {
        imageIfCached(url, maxPixelSize)?.let { return it }
        val fetchUrl = cacheableUrl(url)
        val key = cacheKey(fetchUrl, maxPixelSize)

        loadFromDisk(key)?.let {
            memory[key] = it
            return it
        }
        for (size in SIZE_BUCKETS) {
            if (size == maxPixelSize) continue
            val alt = cacheKey(fetchUrl, size)
            loadFromDisk(alt)?.let {
                memory[key] = it
                return it
            }
        }

        val existing = inflight[key]
        if (existing != null) return existing.await()

        val deferred = CompletableDeferred<Bitmap?>()
        inflight[key] = deferred
        scope.launch {
            val result = runCatching {
                downloadGate.withPermit {
                    val candidates = fetchCandidates(fetchUrl)
                    for (candidate in candidates) {
                        val data = fetchData(candidate) ?: continue
                        val image = downsample(data, maxPixelSize) ?: continue
                        memory[key] = image
                        saveToDisk(image, key)
                        return@withPermit image
                    }
                    null
                }
            }.getOrNull()
            deferred.complete(result)
            inflight.remove(key)
        }
        return deferred.await()
    }

    private suspend fun fetchData(url: String): ByteArray? = withContext(Dispatchers.IO) {
        runCatching {
            val req = Request.Builder().url(url).get().build()
            val response = session.newCall(req).execute()
            if (!response.isSuccessful) return@runCatching null
            response.body?.bytes()
        }.getOrNull()
    }

    private fun loadFromDisk(key: String): Bitmap? {
        val file = File(diskDirectory, key)
        if (!file.exists()) return null
        return runCatching { BitmapFactory.decodeFile(file.absolutePath) }.getOrNull()
    }

    private fun saveToDisk(image: Bitmap, key: String) {
        scope.launch {
            runCatching {
                val file = File(diskDirectory, key)
                file.outputStream().use { out ->
                    image.compress(Bitmap.CompressFormat.WEBP, 85, out)
                }
            }
        }
    }

    private fun downsample(data: ByteArray, maxPixelSize: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        val sample = calculateInSampleSize(bounds.outWidth, bounds.outHeight, maxPixelSize)
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(data, 0, data.size, opts)
    }

    private fun calculateInSampleSize(width: Int, height: Int, maxPixelSize: Int): Int {
        var inSampleSize = 1
        val maxDim = maxOf(width, height)
        if (maxDim > maxPixelSize && maxPixelSize > 0) {
            var half = maxDim / 2
            while (half / inSampleSize >= maxPixelSize) {
                inSampleSize *= 2
            }
        }
        return maxOf(1, inSampleSize)
    }

    private fun cacheKey(url: String, maxPixelSize: Int): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("$url|$maxPixelSize".toByteArray())
            .joinToString("") { "%02x".format(it) }
        return digest
    }

    private fun cacheableUrl(url: String): String {
        // Strip ephemeral query tokens that bust cache for same image.
        return url.substringBefore("?token=").substringBefore("&token=")
    }

    private fun fetchCandidates(url: String): List<String> {
        val list = mutableListOf(url)
        // Archive thumbs → services/img fallback
        if (url.contains("archive.org") && url.contains(".thumbs")) {
            MediaUrlResolver.archiveItemId(url)?.let {
                list.add("https://archive.org/services/img/$it")
            }
        }
        return list
    }

    companion object {
        private val SIZE_BUCKETS = listOf(240, 280, 320, 360, 420, 480, 720)

        @Volatile private var instance: ImageCache? = null

        val shared: ImageCache
            get() = instance ?: ImageCache(null).also { instance = it }

        fun init(context: Context): ImageCache {
            return instance ?: synchronized(this) {
                instance ?: ImageCache(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): ImageCache = init(context)

        fun configureSharedCache() {
            // Coil handles URLCache-level setup in MatteryaApp.
        }
    }
}
