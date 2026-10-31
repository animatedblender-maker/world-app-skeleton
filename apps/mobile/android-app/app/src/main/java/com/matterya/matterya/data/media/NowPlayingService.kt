package com.matterya.matterya.data.media

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import com.matterya.matterya.data.hubs.StreamingHubService
import com.matterya.matterya.model.LivePlaybackState
import com.matterya.matterya.model.StreamingPlatform
import com.matterya.matterya.model.YourNowPlaying
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.Date

/**
 * Android MediaSession equivalent of iOS `AppleMusicNowPlayingService.swift`.
 *
 * Reads the active MediaController (system media session) and syncs to
 * StreamingHubService. Join-session / catalog play is platform-specific
 * (Android cannot drive Apple Music the same way; exposes surface for Spotify/etc).
 */
data class NowPlayingSnapshot(
    val contentId: String?,
    val title: String,
    val subtitle: String,
    val momentLabel: String?,
    val progressMs: Int,
    val durationMs: Int,
    val isPlaying: Boolean,
    val platform: StreamingPlatform = StreamingPlatform.AppleMusic,
)

sealed class NowPlayingServiceError(message: String) : Exception(message) {
    data object NotAuthorized : NowPlayingServiceError(
        "Allow Matterya notification access (or media control) in Settings to share what you're listening to.",
    )
    data object NothingPlaying : NowPlayingServiceError(
        "Nothing is playing right now. Start a song, then come back.",
    )
    data object SongUnavailable : NowPlayingServiceError(
        "That song isn't available to control from Matterya on Android.",
    )
}

class NowPlayingService private constructor(
    private val appContext: Context?,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var syncJob: Job? = null
    private var lastUploadedSecond: Int? = null
    private var onUpdated: (suspend () -> Unit)? = null

    @Volatile
    var localSnapshot: NowPlayingSnapshot? = null
        private set

    fun requestAuthorization() {
        // Notification listener / media projection is opt-in at OS level.
        // Surface is ready; host can deep-link to notification access settings.
    }

    fun readCurrentPlayback(): NowPlayingSnapshot {
        val controller = activeController()
            ?: throw NowPlayingServiceError.NothingPlaying
        val meta = controller.metadata
            ?: throw NowPlayingServiceError.NothingPlaying
        val state = controller.playbackState
        val title = meta.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty()
        if (title.isEmpty()) throw NowPlayingServiceError.NothingPlaying
        val artist = meta.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: "Now playing"
        val album = meta.getString(MediaMetadata.METADATA_KEY_ALBUM)
        val duration = meta.getLong(MediaMetadata.METADATA_KEY_DURATION).coerceAtLeast(0)
        val position = state?.position?.coerceAtLeast(0) ?: 0
        val isPlaying = state?.state == PlaybackState.STATE_PLAYING
        val contentId = meta.getString(MediaMetadata.METADATA_KEY_MEDIA_ID)
        val packageName = controller.packageName.orEmpty()
        val platform = platformFromPackage(packageName)

        val snapshot = NowPlayingSnapshot(
            contentId = contentId,
            title = title,
            subtitle = artist,
            momentLabel = album,
            progressMs = position.toInt(),
            durationMs = maxOf(duration.toInt(), position.toInt() + 1),
            isPlaying = isPlaying,
            platform = platform,
        )
        localSnapshot = snapshot
        return snapshot
    }

    suspend fun syncNowPlayingToHub(
        sharingEnabled: Boolean,
        force: Boolean = false,
    ): YourNowPlaying? {
        val snapshot = readCurrentPlayback()
        val currentSecond = snapshot.progressMs / 1000
        if (!force && !snapshot.isPlaying && lastUploadedSecond == currentSecond) return null
        if (!force && snapshot.isPlaying && lastUploadedSecond == currentSecond) return null

        val saved = StreamingHubService.shared.updateNowPlaying(
            platform = snapshot.platform,
            title = snapshot.title,
            subtitle = snapshot.subtitle,
            momentLabel = snapshot.momentLabel,
            progressMs = snapshot.progressMs,
            durationMs = snapshot.durationMs,
            isSharing = sharingEnabled && snapshot.isPlaying,
            contentId = snapshot.contentId,
        )
        lastUploadedSecond = currentSecond
        return saved
    }

    suspend fun joinSession(contentId: String, progressMs: Int) {
        @Suppress("UNUSED_VARIABLE")
        val unused = contentId to progressMs
        // Android cannot reliably launch Apple Music catalog items like iOS MusicKit.
        // Best-effort: try to resume the active session and re-sync.
        val controller = activeController()
            ?: throw NowPlayingServiceError.SongUnavailable
        controller.transportControls?.play()
        StreamingHubService.shared.linkPlatform(StreamingPlatform.AppleMusic)
        syncNowPlayingToHub(sharingEnabled = true, force = true)
    }

    fun startAutoSync(sharingEnabled: Boolean, onUpdated: suspend () -> Unit) {
        stopAutoSync()
        if (!sharingEnabled) return
        this.onUpdated = onUpdated
        syncJob = scope.launch {
            while (isActive) {
                try {
                    val snapshot = readCurrentPlayback()
                    val interval = if (snapshot.isPlaying) 2_000L else 6_000L
                    syncNowPlayingToHub(sharingEnabled)
                    onUpdated()
                    delay(interval)
                } catch (_: Exception) {
                    delay(4_000)
                }
            }
        }
    }

    fun stopAutoSync() {
        syncJob?.cancel()
        syncJob = null
        onUpdated = null
        lastUploadedSecond = null
    }

    fun liveStateForDisplay(fallback: YourNowPlaying): LivePlaybackState {
        val local = localSnapshot ?: return fallback.liveState
        val controller = activeController()
        val position = controller?.playbackState?.position?.toInt() ?: local.progressMs
        val isPlaying = controller?.playbackState?.state == PlaybackState.STATE_PLAYING
        return LivePlaybackState(
            contentId = local.contentId,
            title = local.title,
            subtitle = local.subtitle,
            momentLabel = local.momentLabel,
            progressMs = position,
            durationMs = local.durationMs,
            updatedAt = Date(),
            isPlaying = isPlaying,
            platform = local.platform,
        )
    }

    private fun activeController(): MediaController? {
        val ctx = appContext ?: return null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        return runCatching {
            val sm = ctx.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
                ?: return null
            // Requires notification listener permission for third-party sessions.
            val component = ComponentName(ctx, ctx.packageName)
            @Suppress("DEPRECATION")
            val controllers = sm.getActiveSessions(null)
            controllers.firstOrNull {
                it.playbackState?.state == PlaybackState.STATE_PLAYING
            } ?: controllers.firstOrNull()
        }.getOrNull()
    }

    private fun platformFromPackage(packageName: String): StreamingPlatform = when {
        packageName.contains("spotify", ignoreCase = true) -> StreamingPlatform.Spotify
        packageName.contains("netflix", ignoreCase = true) -> StreamingPlatform.Netflix
        packageName.contains("disney", ignoreCase = true) -> StreamingPlatform.Disney
        packageName.contains("apple", ignoreCase = true) -> StreamingPlatform.AppleMusic
        packageName.contains("music", ignoreCase = true) -> StreamingPlatform.AppleMusic
        else -> StreamingPlatform.AppleMusic
    }

    companion object {
        @Volatile private var instance: NowPlayingService? = null

        val shared: NowPlayingService
            get() = instance ?: NowPlayingService(null).also { instance = it }

        fun init(context: Context): NowPlayingService {
            return instance ?: synchronized(this) {
                instance ?: NowPlayingService(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): NowPlayingService = init(context)
    }
}
