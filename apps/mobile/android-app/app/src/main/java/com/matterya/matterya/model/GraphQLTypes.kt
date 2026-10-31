package com.matterya.matterya.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.max

/**
 * GraphQL wire DTOs — mirrors iOS `GraphQLTypes.swift`.
 * Map into domain models with [toModel] / [toPreview], including effective comment counts.
 */

@Serializable
data class GraphQLPost(
    val id: String = "",
    val title: String? = null,
    val body: String = "",
    @SerialName("media_type") val mediaType: String? = null,
    @SerialName("media_url") val mediaUrl: String? = null,
    @SerialName("thumb_url") val thumbUrl: String? = null,
    @SerialName("shared_post_id") val sharedPostId: String? = null,
    @SerialName("shared_post") val sharedPost: GraphQLSharedPost? = null,
    val visibility: String = "public",
    @SerialName("like_count") val likeCount: Int = 0,
    @SerialName("comment_count") val commentCount: Int = 0,
    @SerialName("liked_by_me") val likedByMe: Boolean = false,
    @SerialName("saved_by_me") val savedByMe: Boolean? = null,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
    @SerialName("author_id") val authorId: String = "",
    @SerialName("country_name") val countryName: String? = null,
    @SerialName("country_code") val countryCode: String? = null,
    @SerialName("city_name") val cityName: String? = null,
    val author: GraphQLAuthor? = null,
) {
    val toModel: CountryPost
        get() {
            val preview = sharedPost?.toPreview
            // Prefer fuller origin thread count for spark/hub shares (local share often has 0 rows).
            val effectiveComments = max(commentCount, preview?.commentCount ?: 0)
            return CountryPost(
                id = id,
                title = title,
                body = body,
                mediaType = mediaType,
                mediaUrl = mediaUrl,
                thumbUrl = thumbUrl,
                sharedPostId = sharedPostId,
                sharedPost = preview,
                visibility = visibility.ifEmpty { "public" },
                likeCount = likeCount,
                commentCount = effectiveComments,
                viewCount = 0,
                likedByMe = likedByMe,
                savedByMe = savedByMe ?: false,
                createdAt = createdAt,
                updatedAt = updatedAt.ifEmpty { createdAt },
                authorId = authorId,
                countryName = countryName,
                countryCode = countryCode,
                cityName = cityName,
                author = author?.toModel,
            )
        }
}

@Serializable
data class GraphQLSharedPost(
    val id: String = "",
    val title: String? = null,
    val body: String = "",
    @SerialName("media_type") val mediaType: String? = null,
    @SerialName("media_url") val mediaUrl: String? = null,
    @SerialName("thumb_url") val thumbUrl: String? = null,
    @SerialName("author_id") val authorId: String = "",
    @SerialName("like_count") val likeCount: Int = 0,
    @SerialName("comment_count") val commentCount: Int = 0,
    val author: GraphQLAuthor? = null,
) {
    val toPreview: SharedPostPreview
        get() = SharedPostPreview(
            id = id,
            title = title,
            body = body,
            mediaType = mediaType,
            mediaUrl = mediaUrl,
            thumbUrl = thumbUrl,
            authorId = authorId,
            author = author?.toModel,
            commentCount = commentCount,
            likeCount = likeCount,
        )
}

@Serializable
data class GraphQLAuthor(
    @SerialName("user_id") val userId: String = "",
    @SerialName("display_name") val displayName: String? = null,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("country_name") val countryName: String? = null,
    @SerialName("country_code") val countryCode: String? = null,
    @SerialName("last_read_at") val lastReadAt: String? = null,
) {
    val toModel: PostAuthor
        get() = PostAuthor(
            userId = userId,
            displayName = displayName,
            username = username,
            avatarUrl = avatarUrl,
            countryName = countryName,
            countryCode = countryCode,
            lastReadAt = lastReadAt,
        )

    val toModelIfValid: PostAuthor?
        get() {
            val normalized = userId.trim()
            if (normalized.isEmpty()) return null
            return PostAuthor(
                userId = normalized,
                displayName = displayName,
                username = username,
                avatarUrl = avatarUrl,
                countryName = countryName,
                countryCode = countryCode,
                lastReadAt = lastReadAt,
            )
        }
}

@Serializable
data class GraphQLComment(
    val id: String = "",
    @SerialName("post_id") val postId: String = "",
    @SerialName("parent_id") val parentId: String? = null,
    @SerialName("author_id") val authorId: String = "",
    val body: String = "",
    @SerialName("like_count") val likeCount: Int = 0,
    @SerialName("liked_by_me") val likedByMe: Boolean = false,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
    val author: GraphQLAuthor? = null,
) {
    val toModel: PostComment
        get() {
            val rawParent = parentId?.trim()
            val normalizedParent = if (rawParent.isNullOrEmpty()) null else rawParent
            return PostComment(
                id = id,
                postId = postId,
                parentId = normalizedParent,
                authorId = authorId,
                body = body,
                likeCount = likeCount,
                likedByMe = likedByMe,
                createdAt = createdAt,
                updatedAt = updatedAt,
                author = author?.toModel,
            )
        }
}

