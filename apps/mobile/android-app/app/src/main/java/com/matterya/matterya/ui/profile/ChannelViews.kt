package com.matterya.matterya.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.ChannelMember
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.HubChannel
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.VideoThumbnailView

/** iOS `ProfilePostCard`. */
@Composable
fun ProfilePostCard(
    post: CountryPost,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius)),
    ) {
        Row(
            Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 14.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Column(Modifier.weight(1f)) {
                post.countryName?.let {
                    Text(
                        it.uppercase(),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.accent,
                        letterSpacing = 1.6.sp,
                    )
                    Spacer(Modifier.height(6.dp))
                }
                post.displayHeadline?.let {
                    Text(it, fontFamily = FontFamily.Serif, fontSize = 17.sp, color = MatteryaColors.ink, maxLines = 3)
                }
            }
            Text(post.relativeTime, fontSize = 11.sp, color = MatteryaColors.inkMuted)
        }
        if (post.hasMedia) {
            VideoThumbnailView(
                post = post,
                maxLogicalPx = 720,
                showsPlayIcon = false,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(220.dp)
                    .padding(horizontal = 16.dp)
                    .clip(RoundedCornerShape(10.dp)),
                contentScale = ContentScale.Crop,
            )
        }
        val excerpt = post.displayExcerpt
        if (excerpt.isNotEmpty()) {
            Text(
                excerpt,
                color = MatteryaColors.inkSecondary,
                fontSize = 14.sp,
                maxLines = if (post.mediaUrl == null) 8 else 4,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
            )
        }
        Row(
            Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Favorite, null, tint = MatteryaColors.inkMuted, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(4.dp))
            Text("${post.likeCount}", fontSize = 12.sp, color = MatteryaColors.inkMuted)
            Spacer(Modifier.width(16.dp))
            Icon(Icons.Outlined.ChatBubbleOutline, null, tint = MatteryaColors.inkMuted, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(4.dp))
            Text("${post.commentCount}", fontSize = 12.sp, color = MatteryaColors.inkMuted)
            post.cityName?.takeIf { it.isNotEmpty() }?.let {
                Spacer(Modifier.width(16.dp))
                Text(it, fontSize = 12.sp, color = MatteryaColors.inkMuted)
            }
        }
    }
}

/**
 * iOS `ChannelSetupView` — channel photo, name, about, Create channel CTA.
 * [onCreate] passes (name, about) for full parity; older callers using handle can ignore about.
 */
@Composable
fun ChannelSetupView(
    profile: Profile? = null,
    busy: Boolean = false,
    errorMessage: String? = null,
    onCancel: () -> Unit = {},
    onChangePhoto: () -> Unit = {},
    onCreate: (name: String, about: String) -> Unit = { _, _ -> },
) {
    var name by remember {
        mutableStateOf(com.matterya.matterya.model.LivingChannelMarker.parse(profile?.bio).orEmpty())
    }
    var about by remember { mutableStateOf("") }
    val canSave = name.trim().isNotEmpty() && !busy
    val fieldShape = RoundedCornerShape(MatteryaDimens.controlRadius)

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 20.dp),
    ) {
        Text("Create your channel", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = MatteryaColors.ink)
        Spacer(Modifier.height(18.dp))
        Text(
            "Publish to Matterya Hubs",
            fontFamily = FontFamily.Serif,
            fontSize = 20.sp,
            color = MatteryaColors.ink,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "Set up a channel name, photo, and about. Then you can post long-form videos to Hubs — separate from normal feed videos.",
            color = MatteryaColors.inkMuted,
            fontSize = 14.sp,
        )
        Spacer(Modifier.height(22.dp))

        Text(
            "CHANNEL PHOTO",
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.inkMuted,
            letterSpacing = 1.1.sp,
        )
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            AvatarView(
                url = profile?.avatarUrl,
                seed = profile?.userId ?: "me",
                size = 72.dp,
            )
            Spacer(Modifier.width(16.dp))
            TextButton(onClick = onChangePhoto) {
                Text(
                    if (profile?.avatarUrl == null) "Add photo" else "Change photo",
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.accentBright,
                )
            }
        }
        Text(
            "This photo shows on your Hubs channel and profile.",
            fontSize = 12.sp,
            color = MatteryaColors.inkMuted,
            modifier = Modifier.padding(top = 8.dp),
        )

        Spacer(Modifier.height(22.dp))
        Text(
            "CHANNEL NAME",
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.inkMuted,
            letterSpacing = 1.1.sp,
        )
        Spacer(Modifier.height(8.dp))
        TextField(
            value = name,
            onValueChange = { name = it },
            modifier = Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface, fieldShape)
                .border(0.5.dp, MatteryaColors.border, fieldShape),
            placeholder = { Text("e.g. Travel with Maya", color = MatteryaColors.inkMuted) },
            singleLine = true,
        )

        Spacer(Modifier.height(18.dp))
        Text(
            "ABOUT",
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.inkMuted,
            letterSpacing = 1.1.sp,
        )
        Spacer(Modifier.height(8.dp))
        TextField(
            value = about,
            onValueChange = { about = it },
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp)
                .background(MatteryaColors.surface, fieldShape)
                .border(0.5.dp, MatteryaColors.border, fieldShape),
            placeholder = { Text("What is your channel about?", color = MatteryaColors.inkMuted) },
        )

        errorMessage?.let {
            Spacer(Modifier.height(10.dp))
            Text(it, fontSize = 12.sp, color = MatteryaColors.danger)
        }

        Spacer(Modifier.height(20.dp))
        TextButton(
            onClick = { onCreate(name.trim(), about.trim()) },
            enabled = canSave,
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    if (canSave) MatteryaColors.accentBright else MatteryaColors.inkMuted,
                    RoundedCornerShape(percent = 50),
                )
                .padding(vertical = 4.dp),
        ) {
            Text(
                if (busy) "Creating…" else "Create channel",
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.paper,
            )
        }
        Spacer(Modifier.height(8.dp))
        TextButton(onClick = onCancel, modifier = Modifier.align(Alignment.CenterHorizontally)) {
            Text("Cancel", color = MatteryaColors.inkMuted)
        }
    }
}

