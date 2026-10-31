package com.matterya.matterya.ui.living

import androidx.compose.runtime.Composable
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.ui.hubs.YouTubeAppView

/**
 * iOS `LivingView` / `MatteryaHubsView` — Hubs tab hosts [YouTubeAppView].
 */
@Composable
fun LivingView(
    videos: List<CountryPost> = emptyList(),
    sparks: List<CountryPost> = emptyList(),
    continueWatching: List<CountryPost> = emptyList(),
    isLoading: Boolean = false,
    errorMessage: String? = null,
    hostsShareSheet: Boolean = false,
    onSearch: () -> Unit = {},
    onOpenVideo: (CountryPost) -> Unit = {},
    onOpenSpark: (CountryPost) -> Unit = {},
) {
    @Suppress("UNUSED_VARIABLE")
    val _shareHost = hostsShareSheet
    @Suppress("UNUSED_VARIABLE")
    val _loading = isLoading
    @Suppress("UNUSED_VARIABLE")
    val _error = errorMessage
    YouTubeAppView(
        seedVideos = videos,
        seedSparks = sparks,
        seedContinueWatching = continueWatching,
        onSearch = onSearch,
        onOpenVideo = onOpenVideo,
        onOpenSpark = onOpenSpark,
    )
}
