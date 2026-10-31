package com.matterya.matterya.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class ChannelMemberRole {
    @SerialName("owner")
    OWNER,

    @SerialName("admin")
    ADMIN,
    ;

    val isStaff: Boolean get() = this == OWNER || this == ADMIN

    val displayTitle: String
        get() = when (this) {
            OWNER -> "Creator"
            ADMIN -> "Admin"
        }

    val rawValue: String
        get() = when (this) {
            OWNER -> "owner"
            ADMIN -> "admin"
        }

    companion object {
        fun fromRaw(raw: String?): ChannelMemberRole? = when (raw?.trim()?.lowercase()) {
            "owner" -> OWNER
            "admin" -> ADMIN
            else -> null
        }
    }
}

data class HubChannel(
    val id: String,
    val ownerUserId: String,
    val name: String,
    val handle: String? = null,
    val about: String? = null,
    val avatarUrl: String? = null,
    /** Wide banner / cover image on the channel page (separate from avatar). */
    val coverUrl: String? = null,
    val createdAt: String = "",
    val updatedAt: String = "",
    val owner: PostAuthor? = null,
    val myRole: ChannelMemberRole? = null,
    val videoCount: Int = 0,
) {
    val isStaff: Boolean get() = myRole?.isStaff == true
    val isOwner: Boolean get() = myRole == ChannelMemberRole.OWNER
}

data class ChannelMember(
    val channelId: String,
    val userId: String,
    val role: ChannelMemberRole,
    val invitedBy: String? = null,
    val createdAt: String = "",
    val profile: PostAuthor? = null,
) {
    val id: String get() = "$channelId:$userId"
}
