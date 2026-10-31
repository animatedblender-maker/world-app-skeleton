package com.matterya.matterya.data.letters

import android.content.Context
import com.matterya.matterya.model.LetterFlightEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.Calendar
import java.util.Date
import java.util.UUID
import kotlin.math.max
import kotlin.random.Random

enum class LetterDeliveryStatus {
    Composing, Sealing, InFlight, Delivered, AwaitingReply, Replied, Expired, PenFriend
}

enum class PenFriendRequestKind {
    Chat, Follow, Profile;

    val title: String
        get() = when (this) {
            Chat -> "Open chat"
            Follow -> "Follow"
            Profile -> "See profile"
        }

    val subtitle: String
        get() = when (this) {
            Chat -> "Message in normal chats — only if mutual"
            Follow -> "Follow each other — only if mutual"
            Profile -> "Reveal real identity — only if mutual"
        }
}

@Serializable
data class LetterMessage(
    val id: String,
    val authorIsMe: Boolean,
    val body: String,
    val createdAtEpochMs: Long,
    val fromCountryCode: String,
    val fromCountryName: String,
)

@Serializable
data class PenFriendRequestState(
    val iRequested: Boolean = false,
    val theyRequested: Boolean = false,
) {
    val isMutual: Boolean get() = iRequested && theyRequested
}

@Serializable
data class LetterThread(
    val id: String,
    val strangerId: String,
    val destinationCountryCode: String,
    val destinationCountryName: String,
    val messages: List<LetterMessage>,
    val status: String,
    val createdAtEpochMs: Long,
    val replyDeadlineEpochMs: Long? = null,
    val lastActivityAtEpochMs: Long,
    val chatRequest: PenFriendRequestState = PenFriendRequestState(),
    val followRequest: PenFriendRequestState = PenFriendRequestState(),
    val profileRequest: PenFriendRequestState = PenFriendRequestState(),
    val startedByMe: Boolean,
) {
    val deliveryStatus: LetterDeliveryStatus
        get() = runCatching { LetterDeliveryStatus.valueOf(status) }.getOrDefault(LetterDeliveryStatus.InFlight)

    val isPenFriend: Boolean
        get() = messages.size >= 2 &&
            messages.any { it.authorIsMe } &&
            messages.any { !it.authorIsMe }

    val latestMessage: LetterMessage? get() = messages.lastOrNull()

    val awaitingMyReply: Boolean
        get() {
            val last = messages.lastOrNull() ?: return false
            return !last.authorIsMe && deliveryStatus != LetterDeliveryStatus.Expired
        }

    val awaitingTheirReply: Boolean
        get() {
            val last = messages.lastOrNull() ?: return false
            return last.authorIsMe && deliveryStatus in setOf(
                LetterDeliveryStatus.AwaitingReply,
                LetterDeliveryStatus.Delivered,
                LetterDeliveryStatus.InFlight,
            )
        }

    fun requestState(kind: PenFriendRequestKind): PenFriendRequestState = when (kind) {
        PenFriendRequestKind.Chat -> chatRequest
        PenFriendRequestKind.Follow -> followRequest
        PenFriendRequestKind.Profile -> profileRequest
    }
}

@Serializable
data class DailyLetterQuota(
    val dayKey: String,
    val sentCount: Int,
) {
    val remaining: Int get() = max(0, DAILY_LIMIT - sentCount)
    val isExhausted: Boolean get() = remaining == 0

    companion object {
        const val DAILY_LIMIT = 5
    }
}

/** iOS `LettersService.swift` — local store, 5/day quota, demo replies. */
class LettersService private constructor(context: Context) {
    private val prefs = context.getSharedPreferences("matterya_letters", Context.MODE_PRIVATE)
    private val storeKey = "matterya.letters.store.v1"
    private val quotaKey = "matterya.letters.quota.v1"
    private val seedKey = "matterya.letters.seeded.v1"
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _threads = MutableStateFlow(loadThreads())
    val threads: StateFlow<List<LetterThread>> = _threads.asStateFlow()

    private val _quota = MutableStateFlow(loadQuota())
    val quota: StateFlow<DailyLetterQuota> = _quota.asStateFlow()

    private val _activeFlight = MutableStateFlow<LetterFlightEvent?>(null)
    val activeFlight: StateFlow<LetterFlightEvent?> = _activeFlight.asStateFlow()

    init {
        rolloverQuotaIfNeeded()
        expireStaleThreads()
        seedDemoIfNeeded()
    }

    sealed class SendError(message: String) : Exception(message) {
        data object EmptyBody : SendError("Write something before sealing the letter.")
        data object QuotaExhausted : SendError("You've sent all 5 letters today. New ones unlock at local midnight.")
        data object TooLong : SendError("Letters are short notes — keep it under 500 characters.")
    }

