package com.matterya.matterya.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.matterya.matterya.theme.MatteryaColors
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/** Multi-pass hand-drawn stroke — mirrors iOS `HandDrawnStroke`. */
object HandDrawnStroke {
    fun sketch(scope: DrawScope, path: Path, color: Color, width: Float = 1.1f) {
        val offsets = listOf(
            Offset.Zero,
            Offset(0.35f, 0.2f),
            Offset(-0.25f, 0.15f),
        )
        offsets.forEachIndexed { index, offset ->
            scope.translate(offset.x, offset.y) {
                drawPath(
                    path = path,
                    color = color.copy(alpha = if (index == 0) 0.88f else 0.18f),
                    style = Stroke(
                        width = width - index * 0.15f,
                        cap = StrokeCap.Round,
                        join = StrokeJoin.Round,
                    ),
                )
            }
        }
    }

    fun brushFill(scope: DrawScope, path: Path, color: Color) {
        val offsets = listOf(
            Offset.Zero,
            Offset(0.4f, -0.25f),
            Offset(-0.35f, 0.3f),
            Offset(0.2f, 0.35f),
        )
        offsets.forEachIndexed { index, offset ->
            scope.translate(offset.x, offset.y) {
                drawPath(
                    path = path,
                    color = color.copy(alpha = if (index == 0) 0.92f else 0.14f),
                )
            }
        }
    }
}

@Composable
fun HandDrawnPlusIcon(
    size: Dp = 28.dp,
    color: Color = MatteryaColors.ink,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier.size(size)) {
        val centerX = this.size.width / 2
        val centerY = this.size.height / 2
        val arm = size.toPx() * 0.36f

        val horizontal = Path().apply {
            moveTo(centerX - arm, centerY + 0.4f)
            lineTo(centerX + arm, centerY - 0.3f)
        }
        val vertical = Path().apply {
            moveTo(centerX - 0.3f, centerY - arm)
            lineTo(centerX + 0.5f, centerY + arm)
        }
        HandDrawnStroke.sketch(this, horizontal, color, 2.1f)
        HandDrawnStroke.sketch(this, vertical, color, 2.1f)
    }
}

@Composable
fun HandDrawnGlobeStoryRing(
    size: Dp = 62.dp,
    highlighted: Boolean = true,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier.size(size)) {
        val center = Offset(this.size.width / 2, this.size.height / 2)
        val radius = min(this.size.width, this.size.height) / 2 - 1.5f
        val ringColor = if (highlighted) MatteryaColors.accent else MatteryaColors.inkMuted
        val meridianColor = if (highlighted) MatteryaColors.oceanWash.copy(alpha = 0.95f) else MatteryaColors.border

        val ring = wobblyCircle(center, radius, 28, 0.9f)
        HandDrawnStroke.sketch(this, ring, ringColor, if (highlighted) 2.3f else 1.6f)

        if (highlighted) {
            val inner = wobblyCircle(center, radius - 2.8f, 24, 0.45f)
            HandDrawnStroke.sketch(this, inner, MatteryaColors.oceanWash.copy(alpha = 0.35f), 0.9f)
        }

        // Meridians approximated with cubic-ish arcs via quadratic points
        val left = Path().apply {
            val r = radius - 4
            moveTo(center.x + cos(-68 * Math.PI / 180).toFloat() * r, center.y + sin(-68 * Math.PI / 180).toFloat() * r)
            quadraticBezierTo(
                center.x - r * 0.35f,
                center.y,
                center.x + cos(68 * Math.PI / 180).toFloat() * r,
                center.y + sin(68 * Math.PI / 180).toFloat() * r,
            )
        }
        HandDrawnStroke.sketch(this, left, meridianColor, 1f)

        val right = Path().apply {
            val r = radius - 4
            moveTo(center.x + cos(112 * Math.PI / 180).toFloat() * r, center.y + sin(112 * Math.PI / 180).toFloat() * r)
            quadraticBezierTo(
                center.x + r * 0.35f,
                center.y,
                center.x + cos(248 * Math.PI / 180).toFloat() * r,
                center.y + sin(248 * Math.PI / 180).toFloat() * r,
            )
        }
        HandDrawnStroke.sketch(this, right, meridianColor, 1f)

        val equator = Path().apply {
            moveTo(center.x - radius + 3, center.y + 0.6f)
            quadraticBezierTo(center.x, center.y + 2.4f, center.x + radius - 3, center.y - 0.4f)
        }
        HandDrawnStroke.sketch(this, equator, meridianColor.copy(alpha = 0.85f), 0.9f)
    }
}

@Composable
fun HandDrawnBrushPlayButton(
    size: Dp = 88.dp,
    ink: Color = Color(red = 0.98f, green = 0.95f, blue = 0.86f),
    modifier: Modifier = Modifier,
) {
    Canvas(modifier.size(size)) {
        val center = Offset(this.size.width / 2, this.size.height / 2)
        val tri = brushPlayTriangle(center, min(this.size.width, this.size.height) * 0.92f)
        HandDrawnStroke.brushFill(this, tri, ink)
        HandDrawnStroke.sketch(this, tri, ink, maxOf(2.4f, size.toPx() * 0.048f))
        translate(0.6f, -0.4f) {
            HandDrawnStroke.sketch(this, tri, ink.copy(alpha = 0.35f), maxOf(1.6f, size.toPx() * 0.03f))
        }
    }
}

