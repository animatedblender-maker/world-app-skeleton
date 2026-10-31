package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors

enum class ToastStyle {
    Info, Success, Error;

    val background: Color
        get() = when (this) {
            Info -> MatteryaColors.ink
            Success -> MatteryaColors.accent
            Error -> MatteryaColors.danger
        }
}

/** Mirrors iOS `ToastBanner`. */
@Composable
fun ToastBanner(
    message: String,
    style: ToastStyle = ToastStyle.Info,
    modifier: Modifier = Modifier,
) {
    Text(
        text = message,
        color = Color.White,
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
        textAlign = TextAlign.Center,
        modifier = modifier
            .padding(horizontal = 20.dp)
            .background(style.background, RoundedCornerShape(50))
            .padding(horizontal = 18.dp, vertical = 12.dp),
    )
}
