package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.matterya.matterya.model.AppTab
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens

/**
 * Mirrors iOS `BottomTabBar` — Feed | Globe | + | Hubs | Messages | Profile avatar.
 */
@Composable
fun BottomTabBar(
    selected: AppTab,
    profile: Profile?,
    messagesUnread: Int = 0,
    onSelect: (AppTab) -> Unit,
    onCreate: () -> Unit,
    modifier: Modifier = Modifier,
) {
    androidx.compose.foundation.layout.Column(
        modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface.copy(alpha = 0.96f)),
    ) {
        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
        Row(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .height(MatteryaDimens.tabBarHeight),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            TabIcon(
                filled = Icons.Filled.Home,
                outlined = Icons.Outlined.Home,
                selected = selected == AppTab.Feed,
                size = 26.dp,
            ) { onSelect(AppTab.Feed) }

            TabIcon(
                filled = Icons.Filled.Public,
                outlined = Icons.Outlined.Public,
                selected = selected == AppTab.Globe,
                size = 24.dp,
            ) { onSelect(AppTab.Globe) }

            IconButton(
                onClick = onCreate,
                modifier = Modifier
                    .size(52.dp)
                    .offset(y = (-10).dp),
            ) {
                HandDrawnPlusIcon(size = 30.dp)
            }

            TabIcon(
                filled = Icons.Filled.GridView,
                outlined = Icons.Outlined.GridView,
                selected = selected == AppTab.Hubs,
                size = 22.dp,
            ) { onSelect(AppTab.Hubs) }

            Box {
                TabIcon(
                    filled = Icons.Filled.ChatBubble,
                    outlined = Icons.Outlined.ChatBubbleOutline,
                    selected = selected == AppTab.Messages,
                    size = 22.dp,
                ) { onSelect(AppTab.Messages) }
                if (messagesUnread > 0) {
                    UnreadDot(
                        size = 8.dp,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .offset(x = (-6).dp, y = 6.dp),
                    )
                }
            }

            IconButton(onClick = { onSelect(AppTab.Profile) }) {
                ProfileTabAvatar(
                    profile = profile,
                    isSelected = selected == AppTab.Profile,
                )
            }
        }
    }
}

@Composable
private fun TabIcon(
    filled: ImageVector,
    outlined: ImageVector,
    selected: Boolean,
    size: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit,
) {
    IconButton(onClick = onClick) {
        Icon(
            imageVector = if (selected) filled else outlined,
            contentDescription = null,
            tint = MatteryaColors.ink,
            modifier = Modifier.size(size),
        )
    }
}

/** Mirrors iOS `ProfileTabAvatar` with hand-drawn globe ring when selected. */
@Composable
fun ProfileTabAvatar(
    profile: Profile?,
    isSelected: Boolean,
) {
    Box(contentAlignment = Alignment.Center) {
        if (isSelected) {
            HandDrawnGlobeStoryRing(size = 30.dp, highlighted = true)
        }
        AvatarView(
            url = profile?.avatarUrl,
            seed = profile?.userId ?: "me",
            size = if (isSelected) 26.dp else 28.dp,
        )
    }
}
