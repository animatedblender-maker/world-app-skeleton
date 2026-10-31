package com.matterya.matterya.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.matterya.matterya.theme.MatteryaColors

/**
 * iOS `MatteryaVerifiedBadge` — scalloped bronze seal + white check.
 * Design space is 24×24 (same path as iOS / Angular SVG).
 */
@Composable
fun MatteryaVerifiedBadge(
    size: Dp = 20.dp,
    color: Color = MatteryaColors.verifiedMark,
    modifier: Modifier = Modifier,
) {
    Canvas(
        modifier
            .size(size)
            .semantics { contentDescription = "Verified account" },
    ) {
        val s = minOf(this.size.width, this.size.height) / 24f
        val ox = this.size.width / 2f - 12f * s
        val oy = this.size.height / 2f - 12f * s
        fun p(x: Float, y: Float) = Offset(ox + x * s, oy + y * s)

        val scallop = Path().apply {
            moveTo(p(12f, 1.5f).x, p(12f, 1.5f).y)
            lineTo(p(14.8f, 3.1f).x, p(14.8f, 3.1f).y)
            lineTo(p(18f, 3.4f).x, p(18f, 3.4f).y)
            lineTo(p(19f, 6.5f).x, p(19f, 6.5f).y)
            lineTo(p(21.7f, 8.3f).x, p(21.7f, 8.3f).y)
            lineTo(p(21f, 11.5f).x, p(21f, 11.5f).y)
            lineTo(p(21.7f, 14.7f).x, p(21.7f, 14.7f).y)
            lineTo(p(19f, 16.5f).x, p(19f, 16.5f).y)
            lineTo(p(18f, 19.6f).x, p(18f, 19.6f).y)
            lineTo(p(14.8f, 19.9f).x, p(14.8f, 19.9f).y)
            lineTo(p(12f, 22.5f).x, p(12f, 22.5f).y)
            lineTo(p(9.2f, 20.9f).x, p(9.2f, 20.9f).y)
            lineTo(p(6f, 20.6f).x, p(6f, 20.6f).y)
            lineTo(p(5f, 17.5f).x, p(5f, 17.5f).y)
            lineTo(p(2.3f, 15.7f).x, p(2.3f, 15.7f).y)
            lineTo(p(3f, 12.5f).x, p(3f, 12.5f).y)
            lineTo(p(2.3f, 9.3f).x, p(2.3f, 9.3f).y)
            lineTo(p(5f, 6.5f).x, p(5f, 6.5f).y)
            lineTo(p(6f, 3.4f).x, p(6f, 3.4f).y)
            lineTo(p(9.2f, 3.1f).x, p(9.2f, 3.1f).y)
            close()
        }
        drawPath(scallop, color)

        val check = Path().apply {
            moveTo(p(7.3f, 12.1f).x, p(7.3f, 12.1f).y)
            lineTo(p(10.4f, 15.1f).x, p(10.4f, 15.1f).y)
            lineTo(p(16.8f, 8.5f).x, p(16.8f, 8.5f).y)
        }
        drawPath(
            check,
            Color.White,
            style = Stroke(
                width = size.toPx() * (2.6f / 24f),
                cap = StrokeCap.Round,
                join = StrokeJoin.Round,
            ),
        )
    }
}
