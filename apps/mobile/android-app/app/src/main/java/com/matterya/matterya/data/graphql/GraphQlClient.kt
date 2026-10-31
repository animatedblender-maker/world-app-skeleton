package com.matterya.matterya.data.graphql

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class GraphQlException(message: String) : Exception(message)

/** Thin GraphQL client — mirrors iOS `GraphQLService`. */
class GraphQlClient(
    private val auth: AuthService = AuthService.instance,
    private val http: OkHttpClient = defaultClient,
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    /** Authenticated request (uses ensureValidToken when possible). */
    suspend fun request(
        query: String,
        variables: Map<String, JsonElement> = emptyMap(),
        timeoutMs: Long = 25_000,
        requireAuth: Boolean = true,
    ): JsonObject = withContext(Dispatchers.IO) {
        val token = if (requireAuth) {
            auth.ensureValidTokenOrNull()
        } else {
            auth.accessToken()
        }
        execute(query, variables, token, timeoutMs)
    }

    /** Unauthenticated / optional-auth request (mirrors iOS `gql.request`). */
    suspend fun requestPublic(
        query: String,
        variables: Map<String, JsonElement> = emptyMap(),
        timeoutMs: Long = 25_000,
    ): JsonObject = withContext(Dispatchers.IO) {
        execute(query, variables, token = null, timeoutMs = timeoutMs)
    }

    private fun execute(
        query: String,
        variables: Map<String, JsonElement>,
        token: String?,
        timeoutMs: Long,
    ): JsonObject {
        val body = buildJsonObject {
            put("query", query)
            putJsonObject("variables") {
                variables.forEach { (k, v) -> put(k, v) }
            }
        }.toString()

        val client = http.newBuilder()
            .callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .build()

        val reqBuilder = Request.Builder()
            .url(AppConfig.graphqlEndpoint)
            .post(body.toRequestBody(JSON))
            .header("content-type", "application/json")
            .header("accept", "application/json")
        if (token != null) reqBuilder.header("authorization", "Bearer $token")

        val response = client.newCall(reqBuilder.build()).execute()
        val raw = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            throw GraphQlException("GraphQL HTTP ${response.code}")
        }
        val root = try {
            json.parseToJsonElement(raw).jsonObject
        } catch (_: Exception) {
            throw GraphQlException("GraphQL non-JSON response")
        }
        val errors = root["errors"] as? JsonArray
        if (errors != null && errors.isNotEmpty()) {
            val first = errors.first().jsonObject
            val msg = first["message"]?.jsonPrimitive?.contentOrNull ?: "GraphQL error"
            val code = first["extensions"]?.jsonObject?.get("code")?.jsonPrimitive?.contentOrNull
            throw GraphQlException(if (code != null) "$msg (code=$code)" else msg)
        }
        return root["data"]?.jsonObject ?: JsonObject(emptyMap())
    }

    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()
        val defaultClient: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(25, TimeUnit.SECONDS)
            .writeTimeout(25, TimeUnit.SECONDS)
            .build()
    }
}

/**
 * All GraphQL documents used by Android services — copied from iOS Services.
 * postFields / postFieldsWithBookmarks match iOS `PostsService` exactly
 * (shared_post includes like_count + comment_count).
 */
object GqlOps {
    /** Exact iOS `postFields` selection. */
    const val POST_FIELDS = """
    id title body media_type media_url thumb_url shared_post_id
    shared_post {
      id title body media_type media_url thumb_url author_id
      like_count comment_count
      author { user_id display_name username avatar_url country_name country_code }
    }
    visibility like_count comment_count liked_by_me
    created_at updated_at author_id country_name country_code city_name
    author { user_id display_name username avatar_url country_name country_code }
    """

    /** Exact iOS `postFieldsWithBookmarks` (adds saved_by_me). */
    const val POST_FIELDS_WITH_BOOKMARKS = """
    id title body media_type media_url thumb_url shared_post_id
    shared_post {
      id title body media_type media_url thumb_url author_id
      like_count comment_count
      author { user_id display_name username avatar_url country_name country_code }
    }
    visibility like_count comment_count liked_by_me saved_by_me
    created_at updated_at author_id country_name country_code city_name
    author { user_id display_name username avatar_url country_name country_code }
    """

    const val COMMENT_FIELDS = """
    id post_id parent_id author_id body like_count liked_by_me created_at updated_at
    author { user_id display_name username avatar_url country_name country_code }
    """

    const val PROFILE_FIELDS = """
    user_id email display_name username avatar_url
    country_name country_code city_name bio
    created_at updated_at
    """

    const val PROFILE_FIELDS_FULL = """
    user_id email display_name username avatar_url
    country_name country_code city_name bio
    account_status deactivated_at deleted_at
    created_at updated_at
    """

