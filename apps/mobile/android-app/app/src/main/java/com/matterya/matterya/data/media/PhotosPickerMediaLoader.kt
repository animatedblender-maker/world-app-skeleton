package com.matterya.matterya.data.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * iOS `PhotosPickerMediaLoader.swift`.
 * Loads image bytes from content URIs (Android photo picker / SAF).
 */
object PhotosPickerMediaLoader {
    sealed class LoadError(message: String) : Exception(message) {
        data object Empty : LoadError("Couldn't read that photo.")
        data object NotAnImage : LoadError("That file isn't a supported image.")
        data object CloudNotDownloaded : LoadError(
            "This photo isn't available offline yet. Open Google Photos / Files and download it, then try again.",
        )
        class Underlying(cause: Throwable) : LoadError(
            friendlyMessage(cause),
        ) {
            init {
                initCause(cause)
            }
        }

        companion object {
            fun friendlyMessage(error: Throwable): String {
                val msg = error.message.orEmpty()
                if (msg.contains("cloud", ignoreCase = true) ||
                    msg.contains("download", ignoreCase = true) ||
                    msg.contains("unavailable", ignoreCase = true)
                ) {
                    return CloudNotDownloaded.message ?: msg
                }
                return msg.ifEmpty { "Couldn't read that photo." }
            }
        }
    }

    suspend fun loadJpegData(
        context: Context,
        uri: Uri,
        compressionQuality: Int = 82,
        maxEdge: Int = 1280,
    ): ByteArray = withContext(Dispatchers.IO) {
        val raw = loadRawImageData(context, uri)
        normalizeToJpeg(raw, compressionQuality, maxEdge)
    }

    suspend fun loadJpegData(
        context: Context,
        uri: Uri,
        timeoutSeconds: Double,
        compressionQuality: Int = 82,
        maxEdge: Int = 1280,
    ): ByteArray = coroutineScope {
        val job = async {
            loadJpegData(context, uri, compressionQuality, maxEdge)
        }
        val result = withTimeoutOrNull((maxOf(5.0, timeoutSeconds) * 1000).toLong()) {
            job.await()
        }
        if (result == null) {
            job.cancel()
            throw LoadError.Underlying(
                Exception("Loading that photo took too long. Try a smaller image."),
            )
        }
        result
    }

    suspend fun loadRawImageData(context: Context, uri: Uri): ByteArray = withContext(Dispatchers.IO) {
        runCatching {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        }.getOrElse {
            throw LoadError.Underlying(it)
        } ?: throw LoadError.Empty
    }

    suspend fun loadJpegData(
        fromFile: File,
        compressionQuality: Int = 88,
    ): ByteArray = withContext(Dispatchers.IO) {
        if (!fromFile.exists()) throw LoadError.Empty
        val raw = fromFile.readBytes()
        normalizeToJpeg(raw, compressionQuality, maxEdge = 1280)
    }

    fun normalizeToJpeg(
        raw: ByteArray,
        quality: Int,
        maxEdge: Int,
    ): ByteArray {
        val bitmap = BitmapFactory.decodeByteArray(raw, 0, raw.size)
            ?: throw LoadError.NotAnImage
        val scaled = scaleDown(bitmap, maxEdge)
        val out = ByteArrayOutputStream()
        val ok = scaled.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), out)
        if (scaled !== bitmap) scaled.recycle()
        if (!bitmap.isRecycled) bitmap.recycle()
        if (!ok) throw LoadError.NotAnImage
        return out.toByteArray()
    }

    fun writeTempJpeg(
        context: Context,
        data: ByteArray,
        name: String = "picked-${System.currentTimeMillis()}.jpg",
    ): File {
        val file = File(context.cacheDir, name)
        FileOutputStream(file).use { it.write(data) }
        return file
    }

    private fun scaleDown(source: Bitmap, maxEdge: Int): Bitmap {
        val w = source.width
        val h = source.height
        val longest = max(w, h)
        if (longest <= maxEdge || maxEdge <= 0) return source
        val scale = maxEdge.toFloat() / longest.toFloat()
        val nw = max(1, (w * scale).roundToInt())
        val nh = max(1, (h * scale).roundToInt())
        return Bitmap.createScaledBitmap(source, nw, nh, true)
    }
}
