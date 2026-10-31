package com.matterya.matterya.data.presence

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class GlobePresenceDot(
    val id: String,
    val lat: Double,
    val lng: Double,
    val count: Int,
)

data class OnlinePresenceUser(
    val userId: String,
    val countryCode: String,
    val cityName: String? = null,
    val countryName: String? = null,
)

/** iOS `GlobePresenceGeo.swift`. */
object GlobePresenceGeo {
    private const val TTL_SECONDS = 70

    fun ttlCutoffIso(): String {
        val cutoff = Date(System.currentTimeMillis() - TTL_SECONDS * 1000L)
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(cutoff)
    }

    fun buildDots(
        users: List<OnlinePresenceUser>,
        coordinates: Map<String, Pair<Double, Double>>,
    ): List<GlobePresenceDot> = clusterDots(users, coordinates, precision = 5)

    fun clusterDots(
        users: List<OnlinePresenceUser>,
        coordinates: Map<String, Pair<Double, Double>>,
        precision: Int,
    ): List<GlobePresenceDot> {
        val cellSize = cellSize(precision)
        data class Bucket(var lat: Double, var lng: Double, var count: Int)
        val buckets = linkedMapOf<String, Bucket>()

        for (user in users) {
            val coordinate = coordinates[user.userId] ?: continue
            val lat = coordinate.first
            val lng = coordinate.second
            if (!lat.isFinite() || !lng.isFinite()) continue

            val latBucket = kotlin.math.floor(lat / cellSize).toInt()
            val lngBucket = kotlin.math.floor(normalizeLongitude(lng) / cellSize).toInt()
            val key = "$latBucket:$lngBucket"

            val existing = buckets[key]
            if (existing != null) {
                val total = existing.count.toDouble()
                existing.lat = ((existing.lat * total) + lat) / (total + 1)
                existing.lng = ((existing.lng * total) + normalizeLongitude(lng)) / (total + 1)
                existing.count += 1
            } else {
                buckets[key] = Bucket(lat, normalizeLongitude(lng), 1)
            }
        }

        return buckets.map { (key, bucket) ->
            GlobePresenceDot(
                id = key,
                lat = bucket.lat,
                lng = bucket.lng,
                count = bucket.count,
            )
        }
    }

    private fun cellSize(precision: Int): Double = when (precision) {
        5 -> 0.08
        4 -> 0.35
        3 -> 1.2
        2 -> 4.0
        else -> 12.0
    }

    fun normalizeLongitude(lng: Double): Double {
        var value = lng
        while (value > 180) value -= 360
        while (value < -180) value += 360
        return value
    }
}
