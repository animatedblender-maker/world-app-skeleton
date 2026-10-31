package com.matterya.matterya.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.StoryGroup
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens
import kotlinx.coroutines.delay

/**
 * Structure port of iOS `StoriesStripView` — Globe moments strip.
 * Unviewed groups first, passport bubbles, Add moment + orbit ring.
 */
@Composable
fun StoriesStripView(
    profile: Profile?,
    groups: List<StoryGroup> = emptyList(),
    onYourStory: () -> Unit = {},
    onOpenGroup: (StoryGroup) -> Unit = {},
    onRefresh: suspend () -> Unit = {},
    sessionReady: Boolean = false,
    authenticated: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val sorted = groups
        .filter { it.authorId != profile?.userId }
        .sortedWith(
            compareByDescending<StoryGroup> { it.hasUnviewed }
                .thenBy { it.displayName.lowercase() },
        )
        .take(12)

    LaunchedEffect(sessionReady, authenticated) {
        if (!sessionReady || !authenticated) return@LaunchedEffect
        while (true) {
            delay(8_000)
            onRefresh()
        }
    }

    Column(
        modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    listOf(
                        MatteryaColors.oceanWash.copy(alpha = 0.08f),
                        MatteryaColors.canvas.copy(alpha = 0f),
                    ),
                ),
            )
            .padding(vertical = 8.dp),
    ) {
        Row(
            Modifier.padding(horizontal = MatteryaDimens.pagePadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.Public,
                contentDescription = null,
                tint = MatteryaColors.oceanWash.copy(alpha = 0.95f),
                modifier = Modifier.size(14.dp),
            )
            Spacer(Modifier.width(6.dp))
            Text(
                "GLOBE MOMENTS",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.inkMuted,
                letterSpacing = 0.6.sp,
            )
        }
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(bottom = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            YourStoryButton(profile = profile, groups = groups, onClick = onYourStory)
            sorted.forEach { group ->
                StoryBubble(
                    group = group,
                    onClick = { onOpenGroup(group) },
                )
            }
        }
    }
}

@Composable
private fun YourStoryButton(
    profile: Profile?,
    groups: List<StoryGroup>,
    onClick: () -> Unit,
) {
    val mine = groups.firstOrNull { it.authorId == profile?.userId }
    val preview = mine?.stories?.lastOrNull()?.feedImageUrl
        ?: mine?.stories?.lastOrNull()?.posterImageUrl
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .width(76.dp)
            .clickable(onClick = onClick),
    ) {
        Box {
            StoryPassportBubble(
                previewUrl = preview,
                avatarSeed = profile?.userId ?: "me",
                avatarUrl = profile?.avatarUrl,
                highlighted = !(mine?.stories.isNullOrEmpty()),
            )
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = 2.dp, y = 2.dp)
                    .size(24.dp)
                    .background(MatteryaColors.surface, CircleShape)
                    .border(0.5.dp, MatteryaColors.border, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                HandDrawnPlusIcon(size = 14.dp, color = MatteryaColors.accentBright)
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            "Add moment",
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.inkSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun StoryBubble(
    group: StoryGroup,
    onClick: () -> Unit,
) {
    val preview = group.stories.lastOrNull()?.feedImageUrl
        ?: group.stories.lastOrNull()?.posterImageUrl
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .width(76.dp)
            .clickable(onClick = onClick),
    ) {
        StoryPassportBubble(
            previewUrl = preview,
            avatarSeed = group.authorId,
            avatarUrl = group.author?.avatarUrl,
            highlighted = group.hasUnviewed,
        )
        Spacer(Modifier.height(6.dp))
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                group.displayName,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.inkSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                modifier = Modifier.width(76.dp),
            )
            group.author?.countryCode?.uppercase()?.takeIf { it.isNotBlank() }?.let { code ->
                Spacer(Modifier.height(2.dp))
                Text(
                    code,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    color = if (group.hasUnviewed) MatteryaColors.accent else MatteryaColors.inkMuted,
                    modifier = Modifier
                        .background(MatteryaColors.surface, RoundedCornerShape(percent = 50))
                        .border(0.5.dp, MatteryaColors.border.copy(alpha = 0.7f), RoundedCornerShape(percent = 50))
                        .padding(horizontal = 5.dp, vertical = 2.dp),
                )
            }
        }
    }
}

@Composable
private fun StoryPassportBubble(
    previewUrl: String?,
    avatarSeed: String,
    avatarUrl: String?,
    highlighted: Boolean,
) {
    Box(
        Modifier.size(68.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (highlighted) {
            StoryOrbitRing(size = 68.dp)
        }
        HandDrawnGlobeStoryRing(size = 62.dp, highlighted = highlighted)
        Box(
            Modifier
                .size(50.dp)
                .clip(CircleShape)
                .background(MatteryaColors.canvasMuted),
        ) {
            if (!previewUrl.isNullOrBlank()) {
                AsyncImage(
                    model = previewUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(50.dp)
                        .clip(CircleShape),
                )
            }
            Box(
                Modifier
                    .matchParentSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(
                                androidx.compose.ui.graphics.Color.Transparent,
                                MatteryaColors.ink.copy(alpha = 0.12f),
                            ),
                        ),
                    ),
            )
        }
        AvatarView(
            url = avatarUrl,
            seed = avatarSeed,
            size = 20.dp,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .offset(x = 2.dp, y = 2.dp)
                .border(1.5.dp, MatteryaColors.surface, CircleShape),
        )
    }
}

@Composable
private fun StoryOrbitRing(size: androidx.compose.ui.unit.Dp) {
    val transition = rememberInfiniteTransition(label = "orbit")
    val rotation by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(8000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "rot",
    )
    Box(
        Modifier
            .size(size)
            .rotate(rotation),
        contentAlignment = Alignment.TopCenter,
    ) {
        repeat(3) { index ->
            Box(
                Modifier
                    .rotate(index * 120f)
                    .size(size),
                contentAlignment = Alignment.TopCenter,
            ) {
                Box(
                    Modifier
                        .padding(top = 2.dp)
                        .size(5.dp)
                        .background(MatteryaColors.oceanWash, CircleShape),
                )
            }
        }
    }
}

/** Legacy bubble item for callers that still pass simplified data. */
data class StoryBubbleItem(
    val id: String,
    val displayName: String,
    val avatarUrl: String?,
    val hasUnviewed: Boolean = false,
)
