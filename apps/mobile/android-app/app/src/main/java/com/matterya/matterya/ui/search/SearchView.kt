package com.matterya.matterya.ui.search

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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Notes
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.RelativeTime
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.FollowButton
import com.matterya.matterya.ui.components.VideoThumbnailView

/** iOS `SearchView` — people + content result rows (not full PostCards). */
@Composable
fun SearchView(
    profiles: List<Profile> = emptyList(),
    content: List<CountryPost> = emptyList(),
    isSearching: Boolean = false,
    searchError: String? = null,
    currentUserId: String? = null,
    isFollowing: (String) -> Boolean = { false },
    onQueryChange: (String) -> Unit = {},
    onOpenProfile: (Profile) -> Unit = {},
    onOpenContent: (CountryPost) -> Unit = {},
    onOpenHubsChannel: (Profile) -> Unit = {},
    onFollowToggle: suspend (String) -> Unit = {},
    /** Kept for shell API stability (feed like actions still available via detail). */
    onLike: (CountryPost) -> Unit = {},
) {
    @Suppress("UNUSED_PARAMETER")
    val unusedLike = onLike
    var query by remember { mutableStateOf("") }
    val fieldShape = RoundedCornerShape(MatteryaDimens.controlRadius)

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas),
    ) {
        Row(
            Modifier
                .padding(MatteryaDimens.pagePadding)
                .fillMaxWidth()
                .background(MatteryaColors.surface, fieldShape)
                .border(0.5.dp, MatteryaColors.border, fieldShape)
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Search, contentDescription = null, tint = MatteryaColors.inkMuted)
            TextField(
                value = query,
                onValueChange = {
                    query = it
                    onQueryChange(it)
                },
                placeholder = {
                    Text("Search people and content…", color = MatteryaColors.inkMuted, fontSize = 15.sp)
                },
                singleLine = true,
                modifier = Modifier.weight(1f),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    cursorColor = MatteryaColors.accentBright,
                ),
            )
            if (query.isNotEmpty()) {
                IconButton(onClick = {
                    query = ""
                    onQueryChange("")
                }) {
                    Icon(Icons.Default.Close, contentDescription = "Clear", tint = MatteryaColors.inkMuted)
                }
            }
        }

        when {
            isSearching -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                    CircularProgressIndicator(
                        Modifier.padding(24.dp),
                        color = MatteryaColors.accentBright,
                    )
                }
            }
            query.isBlank() -> EmptyPrompt()
            searchError != null && profiles.isEmpty() && content.isEmpty() -> {
                EmptyState("Search failed", searchError)
            }
            profiles.isEmpty() && content.isEmpty() -> {
                EmptyState("No results", "Try another person or keyword.")
            }
            else -> {
                LazyColumn(Modifier.fillMaxSize()) {
                    if (profiles.isNotEmpty()) {
                        item {
                            SectionLabel("People")
                        }
                        items(profiles, key = { it.userId }) { person ->
                            ProfileResultRow(
                                profile = person,
                                currentUserId = currentUserId,
                                following = isFollowing(person.userId),
                                onOpen = { onOpenProfile(person) },
                                onHubs = { onOpenHubsChannel(person) },
                                onFollowToggle = { onFollowToggle(person.userId) },
                            )
                        }
                    }
                    if (content.isNotEmpty()) {
                        item {
                            SectionLabel("Content")
                        }
                        items(content.distinctBy { it.id }, key = { it.id }) { post ->
                            ContentResultRow(
                                post = post,
                                onOpen = { onOpenContent(post) },
                            )
                        }
                    }
                    item { Spacer(Modifier.height(24.dp)) }
                }
            }
        }
    }
}

@Composable
private fun EmptyPrompt() {
    Column(
        Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(48.dp))
        Icon(
            Icons.Default.Search,
            contentDescription = null,
            tint = MatteryaColors.inkMuted,
            modifier = Modifier.size(40.dp),
        )
        Spacer(Modifier.height(16.dp))
        Text("Search Matterya", fontWeight = FontWeight.SemiBold, fontSize = 18.sp, color = MatteryaColors.ink)
        Spacer(Modifier.height(8.dp))
        Text(
            "Find people and posts, Sparks, and videos.",
            color = MatteryaColors.inkMuted,
            fontSize = 14.sp,
        )
    }
}

