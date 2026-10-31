package com.matterya.matterya.ui.globe

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.NotificationItem
import com.matterya.matterya.model.RelativeTime
import com.matterya.matterya.theme.ContentSanitizer
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.AvatarView

/**
 * iOS `NotificationsPanelView` + `NotificationsOverlay` chrome.
 */
@Composable
fun NotificationsOverlay(
    visible: Boolean,
    notifications: List<NotificationItem>,
    socialUnread: Int,
    messagesUnread: Int,
    onDismiss: () -> Unit,
    onMarkAllRead: () -> Unit,
    onOpen: (NotificationItem) -> Unit,
    onRefresh: () -> Unit = {},
) {
    if (!visible) return

    LaunchedEffect(Unit) { onRefresh() }

    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.18f))
                .clickable(onClick = onDismiss),
        )
        NotificationsPanelView(
            notifications = notifications,
            socialUnread = socialUnread,
            messagesUnread = messagesUnread,
            onMarkAllRead = onMarkAllRead,
            onClose = onDismiss,
            onOpen = onOpen,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(
                    top = 52.dp,
                    end = MatteryaDimens.pagePadding,
                    start = MatteryaDimens.pagePadding,
                ),
        )
    }
}

@Composable
fun NotificationsPanelView(
    notifications: List<NotificationItem>,
    socialUnread: Int,
    messagesUnread: Int,
    onMarkAllRead: () -> Unit,
    onClose: () -> Unit,
    onOpen: (NotificationItem) -> Unit,
    modifier: Modifier = Modifier,
) {
    val screenW = LocalConfiguration.current.screenWidthDp.dp
    val screenH = LocalConfiguration.current.screenHeightDp.dp
    val panelShape = RoundedCornerShape(24.dp)

    Column(
        modifier
            .widthIn(max = minOf(320.dp, screenW - 32.dp))
            .clip(panelShape)
            .background(MatteryaColors.surface)
            .border(0.5.dp, MatteryaColors.border, panelShape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                "NOTIFICATIONS",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.inkMuted,
                letterSpacing = 0.8.sp,
            )
            Text(
                notificationSummary(socialUnread, messagesUnread),
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
            )
        }

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onMarkAllRead) {
                Text(
                    "Mark all read",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = MatteryaColors.accentBright,
                )
            }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onClose) {
                Text(
                    "Close",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = MatteryaColors.accentBright,
                )
            }
        }

        if (notifications.isEmpty()) {
            Text(
                "No notifications yet.",
                fontSize = 14.sp,
                color = MatteryaColors.inkMuted,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 24.dp),
            )
        } else {
            LazyColumn(
                Modifier.heightIn(max = minOf(420.dp, screenH * 0.45f)),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(notifications, key = { it.id }) { n ->
                    NotificationRow(n, onClick = { onOpen(n) })
                }
            }
        }
    }
}

@Composable
private fun NotificationRow(notification: NotificationItem, onClick: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    val bg = if (notification.isUnread) {
        MatteryaColors.danger.copy(alpha = 0.10f)
    } else {
        MatteryaColors.surfaceMuted
    }
    val stroke = if (notification.isUnread) {
        MatteryaColors.danger.copy(alpha = 0.35f)
    } else {
        MatteryaColors.border
    }

    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(bg)
            .border(0.5.dp, stroke, shape)
            .clickable(onClick = onClick),
    ) {
        Box(
            Modifier
                .padding(vertical = 4.dp)
                .width(4.dp)
                .height(48.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(
                    if (notification.isUnread) MatteryaColors.danger
                    else androidx.compose.ui.graphics.Color.Transparent,
                ),
        )
        Row(
            Modifier.padding(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box {
                AvatarView(
                    url = notification.actor?.avatarUrl,
                    seed = notification.actor?.userId ?: notification.id,
                    size = 36.dp,
                )
                if (notification.isUnread) {
                    Box(
                        Modifier
                            .align(Alignment.TopEnd)
                            .offset(x = 3.dp, y = (-3).dp)
                            .size(11.dp)
                            .background(MatteryaColors.danger, CircleShape)
                            .border(2.dp, MatteryaColors.surface, CircleShape),
                    )
                }
            }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    notificationTitle(notification),
                    fontSize = 14.sp,
                    fontWeight = if (notification.isUnread) FontWeight.Bold else FontWeight.Normal,
                    color = MatteryaColors.ink,
                )
                Text(
                    RelativeTime.format(notification.createdAt),
                    fontSize = 11.sp,
                    color = MatteryaColors.inkMuted,
                )
            }
            if (notification.isUnread) {
                Text(
                    "NEW",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = androidx.compose.ui.graphics.Color.White,
                    modifier = Modifier
                        .clip(RoundedCornerShape(percent = 50))
                        .background(MatteryaColors.danger)
                        .padding(horizontal = 7.dp, vertical = 4.dp),
                )
            }
        }
    }
}

