package com.matterya.matterya.ui.feed

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens

data class FeedUploadPlaceholder(
    val id: String,
    val caption: String = "",
    val progress: Float = 0f,
    val isHub: Boolean = false,
    val isSpark: Boolean = false,
    val failedMessage: String? = null,
) {
    val progressText: String
        get() = failedMessage
            ?: if (progress >= 1f) "Processing…"
            else "Uploading ${((progress * 100).toInt()).coerceIn(0, 99)}%"
}

/** Animated shadow of a post card while a video is uploading — iOS `FeedUploadingShadowCard`. */
@Composable
fun FeedUploadingShadowCard(
    draft: FeedUploadPlaceholder,
    modifier: Modifier = Modifier,
) {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val phase by transition.animateFloat(
        initialValue = -1f,
        targetValue = 1.2f,
        animationSpec = infiniteRepeatable(
            animation = tween(1350, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "phase",
    )

    Column(
        modifier
            .fillMaxWidth()
            .background(MatteryaColors.canvas)
            .padding(bottom = 10.dp),
    ) {
        Row(
            Modifier.padding(
                start = MatteryaDimens.feedGutter,
                end = MatteryaDimens.feedGutter,
                top = 16.dp,
                bottom = 12.dp,
            ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ShimmerBox(Modifier.size(36.dp), CircleShape, phase)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                ShimmerBox(Modifier.width(108.dp).height(12.dp), RoundedCornerShape(3.dp), phase)
                Spacer(Modifier.height(6.dp))
                ShimmerBox(Modifier.width(64.dp).height(9.dp), RoundedCornerShape(3.dp), phase)
            }
            if (draft.isHub) {
                Text(
                    "Hubs",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = MatteryaColors.accentBright.copy(alpha = 0.85f),
                    modifier = Modifier
                        .background(MatteryaColors.accentSoft, RoundedCornerShape(50))
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }
        }

        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(if (draft.isSpark) 4f / 5f else 16f / 9f)
                .background(MatteryaColors.canvasMuted),
        ) {
            ShimmerOverlay(phase)
        }

        if (draft.caption.isNotBlank()) {
            Text(
                draft.caption,
                color = MatteryaColors.inkSecondary.copy(alpha = 0.85f),
                fontSize = 15.sp,
                maxLines = 3,
                modifier = Modifier.padding(
                    horizontal = MatteryaDimens.feedGutter,
                    vertical = 12.dp,
                ),
            )
        }

        Column(Modifier.padding(horizontal = MatteryaDimens.feedGutter, vertical = 10.dp)) {
            if (draft.failedMessage != null) {
                Text(draft.failedMessage, color = MatteryaColors.danger, fontSize = 13.sp)
            } else {
                LinearProgressIndicator(
                    progress = { draft.progress.coerceIn(0f, 1f) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp)),
                    color = MatteryaColors.accent,
                    trackColor = MatteryaColors.canvasMuted,
                )
                Spacer(Modifier.height(6.dp))
                Text(draft.progressText, fontSize = 12.sp, color = MatteryaColors.inkMuted)
            }
        }
        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
    }
}

@Composable
private fun ShimmerBox(
    modifier: Modifier,
    shape: androidx.compose.ui.graphics.Shape,
    phase: Float,
) {
    Box(
        modifier
            .clip(shape)
            .background(MatteryaColors.canvasMuted),
    ) {
        ShimmerOverlay(phase)
    }
}

@Composable
private fun ShimmerOverlay(phase: Float) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(200.dp)
            .background(
                Brush.horizontalGradient(
                    colors = listOf(
                        Color.Transparent,
                        Color.White.copy(alpha = 0.35f),
                        Color.Transparent,
                    ),
                    startX = phase * 600f,
                    endX = phase * 600f + 200f,
                ),
            ),
    )
}
