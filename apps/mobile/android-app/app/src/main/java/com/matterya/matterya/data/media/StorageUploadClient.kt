package com.matterya.matterya.data.media

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okio.BufferedSink
import okio.source
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * iOS `StorageUploadClient.swift` — progress-aware HTTP upload.
 */
class StorageUploadClient private constructor() {
    private val client = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60 * 20, TimeUnit.SECONDS)
        .writeTimeout(60 * 20, TimeUnit.SECONDS)
        .callTimeout(60 * 30, TimeUnit.SECONDS)
        .build()

    data class UploadResponse(val body: ByteArray, val code: Int, val headers: Map<String, String>)

    suspend fun upload(
        request: Request,
        file: File,
        onProgress: ((UploadProgress) -> Unit)? = null,
    ): UploadResponse = withContext(Dispatchers.IO) {
        val expected = file.length().coerceAtLeast(0)
        onProgress?.invoke(UploadProgress(0.0, 0, expected.coerceAtLeast(1)))

        val contentType = request.header("Content-Type")?.toMediaTypeOrNull()
            ?: "application/octet-stream".toMediaTypeOrNull()

        val body: RequestBody = if (onProgress == null) {
            file.asRequestBody(contentType)
        } else {
            object : RequestBody() {
                override fun contentType() = contentType
                override fun contentLength() = expected
                override fun writeTo(sink: BufferedSink) {
                    file.source().use { source ->
                        var sent = 0L
                        val buffer = okio.Buffer()
                        while (true) {
                            val read = source.read(buffer, 8_192)
                            if (read == -1L) break
                            sink.write(buffer, read)
                            sent += read
                            val total = expected.coerceAtLeast(1)
                            onProgress(
                                UploadProgress(
                                    fractionCompleted = (sent.toDouble() / total).coerceIn(0.0, 1.0),
                                    bytesSent = sent,
                                    totalBytes = total,
                                ),
                            )
                        }
                    }
                }
            }
        }

        val uploadRequest = request.newBuilder().method(request.method, body).build()
        val response = client.newCall(uploadRequest).execute()
        val bytes = response.body?.bytes() ?: ByteArray(0)
        if (onProgress != null) {
            val total = expected.coerceAtLeast(1)
            onProgress(UploadProgress(1.0, total, total))
        }
        if (response.code == 0) {
            throw MediaError.UploadFailed("Missing upload response.")
        }
        UploadResponse(
            body = bytes,
            code = response.code,
            headers = response.headers.toMultimap().mapValues { it.value.firstOrNull().orEmpty() },
        )
    }

    companion object {
        val shared by lazy { StorageUploadClient() }
    }
}
