package com.matterya.matterya.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.matterya.matterya.data.media.MediaUrlResolver
import com.matterya.matterya.theme.MatteryaColors
import kotlin.math.hypot
import kotlin.math.min

/** iOS `HandDrawnPictureFrame` path — soft irregular rounded rect. */
fun handDrawnPicturePath(rect: Rect, seed: String): Path {
    val inset = min(rect.width, rect.height) * 0.04f
    val r = Rect(
        rect.left + inset,
        rect.top + inset,
        rect.right - inset,
        rect.bottom - inset,
    )
    val wobble = seedWobble(seed)
    val corners = listOf(
        Offset(r.left + wobble[0], r.top + wobble[1]),
        Offset(r.right + wobble[2], r.top + wobble[3]),
        Offset(r.right + wobble[4], r.bottom + wobble[5]),
        Offset(r.left + wobble[6], r.bottom + wobble[7]),
    )
    val radius = min(r.width, r.height) * 0.16f
    val path = Path()
    for (i in 0 until 4) {
        val curr = corners[i]
        val next = corners[(i + 1) % 4]
        val prev = corners[(i + 3) % 4]
        val toPrev = Offset(prev.x - curr.x, prev.y - curr.y)
        val toNext = Offset(next.x - curr.x, next.y - curr.y)
        val lenPrev = hypot(toPrev.x.toDouble(), toPrev.y.toDouble()).toFloat().coerceAtLeast(0.001f)
        val lenNext = hypot(toNext.x.toDouble(), toNext.y.toDouble()).toFloat().coerceAtLeast(0.001f)
        val start = Offset(
            curr.x + toPrev.x / lenPrev * radius,
            curr.y + toPrev.y / lenPrev * radius,
        )
        val end = Offset(
            curr.x + toNext.x / lenNext * radius,
            curr.y + toNext.y / lenNext * radius,
        )
        if (i == 0) path.moveTo(start.x, start.y) else path.lineTo(start.x, start.y)
        path.quadraticBezierTo(curr.x, curr.y, end.x, end.y)
    }
    path.close()
    return path
}

private fun seedWobble(seed: String): FloatArray {
    var h = 2166136261u
    for (b in seed.toByteArray()) {
        h = h xor b.toUInt()
        h *= 16777619u
    }
    val values = FloatArray(8)
    var x = h.toLong()
    for (i in 0 until 8) {
        x = x * 6364136223846793005L + 1
        val unit = ((x % 1000).toFloat() / 1000f)
        values[i] = (unit - 0.5f) * 1.8f
    }
    return values
}

fun frameAccent(seed: String): Color {
    var hash = 0
    for (u in seed) hash = hash * 31 + u.code
    val hues = listOf(
        MatteryaColors.ink.copy(alpha = 0.55f),
        MatteryaColors.accent.copy(alpha = 0.75f),
        Color(0xFF73614F),
        Color(0xFF526B66),
    )
    return hues[kotlin.math.abs(hash) % hues.size]
}

class HandDrawnPictureShape(private val seed: String) : Shape {
    override fun createOutline(
        size: Size,
        layoutDirection: androidx.compose.ui.unit.LayoutDirection,
        density: androidx.compose.ui.unit.Density,
    ): Outline {
        val path = handDrawnPicturePath(Rect(0f, 0f, size.width, size.height), seed)
        return Outline.Generic(path)
    }
}

/** iOS `AvatarView` — hand-drawn scrapbook frame around avatar. */
@Composable
fun AvatarView(
    url: String?,
    seed: String,
    size: Dp = 36.dp,
    modifier: Modifier = Modifier,
) {
    val resolved = MediaUrlResolver.normalizedAvatarUrl(url)
    val accent = frameAccent(seed)
    Box(
        modifier = modifier
            .size(size)
            .shadow(2.dp, HandDrawnPictureShape(seed), clip = false),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val path = handDrawnPicturePath(Rect(0f, 0f, this.size.width, this.size.height), seed)
            drawPath(path, MatteryaColors.paper)
            drawPath(
                path,
                color = accent,
                style = Stroke(width = (size.toPx() * 0.055f).coerceAtLeast(1.2f)),
            )
            val inset = size.toPx() * 0.055f
            val inner = handDrawnPicturePath(
                Rect(inset, inset, this.size.width - inset, this.size.height - inset),
                "$seed-rim",
            )
            drawPath(
                inner,
                color = accent.copy(alpha = 0.45f),
                style = Stroke(width = (size.toPx() * 0.028f).coerceAtLeast(0.7f)),
            )
        }
        Box(
            Modifier
                .size(size * 0.78f)
                .clip(HandDrawnPictureShape("$seed-inner")),
            contentAlignment = Alignment.Center,
        ) {
            if (resolved != null) {
                AsyncImage(
                    model = ImageRequest.Builder(LocalContext.current)
                        .data(resolved)
                        .crossfade(true)
                        .size((size.value * 3).toInt().coerceIn(64, 256))
                        .build(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(MatteryaColors.canvasMuted),
                    contentAlignment = Alignment.Center,
                ) {
                    val letter = seed.removePrefix("user_").firstOrNull()?.uppercaseChar() ?: '?'
                    Text(
                        text = letter.toString(),
                        color = MatteryaColors.inkSecondary,
                        fontFamily = FontFamily.Serif,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = (size.value * 0.30f).sp,
                    )
                }
            }
        }
    }
}

/** Scrapbook frame around feed / shelf media. */
@Composable
fun HandDrawnMediaFrame(
    seed: String,
    modifier: Modifier = Modifier,
    padding: Dp = 5.dp,
    content: @Composable () -> Unit,
) {
    val accent = frameAccent(seed)
    Box(modifier) {
        Canvas(Modifier.fillMaxSize()) {
            val path = handDrawnPicturePath(
                Rect(1f, 1f, size.width - 1f, size.height - 1f),
                seed,
            )
            drawPath(path, MatteryaColors.paper)
            drawPath(path, color = accent, style = Stroke(width = 1.6f))
            val inset = 3.5f
            val inner = handDrawnPicturePath(
                Rect(inset, inset, size.width - inset, size.height - inset),
                "$seed-rim",
            )
            drawPath(inner, color = accent.copy(alpha = 0.4f), style = Stroke(width = 0.8f))
        }
        Box(
            Modifier
                .padding(padding)
                .clip(HandDrawnPictureShape("$seed-media"))
                .fillMaxSize(),
        ) {
            content()
        }
    }
}
