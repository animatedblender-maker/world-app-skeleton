package com.matterya.matterya.data.ads

import com.matterya.matterya.data.graphql.GraphQlClient
import com.matterya.matterya.model.AdCampaign
import com.matterya.matterya.model.AdCreative
import com.matterya.matterya.model.AdSlot
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** GraphQL field selections — match iOS `AdsService.swift`. */
private object AdsGraphQlFields {
    const val campaign = """
    id advertiser_user_id name status placement target_country_codes
    budget_cents daily_budget_cents start_at end_at created_at updated_at
    impression_count click_count
    creatives {
      id campaign_id title body media_kind media_url click_url cta_label duration_seconds
      created_at updated_at
    }
    """

    const val creative = """
    id campaign_id title body media_kind media_url click_url cta_label duration_seconds
    created_at updated_at
    """
}

data class AdCampaignInput(
    val name: String,
    val placement: String,
    val status: String? = null,
    val targetCountryCodes: List<String>? = null,
    val budgetCents: Int? = null,
    val dailyBudgetCents: Int? = null,
    val startAt: String? = null,
    val endAt: String? = null,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("name", name)
        put("placement", placement)
        status?.let { put("status", it) }
        targetCountryCodes?.let { codes ->
            put(
                "target_country_codes",
                JsonArray(codes.map { JsonPrimitive(it) }),
            )
        }
        budgetCents?.let { put("budget_cents", it) }
        dailyBudgetCents?.let { put("daily_budget_cents", it) }
        startAt?.let { put("start_at", it) }
        endAt?.let { put("end_at", it) }
    }
}

data class AdCreativeInput(
    val title: String? = null,
    val body: String? = null,
    val mediaKind: String? = null,
    val mediaUrl: String,
    val clickUrl: String? = null,
    val ctaLabel: String? = null,
    val durationSeconds: Int? = null,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("media_url", mediaUrl)
        title?.let { put("title", it) }
        body?.let { put("body", it) }
        mediaKind?.let { put("media_kind", it) }
        clickUrl?.let { put("click_url", it) }
        ctaLabel?.let { put("cta_label", it) }
        durationSeconds?.let { put("duration_seconds", it) }
    }
}