    companion object {
        fun localDayKey(date: Date = Date()): String {
            val cal = Calendar.getInstance().apply { time = date }
            val y = cal.get(Calendar.YEAR)
            val m = cal.get(Calendar.MONTH) + 1
            val d = cal.get(Calendar.DAY_OF_MONTH)
            return "%04d-%02d-%02d".format(y, m, d)
        }

        data class Destination(val code: String, val name: String)

        val destinations = listOf(
            Destination("JP", "Japan"), Destination("BR", "Brazil"), Destination("IS", "Iceland"),
            Destination("MA", "Morocco"), Destination("NZ", "New Zealand"), Destination("NO", "Norway"),
            Destination("KE", "Kenya"), Destination("CL", "Chile"), Destination("KR", "South Korea"),
            Destination("PT", "Portugal"), Destination("IN", "India"), Destination("CA", "Canada"),
            Destination("EG", "Egypt"), Destination("PE", "Peru"), Destination("FI", "Finland"),
            Destination("TH", "Thailand"), Destination("GR", "Greece"), Destination("AR", "Argentina"),
            Destination("VN", "Vietnam"), Destination("IE", "Ireland"), Destination("ZA", "South Africa"),
            Destination("TR", "Turkey"), Destination("PH", "Philippines"), Destination("SE", "Sweden"),
            Destination("MX", "Mexico"), Destination("AU", "Australia"), Destination("IT", "Italy"),
            Destination("FR", "France"), Destination("ES", "Spain"), Destination("PL", "Poland"),
        )

        fun randomDestination(excluding: String?): Destination {
            val exclude = excluding?.uppercase()
            val pool = destinations.filter { it.code != exclude }
            return pool.randomOrNull() ?: destinations[0]
        }

        private val demoReplyBodies = listOf(
            "Your words landed softly. I don't know your name, only this country of mine — and that felt like enough.",
            "I folded your letter next to my window. The world feels a little smaller tonight.",
            "Thank you for writing to a stranger. Here's one true thing: I smiled reading this.",
            "I almost never answer cold messages. Letters are different. Tell me more when you can.",
            "Somewhere between your sky and mine, this found me. I'm glad it did.",
        )

        @Volatile private var instance: LettersService? = null
        fun get(context: Context): LettersService =
            instance ?: synchronized(this) {
                instance ?: LettersService(context.applicationContext).also { instance = it }
            }
    }

    fun rolloverQuotaIfNeeded(now: Date = Date()) {
        val today = localDayKey(now)
        if (_quota.value.dayKey != today) {
            _quota.value = DailyLetterQuota(today, 0)
            persistQuota()
        }
    }

    val remainingToday: Int
        get() {
            rolloverQuotaIfNeeded()
            return _quota.value.remaining
        }

    val sentToday: Int
        get() {
            rolloverQuotaIfNeeded()
            return _quota.value.sentCount
        }

    val secondsUntilLocalMidnight: Long
        get() {
            val cal = Calendar.getInstance()
            cal.add(Calendar.DAY_OF_YEAR, 1)
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            return max(0L, (cal.timeInMillis - System.currentTimeMillis()) / 1000)
        }

    val inboxThreads: List<LetterThread>
        get() = _threads.value
            .filter { it.awaitingMyReply || (!it.startedByMe && it.messages.size == 1) }
            .sortedByDescending { it.lastActivityAtEpochMs }

    val inFlightThreads: List<LetterThread>
        get() = _threads.value
            .filter {
                it.startedByMe && (
                    it.awaitingTheirReply ||
                        it.deliveryStatus == LetterDeliveryStatus.InFlight ||
                        it.deliveryStatus == LetterDeliveryStatus.Delivered
                    )
            }
            .sortedByDescending { it.lastActivityAtEpochMs }

    val penFriendThreads: List<LetterThread>
        get() = _threads.value.filter { it.isPenFriend }.sortedByDescending { it.lastActivityAtEpochMs }

    val unreadIncomingCount: Int get() = inboxThreads.size

    fun thread(id: String): LetterThread? = _threads.value.firstOrNull { it.id == id }

