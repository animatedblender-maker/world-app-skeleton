package com.matterya.matterya.theme

import com.matterya.matterya.model.CountryPost
import kotlin.math.max
import kotlin.math.min

enum class MediaContext { Feed, Reel }

/**
 * Mirrors iOS `FacebookMediaLayout.swift` **exactly** — feed media aspect ratios and heights.
 */
object FacebookMediaLayout {
    /** Facebook feed portrait photo (4:5). */
    const val photoPortraitAspect = 4f / 5f
    /** Facebook feed square photo (1:1). */
    const val photoSquareAspect = 1f
    /** Facebook feed landscape photo (1.91:1). */
    const val photoLandscapeAspect = 1.91f
    /** Facebook in-feed horizontal video (16:9). */
    const val feedVideoAspect = 16f / 9f
    /** Facebook Reels / Stories vertical video (9:16). */
    const val reelAspect = 9f / 16f
    /** Max height for in-feed photos — tall enough for 4:5 immersion on phones. */
    const val maxFeedMediaHeight = 520f
    /** Hard floor so LazyColumn never proposes infinite/zero media boxes. */
    const val minFeedMediaHeight = 160f

    /**
     * Facebook mobile feed: full-width, tall media (~4:5 immersion, not flat 16:9).
     * Pair with fillsFrame/Crop so the picture fills the box (no letterbox “tiny video”).
     * Line-by-line from iOS `dominantFeedVideoHeight`.
     */
    fun dominantFeedVideoHeight(widthPx: Float, screenHeightPx: Float): Float {
        val w = max(200f, if (widthPx.isFinite()) widthPx else 390f)
        val h = max(400f, if (screenHeightPx.isFinite()) screenHeightPx else 844f)
        val classic16x9 = w / feedVideoAspect
        // FB mobile feed reads closer to ~4:5 than flat 16:9.
        val fbLike = w / photoPortraitAspect
        val minDominant = min(h * 0.42f, maxFeedMediaHeight)
        val maxDominant = min(h * 0.62f, maxFeedMediaHeight + 20f)
        val preferred = max(classic16x9 * 1.15f, min(fbLike, maxDominant))
        val raw = min(max(preferred, minDominant), maxDominant)
        return min(max(raw, minFeedMediaHeight), maxFeedMediaHeight + 20f)
    }

    /** Clamp aspect ratios so bad metadata can't blow out the card. */
    fun clampedAspect(aspect: Float): Float {
        if (!aspect.isFinite() || aspect <= 0.05f) return photoPortraitAspect
        // 9:16 … 2.4:1
        return min(max(aspect, 0.45f), 2.4f)
    }

    /**
     * Spark share on feed — **same** Facebook tall media box as other video posts (iOS).
     * NOT full 9:16 (that made Sparks cards too tall on Android).
     */
    fun sparkFeedCardHeight(widthPx: Float, screenHeightPx: Float): Float =
        dominantFeedVideoHeight(widthPx, screenHeightPx)

    fun mediaHeight(
        widthPx: Float,
        screenHeightPx: Float,
        post: CountryPost,
        context: MediaContext = MediaContext.Feed,
    ): Float {
        if (post.hasVideo) {
            val isSpark = post.isSpark ||
                post.isSparkFeedShare ||
                post.isReel ||
                context == MediaContext.Reel
            if (isSpark) return sparkFeedCardHeight(widthPx, screenHeightPx)
            if (usesYouTubeFrame(post, context) || context == MediaContext.Feed) {
                return dominantFeedVideoHeight(widthPx, screenHeightPx)
            }
        }
        val aspect = aspectRatio(post, context) ?: photoPortraitAspect
        val natural = widthPx / aspect
        return min(natural, maxFeedMediaHeight)
    }

    fun usesYouTubeFrame(post: CountryPost, context: MediaContext = MediaContext.Feed): Boolean =
        post.hasVideo && !post.isReel && !post.isStory && context != MediaContext.Reel

    fun aspectRatio(post: CountryPost, context: MediaContext = MediaContext.Feed): Float? {
        if (post.hasVideo) {
            if (usesYouTubeFrame(post, context)) return feedVideoAspect
            if (post.isSpark || context == MediaContext.Reel) return reelAspect
            return feedVideoAspect
        }
        if (post.thumbUrl != null || post.mediaUrl != null || post.mediaPayload != null) {
            return photoPortraitAspect
        }
        return null
    }

    fun feedAspectForPost(post: CountryPost): Float {
        // Sparks still use tall FB feed box for height; aspect for photo math differs.
        if (post.isSpark || post.isSparkFeedShare || post.isReel) return reelAspect
        if (post.hasVideo) return feedVideoAspect
        return photoPortraitAspect
    }
}
