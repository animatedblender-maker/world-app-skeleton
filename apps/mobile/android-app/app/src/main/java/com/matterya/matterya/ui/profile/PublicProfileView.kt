package com.matterya.matterya.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.FollowCounts
import com.matterya.matterya.model.LivingChannelMarker
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.forProfileFeedGrid
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.FollowButton
import com.matterya.matterya.ui.components.PostCard

/** iOS `PublicProfileView` — header, stats, Message/Edit, posts feed. */
@Composable
fun PublicProfileView(
    profile: Profile?,
    posts: List<CountryPost> = emptyList(),
    loading: Boolean = false,
    errorMessage: String? = null,
    postsErrorMessage: String? = null,
    isOwner: Boolean = false,
    isFollowing: Boolean = false,
    followCounts: FollowCounts = FollowCounts(
        followers = profile?.followersCount ?: 0,
        following = profile?.followingCount ?: 0,
    ),
    hasHubsChannel: Boolean = false,
    currentUserId: String? = null,
    onFollowToggle: () -> Unit = {},
    onFollowToggleSuspend: (suspend () -> Unit)? = null,
    onMessage: () -> Unit = {},
    onEditProfile: () -> Unit = {},
    onSettings: () -> Unit = {},
    onOpenHubs: () -> Unit = {},
    onShareProfile: () -> Unit = {},
    onBlock: () -> Unit = {},
    onUnblock: () -> Unit = {},
    isBlocked: Boolean = false,
    onLike: (CountryPost) -> Unit = {},
    onOpenPost: (CountryPost) -> Unit = {},
) {
    val visiblePosts = remember(posts) { posts.forProfileFeedGrid() }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas),
    ) {
        when {
            loading && profile == null -> {
                CircularProgressIndicator(
                    Modifier
                        .padding(40.dp)
                        .align(Alignment.CenterHorizontally),
                    color = MatteryaColors.accentBright,
                )
            }
            errorMessage != null && profile == null -> {
                Text(
                    errorMessage,
                    color = MatteryaColors.danger,
                    modifier = Modifier.padding(24.dp),
                )
            }
            profile == null -> {
                Text(
                    "Profile not found",
                    color = MatteryaColors.inkMuted,
                    modifier = Modifier.padding(24.dp),
                )
            }
            else -> {
                LazyColumn(Modifier.fillMaxSize()) {
                    item {
                        ProfileHeader(
                            profile = profile,
                            visiblePostCount = visiblePosts.size,
                            followCounts = followCounts,
                            isOwner = isOwner || profile.userId == currentUserId,
                            isFollowing = isFollowing,
                            hasHubsChannel = hasHubsChannel,
                            isBlocked = isBlocked,
                            onFollowToggle = onFollowToggle,
                            onFollowToggleSuspend = onFollowToggleSuspend,
                            onMessage = onMessage,
                            onEditProfile = onEditProfile,
                            onSettings = onSettings,
                            onOpenHubs = onOpenHubs,
                            onShareProfile = onShareProfile,
                            onBlock = onBlock,
                            onUnblock = onUnblock,
                        )
                    }
                    item {
                        Text(
                            "Posts",
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 17.sp,
                            color = MatteryaColors.ink,
                            modifier = Modifier.padding(
                                horizontal = MatteryaDimens.pagePadding,
                                vertical = 10.dp,
                            ),
                        )
                    }
                    if (postsErrorMessage != null) {
                        item {
                            Text(
                                postsErrorMessage,
                                fontSize = 12.sp,
                                color = MatteryaColors.inkMuted,
                                modifier = Modifier
                                    .padding(horizontal = MatteryaDimens.pagePadding)
                                    .fillMaxWidth()
                                    .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
                                    .padding(MatteryaDimens.cardPadding),
                            )
                        }
                    }
                    if (visiblePosts.isEmpty() && postsErrorMessage == null) {
                        item {
                            Text(
                                "No posts yet.",
                                color = MatteryaColors.inkMuted,
                                modifier = Modifier
                                    .padding(horizontal = MatteryaDimens.pagePadding)
                                    .fillMaxWidth()
                                    .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
                                    .padding(MatteryaDimens.cardPadding),
                            )
                        }
                    }
                    items(visiblePosts.distinctBy { it.id }, key = { it.id }) { post ->
                        PostCard(
                            post = post,
                            onLike = { onLike(post) },
                            onOpenPost = { onOpenPost(post) },
                            edgeToEdge = true,
                        )
                    }
                    item { Spacer(Modifier.height(24.dp)) }
                }
            }
        }
    }
}

