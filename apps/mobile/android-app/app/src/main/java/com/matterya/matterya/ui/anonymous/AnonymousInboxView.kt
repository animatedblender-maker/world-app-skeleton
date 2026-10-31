package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnonymousInboxView(store: AnonymousStore) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { store.loadInbox(force = true) }

    Column(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = MatteryaDimens.pagePadding, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Alerts", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            Spacer(Modifier.weight(1f))
            if (state.notificationUnreadCount > 0) {
                TextButton(onClick = { scope.launch { store.markAllNotificationsRead() } }) {
                    Text("Mark all read", color = MatteryaColors.accent)
                }
            }
        }
        PullToRefreshBox(
            isRefreshing = state.inboxLoading,
            onRefresh = { scope.launch { store.loadInbox(force = true) } },
            modifier = Modifier.fillMaxSize(),
        ) {
            when {
                state.inboxLoading && state.inbox.isEmpty() -> AnonymousLoadingSkeleton()
                state.inbox.isEmpty() -> AnonymousEmptyState(
                    title = MatteryaCopy.anonymousNotificationsTitle,
                    message = MatteryaCopy.anonymousNotificationsBody,
                )
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    items(state.inbox, key = { it.id }) { item ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable {
                                    scope.launch { store.markNotificationRead(item) }
                                    item.postId?.let { store.pushPostId(it) }
                                }
                                .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            if (item.isUnread) {
                                Spacer(
                                    Modifier
                                        .padding(top = 6.dp, end = 8.dp)
                                        .size(8.dp)
                                        .clip(CircleShape)
                                        .background(MatteryaColors.danger),
                                )
                            } else {
                                Spacer(Modifier.width(16.dp))
                            }
                            Column(Modifier.weight(1f)) {
                                Text(item.displayTitle, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                                Spacer(Modifier.height(2.dp))
                                Text(item.displayBody, color = MatteryaColors.inkSecondary, fontSize = 13.sp)
                            }
                        }
                    }
                    item {
                        Text(
                            MatteryaCopy.anonymousInboxPrivacyNote,
                            color = MatteryaColors.inkMuted,
                            fontSize = 12.sp,
                            modifier = Modifier.padding(MatteryaDimens.pagePadding),
                        )
                    }
                }
            }
        }
    }
}
