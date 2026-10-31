package com.matterya.matterya.data.calls

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.RingtoneManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.min
import kotlin.math.sin

/** iOS `CallSoundService.swift` — ringtone / synthetic tones. */
class CallSoundService private constructor(private val appContext: Context?) {
    enum class Pattern {
        IncomingRing,
        OutgoingRing,
        TryingToReach,
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var loopJob: Job? = null
    private var activePattern: Pattern? = null
    private var ringtonePlayer: MediaPlayer? = null
    private var audioTrack: AudioTrack? = null

    fun start(pattern: Pattern) {
        if (activePattern == pattern) return
        val callManager = CallSessionManager.shared
        if (callManager.isConnecting || callManager.isActive) return
        stop()
        activePattern = pattern
        configureSession()

        if (pattern == Pattern.IncomingRing && startIncomingRingtone()) {
            return
        }

        loopJob = scope.launch {
            while (isActive) {
                playBurst(pattern)
                delay((pauseDuration(pattern) * 1000).toLong())
            }
        }
    }

    fun stop() {
        loopJob?.cancel()
        loopJob = null
        activePattern = null
        runCatching { ringtonePlayer?.stop() }
        ringtonePlayer?.release()
        ringtonePlayer = null
        runCatching { audioTrack?.stop() }
        audioTrack?.release()
        audioTrack = null
    }

    private fun startIncomingRingtone(): Boolean {
        val ctx = appContext ?: return false
        // Prefer bundled asset if present; fall back to system ringtone.
        return runCatching {
            val afd = runCatching { ctx.assets.openFd("MatteryaCallRing.mp3") }.getOrNull()
            val player = MediaPlayer()
            if (afd != null) {
                player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
            } else {
                val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                    ?: return false
                player.setDataSource(ctx, uri)
            }
            player.isLooping = true
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.prepare()
            player.start()
            ringtonePlayer = player
            true
        }.getOrDefault(false)
    }

    private fun configureSession() {
        val ctx = appContext ?: return
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        am.isSpeakerphoneOn = true
    }

    private fun pauseDuration(pattern: Pattern): Double = when (pattern) {
        Pattern.IncomingRing, Pattern.OutgoingRing -> 2.0
        Pattern.TryingToReach -> 2.8
    }

    private suspend fun playBurst(pattern: Pattern) {
        when (pattern) {
            Pattern.IncomingRing -> {
                playTone(392.0, 0.11, 0.36f)
                delay(55)
                playTone(523.25, 0.11, 0.38f)
                delay(55)
                playTone(659.25, 0.24, 0.4f)
                delay(90)
                playTone(440.0, 0.1, 0.3f)
                delay(50)
                playTone(659.25, 0.22, 0.34f)
            }
            Pattern.OutgoingRing -> {
                playTone(440.0, 0.18, 0.28f)
                delay(100)
                playTone(554.37, 0.18, 0.28f)
                delay(100)
                playTone(659.25, 0.24, 0.3f)
            }
            Pattern.TryingToReach -> {
                playTone(294.0, 0.18, 0.22f)
                delay(90)
                playTone(330.0, 0.16, 0.18f)
            }
        }
    }

    private fun playTone(frequency: Double, duration: Double, volume: Float) {
        val sampleRate = 44_100
        val frameCount = (duration * sampleRate).toInt().coerceAtLeast(1)
        val buffer = ShortArray(frameCount)
        val angular = 2.0 * Math.PI * frequency / sampleRate
        val attack = sampleRate * 0.015
        val release = sampleRate * 0.04
        val total = frameCount.toDouble()
        for (frame in 0 until frameCount) {
            val t = frame.toDouble()
            val attackEnv = min(1.0, t / attack)
            val releaseEnv = min(1.0, (total - t) / release)
            val envelope = min(attackEnv, releaseEnv).toFloat()
            val sample = (sin(angular * t) * envelope * volume * Short.MAX_VALUE).toInt()
            buffer[frame] = sample.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        }

        val minBuf = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(maxOf(minBuf, frameCount * 2))
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        audioTrack?.release()
        audioTrack = track
        track.write(buffer, 0, buffer.size)
        track.play()
        // Wait for tone to finish roughly
        Thread.sleep((duration * 1000).toLong().coerceAtLeast(20))
        runCatching { track.stop() }
        track.release()
        if (audioTrack === track) audioTrack = null
    }

    companion object {
        @Volatile private var instance: CallSoundService? = null

        val shared: CallSoundService
            get() = instance ?: CallSoundService(null).also { instance = it }

        fun init(context: Context): CallSoundService {
            return instance ?: synchronized(this) {
                instance ?: CallSoundService(context.applicationContext).also { instance = it }
            }
        }

        fun get(context: Context): CallSoundService = init(context)
    }
}
