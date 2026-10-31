package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.AnonymousPost
import com.matterya.matterya.model.AnonymousPublicProfilePayload
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

@Composable
fun AnonymousPublicProfileView(
    store: AnonymousStore,
    username: String,
    onBack: () -> Unit,
) {
    var payload by remember { mutableStateOf<AnonymousPublicProfilePayload?>(null) }
    var posts by remember { mutableStateOf<List<AnonymousPost>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(username) {
        loading = true
        payload = store.fetchPublicProfile(username)
        posts = store.loadAuthorPosts(username)
        loading = false
    }

    Column(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
        Row(
            Modifier.fillMaxWidth().background(MatteryaColors.surface).padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = MatteryaColors.ink)
            }
            Text("@$username", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
        }
        when {
            loading -> AnonymousLoadingSkeleton()
            payload == null -> AnonymousEmptyState(title = "Profile unavailable", message = "This Masquerade profile could not be loaded.")
            else -> LazyColumn(Modifier.fillMaxSize()) {
                item {
                    Column(Modifier.padding(16.dp)) {
                        Text(payload!!.profile.displayHandle, fontWeight = FontWeight.Bold, fontSize = 24.sp, color = MatteryaColors.ink)
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "${payload!!.postCount ?: posts.size} posts · ${payload!!.spaceCount ?: 0} spaces",
                            color = MatteryaColors.inkMuted,
                            fontSize = 13.sp,
                        )
                    }
                }
                items(posts, key = { it.id }) { post ->
                    AnonymousPostCard(
                        post = post,
                        style = AnonymousPostCardStyle.Profile,
                        onOpen = { store.pushPost(post) },
                        onOpenSpace = { post.spaceSlug?.let { store.pushSpace(it) } },
                        onVote = { v -> scope.launch { store.vote(post, v) } },
                    )
                }
            }
        }
    }
}
