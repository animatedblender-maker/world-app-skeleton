package com.matterya.matterya.config

/** Mirrors iOS `AppConfig.swift` — same endpoints / flags. */
object AppConfig {
    const val appName = "Matterya"
    const val supabaseURL = "https://bpdkltgikgbnfjswdbaj.supabase.co"
    const val supabaseStorageURL = "https://bpdkltgikgbnfjswdbaj.storage.supabase.co"
    const val supabaseAnonKey = "sb_publishable_17VL78hCv9BVez2c4lIqFQ_MUv1iOHb"
    const val graphqlEndpoint = "https://api.matterya.com/graphql"
    const val apiBaseURL = "https://api.matterya.com"
    const val demoDatasetBaseURL = "https://matterya.com"
    const val useDemoDataset = false
    /** When false (default), DemoDatasetService returns empty — matches iOS. */
    const val demoDatasetAllowRemoteDownload = false
    const val demoDatasetMaxPosts = 0
    const val archiveContentEnabled = false
}
