package com.matterya.matterya.data.posts

import com.matterya.matterya.data.graphql.GqlOps
import com.matterya.matterya.data.graphql.GraphQlClient
import com.matterya.matterya.data.graphql.GraphQlException
import com.matterya.matterya.model.AccountActionResult
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.CountryStats
import com.matterya.matterya.model.DetectedLocation
import com.matterya.matterya.model.GlobalStats
import com.matterya.matterya.model.GraphQLProfile
import com.matterya.matterya.model.Profile
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Profile GraphQL — mirrors iOS `ProfileService.swift`. */
class ProfileService(
    private val gql: GraphQlClient = GraphQlClient(),
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    @Volatile private var countriesCache: List<Country>? = null

    suspend fun countries(): List<Country> {
        countriesCache?.let { return it }
        return try {
            val mapped = fetchCountries(authenticated = false)
            countriesCache = mapped
            mapped
        } catch (_: Exception) {
            val mapped = fetchCountries(authenticated = true)
            countriesCache = mapped
            mapped
        }
    }

    private suspend fun fetchCountries(authenticated: Boolean): List<Country> {
        val data = if (authenticated) {
            gql.request(GqlOps.countries())
        } else {
            gql.requestPublic(GqlOps.countries())
        }
        val outer = data["countries"]?.jsonObject ?: return emptyList()
        val rows = outer["countries"] as? JsonArray ?: return emptyList()
        return rows.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val id = obj["id"]?.jsonPrimitive?.contentOrNull
                ?: obj["id"]?.jsonPrimitive?.intOrNull?.toString()
                ?: return@mapNotNull null
            val name = obj["name"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val iso = obj["iso"]?.jsonPrimitive?.contentOrNull?.uppercase() ?: return@mapNotNull null
            val continent = obj["continent"]?.jsonPrimitive?.contentOrNull
            val center = obj["center"]?.jsonObject
            Country(
                id = id,
                name = name,
                iso = iso,
                continent = continent,
                centerLat = center?.get("lat")?.jsonPrimitive?.doubleOrNull,
                centerLng = center?.get("lng")?.jsonPrimitive?.doubleOrNull,
            )
        }.sortedBy { it.name }
    }

    suspend fun detectLocation(lat: Double, lng: Double): DetectedLocation {
        val data = gql.request(
            GqlOps.detectLocation(),
            mapOf(
                "lat" to JsonPrimitive(lat),
                "lng" to JsonPrimitive(lng),
            ),
        )
        val row = data["detectLocation"]?.jsonObject
            ?: throw GraphQlException("detectLocation failed")
        return DetectedLocation(
            countryCode = row["countryCode"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            countryName = row["countryName"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            cityName = row["cityName"]?.jsonPrimitive?.contentOrNull,
            source = row["source"]?.jsonPrimitive?.contentOrNull.orEmpty(),
        )
    }

    suspend fun meProfile(): Profile? {
        val data = gql.request(GqlOps.meProfile())
        val row = data["meProfile"] ?: return null
        return runCatching { json.decodeFromJsonElement<GraphQLProfile>(row).toModel }.getOrNull()
    }

    suspend fun deactivateAccount(): AccountActionResult {
        val data = gql.request(GqlOps.deactivateAccount())
        return parseAccountAction(data["deactivateAccount"]?.jsonObject)
    }

    suspend fun reactivateAccount(): AccountActionResult {
        val data = gql.request(GqlOps.reactivateAccount())
        return parseAccountAction(data["reactivateAccount"]?.jsonObject)
    }

    /** `confirmation` must be `"DELETE"` or the account username. */
    suspend fun deleteAccount(confirmation: String): AccountActionResult {
        val data = gql.request(
            GqlOps.deleteAccount(),
            mapOf("confirmation" to JsonPrimitive(confirmation)),
        )
        return parseAccountAction(data["deleteAccount"]?.jsonObject)
    }

    suspend fun updateProfile(
        displayName: String? = null,
        username: String? = null,
        countryName: String? = null,
        countryCode: String? = null,
        cityName: String? = null,
        bio: String? = null,
        avatarUrl: String? = null,
    ): Profile {
        val input = buildJsonObject {
            if (displayName != null) put("display_name", displayName)
            if (username != null) put("username", username)
            if (countryName != null) put("country_name", countryName)
            if (countryCode != null) put("country_code", countryCode)
            if (cityName != null) put("city_name", cityName)
            if (bio != null) put("bio", bio)
            if (avatarUrl != null) put("avatar_url", avatarUrl)
        }
        if (input.isEmpty()) throw GraphQlException("Nothing to update.")
        val data = gql.request(
            GqlOps.updateProfile(),
            mapOf("input" to input),
        )
        val row = data["updateProfile"] ?: throw GraphQlException("updateProfile failed")
        return json.decodeFromJsonElement<GraphQLProfile>(row).toModel
    }

    suspend fun profileByUsername(username: String): Profile? {
        val vars = mapOf("username" to JsonPrimitive(username))
        val data = try {
            gql.requestPublic(GqlOps.profileByUsername(), vars)
        } catch (_: Exception) {
            gql.request(GqlOps.profileByUsername(), vars)
        }
        val row = data["profileByUsername"] ?: return null
        return runCatching { json.decodeFromJsonElement<GraphQLProfile>(row).toModel }.getOrNull()
    }

    suspend fun searchProfiles(query: String, limit: Int = 20): List<Profile> {
        val data = gql.request(
            GqlOps.searchProfiles(),
            mapOf(
                "query" to JsonPrimitive(query),
                "limit" to JsonPrimitive(limit),
            ),
        )
        return mapProfiles(data["searchProfiles"]).let { rankProfiles(it, query, limit) }
    }

    suspend fun browseProfiles(limit: Int = 30, offset: Int = 0): List<Profile> {
        val data = gql.request(
            GqlOps.browseProfiles(),
            mapOf(
                "limit" to JsonPrimitive(limit),
                "offset" to JsonPrimitive(offset),
            ),
        )
        return mapProfiles(data["browseProfiles"])
    }

    suspend fun profileById(userId: String): Profile? {
        val vars = mapOf("user_id" to JsonPrimitive(userId))
        val data = try {
            gql.requestPublic(GqlOps.profileById(), vars)
        } catch (_: Exception) {
            gql.request(GqlOps.profileById(), vars)
        }
        val row = data["profileById"] ?: return null
        return runCatching { json.decodeFromJsonElement<GraphQLProfile>(row).toModel }.getOrNull()
    }

    suspend fun globalStats(): GlobalStats {
        val data = gql.request(GqlOps.globalStats())
        val row = data["globalStats"]?.jsonObject
            ?: throw GraphQlException("globalStats failed")
        return GlobalStats(
            totalUsers = row["totalUsers"]?.jsonPrimitive?.intOrNull ?: 0,
            onlineUsers = row["onlineNow"]?.jsonPrimitive?.intOrNull ?: 0,
        )
    }

    suspend fun countryStats(code: String): CountryStats {
        val data = gql.request(
            GqlOps.countryStats(),
            mapOf("iso" to JsonPrimitive(code.uppercase())),
        )
        val row = data["countryStats"]?.jsonObject
            ?: throw GraphQlException("countryStats failed")
        return CountryStats(
            countryCode = row["iso"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            totalUsers = row["totalUsers"]?.jsonPrimitive?.intOrNull ?: 0,
            onlineUsers = row["onlineNow"]?.jsonPrimitive?.intOrNull ?: 0,
        )
    }

    private fun parseAccountAction(obj: JsonObject?): AccountActionResult {
        obj ?: throw GraphQlException("Account action failed")
        val okPrim = obj["ok"]?.jsonPrimitive
        val ok = okPrim?.booleanOrNull
            ?: (okPrim?.contentOrNull == "true")
            ?: false
        return AccountActionResult(
            ok = ok,
            action = obj["action"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            message = obj["message"]?.jsonPrimitive?.contentOrNull,
            accountStatus = obj["account_status"]?.jsonPrimitive?.contentOrNull ?: "active",
        )
    }

    private fun mapProfiles(element: kotlinx.serialization.json.JsonElement?): List<Profile> {
        val rows = element as? JsonArray ?: return emptyList()
        return rows.mapNotNull {
            runCatching { json.decodeFromJsonElement<GraphQLProfile>(it).toModel }.getOrNull()
        }
    }

    /** Lightweight local rank (iOS uses MatteryaSearchEngine). */
    private fun rankProfiles(profiles: List<Profile>, query: String, limit: Int): List<Profile> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return profiles.take(limit)
        return profiles.sortedBy { p ->
            val name = p.displayName?.lowercase().orEmpty()
            val user = p.username?.lowercase().orEmpty()
            when {
                user == q || name == q -> 0
                user.startsWith(q) || name.startsWith(q) -> 1
                user.contains(q) || name.contains(q) -> 2
                else -> 3
            }
        }.take(limit)
    }
}
