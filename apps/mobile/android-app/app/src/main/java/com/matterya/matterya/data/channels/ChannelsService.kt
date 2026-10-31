package com.matterya.matterya.data.channels

import com.matterya.matterya.data.graphql.GqlOps
import com.matterya.matterya.data.graphql.GraphQlClient
import com.matterya.matterya.data.graphql.GraphQlException
import com.matterya.matterya.model.ChannelMember
import com.matterya.matterya.model.GraphQLChannel
import com.matterya.matterya.model.GraphQLChannelMember
import com.matterya.matterya.model.HubChannel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Hubs channels GraphQL — mirrors iOS `ChannelsService.swift`. */
class ChannelsService(
    private val gql: GraphQlClient = GraphQlClient(),
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    suspend fun myChannel(): HubChannel? {
        val data = gql.request(GqlOps.myChannel())
        val row = data["myChannel"] ?: return null
        return runCatching { json.decodeFromJsonElement<GraphQLChannel>(row).toModel }.getOrNull()
    }

    suspend fun channel(id: String): HubChannel? {
        val data = gql.request(
            GqlOps.channel(),
            mapOf("id" to JsonPrimitive(id)),
        )
        val row = data["channel"] ?: return null
        return runCatching { json.decodeFromJsonElement<GraphQLChannel>(row).toModel }.getOrNull()
    }

    suspend fun channelByOwner(userId: String): HubChannel? {
        val data = gql.request(
            GqlOps.channelByOwner(),
            mapOf("userId" to JsonPrimitive(userId)),
        )
        val row = data["channelByOwner"] ?: return null
        return runCatching { json.decodeFromJsonElement<GraphQLChannel>(row).toModel }.getOrNull()
    }

    suspend fun members(channelId: String): List<ChannelMember> {
        val data = gql.request(
            GqlOps.channelMembers(),
            mapOf("channelId" to JsonPrimitive(channelId)),
        )
        val rows = data["channelMembers"] as? JsonArray ?: return emptyList()
        return rows.mapNotNull {
            runCatching { json.decodeFromJsonElement<GraphQLChannelMember>(it).toModel }.getOrNull()
        }
    }

    suspend fun channelsIAdmin(): List<HubChannel> {
        val data = gql.request(GqlOps.channelsIAdmin())
        val rows = data["channelsIAdmin"] as? JsonArray ?: return emptyList()
        return rows.mapNotNull {
            runCatching { json.decodeFromJsonElement<GraphQLChannel>(it).toModel }.getOrNull()
        }
    }

    suspend fun createChannel(
        name: String,
        about: String? = null,
        avatarUrl: String? = null,
        coverUrl: String? = null,
        handle: String? = null,
    ): HubChannel {
        val input = buildJsonObject {
            put("name", name)
            if (!about.isNullOrEmpty()) put("about", about)
            if (!avatarUrl.isNullOrEmpty()) put("avatar_url", avatarUrl)
            if (!coverUrl.isNullOrEmpty()) put("cover_url", coverUrl)
            if (!handle.isNullOrEmpty()) put("handle", handle)
        }
        val data = gql.request(GqlOps.createChannel(), mapOf("input" to input))
        val row = data["createChannel"] ?: throw GraphQlException("createChannel failed")
        return json.decodeFromJsonElement<GraphQLChannel>(row).toModel
    }

    suspend fun updateChannel(
        id: String,
        name: String? = null,
        about: String? = null,
        avatarUrl: String? = null,
        coverUrl: String? = null,
        handle: String? = null,
    ): HubChannel {
        val input = buildJsonObject {
            if (name != null) put("name", name)
            if (about != null) put("about", about)
            if (avatarUrl != null) put("avatar_url", avatarUrl)
            if (coverUrl != null) put("cover_url", coverUrl)
            if (handle != null) put("handle", handle)
        }
        val data = gql.request(
            GqlOps.updateChannel(),
            mapOf(
                "id" to JsonPrimitive(id),
                "input" to input,
            ),
        )
        val row = data["updateChannel"] ?: throw GraphQlException("updateChannel failed")
        return json.decodeFromJsonElement<GraphQLChannel>(row).toModel
    }

    suspend fun addAdmin(channelId: String, userId: String): ChannelMember {
        val data = gql.request(
            GqlOps.addChannelAdmin(),
            mapOf(
                "channelId" to JsonPrimitive(channelId),
                "userId" to JsonPrimitive(userId),
            ),
        )
        val row = data["addChannelAdmin"] ?: throw GraphQlException("addChannelAdmin failed")
        return json.decodeFromJsonElement<GraphQLChannelMember>(row).toModel
    }

    suspend fun removeAdmin(channelId: String, userId: String): Boolean {
        val data = gql.request(
            GqlOps.removeChannelAdmin(),
            mapOf(
                "channelId" to JsonPrimitive(channelId),
                "userId" to JsonPrimitive(userId),
            ),
        )
        return data["removeChannelAdmin"]?.jsonPrimitive?.booleanOrNull == true ||
            data["removeChannelAdmin"]?.jsonPrimitive?.contentOrNull == "true"
    }

    suspend fun transferOwnership(channelId: String, newOwnerUserId: String): HubChannel {
        val data = gql.request(
            GqlOps.transferChannelOwnership(),
            mapOf(
                "channelId" to JsonPrimitive(channelId),
                "newOwner" to JsonPrimitive(newOwnerUserId),
            ),
        )
        val row = data["transferChannelOwnership"]
            ?: throw GraphQlException("transferChannelOwnership failed")
        return json.decodeFromJsonElement<GraphQLChannel>(row).toModel
    }

    suspend fun setPostHidden(postId: String, hidden: Boolean): Boolean {
        val data = gql.request(
            GqlOps.setChannelPostHidden(),
            mapOf(
                "postId" to JsonPrimitive(postId),
                "hidden" to JsonPrimitive(hidden),
            ),
        )
        return data["setChannelPostHidden"]?.jsonPrimitive?.booleanOrNull == true ||
            data["setChannelPostHidden"]?.jsonPrimitive?.contentOrNull == "true"
    }

    suspend fun deleteComment(commentId: String): Boolean {
        val data = gql.request(
            GqlOps.deleteChannelComment(),
            mapOf("commentId" to JsonPrimitive(commentId)),
        )
        return data["deleteChannelComment"]?.jsonPrimitive?.booleanOrNull == true ||
            data["deleteChannelComment"]?.jsonPrimitive?.contentOrNull == "true"
    }
}
