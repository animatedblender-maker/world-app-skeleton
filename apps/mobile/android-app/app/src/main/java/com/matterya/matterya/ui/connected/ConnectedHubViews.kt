package com.matterya.matterya.ui.connected

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.AvatarView

enum class StreamingPlatform(val title: String, val apiSlug: String, val available: Boolean) {
    Netflix("Netflix", "netflix", true),
    AppleMusic("Apple Music", "apple_music", true),
    AppleTV("Apple TV+", "apple_tv", true),
    Spotify("Spotify", "spotify", false),
    Disney("Disney+", "disney", false);

    val accent: Color
        get() = when (this) {
            Netflix -> Color(0.90f, 0.04f, 0.08f)
            AppleMusic -> Color(0.98f, 0.24f, 0.37f)
            AppleTV -> MatteryaColors.ink
            Spotify -> Color(0.12f, 0.73f, 0.33f)
            Disney -> Color(0.07f, 0.29f, 0.67f)
        }
}

data class ConnectedAccount(
    val id: String,
    val platform: StreamingPlatform,
    val isLinked: Boolean,
    val sharingEnabled: Boolean,
)

data class YourNowPlaying(
    val id: String,
    val platform: StreamingPlatform,
    val title: String,
    val subtitle: String,
    val progressLabel: String,
    val progress: Double,
    val isSharing: Boolean,
    val momentLabel: String? = null,
)

data class FriendActivity(
    val id: String,
    val name: String,
    val avatarUrl: String?,
    val avatarSeed: String,
    val platform: StreamingPlatform,
    val title: String,
    val subtitle: String,
    val momentLabel: String? = null,
)

data class LivePlaybackItem(
    val id: String,
    val title: String,
    val subtitle: String,
    val platform: StreamingPlatform,
    val progress: Double = 0.0,
    val isLive: Boolean = true,
)

/** iOS `ConnectedHubView`. */
@Composable
fun ConnectedHubView(
    accounts: List<ConnectedAccount> = emptyList(),
    nowPlaying: YourNowPlaying? = null,
    friends: List<FriendActivity> = emptyList(),
    onBack: () -> Unit = {},
    onLink: (StreamingPlatform) -> Unit = {},
    onUpdateNowPlaying: () -> Unit = {},
    onOpenMoment: (FriendActivity) -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MatteryaColors.ink)
            }
            Text("Connected", fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
        }

        LazyColumn(Modifier.fillMaxSize()) {
            item {
                Text(
                    "Your platforms",
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
                    color = MatteryaColors.ink,
                )
            }
            items(StreamingPlatform.entries.filter { it.available }) { platform ->
                val account = accounts.firstOrNull { it.platform == platform }
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { onLink(platform) }
                        .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        Modifier
                            .size(40.dp)
                            .background(platform.accent.copy(alpha = 0.15f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            if (platform == StreamingPlatform.AppleMusic) Icons.Default.MusicNote else Icons.Default.Tv,
                            null,
                            tint = platform.accent,
                        )
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(platform.title, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                        Text(
                            if (account?.isLinked == true) "Linked" else "Not linked",
                            fontSize = 12.sp,
                            color = MatteryaColors.inkMuted,
                        )
                    }
                    Text(
                        if (account?.isLinked == true) "Manage" else "Link",
                        color = MatteryaColors.accent,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 13.sp,
                    )
                }
            }

            item {
                Spacer(Modifier.height(8.dp))
                Text(
                    "Now playing",
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
                    color = MatteryaColors.ink,
                )
            }
            item {
                if (nowPlaying != null) {
                    LivePlaybackCard(
                        item = LivePlaybackItem(
                            id = nowPlaying.id,
                            title = nowPlaying.title,
                            subtitle = nowPlaying.subtitle,
                            platform = nowPlaying.platform,
                            progress = nowPlaying.progress,
                        ),
                        onClick = onUpdateNowPlaying,
                    )
                } else {
                    Text(
                        "Nothing shared yet. Update what you’re watching.",
                        color = MatteryaColors.inkMuted,
                        modifier = Modifier.padding(MatteryaDimens.pagePadding),
                    )
                    TextButton(
                        onClick = onUpdateNowPlaying,
                        modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding),
                    ) {
                        Text("Update now playing", color = MatteryaColors.accent)
                    }
                }
            }

            item {
                Spacer(Modifier.height(8.dp))
                Text(
                    "Friends",
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
                    color = MatteryaColors.ink,
                )
            }
            if (friends.isEmpty()) {
                item {
                    Text(
                        "When friends share moments, they appear here.",
                        color = MatteryaColors.inkMuted,
                        modifier = Modifier.padding(MatteryaDimens.pagePadding),
                    )
                }
            } else {
                items(friends, key = { it.id }) { friend ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable { onOpenMoment(friend) }
                            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        AvatarView(url = friend.avatarUrl, seed = friend.avatarSeed, size = 40.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(friend.name, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                            Text(
                                "${friend.platform.title} · ${friend.title}",
                                fontSize = 12.sp,
                                color = MatteryaColors.inkMuted,
                                maxLines = 1,
                            )
                        }
                    }
                }
            }
        }
    }
}

