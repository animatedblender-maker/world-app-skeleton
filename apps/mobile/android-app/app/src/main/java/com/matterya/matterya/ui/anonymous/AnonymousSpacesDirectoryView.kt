package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.matterya.matterya.model.AnonymousSpaceFilter
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnonymousSpacesDirectoryView(
    store: AnonymousStore,
    onCreateSpace: () -> Unit = {},
) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    val filter = state.activeSpaceFilter
    val spaces = state.spacesByFilter[filter].orEmpty()
    val loading = state.spacesLoading[filter] == true

    LaunchedEffect(filter) { store.loadSpaces(filter, force = false) }

    Column(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
        Row(
            Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
        ) {
            AnonymousSpaceFilter.entries.forEach { f ->
                FilterChip(
                    selected = f == filter,
                    onClick = { store.setActiveSpaceFilter(f) },
                    label = { Text(f.title) },
                    modifier = Modifier.padding(end = 6.dp),
                )
            }
        }
        PullToRefreshBox(
            isRefreshing = loading,
            onRefresh = { scope.launch { store.loadSpaces(filter, force = true) } },
            modifier = Modifier.fillMaxSize(),
        ) {
            when {
                loading && spaces.isEmpty() -> AnonymousLoadingSkeleton()
                spaces.isEmpty() && filter == AnonymousSpaceFilter.Joined ->
                    AnonymousEmptyState(
                        title = MatteryaCopy.anonymousNoJoinedSpaces,
                        message = MatteryaCopy.anonymousNoJoinedSpacesBody,
                    )
                spaces.isEmpty() && filter == AnonymousSpaceFilter.Paid ->
                    AnonymousEmptyState(
                        title = MatteryaCopy.anonymousPaidComingSoonTitle,
                        message = MatteryaCopy.anonymousPaidComingSoonBody,
                    )
                spaces.isEmpty() ->
                    AnonymousEmptyState(
                        title = MatteryaCopy.anonymousNoSpaces,
                        message = MatteryaCopy.anonymousNoSpacesBody,
                        actionTitle = MatteryaCopy.anonymousCreateSpace,
                        onAction = onCreateSpace,
                    )
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    items(spaces, key = { it.id }) { space ->
                        AnonymousSpaceRow(
                            space = space,
                            joined = store.isJoined(space),
                            busy = store.isMembershipBusy(space.id),
                            onOpen = { store.pushSpace(space.slug) },
                            onToggleJoin = {
                                scope.launch {
                                    if (store.isJoined(space)) {
                                        // Directory leave goes through currentSpace path after open.
                                        store.pushSpace(space.slug)
                                    } else {
                                        store.joinSpace(space)
                                    }
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}
