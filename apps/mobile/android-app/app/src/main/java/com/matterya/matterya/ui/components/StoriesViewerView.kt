package com.matterya.matterya.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.StoryGroup
import com.matterya.matterya.model.StoryViewerContext
import com.matterya.matterya.theme.MatteryaColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * iOS `StoriesViewerView` — progress bars, tap left/right, auto-advance timer,
 * own-moment delete, body caption gradient.
 */
@Composable
fun StoriesViewerView(
    context: StoryViewerContext,
    currentUserId: String? = null,
    onDismiss: () -> Unit = {},
    onMarkViewed: (String) -> Unit = {},
    onDeleteMoment: (suspend (CountryPost) -> Unit)? = null,
    onContextChange: (StoryViewerContext) -> Unit = {},
) {
    var groupIndex by remember(context.id) { mutableIntStateOf(context.groupIndex) }
    var storyIndex by remember(context.id) { mutableIntStateOf(context.storyIndex) }
    var progress by remember { mutableFloatStateOf(0f) }
    var paused by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var isDeleting by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val groups = context.groups
    val currentGroup: StoryGroup? = groups.getOrNull(groupIndex)
    val currentStory: CountryPost? = currentGroup?.stories?.getOrNull(storyIndex)
    val isOwnMoment = currentStory != null &&
        currentUserId != null &&
        currentStory.authorId == currentUserId

    fun goNext() {
        val group = currentGroup ?: return onDismiss()
        if (storyIndex + 1 < group.stories.size) {
            storyIndex += 1
            progress = 0f
        } else if (groupIndex + 1 < groups.size) {
            groupIndex += 1
            storyIndex = 0
            progress = 0f
        } else {
            onDismiss()
        }
    }

    fun goPrevious() {
        if (storyIndex > 0) {
            storyIndex -= 1
            progress = 0f
        } else if (groupIndex > 0) {
            groupIndex -= 1
            storyIndex = (groups.getOrNull(groupIndex)?.stories?.lastIndex ?: 0).coerceAtLeast(0)
            progress = 0f
        }
    }

    LaunchedEffect(groupIndex, storyIndex, currentStory?.id) {
        onContextChange(context.copy(groupIndex = groupIndex, storyIndex = storyIndex))
        currentStory?.let { onMarkViewed(it.id) }
        progress = 0f
    }

    LaunchedEffect(groupIndex, storyIndex, paused, currentStory?.id) {
        if (paused || currentStory == null) return@LaunchedEffect
        val durationMs = if (currentStory.hasVideo) 12_000L else 5_000L
        val steps = 60
        val stepMs = durationMs / steps
        for (i in 0..steps) {
            if (paused) return@LaunchedEffect
            progress = i / steps.toFloat()
            delay(stepMs)
        }
        goNext()
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) {
                detectTapGestures(
                    onPress = {
                        paused = true
                        tryAwaitRelease()
                        paused = false
                    },
                    onTap = { offset ->
                        if (offset.x < size.width / 2f) goPrevious() else goNext()
                    },
                )
            },
    ) {
        if (currentStory != null) {
            StoryContent(currentStory)
        } else {
            CircularProgressIndicator(
                Modifier.align(Alignment.Center),
                color = Color.White,
            )
        }

        Column(Modifier.fillMaxSize()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(
                        Brush.verticalGradient(
                            listOf(
                                Color.Black.copy(alpha = 0.68f),
                                Color.Black.copy(alpha = 0.34f),
                                Color.Transparent,
                            ),
                        ),
                    )
                    .padding(top = 8.dp, bottom = 10.dp),
            ) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    val stories = currentGroup?.stories.orEmpty()
                    stories.forEachIndexed { index, _ ->
                        Box(
                            Modifier
                                .weight(1f)
                                .height(3.dp)
                                .clip(RoundedCornerShape(2.dp))
                                .background(Color.White.copy(alpha = 0.25f)),
                        ) {
                            val fraction = when {
                                index < storyIndex -> 1f
                                index > storyIndex -> 0f
                                else -> progress
                            }
                            Box(
                                Modifier
                                    .fillMaxHeight()
                                    .fillMaxWidth(fraction)
                                    .background(Color.White, RoundedCornerShape(2.dp)),
                            )
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AvatarView(
                        url = currentGroup?.author?.avatarUrl,
                        seed = currentGroup?.authorId ?: "story",
                        size = 34.dp,
                    )
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            currentGroup?.displayName ?: "Moment",
                            color = Color.White,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 14.sp,
                        )
                        currentStory?.relativeTime?.takeIf { it.isNotEmpty() }?.let {
                            Text(it, color = Color.White.copy(alpha = 0.75f), fontSize = 11.sp)
                        }
                    }
                    if (isOwnMoment && onDeleteMoment != null) {
                        IconButton(onClick = { showDeleteConfirm = true }) {
                            Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Color.White)
                        }
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
                    }
                }
            }

            Spacer(Modifier.weight(1f))

            currentStory?.displayBody?.takeIf { it.isNotBlank() }?.let { body ->
                Text(
                    body,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    maxLines = 4,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            Brush.verticalGradient(
                                listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f)),
                            ),
                        )
                        .padding(14.dp),
                )
            }
        }

        if (isDeleting) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.35f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = Color.White)
                    Spacer(Modifier.height(8.dp))
                    Text("Removing moment…", color = Color.White)
                }
            }
        }
    }

    if (showDeleteConfirm && currentStory != null && onDeleteMoment != null) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("Delete this moment?") },
            text = { Text("It will disappear from Globe moments right away.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirm = false
                        isDeleting = true
                        scope.launch {
                            try {
                                onDeleteMoment.invoke(currentStory)
                                goNext()
                            } finally {
                                isDeleting = false
                            }
                        }
                    },
                ) {
                    Text("Delete moment", color = MatteryaColors.danger)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text("Cancel")
                }
            },
        )
    }
}

@Composable
private fun StoryContent(story: CountryPost) {
    Box(Modifier.fillMaxSize()) {
        when {
            story.hasVideo && !story.playableVideoUrl.isNullOrBlank() -> {
                VideoPlayerView(
                    url = story.playableVideoUrl,
                    posterUrl = story.posterImageUrl,
                    adsEnabled = false,
                    isActive = true,
                    loops = false,
                    fillsFrame = true,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            !story.feedImageUrl.isNullOrBlank() -> {
                AsyncImage(
                    model = story.feedImageUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            else -> {
                Text(
                    story.displayBody,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 20.sp,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(24.dp),
                )
            }
        }
    }
}
