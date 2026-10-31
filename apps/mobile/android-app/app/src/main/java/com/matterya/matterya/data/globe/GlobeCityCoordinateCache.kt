package com.matterya.matterya.data.globe

import android.content.Context
import android.location.Geocoder
import com.matterya.matterya.data.presence.GlobePresenceGeo
import com.matterya.matterya.data.presence.OnlinePresenceUser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.abs

/** iOS `GlobeCityCoordinateCache.swift`. */
class GlobeCityCoordinateCache private constructor(private val appContext: Context?) {
    private val cache = mutableMapOf<String, Pair<Double, Double>>()

    suspend fun resolve(
        user: OnlinePresenceUser,
        entries: List<CountryMapEntry>,
    ): Pair<Double, Double> {
        val iso = user.countryCode.uppercase()
        if (iso.isEmpty() || iso == "XX") return 0.0 to 0.0

        val entry = entries.firstOrNull {
            it.iso2.equals(iso, ignoreCase = true) || it.iso3.equals(iso, ignoreCase = true)
        }
        val centerLat = entry?.lat ?: 0.0
        val centerLng = entry?.lng ?: 0.0

        val city = user.cityName?.trim().orEmpty()
        if (city.isNotEmpty()) {
            val key = "${city.lowercase()}|$iso"
            cache[key]?.let { return it }

            val query = listOfNotNull(
                city.takeIf { it.isNotEmpty() },
                user.countryName?.trim()?.takeIf { it.isNotEmpty() },
                iso,
            ).joinToString(", ")

            geocode(query)?.let {
                cache[key] = it
                return it
            }
        }

        return jitteredPosition(
            userId = user.userId,
            centerLat = centerLat,
            centerLng = centerLng,
            maxOffset = 0.08,
        )
    }

    suspend fun resolveCurrentUser(
        userId: String,
        countryCode: String?,
        cityName: String?,
        countryName: String?,
        entries: List<CountryMapEntry>,
    ): Pair<Double, Double>? {
        val code = countryCode?.trim().orEmpty()
        if (code.isEmpty()) return null
        val user = OnlinePresenceUser(
            userId = userId,
            countryCode = code,
            cityName = cityName,
            countryName = countryName,
        )
        val coordinate = resolve(user, entries)
        if (!coordinate.first.isFinite() || !coordinate.second.isFinite()) return null
        return coordinate
    }

    @Suppress("DEPRECATION")
    private suspend fun geocode(query: String): Pair<Double, Double>? = withContext(Dispatchers.IO) {
        val ctx = appContext ?: return@withContext null
        if (!Geocoder.isPresent()) return@withContext null
        runCatching {
            val geocoder = Geocoder(ctx, Locale.getDefault())
            val results = geocoder.getFromLocationName(query, 1)
            val first = results?.firstOrNull() ?: return@runCatching null
            first.latitude to first.longitude
        }.getOrNull()
    }

    private fun jitteredPosition(
        userId: String,
        centerLat: Double,
        centerLng: Double,
        maxOffset: Double,
    ): Pair<Double, Double> {
        val seed = abs(hash32("$userId:presence"))
        val latOffset = ((seed % 10_000) / 10_000.0 - 0.5) * maxOffset
        val lngOffset = (((seed / 10_000) % 10_000) / 10_000.0 - 0.5) * maxOffset
        return centerLat + latOffset to GlobePresenceGeo.normalizeLongitude(centerLng + lngOffset)
    }

    private fun hash32(input: String): Int {
        var hash = 2_166_136_261L
        for (byte in input.encodeToByteArray()) {
            hash = hash xor (byte.toLong() and 0xFF)
            hash = (hash * 16_777_619L) and 0xFFFF_FFFFL
        }
        return hash.toInt()
    }

    companion object {
        @Volatile private var instance: GlobeCityCoordinateCache? = null

        val shared: GlobeCityCoordinateCache
            get() = instance ?: GlobeCityCoordinateCache(null).also { instance = it }

        fun init(context: Context): GlobeCityCoordinateCache {
            return instance ?: synchronized(this) {
                instance ?: GlobeCityCoordinateCache(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): GlobeCityCoordinateCache = init(context)
    }
}
