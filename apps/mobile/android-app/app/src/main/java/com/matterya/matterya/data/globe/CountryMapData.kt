package com.matterya.matterya.data.globe

import android.content.Context
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

data class CountryMapEntry(
    val id: String,
    val iso2: String,
    val iso3: String,
    val name: String,
    val lat: Double,
    val lng: Double,
    val rings: List<List<MapPoint>> = emptyList(),
) {
    data class MapPoint(val lng: Double, val lat: Double)
}

data class SphereCoordinate(val x: Float, val y: Float, val z: Float)

/**
 * iOS `CountryMapData.swift` — loads `countries_map.json` from assets when present,
 * otherwise returns a compact center-point fallback table for presence jitter.
 */
object CountryMapData {
    const val globeRadius = 1.0f
    const val borderRadius = 1.014f
    const val labelRadius = 1.05f

    @Volatile private var cached: List<CountryMapEntry>? = null

    fun load(context: Context? = null): List<CountryMapEntry> {
        cached?.let { return it }
        val fromAssets = context?.let { loadFromAssets(it) }.orEmpty()
        val result = fromAssets.ifEmpty { fallbackCenters() }
        cached = result
        return result
    }

    fun sphereCoordinate(lat: Double, lng: Double, radius: Float = globeRadius): SphereCoordinate {
        val latRad = (lat * Math.PI / 180.0).toFloat()
        val lngRad = (lng * Math.PI / 180.0).toFloat()
        val cosLat = cos(latRad)
        val x = radius * cosLat * cos(lngRad)
        val y = radius * sin(latRad)
        val z = radius * cosLat * sin(lngRad)
        return SphereCoordinate(x, y, z)
    }

    fun geographicCoordinate(x: Float, y: Float, z: Float): Pair<Double, Double> {
        val radius = max(sqrt(x * x + y * y + z * z), 0.0001f)
        val lat = asin(min(1f, max(-1f, y / radius))).toDouble() * 180.0 / Math.PI
        val lng = atan2(z.toDouble(), x.toDouble()) * 180.0 / Math.PI
        return lat to lng
    }

    /**
     * Orthographic projection of lat/lng onto a 2D disc (front hemisphere).
     * Returns null when the point is on the back of the globe for given rotation.
     */
    fun projectToDisc(
        lat: Double,
        lng: Double,
        rotationYDeg: Float = 0f,
        radiusPx: Float,
        centerX: Float,
        centerY: Float,
    ): Pair<Float, Float>? {
        val sphere = sphereCoordinate(lat, lng)
        val rot = (rotationYDeg * Math.PI / 180.0).toFloat()
        val cosR = cos(rot)
        val sinR = sin(rot)
        val x = sphere.x * cosR + sphere.z * sinR
        val y = sphere.y
        val z = -sphere.x * sinR + sphere.z * cosR
        if (z < -0.02f) return null
        val px = centerX + x * radiusPx
        val py = centerY - y * radiusPx
        return px to py
    }

    /** Inverse orthographic: disc (px) → lat/lng for front face. */
    fun discToGeographic(
        px: Float,
        py: Float,
        rotationYDeg: Float,
        radiusPx: Float,
        centerX: Float,
        centerY: Float,
    ): Pair<Double, Double>? {
        val nx = (px - centerX) / radiusPx
        val ny = -(py - centerY) / radiusPx
        val r2 = nx * nx + ny * ny
        if (r2 > 1f) return null
        val nz = sqrt(1f - r2)
        val rot = (-rotationYDeg * Math.PI / 180.0).toFloat()
        val cosR = cos(rot)
        val sinR = sin(rot)
        val x = nx * cosR + nz * sinR
        val y = ny
        val z = -nx * sinR + nz * cosR
        return geographicCoordinate(x, y, z)
    }

    fun country(containingLng: Double, containingLat: Double, entries: List<CountryMapEntry>): CountryMapEntry? {
        // Prefer ring hit-test when polygons exist; else nearest centroid.
        val withRings = entries.filter { it.rings.any { ring -> ring.size >= 3 } }
        if (withRings.isNotEmpty()) {
            val reversed = withRings.sortedBy { countryArea(it) }
            for (entry in reversed) {
                for (ring in entry.rings) {
                    if (ring.size >= 3 && pointInGeoRing(containingLng, containingLat, ring)) {
                        return entry
                    }
                }
            }
        }
        // Centroid nearest-neighbor (fallback map)
        return entries.minByOrNull { e ->
            val dLat = e.lat - containingLat
            val dLng = e.lng - containingLng
            dLat * dLat + dLng * dLng
        }
    }

