package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.MediaUploadPhase
import com.matterya.matterya.model.UploadProgress
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens

/** iOS `UploadProgressView` — phase label + determinate/indeterminate bar. */
@Composable
fun UploadProgressView(
    phase: MediaUploadPhase,
    progress: UploadProgress? = null,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(MatteryaDimens.controlRadius)
    Column(
        modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface, shape)
            .border(0.5.dp, MatteryaColors.border, shape)
            .padding(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                titleFor(phase, progress),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
            )
            Spacer(Modifier.weight(1f))
            if (progress != null && (phase == MediaUploadPhase.Uploading || phase == MediaUploadPhase.Compressing)) {
                Text(
                    progress.percentText,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = MatteryaColors.inkSecondary,
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        when (phase) {
            MediaUploadPhase.Uploading, MediaUploadPhase.Compressing -> {
                if (progress != null) {
                    LinearProgressIndicator(
                        progress = { progress.fractionCompleted.toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth(),
                        color = MatteryaColors.accentBright,
                        trackColor = MatteryaColors.canvasMuted,
                    )
                    if (phase == MediaUploadPhase.Uploading) {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            progress.bytesText,
                            fontSize = 11.sp,
                            color = MatteryaColors.inkMuted,
                        )
                    }
                } else {
                    LinearProgressIndicator(
                        modifier = Modifier.fillMaxWidth(),
                        color = MatteryaColors.accentBright,
                        trackColor = MatteryaColors.canvasMuted,
                    )
                }
            }
            MediaUploadPhase.Publishing -> {
                CircularProgressIndicator(
                    modifier = Modifier
                        .height(24.dp)
                        .padding(top = 2.dp),
                    color = MatteryaColors.accentBright,
                    strokeWidth = 2.dp,
                )
            }
            MediaUploadPhase.Idle -> Unit
        }
    }
}

private fun titleFor(phase: MediaUploadPhase, progress: UploadProgress?): String = when (phase) {
    MediaUploadPhase.Idle -> "Preparing…"
    MediaUploadPhase.Compressing -> "Compressing video"
    MediaUploadPhase.Uploading -> {
        if (progress != null && progress.totalBytes > 0 && progress.bytesSent >= progress.totalBytes) {
            "Finishing upload"
        } else {
            "Uploading video"
        }
    }
    MediaUploadPhase.Publishing -> "Publishing post"
}
