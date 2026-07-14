import Foundation

/// Routes content between Matterya Feed/Messages/Profile and Matterya Hubs.
enum PlayPlatformBridge {
    static func isPlayEligible(_ post: CountryPost) -> Bool {
        post.hasVideo && !post.isStory
    }

    static func isLongFormVideo(_ post: CountryPost) -> Bool {
        isPlayEligible(post) && !post.isReel
    }

    static func isReelVideo(_ post: CountryPost) -> Bool {
        isPlayEligible(post) && post.isReel
    }

    static func preferredPlayTab(for post: CountryPost) -> YouTubeMainTab {
        .home
    }

    static func shareURL(for post: CountryPost) -> URL {
        if isPlayEligible(post) {
            return URL(string: "https://matterya.com/play/watch/\(post.sharedPostID ?? post.id)")!
        }
        return URL(string: "https://matterya.com/post/\(post.sharedPostID ?? post.id)")!
    }

    /// Long-form videos appear in Feed as Play link cards, not inline players.
    static func showsPlayLinkInFeed(_ post: CountryPost, context: MediaContext = .feed) -> Bool {
        isLongFormVideo(post) && context == .feed
    }

    static func channelURL(authorID: String, username: String?) -> URL {
        if let username, !username.isEmpty {
            return URL(string: "https://matterya.com/play/channel/\(username)")!
        }
        return URL(string: "https://matterya.com/play/channel/id/\(authorID)")!
    }
}