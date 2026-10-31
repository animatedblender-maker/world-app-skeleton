package com.matterya.matterya.data.notifications

import com.matterya.matterya.data.graphql.GqlOps
import com.matterya.matterya.data.graphql.GraphQlClient
import com.matterya.matterya.model.GraphQLNotification
import com.matterya.matterya.model.NotificationItem
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/** Notifications GraphQL — mirrors iOS `NotificationsService.swift`. */
class NotificationsService(
    private val gql: GraphQlClient = GraphQlClient(),
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    suspend fun list(limit: Int = 40): List<NotificationItem> {
        return try {
            val data = gql.request(
                GqlOps.notifications(),
                mapOf("limit" to JsonPrimitive(limit)),
            )
            val rows = data["notifications"] as? JsonArray ?: return emptyList()
            rows.mapNotNull {
                runCatching { json.decodeFromJsonElement<GraphQLNotification>(it).toModel }.getOrNull()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun unreadCount(): Int {
        return try {
            val data = gql.request(GqlOps.notificationsUnreadCount())
            data["notificationsUnreadCount"]?.jsonPrimitive?.intOrNull ?: 0
        } catch (_: Exception) {
            0
        }
    }

    suspend fun markRead(id: String) {
        gql.request(
            GqlOps.markNotificationRead(),
            mapOf("id" to JsonPrimitive(id)),
        )
    }

    suspend fun markAllRead() {
        gql.request(GqlOps.markAllNotificationsRead())
    }

    companion object {
        val shared by lazy { NotificationsService() }
    }
}
