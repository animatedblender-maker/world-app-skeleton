package com.matterya.matterya.ui.anonymous

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.AnonymousSpace
import com.matterya.matterya.model.AnonymousSpaceFilter
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

/**
 * iOS `AnonymousPostSpacePickerView` — choose a Space, join if needed, open composer.
 */
@Composable
fun AnonymousPostSpacePickerView(
    store: AnonymousStore,
    onBack: () -> Unit,
    onRequestCreateSpace: () -> Unit,
) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    var joiningSpaceId by remember { mutableStateOf<String?>(null) }
    var composerSpace by remember { mutableStateOf<AnonymousSpace?>(null) }

    LaunchedEffect(Unit) {
        launch { store.loadSpaces(AnonymousSpaceFilter.Joined, force = false) }
        launch { store.loadSpaces(AnonymousSpaceFilter.ForYou, force = false) }
        launch { store.loadSpaces(AnonymousSpaceFilter.Newest, force = false) }
    }

    LaunchedEffect(state.publishEpoch) {
        if (composerSpace != null) {
            composerSpace = null
            onBack()
        }
    }

    val candidates = remember(
        state.spacesByFilter[AnonymousSpaceFilter.Joined],
        state.spacesByFilter[AnonymousSpaceFilter.ForYou],
        state.spacesByFilter[AnonymousSpaceFilter.Newest],
        state.spacesByFilter[AnonymousSpaceFilter.Popular],
        state.spacesByFilter[AnonymousSpaceFilter.Free],
    ) {
        val seen = linkedSetOf<String>()
        val out = mutableListOf<AnonymousSpace>()
        val pools = listOf(
            state.spacesByFilter[AnonymousSpaceFilter.Joined].orEmpty(),
            state.spacesByFilter[AnonymousSpaceFilter.ForYou].orEmpty(),
            state.spacesByFilter[AnonymousSpaceFilter.Newest].orEmpty(),
            state.spacesByFilter[AnonymousSpaceFilter.Popular].orEmpty(),
            state.spacesByFilter[AnonymousSpaceFilter.Free].orEmpty(),
        )
        for (pool in pools) {
            for (space in pool) {
                if (space.isPaid) continue
                if (seen.add(space.id)) out.add(space)
            }
        }
        out.sortedWith(
            compareByDescending<AnonymousSpace> { it.isJoined == true }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.title },
        )
    }

    val loadingJoined = state.spacesLoading[AnonymousSpaceFilter.Joined] == true

    if (composerSpace != null) {
        AnonymousComposerView(
            store = store,
            spaceId = composerSpace!!.id,
            spaceTitle = composerSpace!!.title,
            onBack = { composerSpace = null },
            onPublished = {
                composerSpace = null
                onBack()
            },
        )
        return
    }

    Column(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
        MasqueradePushChrome(
            title = MatteryaCopy.anonymousCreatePost,
            onBack = onBack,
            trailing = {
                TextButton(onClick = onBack) {
                    Text("Cancel", color = MatteryaColors.ink)
                }
            },
        )

        when {
            candidates.isEmpty() && loadingJoined -> {
                Column(
                    Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Spacer(Modifier.height(48.dp))
                    CircularProgressIndicator(color = MatteryaColors.ink)
                }
            }
            candidates.isEmpty() -> {
                AnonymousEmptyState(
                    title = MatteryaCopy.anonymousNoSpaces,
                    message = "Create a Space first, or pull to refresh the directory.",
                    actionTitle = MatteryaCopy.anonymousCreateSpace,
                    onAction = onRequestCreateSpace,
                )
            }
            else -> {
                LazyColumn(
                    Modifier
                        .fillMaxSize()
                        .padding(MatteryaDimens.pagePadding),
                ) {
                    items(candidates, key = { it.id }) { space ->
                        SpacePickerRow(
                            space = space,
                            busy = joiningSpaceId == space.id,
                            enabled = joiningSpaceId == null,
                            onClick = {
                                scope.launch {
                                    joiningSpaceId = space.id
                                    val ok = store.ensureJoined(space)
                                    joiningSpaceId = null
                                    if (ok) {
                                        composerSpace = space.copy(isJoined = true)
                                    }
                                }
                            },
                        )
                        Spacer(Modifier.height(10.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun SpacePickerRow(
    space: AnonymousSpace,
    busy: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                space.title,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
                fontSize = 15.sp,
            )
            space.description?.takeIf { it.isNotBlank() }?.let {
                Spacer(Modifier.height(4.dp))
                Text(
                    it,
                    color = MatteryaColors.inkMuted,
                    fontSize = 12.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (space.isJoined == true) {
                    Text(
                        "Joined",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.ink,
                        modifier = Modifier
                            .background(MatteryaColors.matteDeep, RoundedCornerShape(50))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                }
                space.memberCount?.let { count ->
                    Text(
                        "$count members",
                        fontSize = 11.sp,
                        color = MatteryaColors.inkMuted,
                    )
                }
            }
        }
        Spacer(Modifier.width(8.dp))
        if (busy) {
            CircularProgressIndicator(
                Modifier.size(18.dp),
                color = MatteryaColors.ink,
                strokeWidth = 2.dp,
            )
        } else {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MatteryaColors.inkMuted,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}
