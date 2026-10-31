package com.matterya.matterya.data.media

import com.matterya.matterya.model.AppDestination
import com.matterya.matterya.model.AppTab
import com.matterya.matterya.viewmodel.AppUiState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

enum class FeedAutoplaySurface {
    Home, Profile, PostDetail;

    /** Whether this surface should currently autoplay, given shell UI state. */
    fun isLive(state: AppUiState): Boolean {
        return when (this) {
            Home -> state.selectedTab == AppTab.Feed && state.sessionReady
            Profile -> state.selectedTab == AppTab.Profile && state.sessionReady
            PostDetail -> state.selectedTab == AppTab.Feed && state.sessionReady
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
            PostDetail -> {
                if (selectedTab != AppTab.Feed) return false
                navigationPath.any { it is AppDestination.Post }
            }
        }
    }
}

/**
 * Exactly one feed video plays at a time — most visible eligible card.
 * Matches iOS `FeedVideoFocus.swift`: play ≥12% visible, keep ≥8%, steal epsilon,
 * sticky zero-glitch tolerance, cold-open lock, clearElectionOnly vs resetAll.
 */
class FeedVideoFocus private constructor() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _activeId = MutableStateFlow<String?>(null)
    val activeId: StateFlow<String?> = _activeId.asStateFlow()

    private val _generation = MutableStateFlow(0)
    val generation: StateFlow<Int> = _generation.asStateFlow()

    @Volatile
    var autoplayUnlocked: Boolean = false
        private set

    val allowsFeedAVWarm: Boolean get() = autoplayUnlocked

    private val ratios = mutableMapOf<String, Float>()
    private val stickyRatios = mutableMapOf<String, Float>()
    private val zeroStreak = mutableMapOf<String, Int>()

    private var unlockJob: Job? = null
    private var silenceWhenEmptyJob: Job? = null
    private var recomputeScheduled = false

    /** Start autoplay once ~12% is on-screen. */
    private val minVisibleToPlay = 0.12f
    /** Keep current winner until it drops below this. */
    private val minVisibleToKeep = 0.08f
    /** Challenger must beat the current winner by this much to steal focus. */
    private val stealEpsilon = 0.015f
    /** Ignore this many consecutive near-zero layout reports before clearing. */
    private val zeroGlitchTolerance = 6

    fun lockAutoplayForColdOpen() {
        unlockJob?.cancel()
        unlockJob = null
        autoplayUnlocked = false
        publish(winner = null, previous = _activeId.value, silenceImmediately = true)
        MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
    }

    fun unlockAutoplayAfterFirstPaint(delayMs: Long = 100L) {
        unlockJob?.cancel()
        unlockJob = scope.launch {
            delay(delayMs)
            autoplayUnlocked = true
            scheduleRecompute()
        }
    }

    fun reportVisibility(postId: String, ratio: Float) {
        report(postId, ratio)
    }

    fun report(id: String, visibleRatio: Float) {
        val clamped = min(1f, max(0f, visibleRatio))

        if (clamped < 0.02f) {
            val streak = (zeroStreak[id] ?: 0) + 1
            zeroStreak[id] = streak
            if (streak < zeroGlitchTolerance) {
                val sticky = stickyRatios[id]
                if (sticky != null && sticky >= minVisibleToKeep) {
                    if (abs((ratios[id] ?: -1f) - sticky) > 0.02f) {
                        ratios[id] = sticky
                        scheduleRecompute()
                    }
                    return
                }
            }
            ratios.remove(id)
            stickyRatios.remove(id)
            zeroStreak.remove(id)
            scheduleRecompute()
            return
        }

        zeroStreak[id] = 0
        val prev = ratios[id]
        val crossedPlay =
            (prev == null || prev < minVisibleToPlay) && clamped >= minVisibleToPlay ||
                (prev != null && prev >= minVisibleToPlay && clamped < minVisibleToKeep)
        if (prev != null && !crossedPlay && abs(prev - clamped) < 0.03f) {
            stickyRatios[id] = clamped
            return
        }
        ratios[id] = clamped
        stickyRatios[id] = clamped
        scheduleRecompute()
    }

    /** Drop one feed card from the visibility map (iOS `FeedVideoFocus.clear`). */
    fun clear(id: String) {
        ratios.remove(id)
        stickyRatios.remove(id)
        zeroStreak.remove(id)
        scheduleRecompute()
    }

    /**
     * Drop every candidate (tab switch / push). Cards re-report when their surface is live.
     * Always hard-silences AV — even when the map was already empty.
     */
    fun resetAll() {
        clearElectionOnly()
        MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
    }

    /**
     * Clear the elected feed card without touching AV (continuous Hubs mini stays untouched).
     * Use on tab hops while hubs film is playing — `resetAll` was the hitch storm.
     */
    fun clearElectionOnly() {
        silenceWhenEmptyJob?.cancel()
        silenceWhenEmptyJob = null
        val previous = _activeId.value
        ratios.clear()
        stickyRatios.clear()
        zeroStreak.clear()
        if (previous != null) {
            _activeId.value = null
            _generation.value = _generation.value + 1
        } else {
            _activeId.value = null
        }
    }

    fun isActive(id: String): Boolean = _activeId.value == id

    private fun scheduleRecompute() {
        if (recomputeScheduled) return
        recomputeScheduled = true
        scope.launch {
            recomputeScheduled = false
            recompute()
        }
    }

    private fun recompute() {
        val previous = _activeId.value

        if (!autoplayUnlocked) {
            if (previous != null) {
                publish(winner = null, previous = previous, silenceImmediately = true)
            }
            return
        }

        val current = _activeId.value
        if (current != null) {
            val currentRatio = ratios[current]
            if (currentRatio != null && currentRatio >= minVisibleToKeep) {
                val best = bestCandidate(minVisibleToPlay)
                if (best != null &&
                    best.first != current &&
                    best.second >= currentRatio + stealEpsilon
                ) {
                    publish(winner = best.first, previous = previous)
                }
                return
            }
        }

        val best = bestCandidate(minVisibleToPlay)
        if (best != null) {
            publish(winner = best.first, previous = previous)
            return
        }
        publish(winner = null, previous = previous)
    }

    private fun bestCandidate(minRatio: Float): Pair<String, Float>? {
        val eligible = ratios.filter { it.value >= minRatio }
        if (eligible.isEmpty()) return null
        val winner = eligible.maxWithOrNull(
            compareBy<Map.Entry<String, Float>> { it.value }
                .thenBy { it.key },
        ) ?: return null
        return winner.key to winner.value
    }

    private fun publish(
        winner: String?,
        previous: String?,
        silenceImmediately: Boolean = false,
    ) {
        if (winner == previous) return
        _activeId.value = winner
        _generation.value = _generation.value + 1
        if (winner != null) {
            silenceWhenEmptyJob?.cancel()
            silenceWhenEmptyJob = null
        } else {
            silenceWhenEmptyJob?.cancel()
            if (silenceImmediately) {
                MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
            } else {
                silenceWhenEmptyJob = scope.launch {
                    delay(450)
                    if (_activeId.value == null) {
                        MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
                    }
                }
            }
        }
    }

    companion object {
        val shared: FeedVideoFocus by lazy { FeedVideoFocus() }
    }
}
