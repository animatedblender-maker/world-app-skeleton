package com.matterya.matterya.ui.hubs

import androidx.compose.runtime.Composable
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.ui.living.LivingView

/**
 * iOS `MatteryaHubsView` / `HubsComingSoonView` — Hubs tab is Living (YouTubeAppView).
 */
@Composable
fun HubsComingSoonView(
    videos: List<CountryPost> = emptyList(),
    sparks: List<CountryPost> = emptyList(),
    continueWatching: List<CountryPost> = emptyList(),
    isLoading: Boolean = false,
    onSearch: () -> Unit = {},
    onOpenVideo: (CountryPost) -> Unit = {},
    onOpenSpark: (CountryPost) -> Unit = {},
) = LivingView(
    videos = videos,
    sparks = sparks,
    continueWatching = continueWatching,
    isLoading = isLoading,
    onSearch = onSearch,
    onOpenVideo = onOpenVideo,
    onOpenSpark = onOpenSpark,
)