    const val CHANNEL_FIELDS = """
    id owner_user_id name handle about avatar_url cover_url created_at updated_at
    my_role video_count
    owner { user_id display_name username avatar_url country_name country_code }
    """

    const val CHANNEL_MEMBER_FIELDS = """
    channel_id user_id role invited_by created_at
    profile { user_id display_name username avatar_url country_name country_code }
    """

    const val CONVERSATION_FIELDS = """
    id is_direct created_at updated_at last_message_at
    is_request request_status surface
    members {
      user_id display_name username avatar_url country_name country_code last_read_at is_verified
    }
    last_message {
      id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
      sender { user_id display_name username avatar_url country_name country_code is_verified }
    }
    """

    const val MESSAGE_FIELDS = """
    id conversation_id sender_id body media_type media_path media_name media_mime media_size created_at updated_at
    sender { user_id display_name username avatar_url country_name country_code is_verified }
    """

    // ── Posts ──────────────────────────────────────────────────────────

    fun recentPosts() = """
      query(${'$'}limit: Int, ${'$'}before: String) {
        recentPosts(limit: ${'$'}limit, before: ${'$'}before) { $POST_FIELDS }
      }
    """

    fun postsByCountry() = """
      query(${'$'}code: String!, ${'$'}limit: Int) {
        postsByCountry(country_code: ${'$'}code, limit: ${'$'}limit) { $POST_FIELDS }
      }
    """

    fun postsByAuthor() = """
      query PostsByAuthor(${'$'}authorId: ID!, ${'$'}limit: Int) {
        postsByAuthor(user_id: ${'$'}authorId, limit: ${'$'}limit) { $POST_FIELDS }
      }
    """

    fun searchPosts() = """
      query SearchPosts(${'$'}query: String!, ${'$'}limit: Int) {
        searchPosts(query: ${'$'}query, limit: ${'$'}limit) { $POST_FIELDS }
      }
    """

    fun postById() = """
      query(${'$'}postId: ID!) {
        postById(post_id: ${'$'}postId) { $POST_FIELDS }
      }
    """

    fun commentsByPost() = """
      query(${'$'}post_id: ID!, ${'$'}limit: Int) {
        commentsByPost(post_id: ${'$'}post_id, limit: ${'$'}limit) { $COMMENT_FIELDS }
      }
    """

    fun addComment() = """
      mutation(${'$'}post_id: ID!, ${'$'}body: String!, ${'$'}parent_id: ID) {
        addComment(post_id: ${'$'}post_id, body: ${'$'}body, parent_id: ${'$'}parent_id) {
          $COMMENT_FIELDS
        }
      }
    """

    fun likePost() = """
      mutation(${'$'}postId: ID!) { likePost(post_id: ${'$'}postId) { id } }
    """

    fun unlikePost() = """
      mutation(${'$'}postId: ID!) { unlikePost(post_id: ${'$'}postId) { id } }
    """

    fun createPost() = """
      mutation(${'$'}input: CreatePostInput!) {
        createPost(input: ${'$'}input) { $POST_FIELDS }
      }
    """

    fun updatePost() = """
      mutation(${'$'}postId: ID!, ${'$'}input: UpdatePostInput!) {
        updatePost(post_id: ${'$'}postId, input: ${'$'}input) { $POST_FIELDS }
      }
    """

    fun deletePost() = """
      mutation(${'$'}postId: ID!) { deletePost(post_id: ${'$'}postId) }
    """

    fun reportPost() = """
      mutation(${'$'}postId: ID!, ${'$'}reason: String!) {
        reportPost(post_id: ${'$'}postId, reason: ${'$'}reason)
      }
    """

    fun savedPosts() = """
      query SavedPosts(${'$'}limit: Int) {
        savedPosts(limit: ${'$'}limit) { $POST_FIELDS_WITH_BOOKMARKS }
      }
    """

    fun savePost() = """
      mutation(${'$'}postId: ID!) {
        savePost(post_id: ${'$'}postId) { $POST_FIELDS_WITH_BOOKMARKS }
      }
    """

    fun unsavePost() = """
      mutation(${'$'}postId: ID!) {
        unsavePost(post_id: ${'$'}postId) { $POST_FIELDS_WITH_BOOKMARKS }
      }
    """

    fun likeComment() = """
      mutation(${'$'}commentId: ID!) {
        likeComment(comment_id: ${'$'}commentId) { $COMMENT_FIELDS }
      }
    """

    fun unlikeComment() = """
      mutation(${'$'}commentId: ID!) {
        unlikeComment(comment_id: ${'$'}commentId) { $COMMENT_FIELDS }
      }
    """

