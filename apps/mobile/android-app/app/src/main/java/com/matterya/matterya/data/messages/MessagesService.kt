package com.matterya.matterya.data.messages

import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.graphql.GqlOps
import com.matterya.matterya.data.graphql.GraphQlClient
import com.matterya.matterya.data.graphql.GraphQlException
import com.matterya.matterya.model.Conversation
import com.matterya.matterya.model.GraphQLConversation
import com.matterya.matterya.model.GraphQLMessage
import com.matterya.matterya.model.Message
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/** Messages GraphQL — mirrors iOS `MessagesService.swift`. */
class MessagesService(
    private val gql: GraphQlClient = GraphQlClient(),
    private val auth: AuthService = AuthService.instance,
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private var cachedConversations: List<Conversation> = emptyList()
    private var cacheUserId: String? = null
    private val cachedMessagesByConversation = LinkedHashMap<String, List<Message>>()
    private val cachedPeerReadByConversation = LinkedHashMap<String, String>()

    fun cachedMessages(conversationId: String): List<Message>? {
        val id = conversationId.trim()
        if (id.isEmpty()) return null
        return cachedMessagesByConversation[id]
    }

    fun cachedPeerRead(conversationId: String): String? {
        val id = conversationId.trim()
        if (id.isEmpty()) return null
        return cachedPeerReadByConversation[id]
    }

    fun cachedConversation(conversationId: String): Conversation? {
        val id = conversationId.trim()
        if (id.isEmpty()) return null
        return cachedConversations.firstOrNull { it.id == id }
    }

    fun storeConversation(conversation: Conversation) {
        val id = conversation.id.trim()
        if (id.isEmpty()) return
        val idx = cachedConversations.indexOfFirst { it.id == id }
        cachedConversations = if (idx >= 0) {
            cachedConversations.toMutableList().also { it[idx] = conversation }
        } else {
            listOf(conversation) + cachedConversations
        }
        auth.currentUser?.id?.let { cacheUserId = it }
    }

    fun placeholderConversation(conversationId: String): Conversation {
        val id = conversationId.trim()
        return Conversation(
            id = id,
            isDirect = true,
            createdAt = "",
            updatedAt = "",
            lastMessageAt = null,
            members = emptyList(),
            lastMessage = null,
        )
    }

    fun storeMessages(
        messages: List<Message>,
        peerReadAt: String? = null,
        conversationId: String,
    ) {
        val id = conversationId.trim()
        if (id.isEmpty()) return
        cachedMessagesByConversation[id] = messages
        if (!peerReadAt.isNullOrEmpty()) {
            cachedPeerReadByConversation[id] = peerReadAt
        }
        while (cachedMessagesByConversation.size > 12) {
            val key = cachedMessagesByConversation.keys.firstOrNull { it != id } ?: break
            cachedMessagesByConversation.remove(key)
            cachedPeerReadByConversation.remove(key)
        }
    }

    suspend fun prefetchRecentThreads(limit: Int = 4) {
        val ids = cachedConversations.take(limit).map { it.id }
        for (id in ids) {
            if (cachedMessages(id) != null) continue
            runCatching { listMessages(id, limit = 40) }
        }
    }

    /**
     * @param inbox primary | requests | all | masquerade — mirrors iOS MessagesService.
     * Masquerade inbox never mixes with normal Messages welcome DMs.
     */
    suspend fun listConversations(limit: Int = 40, inbox: String = "primary"): List<Conversation> {
        val folder = inbox.trim().lowercase().ifEmpty { "primary" }
        runCatching { auth.ensureValidToken() }
        return try {
            val conversations = fetchConversations(limit, folder, retryingAuth = true)
            if (folder == "primary" || folder == "all") {
                auth.currentUser?.id?.let {
                    cacheUserId = it
                    cachedConversations = conversations
                }
                runCatching { prefetchRecentThreads(4) }
            } else {
                conversations.forEach { storeConversation(it) }
            }
            conversations
        } catch (e: Exception) {
            if (folder == "primary" || folder == "all") {
                val userId = auth.currentUser?.id
                if (userId != null && cacheUserId == userId && cachedConversations.isNotEmpty()) {
                    return cachedConversations
                }
            }
            throw e
        }
    }

    private suspend fun fetchConversations(
        limit: Int,
        inbox: String,
        retryingAuth: Boolean,
    ): List<Conversation> {
        return try {
            val data = gql.request(
                GqlOps.conversations(),
                mapOf(
                    "limit" to JsonPrimitive(limit),
                    "inbox" to JsonPrimitive(inbox),
                ),
            )
            filterConversations(mapConversations(data["conversations"]), inbox)
        } catch (e: Exception) {
            val message = e.message?.lowercase().orEmpty()
            val authFailure = message.contains("auth") ||
                message.contains("unauthenticated") ||
                message.contains("jwt") ||
                message.contains("token")
            if (retryingAuth && authFailure) {
                runCatching { auth.ensureValidToken() }
                return fetchConversations(limit, inbox, retryingAuth = false)
            }
            if (message.contains("inbox") || message.contains("unknown") || message.contains("surface")) {
                return fetchConversationsLegacy(limit, inbox)
            }
            throw e
        }
    }

    private suspend fun fetchConversationsLegacy(limit: Int, inbox: String): List<Conversation> {
        val data = gql.request(
            GqlOps.conversationsLegacy(),
            mapOf("limit" to JsonPrimitive(limit)),
        )
        return filterConversations(mapConversations(data["conversations"]), inbox)
    }

    private fun filterConversations(list: List<Conversation>, inbox: String): List<Conversation> {
        val folder = inbox.trim().lowercase()
        return when (folder) {
            "masquerade" -> list.filter { it.isMasqueradeSurface }
            "all" -> list
            "requests" -> list.filter { it.isRequest && !it.isMasqueradeSurface }
            else -> list.filter { !it.isMasqueradeSurface && !it.isRequest }
        }
    }

    suspend fun listMessages(conversationId: String, limit: Int = 50): List<Message> {
        val data = gql.request(
            GqlOps.messagesByConversation(),
            mapOf(
                "conversationId" to JsonPrimitive(conversationId),
                "limit" to JsonPrimitive(limit),
            ),
        )
        val messages = mapMessages(data["messagesByConversation"])
        storeMessages(messages, conversationId = conversationId)
        return messages
    }

    suspend fun startConversation(targetId: String): Conversation {
        val data = gql.request(
            GqlOps.startConversation(),
            mapOf("targetId" to JsonPrimitive(targetId)),
        )
        val row = data["startConversation"]
            ?: throw GraphQlException("startConversation failed")
        val conversation = json.decodeFromJsonElement<GraphQLConversation>(row).toModel
        storeConversation(conversation)
        return conversation
    }

    suspend fun getConversationById(conversationId: String): Conversation? {
        val data = gql.request(
            GqlOps.conversationById(),
            mapOf("conversationId" to JsonPrimitive(conversationId)),
        )
        val row = data["conversationById"] ?: return null
        val conversation = runCatching {
            json.decodeFromJsonElement<GraphQLConversation>(row).toModel
        }.getOrNull() ?: return null
        storeConversation(conversation)
        return conversation
    }

    suspend fun archiveConversation(conversationId: String): Boolean {
        val data = gql.request(
            GqlOps.archiveConversation(),
            mapOf("conversationId" to JsonPrimitive(conversationId)),
        )
        return data["archiveConversation"]?.jsonPrimitive?.booleanOrNull == true ||
            data["archiveConversation"]?.jsonPrimitive?.contentOrNull == "true"
    }

    suspend fun deleteConversation(conversationId: String): Boolean {
        val data = gql.request(
            GqlOps.deleteConversation(),
            mapOf("conversationId" to JsonPrimitive(conversationId)),
        )
        return data["deleteConversation"]?.jsonPrimitive?.booleanOrNull == true ||
            data["deleteConversation"]?.jsonPrimitive?.contentOrNull == "true"
    }

    suspend fun messagesUnreadCount(): Int {
        return try {
            val data = gql.request(GqlOps.messagesUnreadCount())
            data["messagesUnreadCount"]?.jsonPrimitive?.intOrNull ?: 0
        } catch (_: Exception) {
            0
        }
    }

    suspend fun deleteMessage(messageId: String): Boolean {
        val data = gql.request(
            GqlOps.deleteMessage(),
            mapOf("messageId" to JsonPrimitive(messageId)),
        )
        return data["deleteMessage"]?.jsonPrimitive?.booleanOrNull == true ||
            data["deleteMessage"]?.jsonPrimitive?.contentOrNull == "true"
    }

    suspend fun sendMessage(
        conversationId: String,
        body: String,
        mediaType: String? = null,
        mediaPath: String? = null,
        mediaName: String? = null,
        mediaMime: String? = null,
        mediaSize: Int? = null,
    ): Message {
        val vars = buildMap {
            put("conversationId", JsonPrimitive(conversationId))
            put("body", JsonPrimitive(body))
            if (mediaType != null) put("mediaType", JsonPrimitive(mediaType))
            if (mediaPath != null) put("mediaPath", JsonPrimitive(mediaPath))
            if (mediaName != null) put("mediaName", JsonPrimitive(mediaName))
            if (mediaMime != null) put("mediaMime", JsonPrimitive(mediaMime))
            if (mediaSize != null) put("mediaSize", JsonPrimitive(mediaSize))
        }
        val data = gql.request(GqlOps.sendMessage(), vars)
        val row = data["sendMessage"] ?: throw GraphQlException("sendMessage failed")
        return json.decodeFromJsonElement<GraphQLMessage>(row).toModel
    }

    private fun mapConversations(element: kotlinx.serialization.json.JsonElement?): List<Conversation> {
        val rows = element as? JsonArray ?: return emptyList()
        return rows.mapNotNull {
            runCatching { json.decodeFromJsonElement<GraphQLConversation>(it).toModel }.getOrNull()
        }
    }

    private fun mapMessages(element: kotlinx.serialization.json.JsonElement?): List<Message> {
        val rows = element as? JsonArray ?: return emptyList()
        return rows.mapNotNull {
            runCatching { json.decodeFromJsonElement<GraphQLMessage>(it).toModel }.getOrNull()
        }
    }

    companion object {
        val shared by lazy { MessagesService() }
    }
}