/** iOS `ChannelSettingsView`. */
@Composable
fun ChannelSettingsView(
    channel: HubChannel,
    members: List<ChannelMember> = emptyList(),
    onBack: () -> Unit = {},
    onSave: (name: String, description: String) -> Unit = { _, _ -> },
    onPickAdmins: () -> Unit = {},
    onTransfer: () -> Unit = {},
) {
    var name by remember(channel.id) { mutableStateOf(channel.name) }
    var description by remember(channel.id) { mutableStateOf(channel.about.orEmpty()) }
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper)
            .verticalScroll(rememberScrollState()),
    ) {
        Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MatteryaColors.ink)
            }
            Text("Channel settings", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
        }
        Column(Modifier.padding(MatteryaDimens.pagePadding)) {
            Text("NAME", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MatteryaColors.inkMuted)
            TextField(value = name, onValueChange = { name = it }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(12.dp))
            Text("ABOUT", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MatteryaColors.inkMuted)
            TextField(value = description, onValueChange = { description = it }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            TextButton(onClick = { onSave(name.trim(), description.trim()) }) {
                Text("Save", color = MatteryaColors.accent, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(20.dp))
            Text("Admins · ${members.size}", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            OutlinedButton(onClick = onPickAdmins, modifier = Modifier.padding(top = 8.dp)) {
                Text("Manage admins", color = MatteryaColors.ink)
            }
            OutlinedButton(onClick = onTransfer, modifier = Modifier.padding(top = 8.dp)) {
                Text("Transfer ownership", color = MatteryaColors.danger)
            }
        }
    }
}

/** iOS `ChannelAdminPickerView`. */
@Composable
fun ChannelAdminPickerView(
    candidates: List<Profile> = emptyList(),
    selectedIds: Set<String> = emptySet(),
    onToggle: (Profile) -> Unit = {},
    onDone: () -> Unit = {},
    onBack: () -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MatteryaColors.ink)
            }
            Text("Pick admins", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            TextButton(onClick = onDone) { Text("Done", color = MatteryaColors.accent) }
        }
        LazyColumn {
            items(candidates, key = { it.userId }) { person ->
                val selected = person.userId in selectedIds
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { onToggle(person) }
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AvatarView(url = person.avatarUrl, seed = person.userId, size = 40.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(person.displayLabel, fontWeight = FontWeight.SemiBold)
                        Text("@${person.username ?: "user"}", fontSize = 12.sp, color = MatteryaColors.inkMuted)
                    }
                    Text(
                        if (selected) "Admin" else "Add",
                        color = if (selected) MatteryaColors.accent else MatteryaColors.inkMuted,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}
