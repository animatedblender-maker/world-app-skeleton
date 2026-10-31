package com.matterya.matterya.ui.news

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.matterya.matterya.data.news.NewsService
import com.matterya.matterya.model.ExternalNewsComment
import com.matterya.matterya.model.ExternalNewsItem
import com.matterya.matterya.model.RelativeTime
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens
import kotlinx.coroutines.launch

/** iOS `NewsDetailView`. */
@Composable
fun NewsDetailView(
    newsId: String,
    initial: ExternalNewsItem? = null,
    onShared: () -> Unit = {},
) {
    val newsService = remember { NewsService() }
    var item by remember(newsId) { mutableStateOf(initial) }
    var comments by remember { mutableStateOf<List<ExternalNewsComment>>(emptyList()) }
    var shareDraft by remember { mutableStateOf("") }
    var commentsOpen by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(initial == null) }
    var busy by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current

    LaunchedEffect(newsId) {
        isLoading = item == null
        runCatching {
            val fetched = newsService.item(newsId)
            if (fetched != null) item = fetched
            comments = newsService.comments(newsId)
        }.onFailure { errorMessage = it.message }
        isLoading = false
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper)
            .verticalScroll(rememberScrollState())
            .padding(MatteryaDimens.pagePadding),
    ) {
        when {
            isLoading -> CircularProgressIndicator(color = MatteryaColors.accent)
            errorMessage != null && item == null -> Text(errorMessage!!, color = MatteryaColors.danger)
            item != null -> {
                val article = item!!
                Row {
                    Text(
                        article.sourceName ?: "ReliefWeb",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = MatteryaColors.accentBright,
                    )
                    Spacer(Modifier.weight(1f))
                    article.publishedAt?.let {
                        Text(RelativeTime.format(it), fontSize = 11.sp, color = MatteryaColors.inkMuted)
                    }
                }
                Spacer(Modifier.height(10.dp))
                Text(article.title, fontWeight = FontWeight.Bold, fontSize = 18.sp, color = MatteryaColors.ink)
                Spacer(Modifier.height(8.dp))
                val tags = (article.themeNames.take(3) + article.disasterTypes.take(3))
                if (tags.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        tags.forEach { tag ->
                            Text(
                                tag,
                                fontSize = 11.sp,
                                color = MatteryaColors.inkSecondary,
                                modifier = Modifier
                                    .background(MatteryaColors.canvasMuted, RoundedCornerShape(50))
                                    .padding(horizontal = 8.dp, vertical = 4.dp),
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }
                article.imageUrl?.let { url ->
                    AsyncImage(
                        model = url,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(220.dp)
                            .clip(RoundedCornerShape(16.dp)),
                    )
                    Spacer(Modifier.height(12.dp))
                }
                article.snippet?.let {
                    Text(it, color = MatteryaColors.ink, fontSize = 15.sp)
                    Spacer(Modifier.height(12.dp))
                }
                if (article.countryNames.isNotEmpty()) {
                    Text(
                        article.countryNames.joinToString(" • "),
                        fontSize = 12.sp,
                        color = MatteryaColors.inkMuted,
                    )
                    Spacer(Modifier.height(12.dp))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = {
                        scope.launch {
                            item = if (article.likedByMe) newsService.unlike(newsId) else newsService.like(newsId)
                        }
                    }) {
                        Text(if (article.likedByMe) "Unlike" else "Like (${article.likeCount})")
                    }
                    TextButton(onClick = { commentsOpen = !commentsOpen }) {
                        Text(if (commentsOpen) "Hide comments" else "Comments (${article.commentCount})")
                    }
                    if (article.url.isNotBlank()) {
                        TextButton(onClick = { runCatching { uriHandler.openUri(article.url) } }) {
                            Text("Source")
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(MatteryaColors.canvasMuted, RoundedCornerShape(14.dp))
                        .padding(14.dp),
                ) {
                    Text("Share to country feed", fontWeight = FontWeight.Bold, color = MatteryaColors.ink)
                    Spacer(Modifier.height(8.dp))
                    TextField(
                        value = shareDraft,
                        onValueChange = { shareDraft = it },
                        placeholder = { Text("Add your caption…") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    TextButton(
                        onClick = {
                            scope.launch {
                                busy = true
                                runCatching {
                                    newsService.shareToCountry(newsId, shareDraft)
                                    onShared()
                                }.onFailure { errorMessage = it.message }
                                busy = false
                            }
                        },
                        enabled = !busy,
                    ) {
                        Text(if (busy) "Sharing…" else "Share")
                    }
                }
                if (commentsOpen) {
                    Spacer(Modifier.height(16.dp))
                    comments.forEach { c ->
                        Column(Modifier.padding(vertical = 6.dp)) {
                            Text(
                                c.author?.displayName ?: c.author?.username ?: "Member",
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 13.sp,
                            )
                            Text(c.body, fontSize = 14.sp, color = MatteryaColors.inkSecondary)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun NewsListCard(item: ExternalNewsItem, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 10.dp)
            .background(MatteryaColors.surface, RoundedCornerShape(12.dp))
            .padding(14.dp),
    ) {
        Text(
            item.sourceName ?: "News",
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = MatteryaColors.accentBright,
        )
        Spacer(Modifier.height(4.dp))
        Text(item.title, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink, maxLines = 3)
        item.snippet?.let {
            Spacer(Modifier.height(4.dp))
            Text(it, fontSize = 13.sp, color = MatteryaColors.inkMuted, maxLines = 2)
        }
    }
}
