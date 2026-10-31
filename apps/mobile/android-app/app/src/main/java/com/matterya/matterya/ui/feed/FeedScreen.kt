package com.matterya.matterya.ui.feed

import androidx.compose.runtime.Composable
import com.matterya.matterya.model.CountryPost

/** Back-compat alias — prefer [FeedView]. */
@Composable
fun FeedScreen(
    posts: List<CountryPost>,
    sparks: List<CountryPost>,
    hubs: List<CountryPost>,
    loading: Boolean,
    onRefresh: () -> Unit,
    onLike: (CountryPost) -> Unit,
    onPostUpdated: (CountryPost) -> Unit,
) {
    FeedView(
        posts = posts,
        sparks = sparks,
        hubs = hubs,
        loading = loading,
        onRefresh = onRefresh,
        onLike = onLike,
        onPostUpdated = onPostUpdated,
    )
}
