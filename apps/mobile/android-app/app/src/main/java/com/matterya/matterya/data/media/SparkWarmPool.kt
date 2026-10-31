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
import kotlinx.coroutines.launch
import java.util.Date

/**
 * iOS `SparkWarmPool.swift` — keeps nearby Sparks fully buffered for instant play.
 * Uses ExoPlayer slots instead of AVPlayer.
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
    private val maxSlots = 20

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
        val keep = window.map { it.id }.toSet() + inUse

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
            if (post.id in inUse) continue
            scope.launch { warm(post.id, url) }
        }
    }

    fun claim(postId: String): ExoPlayer? {
        inUse.add(postId)
        val slot = slots.remove(postId) ?: return null
        val player = slot.player
        player.pause()
        player.volume = 0f
        return player
    }

    fun markInUse(postId: String) {
        inUse.add(postId)
    }

    fun release(postId: String) {
        inUse.remove(postId)
    }

    fun park(postId: String, player: ExoPlayer) {
        inUse.remove(postId)
        player.pause()
        player.volume = 0f

        if (player.mediaItemCount == 0 || player.playbackState == Player.STATE_IDLE) {
            MediaPlaybackCoordinator.shared.unregister(player)
            player.release()
            return
        }

        val existing = slots[postId]
        if (existing != null && existing.player !== player) {
            MediaPlaybackCoordinator.shared.unregister(player)
            player.release()
            return
        }

        while (slots.size >= maxSlots) {
            val victim = slots
                .filter { it.key != postId }
                .minByOrNull { it.value.parkedAt.time }
                ?.key
            if (victim != null) evict(victim) else break
        }

        MediaPlaybackCoordinator.shared.register(player)
        slots[postId] = Slot(postId, player, Date())
        scope.launch { silentBufferFill(postId, player) }
    }

    fun isParked(postId: String, player: ExoPlayer): Boolean =
        slots[postId]?.player === player

    fun drain() {
        for (id in slots.keys.toList()) evict(id)
        warming.clear()
        inUse.clear()
    }

    fun silenceAllBuffered() {
        for (slot in slots.values) {
            slot.player.pause()
            slot.player.volume = 0f
        }
    }

    fun warmSingle(postId: String, url: String) {
        if (slots.containsKey(postId) || postId in inUse) return
        scope.launch { warm(postId, url) }
    }

    private suspend fun warm(postId: String, sourceUrl: String) {
        if (slots.containsKey(postId) || postId in inUse) return
        if (!warming.add(postId)) return
        try {
            val ctx = appContext ?: return
            val playUrl = if (ArchiveVideoPlayback.isArchiveUrl(sourceUrl)) {
                ArchiveVideoPlayback.resolvedPlaybackUrl(sourceUrl)
            } else {
                sourceUrl
            }
            if (slots.containsKey(postId) || postId in inUse) return

            val player = ExoPlayer.Builder(ctx).build().apply {
                volume = 0f
                playWhenReady = false
                repeatMode = Player.REPEAT_MODE_OFF
                setMediaItem(MediaItem.fromUri(playUrl))
                prepare()
            }

            if (slots.containsKey(postId) || postId in inUse) {
                player.release()
                return
            }

            while (slots.size >= maxSlots) {
                val victim = slots
                    .filter { it.key != postId }
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
