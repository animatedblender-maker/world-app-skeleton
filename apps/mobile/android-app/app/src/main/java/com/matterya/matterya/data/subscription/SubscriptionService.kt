package com.matterya.matterya.data.subscription

/**
 * Matterya is free — subscription plumbing is disabled for now.
 * Mirrors iOS `SubscriptionService.swift`.
 */
class SubscriptionService private constructor() {
    val isPremium: Boolean get() = true

    suspend fun loadProducts() {}

    suspend fun refreshEntitlements() {}

    suspend fun restorePurchases(): String? = null

    companion object {
        val shared by lazy { SubscriptionService() }
    }
}