/** iOS `AdsService.swift`. */
class AdsService(
    private val gql: GraphQlClient = GraphQlClient(),
) {
    suspend fun myCampaigns(): List<AdCampaign> {
        val query = """
        query {
          myAdCampaigns {
            ${AdsGraphQlFields.campaign}
          }
        }
        """.trimIndent()
        val data = gql.request(query)
        val rows = data["myAdCampaigns"]?.jsonArray ?: return emptyList()
        return rows.mapNotNull { parseCampaign(it) }
    }

    suspend fun createCampaign(input: AdCampaignInput): AdCampaign {
        val mutation = """
        mutation(${'$'}input: AdCampaignInput!) {
          createAdCampaign(input: ${'$'}input) {
            ${AdsGraphQlFields.campaign}
          }
        }
        """.trimIndent()
        val data = gql.request(mutation, mapOf("input" to input.toJson()))
        return parseCampaign(data["createAdCampaign"]!!)
            ?: error("createAdCampaign returned null")
    }

    suspend fun updateCampaign(campaignId: String, input: AdCampaignInput): AdCampaign {
        val mutation = """
        mutation(${'$'}campaignId: ID!, ${'$'}input: AdCampaignInput!) {
          updateAdCampaign(campaign_id: ${'$'}campaignId, input: ${'$'}input) {
            ${AdsGraphQlFields.campaign}
          }
        }
        """.trimIndent()
        val data = gql.request(
            mutation,
            mapOf(
                "campaignId" to JsonPrimitive(campaignId),
                "input" to input.toJson(),
            ),
        )
        return parseCampaign(data["updateAdCampaign"]!!)
            ?: error("updateAdCampaign returned null")
    }

    suspend fun createCreative(campaignId: String, input: AdCreativeInput): AdCreative {
        val mutation = """
        mutation(${'$'}campaignId: ID!, ${'$'}input: AdCreativeInput!) {
          createAdCreative(campaign_id: ${'$'}campaignId, input: ${'$'}input) {
            ${AdsGraphQlFields.creative}
          }
        }
        """.trimIndent()
        val data = gql.request(
            mutation,
            mapOf(
                "campaignId" to JsonPrimitive(campaignId),
                "input" to input.toJson(),
            ),
        )
        return parseCreative(data["createAdCreative"]!!)
            ?: error("createAdCreative returned null")
    }

    suspend fun updateCreative(creativeId: String, input: AdCreativeInput): AdCreative {
        val mutation = """
        mutation(${'$'}creativeId: ID!, ${'$'}input: AdCreativeInput!) {
          updateAdCreative(creative_id: ${'$'}creativeId, input: ${'$'}input) {
            ${AdsGraphQlFields.creative}
          }
        }
        """.trimIndent()
        val data = gql.request(
            mutation,
            mapOf(
                "creativeId" to JsonPrimitive(creativeId),
                "input" to input.toJson(),
            ),
        )
        return parseCreative(data["updateAdCreative"]!!)
            ?: error("updateAdCreative returned null")
    }

    suspend fun deleteCampaign(campaignId: String): Boolean {
        val mutation = """
        mutation(${'$'}campaignId: ID!) {
          deleteAdCampaign(campaign_id: ${'$'}campaignId)
        }
        """.trimIndent()
        val data = gql.request(mutation, mapOf("campaignId" to JsonPrimitive(campaignId)))
        return data["deleteAdCampaign"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull()
            ?: data["deleteAdCampaign"]?.toString()?.contains("true") == true
    }

    suspend fun serveVideoAd(
        placement: String,
        countryCode: String? = null,
        contentCountryCode: String? = null,
        postId: String? = null,
    ): AdSlot? {
        val query = """
        query ServeVideoAd(
          ${'$'}placement: String!
          ${'$'}country_code: String
          ${'$'}content_country_code: String
          ${'$'}post_id: ID
        ) {
          serveVideoAd(
            placement: ${'$'}placement
            country_code: ${'$'}country_code
            content_country_code: ${'$'}content_country_code
            post_id: ${'$'}post_id
          ) {
            impression_token
            skip_after_seconds
            campaign {
              ${AdsGraphQlFields.campaign}
            }
            creative {
              ${AdsGraphQlFields.creative}
            }
          }
        }
        """.trimIndent()
        val vars = buildMap<String, JsonElement> {
            put("placement", JsonPrimitive(placement))
            if (countryCode != null) put("country_code", JsonPrimitive(countryCode))
            if (contentCountryCode != null) put("content_country_code", JsonPrimitive(contentCountryCode))
            if (postId != null) put("post_id", JsonPrimitive(postId))
            else put("post_id", JsonNull)
        }
        val data = gql.request(query, vars)
        val slot = data["serveVideoAd"] ?: return null
        if (slot is JsonNull) return null
        return parseSlot(slot)
    }

    suspend fun logImpression(impressionToken: String): Boolean {
        val mutation = """
        mutation(${'$'}token: String!) {
          logAdImpression(impression_token: ${'$'}token) { ok }
        }
        """.trimIndent()
        val data = gql.request(mutation, mapOf("token" to JsonPrimitive(impressionToken)))
        return data["logAdImpression"]?.jsonObject?.get("ok")?.jsonPrimitive?.contentOrNull
            ?.toBooleanStrictOrNull() == true ||
            data["logAdImpression"]?.jsonObject?.get("ok")?.toString() == "true"
    }

    suspend fun logClick(impressionToken: String): Boolean {
        val mutation = """
        mutation(${'$'}token: String!) {
          logAdClick(impression_token: ${'$'}token) { ok }
        }
        """.trimIndent()
        val data = gql.request(mutation, mapOf("token" to JsonPrimitive(impressionToken)))
        return data["logAdClick"]?.jsonObject?.get("ok")?.jsonPrimitive?.contentOrNull
            ?.toBooleanStrictOrNull() == true ||
            data["logAdClick"]?.jsonObject?.get("ok")?.toString() == "true"
    }

    private fun parseSlot(el: JsonElement): AdSlot? {
        val o = el as? JsonObject ?: return null
        val campaign = parseCampaign(o["campaign"] ?: return null) ?: return null
        val creative = parseCreative(o["creative"] ?: return null) ?: return null
        return AdSlot(
            impressionToken = o.str("impression_token") ?: return null,
            skipAfterSeconds = o.int("skip_after_seconds") ?: 0,
            campaign = campaign,
            creative = creative,
        )
    }

    private fun parseCampaign(el: JsonElement): AdCampaign? {
        val o = el as? JsonObject ?: return null
        val creatives = o["creatives"]?.jsonArray?.mapNotNull { parseCreative(it) }.orEmpty()
        return AdCampaign(
            id = o.str("id") ?: return null,
            name = o.str("name") ?: "",
            status = o.str("status") ?: "",
            placement = o.str("placement") ?: "",
            targetCountryCodes = o["target_country_codes"]?.jsonArray
                ?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty(),
            budgetCents = o.int("budget_cents") ?: 0,
            dailyBudgetCents = o.int("daily_budget_cents") ?: 0,
            startAt = o.str("start_at"),
            endAt = o.str("end_at"),
            impressionCount = o.int("impression_count") ?: 0,
            clickCount = o.int("click_count") ?: 0,
            creatives = creatives,
        )
    }

    private fun parseCreative(el: JsonElement): AdCreative? {
        val o = el as? JsonObject ?: return null
        return AdCreative(
            id = o.str("id") ?: return null,
            campaignId = o.str("campaign_id") ?: "",
            title = o.str("title"),
            body = o.str("body"),
            mediaKind = o.str("media_kind") ?: "video",
            mediaUrl = o.str("media_url") ?: "",
            clickUrl = o.str("click_url"),
            ctaLabel = o.str("cta_label"),
            durationSeconds = o.int("duration_seconds") ?: 0,
        )
    }

    private fun JsonObject.str(key: String): String? =
        this[key]?.jsonPrimitive?.contentOrNull

    private fun JsonObject.int(key: String): Int? =
        this[key]?.jsonPrimitive?.intOrNull
            ?: this[key]?.jsonPrimitive?.contentOrNull?.toIntOrNull()

    companion object {
        val shared by lazy { AdsService() }
    }
}
