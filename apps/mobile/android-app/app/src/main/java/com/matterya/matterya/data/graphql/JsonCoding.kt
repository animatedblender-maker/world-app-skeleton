package com.matterya.matterya.data.graphql

import com.matterya.matterya.model.Conversation
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.Message
import com.matterya.matterya.model.PostAuthor
import com.matterya.matterya.model.Profile
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID

/** Mirrors iOS `JSONCoding.swift` — map GraphQL dict rows into models. */
object JsonCoding {
    val json = Json { ignoreUnknownKeys = true; isLenient = true }

    fun string(row: JsonObject, key: String): String? =
        row[key]?.jsonPrimitive?.contentOrNull

    fun int(row: JsonObject, key: String): Int =
        row[key]?.jsonPrimitive?.intOrNull ?: 0

    fun bool(row: JsonObject, key: String): Boolean =
        row[key]?.jsonPrimitive?.booleanOrNull ?: false

    fun countryPost(row: JsonObject): CountryPost = CountryPost(
        id = string(row, "id") ?: UUID.randomUUID().toString(),
        title = string(row, "title"),
        body = string(row, "body") ?: "",
        mediaType = string(row, "media_type"),
        mediaUrl = string(row, "media_url"),
        thumbUrl = string(row, "thumb_url"),
        mediaCaption = string(row, "media_caption"),
        sharedPostId = string(row, "shared_post_id"),
        visibility = string(row, "visibility") ?: "public",
        likeCount = int(row, "like_count"),
        commentCount = int(row, "comment_count"),
        viewCount = int(row, "view_count"),
        likedByMe = bool(row, "liked_by_me"),
        savedByMe = bool(row, "saved_by_me"),
        createdAt = string(row, "created_at") ?: "",
        updatedAt = string(row, "updated_at") ?: "",
        authorId = string(row, "author_id") ?: "",
        countryName = string(row, "country_name"),
        countryCode = string(row, "country_code"),
        cityName = string(row, "city_name"),
        author = postAuthor(row["author"]),
        linkUrl = string(row, "link_url"),
        linkTitle = string(row, "link_title"),
        externalRefType = string(row, "external_ref_type"),
        externalRefId = string(row, "external_ref_id"),
    )

    fun postAuthor(el: JsonElement?): PostAuthor? {
        val row = el?.jsonObject ?: return null
        val userId = string(row, "user_id") ?: return null
        return PostAuthor(
            userId = userId,
            displayName = string(row, "display_name"),
            username = string(row, "username"),
            avatarUrl = string(row, "avatar_url"),
            countryName = string(row, "country_name"),
            countryCode = string(row, "country_code"),
            lastReadAt = string(row, "last_read_at"),
        )
    }

    fun profile(el: JsonElement?): Profile? {
        val row = el?.jsonObject ?: return null
        val userId = string(row, "user_id") ?: return null
        return Profile(
            userId = userId,
            email = string(row, "email"),
            displayName = string(row, "display_name"),
            username = string(row, "username"),
            avatarUrl = string(row, "avatar_url"),
            countryName = string(row, "country_name"),
            countryCode = string(row, "country_code"),
            cityName = string(row, "city_name"),
            bio = string(row, "bio"),
            followersCount = row["followers_count"]?.jsonPrimitive?.intOrNull,
            followingCount = row["following_count"]?.jsonPrimitive?.intOrNull,
            accountStatus = string(row, "account_status"),
            deactivatedAt = string(row, "deactivated_at"),
            deletedAt = string(row, "deleted_at"),
            createdAt = string(row, "created_at") ?: "",
            updatedAt = string(row, "updated_at") ?: "",
        )
    }

    fun country(row: JsonObject): Country {
        val center = row["center"]?.jsonObject
        return Country(
            id = string(row, "id") ?: string(row, "iso") ?: UUID.randomUUID().toString(),
            name = string(row, "name") ?: "",
            iso = string(row, "iso") ?: "",
            continent = string(row, "continent"),
            centerLat = center?.get("lat")?.jsonPrimitive?.doubleOrNull,
            centerLng = center?.get("lng")?.jsonPrimitive?.doubleOrNull,
        )
    }

    fun message(row: JsonObject): Message = Message(
        id = string(row, "id") ?: UUID.randomUUID().toString(),
        conversationId = string(row, "conversation_id") ?: "",
        senderId = string(row, "sender_id") ?: "",
        body = string(row, "body") ?: "",
        mediaType = string(row, "media_type"),
        mediaPath = string(row, "media_path"),
        mediaUrl = string(row, "media_url"),
        mediaName = string(row, "media_name"),
        createdAt = string(row, "created_at") ?: "",
        updatedAt = string(row, "updated_at") ?: "",
        sender = postAuthor(row["sender"]),
    )

    fun conversation(row: JsonObject): Conversation {
        val members = row["members"]?.jsonArray
            ?.mapNotNull { postAuthor(it) }
            .orEmpty()
        val last = row["last_message"]?.jsonObject
        return Conversation(
            id = string(row, "id") ?: UUID.randomUUID().toString(),
            isDirect = bool(row, "is_direct").let { if (row["is_direct"] == null) true else it },
            createdAt = string(row, "created_at") ?: "",
            updatedAt = string(row, "updated_at") ?: "",
            lastMessageAt = string(row, "last_message_at"),
            members = members,
            lastMessage = last?.let { message(it) },
        )
    }
}