    fun sendNewLetter(body: String, myCountryCode: String?, myCountryName: String?): LetterFlightEvent {
        rolloverQuotaIfNeeded()
        val trimmed = body.trim()
        if (trimmed.isEmpty()) throw SendError.EmptyBody
        if (trimmed.length > 500) throw SendError.TooLong
        if (_quota.value.isExhausted) throw SendError.QuotaExhausted

        val dest = randomDestination(myCountryCode)
        val now = System.currentTimeMillis()
        val message = LetterMessage(
            id = UUID.randomUUID().toString(),
            authorIsMe = true,
            body = trimmed,
            createdAtEpochMs = now,
            fromCountryCode = (myCountryCode ?: "XX").uppercase(),
            fromCountryName = myCountryName ?: "Somewhere",
        )
        val thread = LetterThread(
            id = UUID.randomUUID().toString(),
            strangerId = "stranger-${UUID.randomUUID().toString().take(8)}",
            destinationCountryCode = dest.code,
            destinationCountryName = dest.name,
            messages = listOf(message),
            status = LetterDeliveryStatus.InFlight.name,
            createdAtEpochMs = now,
            replyDeadlineEpochMs = now + 24 * 60 * 60 * 1000L,
            lastActivityAtEpochMs = now,
            startedByMe = true,
        )
        _threads.update { listOf(thread) + it }
        _quota.update { it.copy(sentCount = it.sentCount + 1) }
        persistAll()
        val event = LetterFlightEvent(
            threadId = thread.id,
            body = trimmed,
            slotUsed = _quota.value.sentCount,
            dailyLimit = DailyLetterQuota.DAILY_LIMIT,
            destinationCountryCode = dest.code,
            destinationCountryName = dest.name,
        )
        _activeFlight.value = event
        return event
    }

    fun completeFlight(threadId: String) {
        val list = _threads.value.toMutableList()
        val index = list.indexOfFirst { it.id == threadId }
        if (index < 0) {
            _activeFlight.value = null
            return
        }
        val t = list[index]
        val already = t.deliveryStatus in setOf(
            LetterDeliveryStatus.AwaitingReply,
            LetterDeliveryStatus.PenFriend,
            LetterDeliveryStatus.Replied,
        )
        if (!already) {
            list[index] = t.copy(
                status = LetterDeliveryStatus.AwaitingReply.name,
                lastActivityAtEpochMs = System.currentTimeMillis(),
                replyDeadlineEpochMs = t.replyDeadlineEpochMs
                    ?: (System.currentTimeMillis() + 24 * 60 * 60 * 1000L),
            )
            _threads.value = list
            persistThreads()
            scheduleDemoReply(threadId)
        }
        if (_activeFlight.value?.threadId == threadId) _activeFlight.value = null
    }

    fun reply(threadId: String, body: String, myCountryCode: String?, myCountryName: String?): LetterThread {
        val trimmed = body.trim()
        if (trimmed.isEmpty()) throw SendError.EmptyBody
        if (trimmed.length > 500) throw SendError.TooLong
        val list = _threads.value.toMutableList()
        val index = list.indexOfFirst { it.id == threadId }
        if (index < 0) throw SendError.EmptyBody
        expireIfNeeded(list, index)
        if (list[index].deliveryStatus == LetterDeliveryStatus.Expired) throw SendError.EmptyBody
        val now = System.currentTimeMillis()
        val message = LetterMessage(
            id = UUID.randomUUID().toString(),
            authorIsMe = true,
            body = trimmed,
            createdAtEpochMs = now,
            fromCountryCode = (myCountryCode ?: "XX").uppercase(),
            fromCountryName = myCountryName ?: "Somewhere",
        )
        val t = list[index]
        list[index] = t.copy(
            messages = t.messages + message,
            status = LetterDeliveryStatus.PenFriend.name,
            replyDeadlineEpochMs = now + 24 * 60 * 60 * 1000L,
            lastActivityAtEpochMs = now,
        )
        _threads.value = list
        persistThreads()
        scheduleDemoReply(threadId, delaySeconds = Random.nextDouble(12.0, 40.0))
        return list[index]
    }

    fun request(kind: PenFriendRequestKind, threadId: String) {
        val list = _threads.value.toMutableList()
        val index = list.indexOfFirst { it.id == threadId }
        if (index < 0) return
        if (!list[index].isPenFriend) return
        val t = list[index]
        list[index] = when (kind) {
            PenFriendRequestKind.Chat -> t.copy(
                chatRequest = t.chatRequest.copy(
                    iRequested = true,
                    theyRequested = t.chatRequest.theyRequested || Random.nextBoolean(),
                ),
                lastActivityAtEpochMs = System.currentTimeMillis(),
            )
            PenFriendRequestKind.Follow -> t.copy(
                followRequest = t.followRequest.copy(
                    iRequested = true,
                    theyRequested = t.followRequest.theyRequested || Random.nextBoolean(),
                ),
                lastActivityAtEpochMs = System.currentTimeMillis(),
            )
            PenFriendRequestKind.Profile -> t.copy(
                profileRequest = t.profileRequest.copy(
                    iRequested = true,
                    theyRequested = t.profileRequest.theyRequested || Random.nextBoolean(),
                ),
                lastActivityAtEpochMs = System.currentTimeMillis(),
            )
        }
        _threads.value = list
        persistThreads()
    }

