package com.matterya.matterya.data.media

import android.util.Base64
import com.matterya.matterya.config.AppConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.TimeUnit

/**
 * Supabase Storage TUS resumable uploads — iOS `SupabaseResumableUploadClient.swift`.
 * https://supabase.com/docs/guides/storage/uploads/resumable-uploads
 */
class SupabaseResumableUploadClient private constructor() {
    private val client = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60 * 20, TimeUnit.SECONDS)
        .writeTimeout(60 * 20, TimeUnit.SECONDS)
        .callTimeout(60 * 30, TimeUnit.SECONDS)
        .build()

    suspend fun upload(
        bucket: String,
        path: String,
        file: File,
        mimeType: String,
        accessTokenProvider: suspend () -> String,
        onProgress: ((UploadProgress) -> Unit)? = null,
    ) = withContext(Dispatchers.IO) {
        val fileSize = file.length()
        if (fileSize <= 0) throw MediaError.UploadFailed("Video file is empty.")

        val initialToken = accessTokenProvider()
        val uploadUrl = createUploadSession(
            bucket = bucket,
            path = path,
            fileSize = fileSize,
            mimeType = mimeType,
            accessToken = initialToken,
        )
        uploadChunks(
            uploadUrl = uploadUrl,
            file = file,
            fileSize = fileSize,
            accessTokenProvider = accessTokenProvider,
            onProgress = onProgress,
        )
    }

    private fun createUploadSession(
        bucket: String,
        path: String,
        fileSize: Long,
        mimeType: String,
        accessToken: String,
    ): String {
        val endpoint = "${AppConfig.supabaseStorageURL}/storage/v1/upload/resumable"
        val request = Request.Builder()
            .url(endpoint)
            .post(ByteArray(0).toRequestBody(null))
            .header("Tus-Resumable", TUS_VERSION)
            .header("Upload-Length", fileSize.toString())
            .header(
                "Upload-Metadata",
                tusMetadata(
                    listOf(
                        "bucketName" to bucket,
                        "objectName" to path,
                        "contentType" to mimeType,
                        "cacheControl" to "3600",
                    ),
                ),
            )
            .header("Authorization", "Bearer $accessToken")
            .header("apikey", AppConfig.supabaseAnonKey)
            .build()

        val response = client.newCall(request).execute()
        val body = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            throw MediaError.UploadFailed(storageErrorMessage(body, response.code))
        }
        val location = response.header("Location")
            ?: throw MediaError.UploadFailed("Supabase did not return an upload location.")
        return resolveUploadLocation(location, endpoint)
    }

    private suspend fun uploadChunks(
        uploadUrl: String,
        file: File,
        fileSize: Long,
        accessTokenProvider: suspend () -> String,
        onProgress: ((UploadProgress) -> Unit)?,
    ) {
        RandomAccessFile(file, "r").use { raf ->
            var offset = 0L
            emitProgress(0, fileSize, onProgress)
            while (offset < fileSize) {
                val remaining = fileSize - offset
                val chunkLength = minOf(CHUNK_SIZE.toLong(), remaining).toInt()
                raf.seek(offset)
                val chunk = ByteArray(chunkLength)
                val read = raf.read(chunk)
                if (read != chunkLength) {
                    throw MediaError.UploadFailed("Could not read video file for upload.")
                }
                val accessToken = accessTokenProvider()
                val (responseBody, code, headers) = uploadChunkWithTimeout(
                    uploadUrl = uploadUrl,
                    offset = offset,
                    chunkData = chunk,
                    accessToken = accessToken,
                )
                if (code !in 200..299) {
                    throw MediaError.UploadFailed(storageErrorMessage(responseBody, code))
                }
                val newOffset = headers["Upload-Offset"]?.toLongOrNull()
                offset = newOffset ?: (offset + chunkLength)
                emitProgress(offset, fileSize, onProgress)
            }
            emitProgress(fileSize, fileSize, onProgress)
        }
    }

    private suspend fun uploadChunkWithTimeout(
        uploadUrl: String,
        offset: Long,
        chunkData: ByteArray,
        accessToken: String,
    ): Triple<String, Int, Map<String, String>> = coroutineScope {
        val uploadJob = async(Dispatchers.IO) {
            val request = Request.Builder()
                .url(uploadUrl)
                .patch(chunkData.toRequestBody("application/offset+octet-stream".toMediaType()))
                .header("Tus-Resumable", TUS_VERSION)
                .header("Upload-Offset", offset.toString())
                .header("Content-Type", "application/offset+octet-stream")
                .header("Authorization", "Bearer $accessToken")
                .header("apikey", AppConfig.supabaseAnonKey)
                .build()
            val response = client.newCall(request).execute()
            val body = response.body?.string().orEmpty()
            val headers = response.headers.toMultimap().mapValues { it.value.firstOrNull().orEmpty() }
            Triple(body, response.code, headers)
        }
        val result = withTimeoutOrNull(CHUNK_TIMEOUT_MS) { uploadJob.await() }
            ?: run {
                uploadJob.cancel()
                throw MediaError.UploadFailed("Upload stalled. Check your connection and try again.")
            }
        result
    }

    private fun resolveUploadLocation(location: String, relativeTo: String): String {
        if (location.startsWith("http://") || location.startsWith("https://")) return location
        val base = relativeTo.trimEnd('/')
        return if (location.startsWith("/")) {
            val origin = base.substringBefore("/storage/")
            "$origin$location"
        } else {
            "$base/$location"
        }
    }

    private fun tusMetadata(pairs: List<Pair<String, String>>): String =
        pairs.joinToString(",") { (key, value) ->
            val encoded = Base64.encodeToString(value.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
            "$key $encoded"
        }

    private fun emitProgress(
        bytesSent: Long,
        totalBytes: Long,
        handler: ((UploadProgress) -> Unit)?,
    ) {
        if (handler == null) return
        val total = maxOf(totalBytes, 1)
        handler(
            UploadProgress(
                fractionCompleted = minOf(1.0, bytesSent.toDouble() / total.toDouble()),
                bytesSent = bytesSent,
                totalBytes = total,
            ),
        )
    }

    private fun storageErrorMessage(body: String, statusCode: Int): String {
        runCatching {
            val o = JSONObject(body)
            val message = o.optString("message")
            if (message.isNotEmpty()) return message
            val error = o.optString("error")
            if (error.isNotEmpty()) return error
        }
        if (body.isNotEmpty()) return body
        return "Supabase upload failed (HTTP $statusCode)."
    }

    companion object {
        private const val CHUNK_SIZE = 6 * 1024 * 1024
        private const val TUS_VERSION = "1.0.0"
        private const val CHUNK_TIMEOUT_MS = 120_000L

        val shared by lazy { SupabaseResumableUploadClient() }
    }
}
