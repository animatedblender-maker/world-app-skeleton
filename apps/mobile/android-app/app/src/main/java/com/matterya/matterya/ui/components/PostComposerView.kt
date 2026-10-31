package com.matterya.matterya.ui.components

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.PostVisibility
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import kotlinx.coroutines.launch

/**
 * iOS `PostComposerView` — headline, body, privacy, photo pick, publish bar.
 * Upload/create are injected via callbacks so the shell stays compilable without media service wiring.
 */
@Composable
fun PostComposerView(
    country: Country,
    profile: Profile? = null,
    canPostHere: Boolean = true,
    quotedEmbed: SharedPostEmbed? = null,
    onCancel: () -> Unit = {},
    onPublish: suspend (title: String, body: String, visibility: PostVisibility, imageUri: Uri?) -> CountryPost? = { _, _, _, _ -> null },
    onPosted: (CountryPost) -> Unit = {},
) {
    var bodyText by remember { mutableStateOf("") }
    var title by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var imageUri by remember { mutableStateOf<Uri?>(null) }
    var visibility by remember { mutableStateOf(PostVisibility.PUBLIC) }
    val scope = rememberCoroutineScope()
    val maxBody = 2_000
    val trimmed = bodyText.trim()
    val canSubmit = trimmed.isNotEmpty() || imageUri != null || quotedEmbed != null

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        imageUri = uri
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        // Toolbar
        Row(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface.copy(alpha = 0.94f))
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onCancel) {
                Text("Cancel", color = MatteryaColors.inkSecondary)
            }
            Spacer(Modifier.weight(1f))
            Text(
                "New post",
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
            )
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.width(72.dp))
        }

        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            // Header card
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
                    .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
                    .padding(18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AvatarView(
                    url = profile?.avatarUrl,
                    seed = profile?.userId ?: "me",
                    size = 52.dp,
                )
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(
                        profile?.displayName ?: profile?.username ?: "You",
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.ink,
                    )
                    Spacer(Modifier.height(6.dp))
                    Row(
                        Modifier
                            .background(MatteryaColors.accentSoft, RoundedCornerShape(50))
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(countryFlag(country.iso), fontSize = 12.sp)
                        Spacer(Modifier.width(6.dp))
                        Text(
                            MatteryaCopy.postToYourFeed,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = MatteryaColors.accent,
                        )
                    }
                }
            }

            quotedEmbed?.let { embed ->
                SharedPostEmbedCard(embed)
            }

            // Headline
            LabeledField("HEADLINE") {
                TextField(
                    value = title,
                    onValueChange = { title = it },
                    placeholder = { Text("Optional headline", color = MatteryaColors.inkMuted) },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors(),
                    textStyle = androidx.compose.ui.text.TextStyle(
                        fontFamily = FontFamily.Serif,
                        fontSize = 18.sp,
                        color = MatteryaColors.ink,
                    ),
                )
            }

            // Body
            Column {
                Row {
                    Text(
                        "YOUR STORY",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.inkMuted,
                        letterSpacing = 1.2.sp,
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        "${bodyText.length}/$maxBody",
                        fontSize = 11.sp,
                        color = if (bodyText.length > maxBody) MatteryaColors.danger else MatteryaColors.inkMuted,
                    )
                }
                Spacer(Modifier.height(8.dp))
                TextField(
                    value = bodyText,
                    onValueChange = { if (it.length <= maxBody) bodyText = it },
                    placeholder = {
                        Text(
                            "What's happening in ${country.name}?",
                            color = MatteryaColors.inkMuted.copy(alpha = 0.7f),
                        )
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(160.dp),
                    colors = fieldColors(),
                )
            }

            PostVisibilityControl(visibility = visibility, onChange = { visibility = it })

            // Media
            Column {
                Text(
                    "MEDIA",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MatteryaColors.inkMuted,
                    letterSpacing = 1.2.sp,
                )
                Spacer(Modifier.height(12.dp))
                if (imageUri != null) {
                    Box {
                        AsyncImage(
                            model = imageUri,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(240.dp)
                                .clip(RoundedCornerShape(MatteryaDimens.cardRadius))
                                .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius)),
                        )
                        IconButton(
                            onClick = { imageUri = null },
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .padding(10.dp)
                                .background(Color.Black.copy(alpha = 0.55f), CircleShape),
                        ) {
                            Icon(Icons.Default.Close, contentDescription = "Remove", tint = Color.White)
                        }
                    }
                } else {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable { picker.launch("image/*") }
                            .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
                            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            Modifier
                                .size(48.dp)
                                .background(MatteryaColors.accentSoft, RoundedCornerShape(12.dp)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Default.Image, contentDescription = null, tint = MatteryaColors.accentBright)
                        }
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text("Add a photo", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                            Text(
                                "High-resolution images look best in the feed.",
                                fontSize = 12.sp,
                                color = MatteryaColors.inkMuted,
                            )
                        }
                        Icon(Icons.Default.Add, contentDescription = null, tint = MatteryaColors.inkMuted)
                    }
                }
            }

            errorMessage?.let { msg ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(MatteryaColors.danger.copy(alpha = 0.08f), RoundedCornerShape(MatteryaDimens.controlRadius))
                        .padding(14.dp),
                ) {
                    Text(msg, fontSize = 12.sp, color = MatteryaColors.danger)
                }
            }
        }

        // Publish bar
        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
        Row(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface.copy(alpha = 0.96f))
                .padding(horizontal = MatteryaDimens.pagePadding, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    if (canPostHere) "Ready to publish" else "Set your home country",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (canPostHere) MatteryaColors.ink else MatteryaColors.danger,
                )
                Text(
                    if (canPostHere) "Posts to the main feed" else "Add a home country in your profile first.",
                    fontSize = 11.sp,
                    color = MatteryaColors.inkMuted,
                )
            }
            val enabled = canSubmit && !busy && canPostHere
            TextButton(
                onClick = {
                    if (!canPostHere) {
                        errorMessage = MatteryaCopy.homeCountryOnlyPost
                        return@TextButton
                    }
                    scope.launch {
                        busy = true
                        errorMessage = null
                        try {
                            val post = onPublish(title.trim(), trimmed, visibility, imageUri)
                            if (post != null) onPosted(post)
                        } catch (e: Exception) {
                            errorMessage = e.message ?: "Publish failed"
                        } finally {
                            busy = false
                        }
                    }
                },
                enabled = enabled,
                modifier = Modifier
                    .background(
                        if (enabled) MatteryaColors.accentBright else MatteryaColors.inkMuted,
                        RoundedCornerShape(50),
                    )
                    .padding(horizontal = 8.dp),
            ) {
                if (busy) {
                    CircularProgressIndicator(
                        Modifier.size(16.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    if (busy) "Publishing…" else "Publish",
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
fun PostVisibilityControl(
    visibility: PostVisibility,
    onChange: (PostVisibility) -> Unit,
) {
    val options = listOf(PostVisibility.PUBLIC, PostVisibility.FOLLOWERS, PostVisibility.PRIVATE)
    Column {
        Text(
            "PRIVACY",
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.inkMuted,
            letterSpacing = 1.2.sp,
        )
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            options.forEach { option ->
                val selected = visibility == option
                Row(
                    Modifier
                        .clickable { onChange(option) }
                        .background(
                            if (selected) MatteryaColors.accentSoft else MatteryaColors.surface,
                            RoundedCornerShape(50),
                        )
                        .border(
                            0.5.dp,
                            if (selected) MatteryaColors.accent.copy(alpha = 0.45f) else MatteryaColors.border,
                            RoundedCornerShape(50),
                        )
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        when (option) {
                            PostVisibility.PUBLIC -> Icons.Default.Public
                            PostVisibility.FOLLOWERS -> Icons.Default.People
                            else -> Icons.Default.Lock
                        },
                        contentDescription = null,
                        tint = if (selected) MatteryaColors.accentBright else MatteryaColors.inkSecondary,
                        modifier = Modifier.size(14.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        when (option) {
                            PostVisibility.PUBLIC -> "Public"
                            PostVisibility.FOLLOWERS -> "Followers"
                            PostVisibility.PRIVATE -> "Only me"
                            PostVisibility.COUNTRY -> "Country"
                        },
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (selected) MatteryaColors.accentBright else MatteryaColors.inkSecondary,
                    )
                }
            }
        }
    }
}

data class SharedPostEmbed(
    val id: String,
    val title: String? = null,
    val body: String? = null,
    val authorName: String? = null,
    val thumbUrl: String? = null,
)

@Composable
fun SharedPostEmbedCard(embed: SharedPostEmbed) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.canvasMuted, RoundedCornerShape(MatteryaDimens.controlRadius))
            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.controlRadius))
            .padding(12.dp),
    ) {
        if (!embed.thumbUrl.isNullOrBlank()) {
            AsyncImage(
                model = embed.thumbUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(8.dp)),
            )
            Spacer(Modifier.width(10.dp))
        }
        Column {
            Text("Sharing post", fontSize = 11.sp, color = MatteryaColors.inkMuted)
            Text(
                embed.title ?: embed.body?.take(80) ?: "Post",
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
                maxLines = 2,
            )
            embed.authorName?.let {
                Text(it, fontSize = 12.sp, color = MatteryaColors.inkMuted)
            }
        }
    }
}

@Composable
private fun LabeledField(label: String, content: @Composable () -> Unit) {
    Column {
        Text(
            label,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.inkMuted,
            letterSpacing = 1.2.sp,
        )
        Spacer(Modifier.height(8.dp))
        content()
    }
}

@Composable
private fun fieldColors() = TextFieldDefaults.colors(
    focusedContainerColor = MatteryaColors.surface,
    unfocusedContainerColor = MatteryaColors.surface,
    focusedIndicatorColor = MatteryaColors.accent.copy(alpha = 0.45f),
    unfocusedIndicatorColor = MatteryaColors.border,
    cursorColor = MatteryaColors.accent,
    focusedTextColor = MatteryaColors.ink,
    unfocusedTextColor = MatteryaColors.ink,
)

fun countryFlag(iso: String): String {
    val code = iso.uppercase()
    if (code.length != 2) return "🌍"
    val base = 0x1F1E6 - 'A'.code
    return buildString {
        for (ch in code) appendCodePoint(base + ch.code)
    }
}
