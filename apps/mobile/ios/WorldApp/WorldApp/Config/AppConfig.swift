import Foundation

enum AppConfig {
    static let supabaseURL = "https://bpdkltgikgbnfjswdbaj.supabase.co"
    static let supabaseStorageURL = "https://bpdkltgikgbnfjswdbaj.storage.supabase.co"
    static let supabaseAnonKey = "sb_publishable_17VL78hCv9BVez2c4lIqFQ_MUv1iOHb"
    static let graphqlEndpoint = "https://api.matterya.com/graphql"
    static let apiBaseURL = "https://api.matterya.com"
    static let demoDatasetBaseURL = "https://matterya.com"
    /// Merge Reddit / bundled seed into feeds (TestFlight-style density).
    static let useDemoDataset = true
    /// Prefer local monorepo + app-bundled seed over remote download.
    static let demoDatasetAllowRemoteDownload = false
    /// Cap demo posts held for home-feed filler.
    static let demoDatasetMaxPosts = 4_000
    static let pexelsAPIKey = "gN9dMuDmlYiMu1AjIEHZcpoemMfHhfWhAmi71jrRssq5I5AIVIl6D3Ll"
    static let appName = "Matterya"
}
