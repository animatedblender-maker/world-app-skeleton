package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.theme.MatteryaColors

/** Mirrors iOS `MatteryaTopBar`. */
@Composable
fun MatteryaTopBar(
    showsSearch: Boolean = false,
    notificationsUnread: Int = 0,
    onMenu: () -> Unit = {},
    onSearch: (() -> Unit)? = null,
    onNotifications: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    ColumnBar(modifier) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(44.dp)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onMenu, modifier = Modifier.size(44.dp)) {
                Icon(Icons.Default.Menu, contentDescription = "Menu", tint = MatteryaColors.ink)
            }
            Spacer(Modifier.weight(1f))
            Text(
                AppConfig.appName,
                fontFamily = FontFamily.Serif,
                fontSize = 22.sp,
                color = MatteryaColors.ink,
                letterSpacing = 0.5.sp,
            )
            Spacer(Modifier.weight(1f))
            // iOS HStack(spacing: 18) for search + bell
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(18.dp),
            ) {
                if (showsSearch && onSearch != null) {
                    IconButton(onClick = onSearch, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Default.Search, contentDescription = "Search", tint = MatteryaColors.ink)
                    }
                }
                // iOS: ZStack topTrailing bell + 7pt danger dot offset(x: 4, y: -2)
                Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
                    IconButton(onClick = onNotifications, modifier = Modifier.size(32.dp)) {
                        Icon(
                            Icons.Default.NotificationsNone,
                            contentDescription = "Notifications",
                            tint = MatteryaColors.ink,
                        )
                    }
                    if (notificationsUnread > 0) {
                        UnreadDot(
                            size = 7.dp,
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .offset(x = 4.dp, y = (-2).dp),
                        )
                    }
                }
            }
        }
    }
}


/** Mirrors iOS `ProfileTabTopBar`. */
@Composable
fun ProfileTabTopBar(
    title: String,
    onMenu: () -> Unit = {},
    onEdit: () -> Unit = {},
    onSettings: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    ColumnBar(modifier) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(44.dp)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onMenu, modifier = Modifier.size(44.dp)) {
                Icon(Icons.Default.Menu, contentDescription = "Menu", tint = MatteryaColors.ink)
            }
            Spacer(Modifier.weight(1f))
            Text(
                title,
                fontFamily = FontFamily.Serif,
                fontSize = 20.sp,
                color = MatteryaColors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onSettings, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Default.Settings, contentDescription = "Settings", tint = MatteryaColors.ink)
            }
            Spacer(Modifier.width(8.dp))
            IconButton(onClick = onEdit, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Default.Edit, contentDescription = "Edit profile", tint = MatteryaColors.ink)
            }
        }
    }
}

@Composable
private fun ColumnBar(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    androidx.compose.foundation.layout.Column(
        modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface.copy(alpha = 0.92f))
            .statusBarsPadding(),
    ) {
        content()
        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
    }
}
