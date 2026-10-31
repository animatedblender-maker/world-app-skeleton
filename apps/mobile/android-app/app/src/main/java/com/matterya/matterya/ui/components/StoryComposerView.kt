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
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.MediaUploadPhase
import com.matterya.matterya.model.UploadProgress
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens
import kotlinx.coroutines.launch

/** iOS `StoryComposerView` — Globe moments (24h). */
@Composable
fun StoryComposerView(
    country: Country,
    canPostHere: Boolean = true,
    onCancel: () -> Unit = {},
    onPublish: suspend (
        caption: String,
        mediaUri: Uri,
        isVideo: Boolean,
        onPhase: (MediaUploadPhase) -> Unit,
        onProgress: (UploadProgress) -> Unit,
    ) -> CountryPost? = { _, _, _, _, _ -> null },
    onPosted: (CountryPost) -> Unit = {},
) {
    var caption by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var uploadPhase by remember { mutableStateOf(MediaUploadPhase.Idle) }
    var uploadProgress by remember { mutableStateOf<UploadProgress?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var mediaUri by remember { mutableStateOf<Uri?>(null) }
    var isVideo by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val canSubmit = mediaUri != null

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            mediaUri = uri
            isVideo = false
        }
    }
    val videoPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            mediaUri = uri
            isVideo = true
        }
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
            Text("New moment", fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
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
                    Icon(Icons.Default.Image, null, tint = MatteryaColors.accentBright)
                }
                Spacer(Modifier.width(14.dp))
                Column {
                    Text("Sharing to Globe moments", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "Visible in the moments strip — not your feed. Disappears after 24 hours.",
                        fontSize = 12.sp,
                        color = MatteryaColors.inkMuted,
                    )
                }
            }

            Column {
                Text("MEDIA", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MatteryaColors.inkMuted, letterSpacing = 1.2.sp)
                Spacer(Modifier.height(12.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(240.dp)
                        .background(MatteryaColors.canvasMuted, RoundedCornerShape(MatteryaDimens.cardRadius))
                        .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius)),
                    contentAlignment = Alignment.Center,
                ) {
                    when {
                        mediaUri != null && isVideo -> {
                            VideoPlayerView(
                                url = mediaUri.toString(),
                                adsEnabled = false,
                                isActive = true,
                                loops = true,
                                showsControls = true,
                                modifier = Modifier
                                    .fillMaxSize()
                                    .clip(RoundedCornerShape(MatteryaDimens.cardRadius)),
                            )
                        }
                        mediaUri != null -> {
                            AsyncImage(
                                model = mediaUri,
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .fillMaxSize()
                                    .clip(RoundedCornerShape(MatteryaDimens.cardRadius)),
                            )
                        }
                        else -> {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(Icons.Default.Image, null, tint = MatteryaColors.accentBright, modifier = Modifier.size(40.dp))
                                Spacer(Modifier.height(18.dp))
                                Text("Pick a photo or video", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                            }
                        }
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MediaPickChip("Photo", Icons.Default.Image) { imagePicker.launch("image/*") }
                MediaPickChip("Video", Icons.Default.VideoLibrary) { videoPicker.launch("video/*") }
            }

            Column {
                Text("TEXT", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MatteryaColors.inkMuted, letterSpacing = 1.2.sp)
                Spacer(Modifier.height(8.dp))
                TextField(
                    value = caption,
                    onValueChange = { caption = it },
                    placeholder = { Text("Add text (optional)", color = MatteryaColors.inkMuted) },
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
                    if (canPostHere) "Ready to share" else "Set your home country",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (canPostHere) MatteryaColors.ink else MatteryaColors.danger,
                )
                Text("Moments disappear after 24 hours", fontSize = 11.sp, color = MatteryaColors.inkMuted)
            }
            val enabled = canSubmit && !busy && canPostHere
            TextButton(
                onClick = {
                    val uri = mediaUri ?: return@TextButton
                    scope.launch {
                        busy = true
                        errorMessage = null
                        try {
                            val post = onPublish(
                                caption.trim(),
                                uri,
                                isVideo,
                                { uploadPhase = it },
                                { uploadProgress = it },
                            )
                            if (post != null) onPosted(post)
                        } catch (e: Exception) {
                            errorMessage = e.message ?: "Failed"
                        } finally {
                            busy = false
                            uploadPhase = MediaUploadPhase.Idle
                        }
                    }
                },
                enabled = enabled,
                modifier = Modifier.background(
                    if (enabled) MatteryaColors.accentBright else MatteryaColors.inkMuted,
                    RoundedCornerShape(50),
                ),
            ) {
                if (busy) {
                    CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(if (busy) "Sharing…" else "Share moment", color = Color.White, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun MediaPickChip(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .clickable(onClick = onClick)
            .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.controlRadius))
            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.controlRadius))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = MatteryaColors.accentBright, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(label, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink, fontSize = 13.sp)
    }
}
