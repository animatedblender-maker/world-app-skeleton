package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy


enum class AppMenuAction {
    Profile, Hubs, People, Ads, Masquerade, Invite, Saved, Settings, Logout
}

/** Mirrors iOS `AppMenuOverlay` + `AppMenuPanel`. */
@Composable
fun AppMenuOverlay(
    visible: Boolean,
    profile: Profile?,
    onDismiss: () -> Unit,
    onAction: (AppMenuAction) -> Unit,
) {
    if (!visible) return

    Box(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.45f))
                .clickable(onClick = onDismiss),
        )
        Column(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth(0.84f)
                .align(Alignment.CenterStart)
                .background(MatteryaColors.surface)
                .statusBarsPadding(),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Menu",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = MatteryaColors.ink,
                )
                Spacer(modifier = Modifier.weight(1f))
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Close", tint = MatteryaColors.inkMuted)
                }
            }

            if (profile != null) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onAction(AppMenuAction.Profile) }
                        .padding(horizontal = 20.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AvatarView(url = profile.avatarUrl, seed = profile.userId, size = 56.dp)
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text(
                            profile.displayLabel,
                            fontWeight = FontWeight.SemiBold,
                            color = MatteryaColors.ink,
                        )
                        profile.username?.let {
                            Text("@$it", fontSize = 14.sp, color = MatteryaColors.inkMuted)
                        }
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))
            }

            HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
            Spacer(modifier = Modifier.height(8.dp))

            MenuRow(MatteryaCopy.matteryaHubs, Icons.Default.GridView) {
                onAction(AppMenuAction.Hubs)
            }
            MenuRow("Discover People", Icons.Default.People) {
                onAction(AppMenuAction.People)
            }
            MenuRow("Ads Manager", Icons.Default.Campaign) {
                onAction(AppMenuAction.Ads)
            }
            MenuRow(MatteryaCopy.anonymous, Icons.Default.TheaterComedy) {
                onAction(AppMenuAction.Masquerade)
            }
            MenuRow("Invite friends", Icons.Default.PersonAdd) {
                onAction(AppMenuAction.Invite)
            }
            MenuRow("Saved", Icons.Default.Bookmark) {
                onAction(AppMenuAction.Saved)
            }
            MenuRow("Settings", Icons.Default.Settings) {
                onAction(AppMenuAction.Settings)
            }

            Spacer(modifier = Modifier.weight(1f))
            HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onAction(AppMenuAction.Logout) }
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.Logout,
                    contentDescription = null,
                    tint = MatteryaColors.danger,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(14.dp))
                Text("Log Out", fontWeight = FontWeight.Medium, color = MatteryaColors.danger)
            }
        }
    }
}

@Composable
private fun MenuRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = MatteryaColors.ink, modifier = Modifier.size(24.dp))
        Spacer(modifier = Modifier.width(14.dp))
        Text(title, color = MatteryaColors.ink, fontSize = 16.sp)
    }
}
