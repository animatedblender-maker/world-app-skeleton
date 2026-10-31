package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import com.matterya.matterya.data.anonymous.AnonymousService
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnonymousFeedView(store: AnonymousStore) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    LaunchedEffect(Unit) {
        if (state.feed.isEmpty()) store.loadFeed(force = true)
        else store.reshuffleFeedOnOpen()
    }

    when {
        state.feedLoading && state.feed.isEmpty() -> AnonymousLoadingSkeleton()
        state.feed.isEmpty() -> {
            val wake = (state.lastError ?: "").contains("time", ignoreCase = true) ||
                (state.lastError ?: "").contains("network", ignoreCase = true)
            PullToRefreshBox(
                isRefreshing = state.feedLoading,
                onRefresh = { scope.launch { store.refreshFeed() } },
                modifier = Modifier.fillMaxSize().background(MatteryaColors.canvas),
            ) {
                AnonymousEmptyState(
                    title = if (wake) MatteryaCopy.anonymousFeedWakeTitle else MatteryaCopy.anonymousFeedEmptyTitle,
                    message = if (wake) MatteryaCopy.anonymousFeedWakeBody else MatteryaCopy.anonymousFeedEmptyBody,
                )
            }
        }
        else -> {
            PullToRefreshBox(
                isRefreshing = state.feedLoading,
                onRefresh = { scope.launch { store.refreshFeed() } },
                modifier = Modifier.fillMaxSize().background(MatteryaColors.canvas),
            ) {
                LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                    itemsIndexed(state.feed, key = { _, p -> p.id }) { index, post ->
                        AnonymousPostCard(
                            post = post,
                            style = AnonymousPostCardStyle.Feed,
                            onOpen = { store.pushPost(post) },
                            onOpenSpace = {
                                post.spaceSlug?.takeIf { it.isNotBlank() }?.let { store.pushSpace(it) }
                            },
                            onOpenAuthor = { store.pushProfile(post.authorUsername) },
                            onVote = { value -> scope.launch { store.vote(post, value) } },
                        )
                        LaunchedEffect(post.id) {
                            store.markFeedPostSeen(post.id)
                            val remaining = state.feed.size - index
                            if (remaining <= AnonymousService.feedPrefetchRemaining) {
                                store.loadMoreFeed()
                            }
                        }
                    }
                }
            }
            LaunchedEffect(listState, state.feed.size) {
                snapshotFlow {
                    val info = listState.layoutInfo
                    val last = info.visibleItemsInfo.lastOrNull()?.index ?: 0
                    state.feed.size - last
                }.distinctUntilChanged().collect { remaining ->
                    if (remaining <= AnonymousService.feedPrefetchRemaining) {
                        store.loadMoreFeed()
                    }
                }
            }
        }
    }
}
