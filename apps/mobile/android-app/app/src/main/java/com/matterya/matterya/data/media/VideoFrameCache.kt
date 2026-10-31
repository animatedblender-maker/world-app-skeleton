package com.matterya.matterya.data.media

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Native Android video frame cache — mirrors iOS `VideoFrameCache` /
 * MediaMetadataRetriever (not Flutter).
 *
 * R2 sparks often have null thumb_url; we extract one JPEG frame and cache it.
 */
class VideoFrameCache private constructor(private val appContext: Context) {
    private val memory = ConcurrentHashMap<String, Bitmap>()
    private val gate = Mutex()
    private var active = 0
    private val maxConcurrent = 3

    private val dir: File by lazy {
        File(appContext.cacheDir, "VideoFrameCache").also { it.mkdirs() }
    }

    suspend fun image(postId: String, videoUrl: String, maxSize: Int = 480): Bitmap? {
        if (videoUrl.isBlank()) return null
        val key = key(postId, videoUrl)
        memory[key]?.let { return it }

        val disk = File(dir, "$key.jpg")
        if (disk.exists()) {
            val bmp = runCatching {
                android.graphics.BitmapFactory.decodeFile(disk.absolutePath)
            }.getOrNull()
            if (bmp != null) {
                memory[key] = bmp
                return bmp
            }
        }

        return withContext(Dispatchers.IO) {
            gate.withLock {
                while (active >= maxConcurrent) {
                    kotlinx.coroutines.delay(100)
                }
                active++
            }
            try {
                extract(videoUrl, maxSize)?.also { bmp ->
                    memory[key] = bmp
                    runCatching {
                        FileOutputStream(disk).use { out ->
                            bmp.compress(Bitmap.CompressFormat.JPEG, 80, out)
                        }
                    }
                }
            } finally {
                gate.withLock { active-- }
            }
        }
    }

    private fun extract(videoUrl: String, maxSize: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoUrl, HashMap())
            // Prefer ~350ms; fall back to start.
            val timesUs = longArrayOf(350_000L, 1_000_000L, 0L)
            var bitmap: Bitmap? = null
            for (t in timesUs) {
                bitmap = retriever.getFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (bitmap != null) break
            }
            bitmap?.let { scale(it, maxSize) }
        } catch (e: Exception) {
            Log.w(TAG, "extract failed: ${e.message}")
            null
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun scale(src: Bitmap, maxSize: Int): Bitmap {
        val w = src.width
        val h = src.height
        val longEdge = maxOf(w, h)
        if (longEdge <= maxSize) return src
        val scale = maxSize.toFloat() / longEdge
        val nw = (w * scale).toInt().coerceAtLeast(1)
        val nh = (h * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, nw, nh, true)
    }

    private fun key(postId: String, videoUrl: String): String {
        val path = runCatching { java.net.URI(videoUrl).path }.getOrNull() ?: videoUrl
        val raw = "$postId|$path"
        val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray())
        return digest.take(12).joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val TAG = "VideoFrameCache"

        @Volatile private var _instance: VideoFrameCache? = null
        fun instance(context: Context): VideoFrameCache {
            return _instance ?: synchronized(this) {
                _instance ?: VideoFrameCache(context.applicationContext).also { _instance = it }
            }
        }
    }
}
