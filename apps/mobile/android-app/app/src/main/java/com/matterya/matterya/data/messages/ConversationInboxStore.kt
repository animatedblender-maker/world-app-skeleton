package com.matterya.matterya.data.messages

import android.content.Context
import com.matterya.matterya.data.auth.AuthService

/**
 * iOS `ConversationInboxStore` (MessagesView.swift) — local hide list for archived/deleted chats.
 *
 * Server archive/delete can fail offline; we still hide rows via SharedPreferences so the
 * inbox matches iOS UserDefaults behavior until the next successful server clear.
 */
object ConversationInboxStore {
    private const val PREFS = "matterya_conversation_inbox"
    private const val KEY_ARCHIVED = "archived"
    private const val KEY_DELETED = "deleted"

    @Volatile
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    private fun prefs(): android.content.SharedPreferences? {
        val ctx = appContext ?: return null
        return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    private fun storagePrefix(): String {
        val userId = AuthService.instance.currentUser?.id ?: "anonymous"
        return "conversation.inbox.$userId"
    }

    fun isHidden(conversationId: String): Boolean {
        val id = conversationId.trim()
        if (id.isEmpty()) return false
        return archivedIds().contains(id) || deletedIds().contains(id)
    }

    fun markArchived(conversationId: String) {
        val id = conversationId.trim()
        if (id.isEmpty()) return
        val archived = archivedIds().toMutableSet().apply { add(id) }
        val deleted = deletedIds().toMutableSet().apply { remove(id) }
        persist(archived, deleted)
    }

    fun markDeleted(conversationId: String) {
        val id = conversationId.trim()
        if (id.isEmpty()) return
        val archived = archivedIds().toMutableSet().apply { remove(id) }
        val deleted = deletedIds().toMutableSet().apply { add(id) }
        persist(archived, deleted)
    }

    fun clear(conversationId: String) {
        val id = conversationId.trim()
        if (id.isEmpty()) return
        val archived = archivedIds().toMutableSet().apply { remove(id) }
        val deleted = deletedIds().toMutableSet().apply { remove(id) }
        persist(archived, deleted)
    }

    private fun archivedIds(): Set<String> =
        prefs()?.getStringSet("${storagePrefix()}.$KEY_ARCHIVED", emptySet())?.toSet()
            ?: emptySet()

    private fun deletedIds(): Set<String> =
        prefs()?.getStringSet("${storagePrefix()}.$KEY_DELETED", emptySet())?.toSet()
            ?: emptySet()

    private fun persist(archived: Set<String>, deleted: Set<String>) {
        // Always copy — SharedPreferences StringSet must not reuse the getStringSet instance.
        prefs()?.edit()
            ?.putStringSet("${storagePrefix()}.$KEY_ARCHIVED", HashSet(archived))
            ?.putStringSet("${storagePrefix()}.$KEY_DELETED", HashSet(deleted))
            ?.apply()
    }
}