/** iOS `LivePlaybackCard`. */
@Composable
fun LivePlaybackCard(
    item: LivePlaybackItem,
    onClick: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp)
            .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.PlayArrow, null, tint = item.platform.accent)
            Spacer(Modifier.width(8.dp))
            Text(item.platform.title, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = item.platform.accent)
            Spacer(Modifier.weight(1f))
            if (item.isLive) {
                Text(
                    "LIVE",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = MatteryaColors.danger,
                    modifier = Modifier
                        .background(MatteryaColors.danger.copy(alpha = 0.12f), RoundedCornerShape(4.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(item.title, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
        Text(item.subtitle, fontSize = 13.sp, color = MatteryaColors.inkMuted)
        if (item.progress > 0) {
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { item.progress.toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
                color = item.platform.accent,
                trackColor = MatteryaColors.canvasMuted,
            )
        }
    }
}

/** iOS `MomentRoomSheet`. */
@Composable
fun MomentRoomSheet(
    friend: FriendActivity,
    onDismiss: () -> Unit = {},
    onJoin: () -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface, RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
            .padding(20.dp),
    ) {
        Text("Watch together", fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, fontSize = 20.sp)
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            AvatarView(url = friend.avatarUrl, seed = friend.avatarSeed, size = 48.dp)
            Spacer(Modifier.width(12.dp))
            Column {
                Text(friend.name, fontWeight = FontWeight.SemiBold)
                Text("${friend.title} · ${friend.platform.title}", fontSize = 13.sp, color = MatteryaColors.inkMuted)
            }
        }
        friend.momentLabel?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
        }
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(onClick = onDismiss) { Text("Not now", color = MatteryaColors.inkMuted) }
            TextButton(
                onClick = onJoin,
                modifier = Modifier.background(MatteryaColors.ink, RoundedCornerShape(8.dp)),
            ) {
                Text("Join moment", color = MatteryaColors.paper, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** iOS `UpdateNowPlayingSheet`. */
@Composable
fun UpdateNowPlayingSheet(
    platforms: List<StreamingPlatform> = StreamingPlatform.entries.filter { it.available },
    onDismiss: () -> Unit = {},
    onSelect: (StreamingPlatform, title: String) -> Unit = { _, _ -> },
) {
    var title by remember { mutableStateOf("") }
    Column(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface, RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
            .padding(20.dp),
    ) {
        Text("Update now playing", fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        Spacer(Modifier.height(12.dp))
        androidx.compose.material3.TextField(
            value = title,
            onValueChange = { title = it },
            placeholder = { Text("What are you watching or listening to?") },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(12.dp))
        platforms.forEach { p ->
            TextButton(
                onClick = { onSelect(p, title.trim()) },
                enabled = title.isNotBlank(),
            ) {
                Text("Share on ${p.title}", color = p.accent)
            }
        }
        TextButton(onClick = onDismiss) { Text("Cancel", color = MatteryaColors.inkMuted) }
    }
}
