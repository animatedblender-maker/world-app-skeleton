package com.matterya.matterya.data.system

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.matterya.matterya.data.location.LocationService
import com.matterya.matterya.data.push.PushNotificationService
import kotlinx.coroutines.delay

/**
 * Android port of iOS `AppPermissionsService.swift`.
 *
 * Runtime permission *dialogs* must be launched from an Activity via
 * [requestEssentialPermissionsOnLaunch]. This service exposes the same
 * sequential request flow + helpers for checking grant state.
 */
class AppPermissionsService private constructor(private val appContext: Context) {

    /**
     * Requests every essential permission the first time the app is opened.
     * [launcher] should map to Activity Result API permission requests.
     */
    suspend fun requestEssentialPermissionsOnLaunch(
        launcher: suspend (Array<String>) -> Map<String, Boolean>,
    ) {
        requestMicrophoneIfNeeded(launcher)
        pauseBetweenPrompts()
        requestCameraIfNeeded(launcher)
        pauseBetweenPrompts()
        PushNotificationService.shared.requestAuthorizationAndRegister(launcher)
        pauseBetweenPrompts()
        requestLocationIfNeeded(launcher)
    }

    suspend fun requestMicrophoneIfNeeded(
        launcher: suspend (Array<String>) -> Map<String, Boolean>,
    ) {
        if (hasPermission(Manifest.permission.RECORD_AUDIO)) return
        launcher(arrayOf(Manifest.permission.RECORD_AUDIO))
    }

    suspend fun requestCameraIfNeeded(
        launcher: suspend (Array<String>) -> Map<String, Boolean>,
    ) {
        if (hasPermission(Manifest.permission.CAMERA)) return
        launcher(arrayOf(Manifest.permission.CAMERA))
    }

    suspend fun requestLocationIfNeeded(
        launcher: suspend (Array<String>) -> Map<String, Boolean>,
    ) {
        if (hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ||
            hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        ) {
            return
        }
        launcher(
            arrayOf(
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ),
        )
        LocationService.get(appContext).requestAuthorizationIfNeeded()
    }

    fun hasMicrophonePermission(): Boolean = hasPermission(Manifest.permission.RECORD_AUDIO)
    fun hasCameraPermission(): Boolean = hasPermission(Manifest.permission.CAMERA)
    fun hasLocationPermission(): Boolean =
        hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ||
            hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)

    fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            hasPermission(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            true
        }
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(appContext, permission) ==
            PackageManager.PERMISSION_GRANTED

    private suspend fun pauseBetweenPrompts() {
        delay(450)
    }

    companion object {
        @Volatile private var instance: AppPermissionsService? = null

        val shared: AppPermissionsService
            get() = instance ?: error("AppPermissionsService.init(context) required")

        fun init(context: Context): AppPermissionsService {
            return instance ?: synchronized(this) {
                instance ?: AppPermissionsService(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): AppPermissionsService = init(context)
    }
}
