package com.matterya.matterya.ui.components

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.MediaUploadPhase
import com.matterya.matterya.model.UploadProgress
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import kotlinx.coroutines.launch

/**
 * iOS `ReelComposerView` — spark / feed video / hub channel long-form.
 */
@Composable
fun ReelComposerView(
    country: Country,
    publishAsReel: Boolean = true,
    publishToHubChannel: Boolean = false,
    canPostHere: Boolean = true,
    onCancel: () -> Unit = {},
    onPublish: suspend (
        caption: String,
        videoTitle: String,
        videoUri: Uri,
        onPhase: (MediaUploadPhase) -> Unit,
        onProgress: (UploadProgress) -> Unit,
    ) -> CountryPost? = { _, _, _, _, _ -> null },
    onPosted: (CountryPost) -> Unit = {},
) {
    var caption by remember { mutableStateOf("") }
    var videoTitle by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var uploadPhase by remember { mutableStateOf(MediaUploadPhase.Idle) }
    var uploadProgress by remember { mutableStateOf<UploadProgress?>(null) }
    var isPreparingVideo by remember { mutableStateOf(false) }
    var compressionProgress by remember { mutableFloatStateOf(0f) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var videoUri by remember { mutableStateOf<Uri?>(null) }
    val scope = rememberCoroutineScope()

    val titleOK = when {
        publishAsReel -> true
        !publishToHubChannel -> true
        else -> videoTitle.trim().isNotEmpty()
    }
    val canSubmit = videoUri != null && !isPreparingVideo && titleOK

    val navTitle = when {
        publishAsReel -> MatteryaCopy.newSpark
        publishToHubChannel -> "New channel video"
        else -> "New feed video"
    }
    val destinationHeadline = when {
        publishAsReel -> "Publishing a ${MatteryaCopy.spark}"
        publishToHubChannel -> "Publishing to your channel"
        else -> "Publishing a feed video"
    }
    val destinationHint = when {
        publishAsReel -> MatteryaCopy.publishSparkHint
        publishToHubChannel -> MatteryaCopy.longFormOnHubs
        else -> MatteryaCopy.publishVideoHint
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        videoUri = uri
        isPreparingVideo = false
        compressionProgress = 0f
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface.copy(alpha = 0.94f))
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onCancel) {
                Text("Cancel", color = MatteryaColors.inkSecondary)
            }
            Spacer(Modifier.weight(1f))
            Text(navTitle, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.width(72.dp))
        }

        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            // Header
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
                    .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
                    .padding(18.dp),
            ) {
                Box(
                    Modifier
                        .size(48.dp)
                        .background(MatteryaColors.accentSoft, RoundedCornerShape(12.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (publishAsReel) Icons.Default.Movie else Icons.Default.VideoLibrary,
                        contentDescription = null,
                        tint = MatteryaColors.accentBright,
                    )
                }
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(destinationHeadline, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        when {
                            isPreparingVideo -> "Compressing video · ${(compressionProgress * 100).toInt()}%"
                            videoUri != null -> "Video ready"
                            else -> destinationHint
                        },
                        fontSize = 12.sp,
                        color = MatteryaColors.inkMuted,
                    )
                }
            }

            // Preview
            Column {
                Text(
                    "VIDEO",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.inkMuted,
                    letterSpacing = 1.2.sp,
                )
                Spacer(Modifier.height(12.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(if (publishAsReel) 420.dp else 280.dp)
                        .background(MatteryaColors.canvasMuted, RoundedCornerShape(MatteryaDimens.cardRadius))
                        .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
                        .clickable { picker.launch("video/*") },
                    contentAlignment = Alignment.Center,
                ) {
                    when {
                        isPreparingVideo -> {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                if (compressionProgress > 0f) {
                                    LinearProgressIndicator(
                                        progress = { compressionProgress },
                                        modifier = Modifier.width(220.dp),
                                        color = MatteryaColors.accentBright,
                                    )
                                } else {
                                    CircularProgressIndicator(color = MatteryaColors.accentBright)
                                }
                                Spacer(Modifier.height(10.dp))
                                Text(
                                    if (compressionProgress > 0f) {
                                        "Compressing video · ${(compressionProgress * 100).toInt()}%"
                                    } else {
                                        "Preparing video…"
                                    },
                                    fontWeight = FontWeight.SemiBold,
                                    color = MatteryaColors.inkSecondary,
                                )
                            }
                        }
                        videoUri != null -> {
                            VideoPlayerView(
                                url = videoUri.toString(),
                                adsEnabled = false,
                                isActive = true,
                                loops = true,
                                showsControls = true,
                                fillsFrame = true,
                                modifier = Modifier
                                    .fillMaxSize()
                                    .clip(RoundedCornerShape(MatteryaDimens.cardRadius)),
                            )
                        }
                        else -> {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(
                                    Icons.Default.VideoLibrary,
                                    contentDescription = null,
                                    tint = MatteryaColors.accentBright,
                                    modifier = Modifier.size(42.dp),
                                )
                                Spacer(Modifier.height(14.dp))
                                Text("Choose one video", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                            }
                        }
                    }
                }
            }

            if (publishToHubChannel && !publishAsReel) {
                Column {
                    Text(
                        "TITLE",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.inkMuted,
                        letterSpacing = 1.2.sp,
                    )
                    Spacer(Modifier.height(8.dp))
                    TextField(
                        value = videoTitle,
                        onValueChange = { videoTitle = it },
                        placeholder = { Text("Video title", color = MatteryaColors.inkMuted) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MatteryaColors.surface,
                            unfocusedContainerColor = MatteryaColors.surface,
                            focusedIndicatorColor = MatteryaColors.border,
                            unfocusedIndicatorColor = MatteryaColors.border,
                        ),
                    )
                }
            }

            Column {
                Text(
                    "CAPTION",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.inkMuted,
                    letterSpacing = 1.2.sp,
                )
                Spacer(Modifier.height(8.dp))
                TextField(
                    value = caption,
                    onValueChange = { caption = it },
                    placeholder = { Text("Add a caption (optional)", color = MatteryaColors.inkMuted) },
                    modifier = Modifier.fillMaxWidth(),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = MatteryaColors.surface,
                        unfocusedContainerColor = MatteryaColors.surface,
                        focusedIndicatorColor = MatteryaColors.border,
                        unfocusedIndicatorColor = MatteryaColors.border,
                    ),
                )
            }

            if (uploadPhase != MediaUploadPhase.Idle) {
                UploadProgressView(phase = uploadPhase, progress = uploadProgress)
            }

            errorMessage?.let {
                Text(
                    it,
                    color = MatteryaColors.danger,
                    fontSize = 12.sp,
                    modifier = Modifier
                        .background(MatteryaColors.danger.copy(alpha = 0.08f), RoundedCornerShape(8.dp))
                        .padding(14.dp)
                        .fillMaxWidth(),
                )
            }
        }

        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
        Row(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface.copy(alpha = 0.96f))
                .padding(horizontal = MatteryaDimens.pagePadding, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    if (canPostHere) "Ready to publish" else "Set your home country",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (canPostHere) MatteryaColors.ink else MatteryaColors.danger,
                )
                Text(
                    if (publishAsReel) MatteryaCopy.publishSpark else MatteryaCopy.publishVideo,
                    fontSize = 11.sp,
                    color = MatteryaColors.inkMuted,
                )
            }
            val enabled = canSubmit && !busy && canPostHere
            TextButton(
                onClick = {
                    val uri = videoUri ?: return@TextButton
                    if (!canPostHere) {
                        errorMessage = MatteryaCopy.homeCountryOnlyPost
                        return@TextButton
                    }
                    scope.launch {
                        busy = true
                        errorMessage = null
                        try {
                            val post = onPublish(
                                caption.trim(),
                                videoTitle.trim(),
                                uri,
                                { uploadPhase = it },
                                { uploadProgress = it },
                            )
                            if (post != null) onPosted(post)
                        } catch (e: Exception) {
                            errorMessage = e.message ?: "Publish failed"
                        } finally {
                            busy = false
                            uploadPhase = MediaUploadPhase.Idle
                        }
                    }
                },
                enabled = enabled,
                modifier = Modifier
                    .background(
                        if (enabled) MatteryaColors.accentBright else MatteryaColors.inkMuted,
                        RoundedCornerShape(50),
                    ),
            ) {
                if (busy) {
                    CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    if (busy) "Publishing…" else if (publishAsReel) MatteryaCopy.publishSpark else MatteryaCopy.publishVideo,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}