private fun notificationSummary(social: Int, messages: Int): String {
    val parts = mutableListOf<String>()
    parts += if (social > 0) "Unread: $social" else "All caught up"
    if (messages > 0) parts += "$messages in Messages"
    return parts.joinToString(" · ")
}

private fun notificationTitle(n: NotificationItem): String {
    val actor = ContentSanitizer.displayName(
        displayName = n.actor?.displayName,
        username = n.actor?.username,
        fallback = "Someone",
    )
    return when (n.type.lowercase()) {
        "follow" -> "$actor followed you"
        "like" -> "$actor liked your post"
        "comment" -> "$actor commented on your post"
        "comment_like" -> "$actor liked your comment"
        "comment_reply", "reply" -> "$actor replied to your comment"
        "message" -> "$actor sent you a message"
        else -> "$actor interacted with you"
    }
}

/**
 * iOS `PresencePanelView` — MY PRESENCE status card for the globe overlay.
 */
@Composable
fun PresencePanelView(
    countryName: String? = null,
    countryCode: String? = null,
    cityName: String? = null,
    globalOnline: Int? = null,
    globalTotal: Int? = null,
    onClose: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val panelShape = RoundedCornerShape(MatteryaDimens.cardRadius)
    Column(
        modifier
            .widthIn(max = 360.dp)
            .clip(panelShape)
            .background(MatteryaColors.surface)
            .border(0.5.dp, MatteryaColors.border, panelShape)
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "MY PRESENCE",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.inkMuted,
                letterSpacing = 0.8.sp,
            )
            Spacer(Modifier.weight(1f))
            Box(
                Modifier
                    .size(38.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(MatteryaColors.surfaceMuted)
                    .clickable(onClick = onClose),
                contentAlignment = Alignment.Center,
            ) {
                Text("✕", fontWeight = FontWeight.Bold, color = MatteryaColors.inkMuted)
            }
        }

        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(20.dp))
                .background(MatteryaColors.surfaceMuted)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            PresenceLine("STATUS", "ONLINE")
            PresenceLine("COUNTRY", countryName ?: "—")
            PresenceLine("CODE", countryCode?.uppercase() ?: "—")
            PresenceLine("CITY", cityName ?: "—")
        }

        if (globalOnline != null && globalTotal != null) {
            Text(
                "$globalOnline online worldwide · $globalTotal registered",
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
            )
        }
    }
}

@Composable
private fun PresenceLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            label,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.inkMuted,
            letterSpacing = 0.8.sp,
            modifier = Modifier.weight(1f),
        )
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = MatteryaColors.ink)
    }
}

/** Full-screen dimmer + presence panel (mirrors notifications overlay placement). */
@Composable
fun PresenceOverlay(
    visible: Boolean,
    countryName: String? = null,
    countryCode: String? = null,
    cityName: String? = null,
    globalOnline: Int? = null,
    globalTotal: Int? = null,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.18f))
                .clickable(onClick = onDismiss),
        )
        PresencePanelView(
            countryName = countryName,
            countryCode = countryCode,
            cityName = cityName,
            globalOnline = globalOnline,
            globalTotal = globalTotal,
            onClose = onDismiss,
            modifier = Modifier
                .align(Alignment.Center)
                .padding(MatteryaDimens.pagePadding),
        )
    }
}
