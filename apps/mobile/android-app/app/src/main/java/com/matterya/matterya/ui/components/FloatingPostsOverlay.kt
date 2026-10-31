package com.matterya.matterya.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.theme.MatteryaColors
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** iOS `FloatingPostsOverlay` — non-interactive floating caption chips. */
@Composable
fun FloatingPostsOverlay(
    posts: List<CountryPost>,
    modifier: Modifier = Modifier,
) {
    if (posts.isEmpty()) return
    val capsule = RoundedCornerShape(50)
    BoxWithConstraints(modifier.fillMaxSize()) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        posts.forEachIndexed { index, post ->
            val seed = (index + 1).toDouble()
            val baseX = w * (0.15f + 0.7f * (sin(seed) * 0.5 + 0.5).toFloat())
            val baseY = h * (0.2f + 0.55f * (cos(seed * 1.7) * 0.5 + 0.5).toFloat())
            val transition = rememberInfiniteTransition(label = "float-$index")
            val drift by transition.animateFloat(
                initialValue = -6f,
                targetValue = 6f,
                animationSpec = infiniteRepeatable(
                    animation = tween((4000 + index * 400).coerceAtMost(8000), easing = LinearEasing),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "drift-$index",
            )
            val text = remember(post.id) { shortText(post) }
            Box(
                Modifier
                    .offset {
                        IntOffset(
                            (baseX + drift).roundToInt(),
                            (baseY + drift * 0.6f).roundToInt(),
                        )
                    }
                    .background(MatteryaColors.surface.copy(alpha = 0.92f), capsule)
                    .border(0.5.dp, MatteryaColors.border, capsule)
                    .padding(horizontal = 10.dp, vertical = 6.dp),
            ) {
                Text(
                    text,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.accentBright,
                )
            }
        }
    }
}

private fun shortText(post: CountryPost): String {
    val text = post.displayCaption
        ?: post.displayHeadline
        ?: post.authorDisplayName
    return text.take(28)
}
