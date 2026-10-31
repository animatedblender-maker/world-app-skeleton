package com.matterya.matterya.theme

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min

/**
 * iOS `YouTubeMediaLayout` — Hubs stage geometry (16:9 continuous player).
 */
object YouTubeMediaLayout {
    const val aspect: Float = 16f / 9f

    /** Space reserved under the continuous player for title + channel. */
    val hubsWatchMetaReserve: Dp = 100.dp

    /** Single max-pixel size for Hubs list thumbs. */
    const val hubsListThumbMaxPixel: Int = 320

    /** Gap between video bottom and title. */
    val hubsTitleGapBelowVideo: Dp = 18.dp

    fun hubsContinuousStageHeight(containerWidthPx: Float, contentColumnHeightPx: Float): Float {
        val w = max(1f, containerWidthPx)
        val classic16x9 = w / aspect
        val contentH = max(320f, contentColumnHeightPx)
        val preferred = max(classic16x9, contentH * 0.34f)
        val maxH = max(classic16x9, contentH - hubsWatchMetaReserve.value * 3f)
        return min(preferred, maxH)
    }

    fun hubsExpandedStageHeight(containerWidthPx: Float, contentColumnHeightPx: Float): Float =
        hubsContinuousStageHeight(containerWidthPx, contentColumnHeightPx)

    fun watchPlayerHeight(
        containerWidthPx: Float,
        containerHeightPx: Float,
        contentColumnHeightPx: Float = containerHeightPx,
    ): Float {
        val w = max(1f, containerWidthPx)
        val classic16x9 = w / aspect
        if (containerHeightPx > 200f) {
            val preferred = max(classic16x9, containerHeightPx * 0.34f)
            val maxH = max(classic16x9, containerHeightPx - hubsWatchMetaReserve.value * 3f)
            return min(preferred, maxH)
        }
        return hubsContinuousStageHeight(w, contentColumnHeightPx)
    }
}

enum class MatteryaPlayerFrameStyle {
    /** Rounded card with border — home, library, related. */
    Card,
    /** Flush to top edge — in-feed long-form video. */
    Feed,
    /** Watch screen — pure stage. */
    Watch,
}
