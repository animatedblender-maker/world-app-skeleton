package com.matterya.matterya.data.media

import com.matterya.matterya.model.AppDestination
import com.matterya.matterya.model.AppTab
import com.matterya.matterya.viewmodel.AppUiState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.max
import kotlin.math.min

enum class FeedAutoplaySurface {
    Home, Profile;

    /** Whether this surface should currently autoplay, given shell UI state. */
    fun isLive(state: AppUiState): Boolean {
        return when (this) {
            Home -> state.selectedTab == AppTab.Feed && state.sessionReady
            Profile -> state.selectedTab == AppTab.Profile && state.sessionReady
        }
    }

    fun isLive(
        selectedTab: AppTab,
        navigationPath: List<AppDestination> = emptyList(),
        reelsOpen: Boolean = false,
        hubPlaying: Boolean = false,
    ): Boolean {
        if (reelsOpen || hubPlaying) return false
        return when (this) {
            Home -> selectedTab == AppTab.Feed && navigationPath.isEmpty()
            Profile -> {
                if (selectedTab == AppTab.Profile && navigationPath.isEmpty()) return true
                navigationPath.any {
                    it is AppDestination.PublicProfile || it is AppDestination.PublicProfileByUserId
                }
            }
        }
    }
}

/**
 * Exactly one feed video plays at a time — most visible eligible card.
 * Pause when more than 70% off-screen (visible ratio < 0.30). iOS `FeedVideoFocus.swift`.
 */
class FeedVideoFocus private constructor() {
    private val _activeId = MutableStateFlow<String?>(null)
    val activeId: StateFlow<String?> = _activeId.asStateFlow()

    private val visibility = mutableMapOf<String, Float>()

    fun reportVisibility(postId: String, ratio: Float) {
        val clamped = min(1f, max(0f, ratio))
        if (clamped < 0.05f) {
            visibility.remove(postId)
        } else {
            visibility[postId] = clamped
        }
        elect()
    }

    fun clear(postId: String) {
        visibility.remove(postId)
        if (_activeId.value == postId) elect()
    }

    fun resetAll() {
        visibility.clear()
        _activeId.value = null
    }

    private fun elect() {
        val winner = visibility.entries
            .filter { it.value >= 0.30f }
            .maxByOrNull { it.value }
            ?.key
        if (_activeId.value != winner) {
            _activeId.value = winner
        }
    }

    companion object {
        val shared: FeedVideoFocus by lazy { FeedVideoFocus() }
    }
}