@Composable
fun MatteryaHubsLogoView(
    size: Dp = 28.dp,
    ink: Color = Color(red = 0.22f, green = 0.20f, blue = 0.18f),
    screenFill: Color = Color(red = 0.97f, green = 0.96f, blue = 0.93f),
    modifier: Modifier = Modifier,
) {
    Canvas(modifier.size(size)) {
        val w = this.size.width
        val h = this.size.height
        val screenRect = Rect(w * 0.08f, h * 0.06f, w * 0.92f, h * 0.68f)
        val screen = wobblyRoundedRect(screenRect, w * 0.12f, w * 0.02f)
        drawPath(screen, screenFill.copy(alpha = 0.95f))
        HandDrawnStroke.sketch(this, screen, ink, maxOf(1.6f, size.toPx() * 0.07f))

        val neck = Path().apply {
            val neckTopY = screenRect.bottom + h * 0.02f
            val neckBotY = h * 0.82f
            moveTo(w * 0.5f - w * 0.03f, neckTopY)
            lineTo(w * 0.5f - w * 0.04f, neckBotY)
            lineTo(w * 0.5f + w * 0.04f, neckBotY)
            lineTo(w * 0.5f + w * 0.03f, neckTopY)
            close()
        }
        HandDrawnStroke.brushFill(this, neck, ink.copy(alpha = 0.85f))
        HandDrawnStroke.sketch(this, neck, ink, maxOf(1.2f, size.toPx() * 0.045f))

        val baseY = h * 0.88f
        val base = Path().apply {
            moveTo(w * 0.22f, baseY)
            quadraticBezierTo(w * 0.5f, baseY + h * 0.06f, w * 0.78f, baseY + h * 0.02f)
            quadraticBezierTo(w * 0.5f, baseY - h * 0.02f, w * 0.22f, baseY)
        }
        HandDrawnStroke.sketch(this, base, ink, maxOf(1.8f, size.toPx() * 0.065f))
    }
}

private fun wobblyCircle(center: Offset, radius: Float, segments: Int, wobble: Float): Path {
    val path = Path()
    for (index in 0..segments) {
        val progress = index.toDouble() / segments
        val angle = progress * 2 * Math.PI
        val offset = (sin(angle * 4) * 0.55 + cos(angle * 6) * 0.35).toFloat() * wobble
        val point = Offset(
            center.x + cos(angle).toFloat() * (radius + offset),
            center.y + sin(angle).toFloat() * (radius + offset),
        )
        if (index == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
    }
    path.close()
    return path
}

private fun wobblyRoundedRect(rect: Rect, corner: Float, wobble: Float): Path {
    val r = min(corner, min(rect.width, rect.height) / 2)
    val inset = wobble
    return Path().apply {
        moveTo(rect.left + r, rect.top + inset * 0.3f)
        lineTo(rect.right - r, rect.top - inset * 0.2f)
        quadraticBezierTo(rect.right + inset, rect.top - inset * 0.3f, rect.right + inset * 0.2f, rect.top + r)
        lineTo(rect.right - inset * 0.15f, rect.bottom - r)
        quadraticBezierTo(rect.right + inset * 0.4f, rect.bottom + inset * 0.2f, rect.right - r, rect.bottom + inset * 0.25f)
        lineTo(rect.left + r, rect.bottom - inset * 0.1f)
        quadraticBezierTo(rect.left - inset * 0.5f, rect.bottom + inset * 0.15f, rect.left - inset * 0.2f, rect.bottom - r)
        lineTo(rect.left + inset * 0.1f, rect.top + r)
        quadraticBezierTo(rect.left - inset * 0.3f, rect.top - inset * 0.2f, rect.left + r, rect.top + inset * 0.3f)
        close()
    }
}

private fun brushPlayTriangle(center: Offset, size: Float): Path {
    val h = size * 0.88f
    val w = size * 0.78f
    val ox = size * 0.05f
    val tip = Offset(center.x + w * 0.50f + ox, center.y + 0.6f)
    val top = Offset(center.x - w * 0.46f + ox, center.y - h * 0.50f)
    val bot = Offset(center.x - w * 0.44f + ox, center.y + h * 0.52f)
    val midTop = Offset((tip.x + top.x) / 2 + size * 0.03f, (tip.y + top.y) / 2 - size * 0.025f)
    val midBot = Offset((tip.x + bot.x) / 2 - size * 0.02f, (tip.y + bot.y) / 2 + size * 0.03f)
    val midBack = Offset((top.x + bot.x) / 2 - size * 0.035f, (top.y + bot.y) / 2 + size * 0.01f)
    return Path().apply {
        moveTo(top.x, top.y)
        quadraticBezierTo(midTop.x, midTop.y, tip.x, tip.y)
        quadraticBezierTo(midBot.x, midBot.y, bot.x, bot.y)
        quadraticBezierTo(midBack.x, midBack.y, top.x, top.y)
        close()
    }
}
