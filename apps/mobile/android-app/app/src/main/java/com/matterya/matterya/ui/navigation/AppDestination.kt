package com.matterya.matterya.ui.navigation

/**
 * Nav host route strings for Compose Navigation.
 * Distinct from model [com.matterya.matterya.model.AppDestination] (typed destinations).
 */
object NavRoutes {
    const val tabs = "tabs"
    const val search = "search"
    const val people = "people"
    const val settings = "settings"
    const val editProfile = "edit_profile"
    const val blockedAccounts = "blocked_accounts"
    const val ads = "ads"
    const val masquerade = "masquerade"
    const val letters = "letters"
    const val composeLetter = "compose_letter"
    const val connected = "connected"
    const val composePost = "compose_post"
    const val composeSpark = "compose_spark"
    const val composeHubVideo = "compose_hub_video"
    const val composeStory = "compose_story"
    const val post = "post/{postId}"
    const val profile = "profile/{username}"
    const val profileId = "profile_id/{userId}"
    const val chat = "chat/{conversationId}"
    const val country = "country/{iso}"
    const val reels = "reels/{iso}"
    const val news = "news/{newsId}"
    const val hubsWatch = "hubs_watch/{postId}"

    fun post(id: String) = "post/$id"
    fun profile(username: String) = "profile/$username"
    fun profileId(userId: String) = "profile_id/$userId"
    fun chat(id: String) = "chat/$id"
    fun country(iso: String) = "country/$iso"
    fun reels(iso: String) = "reels/$iso"
    fun news(id: String) = "news/$id"
    fun hubsWatch(id: String) = "hubs_watch/$id"
}
