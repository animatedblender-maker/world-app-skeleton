package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun AnonymousSearchView(
    store: AnonymousStore,
    query: String,
) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    val results = state.searchResults

    LaunchedEffect(query) {
        delay(280)
        store.search(query)
    }

    when {
        state.searchLoading &&
            results.people.isEmpty() && results.spaces.isEmpty() && results.posts.isEmpty() &&
            query.isNotBlank() -> AnonymousLoadingSkeleton()
        query.isBlank() -> AnonymousEmptyState(
            title = MatteryaCopy.anonymousSearchTitle,
            message = MatteryaCopy.anonymousSearchHint,
        )
        results.people.isEmpty() && results.spaces.isEmpty() && results.posts.isEmpty() ->
            AnonymousEmptyState(
                title = MatteryaCopy.anonymousSearchEmptyTitle,
                message = MatteryaCopy.anonymousSearchEmptyBody,
            )
        else -> LazyColumn(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
            if (results.people.isNotEmpty()) {
                item { SectionHeader("People") }
                items(results.people, key = { "p-${it.id}" }) { person ->
                    Text(
                        person.displayHandle,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { store.pushProfile(person.username) }
                            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp),
                        color = MatteryaColors.ink,
                        fontWeight = FontWeight.Medium,
                    )
                }
            }
            if (results.spaces.isNotEmpty()) {
                item { SectionHeader("Spaces") }
                items(results.spaces, key = { "s-${it.id}" }) { space ->
                    AnonymousSpaceRow(
                        space = space,
                        joined = store.isJoined(space),
                        busy = store.isMembershipBusy(space.id),
                        onOpen = { store.pushSpace(space.slug) },
                        onToggleJoin = { scope.launch { store.joinSpace(space) } },
                    )
                }
            }
            if (results.posts.isNotEmpty()) {
                item { SectionHeader("Posts") }
                items(results.posts, key = { "post-${it.id}" }) { post ->
                    AnonymousPostCard(
                        post = post,
                        onOpen = { store.pushPost(post) },
                        onOpenSpace = { post.spaceSlug?.let { store.pushSpace(it) } },
                        onOpenAuthor = { store.pushProfile(post.authorUsername) },
                        onVote = { v -> scope.launch { store.vote(post, v) } },
                    )
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        fontWeight = FontWeight.SemiBold,
        color = MatteryaColors.inkMuted,
        fontSize = 13.sp,
        modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 10.dp),
    )
}
