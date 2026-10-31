package com.matterya.matterya.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.ProfileLibrarySection
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.MatteryaTopBar
import com.matterya.matterya.ui.components.PostCard

/**
 * Own profile — 1:1 with iOS `ProfileView`.
 * Tabs: Posts | Saved posts | Saved videos | Saved sparks.
 */
@Composable
fun ProfileView(
    profile: Profile?,
    posts: List<CountryPost> = emptyList(),
    savedPosts: List<CountryPost> = emptyList(),
    savedVideos: List<CountryPost> = emptyList(),
    savedSparks: List<CountryPost> = emptyList(),
    followers: Int = 0,
    following: Int = 0,
    section: ProfileLibrarySection = ProfileLibrarySection.POSTS,
    onSectionChange: (ProfileLibrarySection) -> Unit = {},
    onMenu: () -> Unit = {},
    onSearch: () -> Unit = {},
    onEdit: () -> Unit = {},
    onSettings: () -> Unit = {},
    onLike: (CountryPost) -> Unit = {},
    onOpenPost: (CountryPost) -> Unit = {},
    onOpenReel: (CountryPost) -> Unit = {},
    onOpenVideo: (CountryPost) -> Unit = {},
    hasOwnHubsChannel: Boolean = false,
    onOpenHubsChannel: () -> Unit = {},
) {
    var localSection by remember(section) { mutableStateOf(section) }
    val active = localSection

    val library: List<CountryPost> = when (active) {
        ProfileLibrarySection.POSTS -> posts
        ProfileLibrarySection.SAVED_POSTS -> savedPosts
        ProfileLibrarySection.SAVED_VIDEOS -> savedVideos
        ProfileLibrarySection.SAVED_REELS -> savedSparks
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        MatteryaTopBar(showsSearch = true, onMenu = onMenu, onSearch = onSearch)
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                ProfileHeader(
                    profile = profile,
                    postCount = posts.size,
                    followers = followers,
                    following = following,
                    onEdit = onEdit,
                    onSettings = onSettings,
                    hasOwnHubsChannel = hasOwnHubsChannel,
                    onOpenHubsChannel = onOpenHubsChannel,
                )
            }
            item {
                // iOS pill tabs — horizontal scroll of all library sections
                Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = MatteryaDimens.pagePadding)
                        .padding(bottom = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    ProfileLibrarySection.entries.forEach { tab ->
                        PillTab(
                            title = tab.title,
                            selected = active == tab,
                            onClick = {
                                localSection = tab
                                onSectionChange(tab)
                            },
                        )
                    }
                }
            }
            when {
                library.isEmpty() -> {
                    item {
                        SavedEmptyState(section = active)
                    }
                }
                active == ProfileLibrarySection.POSTS -> {
                    items(library.distinctBy { it.id }, key = { it.id }) { post ->
                        PostCard(
                            post = post,
                            onLike = { onLike(post) },
                            onOpenPost = { onOpenPost(post) },
                            onOpenReel = { onOpenReel(post) },
                            onOpenVideo = { onOpenVideo(post) },
                            showsAuthorHeader = true,
                            edgeToEdge = true,
                        )
                    }
                }
                else -> {
                    item {
                        val (title, subtitle) = when (active) {
                            ProfileLibrarySection.SAVED_POSTS ->
                                "Saved posts" to "Bookmarks from your feed"
                            ProfileLibrarySection.SAVED_VIDEOS ->
                                "Saved videos" to "Videos you bookmarked"
                            ProfileLibrarySection.SAVED_REELS ->
                                MatteryaCopy.savedSparks to MatteryaCopy.savedSparksSubtitle
                            else -> "" to ""
                        }
                        Column(Modifier.padding(horizontal = MatteryaDimens.pagePadding)) {
                            Text(title, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                            Text(subtitle, fontSize = 12.sp, color = MatteryaColors.inkMuted)
                            Spacer(Modifier.height(8.dp))
                        }
                    }
                    items(library.distinctBy { it.id }, key = { it.id }) { post ->
                        PostCard(
                            post = post,
                            onLike = { onLike(post) },
                            onOpenPost = { onOpenPost(post) },
                            onOpenReel = { onOpenReel(post) },
                            onOpenVideo = { onOpenVideo(post) },
                            showsAuthorHeader = true,
                            edgeToEdge = true,
                        )
                    }
                }
            }
            item {
                // Logout lives in the app menu only (iOS parity) — not on the profile page.
                Spacer(Modifier.height(48.dp))
            }
        }
    }
}

