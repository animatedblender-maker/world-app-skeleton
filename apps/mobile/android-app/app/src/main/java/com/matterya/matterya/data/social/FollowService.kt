package com.matterya.matterya.data.social

import android.content.Context
import com.matterya.matterya.data.graphql.GqlOps
import com.matterya.matterya.data.graphql.GraphQlClient
import com.matterya.matterya.model.FollowCounts
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID

/**
 * Follow GraphQL — mirrors iOS `FollowService.swift`.
 * Synthetic non-UUID authors stay on-device only (cannot FK into user_follows).
 */
class FollowService(
    private val gql: GraphQlClient = GraphQlClient(),
    private val prefsContext: Context? = null,
) {
    private val prefs by lazy {
        prefsContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    private var memoryLocal: MutableSet<String> = mutableSetOf()

    private var localFollowingIds: Set<String>
        get() {
            val stored = prefs?.getStringSet(KEY_LOCAL, null)
            return if (stored != null) stored.toSet() else memoryLocal.toSet()
        }
        set(value) {
            memoryLocal = value.toMutableSet()
            prefs?.edit()?.putStringSet(KEY_LOCAL, value)?.apply()
        }

    /**
     * True only for synthetic demo/seed ids that **cannot** be stored in Supabase
     * `user_follows` (FK to auth.users). Real channel owners are UUIDs → always server.
     */
    fun usesLocalFollow(userId: String): Boolean {
        val id = userId.trim()
        if (id.isEmpty()) return true
        if (runCatching { UUID.fromString(id) }.isSuccess) return false
        val lower = id.lowercase()
        if (lower.startsWith("user_") ||
            lower.startsWith("hub_") ||
            lower.startsWith("hub_spark_") ||
            lower.startsWith("demo_") ||
            lower.startsWith("ia_") ||
            lower.startsWith("archive_") ||
            lower.startsWith("spark_")
        ) {
            return true
        }
        return true
    }

    suspend fun counts(userId: String): FollowCounts {
        val id = userId.trim()
        if (usesLocalFollow(id)) {
            val followers = if (localFollowingIds.contains(id)) 1 else 0
            return FollowCounts(followers = followers, following = 0)
        }
        return try {
            val data = gql.request(
                GqlOps.followCounts(),
                mapOf("userId" to JsonPrimitive(id)),
            )
            val row = data["followCounts"]?.jsonObject
            FollowCounts(
                followers = row?.get("followers")?.jsonPrimitive?.intOrNull ?: 0,
                following = row?.get("following")?.jsonPrimitive?.intOrNull ?: 0,
            )
        } catch (_: Exception) {
            FollowCounts(0, 0)
        }
    }

    suspend fun isFollowing(targetId: String): Boolean {
        val id = targetId.trim()
        if (usesLocalFollow(id)) return localFollowingIds.contains(id)
        return try {
            val data = gql.request(
                GqlOps.isFollowing(),
                mapOf("target" to JsonPrimitive(id)),
            )
            data["isFollowing"]?.jsonPrimitive?.booleanOrNull == true ||
                data["isFollowing"]?.jsonPrimitive?.contentOrNull == "true"
        } catch (_: Exception) {
            false
        }
    }

    /** Server following set is source of truth for real users; synthetic ids stay local. */
    suspend fun followingIds(): Set<String> {
        val local = localFollowingIds
        return try {
            val data = gql.request(GqlOps.followingIds())
            val remote = data["followingIds"]?.jsonArray
                ?.mapNotNull { it.jsonPrimitive.contentOrNull }
                ?.toSet()
                ?: emptySet()
            remote + local
        } catch (_: Exception) {
            local
        }
    }

    suspend fun follow(targetId: String) {
        val id = targetId.trim()
        if (id.isEmpty()) return
        if (usesLocalFollow(id)) {
            localFollowingIds = localFollowingIds + id
            return
        }
        gql.request(
            GqlOps.followUser(),
            mapOf("target" to JsonPrimitive(id)),
        )
    }

    suspend fun unfollow(targetId: String) {
        val id = targetId.trim()
        if (id.isEmpty()) return
        if (usesLocalFollow(id)) {
            localFollowingIds = localFollowingIds - id
            return
        }
        gql.request(
            GqlOps.unfollowUser(),
            mapOf("target" to JsonPrimitive(id)),
        )
    }

    companion object {
        private const val PREFS = "matterya_follow"
        private const val KEY_LOCAL = "matterya.local_following_ids.v1"
    }
}
