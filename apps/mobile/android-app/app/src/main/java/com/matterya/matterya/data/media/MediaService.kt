package com.matterya.matterya.data.media

import android.content.Context
import android.net.Uri
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.model.UploadProgress
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * iOS `MediaService.swift` — Supabase storage uploads for avatars, posts, ads, messages.
 * Uses [StorageUploadClient] for direct PUT/POST and [SupabaseResumableUploadClient] for large video.
 */
class MediaService private constructor(
    private val appContext: Context,
    private val auth: AuthService = AuthService.instance,
) {
    private val http = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60 * 20, TimeUnit.SECONDS)
        .writeTimeout(60 * 20, TimeUnit.SECONDS)
        .callTimeout(60 * 30, TimeUnit.SECONDS)
        .build()

    private val signedMessageURLCache = ConcurrentHashMap<String, Pair<String, Long>>()

    data class UploadResult(
        val path: String,
        val publicURL: String,
    )

    data class MessageMediaResult(
        val path: String,
        val name: String,
        val mime: String,
        val size: Int,
    )

    // ── Ad media ──────────────────────────────────────────────────────

    suspend fun uploadAdMedia(
        data: ByteArray,
        fileExtension: String,
        mimeType: String,
        onProgress: ((UploadProgress) -> Unit)? = null,
    ): UploadResult {
        if (!mimeType.startsWith("video/")) {
            throw MediaError.UploadFailed("Ad creative must be a video file.")
        }
        val ext = fileExtension.lowercase().ifEmpty { "mp4" }
        val temp = writeTemp(data, "ad-upload-${UUID.randomUUID()}.$ext")
        return try {
            uploadAdMedia(temp, ext, mimeType, onProgress)
        } finally {
            temp.delete()
        }
    }

    suspend fun uploadAdMedia(
        file: File,
        fileExtension: String,
        mimeType: String,
        onProgress: ((UploadProgress) -> Unit)? = null,
    ): UploadResult {
        if (!mimeType.startsWith("video/")) {
            throw MediaError.UploadFailed("Ad creative must be a video file.")
        }
        val userId = auth.currentUser?.id ?: throw MediaError.NotAuthenticated
        val ext = fileExtension.lowercase().ifEmpty { "mp4" }
        val path = "$userId/ads/${UUID.randomUUID()}.$ext"
        upload(
            bucket = "posts",
            path = path,
            file = file,
            mimeType = mimeType,
            onProgress = onProgress,
        )
        return UploadResult(path, publicObjectURL("posts", path))
    }

    // ── Post media ────────────────────────────────────────────────────

    suspend fun uploadPostMedia(
        data: ByteArray,
        fileExtension: String,
        mimeType: String,
        onProgress: ((UploadProgress) -> Unit)? = null,
    ): UploadResult {
        val userId = auth.currentUser?.id ?: throw MediaError.NotAuthenticated
        val ext = fileExtension.ifEmpty { guessExtension(mimeType) }
        val path = "$userId/${UUID.randomUUID()}.$ext"
        if (mimeType.startsWith("video/")) {
            val temp = writeTemp(data, "post-${UUID.randomUUID()}.$ext")
            return try {
                uploadVideoToPosts(path, temp, mimeType, onProgress)
                UploadResult(path, publicObjectURL("posts", path))
            } finally {
                temp.delete()
            }
        }
        uploadBytes(bucket = "posts", path = path, data = data, mimeType = mimeType)
        return UploadResult(path, publicObjectURL("posts", path))
    }

    suspend fun uploadPostMedia(
        file: File,
        fileExtension: String,
        mimeType: String,
        onProgress: ((UploadProgress) -> Unit)? = null,
    ): UploadResult {
        val userId = auth.currentUser?.id ?: throw MediaError.NotAuthenticated
        val ext = fileExtension.ifEmpty { guessExtension(mimeType) }
        val path = "$userId/${UUID.randomUUID()}.$ext"
        if (mimeType.startsWith("video/")) {
            uploadVideoToPosts(path, file, mimeType, onProgress)
        } else {
            upload(bucket = "posts", path = path, file = file, mimeType = mimeType, onProgress = onProgress)
        }
        return UploadResult(path, publicObjectURL("posts", path))
    }

    /**
     * Upload image/video from a content [Uri] (photo picker / SAF).
     * Returns public storage URL suitable for GraphQL createPost.
     */
    suspend fun uploadPostMediaFromUri(
        uri: Uri,
        isVideo: Boolean,
        onProgress: ((UploadProgress) -> Unit)? = null,
    ): UploadResult = withContext(Dispatchers.IO) {
        if (isVideo) {
            val file = copyUriToCache(uri, "post-video-${UUID.randomUUID()}.mp4")
            try {
                val prepared = VideoCompressionService.shared.prepareVideoForUpload(file) { frac ->
                    onProgress?.invoke(
                        UploadProgress(
                            fractionCompleted = frac * 0.15,
                            bytesSent = 0,
                            totalBytes = 1,
                        ),
                    )
                }
                try {
                    val result = uploadPostMedia(
                        file = prepared,
                        fileExtension = prepared.extension.ifEmpty { "mp4" },
                        mimeType = "video/mp4",
                        onProgress = { p ->
                            // Map remaining 85% of progress after compression phase
                            onProgress?.invoke(
                                UploadProgress(
                                    fractionCompleted = 0.15 + p.fractionCompleted * 0.85,
                                    bytesSent = p.bytesSent,
                                    totalBytes = p.totalBytes,
                                ),
                            )
                        },
                    )
                    result
                } finally {
                    if (prepared != file) prepared.delete()
                }
            } finally {
                file.delete()
            }
        } else {
            val jpeg = PhotosPickerMediaLoader.loadJpegData(appContext, uri, compressionQuality = 85, maxEdge = 1920)
            uploadPostMedia(data = jpeg, fileExtension = "jpg", mimeType = "image/jpeg", onProgress = onProgress)
        }
    }

    // ── Avatar ────────────────────────────────────────────────────────

    /**
     * Upload avatar without freezing UI. Encode + HTTP run on IO dispatcher.
     */
    suspend fun uploadAvatar(
        data: ByteArray,
        fileExtension: String,
        mimeType: String,
    ): UploadResult {
        val userId = auth.currentUser?.id ?: throw MediaError.NotAuthenticated
        if (mimeType == "image/gif") throw MediaError.UploadFailed("GIF avatars are disabled.")
        if (data.isEmpty()) throw MediaError.UploadFailed("Empty image data.")

        val token = try {
            auth.ensureValidToken()
        } catch (_: Exception) {
            throw MediaError.NotAuthenticated
        }
        val ext = fileExtension.ifEmpty { "jpg" }
        val path = "$userId/${UUID.randomUUID()}.$ext"
        val publicURL = putAvatarOffMain(data, path, mimeType, token)
        return UploadResult(path, publicURL)
    }

    suspend fun uploadAvatarFromUri(uri: Uri): UploadResult {
        val jpeg = PhotosPickerMediaLoader.loadJpegData(appContext, uri, compressionQuality = 82, maxEdge = 1024)
        return uploadAvatar(jpeg, "jpg", "image/jpeg")
    }

    fun normalizedAvatarURL(url: String?): String? {
        val raw = url?.trim().orEmpty()
        if (raw.isEmpty()) return null
        if (raw.startsWith("data:") || raw.startsWith("blob:")) return raw

        val objectPrefix = "${AppConfig.supabaseURL}/storage/v1/object/"
        val signMarker = "${objectPrefix}sign/avatars/"
        if (raw.contains(signMarker)) {
            val path = raw.substringAfter(signMarker).substringBefore("?")
            val decoded = runCatching { java.net.URLDecoder.decode(path, Charsets.UTF_8.name()) }.getOrDefault(path)
            return publicAvatarURL(decoded)
        }

        val publicMarker = "${objectPrefix}public/avatars/"
        if (raw.startsWith(publicMarker)) {
            return raw.substringBefore("?")
        }

        if (raw.startsWith("http://") || raw.startsWith("https://")) {
            return raw.substringBefore("?")
        }

        return publicAvatarURL(raw.trim('/'))
    }

    // ── Messages ──────────────────────────────────────────────────────

    suspend fun signedMessageURL(path: String): String {
        val cached = signedMessageURLCache[path]
        if (cached != null && cached.second > System.currentTimeMillis()) {
            return cached.first
        }
        val url = createSignedURL(bucket = "messages", path = path)
        signedMessageURLCache[path] = url to (System.currentTimeMillis() + 55 * 60 * 1000L)
        return url
    }

    suspend fun uploadMessageMedia(
        data: ByteArray,
        conversationId: String,
        fileName: String,
        mimeType: String,
    ): MessageMediaResult {
        val userId = auth.currentUser?.id ?: throw MediaError.NotAuthenticated
        val ext = fileName.substringAfterLast('.', missingDelimiterValue = "").lowercase().ifEmpty { "bin" }
        val path = "$userId/$conversationId/${UUID.randomUUID()}.$ext"
        uploadBytes(bucket = "messages", path = path, data = data, mimeType = mimeType)
        return MessageMediaResult(path = path, name = fileName, mime = mimeType, size = data.size)
    }

    // ── Internals ─────────────────────────────────────────────────────

    private suspend fun putAvatarOffMain(
        data: ByteArray,
        path: String,
        mimeType: String,
        token: String,
    ): String = withContext(Dispatchers.IO) {
        var payload = data
        if (payload.size > 900_000) {
            payload = PhotosPickerMediaLoader.normalizeToJpeg(payload, quality = 72, maxEdge = 1024)
        }
        val encodedPath = encodedStoragePath(path)
        val url = "${AppConfig.supabaseURL}/storage/v1/object/avatars/$encodedPath"
        val body = payload.toRequestBody(mimeType.toMediaTypeOrNull())
        val request = Request.Builder()
            .url(url)
            .post(body)
            .header("Content-Type", mimeType)
            .header("apikey", AppConfig.supabaseAnonKey)
            .header("Authorization", "Bearer $token")
            .header("x-upsert", "true")
            .build()
        val response = http.newCall(request).execute()
        val responseBody = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            throw MediaError.UploadFailed(storageErrorMessage(responseBody, response.code))
        }
        publicAvatarURL(path)
    }

    private suspend fun uploadVideoToPosts(
        path: String,
        file: File,
        mimeType: String,
        onProgress: ((UploadProgress) -> Unit)?,
    ) {
        var lastError: Exception? = null
        repeat(2) { attempt ->
            try {
                // Prefer resumable for larger videos; direct for small
                if (file.length() > 8L * 1024 * 1024) {
                    SupabaseResumableUploadClient.shared.upload(
                        bucket = "posts",
                        path = path,
                        file = file,
                        mimeType = mimeType,
                        accessTokenProvider = {
                            try {
                                auth.ensureValidToken()
                            } catch (_: Exception) {
                                throw MediaError.NotAuthenticated
                            }
                        },
                        onProgress = onProgress,
                    )
                } else {
                    uploadDirect(
                        bucket = "posts",
                        path = path,
                        file = file,
                        mimeType = mimeType,
                        upsert = false,
                        onProgress = onProgress,
                    )
                }
                return
            } catch (e: Exception) {
                lastError = e
                if (attempt == 0) {
                    runCatching { auth.ensureValidToken() }
                }
            }
        }
        throw lastError ?: MediaError.UploadFailed("Upload failed.")
    }

    private suspend fun upload(
        bucket: String,
        path: String,
        file: File,
        mimeType: String,
        upsert: Boolean = false,
        onProgress: ((UploadProgress) -> Unit)? = null,
    ) {
        uploadDirect(bucket, path, file, mimeType, upsert, onProgress)
    }

    private suspend fun uploadDirect(
        bucket: String,
        path: String,
        file: File,
        mimeType: String,
        upsert: Boolean,
        onProgress: ((UploadProgress) -> Unit)?,
    ) {
        val request = makeUploadRequest(bucket, path, mimeType, upsert)
        val response = StorageUploadClient.shared.upload(request, file, onProgress)
        if (response.code !in 200..299) {
            throw MediaError.UploadFailed(
                storageErrorMessage(String(response.body, Charsets.UTF_8), response.code),
            )
        }
    }

    private suspend fun uploadBytes(
        bucket: String,
        path: String,
        data: ByteArray,
        mimeType: String,
        upsert: Boolean = false,
    ) = withContext(Dispatchers.IO) {
        val request = makeUploadRequest(bucket, path, mimeType, upsert)
        val body = data.toRequestBody(mimeType.toMediaTypeOrNull())
        val uploadRequest = request.newBuilder().method(request.method, body).build()
        val response = http.newCall(uploadRequest).execute()
        val responseBody = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            throw MediaError.UploadFailed(storageErrorMessage(responseBody, response.code))
        }
    }

    private suspend fun makeUploadRequest(
        bucket: String,
        path: String,
        mimeType: String,
        upsert: Boolean,
    ): Request {
        val token = try {
            auth.ensureValidToken()
        } catch (_: Exception) {
            throw MediaError.NotAuthenticated
        }
        val url = storageObjectURL(bucket, path)
            ?: throw MediaError.UploadFailed("Invalid upload URL.")
        return Request.Builder()
            .url(url)
            .post(ByteArray(0).toRequestBody(null))
            .header("Content-Type", mimeType)
            .header("apikey", AppConfig.supabaseAnonKey)
            .header("Authorization", "Bearer $token")
            .apply {
                if (upsert) header("x-upsert", "true")
            }
            .build()
    }

    private suspend fun createSignedURL(bucket: String, path: String): String = withContext(Dispatchers.IO) {
        val token = try {
            auth.ensureValidToken()
        } catch (_: Exception) {
            throw MediaError.NotAuthenticated
        }
        val url = storageSignURL(bucket, path)
            ?: throw MediaError.UploadFailed("Invalid sign URL.")
        val body = """{"expiresIn":3600}""".toRequestBody("application/json".toMediaTypeOrNull())
        val request = Request.Builder()
            .url(url)
            .post(body)
            .header("Content-Type", "application/json")
            .header("apikey", AppConfig.supabaseAnonKey)
            .header("Authorization", "Bearer $token")
            .build()
        val response = http.newCall(request).execute()
        val raw = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            throw MediaError.UploadFailed("Failed to sign media URL.")
        }
        val signed = runCatching { JSONObject(raw).optString("signedURL") }.getOrNull().orEmpty()
        if (signed.isEmpty()) throw MediaError.UploadFailed("Failed to sign media URL.")
        if (signed.startsWith("http")) signed
        else "${AppConfig.supabaseURL}/storage/v1$signed"
    }

    private fun writeTemp(data: ByteArray, name: String): File {
        val file = File(appContext.cacheDir, name)
        FileOutputStream(file).use { it.write(data) }
        return file
    }

    private fun copyUriToCache(uri: Uri, name: String): File {
        val file = File(appContext.cacheDir, name)
        appContext.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(file).use { output -> input.copyTo(output) }
        } ?: throw MediaError.InvalidFile("Could not read media file.")
        if (file.length() <= 0) throw MediaError.InvalidFile("Media file is empty.")
        return file
    }

    companion object {
        @Volatile private var instance: MediaService? = null

        fun get(context: Context): MediaService =
            instance ?: synchronized(this) {
                instance ?: MediaService(context.applicationContext).also { instance = it }
            }

        val shared: MediaService
            get() = instance ?: error("MediaService not initialized. Call MediaService.get(context) first.")

        fun init(context: Context) {
            get(context)
        }

        fun publicAvatarURL(path: String): String {
            val cleaned = path.trim('/')
            return "${AppConfig.supabaseURL}/storage/v1/object/public/avatars/$cleaned"
        }

        fun publicObjectURL(bucket: String, path: String): String {
            val cleaned = path.trim('/')
            return "${AppConfig.supabaseURL}/storage/v1/object/public/$bucket/$cleaned"
        }

        fun encodedStoragePath(path: String): String =
            path.split("/")
                .joinToString("/") { segment ->
                    java.net.URLEncoder.encode(segment, Charsets.UTF_8.name())
                        .replace("+", "%20")
                }

        fun storageObjectURL(bucket: String, path: String): String? {
            val encoded = encodedStoragePath(path)
            return "${AppConfig.supabaseURL}/storage/v1/object/$bucket/$encoded"
        }

        fun storageSignURL(bucket: String, path: String): String? {
            val encoded = encodedStoragePath(path)
            return "${AppConfig.supabaseURL}/storage/v1/object/sign/$bucket/$encoded"
        }

        fun storageErrorMessage(body: String, statusCode: Int): String {
            runCatching {
                val o = JSONObject(body)
                val message = o.optString("message")
                if (message.isNotEmpty()) return message
                val error = o.optString("error")
                if (error.isNotEmpty()) return error
            }
            if (body.isNotEmpty()) return body
            if (statusCode == 413) return "Video is too large for storage. Try a shorter clip."
            if (statusCode > 0) return "Upload failed (HTTP $statusCode)."
            return "Upload failed."
        }

        private fun guessExtension(mimeType: String): String = when {
            mimeType.contains("png") -> "png"
            mimeType.contains("webp") -> "webp"
            mimeType.contains("gif") -> "gif"
            mimeType.startsWith("video/") -> "mp4"
            else -> "jpg"
        }
    }
}
