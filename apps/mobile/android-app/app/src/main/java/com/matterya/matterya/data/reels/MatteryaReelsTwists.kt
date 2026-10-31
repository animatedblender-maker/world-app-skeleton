package com.matterya.matterya.data.reels

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.MatteryaCopy

/** iOS `CountryFlag` / reels helpers from `MatteryaReelsTwists.swift`. */
object CountryFlag {
    fun emoji(forIso: String?): String {
        val iso = forIso?.uppercase() ?: return "🌍"
        if (iso.length != 2 || !iso.all { it.code in 0x41..0x5A }) return "🌍"
        val base = 0x1F1E6
        val first = Character.toChars(base + (iso[0].code - 'A'.code))
        val second = Character.toChars(base + (iso[1].code - 'A'.code))
        return String(first) + String(second)
    }
}

object MatteryaCountryBridge {
    fun country(from: CountryPost): Country? {
        val code = from.countryCode?.uppercase().orEmpty()
        if (code.isEmpty()) return null
        val name = from.countryName ?: code
        return Country(
            id = code,
            name = name,
            iso = code,
            continent = null,
            centerLat = null,
            centerLng = null,
        )
    }

    fun isHomeCountry(post: CountryPost, viewerCountryCode: String?): Boolean {
        val viewer = viewerCountryCode?.uppercase().orEmpty()
        val postCode = post.countryCode?.uppercase().orEmpty()
        if (viewer.isEmpty() || postCode.isEmpty()) return false
        return viewer == postCode
    }
}

data class ReelsWorldHopMoment(
    val countryCode: String,
    val countryName: String,
    val cityName: String?,
    val isHomeCountry: Boolean,
)

object ReelsTwistHaptics {
    /** No-op — country hop while scrolling must stay silent. */
    fun worldHop(@Suppress("UNUSED_PARAMETER") view: View? = null) {}

    fun globeShuffle(view: View?) {
        if (view == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        } else {
            @Suppress("DEPRECATION")
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        }
    }

    fun pullDismiss(@Suppress("UNUSED_PARAMETER") view: View? = null) {
        // Silent
    }
}

/**
 * Full-screen Sparks stage gravity — iOS `SparksStageLayout`.
 * Portrait/square → fill; landscape → fit unless crop is tiny.
 */
object SparksStageLayout {
    /** iOS `maxLandscapeCropFraction = 0.12`. */
    const val maxCropFraction = 0.12f

    fun shouldFillWithoutCrop(videoWidth: Float, videoHeight: Float, stageWidth: Float, stageHeight: Float): Boolean {
        if (videoWidth <= 2f || videoHeight <= 2f) return true
        if (stageWidth <= 2f || stageHeight <= 2f) return true
        if (videoHeight >= videoWidth * 0.92f) return true

        val scaleFit = minOf(stageWidth / videoWidth, stageHeight / videoHeight)
        val scaleFill = maxOf(stageWidth / videoWidth, stageHeight / videoHeight)
        if (scaleFill <= 0.0001f) return false
        val visibleFraction = scaleFit / scaleFill
        return visibleFraction >= (1 - maxCropFraction)
    }
}

/** Pull-down dismiss math — iOS `MatteryaPullDownDismiss`. */
object MatteryaPullDownDismiss {
    const val dismissDistance = 140f
    const val predictedDismissDistance = 180f
    const val chromeFadeDistance = 140f
    const val releaseSnapBackProgress = 0.06f
    const val releaseSnapBackTranslation = 14f

    fun shouldDismiss(translationY: Float, predictedY: Float): Boolean =
        translationY > dismissDistance || predictedY > predictedDismissDistance

    fun shouldMinimizeOnRelease(
        translationY: Float,
        predictedY: Float,
        dragOffset: Float = 0f,
        pullProgress: Float = 0f,
    ): Boolean {
        val progress = maxOf(pullProgress, pullProgressForVertical(translationY))
        val y = maxOf(0f, translationY)
        val nearTop = progress < releaseSnapBackProgress &&
            y < releaseSnapBackTranslation &&
            dragOffset < releaseSnapBackTranslation &&
            predictedY < 40f
        if (nearTop) return false
        return progress > 0.04f ||
            y > 10f ||
            dragOffset > 10f ||
            predictedY > 48f ||
            shouldDismiss(translationY, predictedY)
    }

    fun pullProgressForVertical(translationY: Float): Float {
        val y = maxOf(0f, translationY)
        return minOf(1f, y / chromeFadeDistance)
    }

    /** Alias — iOS uses both offset and vertical naming. */
    fun pullProgressForOffset(offset: Float): Float = pullProgressForVertical(offset)

    fun pullProgress(translationY: Float): Float = pullProgressForVertical(translationY)

    data class DragState(var offset: Float = 0f, var isDragging: Boolean = false)

    fun applyChanged(
        translationX: Float,
        translationY: Float,
        state: DragState,
    ) {
        val vertical = translationY
        val horizontal = kotlin.math.abs(translationX)
        if (state.isDragging) {
            if (vertical <= 0) {
                state.isDragging = false
                state.offset = 0f
                return
            }
            if (horizontal > vertical * 1.35f && vertical < 24f) {
                state.isDragging = false
                state.offset = 0f
                return
            }
            val y = maxOf(0f, vertical)
            state.offset = if (y > 280f) {
                val extra = y - 280f
                280f + extra * 0.35f
            } else {
                y
            }
            return
        }
        if (vertical > 12f && vertical > horizontal * 0.75f) {
            state.isDragging = true
            state.offset = vertical
        }
    }

    fun applyEnded(
        translationY: Float,
        predictedY: Float,
        state: DragState,
        dismiss: () -> Unit,
    ) {
        state.isDragging = false
        if (shouldDismiss(translationY, predictedY)) {
            ReelsTwistHaptics.pullDismiss()
            dismiss()
            return
        }
        state.offset = 0f
    }
}

data class ReelsPassport(
    private val visitedCodes: MutableList<String> = mutableListOf(),
) {
    fun visit(code: String?) {
        val c = code?.uppercase().orEmpty()
        if (c.isEmpty()) return
        if (c !in visitedCodes) visitedCodes.add(c)
    }

    val placeCount: Int get() = visitedCodes.size

    val label: String
        get() = when (placeCount) {
            0 -> MatteryaCopy.matteryaSparks
            1 -> "1 place"
            else -> "$placeCount places"
        }

    fun codes(): List<String> = visitedCodes.toList()
}

object ReelsLocationLabel {
    fun forPost(post: CountryPost?): String {
        if (post == null) return MatteryaCopy.matteryaSparks
        val name = post.countryName?.trim().orEmpty()
        if (name.isNotEmpty()) return name
        return post.countryCode?.uppercase() ?: MatteryaCopy.sparks
    }

    fun chipLabel(post: CountryPost): String {
        val name = post.countryName?.trim().orEmpty()
        if (name.isNotEmpty()) return name
        return post.countryCode?.uppercase() ?: "Explore"
    }
}
