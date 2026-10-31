package com.matterya.matterya.model

import java.time.Instant

data class NotificationItem(
    val id: String,
    val userId: String,
    val actorId: String? = null,
    val type: String,
    val entityType: String? = null,
    val entityId: String? = null,
    val readAt: String? = null,
    val createdAt: String = "",
    val actor: PostAuthor? = null,
) {
    val isUnread: Boolean
        get() {
            val read = readAt ?: return true
            return read.trim().isEmpty()
        }

    val isMessageType: Boolean get() = type.lowercase() == "message"

    val postId: String?
        get() {
            if (entityType?.lowercase() != "post") return null
            return entityId
        }

    val resolvedPostId: String?
        get() {
            val normalizedType = type.lowercase()
            val rawId = entityId?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            return when (normalizedType) {
                "like", "comment", "comment_like", "comment_reply", "reply", "post" -> rawId
                else -> if (entityType?.lowercase() == "post") rawId else null
            }
        }

    val conversationId: String?
        get() {
            val rawId = entityId?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            if (entityType?.lowercase() == "conversation") return rawId
            if (type.lowercase() == "message") return rawId
            return null
        }

    val actorUserId: String?
        get() {
            actorId?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            actor?.userId?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            if (entityType?.lowercase() == "user") {
                entityId?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            }
            return null
        }

    fun markedAsRead(at: String = Instant.now().toString()): NotificationItem =
        copy(readAt = at)
}

data class ExternalNewsItem(
    val id: String,
    val provider: String,
    val title: String,
    val url: String,
    val sourceName: String? = null,
    val publishedAt: String? = null,
    val countryCodes: List<String> = emptyList(),
    val countryNames: List<String> = emptyList(),
    val disasterTypes: List<String> = emptyList(),
    val themeNames: List<String> = emptyList(),
    val snippet: String? = null,
    val imageUrl: String? = null,
    val likeCount: Int = 0,
    val likedByMe: Boolean = false,
    val commentCount: Int = 0,
    val sharedPostCount: Int = 0,
)

data class ExternalNewsComment(
    val id: String,
    val newsItemId: String,
    val parentId: String? = null,
    val authorId: String,
    val body: String,
    val createdAt: String = "",
    val updatedAt: String = "",
    val author: PostAuthor? = null,
)

data class AdCreative(
    val id: String,
    val campaignId: String,
    val title: String? = null,
    val body: String? = null,
    val mediaKind: String,
    val mediaUrl: String,
    val clickUrl: String? = null,
    val ctaLabel: String? = null,
    val durationSeconds: Int = 0,
)

data class AdCampaign(
    val id: String,
    val name: String,
    val status: String,
    val placement: String,
    val targetCountryCodes: List<String> = emptyList(),
    val budgetCents: Int = 0,
    val dailyBudgetCents: Int = 0,
    val startAt: String? = null,
    val endAt: String? = null,
    val impressionCount: Int = 0,
    val clickCount: Int = 0,
    val creatives: List<AdCreative> = emptyList(),
)

data class AdSlot(
    val impressionToken: String,
    val skipAfterSeconds: Int,
    val campaign: AdCampaign,
    val creative: AdCreative,
)
