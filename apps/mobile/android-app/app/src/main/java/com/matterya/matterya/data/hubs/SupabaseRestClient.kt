package com.matterya.matterya.data.hubs

import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * Thin Supabase PostgREST client — iOS `SupabaseRESTClient` (embedded in StreamingHubService).
 */
class SupabaseRestClient(
    private val auth: AuthService = AuthService.instance,
    private val http: OkHttpClient = defaultClient,
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val base = "${AppConfig.supabaseURL}/rest/v1"

    suspend fun select(table: String, filters: Map<String, String>): JsonArray =
        request("GET", table, filters = filters)

    suspend fun insert(table: String, rows: List<Map<String, JsonElement>>): JsonArray =
        request(
            method = "POST",
            path = table,
            query = mapOf("select" to "*"),
            body = rowsToJson(rows),
            prefer = "return=representation",
        )

    suspend fun upsert(
        table: String,
        rows: List<Map<String, JsonElement>>,
        onConflict: String,
    ): JsonArray =
        request(
            method = "POST",
            path = table,
            query = mapOf("select" to "*", "on_conflict" to onConflict),
            body = rowsToJson(rows),
            prefer = "return=representation,resolution=merge-duplicates",
        )

    suspend fun patch(
        table: String,
        filters: Map<String, String>,
        body: Map<String, JsonElement>,
    ): JsonArray =
        request(
            method = "PATCH",
            path = table,
            filters = filters,
            query = mapOf("select" to "*"),
            body = mapToJson(body),
            prefer = "return=representation",
        )

    suspend fun patchVoid(
        table: String,
        filters: Map<String, String>,
        body: Map<String, JsonElement>,
    ) {
        request(
            method = "PATCH",
            path = table,
            filters = filters,
            body = mapToJson(body),
        )
    }

    suspend fun delete(table: String, filters: Map<String, String>) {
        request(method = "DELETE", path = table, filters = filters)
    }

    /** Public anon GET (no user JWT) — used for presence. */
    suspend fun selectPublic(table: String, filters: Map<String, String>): JsonArray =
        withContext(Dispatchers.IO) {
            val url = buildUrl(table, filters, emptyMap())
            val req = Request.Builder()
                .url(url)
                .get()
                .header("apikey", AppConfig.supabaseAnonKey)
                .header("Authorization", "Bearer ${AppConfig.supabaseAnonKey}")
                .header("Accept", "application/json")
                .build()
            val response = http.newCall(req).execute()
            val raw = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw SupabaseRestException.Http(response.code, raw.ifEmpty { "Request failed." })
            }
            if (raw.isBlank()) return@withContext JsonArray(emptyList())
            json.parseToJsonElement(raw) as? JsonArray ?: JsonArray(emptyList())
        }

    private suspend fun request(
        method: String,
        path: String,
        filters: Map<String, String> = emptyMap(),
        query: Map<String, String> = emptyMap(),
        body: String? = null,
        prefer: String? = null,
    ): JsonArray = withContext(Dispatchers.IO) {
        val token = auth.ensureValidToken()
        val url = buildUrl(path, filters, query)
        val builder = Request.Builder()
            .url(url)
            .header("apikey", AppConfig.supabaseAnonKey)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
        if (prefer != null) builder.header("Prefer", prefer)

        when (method) {
            "GET" -> builder.get()
            "DELETE" -> builder.delete()
            "POST" -> builder.post((body ?: "[]").toRequestBody(JSON))
            "PATCH" -> builder.patch((body ?: "{}").toRequestBody(JSON))
            else -> error("Unsupported method $method")
        }

        val response = http.newCall(builder.build()).execute()
        val raw = response.body?.string().orEmpty()
        if (response.code >= 400) {
            throw SupabaseRestException.Http(response.code, raw.ifEmpty { "Request failed." })
        }
        if (raw.isBlank()) return@withContext JsonArray(emptyList())
        when (val el = json.parseToJsonElement(raw)) {
            is JsonArray -> el
            is JsonObject -> JsonArray(listOf(el))
            else -> JsonArray(emptyList())
        }
    }

    private fun buildUrl(
        path: String,
        filters: Map<String, String>,
        query: Map<String, String>,
    ): okhttp3.HttpUrl {
        val baseUrl = "$base/$path".toHttpUrl().newBuilder()
        (filters + query).toList().sortedBy { it.first }.forEach { (k, v) ->
            baseUrl.addQueryParameter(k, v)
        }
        return baseUrl.build()
    }

    private fun rowsToJson(rows: List<Map<String, JsonElement>>): String =
        buildJsonArray {
            rows.forEach { row ->
                add(mapToJsonObject(row))
            }
        }.toString()

    private fun mapToJson(map: Map<String, JsonElement>): String =
        mapToJsonObject(map).toString()

    private fun mapToJsonObject(map: Map<String, JsonElement>): JsonObject =
        buildJsonObject {
            map.forEach { (k, v) -> put(k, v) }
        }

    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()
        private val defaultClient = OkHttpClient.Builder()
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        val shared by lazy { SupabaseRestClient() }
    }
}

sealed class SupabaseRestException(message: String) : Exception(message) {
    data object InvalidUrl : SupabaseRestException("Invalid Supabase URL.")
    class Network(msg: String) : SupabaseRestException(msg)
    class Http(val code: Int, msg: String) : SupabaseRestException("Supabase error $code: $msg")
}
