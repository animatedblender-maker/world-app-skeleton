package com.matterya.matterya.data.presence

import android.content.Context
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.cache.ContentCache
import com.matterya.matterya.data.globe.CountryMapData
import com.matterya.matterya.data.globe.CountryMapEntry
import com.matterya.matterya.data.globe.GlobeCityCoordinateCache
import com.matterya.matterya.data.graphql.GraphQlClient
import com.matterya.matterya.data.hubs.SupabaseRestClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.Date
import java.util.concurrent.TimeUnit

/** iOS `GlobePresenceService.swift`. */
class GlobePresenceService private constructor(
    private val appContext: Context?,
    private val gql: GraphQlClient = GraphQlClient(),
    private val rest: SupabaseRestClient = SupabaseRestClient.shared,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pollJob: Job? = null
    private var refreshJob: Job? = null
    private var countryEntries: List<CountryMapEntry> = emptyList()
    private var currentPrecision = 4

    private val _dots = MutableStateFlow<List<GlobePresenceDot>>(emptyList())
    val dots: StateFlow<List<GlobePresenceDot>> = _dots.asStateFlow()

    private val _totalOnline = MutableStateFlow(0)
    val totalOnline: StateFlow<Int> = _totalOnline.asStateFlow()

    private val _lastUpdated = MutableStateFlow<Date?>(null)
    val lastUpdated: StateFlow<Date?> = _lastUpdated.asStateFlow()

    fun startPolling(precision: Int = 4) {
        currentPrecision = precision
        if (countryEntries.isEmpty()) {
            countryEntries = CountryMapData.load(appContext)
        }
        stopPolling()
        pollJob = scope.launch {
            refresh(currentPrecision)
            while (isActive) {
                delay(20_000)
                refresh(currentPrecision)
            }
        }
    }

    fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    fun updatePrecision(precision: Int) {
        if (precision == currentPrecision) return
        currentPrecision = precision
        refreshJob?.cancel()
        refreshJob = scope.launch { refresh(precision) }
    }

    suspend fun refresh(precision: Int? = null) {
        val activePrecision = precision ?: currentPrecision
        currentPrecision = activePrecision
        if (countryEntries.isEmpty()) {
            countryEntries = CountryMapData.load(appContext)
        }

        var merged: List<GlobePresenceDot> = emptyList()
        var onlineCount = 0

        val supabase = fetchSupabaseDots(activePrecision)
        if (supabase != null) {
            merged = supabase.first
            onlineCount = supabase.second
        } else {
            val gqlDots = fetchGraphQlDots(activePrecision)
            if (gqlDots != null) {
                merged = gqlDots.first
                onlineCount = gqlDots.second
            }
        }

        currentUserDot()?.let { me ->
            if (merged.none { it.id == me.id }) {
                merged = listOf(me) + merged
            }
            onlineCount = maxOf(onlineCount, 1)
        }

        _dots.value = merged
        _totalOnline.value = onlineCount
        _lastUpdated.value = Date()
    }

    private suspend fun currentUserDot(): GlobePresenceDot? {
        val userId = AuthService.instance.currentUser?.id ?: return null
        val cache = appContext?.let { ContentCache.get(it) }
        val profile = cache?.cachedProfile()
        val countryCode = cache?.profileCountryCode() ?: profile?.countryCode
        val coordinate = GlobeCityCoordinateCache.shared.resolveCurrentUser(
            userId = userId,
            countryCode = countryCode,
            cityName = profile?.cityName,
            countryName = profile?.countryName,
            entries = countryEntries,
        ) ?: return null
        return GlobePresenceDot(
            id = "me-$userId",
            lat = coordinate.first,
            lng = coordinate.second,
            count = 1,
        )
    }

    private suspend fun fetchSupabaseDots(precision: Int): Pair<List<GlobePresenceDot>, Int>? {
        val users = fetchPresenceUsers()
        if (users.isEmpty()) return null
        val coordinates = mutableMapOf<String, Pair<Double, Double>>()
        for (user in users) {
            coordinates[user.userId] = GlobeCityCoordinateCache.shared.resolve(user, countryEntries)
        }
        val dots = GlobePresenceGeo.clusterDots(users, coordinates, precision)
        if (dots.isEmpty()) return null
        return dots to users.size
    }

    private suspend fun fetchPresenceUsers(): List<OnlinePresenceUser> {
        val cutoff = GlobePresenceGeo.ttlCutoffIso()
        val filters = mapOf(
            "is_online" to "eq.true",
            "last_seen_at" to "gte.$cutoff",
            "country_code" to "not.is.null",
            "select" to "user_id,country_code,city_name,country_name",
            "order" to "last_seen_at.desc",
            "limit" to "8000",
        )

        val rows = runCatching { fetchPresenceRowsPublic(filters) }.getOrNull()
            ?: runCatching { rest.select("user_presence", filters) }.getOrNull()
            ?: return emptyList()

        return rows.mapNotNull { el ->
            val o = el.jsonObject
            val code = o["country_code"]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
            if (code.isEmpty()) return@mapNotNull null
            OnlinePresenceUser(
                userId = o["user_id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null,
                countryCode = code.uppercase(),
                cityName = o["city_name"]?.jsonPrimitive?.contentOrNull,
                countryName = o["country_name"]?.jsonPrimitive?.contentOrNull,
            )
        }
    }

    private suspend fun fetchPresenceRowsPublic(
        filters: Map<String, String>,
    ): kotlinx.serialization.json.JsonArray {
        val builder = "${AppConfig.supabaseURL}/rest/v1/user_presence"
            .toHttpUrl()
            .newBuilder()
        filters.toList().sortedBy { it.first }.forEach { (k, v) ->
            builder.addQueryParameter(k, v)
        }
        val req = Request.Builder()
            .url(builder.build())
            .get()
            .header("apikey", AppConfig.supabaseAnonKey)
            .header("Authorization", "Bearer ${AppConfig.supabaseAnonKey}")
            .header("Accept", "application/json")
            .build()
        val client = OkHttpClient.Builder()
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(25, TimeUnit.SECONDS)
            .build()
        val response = client.newCall(req).execute()
        val raw = response.body?.string().orEmpty()
        if (!response.isSuccessful) error("presence public fetch failed")
        if (raw.isBlank()) return kotlinx.serialization.json.JsonArray(emptyList())
        return kotlinx.serialization.json.Json.parseToJsonElement(raw).jsonArray
    }

    private suspend fun fetchGraphQlDots(precision: Int): Pair<List<GlobePresenceDot>, Int>? {
        val query = """
        query GlobePresenceDots(${'$'}precision: Int, ${'$'}maxPoints: Int) {
          globePresenceDots(precision: ${'$'}precision, maxPoints: ${'$'}maxPoints) {
            totalOnline
            dots { lat lng count }
          }
        }
        """.trimIndent()
        val data = runCatching {
            gql.request(
                query,
                mapOf(
                    "precision" to JsonPrimitive(precision),
                    "maxPoints" to JsonPrimitive(4096),
                ),
                requireAuth = false,
            )
        }.getOrNull() ?: return null

        val payload = data["globePresenceDots"]?.jsonObject ?: return null
        val rawDots = payload["dots"]?.jsonArray.orEmpty()
        if (rawDots.isEmpty()) return null
        val dots = rawDots.mapIndexed { index, el ->
            val o = el.jsonObject
            GlobePresenceDot(
                id = "${o["lat"]}-${o["lng"]}-$index",
                lat = o["lat"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                lng = o["lng"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                count = o["count"]?.jsonPrimitive?.intOrNull ?: 1,
            )
        }
        val total = payload["totalOnline"]?.jsonPrimitive?.intOrNull ?: dots.sumOf { it.count }
        return dots to total
    }

    companion object {
        @Volatile private var instance: GlobePresenceService? = null

        val shared: GlobePresenceService
            get() = instance ?: GlobePresenceService(null).also { instance = it }

        fun init(context: Context): GlobePresenceService {
            return instance ?: synchronized(this) {
                instance ?: GlobePresenceService(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): GlobePresenceService = init(context)
    }
}
