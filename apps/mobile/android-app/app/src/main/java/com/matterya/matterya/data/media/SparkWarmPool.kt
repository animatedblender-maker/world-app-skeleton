package com.matterya.matterya.data.media

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.model.CountryPost
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import java.lang.ref.WeakReference
import java.util.Date

/**
 * iOS `SparkWarmPool.swift` — keeps nearby Sparks fully buffered for instant play.
 * Uses ExoPlayer slots instead of AVPlayer.
 *
 * Feed→Sparks handoff: [exportPlaybackForHandoff] parks a live mid-clip player via
 * [parkContinuing]; Sparks [claim]s the same ExoPlayer without seek-to-0.
 */
class SparkWarmPool private constructor(private val appContext: Context?) {
    private data class Slot(
        val postId: String,
        val player: ExoPlayer,
        val parkedAt: Date,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val slots = linkedMapOf<String, Slot>()
    private val warming = mutableSetOf<String>()
    private val inUse = mutableSetOf<String>()
    /** Mid-clip Feed→Sparks/Hubs handoff — muted but keep decoding. */
    private val continuingIds = mutableSetOf<String>()
    /** Playheads (seconds) for Feed→Sparks continue without seek-to-0. */
    private val playheadsSec = mutableMapOf<String, Double>()
    /** Live surface players that can sync-export into the pool on Sparks/Hubs open. */
    private val livePlayers = mutableMapOf<String, WeakReference<ExoPlayer>>()
    private val maxSlots = 20

    /** Sticky: last successful [claim] was a mid-clip handoff (share/origin id race). */
    @Volatile
    var lastClaimWasContinuing: Boolean = false
        private set

    private val _exportTaken = MutableSharedFlow<Set<String>>(extraBufferCapacity = 4)
    /** Post IDs whose live ExoPlayer was parked into the pool (detach without release). */
    val exportTaken: SharedFlow<Set<String>> = _exportTaken.asSharedFlow()

    fun prepare(
        posts: List<CountryPost>,
        around: Int,
        ahead: Int = 8,
        behind: Int = 2,
    ) {
        if (posts.isEmpty()) return
        val resolveLo = maxOf(0, around - behind)
        val resolveHi = minOf(posts.size, around + ahead + 3)
        if (resolveLo < resolveHi) {
            if (AppConfig.archiveContentEnabled) {
                for (post in posts.subList(resolveLo, resolveHi)) {
                    val url = post.playableVideoUrl
                    if (url != null && ArchiveVideoPlayback.isArchiveUrl(url)) {
                        ArchiveVideoPlayback.warmResolve(url)
                    }
                }
            }
            ImageCache.shared.prefetchPostThumbnails(
                posts.subList(resolveLo, resolveHi),
                maxPixelSize = 360,
                aggressive = true,
            )
        }

        val lo = maxOf(0, around - behind)
        val hi = minOf(posts.size, around + ahead + 1)
        if (lo >= hi) return
        val window = posts.subList(lo, hi)
        // Never evict mid-clip handoff slots (share id may ≠ origin id).
        val keep = window.map { it.id }.toSet() + inUse + continuingIds

        for (id in slots.keys.toList()) {
            if (id !in keep) evict(id)
        }

        val ordered = window.sortedWith { a, b ->
            val ia = posts.indexOfFirst { it.id == a.id }.coerceAtLeast(0)
            val ib = posts.indexOfFirst { it.id == b.id }.coerceAtLeast(0)
            val da = kotlin.math.abs(ia - around)
            val db = kotlin.math.abs(ib - around)
            when {
                da != db -> da.compareTo(db)
                else -> ib.compareTo(ia)
            }
        }
        for (post in ordered) {
            val url = post.playableVideoUrl ?: continue
            // Never re-warm parked / claimed / in-flight / continuing (would race seek-to-0).
            if (post.id in inUse || post.id in continuingIds || post.id in slots || post.id in warming) {
                continue
            }
            scope.launch { warm(post.id, url) }
        }
    }

    /**
     * Hand a buffered player to the visible card (removes it from the pool).
     * Only marks [inUse] on success. Continuing handoff keeps decoding (no pause / seek-0).
     */
    fun claim(postId: String): ExoPlayer? {
        val slot = slots.remove(postId) ?: run {
            lastClaimWasContinuing = false
            return null
        }
        val player = slot.player
        if (player.mediaItemCount == 0 || player.playbackState == Player.STATE_IDLE) {
            MediaPlaybackCoordinator.shared.unregister(player)
            continuingIds.remove(postId)
            runCatching { player.release() }
            lastClaimWasContinuing = false
            return null
        }
        inUse.add(postId)
        val wasContinuing = continuingIds.remove(postId)
        lastClaimWasContinuing = wasContinuing
        livePlayers.remove(postId)
        player.volume = 0f
        if (wasContinuing) {
            // Keep decoding mid-clip — install unmutes without a t=0 blink.
            if (!player.isPlaying) {
                player.playWhenReady = true
                player.play()
            }
        } else {
            player.pause()
            player.playWhenReady = false
        }
        return player
    }

    /** Claim any parked continuing handoff player (share/origin id race). */
    fun claimFirstContinuing(): ExoPlayer? {
        val id = continuingIds.firstOrNull { slots.containsKey(it) } ?: return null
        return claim(id)
    }

    val hasContinuingParked: Boolean
        get() = continuingIds.any { slots.containsKey(it) }

    fun takeLastClaimWasContinuing(): Boolean {
        val v = lastClaimWasContinuing
        lastClaimWasContinuing = false
        return v
    }

    fun parkedPlayer(postId: String): ExoPlayer? = slots[postId]?.player

    fun markInUse(postId: String) {
        inUse.add(postId)
    }

    fun release(postId: String) {
        inUse.remove(postId)
    }

    /** Return a still-buffered player so scrolling back is instant (rewound to t≈0). */
    fun park(postId: String, player: ExoPlayer) {
        parkInternal(postId, player, continueFromCurrentTime = false)
    }

    /** Park without seeking to 0 — feed→Sparks/Hubs open continues mid-clip. */
    fun parkContinuing(postId: String, player: ExoPlayer) {
        parkInternal(postId, player, continueFromCurrentTime = true)
    }

    private fun parkInternal(postId: String, player: ExoPlayer, continueFromCurrentTime: Boolean) {
        inUse.remove(postId)
        livePlayers.remove(postId)

        if (player.mediaItemCount == 0 || player.playbackState == Player.STATE_IDLE) {
            MediaPlaybackCoordinator.shared.unregister(player)
            runCatching { player.release() }
            return
        }

        val existing = slots[postId]
        if (existing != null && existing.player !== player) {
            // Prefer mid-clip handoff over a cold t≈0 warm.
            if (continueFromCurrentTime) {
                evict(postId)
            } else {
                MediaPlaybackCoordinator.shared.unregister(player)
                runCatching { player.release() }
                return
            }
        }

        while (slots.size >= maxSlots) {
            val victim = slots
                .filter { it.key != postId && it.key !in continuingIds }
                .minByOrNull { it.value.parkedAt.time }
                ?.key
                ?: slots.filter { it.key != postId }.minByOrNull { it.value.parkedAt.time }?.key
            if (victim != null) evict(victim) else break
        }

        MediaPlaybackCoordinator.shared.register(player)
        slots[postId] = Slot(postId, player, Date())
        if (continueFromCurrentTime) {
            continuingIds.add(postId)
            val sec = player.currentPosition / 1000.0
            if (sec.isFinite() && sec >= 0.45) playheadsSec[postId] = sec
            // Butter handoff: stay muted but KEEP decoding while cover opens.
            player.volume = 0f
            if (!player.isPlaying) {
                player.playWhenReady = true
                player.play()
            }
        } else {
            continuingIds.remove(postId)
            playheadsSec.remove(postId)
            player.pause()
            player.volume = 0f
            player.playWhenReady = false
            scope.launch { silentBufferFill(postId, player) }
        }
    }

    /**
     * Bind a live feed/Sparks surface so [exportPlaybackForHandoff] can sync-park it.
     */
    fun attachLive(postId: String, player: ExoPlayer) {
        if (postId.isBlank()) return
        livePlayers[postId] = WeakReference(player)
    }

    fun detachLive(postId: String, player: ExoPlayer) {
        if (livePlayers[postId]?.get() === player) livePlayers.remove(postId)
    }

    /**
     * iOS `matteryaExportPlaybackForHandoff` — sync-park live mid-clip players into the pool
     * before Sparks/Hubs mounts, then notify surfaces to detach without releasing.
     */
    fun exportPlaybackForHandoff(postIds: Collection<String>) {
        val ids = postIds.map { it.trim() }.filter { it.isNotEmpty() }.toSet()
        if (ids.isEmpty()) return
        val taken = mutableSetOf<String>()
        for (id in ids) {
            val player = livePlayers.remove(id)?.get() ?: continue
            val sec = player.currentPosition / 1000.0
            if (sec.isFinite() && sec > 0.45) {
                parkContinuing(id, player)
            } else {
                park(id, player)
            }
            taken.add(id)
        }
        if (taken.isNotEmpty()) {
            _exportTaken.tryEmit(taken)
        }
    }

    /** Move a parked warm slot from one id → another (feed share → Sparks origin). */
    fun rekey(from: String, to: String) {
        val old = from.trim()
        val neu = to.trim()
        if (old.isEmpty() || neu.isEmpty() || old == neu) return

        val oldIsContinuing = old in continuingIds

        if (slots[old] != null && slots[neu] != null) {
            if (oldIsContinuing) {
                evict(neu)
            } else {
                evict(old)
                if (inUse.remove(old)) inUse.add(neu)
                if (continuingIds.remove(old)) continuingIds.add(neu)
                playheadsSec.remove(old)?.let { playheadsSec[neu] = it }
                return
            }
        } else if (slots[neu] != null && slots[old] == null) {
            if (inUse.remove(old)) inUse.add(neu)
            if (continuingIds.remove(old)) continuingIds.add(neu)
            playheadsSec.remove(old)?.let { playheadsSec[neu] = it }
            return
        }

        val slot = slots.remove(old)
        if (slot == null) {
            if (inUse.remove(old)) inUse.add(neu)
            if (continuingIds.remove(old)) continuingIds.add(neu)
            playheadsSec.remove(old)?.let { playheadsSec[neu] = it }
            return
        }
        slots[neu] = Slot(neu, slot.player, slot.parkedAt)
        if (inUse.remove(old)) inUse.add(neu)
        if (continuingIds.remove(old)) continuingIds.add(neu)
        playheadsSec.remove(old)?.let { playheadsSec[neu] = it }
        livePlayers.remove(old)?.let { livePlayers[neu] = it }
    }

    fun isParked(postId: String, player: ExoPlayer): Boolean =
        slots[postId]?.player === player

    fun drain() {
        for (id in slots.keys.toList()) evict(id)
        warming.clear()
        inUse.clear()
        continuingIds.clear()
        playheadsSec.clear()
        livePlayers.clear()
    }

    fun silenceAllBuffered() {
        for (slot in slots.values) {
            // Mid-clip Feed→Sparks handoff slots stay muted but keep decoding.
            if (slot.postId in continuingIds) {
                slot.player.volume = 0f
                if (!slot.player.isPlaying) {
                    slot.player.playWhenReady = true
                    slot.player.play()
                }
                continue
            }
            slot.player.pause()
            slot.player.volume = 0f
        }
    }

    /** Tab leave / Search browse — pause+mute every warm slot including handoff. */
    fun hardSilenceAllBuffered() {
        continuingIds.clear()
        for (slot in slots.values) {
            slot.player.pause()
            slot.player.volume = 0f
        }
    }

    /** Silence only slots that are currently playing (leave silent t≈0 buffers). */
    fun silencePlayingBuffered() {
        for (slot in slots.values) {
            if (slot.postId in continuingIds) {
                slot.player.volume = 0f
                continue
            }
            if (slot.player.isPlaying || slot.player.playbackState == Player.STATE_BUFFERING) {
                slot.player.pause()
                slot.player.volume = 0f
            }
        }
    }

    fun markContinuingHandoff(postId: String) {
        if (postId.isNotBlank()) continuingIds.add(postId)
    }

    fun clearContinuingHandoff(postId: String? = null) {
        if (postId == null) {
            continuingIds.clear()
            playheadsSec.clear()
        } else {
            continuingIds.remove(postId)
            playheadsSec.remove(postId)
        }
    }

    fun clearContinueFlag(postId: String) {
        continuingIds.remove(postId)
    }

    fun shouldContinueFromCurrentTime(postId: String): Boolean = postId in continuingIds

    /** Remember mid-clip playhead before Feed player tears down (t > ~0.45s). */
    fun rememberPlayhead(postId: String, seconds: Double) {
        if (postId.isBlank()) return
        if (!seconds.isFinite() || seconds < 0.45) return
        playheadsSec[postId] = seconds
        continuingIds.add(postId)
    }

    fun peekPlayheadSeconds(postId: String): Double? = playheadsSec[postId]

    /** Consume saved playhead for first Sparks paint (or null). */
    fun takePlayheadSeconds(postId: String): Double? = playheadsSec.remove(postId)

    fun warmSingle(postId: String, url: String) {
        if (slots.containsKey(postId) || postId in inUse || postId in continuingIds) return
        scope.launch { warm(postId, url) }
    }

    private suspend fun warm(postId: String, sourceUrl: String) {
        if (slots.containsKey(postId) || postId in inUse || postId in continuingIds) return
        if (!warming.add(postId)) return
        try {
            val ctx = appContext ?: return
            val playUrl = if (ArchiveVideoPlayback.isArchiveUrl(sourceUrl)) {
                ArchiveVideoPlayback.resolvedPlaybackUrl(sourceUrl)
            } else {
                sourceUrl
            }
            if (slots.containsKey(postId) || postId in inUse || postId in continuingIds) return

            val player = ExoPlayer.Builder(ctx).build().apply {
                volume = 0f
                playWhenReady = false
                repeatMode = Player.REPEAT_MODE_OFF
                setMediaItem(MediaItem.fromUri(playUrl))
                prepare()
            }

            if (slots.containsKey(postId) || postId in inUse || postId in continuingIds) {
                player.release()
                return
            }

            while (slots.size >= maxSlots) {
                val victim = slots
                    .filter { it.key != postId && it.key !in continuingIds }
                    .minByOrNull { it.value.parkedAt.time }
                    ?.key
                if (victim != null) evict(victim) else break
            }

            MediaPlaybackCoordinator.shared.register(player)
            slots[postId] = Slot(postId, player, Date())
            silentBufferFill(postId, player)
        } finally {
            warming.remove(postId)
        }
    }

    private suspend fun silentBufferFill(postId: String, player: ExoPlayer) {
        repeat(80) {
            if (!isParked(postId, player)) return
            if (postId in continuingIds) return
            if (player.mediaItemCount == 0) return
            if (player.playbackState == Player.STATE_READY) {
                player.volume = 0f
                player.pause()
                player.seekTo(0)
                return
            }
            if (player.playbackState == Player.STATE_IDLE) return
            delay(40)
        }
    }

    private fun evict(postId: String) {
        val slot = slots.remove(postId) ?: return
        continuingIds.remove(postId)
        playheadsSec.remove(postId)
        slot.player.pause()
        slot.player.volume = 0f
        slot.player.clearMediaItems()
        MediaPlaybackCoordinator.shared.unregister(slot.player)
        slot.player.release()
    }

    companion object {
        @Volatile private var instance: SparkWarmPool? = null

        val shared: SparkWarmPool
            get() = instance ?: SparkWarmPool(null).also { instance = it }

        fun init(context: Context): SparkWarmPool {
            return instance ?: synchronized(this) {
                instance ?: SparkWarmPool(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): SparkWarmPool = init(context)

        fun isAtStart(player: ExoPlayer, epsilonMs: Long = 50): Boolean {
            val t = player.currentPosition
            return t in 0 until epsilonMs
        }
    }
}
