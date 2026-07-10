import SwiftUI

enum FacebookMediaLayout {
    /// Facebook feed portrait photo (4:5).
    static let photoPortraitAspect: CGFloat = 4.0 / 5.0
    /// Facebook feed square photo (1:1).
    static let photoSquareAspect: CGFloat = 1.0
    /// Facebook feed landscape photo (1.91:1).
    static let photoLandscapeAspect: CGFloat = 1.91
    /// Facebook in-feed horizontal video (16:9).
    static let feedVideoAspect: CGFloat = 16.0 / 9.0
    /// Facebook Reels / Stories vertical video (9:16).
    static let reelAspect: CGFloat = 9.0 / 16.0
    /// Max height for in-feed photos and videos (Facebook-style cap).
    static let maxFeedMediaHeight: CGFloat = 420

    static func mediaHeight(for width: CGFloat, post: CountryPost, context: MediaContext = .feed) -> CGFloat {
        let aspect = aspectRatio(for: post, context: context) ?? photoPortraitAspect
        return min(width / aspect, maxFeedMediaHeight)
    }

    static func feedMediaHeight(for width: CGFloat, post: CountryPost, context: MediaContext = .feed) -> CGFloat {
        mediaHeight(for: width, post: post, context: context)
    }

    static func aspectRatio(for post: CountryPost, context: MediaContext = .feed) -> CGFloat? {
        if post.hasVideo {
            return context == .reel ? reelAspect : feedVideoAspect
        }
        if post.hasMedia {
            return photoPortraitAspect
        }
        return nil
    }
}

enum MediaContext {
    case feed
    case reel
}