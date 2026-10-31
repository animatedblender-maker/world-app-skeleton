package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens

enum class CreateMenuAction { Post, HubsVideo, Spark }

/** Mirrors iOS `CreateMenuOverlay` + `CreateMenuPanel`. */
@Composable
fun CreateMenuSheet(
    visible: Boolean,
    onDismiss: () -> Unit,
    onAction: (CreateMenuAction) -> Unit,
) {
    if (!visible) return
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(MatteryaColors.ink.copy(alpha = 0.16f))
                .clickable(onClick = onDismiss),
        )
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp))
                .background(MatteryaColors.surface)
                .navigationBarsPadding()
                .padding(bottom = MatteryaDimens.tabBarHeight),
        ) {
            Box(
                Modifier
                    .padding(top = 10.dp, bottom = 12.dp)
                    .size(width = 36.dp, height = 4.dp)
                    .align(Alignment.CenterHorizontally)
                    .background(MatteryaColors.border, RoundedCornerShape(2.dp)),
            )
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        "Create",
                        fontFamily = FontFamily.Serif,
                        fontSize = 24.sp,
                        color = MatteryaColors.ink,
                    )
                    Text("Share with your country", fontSize = 12.sp, color = MatteryaColors.inkMuted)
                }
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Close", tint = MatteryaColors.inkMuted)
                }
            }
            HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
            Spacer(Modifier.height(6.dp))
            CreateRow("Post", "Share an update", Icons.Default.Edit) {
                onAction(CreateMenuAction.Post)
            }
            CreateRow(
                "Hubs video",
                "Long-form on ${MatteryaCopy.matteryaHubs}",
                Icons.Default.Movie,
            ) { onAction(CreateMenuAction.HubsVideo) }
            CreateRow(
                MatteryaCopy.spark,
                MatteryaCopy.sparksOnHubs,
                Icons.Default.AutoAwesome,
            ) { onAction(CreateMenuAction.Spark) }
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun CreateRow(
    title: String,
    subtitle: String,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = MatteryaColors.accent, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, fontWeight = FontWeight.Medium, color = MatteryaColors.ink)
            Text(subtitle, fontSize = 12.sp, color = MatteryaColors.inkMuted)
        }
    }
}