@Composable
private fun SavedEmptyState(section: ProfileLibrarySection) {
    val message = when (section) {
        ProfileLibrarySection.POSTS -> "No posts yet"
        ProfileLibrarySection.SAVED_POSTS -> "Save posts from the feed to revisit them here."
        ProfileLibrarySection.SAVED_VIDEOS -> "Save videos while watching to find them here."
        ProfileLibrarySection.SAVED_REELS -> MatteryaCopy.saveSparksHint
    }
    Text(
        message,
        color = MatteryaColors.inkMuted,
        fontSize = 14.sp,
        modifier = Modifier.padding(24.dp),
    )
}

@Composable
private fun PillTab(title: String, selected: Boolean, onClick: () -> Unit) {
    // iOS `.pillTab` — uppercase caption, underline when selected
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Text(
            title.uppercase(),
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (selected) MatteryaColors.ink else MatteryaColors.inkMuted,
        )
        Spacer(Modifier.height(10.dp))
        Box(
            Modifier
                .height(1.dp)
                .width(if (selected) 48.dp else 0.dp)
                .background(MatteryaColors.ink),
        )
    }
}

@Composable
private fun ProfileHeader(
    profile: Profile?,
    postCount: Int,
    followers: Int,
    following: Int,
    onEdit: () -> Unit,
    onSettings: () -> Unit,
    hasOwnHubsChannel: Boolean,
    onOpenHubsChannel: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MatteryaDimens.pagePadding)
            .padding(top = 12.dp, bottom = 18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AvatarView(
                url = profile?.avatarUrl,
                seed = profile?.userId ?: "me",
                size = 78.dp,
            )
            Spacer(Modifier.width(22.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val name = profile?.displayName?.takeIf { it.isNotBlank() }
                if (name != null) {
                    Text(
                        name,
                        fontFamily = FontFamily.Serif,
                        fontSize = 26.sp,
                        color = MatteryaColors.ink,
                    )
                }
                profile?.username?.let {
                    Text("@$it", color = MatteryaColors.inkMuted, fontSize = 14.sp)
                } ?: run {
                    if (name == null) {
                        Text(
                            "Member",
                            fontFamily = FontFamily.Serif,
                            fontSize = 26.sp,
                            color = MatteryaColors.ink,
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    StatBlock("Posts", postCount)
                    StatBlock("Followers", followers)
                    StatBlock("Following", following)
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SecondaryButton(
                label = "Edit profile",
                icon = { Icon(Icons.Default.Edit, null, Modifier.size(16.dp), MatteryaColors.ink) },
                onClick = onEdit,
                modifier = Modifier.weight(1f),
            )
            SecondaryButton(
                label = "Settings",
                icon = { Icon(Icons.Default.Settings, null, Modifier.size(16.dp), MatteryaColors.ink) },
                onClick = onSettings,
                modifier = Modifier.weight(1f),
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            profile?.bio?.takeIf { it.isNotBlank() }?.let {
                Text(it, color = MatteryaColors.inkSecondary, fontSize = 15.sp, lineHeight = 20.sp)
            }
            profile?.countryName?.takeIf { it.isNotBlank() && it != "Unknown" }?.let {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Place,
                        contentDescription = null,
                        tint = MatteryaColors.accent,
                        modifier = Modifier.size(14.dp),
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(it, color = MatteryaColors.accent, fontSize = 14.sp)
                }
            }
        }

        if (hasOwnHubsChannel) {
            SecondaryButton(
                label = MatteryaCopy.yourChannelOnHubs,
                onClick = onOpenHubsChannel,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun SecondaryButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier
            .background(MatteryaColors.buttonMuted, RoundedCornerShape(MatteryaDimens.controlRadius))
            .clickable(onClick = onClick)
            .padding(vertical = 7.dp, horizontal = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            icon()
            Spacer(Modifier.width(6.dp))
        }
        Text(
            label,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.ink,
        )
    }
}

@Composable
private fun StatBlock(label: String, value: Int) {
    Column {
        Text("$value", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink, fontSize = 15.sp)
        Text(label, fontSize = 12.sp, color = MatteryaColors.inkMuted)
    }
}
