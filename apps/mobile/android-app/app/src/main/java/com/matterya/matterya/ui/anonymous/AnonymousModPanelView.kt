package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens

/** iOS AnonymousModPanelView parity — placeholder mod tools until ops queue ships. */
@Composable
fun AnonymousModPanelView(
    spaceTitle: String,
    onDismiss: () -> Unit,
) {
    Column(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
        Row(
            Modifier.fillMaxWidth().background(MatteryaColors.surface).padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onDismiss) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = MatteryaColors.ink)
            }
            Text(
                "Mod tools",
                modifier = Modifier.weight(1f),
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
            )
            TextButton(onClick = onDismiss) {
                Text("Done", color = MatteryaColors.ink)
            }
        }
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(MatteryaDimens.pagePadding),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(spaceTitle, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, color = MatteryaColors.ink)
            Text(
                MatteryaCopy.anonymousModPlaceholderBody,
                color = MatteryaColors.inkSecondary,
                fontSize = 14.sp,
            )
            PlaceholderRow("Report queue", "Incoming member reports")
            PlaceholderRow("Removed content", "Soft-deleted posts and comments")
            PlaceholderRow("Member sanctions", "Timeouts and bans")
            PlaceholderRow("Rules & logs", "Versioned rules and audit trail")
        }
    }
}

@Composable
private fun PlaceholderRow(title: String, subtitle: String) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface, RoundedCornerShape(14.dp))
            .padding(14.dp),
    ) {
        Text(title, fontWeight = FontWeight.Medium, color = MatteryaColors.ink)
        Spacer(Modifier.height(4.dp))
        Text(subtitle, fontSize = 12.sp, color = MatteryaColors.inkMuted)
        Spacer(Modifier.height(2.dp))
        Text("Coming soon", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = MatteryaColors.inkMuted)
    }
}
