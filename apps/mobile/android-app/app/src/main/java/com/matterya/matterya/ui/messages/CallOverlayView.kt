package com.matterya.matterya.ui.messages

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.ui.components.AvatarView
import kotlin.math.roundToInt

enum class CallKind { Audio, Video }

/**
 * iOS `CallOverlayView` — full-screen call chrome (LiveKit video lands later).
 * Drag down to minimize when connected.
 */
@Composable
fun CallOverlayView(
    peerName: String,
    peerAvatarUrl: String? = null,
    callKind: CallKind = CallKind.Audio,
    statusLabel: String = "Connecting…",
    isMuted: Boolean = false,
    isCameraOff: Boolean = false,
    isConnecting: Boolean = true,
    isActive: Boolean = false,
    onToggleMute: () -> Unit = {},
    onToggleCamera: () -> Unit = {},
    onSwitchCamera: () -> Unit = {},
    onEnd: () -> Unit = {},
    onMinimize: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var dragOffset by remember { mutableFloatStateOf(0f) }
    val canDrag = isActive || isConnecting

    val bgModifier = if (callKind == CallKind.Video) {
        Modifier.background(Color.Black)
    } else {
        Modifier.background(
            Brush.verticalGradient(
                listOf(
                    Color(0.08f, 0.10f, 0.16f),
                    Color(0.03f, 0.04f, 0.08f),
                ),
            ),
        )
    }
    Box(
        modifier
            .fillMaxSize()
            .offset { IntOffset(0, dragOffset.roundToInt()) }
            .then(bgModifier)
            .then(
                if (canDrag) {
                    Modifier.pointerInput(Unit) {
                        detectVerticalDragGestures(
                            onVerticalDrag = { _, dragAmount ->
                                if (dragAmount > 0) dragOffset = (dragOffset + dragAmount).coerceAtLeast(0f)
                            },
                            onDragEnd = {
                                if (dragOffset > 110f) {
                                    dragOffset = 0f
                                    onMinimize()
                                } else {
                                    dragOffset = 0f
                                }
                            },
                        )
                    }
                } else {
                    Modifier
                },
            ),
    ) {
        if (callKind == CallKind.Audio || isCameraOff) {
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(top = 80.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                AvatarView(url = peerAvatarUrl, seed = peerName, size = 128.dp)
                Spacer(Modifier.height(24.dp))
                Text(peerName, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 24.sp)
                Spacer(Modifier.height(8.dp))
                Text(statusLabel, color = Color.White.copy(alpha = 0.75f), fontSize = 14.sp)
            }
        } else {
            // Video surface placeholder
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color(0.05f, 0.05f, 0.08f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    AvatarView(url = peerAvatarUrl, seed = peerName, size = 96.dp)
                    Spacer(Modifier.height(16.dp))
                    Text(statusLabel, color = Color.White.copy(alpha = 0.8f))
                }
            }
            // PiP self preview placeholder
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(16.dp)
                    .size(width = 100.dp, height = 140.dp)
                    .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(12.dp)),
            )
        }

        Column(Modifier.fillMaxSize()) {
            if (canDrag) {
                Box(
                    Modifier
                        .padding(top = 10.dp)
                        .align(Alignment.CenterHorizontally)
                        .width(42.dp)
                        .height(5.dp)
                        .background(Color.White.copy(alpha = 0.42f), RoundedCornerShape(50)),
                )
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text(peerName, color = Color.White, fontWeight = FontWeight.SemiBold)
                    Text(statusLabel, color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
                }
            }
            Spacer(Modifier.weight(1f))
            // Bottom chrome
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(bottom = 48.dp, start = 24.dp, end = 24.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CallCircleButton(
                    icon = if (isMuted) Icons.Default.MicOff else Icons.Default.Mic,
                    label = if (isMuted) "Unmute" else "Mute",
                    onClick = onToggleMute,
                )
                if (callKind == CallKind.Video) {
                    CallCircleButton(
                        icon = if (isCameraOff) Icons.Default.VideocamOff else Icons.Default.Videocam,
                        label = "Camera",
                        onClick = onToggleCamera,
                    )
                    CallCircleButton(
                        icon = Icons.Default.Cameraswitch,
                        label = "Flip",
                        onClick = onSwitchCamera,
                    )
                }
                IconButton(
                    onClick = onEnd,
                    modifier = Modifier
                        .size(68.dp)
                        .background(MatteryaColors.danger, CircleShape),
                ) {
                    Icon(Icons.Default.CallEnd, contentDescription = "End", tint = Color.White, modifier = Modifier.size(32.dp))
                }
            }
        }
    }
}

@Composable
private fun CallCircleButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        IconButton(
            onClick = onClick,
            modifier = Modifier
                .size(56.dp)
                .background(Color.White.copy(alpha = 0.15f), CircleShape),
        ) {
            Icon(icon, contentDescription = label, tint = Color.White)
        }
        Spacer(Modifier.height(6.dp))
        Text(label, color = Color.White.copy(alpha = 0.75f), fontSize = 11.sp)
    }
}
