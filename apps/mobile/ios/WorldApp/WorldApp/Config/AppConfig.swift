import Foundation

enum AppConfig {
    static let supabaseURL = "https://bpdkltgikgbnfjswdbaj.supabase.co"
    static let supabaseStorageURL = "https://bpdkltgikgbnfjswdbaj.storage.supabase.co"
    static let supabaseAnonKey = "sb_publishable_17VL78hCv9BVez2c4lIqFQ_MUv1iOHb"
    static let graphqlEndpoint = "https://api.matterya.com/graphql"
    static let apiBaseURL = "https://api.matterya.com"
    static let demoDatasetBaseURL = "https://matterya.com"
    /// PERMANENTLY OFF — never load Reddit JSONL (bundled or remote). Backend GraphQL only.
    static let useDemoDataset = false
    static let demoDatasetAllowRemoteDownload = false
    static let demoDatasetMaxPosts = 0
    /// Internet Archive seed catalog (`hub_videos.jsonl`, ia_*, archive.org media).
    /// OFF for now — it slows Hubs/Sparks (CDN resolve + huge offline library).
    /// Code stays in `HubVideoSeedService` / `ArchiveVideoPlayback`; flip to `true` to restore.
    static let archiveContentEnabled = false
    static let pexelsAPIKey = "gN9dMuDmlYiMu1AjIEHZcpoemMfHhfWhAmi71jrRssq5I5AIVIl6D3Ll"
    static let appName = "Matterya"
}
