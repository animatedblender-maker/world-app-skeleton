package com.matterya.matterya.data.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.core.content.ContextCompat
import com.matterya.matterya.MatteryaApp
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Android port of iOS `LocationService.swift`.
 * Uses system [LocationManager] (no Google Play Services required).
 */
class LocationService private constructor(private val appContext: Context) {
    private val manager =
        appContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    fun requestAuthorizationIfNeeded(): Boolean = hasLocationPermission()

    suspend fun currentCoordinate(): Pair<Double, Double>? {
        if (!hasLocationPermission()) return null
        // Prefer last-known first — single-update often hangs forever on emulators.
        lastKnown()?.let { return it.latitude to it.longitude }
        return kotlinx.coroutines.withTimeoutOrNull(8_000) {
            requestSingleUpdate()
        }
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    @SuppressLint("MissingPermission")
    private suspend fun requestSingleUpdate(): Pair<Double, Double>? {
        if (!hasLocationPermission()) return null

        val last = lastKnown()
        if (last != null) return last.latitude to last.longitude

        val provider = when {
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
                LocationManager.NETWORK_PROVIDER
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
                LocationManager.GPS_PROVIDER
            else -> return null
        }

        return suspendCancellableCoroutine { cont ->
            val listener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    if (cont.isActive) {
                        cont.resume(location.latitude to location.longitude)
                    }
                    runCatching { manager.removeUpdates(this) }
                }

                @Deprecated("Deprecated in Java")
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {
                    if (cont.isActive) cont.resume(null)
                    runCatching { manager.removeUpdates(this) }
                }
            }
            cont.invokeOnCancellation {
                runCatching { manager.removeUpdates(listener) }
            }
            try {
                manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            } catch (_: Exception) {
                if (cont.isActive) cont.resume(null)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun lastKnown(): Location? {
        if (!hasLocationPermission()) return null
        val gps = runCatching { manager.getLastKnownLocation(LocationManager.GPS_PROVIDER) }.getOrNull()
        val net = runCatching { manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER) }.getOrNull()
        return listOfNotNull(gps, net).maxByOrNull { it.time }
    }

    companion object {
        @Volatile private var instance: LocationService? = null

        val shared: LocationService
            get() = instance ?: error("LocationService.init(context) required")

        fun init(context: Context): LocationService {
            return instance ?: synchronized(this) {
                instance ?: LocationService(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): LocationService = init(context)
    }
}
