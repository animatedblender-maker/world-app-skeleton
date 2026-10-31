package com.matterya.matterya.model

import kotlin.math.roundToInt

/** iOS `UploadProgress` — StorageUploadClient.swift */
data class UploadProgress(
    val fractionCompleted: Double,
    val bytesSent: Long,
    val totalBytes: Long,
) {
    val percentText: String
        get() = "${(fractionCompleted * 100).roundToInt()}%"

    val bytesText: String
        get() = "${formattedBytes(bytesSent)} / ${formattedBytes(totalBytes)}"

    companion object {
        fun formattedBytes(bytes: Long): String {
            if (bytes <= 0) return "0 MB"
            val megabytes = bytes / (1024.0 * 1024.0)
            if (megabytes >= 1) return String.format("%.1f MB", megabytes)
            val kilobytes = bytes / 1024.0
            return String.format("%.0f KB", kilobytes)
        }
    }
}

/** iOS `MediaUploadPhase` */
enum class MediaUploadPhase {
    Idle,
    Compressing,
    Uploading,
    Publishing,
}
