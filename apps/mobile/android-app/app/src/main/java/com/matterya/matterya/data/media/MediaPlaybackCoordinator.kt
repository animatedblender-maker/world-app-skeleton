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
 * Continuous Hubs mini is protected across tab hops.
 */
class MediaPlaybackCoordinator private constructor() {
    private val players = mutableListOf<WeakReference<Player>>()
    private var soloPlayer: WeakReference<Player>? = null
    private var soloPlayingThroughInterrupt: WeakReference<Player>? = null
    private var protectedContinuousPlayer: WeakReference<Player>? = null
    private var protectedForegroundWatchPlayer: WeakReference<Player>? = null

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
        if (protectedContinuousPlayer?.get() === player) protectedContinuousPlayer = null
        if (protectedForegroundWatchPlayer?.get() === player) protectedForegroundWatchPlayer = null
    }

    fun isSolo(player: Player?): Boolean {
        if (player == null) return false
        return soloPlayer?.get() === player
    }

    /** Mark the global continuous Hubs player so tab switches never kill mini audio. */
    fun protectContinuous(player: Player?) {
        protectedContinuousPlayer = player?.let { WeakReference(it) }
        if (player != null) {
            soloPlayer = WeakReference(player)
            register(player)
        }
    }

    fun clearContinuousProtection() {
        protectedContinuousPlayer = null
    }

    fun protectForegroundWatch(player: Player?) {
        protectedForegroundWatchPlayer = player?.let { WeakReference(it) }
        if (player != null) {
            soloPlayer = WeakReference(player)
            register(player)
        }
    }

    fun clearForegroundWatchProtection(forPlayer: Player? = null) {
        if (forPlayer != null) {
            if (protectedForegroundWatchPlayer?.get() === forPlayer) {
                protectedForegroundWatchPlayer = null
            }
        } else {
            protectedForegroundWatchPlayer = null
        }
    }

    val continuousHubPlayer: Player? get() = protectedContinuousPlayer?.get()

    private fun isProtected(player: Player): Boolean {
        if (protectedContinuousPlayer?.get() === player) return true
        if (protectedForegroundWatchPlayer?.get() === player) return true
        return false
    }

    /**
     * Leave Feed / open Search — kill feed+Sparks audio. Continuous Hubs mini stays.
     * Lighter than `resetAll` remount storms: no item teardown, next-beat safe.
     */
    fun silenceFeedSparksAudioPreservingHubsMini() {
        _sparkPageEpoch.value = _sparkPageEpoch.value + 1uL
        soloPlayingThroughInterrupt = null
        protectedForegroundWatchPlayer = null
        val keep = protectedContinuousPlayer?.get()
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (keep != null && p === keep) continue
            hardSilence(p)
        }
        SparkWarmPool.shared.hardSilenceAllBuffered()
        soloPlayer = keep?.let { WeakReference(it) }
    }

    /**
     * Hard rule: if video is off-screen / tab changed / Sparks closed — silence everything
     * except protected continuous Hubs (and intentional foreground watch).
     */
    fun silenceAllOffScreenAudio() {
        _sparkPageEpoch.value = _sparkPageEpoch.value + 1uL
        val keepContinuous = protectedContinuousPlayer?.get()
        val keepWatch = protectedForegroundWatchPlayer?.get()
        soloPlayingThroughInterrupt = null

        // Feather path: continuous hubs already solo + rolling → skip heavy walk when quiet.
        if (keepContinuous != null &&
            keepWatch == null &&
            keepContinuous.isPlaying &&
            soloPlayer?.get() === keepContinuous
        ) {
            var othersLive = false
            for (ref in players.toList()) {
                val p = ref.get() ?: continue
                if (p === keepContinuous) continue
                if (p.isPlaying || p.playbackState == Player.STATE_BUFFERING || p.volume > 0.01f) {
                    othersLive = true
                    hardSilence(p)
                }
            }
            if (!othersLive) {
                SparkWarmPool.shared.silencePlayingBuffered()
                return
            }
        }

        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (keepContinuous != null && p === keepContinuous) continue
            if (keepWatch != null && p === keepWatch) continue
            hardSilence(p)
        }
        SparkWarmPool.shared.silenceAllBuffered()
        soloPlayer = when {
            keepContinuous != null -> WeakReference(keepContinuous)
            keepWatch != null -> WeakReference(keepWatch)
            else -> null
        }
    }

    /** Re-claim continuous hubs audio after tab/nav silence. */
    fun ensureContinuingHubsPlayback(userMuted: Boolean = false) {
        val keep = protectedContinuousPlayer?.get() ?: return
        soloPlayer = WeakReference(keep)
        register(keep)
        keep.volume = if (userMuted) 0f else 1f
        if (!keep.isPlaying) {
            keep.play()
        }
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
            protectedContinuousPlayer = null
            protectedForegroundWatchPlayer = null
        }
    }

    fun pauseAll(except: Player? = null) {
        val protected = except ?: protectedContinuousPlayer?.get()
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (protected != null && p === protected) continue
            hardSilence(p)
        }
        soloPlayer = protected?.let { WeakReference(it) }
        SparkWarmPool.shared.silenceAllBuffered()
    }

    fun silenceForSparkPageChange() {
        _sparkPageEpoch.value = _sparkPageEpoch.value + 1uL
        val previous = soloPlayer?.get()
        val keepContinuous = protectedContinuousPlayer?.get()
        soloPlayer = keepContinuous?.let { WeakReference(it) }
        soloPlayingThroughInterrupt = null
        if (previous != null && previous !== keepContinuous) {
            hardSilence(previous)
        }
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (keepContinuous != null && p === keepContinuous) continue
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
            keeping?.let { if (!isProtected(it)) hardSilence(it) }
            return false
        }
        val continuous = protectedContinuousPlayer?.get()
        // Live continuous Hubs wins over feed/Sparks claims unless paused.
        if (continuous != null &&
            keeping !== continuous &&
            continuous.isPlaying
        ) {
            keeping?.let { hardSilence(it) }
            soloPlayer = WeakReference(continuous)
            return false
        }
        soloPlayer = keeping?.let { WeakReference(it) }
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (keeping != null && p === keeping) continue
            if (continuous != null && p === continuous) continue
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
        val continuous = protectedContinuousPlayer?.get()
        for (ref in players.toList()) {
            val p = ref.get() ?: continue
            if (keep != null && p === keep) continue
            if (continuous != null && p === continuous) continue
            hardSilence(p)
        }
        if (keep != null) soloPlayer = WeakReference(keep)
    }

    val currentSoloPlayer: Player? get() = soloPlayer?.get()

    fun allowPlaybackIfSolo(player: Player, pageEpoch: ULong? = null): Boolean {
        if (isProtected(player)) return true
        val continuous = protectedContinuousPlayer?.get()
        if (continuous != null &&
            player !== continuous &&
            continuous.isPlaying
        ) {
            hardSilence(player)
            return false
        }
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
        val continuous = protectedContinuousPlayer?.get()
        val solo = soloPlayer?.get()
        if (solo != null &&
            solo !== continuous &&
            (solo.isPlaying || solo.playbackState == Player.STATE_BUFFERING)
        ) {
            soloPlayingThroughInterrupt = WeakReference(solo)
        }
        // Keep continuous hubs rolling through Control Center / app switcher.
        if (continuous != null) {
            soloPlayer = WeakReference(continuous)
            if (!continuous.isPlaying) continuous.play()
        }
    }

    fun resumeAfterInterrupt() {
        val continuous = protectedContinuousPlayer?.get()
        if (continuous != null) {
            soloPlayer = WeakReference(continuous)
            if (!continuous.isPlaying) continuous.play()
            soloPlayingThroughInterrupt = null
            _resumeAfterInterrupt.tryEmit(Unit)
            return
        }
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
