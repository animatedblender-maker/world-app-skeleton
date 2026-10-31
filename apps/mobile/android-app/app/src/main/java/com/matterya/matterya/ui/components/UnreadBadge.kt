package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors

/** Mirrors iOS `UnreadBadge`. */
@Composable
fun UnreadBadge(
    count: Int,
    size: Dp = 18.dp,
    modifier: Modifier = Modifier,
) {
    if (count <= 0) return
    Box(
        modifier
            .size(size)
            .background(MatteryaColors.danger, CircleShape)
            .border(2.dp, MatteryaColors.surface, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = if (count > 9) "9+" else "$count",
            color = Color.White,
            fontSize = (size.value * 0.52f).sp,
            fontWeight = FontWeight.Bold,
        )
    }
}

/** Mirrors iOS `UnreadDot`. */
@Composable
fun UnreadDot(
    size: Dp = 9.dp,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier
            .size(size)
            .background(MatteryaColors.danger, CircleShape)
            .border(1.5.dp, MatteryaColors.surface, CircleShape),
    )
}
