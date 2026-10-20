import Foundation

enum AppConfig {
    static let supabaseURL = "https://bpdkltgikgbnfjswdbaj.supabase.co"
    static let supabaseStorageURL = "https://bpdkltgikgbnfjswdbaj.storage.supabase.co"
    static let supabaseAnonKey = "sb_publishable_17VL78hCv9BVez2c4lIqFQ_MUv1iOHb"
    static let graphqlEndpoint = "https://api.matterya.com/graphql"
    static let apiBaseURL = "https://api.matterya.com"
    /// Legacy public R2 base — currently CF 1010/403 for matterya-sparks. Do not hand to
    /// AVPlayer/ImageCache. Signed cloudflarestorage.com GETs also 403 on HEAD; hubs play
    /// tolerates that via `R2PresignedPlayback` (matterya-r2:// Range GET proxy).
    static let r2PublicBaseURL = "https://pub-0af7dfb233b3438f90451ac0261b6009.r2.dev"
    static let demoDatasetBaseURL = "https://matterya.com"
    /// PERMANENTLY OFF — never load Reddit JSONL (bundled or remote). Backend GraphQL only.
    static let useDemoDataset = false
    static let demoDatasetAllowRemoteDownload = false
    static let demoDatasetMaxPosts = 0
    /// Internet Archive seed catalog (`hub_videos.jsonl`, ia_*, archive.org media).
    /// OFF for now — it slows Hubs/Sparks (CDN resolve + huge offline library).
    /// Code stays in `HubVideoSeedService` / `ArchiveVideoPlayback`; flip to `true` to restore.
    static let archiveContentEnabled = false
    /// Apple Translate / TranslationSession on captions & posts.
    /// OFF for now — removes Translate buttons + on-device translation work from Feed/Sparks/comments.
    /// `TranslatableCaption` stays as plain text; restore hooks from git when re-enabling.
    static let enableTranslate = false
    static let pexelsAPIKey = "gN9dMuDmlYiMu1AjIEHZcpoemMfHhfWhAmi71jrRssq5I5AIVIl6D3Ll"
    static let appName = "Matterya"
}