    private fun countryArea(entry: CountryMapEntry): Double {
        var minLng = 180.0
        var maxLng = -180.0
        var minLat = 90.0
        var maxLat = -90.0
        for (ring in entry.rings) {
            for (point in ring) {
                minLng = min(minLng, point.lng)
                maxLng = max(maxLng, point.lng)
                minLat = min(minLat, point.lat)
                maxLat = max(maxLat, point.lat)
            }
        }
        return max(0.01, (maxLng - minLng) * (maxLat - minLat))
    }

    private fun pointInGeoRing(lng: Double, lat: Double, ring: List<CountryMapEntry.MapPoint>): Boolean {
        var inside = false
        var j = ring.size - 1
        for (i in ring.indices) {
            var piLng = ring[i].lng
            val piLat = ring[i].lat
            var pjLng = ring[j].lng
            val pjLat = ring[j].lat
            if (kotlin.math.abs(piLng - pjLng) > 180) {
                if (piLng < pjLng) piLng += 360 else pjLng += 360
            }
            var testLng = lng
            if (kotlin.math.abs(testLng - piLng) > 180) {
                if (testLng < piLng) testLng += 360 else testLng -= 360
            }
            val intersects = ((piLat > lat) != (pjLat > lat)) &&
                (testLng < (pjLng - piLng) * (lat - piLat) / ((pjLat - piLat) + 0.0000001) + piLng)
            if (intersects) inside = !inside
            j = i
        }
        return inside
    }

    private fun loadFromAssets(context: Context): List<CountryMapEntry> {
        val json = Json { ignoreUnknownKeys = true; isLenient = true }
        val candidates = listOf("countries_map.json", "globe/countries_map.json")
        for (name in candidates) {
            val text = runCatching {
                context.assets.open(name).bufferedReader().use { it.readText() }
            }.getOrNull() ?: continue
            val arr = runCatching { json.parseToJsonElement(text).jsonArray }.getOrNull()
                ?: continue
            val parsed = arr.mapNotNull { parseEntry(it as? JsonObject ?: return@mapNotNull null) }
            if (parsed.isNotEmpty()) return parsed
        }
        return emptyList()
    }

    private fun parseEntry(row: JsonObject): CountryMapEntry? {
        val iso3 = row["iso3"]?.jsonPrimitive?.contentOrNull ?: return null
        val iso2 = row["iso2"]?.jsonPrimitive?.contentOrNull ?: return null
        val name = row["name"]?.jsonPrimitive?.contentOrNull ?: return null
        val lat = row["lat"]?.jsonPrimitive?.doubleOrNull ?: return null
        val lng = row["lng"]?.jsonPrimitive?.doubleOrNull ?: return null
        val ringsRaw = row["rings"] as? JsonArray
        val rings = ringsRaw?.mapNotNull { ringEl ->
            val ring = ringEl as? JsonArray ?: return@mapNotNull null
            ring.mapNotNull { pairEl ->
                val pair = pairEl as? JsonArray ?: return@mapNotNull null
                if (pair.size < 2) return@mapNotNull null
                val plng = pair[0].jsonPrimitive.doubleOrNull ?: return@mapNotNull null
                val plat = pair[1].jsonPrimitive.doubleOrNull ?: return@mapNotNull null
                CountryMapEntry.MapPoint(lng = plng, lat = plat)
            }.takeIf { it.isNotEmpty() }
        }.orEmpty().filter { it.isNotEmpty() }
        return CountryMapEntry(
            id = iso3,
            iso2 = iso2,
            iso3 = iso3,
            name = name,
            lat = lat,
            lng = lng,
            rings = rings,
        )
    }

