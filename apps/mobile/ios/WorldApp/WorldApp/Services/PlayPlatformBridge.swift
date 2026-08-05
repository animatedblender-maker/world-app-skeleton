import Foundation

/// Routes content between Matterya Feed/Messages/Profile and Matterya Hubs.
enum PlayPlatformBridge {
    /// True only for content that belongs on Matterya Hubs:
    /// - Archive / seed hub catalog
    /// - User uploads published via Hubs (+ channel marker)
    /// - Synthetic hub_* / hub_spark_* authors
    ///
    /// Plain feed videos (no channel, no hub marker) are **not** hub content —
    /// they stay feed posts with the same player and no Hubs badge.
    static func isHubCatalogContent(_ post: CountryPost) -> Bool {
        if post.isStory { return false }
        if post.isHubSeedVideo { return true }
        if HubChannelPostMarker.isMarked(post.body) { return true }
        let author = post.authorID.lowercased()
        if author.hasPrefix("hub_") || author.hasPrefix("hub_spark_") { return true }
        let id = post.id.lowercased()
        if id.hasPrefix("ia_") || id.hasPrefix("hub_") || id.hasPrefix("hub_spark_") { return true }
        return false
    }

    static func isPlayEligible(_ post: CountryPost) -> Bool {
        post.hasVideo && !post.isStory
    }

    static func isLongFormVideo(_ post: CountryPost) -> Bool {
        isPlayEligible(post) && !post.isReel
    }

    /// Hub catalog long-form only — opens Hubs watch / shows Hubs badge in feed.
    static func isHubFeedCardVideo(_ post: CountryPost) -> Bool {
        isHubCatalogContent(post) && post.hasVideo && !post.isReel && !post.isStory
    }

    static func isReelVideo(_ post: CountryPost) -> Bool {
        isPlayEligible(post) && post.isReel
    }

    static func preferredPlayTab(for post: CountryPost) -> YouTubeMainTab {
        .home
    }

    static func shareURL(for post: CountryPost) -> URL {
        if isHubCatalogContent(post), post.hasVideo {
            return URL(string: "https://matterya.com/play/watch/\(post.sharedPostID ?? post.id)")!
        }
        return URL(string: "https://matterya.com/post/\(post.sharedPostID ?? post.id)")!
    }

    /// Only true hub long-form gets the feed Hubs card + badge.
    /// Plain feed videos use the normal inline player (same controls, no badge).
    static func showsPlayLinkInFeed(_ post: CountryPost, context: MediaContext = .feed) -> Bool {
        isHubFeedCardVideo(post) && context == .feed
    }

    static func channelURL(authorID: String, username: String?) -> URL {
        if let username, !username.isEmpty {
            return URL(string: "https://matterya.com/play/channel/\(username)")!
        }
        return URL(string: "https://matterya.com/play/channel/id/\(authorID)")!
    }
}