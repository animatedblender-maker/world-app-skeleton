package com.matterya.matterya.ui.feed

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.Profile
import com.matterya.matterya.model.StoryGroup
import com.matterya.matterya.theme.HubsHorizontalShelf
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.PlayBrandMark
import com.matterya.matterya.theme.SparksHorizontalStrip
import com.matterya.matterya.ui.components.MatteryaTopBar
import com.matterya.matterya.ui.components.PostCard
import com.matterya.matterya.ui.components.StoriesStripView

/**
 * Home feed — 1:1 structure with iOS `FeedView`.
 *
 * Section order:
 * 1. Stories strip
 * 2. Pending uploads
 * 3. Sparks horizontal strip
 * 4. Continue watching
 * 5. New on Hubs shelf
 * 6. Post list ([PostCard] / FacebookPostCard path, SparkFeedCard via opensAsSpark)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedView(
    posts: List<CountryPost>,
    sparks: List<CountryPost>,
    hubs: List<CountryPost>,
    continueWatching: List<CountryPost> = emptyList(),
    loading: Boolean,
    profile: Profile? = null,
    pendingUploads: List<FeedUploadPlaceholder> = emptyList(),
    storyGroups: List<StoryGroup> = emptyList(),
    followingIds: Set<String> = emptySet(),
    isPostSaved: (String) -> Boolean = { false },
    sessionReady: Boolean = false,
    authenticated: Boolean = false,
    onRefresh: () -> Unit,
    onLike: (CountryPost) -> Unit,
    onPostUpdated: (CountryPost) -> Unit,
    onMenu: () -> Unit = {},
    onSearch: () -> Unit = {},
    onNotifications: () -> Unit = {},
    onOpenPost: (CountryPost) -> Unit = {},
    onOpenReel: (CountryPost) -> Unit = {},
    onOpenVideo: (CountryPost) -> Unit = {},
    onOpenHubs: () -> Unit = {},
    onOpenAuthor: (CountryPost) -> Unit = {},
    onToggleFollow: (suspend (String) -> Unit)? = null,
    onSave: (CountryPost) -> Unit = {},
    onShare: (CountryPost) -> Unit = {},
    onYourStory: () -> Unit = {},
    onOpenStoryGroup: (StoryGroup) -> Unit = {},
    onRefreshStories: suspend () -> Unit = {},
    onRowAppear: (CountryPost) -> Unit = {},
    notificationsUnread: Int = 0,
    feedVideosMuted: Boolean = false,
    onFeedVideosMutedChange: (Boolean) -> Unit = {},
    reelsOpen: Boolean = false,
    hubPlaying: Boolean = false,
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        MatteryaTopBar(
            showsSearch = true,
            notificationsUnread = notificationsUnread,
            onMenu = onMenu,
            onSearch = onSearch,
            onNotifications = onNotifications,
        )
        PullToRefreshBox(
            isRefreshing = loading && posts.isNotEmpty(),
            onRefresh = onRefresh,
            modifier = Modifier.fillMaxSize(),
        ) {
            val hasStrips = sparks.isNotEmpty() || hubs.isNotEmpty() || continueWatching.isNotEmpty()
            when {
                loading && posts.isEmpty() && !hasStrips -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(color = MatteryaColors.accent)
                            Text(
                                "Loading feed…",
                                color = MatteryaColors.inkMuted,
                                fontSize = 14.sp,
                                modifier = Modifier.padding(top = 12.dp),
                            )
                        }
                    }
                }
                posts.isEmpty() && !hasStrips && !loading -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                "Your feed is quiet",
                                fontWeight = FontWeight.SemiBold,
                                color = MatteryaColors.ink,
                            )
                            Text(
                                "Posts from everywhere will show up here as people share.",
                                color = MatteryaColors.inkMuted,
                                fontSize = 14.sp,
                                modifier = Modifier.padding(horizontal = 32.dp, vertical = 8.dp),
                            )
                        }
                    }
                }
                else -> {
                    LazyColumn(
                        Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(top = 8.dp, bottom = 16.dp),
                    ) {
                        // iOS home feed has NO stories strip (StoriesStripView exists but is not mounted).
                        // Order: pending uploads → Sparks → Continue watching → New on Hubs → posts.

                        // 1. Pending uploads
                        pendingUploads.forEach { draft ->
                            item(key = "upload-${draft.id}") {
                                FeedUploadingShadowCard(draft)
                            }
                        }

                        // 2. Sparks → Continue watching → New on Hubs (iOS order)
                        if (sparks.isNotEmpty()) {
                            item(key = "sparks-strip") {
                                SparksHorizontalStrip(
                                    posts = sparks,
                                    onOpen = onOpenReel,
                                    onBrandTap = onOpenHubs,
                                )
                                HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
                            }
                        }
                        if (continueWatching.isNotEmpty()) {
                            item(key = "continue-watching") {
                                HubsHorizontalShelf(
                                    title = MatteryaCopy.continueWatching,
                                    posts = continueWatching,
                                    onOpen = onOpenVideo,
                                    trailing = {
                                        Text(
                                            MatteryaCopy.matteryaHubs,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            color = MatteryaColors.accentBright,
                                            modifier = Modifier.clickable(onClick = onOpenHubs),
                                        )
                                    },
                                )
                                HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
                            }
                        }
                        if (hubs.isNotEmpty()) {
                            item(key = "new-on-hubs") {
                                HubsHorizontalShelf(
                                    title = MatteryaCopy.newOnHubs,
                                    posts = hubs,
                                    onOpen = onOpenVideo,
                                    trailing = {
                                        PlayBrandMark(compact = true, onClick = onOpenHubs)
                                    },
                                )
                                HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
                            }
                        }

                        if (loading && posts.isEmpty()) {
                            item(key = "posts-loading") {
                                Box(
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(28.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator(color = MatteryaColors.accent)
                                }
                            }
                        }

                        // 6. Post list — SparkFeedCard path via PostCard.opensAsSpark
                        // Defensive distinct: duplicate ids crash LazyColumn ("Key was already used").
                        val uniquePosts = posts.distinctBy { it.id }
                        items(uniquePosts, key = { it.id }) { post ->
                            LaunchedEffect(post.id) {
                                onRowAppear(post)
                            }
                            val followTargetId = PlayPlatformBridge.displayCreator(post).authorId
                                .ifBlank { post.authorId }
                            PostCard(
                                post = post,
                                onLike = { onLike(post) },
                                onUpdated = onPostUpdated,
                                onOpenPost = { onOpenPost(post) },
                                // iOS: openGlobalSparksViewer / openPost
                                onOpenReel = { onOpenReel(post) },
                                onOpenVideo = { onOpenVideo(post) },
                                onOpenAuthor = { onOpenAuthor(post) },
                                onShare = { onShare(post) },
                                onSave = { onSave(post) },
                                onToggleFollow = onToggleFollow?.let { toggle ->
                                    { toggle(followTargetId) }
                                },
                                isFollowingAuthor = followTargetId in followingIds,
                                isPostSaved = isPostSaved(post.id),
                                currentUserId = profile?.userId,
                                currentProfile = profile,
                                // iOS FeedView: showsAuthorHeader: false, showsAuthorInJournal: true
                                showsAuthorHeader = false,
                                showsAuthorInJournal = true,
                                edgeToEdge = true,
                                feedVideosMuted = feedVideosMuted,
                                onFeedVideosMutedChange = onFeedVideosMutedChange,
                                surfaceLive = sessionReady && authenticated,
                                reelsOpen = reelsOpen,
                                hubPlaying = hubPlaying,
                            )
                        }
                    }
                }
            }
        }
    }
}
