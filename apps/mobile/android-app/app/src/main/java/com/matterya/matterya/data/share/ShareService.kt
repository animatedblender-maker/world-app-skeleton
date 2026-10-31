package com.matterya.matterya.data.share

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.matterya.matterya.data.media.PlayPlatformBridge
import com.matterya.matterya.data.messages.MessagesService
import com.matterya.matterya.model.AppDestination
import com.matterya.matterya.model.Conversation
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.ExternalNewsItem
import com.matterya.matterya.model.Message
import com.matterya.matterya.model.Profile

sealed class ShareContent {
    data class Post(val post: CountryPost) : ShareContent()
    data class ProfileShare(val profile: Profile) : ShareContent()
    data class News(val item: ExternalNewsItem) : ShareContent()
    data object AppInvite : ShareContent()
    data class Custom(val title: String, val text: String, val url: String?) : ShareContent()
}

/** iOS `ShareService.swift`. */
class ShareService {
    val appInviteUrl = "https://matterya.com/download"

    fun postUrl(postId: String) = "https://matterya.com/post/$postId"
    fun profileUrl(username: String) = "https://matterya.com/profile/$username"
    fun newsUrl(newsId: String) = "https://matterya.com/news/$newsId"

    fun shareText(content: ShareContent): String = when (content) {
        is ShareContent.Post -> {
            val author = content.post.authorDisplayName
            content.post.displayHeadline?.let { "$it — $author on Matterya" }
                ?: "$author on Matterya"
        }
        is ShareContent.ProfileShare -> {
            val name = content.profile.displayName ?: content.profile.username ?: "Matterya member"
            "Follow $name on Matterya"
        }
        is ShareContent.News -> content.item.title
        ShareContent.AppInvite -> "Join me on Matterya — connect with your country and the world."
        is ShareContent.Custom -> content.title
    }

    fun shareUrl(content: ShareContent): String? = when (content) {
        is ShareContent.Post -> PlayPlatformBridge.shareUrl(content.post)
        is ShareContent.ProfileShare -> {
            val u = content.profile.username
            if (!u.isNullOrEmpty()) profileUrl(u) else appInviteUrl
        }
        is ShareContent.News -> content.item.url.ifEmpty { newsUrl(content.item.id) }
        ShareContent.AppInvite -> appInviteUrl
        is ShareContent.Custom -> content.url
    }

    fun activityItems(content: ShareContent): List<Any> {
        val items = mutableListOf<Any>(shareText(content))
        shareUrl(content)?.let { items.add(it) }
        if (content is ShareContent.Post) {
            (content.post.feedImageUrl ?: content.post.posterImageUrl)?.let { items.add(it) }
        }
        return items
    }

    fun copyLink(context: Context, content: ShareContent) {
        val url = shareUrl(content) ?: return
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("Matterya", url))
    }

    fun messageBody(content: ShareContent): String {
        val text = shareText(content)
        val url = shareUrl(content) ?: return text
        return "$text\n$url"
    }

    fun parseDeepLink(url: String): AppDestination? {
        val uri = android.net.Uri.parse(url)
        val scheme = uri.scheme?.lowercase().orEmpty()
        val host = uri.host?.lowercase().orEmpty()
        val isAppScheme = scheme == "matterya" || scheme == "worldapp"
        val isWeb = host == "matterya.com" || host == "www.matterya.com"
        if (!isAppScheme && !isWeb) return null

        var path = uri.path?.trim('/') ?: ""
        if (isAppScheme && host.isNotEmpty() && host != "matterya.com") {
            path = "$host/$path".trim('/')
        }
        val parts = path.split('/').filter { it.isNotEmpty() }
        val first = parts.firstOrNull()?.lowercase() ?: return null

        return when (first) {
            "post", "p" -> parts.getOrNull(1)?.let { AppDestination.Post(it) }
            "profile", "u" -> parts.getOrNull(1)?.let { AppDestination.PublicProfile(it) }
            "news" -> parts.getOrNull(1)?.let { AppDestination.News(it) }
            "play" -> {
                if (parts.size < 2) return null
                when (parts[1].lowercase()) {
                    "watch" -> parts.getOrNull(2)?.let { AppDestination.PlayWatch(it) }
                    "channel" -> {
                        val rem = parts.drop(2)
                        if (rem.size >= 2 && rem[0].equals("id", true) && rem[1].isNotEmpty()) {
                            AppDestination.PlayChannelId(rem[1])
                        } else rem.firstOrNull()?.takeIf { it.isNotEmpty() }
                            ?.let { AppDestination.PlayChannel(it) }
                    }
                    else -> null
                }
            }
            "settings" -> AppDestination.Settings
            "premium", "plus" -> AppDestination.Settings
            else -> null
        }
    }

    suspend fun sendPostInMessage(
        post: CountryPost,
        conversationId: String,
        messages: MessagesService = MessagesService(),
    ) {
        val body = Message.buildShareBody(post)
        messages.sendMessage(conversationId, body)
    }

    suspend fun sendPostToUser(
        post: CountryPost,
        userId: String,
        messages: MessagesService = MessagesService(),
    ): Conversation {
        val conversation = messages.startConversation(userId)
        sendPostInMessage(post, conversation.id, messages)
        return conversation
    }

    companion object {
        val shared by lazy { ShareService() }
    }
}