    // ── Profile ────────────────────────────────────────────────────────

    fun meProfile() = """
      query MeProfile {
        meProfile { $PROFILE_FIELDS_FULL }
      }
    """

    fun updateProfile() = """
      mutation UpdateProfile(${'$'}input: UpdateProfileInput!) {
        updateProfile(input: ${'$'}input) {
          user_id email display_name username avatar_url
          country_name country_code city_name bio
          account_status
          created_at updated_at
        }
      }
    """

    fun countries() = """
      query Countries {
        countries {
          countries { id name iso continent center { lat lng } }
        }
      }
    """

    fun detectLocation() = """
      mutation DetectLocation(${'$'}lat: Float!, ${'$'}lng: Float!) {
        detectLocation(lat: ${'$'}lat, lng: ${'$'}lng) {
          countryCode
          countryName
          cityName
          source
        }
      }
    """

    fun deactivateAccount() = """
      mutation DeactivateAccount {
        deactivateAccount { ok action message account_status }
      }
    """

    fun reactivateAccount() = """
      mutation ReactivateAccount {
        reactivateAccount { ok action message account_status }
      }
    """

    fun deleteAccount() = """
      mutation DeleteAccount(${'$'}confirmation: String!) {
        deleteAccount(confirmation: ${'$'}confirmation) { ok action message account_status }
      }
    """

    fun profileByUsername() = """
      query ProfileByUsername(${'$'}username: String!) {
        profileByUsername(username: ${'$'}username) {
          user_id email display_name username avatar_url
          country_name country_code city_name bio created_at updated_at
        }
      }
    """

    fun searchProfiles() = """
      query SearchProfiles(${'$'}query: String!, ${'$'}limit: Int) {
        searchProfiles(query: ${'$'}query, limit: ${'$'}limit) {
          user_id email display_name username avatar_url
          country_name country_code city_name bio created_at updated_at
        }
      }
    """

    fun browseProfiles() = """
      query BrowseProfiles(${'$'}limit: Int, ${'$'}offset: Int) {
        browseProfiles(limit: ${'$'}limit, offset: ${'$'}offset) {
          user_id email display_name username avatar_url
          country_name country_code city_name bio created_at updated_at
        }
      }
    """

    fun profileById() = """
      query ProfileById(${'$'}user_id: ID!) {
        profileById(user_id: ${'$'}user_id) {
          user_id email display_name username avatar_url
          country_name country_code city_name bio created_at updated_at
        }
      }
    """

    fun globalStats() = """
      query GlobalStats {
        globalStats { totalUsers onlineNow ttlSeconds computedAt }
      }
    """

    fun countryStats() = """
      query CountryStats(${'$'}iso: String!) {
        countryStats(iso: ${'$'}iso) {
          iso name totalUsers onlineNow
        }
      }
    """

    // ── Follow ─────────────────────────────────────────────────────────

    fun followCounts() = """
      query FollowCounts(${'$'}userId: ID!) {
        followCounts(user_id: ${'$'}userId) { followers following }
      }
    """

    fun isFollowing() = """
      query(${'$'}target: ID!) { isFollowing(user_id: ${'$'}target) }
    """

    fun followingIds() = """
      query { followingIds }
    """

    fun followUser() = """
      mutation(${'$'}target: ID!) { followUser(target_id: ${'$'}target) }
    """

    fun unfollowUser() = """
      mutation(${'$'}target: ID!) { unfollowUser(target_id: ${'$'}target) }
    """

    // ── Messages ───────────────────────────────────────────────────────

    fun conversations() = """
      query Conversations(${'$'}limit: Int, ${'$'}inbox: String) {
        conversations(limit: ${'$'}limit, inbox: ${'$'}inbox) { $CONVERSATION_FIELDS }
      }
    """

    fun conversationsLegacy() = """
      query Conversations(${'$'}limit: Int) {
        conversations(limit: ${'$'}limit) { $CONVERSATION_FIELDS }
      }
    """

    fun messagesByConversation() = """
      query MessagesByConversation(${'$'}conversationId: ID!, ${'$'}limit: Int) {
        messagesByConversation(conversation_id: ${'$'}conversationId, limit: ${'$'}limit) {
          $MESSAGE_FIELDS
        }
      }
    """

    fun startConversation() = """
      mutation StartConversation(${'$'}targetId: ID!) {
        startConversation(target_id: ${'$'}targetId) {
          id is_direct created_at updated_at last_message_at
          members {
            user_id display_name username avatar_url country_name country_code last_read_at
          }
          last_message {
            id conversation_id sender_id body media_type media_path media_name created_at updated_at
            sender { user_id display_name username avatar_url country_name country_code }
          }
        }
      }
    """