    /** Approximate country centers used when map JSON is not bundled yet. */
    private fun fallbackCenters(): List<CountryMapEntry> {
        val raw = listOf(
            Triple("US", "USA", "United States") to (39.8 to -98.5),
            Triple("CA", "CAN", "Canada") to (56.1 to -106.3),
            Triple("MX", "MEX", "Mexico") to (23.6 to -102.5),
            Triple("BR", "BRA", "Brazil") to (-14.2 to -51.9),
            Triple("AR", "ARG", "Argentina") to (-38.4 to -63.6),
            Triple("GB", "GBR", "United Kingdom") to (55.4 to -3.4),
            Triple("FR", "FRA", "France") to (46.2 to 2.2),
            Triple("DE", "DEU", "Germany") to (51.2 to 10.4),
            Triple("ES", "ESP", "Spain") to (40.5 to -3.7),
            Triple("IT", "ITA", "Italy") to (41.9 to 12.6),
            Triple("PL", "POL", "Poland") to (51.9 to 19.1),
            Triple("SE", "SWE", "Sweden") to (60.1 to 18.6),
            Triple("NO", "NOR", "Norway") to (60.5 to 8.5),
            Triple("RU", "RUS", "Russia") to (61.5 to 105.3),
            Triple("TR", "TUR", "Turkey") to (38.96 to 35.24),
            Triple("EG", "EGY", "Egypt") to (26.8 to 30.8),
            Triple("NG", "NGA", "Nigeria") to (9.1 to 8.7),
            Triple("ZA", "ZAF", "South Africa") to (-30.6 to 22.9),
            Triple("KE", "KEN", "Kenya") to (-0.02 to 37.9),
            Triple("IN", "IND", "India") to (20.6 to 78.9),
            Triple("PK", "PAK", "Pakistan") to (30.4 to 69.3),
            Triple("BD", "BGD", "Bangladesh") to (23.7 to 90.4),
            Triple("CN", "CHN", "China") to (35.9 to 104.2),
            Triple("JP", "JPN", "Japan") to (36.2 to 138.3),
            Triple("KR", "KOR", "South Korea") to (35.9 to 127.8),
            Triple("ID", "IDN", "Indonesia") to (-0.8 to 113.9),
            Triple("PH", "PHL", "Philippines") to (12.9 to 121.8),
            Triple("VN", "VNM", "Vietnam") to (14.1 to 108.3),
            Triple("TH", "THA", "Thailand") to (15.9 to 100.9),
            Triple("AU", "AUS", "Australia") to (-25.3 to 133.8),
            Triple("NZ", "NZL", "New Zealand") to (-40.9 to 174.9),
            Triple("SA", "SAU", "Saudi Arabia") to (23.9 to 45.1),
            Triple("AE", "ARE", "United Arab Emirates") to (23.4 to 53.8),
            Triple("IL", "ISR", "Israel") to (31.0 to 34.9),
            Triple("UA", "UKR", "Ukraine") to (48.4 to 31.2),
            Triple("NL", "NLD", "Netherlands") to (52.1 to 5.3),
            Triple("BE", "BEL", "Belgium") to (50.5 to 4.5),
            Triple("CH", "CHE", "Switzerland") to (46.8 to 8.2),
            Triple("PT", "PRT", "Portugal") to (39.4 to -8.2),
            Triple("IE", "IRL", "Ireland") to (53.1 to -8.2),
            Triple("CL", "CHL", "Chile") to (-35.7 to -71.5),
            Triple("CO", "COL", "Colombia") to (4.6 to -74.3),
            Triple("PE", "PER", "Peru") to (-9.2 to -75.0),
            Triple("GH", "GHA", "Ghana") to (7.9 to -1.0),
            Triple("ET", "ETH", "Ethiopia") to (9.1 to 40.5),
            Triple("MA", "MAR", "Morocco") to (31.8 to -7.1),
            Triple("SG", "SGP", "Singapore") to (1.4 to 103.8),
            Triple("MY", "MYS", "Malaysia") to (4.2 to 101.9),
            Triple("TW", "TWN", "Taiwan") to (23.7 to 121.0),
            Triple("HK", "HKG", "Hong Kong") to (22.3 to 114.2),
        )
        return raw.map { (ids, coords) ->
            CountryMapEntry(
                id = ids.second,
                iso2 = ids.first,
                iso3 = ids.second,
                name = ids.third,
                lat = coords.first,
                lng = coords.second,
            )
        }
    }
}
