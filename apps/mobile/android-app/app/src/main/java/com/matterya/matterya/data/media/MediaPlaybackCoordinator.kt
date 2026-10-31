package com.matterya.matterya.data.media

import androidx.media3.common.Player
import com.matterya.matterya.data.system.NotificationNames
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import java.lang.ref.WeakReference

/**
 * ExoPlayer-oriented API surface matching iOS `MediaPlaybackCoordinator`.
 * Tracks active players so Sparks / feed audio cannot stack.
 */
class MediaPlaybackCoordinator private constructor() {
    private val players = mutableListOf<WeakReference<Player>>()
    private var soloPlayer: WeakReference<Player>? = null
    private var soloPlayingThroughInterrupt: WeakReference<Player>? = null

    private val _sparkPageEpoch = MutableStateFlow(0uL)
    val sparkPageEpoch: StateFlow<ULong> = _sparkPageEpoch.asStateFlow()

    private val _resumeAfterInterrupt = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val resumeAfterInterrupt: SharedFlow<Unit> = _resumeAfterInterrupt.asSharedFlow()

    fun register(player: Player) {
        players.removeAll { it.get() == null || it.get() === player }
        players.add(WeakReference(player))
    }

    fun unregister(player: Player) {
        players.removeAll { it.get() == null || it.get() === player }
        if (soloPlayer?.get() === player) soloPlayer = null
        if (soloPlayingThroughInterrupt?.get() === player) soloPlayingThroughInterrupt = null
    }

    fun isSolo(player: Player?): Boolean {
        if (player == null) return false
        return soloPlayer?.get() === player
    }

    fun stopAllPlayback() = stopAllPlayback(except = null)

    fun stopAllPlayback(except: Player?) {
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (except != null && p === except) continue
            hardSilence(p)
            p.stop()
            p.clearMediaItems()
        }
        players.removeAll { it.get() == null || (except != null && it.get() !== except) }
        if (except != null) {
            soloPlayer = WeakReference(except)
        } else {
            soloPlayer = null
            players.clear()
            soloPlayingThroughInterrupt = null
        }
    }

    fun pauseAll(except: Player? = null) {
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (except != null && p === except) continue
            hardSilence(p)
        }
        soloPlayer = except?.let { WeakReference(it) }
    }

    fun silenceForSparkPageChange() {
        _sparkPageEpoch.value = _sparkPageEpoch.value + 1uL
        val previous = soloPlayer?.get()
        soloPlayer = null
        soloPlayingThroughInterrupt = null
        previous?.let { hardSilence(it) }
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (previous != null && p === previous) continue
            if (p.isPlaying || p.playbackState == Player.STATE_BUFFERING) {
                hardSilence(p)
            }
        }
    }

    fun soloSparkAudio(
        keeping: Player?,
        pageEpoch: ULong? = null,
        aggressive: Boolean = false,
    ): Boolean {
        if (pageEpoch != null && pageEpoch != _sparkPageEpoch.value) {
            keeping?.let { hardSilence(it) }
            return false
        }
        soloPlayer = keeping?.let { WeakReference(it) }
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (keeping != null && p === keeping) continue
            if (aggressive) {
                hardSilence(p)
                continue
            }
            if (p.isPlaying || p.playbackState == Player.STATE_BUFFERING || p.volume > 0.01f) {
                hardSilence(p)
            }
        }
        return true
    }

    fun enforceSoloAudioOnly() {
        val keep = soloPlayer?.get()
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (keep != null && p === keep) continue
            hardSilence(p)
        }
        if (keep != null) soloPlayer = WeakReference(keep)
    }

    val currentSoloPlayer: Player? get() = soloPlayer?.get()

    fun allowPlaybackIfSolo(player: Player, pageEpoch: ULong? = null): Boolean {
        if (pageEpoch != null && pageEpoch != _sparkPageEpoch.value) {
            hardSilence(player)
            return false
        }
        if (soloPlayer?.get() !== player) {
            hardSilence(player)
            return false
        }
        return true
    }

    fun noteResignActive() {
        soloPlayingThroughInterrupt = null
        val solo = soloPlayer?.get() ?: return
        if (solo.isPlaying || solo.playbackState == Player.STATE_BUFFERING) {
            soloPlayingThroughInterrupt = WeakReference(solo)
        }
    }

    fun resumeAfterInterrupt() {
        val target = soloPlayingThroughInterrupt?.get()
        soloPlayingThroughInterrupt = null
        if (target == null) {
            _resumeAfterInterrupt.tryEmit(Unit)
            return
        }
        soloSparkAudio(keeping = target)
        if (!target.isPlaying) {
            target.play()
        }
        _resumeAfterInterrupt.tryEmit(Unit)
    }

    fun stopAll(reason: String = "") {
        @Suppress("UNUSED_VARIABLE")
        val _r = reason
        stopAllPlayback()
    }

    private fun hardSilence(player: Player) {
        player.pause()
        player.volume = 0f
    }

    companion object {
        val shared = MediaPlaybackCoordinator()
        const val RESUME_EVENT = NotificationNames.RESUME_PLAYBACK_AFTER_INTERRUPT
    }
}
