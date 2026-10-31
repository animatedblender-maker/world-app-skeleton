package com.matterya.matterya.data.media

/** Shared with UI — single definition in model package. */
typealias UploadProgress = com.matterya.matterya.model.UploadProgress
typealias MediaUploadPhase = com.matterya.matterya.model.MediaUploadPhase

/** iOS `MediaError`. */
sealed class MediaError(message: String) : Exception(message) {
    data object NotAuthenticated : MediaError("Not authenticated.")
    class UploadFailed(message: String) : MediaError(message)
    class InvalidFile(message: String) : MediaError(message)
}
