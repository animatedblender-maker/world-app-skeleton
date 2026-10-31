package com.matterya.matterya.data.social

import android.content.Context
import com.matterya.matterya.model.CountryPost
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.Date

@Serializable
data class BlockedAccount(
    val userId: String,
    val username: String? = null,
    val displayName: String? = null,
    val blockedAtEpochMs: Long = System.currentTimeMillis(),
) {
    val id: String get() = userId
    val label: String
        get() = displayName ?: username?.let { "@$it" } ?: userId
}

/** iOS `BlockService.swift` — local blocked accounts store. */
class BlockService private constructor(context: Context) {
    private val prefs = context.getSharedPreferences("matterya_block", Context.MODE_PRIVATE)
    private val storageKey = "blocked_accounts_v1"
    private val json = Json { ignoreUnknownKeys = true }
    private val _blocked = mutableListOf<BlockedAccount>()

    val blocked: List<BlockedAccount> get() = _blocked.toList()

    init { load() }

    fun isBlocked(userId: String): Boolean = _blocked.any { it.userId == userId }

    fun block(userId: String, username: String? = null, displayName: String? = null) {
        if (userId.isEmpty() || isBlocked(userId)) return
        _blocked.add(0, BlockedAccount(userId, username, displayName, System.currentTimeMillis()))
        persist()
    }

    fun unblock(userId: String) {
        _blocked.removeAll { it.userId == userId }
        persist()
    }

    fun filterPosts(posts: List<CountryPost>): List<CountryPost> {
        val ids = _blocked.map { it.userId }.toSet()
        if (ids.isEmpty()) return posts
        return posts.filter { it.authorId !in ids }
    }

    private fun load() {
        val raw = prefs.getString(storageKey, null) ?: return
        runCatching {
            _blocked.clear()
            _blocked.addAll(json.decodeFromString<List<BlockedAccount>>(raw))
        }
    }

    private fun persist() {
        prefs.edit().putString(storageKey, json.encodeToString(_blocked.toList())).apply()
    }

    companion object {
        @Volatile private var instance: BlockService? = null
        fun get(context: Context): BlockService =
            instance ?: synchronized(this) {
                instance ?: BlockService(context.applicationContext).also { instance = it }
            }
    }
}
