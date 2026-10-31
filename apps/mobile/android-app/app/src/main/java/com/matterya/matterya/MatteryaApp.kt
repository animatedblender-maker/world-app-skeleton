package com.matterya.matterya

import android.app.Application
import android.util.Log
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache
import com.matterya.matterya.data.auth.AuthService

class MatteryaApp : Application(), ImageLoaderFactory {
    override fun onCreate() {
        super.onCreate()
        // Never let a single service kill the whole process on cold start.
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e(TAG, "Uncaught on ${thread.name}", throwable)
            // Fall through to default after log so system still reports the crash.
            defaultHandler?.uncaughtException(thread, throwable)
        }

        safe("AuthService") { AuthService.init(this) }
        safe("ContentCache") { com.matterya.matterya.data.cache.ContentCache.get(this) }
        safe("BlockService") { com.matterya.matterya.data.social.BlockService.get(this) }
        safe("HomeFeedStore") { com.matterya.matterya.data.posts.HomeFeedStore.get(this) }
        safe("YouTubeCatalog") { com.matterya.matterya.data.hubs.YouTubeCatalogService.get(this) }
        safe("LettersService") { com.matterya.matterya.data.letters.LettersService.get(this) }
        safe("MediaService") { com.matterya.matterya.data.media.MediaService.init(this) }
        safe("SparkDiscovery") { com.matterya.matterya.data.reels.SparkDiscoveryEngine.bind(this) }
        safe("LocationService") { com.matterya.matterya.data.location.LocationService.init(this) }
        safe("AppPermissions") { com.matterya.matterya.data.system.AppPermissionsService.init(this) }
        safe("GlobeCityCache") { com.matterya.matterya.data.globe.GlobeCityCoordinateCache.init(this) }
        safe("GlobePresence") { com.matterya.matterya.data.presence.GlobePresenceService.init(this) }
        safe("HubEngagement") { com.matterya.matterya.data.hubs.HubEngagementStore.init(this) }
        safe("ImageCache") { com.matterya.matterya.data.media.ImageCache.init(this) }
        safe("SparkWarmPool") { com.matterya.matterya.data.media.SparkWarmPool.init(this) }
        safe("VideoCompression") { com.matterya.matterya.data.media.VideoCompressionService.init(this) }
        safe("NowPlaying") { com.matterya.matterya.data.media.NowPlayingService.init(this) }
        safe("CallSound") { com.matterya.matterya.data.calls.CallSoundService.init(this) }
        safe("Telecom") { com.matterya.matterya.data.calls.TelecomCallManager.init(this) }
        safe("Push") { com.matterya.matterya.data.push.PushNotificationService.init(this) }
        safe("VoIP") { com.matterya.matterya.data.push.VoIPPushService.init(this) }
        safe("InboxStore") { com.matterya.matterya.data.messages.ConversationInboxStore.init(this) }
        safe("DemoDataset") { com.matterya.matterya.data.demo.DemoDatasetService.init(this) }
        safe("ImageCacheConfig") { com.matterya.matterya.data.media.ImageCache.configureSharedCache() }
        safe("FcmHost") {
            com.matterya.matterya.data.push.MatteryaFirebaseMessagingHost.tryRequestFirebaseTokenRefresh()
        }
    }

    override fun newImageLoader(): ImageLoader {
        return ImageLoader.Builder(this)
            .crossfade(true)
            .memoryCache {
                MemoryCache.Builder(this)
                    .maxSizePercent(0.18)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("coil_image_cache"))
                    .maxSizeBytes(64L * 1024 * 1024)
                    .build()
            }
            .build()
    }

    companion object {
        private const val TAG = "MatteryaApp"
        private val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()

        private inline fun safe(name: String, block: () -> Unit) {
            try {
                block()
            } catch (t: Throwable) {
                Log.e(TAG, "Init failed: $name", t)
            }
        }
    }
}