@Composable
private fun ProfileHeader(
    profile: Profile,
    visiblePostCount: Int,
    followCounts: FollowCounts,
    isOwner: Boolean,
    isFollowing: Boolean,
    hasHubsChannel: Boolean,
    isBlocked: Boolean,
    onFollowToggle: () -> Unit,
    onFollowToggleSuspend: (suspend () -> Unit)?,
    onMessage: () -> Unit,
    onEditProfile: () -> Unit,
    onSettings: () -> Unit,
    onOpenHubs: () -> Unit,
    onShareProfile: () -> Unit,
    onBlock: () -> Unit,
    onUnblock: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    val displayBio = LivingChannelMarker.displayBio(profile.bio)
    val secondaryShape = RoundedCornerShape(MatteryaDimens.controlRadius)

    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MatteryaDimens.pagePadding)
            .padding(top = 8.dp, bottom = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AvatarView(
                url = profile.avatarUrl,
                seed = profile.userId,
                size = 78.dp,
                modifier = Modifier
                    .border(0.5.dp, MatteryaColors.border, CircleShape)
                    .clip(CircleShape),
            )
            Spacer(Modifier.width(20.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        profile.displayName?.takeIf { it.isNotBlank() } ?: "Member",
                        fontFamily = FontFamily.Serif,
                        fontSize = 24.sp,
                        color = MatteryaColors.ink,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    if (!isOwner && !profile.isDemoUser) {
                        Spacer(Modifier.width(10.dp))
                        FollowButton(
                            userId = profile.userId,
                            isFollowing = isFollowing,
                            isSelf = false,
                            onToggle = {
                                if (onFollowToggleSuspend != null) onFollowToggleSuspend()
                                else onFollowToggle()
                            },
                        )
                    }
                }
                profile.username?.let {
                    Text("@$it", fontSize = 14.sp, color = MatteryaColors.inkMuted)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    Stat("Posts", visiblePostCount)
                    Stat("Followers", followCounts.followers)
                    Stat("Following", followCounts.following)
                }
            }
        }

        if (displayBio.isNotBlank()) {
            Text(displayBio, color = MatteryaColors.inkSecondary, fontSize = 15.sp, lineHeight = 22.sp)
        }

        val country = profile.countryName
        if (!country.isNullOrBlank() && country != "Unknown") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Place, null, tint = MatteryaColors.accent, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(country, color = MatteryaColors.accent, fontSize = 14.sp)
            }
        }

        if (hasHubsChannel) {
            OutlinedButton(
                onClick = onOpenHubs,
                modifier = Modifier.fillMaxWidth(),
                shape = secondaryShape,
            ) {
                Icon(Icons.Default.PlayArrow, null, tint = MatteryaColors.ink, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(MatteryaCopy.watchOnHubs, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            }
        }

        if (isOwner) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    onClick = onEditProfile,
                    modifier = Modifier.weight(1f),
                    shape = secondaryShape,
                ) {
                    Text("Edit profile", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                }
                OutlinedButton(
                    onClick = onSettings,
                    modifier = Modifier.weight(1f),
                    shape = secondaryShape,
                ) {
                    Text("Settings", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                }
            }
        } else {
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                androidx.compose.material3.Button(
                    onClick = onMessage,
                    modifier = Modifier.weight(1f),
                    shape = secondaryShape,
                    colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                        containerColor = MatteryaColors.accentBright,
                    ),
                ) {
                    Text("Message", fontWeight = FontWeight.SemiBold, color = androidx.compose.ui.graphics.Color.White)
                }
                BoxMore(
                    expanded = menuOpen,
                    onExpand = { menuOpen = true },
                    onDismiss = { menuOpen = false },
                    onShare = {
                        menuOpen = false
                        onShareProfile()
                    },
                    isBlocked = isBlocked,
                    onBlock = {
                        menuOpen = false
                        onBlock()
                    },
                    onUnblock = {
                        menuOpen = false
                        onUnblock()
                    },
                )
            }
        }
    }
}

@Composable
private fun Stat(label: String, value: Int) {
    Column {
        Text("$value", fontWeight = FontWeight.Bold, color = MatteryaColors.ink, fontSize = 15.sp)
        Text(label, fontSize = 12.sp, color = MatteryaColors.inkMuted)
    }
}

@Composable
private fun BoxMore(
    expanded: Boolean,
    onExpand: () -> Unit,
    onDismiss: () -> Unit,
    onShare: () -> Unit,
    isBlocked: Boolean,
    onBlock: () -> Unit,
    onUnblock: () -> Unit,
) {
    androidx.compose.foundation.layout.Box {
        androidx.compose.foundation.layout.Box(
            Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(MatteryaColors.surface)
                .border(0.5.dp, MatteryaColors.border, CircleShape)
                .clickable(onClick = onExpand),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Default.MoreHoriz, contentDescription = "More", tint = MatteryaColors.ink)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
            DropdownMenuItem(
                text = { Text("Share profile") },
                onClick = onShare,
            )
            if (isBlocked) {
                DropdownMenuItem(
                    text = { Text("Unblock user") },
                    onClick = onUnblock,
                )
            } else {
                DropdownMenuItem(
                    text = { Text("Block user", color = MatteryaColors.danger) },
                    onClick = onBlock,
                )
            }
        }
    }
}
