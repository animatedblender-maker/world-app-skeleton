package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import kotlinx.coroutines.launch

private val Capsule = RoundedCornerShape(percent = 50)

/**
 * Compact Follow / Following chip — 1:1 from iOS `FollowButton` (PeopleView.swift).
 */
@Composable
fun FollowButton(
    userId: String,
    isFollowing: Boolean,
    isSelf: Boolean,
    onToggle: suspend () -> Unit,
    compact: Boolean = false,
    onDark: Boolean = false,
    modifier: Modifier = Modifier,
) {
    if (isSelf || userId.isBlank()) return
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val bg = when {
        onDark && isFollowing -> Color.White.copy(alpha = 0.14f)
        onDark -> MatteryaColors.accentBright
        isFollowing -> MatteryaColors.surfaceMuted
        else -> MatteryaColors.accentBright
    }
    val fg = when {
        onDark -> Color.White
        isFollowing -> MatteryaColors.inkSecondary
        else -> Color.White
    }
    val border = when {
        onDark && isFollowing -> Color.White.copy(alpha = 0.45f)
        isFollowing -> MatteryaColors.border
        else -> Color.Transparent
    }

    Text(
        text = if (isFollowing) MatteryaCopy.following else MatteryaCopy.follow,
        color = fg,
        fontSize = if (compact) 11.sp else 12.sp,
        fontWeight = FontWeight.Bold,
        modifier = modifier
            .clip(Capsule)
            .background(bg, Capsule)
            .border(0.5.dp, border, Capsule)
            .clickable(enabled = !busy) {
                scope.launch {
                    busy = true
                    try {
                        onToggle()
                    } finally {
                        busy = false
                    }
                }
            }
            .padding(
                horizontal = if (compact) 10.dp else 14.dp,
                vertical = if (compact) 4.dp else 7.dp,
            ),
    )
}