    fun conversationById() = """
      query ConversationById(${'$'}conversationId: ID!) {
        conversationById(conversation_id: ${'$'}conversationId) { $CONVERSATION_FIELDS }
      }
    """

    fun archiveConversation() = """
      mutation ArchiveConversation(${'$'}conversationId: ID!) {
        archiveConversation(conversation_id: ${'$'}conversationId)
      }
    """

    fun deleteConversation() = """
      mutation DeleteConversation(${'$'}conversationId: ID!) {
        deleteConversation(conversation_id: ${'$'}conversationId)
      }
    """

    fun messagesUnreadCount() = """
      query { messagesUnreadCount }
    """

    fun deleteMessage() = """
      mutation DeleteMessage(${'$'}messageId: ID!) {
        deleteMessage(message_id: ${'$'}messageId)
      }
    """

    fun sendMessage() = """
      mutation SendMessage(
        ${'$'}conversationId: ID!,
        ${'$'}body: String!,
        ${'$'}mediaType: String,
        ${'$'}mediaPath: String,
        ${'$'}mediaName: String,
        ${'$'}mediaMime: String,
        ${'$'}mediaSize: Int
      ) {
        sendMessage(
          conversation_id: ${'$'}conversationId
          body: ${'$'}body
          media_type: ${'$'}mediaType
          media_path: ${'$'}mediaPath
          media_name: ${'$'}mediaName
          media_mime: ${'$'}mediaMime
          media_size: ${'$'}mediaSize
        ) { $MESSAGE_FIELDS }
      }
    """

    // ── Notifications ──────────────────────────────────────────────────

    fun notifications() = """
      query Notifications(${'$'}limit: Int) {
        notifications(limit: ${'$'}limit) {
          id user_id actor_id type entity_type entity_id read_at created_at
          actor { user_id display_name username avatar_url }
        }
      }
    """

    fun notificationsUnreadCount() = """
      query { notificationsUnreadCount }
    """

    fun markNotificationRead() = """
      mutation(${'$'}id: ID!) { markNotificationRead(id: ${'$'}id) }
    """

    fun markAllNotificationsRead() = """
      mutation { markAllNotificationsRead }
    """

    // ── Channels ───────────────────────────────────────────────────────

    fun myChannel() = """
      query { myChannel { $CHANNEL_FIELDS } }
    """

    fun channel() = """
      query(${'$'}id: ID!) { channel(id: ${'$'}id) { $CHANNEL_FIELDS } }
    """

    fun channelByOwner() = """
      query(${'$'}userId: ID!) {
        channelByOwner(user_id: ${'$'}userId) { $CHANNEL_FIELDS }
      }
    """

    fun channelMembers() = """
      query(${'$'}channelId: ID!) {
        channelMembers(channel_id: ${'$'}channelId) { $CHANNEL_MEMBER_FIELDS }
      }
    """

    fun channelsIAdmin() = """
      query { channelsIAdmin { $CHANNEL_FIELDS } }
    """

    fun createChannel() = """
      mutation(${'$'}input: CreateChannelInput!) {
        createChannel(input: ${'$'}input) { $CHANNEL_FIELDS }
      }
    """

    fun updateChannel() = """
      mutation(${'$'}id: ID!, ${'$'}input: UpdateChannelInput!) {
        updateChannel(id: ${'$'}id, input: ${'$'}input) { $CHANNEL_FIELDS }
      }
    """

    fun addChannelAdmin() = """
      mutation(${'$'}channelId: ID!, ${'$'}userId: ID!) {
        addChannelAdmin(channel_id: ${'$'}channelId, user_id: ${'$'}userId) {
          $CHANNEL_MEMBER_FIELDS
        }
      }
    """

    fun removeChannelAdmin() = """
      mutation(${'$'}channelId: ID!, ${'$'}userId: ID!) {
        removeChannelAdmin(channel_id: ${'$'}channelId, user_id: ${'$'}userId)
      }
    """

    fun transferChannelOwnership() = """
      mutation(${'$'}channelId: ID!, ${'$'}newOwner: ID!) {
        transferChannelOwnership(channel_id: ${'$'}channelId, new_owner_user_id: ${'$'}newOwner) {
          $CHANNEL_FIELDS
        }
      }
    """

    fun setChannelPostHidden() = """
      mutation(${'$'}postId: ID!, ${'$'}hidden: Boolean!) {
        setChannelPostHidden(post_id: ${'$'}postId, hidden: ${'$'}hidden)
      }
    """

    fun deleteChannelComment() = """
      mutation(${'$'}commentId: ID!) {
        deleteChannelComment(comment_id: ${'$'}commentId)
      }
    """
}
