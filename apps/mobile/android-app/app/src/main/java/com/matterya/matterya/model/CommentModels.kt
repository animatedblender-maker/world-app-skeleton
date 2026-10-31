package com.matterya.matterya.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PostComment(
    val id: String = "",
    @SerialName("post_id") val postId: String = "",
    @SerialName("parent_id") val parentId: String? = null,
    @SerialName("author_id") val authorId: String = "",
    val body: String = "",
    @SerialName("like_count") val likeCount: Int = 0,
    @SerialName("liked_by_me") val likedByMe: Boolean = false,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
    val author: PostAuthor? = null,
) {
    val authorDisplayName: String
        get() = ContentSanitizer.displayName(
            displayName = author?.displayName,
            username = author?.username,
        )

    fun withParentId(parentId: String?): PostComment = copy(parentId = parentId)

    fun withPostAndParent(postId: String, parentId: String?): PostComment =
        copy(postId = postId, parentId = parentId)

    /** Reassign the speaker while keeping comment content / engagement. */
    fun withAuthor(authorId: String, author: PostAuthor?): PostComment =
        copy(authorId = authorId, author = author)
}