@Composable
private fun EmptyState(title: String, subtitle: String) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(40.dp))
        Text(title, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
        Spacer(Modifier.height(8.dp))
        Text(subtitle, color = MatteryaColors.inkMuted, fontSize = 14.sp)
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        fontWeight = FontWeight.SemiBold,
        fontSize = 13.sp,
        color = MatteryaColors.inkMuted,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
    )
}

@Composable
private fun ProfileResultRow(
    profile: Profile,
    currentUserId: String?,
    following: Boolean,
    onOpen: () -> Unit,
    onHubs: () -> Unit,
    onFollowToggle: suspend () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .weight(1f)
                .clickable(onClick = onOpen),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AvatarView(url = profile.avatarUrl, seed = profile.userId, size = 40.dp)
            Spacer(Modifier.width(12.dp))
            Column {
                Text(
                    profile.displayName ?: profile.username ?: "User",
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    color = MatteryaColors.ink,
                )
                Text(
                    profile.username?.let { "@$it" } ?: profile.countryName.orEmpty(),
                    fontSize = 12.sp,
                    color = MatteryaColors.inkMuted,
                )
            }
        }
        Box(
            Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(MatteryaColors.accentSoft)
                .clickable(onClick = onHubs),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Default.Public,
                contentDescription = "Open ${MatteryaCopy.matteryaHubs} channel",
                tint = MatteryaColors.accentBright,
                modifier = Modifier.size(16.dp),
            )
        }
        if (!profile.isDemoUser && profile.userId != currentUserId) {
            Spacer(Modifier.width(8.dp))
            FollowButton(
                userId = profile.userId,
                isFollowing = following,
                isSelf = false,
                onToggle = onFollowToggle,
            )
        }
    }
    androidx.compose.material3.HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
}

@Composable
private fun ContentResultRow(
    post: CountryPost,
    onOpen: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface)
            .clickable(onClick = onOpen)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ContentThumbnail(post)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                post.authorDisplayName,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = MatteryaColors.ink,
            )
            post.displayHeadline?.let {
                Text(
                    it,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            val excerpt = post.displayExcerpt
            if (excerpt.isNotEmpty() && !post.hasVideo) {
                Text(
                    excerpt,
                    fontSize = 12.sp,
                    color = MatteryaColors.inkSecondary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val country = post.countryName ?: post.countryCode?.uppercase()
                if (!country.isNullOrBlank()) {
                    Text(country, fontSize = 11.sp, color = MatteryaColors.inkMuted)
                }
                Text(RelativeTime.format(post.createdAt), fontSize = 11.sp, color = MatteryaColors.inkMuted)
                when {
                    post.hasVideo && post.isReel -> {
                        Text(MatteryaCopy.spark, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = MatteryaColors.inkMuted)
                    }
                    post.hasVideo -> {
                        Text("Video", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = MatteryaColors.inkMuted)
                    }
                    post.hasImage -> {
                        Text("Photo", fontSize = 11.sp, color = MatteryaColors.inkMuted)
                    }
                }
            }
        }
    }
    androidx.compose.material3.HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
}

@Composable
private fun ContentThumbnail(post: CountryPost) {
    val shape = RoundedCornerShape(10.dp)
    when {
        post.hasVideo -> {
            val w = if (post.isReel) 72.dp else 128.dp
            val h = if (post.isReel) 128.dp else 72.dp
            VideoThumbnailView(
                post = post,
                maxLogicalPx = 360,
                showsPlayIcon = false,
                modifier = Modifier
                    .width(w)
                    .height(h)
                    .clip(shape),
                contentScale = ContentScale.Crop,
            )
        }
        else -> {
            val url = post.feedImageUrl
            if (!url.isNullOrBlank()) {
                AsyncImage(
                    model = url,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(64.dp)
                        .clip(shape),
                )
            } else {
                Box(
                    Modifier
                        .size(64.dp)
                        .clip(shape)
                        .background(MatteryaColors.canvasMuted),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Outlined.Notes,
                        contentDescription = null,
                        tint = MatteryaColors.inkMuted,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}
