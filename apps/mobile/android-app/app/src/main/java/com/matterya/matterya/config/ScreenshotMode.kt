package com.matterya.matterya.config

import com.matterya.matterya.model.AppDestination
import com.matterya.matterya.model.AppTab
import com.matterya.matterya.model.AuthUser
import com.matterya.matterya.model.Conversation
import com.matterya.matterya.model.Message
import com.matterya.matterya.model.PostAuthor
import com.matterya.matterya.model.Profile
import java.time.Instant

/**
 * Demo / App Store screenshot helper — 1:1 from iOS `ScreenshotMode.swift`.
 * Keep [isActive] == false for normal app use.
 */
object ScreenshotMode {
    /** Flip to true only when capturing marketing screenshots. */
    const val isActive = false

    val tab: AppTab? get() = null
    val route: AppDestination? get() = null
    val searchQuery: String? get() = null

    val demoProfile = Profile(
        userId = "screenshot_demo_user",
        email = "demo@matterya.app",
        displayName = "Alex Rivera",
        username = "alexrivera",
        avatarUrl = "https://api.dicebear.com/7.x/identicon/svg?seed=alexrivera",
        countryName = "Spain",
        countryCode = "ES",
        cityName = "Barcelona",
        bio = "Exploring the world with Matterya.",
        followersCount = 1284,
        followingCount = 312,
        accountStatus = "active",
        createdAt = Instant.now().toString(),
        updatedAt = Instant.now().toString(),
    )

    val demoConversations: List<Conversation>
        get() {
            val peer = PostAuthor(
                userId = "screenshot_peer",
                displayName = "Sam Chen",
                username = "samchen",
                avatarUrl = "https://api.dicebear.com/7.x/identicon/svg?seed=samchen",
                countryName = "Japan",
                countryCode = "JP",
            )
            val me = PostAuthor(
                userId = demoProfile.userId,
                displayName = demoProfile.displayName,
                username = demoProfile.username,
                avatarUrl = demoProfile.avatarUrl,
                countryName = demoProfile.countryName,
                countryCode = demoProfile.countryCode,
            )
            val now = Instant.now().toString()
            val last = Message(
                id = "screenshot_msg_1",
                conversationId = "screenshot_convo_1",
                senderId = peer.userId,
                body = "See you on the globe later!",
                createdAt = now,
                updatedAt = now,
                sender = peer,
            )
            return listOf(
                Conversation(
                    id = "screenshot_convo_1",
                    isDirect = true,
                    createdAt = now,
                    updatedAt = now,
                    lastMessageAt = now,
                    members = listOf(me, peer),
                    lastMessage = last,
                ),
            )
        }
}