    fun expireStaleThreads(now: Long = System.currentTimeMillis()) {
        val list = _threads.value.toMutableList()
        var changed = false
        for (i in list.indices) {
            if (expireIfNeeded(list, i, now)) changed = true
        }
        if (changed) {
            _threads.value = list
            persistThreads()
        }
    }

    private fun expireIfNeeded(list: MutableList<LetterThread>, index: Int, now: Long = System.currentTimeMillis()): Boolean {
        val t = list[index]
        val deadline = t.replyDeadlineEpochMs ?: return false
        if (t.deliveryStatus != LetterDeliveryStatus.AwaitingReply &&
            t.deliveryStatus != LetterDeliveryStatus.Delivered
        ) return false
        if (t.messages.lastOrNull()?.authorIsMe != true) return false
        if (now < deadline) return false
        list[index] = t.copy(status = LetterDeliveryStatus.Expired.name)
        return true
    }

    fun dismissActiveFlight() {
        _activeFlight.value = null
    }

    private fun seedDemoIfNeeded() {
        if (prefs.getBoolean(seedKey, false)) return
        prefs.edit().putBoolean(seedKey, true).apply()
        val samples = listOf(
            Triple("JP", "Japan", "Hello from a rainy afternoon train. What does the sky look like where you are?"),
            Triple("BR", "Brazil", "I left a note under a mango tree once. Writing to a stranger feels the same — soft and a little brave."),
            Triple("IS", "Iceland", "The wind here writes louder than I do. Tell me one quiet thing about your day."),
        )
        val now = System.currentTimeMillis()
        val seeded = samples.mapIndexed { i, sample ->
            val msg = LetterMessage(
                id = UUID.randomUUID().toString(),
                authorIsMe = false,
                body = sample.third,
                createdAtEpochMs = now - 3600_000L * (i + 1),
                fromCountryCode = sample.first,
                fromCountryName = sample.second,
            )
            LetterThread(
                id = UUID.randomUUID().toString(),
                strangerId = "stranger-seed-$i",
                destinationCountryCode = sample.first,
                destinationCountryName = sample.second,
                messages = listOf(msg),
                status = LetterDeliveryStatus.AwaitingReply.name,
                createdAtEpochMs = msg.createdAtEpochMs,
                replyDeadlineEpochMs = now + 20 * 60 * 60 * 1000L,
                lastActivityAtEpochMs = msg.createdAtEpochMs,
                startedByMe = false,
            )
        }
        _threads.update { it + seeded }
        persistThreads()
    }

    private fun scheduleDemoReply(threadId: String, delaySeconds: Double = 8.0) {
        scope.launch {
            delay((delaySeconds * 1000).toLong())
            val list = _threads.value.toMutableList()
            val index = list.indexOfFirst { it.id == threadId }
            if (index < 0) return@launch
            if (list[index].messages.lastOrNull()?.authorIsMe != true) return@launch
            if (list[index].deliveryStatus == LetterDeliveryStatus.Expired) return@launch
            if (Random.nextDouble() >= 0.72) return@launch
            val replyBody = demoReplyBodies.random()
            val now = System.currentTimeMillis()
            val t = list[index]
            val message = LetterMessage(
                id = UUID.randomUUID().toString(),
                authorIsMe = false,
                body = replyBody,
                createdAtEpochMs = now,
                fromCountryCode = t.destinationCountryCode,
                fromCountryName = t.destinationCountryName,
            )
            list[index] = t.copy(
                messages = t.messages + message,
                status = LetterDeliveryStatus.PenFriend.name,
                replyDeadlineEpochMs = now + 24 * 60 * 60 * 1000L,
                lastActivityAtEpochMs = now,
            )
            _threads.value = list
            persistThreads()
        }
    }

    private fun persistAll() {
        persistQuota()
        persistThreads()
    }

    private fun persistQuota() {
        prefs.edit().putString(quotaKey, json.encodeToString(_quota.value)).apply()
    }

    private fun persistThreads() {
        prefs.edit().putString(storeKey, json.encodeToString(_threads.value)).apply()
    }

    private fun loadQuota(): DailyLetterQuota {
        val today = localDayKey()
        val raw = prefs.getString(quotaKey, null) ?: return DailyLetterQuota(today, 0)
        val decoded = runCatching { json.decodeFromString<DailyLetterQuota>(raw) }.getOrNull()
            ?: return DailyLetterQuota(today, 0)
        return if (decoded.dayKey != today) DailyLetterQuota(today, 0) else decoded
    }

    private fun loadThreads(): List<LetterThread> {
        val raw = prefs.getString(storeKey, null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<LetterThread>>(raw) }.getOrDefault(emptyList())
    }
}