@Serializable
data class GraphQLProfile(
    @SerialName("user_id") val userId: String = "",
    val email: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("country_name") val countryName: String? = null,
    @SerialName("country_code") val countryCode: String? = null,
    @SerialName("city_name") val cityName: String? = null,
    val bio: String? = null,
    @SerialName("account_status") val accountStatus: String? = null,
    @SerialName("deactivated_at") val deactivatedAt: String? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    val toModel: Profile
        get() = Profile(
            userId = userId,
            email = email,
            displayName = displayName,
            username = username,
            avatarUrl = avatarUrl,
            countryName = countryName,
            countryCode = countryCode,
            cityName = cityName,
            bio = bio,
            followersCount = null,
            followingCount = null,
            accountStatus = accountStatus,
            deactivatedAt = deactivatedAt,
            deletedAt = deletedAt,
            createdAt = createdAt ?: "",
            updatedAt = updatedAt ?: "",
        )
}

@Serializable
data class GraphQLMessage(
    val id: String = "",
    @SerialName("conversation_id") val conversationId: String = "",
    @SerialName("sender_id") val senderId: String = "",
    val body: String = "",
    @SerialName("media_type") val mediaType: String? = null,
    @SerialName("media_path") val mediaPath: String? = null,
    @SerialName("media_name") val mediaName: String? = null,
    @SerialName("media_mime") val mediaMime: String? = null,
    @SerialName("media_size") val mediaSize: Int? = null,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String? = null,
    val sender: GraphQLAuthor? = null,
) {
    val toModel: Message
        get() = Message(
            id = id,
            conversationId = conversationId,
            senderId = senderId,
            body = body,
            mediaType = mediaType,
            mediaPath = mediaPath,
            mediaUrl = null,
            mediaName = mediaName,
            createdAt = createdAt,
            updatedAt = updatedAt ?: createdAt,
            sender = sender?.toModelIfValid,
        )
}

@Serializable
data class GraphQLConversation(
    val id: String = "",
    @SerialName("is_direct") val isDirect: Boolean = true,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
    @SerialName("last_message_at") val lastMessageAt: String? = null,
    val members: List<GraphQLAuthor> = emptyList(),
    @SerialName("last_message") val lastMessage: GraphQLMessage? = null,
) {
    val toModel: Conversation
        get() = Conversation(
            id = id,
            isDirect = isDirect,
            createdAt = createdAt,
            updatedAt = updatedAt,
            lastMessageAt = lastMessageAt,
            members = members.mapNotNull { it.toModelIfValid },
            lastMessage = lastMessage?.toModel,
        )
}

@Serializable
data class GraphQLChannel(
    val id: String = "",
    @SerialName("owner_user_id") val ownerUserId: String = "",
    val name: String = "",
    val handle: String? = null,
    val about: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("cover_url") val coverUrl: String? = null,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
    val owner: GraphQLAuthor? = null,
    @SerialName("my_role") val myRole: String? = null,
    @SerialName("video_count") val videoCount: Int = 0,
) {
    val toModel: HubChannel
        get() = HubChannel(
            id = id,
            ownerUserId = ownerUserId,
            name = name,
            handle = handle,
            about = about,
            avatarUrl = avatarUrl,
            coverUrl = coverUrl,
            createdAt = createdAt,
            updatedAt = updatedAt,
            owner = owner?.toModel,
            myRole = ChannelMemberRole.fromRaw(myRole),
            videoCount = videoCount,
        )
}

@Serializable
data class GraphQLChannelMember(
    @SerialName("channel_id") val channelId: String = "",
    @SerialName("user_id") val userId: String = "",
    val role: String = "admin",
    @SerialName("invited_by") val invitedBy: String? = null,
    @SerialName("created_at") val createdAt: String = "",
    val profile: GraphQLAuthor? = null,
) {
    val toModel: ChannelMember
        get() = ChannelMember(
            channelId = channelId,
            userId = userId,
            role = ChannelMemberRole.fromRaw(role) ?: ChannelMemberRole.ADMIN,
            invitedBy = invitedBy,
            createdAt = createdAt,
            profile = profile?.toModel,
        )
}

@Serializable
data class GraphQLNotification(
    val id: String = "",
    @SerialName("user_id") val userId: String = "",
    @SerialName("actor_id") val actorId: String? = null,
    val type: String = "",
    @SerialName("entity_type") val entityType: String? = null,
    @SerialName("entity_id") val entityId: String? = null,
    @SerialName("read_at") val readAt: String? = null,
    @SerialName("created_at") val createdAt: String = "",
    val actor: GraphQLNotificationActor? = null,
) {
    val toModel: NotificationItem
        get() = NotificationItem(
            id = id,
            userId = userId,
            actorId = actorId,
            type = type,
            entityType = entityType,
            entityId = entityId,
            readAt = readAt,
            createdAt = createdAt,
            actor = actor?.toModel,
        )
}

@Serializable
data class GraphQLNotificationActor(
    @SerialName("user_id") val userId: String = "",
    @SerialName("display_name") val displayName: String? = null,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
) {
    val toModel: PostAuthor
        get() = PostAuthor(
            userId = userId,
            displayName = displayName,
            username = username,
            avatarUrl = avatarUrl,
        )
}
