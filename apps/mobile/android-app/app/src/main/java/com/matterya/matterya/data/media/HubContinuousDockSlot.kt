package com.matterya.matterya.data.media

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect

/**
 * iOS `HubContinuousVideoSlotKey` — window-space frame of the mini video hole
 * (chat dock or floating mini bar). [GlobalHubPlaybackLayer] morphs the continuous
 * ExoPlayer into this rect so expand/minimize never remounts.
 *
 * Clear is owner-scoped so floating-bar dispose does not wipe a chat hole that
 * already reported (AnimatedVisibility exit race).
 */
object HubContinuousDockSlot {
    /** Hole in window/root coordinates (px). Null when no hole is mounted. */
    var frameInWindow: Rect? by mutableStateOf(null)
        private set

    private var ownerToken: Any? = null

    fun report(owner: Any, frame: Rect?) {
        val next = frame?.takeIf { it.width > 8f && it.height > 8f }
        ownerToken = owner
        if (next == frameInWindow) return
        if (next != null && frameInWindow != null &&
            kotlin.math.abs(next.left - frameInWindow!!.left) < 0.5f &&
            kotlin.math.abs(next.top - frameInWindow!!.top) < 0.5f &&
            kotlin.math.abs(next.width - frameInWindow!!.width) < 0.5f &&
            kotlin.math.abs(next.height - frameInWindow!!.height) < 0.5f
        ) {
            return
        }
        frameInWindow = next
    }

    /** Clears only if [owner] still owns the slot. */
    fun clear(owner: Any) {
        if (ownerToken !== owner) return
        ownerToken = null
        if (frameInWindow != null) frameInWindow = null
    }
}
