package com.matterya.matterya.data.news

import com.matterya.matterya.data.graphql.GraphQlClient
import com.matterya.matterya.model.CountryPost
import com.matterya.matterya.model.ExternalNewsComment
import com.matterya.matterya.model.ExternalNewsItem
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonArray

/** iOS `NewsService.swift` — GraphQL external news APIs. */
class NewsService(
    private val gql: GraphQlClient = GraphQlClient(),
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val newsFields = """
        id provider title url source_name published_at country_codes country_names
        disaster_types theme_names snippet image_url like_count liked_by_me
        comment_count shared_post_count
    """.trimIndent()

    private val commentFields = """
        id news_item_id parent_id author_id body created_at updated_at
        author { user_id display_name username avatar_url country_name country_code }
    """.trimIndent()

    suspend fun countryConflictUpdates(countryCode: String, limit: Int = 10): List<ExternalNewsItem> {
        val data = gql.request(
            """
            query(${'$'}country_code: String!, ${'$'}limit: Int) {
              countryConflictUpdates(country_code: ${'$'}country_code, limit: ${'$'}limit) { $newsFields }
            }
            """.trimIndent(),
            mapOf(
                "country_code" to JsonPrimitive(countryCode.uppercase()),
                "limit" to JsonPrimitive(limit),
            ),
        )
        val rows = data["countryConflictUpdates"]?.jsonArray ?: return emptyList()
        return rows.mapNotNull {
            runCatching { json.decodeFromJsonElement<ExternalNewsItem>(it) }.getOrNull()
        }
    }

    suspend fun item(newsItemId: String): ExternalNewsItem? {
        val data = gql.request(
            """
            query(${'$'}news_item_id: ID!) {
              externalNewsItem(news_item_id: ${'$'}news_item_id) { $newsFields }
            }
            """.trimIndent(),
            mapOf("news_item_id" to JsonPrimitive(newsItemId)),
        )
        val row = data["externalNewsItem"] ?: return null
        return runCatching { json.decodeFromJsonElement<ExternalNewsItem>(row) }.getOrNull()
    }

    suspend fun comments(newsItemId: String, limit: Int = 25): List<ExternalNewsComment> {
        val data = gql.request(
            """
            query(${'$'}news_item_id: ID!, ${'$'}limit: Int) {
              externalNewsComments(news_item_id: ${'$'}news_item_id, limit: ${'$'}limit) { $commentFields }
            }
            """.trimIndent(),
            mapOf(
                "news_item_id" to JsonPrimitive(newsItemId),
                "limit" to JsonPrimitive(limit),
            ),
        )
        val rows = data["externalNewsComments"]?.jsonArray ?: return emptyList()
        return rows.mapNotNull {
            runCatching { json.decodeFromJsonElement<ExternalNewsComment>(it) }.getOrNull()
        }
    }

    suspend fun addComment(
        newsItemId: String,
        body: String,
        parentId: String? = null,
    ): ExternalNewsComment {
        val vars = buildMap {
            put("news_item_id", JsonPrimitive(newsItemId))
            put("body", JsonPrimitive(body))
            if (parentId != null) put("parent_id", JsonPrimitive(parentId))
        }
        val data = gql.request(
            """
            mutation(${'$'}news_item_id: ID!, ${'$'}body: String!, ${'$'}parent_id: ID) {
              addExternalNewsComment(news_item_id: ${'$'}news_item_id, body: ${'$'}body, parent_id: ${'$'}parent_id) {
                $commentFields
              }
            }
            """.trimIndent(),
            vars,
        )
        val row = data["addExternalNewsComment"] ?: error("addExternalNewsComment failed")
        return json.decodeFromJsonElement(row)
    }

    suspend fun like(newsItemId: String): ExternalNewsItem {
        val data = gql.request(
            """
            mutation(${'$'}news_item_id: ID!) {
              likeExternalNews(news_item_id: ${'$'}news_item_id) { $newsFields }
            }
            """.trimIndent(),
            mapOf("news_item_id" to JsonPrimitive(newsItemId)),
        )
        return json.decodeFromJsonElement(data["likeExternalNews"]!!)
    }

    suspend fun unlike(newsItemId: String): ExternalNewsItem {
        val data = gql.request(
            """
            mutation(${'$'}news_item_id: ID!) {
              unlikeExternalNews(news_item_id: ${'$'}news_item_id) { $newsFields }
            }
            """.trimIndent(),
            mapOf("news_item_id" to JsonPrimitive(newsItemId)),
        )
        return json.decodeFromJsonElement(data["unlikeExternalNews"]!!)
    }

    suspend fun shareToCountry(newsItemId: String, body: String?): CountryPost {
        val data = gql.request(
            """
            mutation(${'$'}news_item_id: ID!, ${'$'}body: String) {
              shareExternalNewsToCountry(news_item_id: ${'$'}news_item_id, body: ${'$'}body, visibility: "country") {
                id title body media_type media_url thumb_url visibility like_count comment_count
                liked_by_me created_at updated_at author_id country_name country_code city_name
                author { user_id display_name username avatar_url country_name country_code }
              }
            }
            """.trimIndent(),
            buildMap {
                put("news_item_id", JsonPrimitive(newsItemId))
                if (body != null) put("body", JsonPrimitive(body))
            },
        )
        return json.decodeFromJsonElement(data["shareExternalNewsToCountry"]!!)
    }

    companion object {
        val shared by lazy { NewsService() }
    }
}
