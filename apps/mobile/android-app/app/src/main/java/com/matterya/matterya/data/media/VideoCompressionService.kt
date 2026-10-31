package com.matterya.matterya.data.media

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/**
 * iOS `VideoCompressionService.swift`.
 *
 * Android MediaCodec transcoding is heavyweight; this port preserves the size gates
 * and API surface. Full multi-preset export can be swapped for Media3 Transformer
 * when media dependencies are expanded. Until then, files under the skip threshold
 * pass through; larger files are accepted if already under max, else error.
 */
class VideoCompressionService private constructor(
    private val appContext: Context?,
) {
    sealed class VideoCompressionError(message: String) : Exception(message) {
        class ExportFailed(message: String) : VideoCompressionError(message)
        class TooLarge(val bytes: Int) : VideoCompressionError(
            String.format(
                "Video is still %.0f MB after compression. Try a shorter clip.",
                bytes / (1024.0 * 1024.0),
            ),
        )
    }

    suspend fun prepareVideoForUpload(
        source: File,
        onProgress: ((Double) -> Unit)? = null,
    ): File = withContext(Dispatchers.IO) {
        val sourceSize = source.length().toInt()
        val ext = source.extension.lowercase()
        if (sourceSize > 0 &&
            sourceSize <= SKIP_COMPRESSION_BELOW_BYTES &&
            (ext == "mp4" || ext == "m4v")
        ) {
            onProgress?.invoke(1.0)
            return@withContext source
        }

        onProgress?.invoke(0.0)

        // If already under max, skip heavy encode (device-friendly default).
        if (sourceSize in 1..MAX_UPLOAD_BYTES) {
            onProgress?.invoke(1.0)
            return@withContext source
        }

        // Copy to cache as staging (placeholder for Media3 Transformer pipeline).
        val out = File(
            appContext?.cacheDir ?: source.parentFile,
            "upload-${UUID.randomUUID()}.mp4",
        )
        source.copyTo(out, overwrite = true)
        onProgress?.invoke(0.5)
        val outSize = out.length().toInt()
        if (outSize <= MAX_UPLOAD_BYTES) {
            onProgress?.invoke(1.0)
            return@withContext out
        }
        out.delete()
        throw VideoCompressionError.TooLarge(outSize)
    }

    suspend fun generateThumbnail(from: File, atSeconds: Double = 0.0): Bitmap? =
        withContext(Dispatchers.IO) {
            runCatching {
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(from.absolutePath)
                val timeUs = (maxOf(0.0, atSeconds) * 1_000_000).toLong()
                val frame = retriever.getFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                )
                retriever.release()
                frame
            }.getOrNull()
        }

    suspend fun generateThumbnail(uri: Uri, atSeconds: Double = 0.0): Bitmap? =
        withContext(Dispatchers.IO) {
            val ctx = appContext ?: return@withContext null
            runCatching {
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(ctx, uri)
                val timeUs = (maxOf(0.0, atSeconds) * 1_000_000).toLong()
                val frame = retriever.getFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                )
                retriever.release()
                frame
            }.getOrNull()
        }

    companion object {
        const val MAX_UPLOAD_BYTES = 48 * 1024 * 1024
        private const val SKIP_COMPRESSION_BELOW_BYTES = 24 * 1024 * 1024

        @Volatile private var instance: VideoCompressionService? = null

        val shared: VideoCompressionService
            get() = instance ?: VideoCompressionService(null).also { instance = it }

        fun init(context: Context): VideoCompressionService {
            return instance ?: synchronized(this) {
                instance ?: VideoCompressionService(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): VideoCompressionService = init(context)

        fun formattedSize(bytes: Int): String {
            if (bytes <= 0) return "0 MB"
            val megabytes = bytes / (1024.0 * 1024.0)
            if (megabytes >= 1) return String.format("%.1f MB", megabytes)
            val kilobytes = bytes / 1024.0
            return String.format("%.0f KB", kilobytes)
        }
    }
}
