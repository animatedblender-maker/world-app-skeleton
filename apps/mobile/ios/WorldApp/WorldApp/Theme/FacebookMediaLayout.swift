import SwiftUI
import UIKit

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
    /// Max height for in-feed photos — tall enough for 4:5 immersion on phones.
    static let maxFeedMediaHeight: CGFloat = 520

    /// In-feed video height: at least ~55% of screen so two videos rarely fit together.
    static func dominantFeedVideoHeight(
        forWidth width: CGFloat = UIScreen.main.bounds.width,
        screenHeight: CGFloat = UIScreen.main.bounds.height
    ) -> CGFloat {
        let classic = width / feedVideoAspect
        let minDominant = screenHeight * 0.55
        let maxDominant = screenHeight * 0.68
        return min(max(classic, minDominant), maxDominant)
    }

    static func mediaHeight(for width: CGFloat, post: CountryPost, context: MediaContext = .feed) -> CGFloat {
        if post.hasVideo, usesYouTubeFrame(for: post, context: context) || context == .feed {
            return dominantFeedVideoHeight(forWidth: width)
        }
        let aspect = aspectRatio(for: post, context: context) ?? photoPortraitAspect
        let natural = width / aspect
        return min(natural, maxFeedMediaHeight)
    }

    static func feedMediaHeight(for width: CGFloat, post: CountryPost, context: MediaContext = .feed) -> CGFloat {
        mediaHeight(for: width, post: post, context: context)
    }

    static func usesYouTubeFrame(for post: CountryPost, context: MediaContext = .feed) -> Bool {
        post.hasVideo && !post.isReel && !post.isStory && context != .reel
    }

    static func aspectRatio(for post: CountryPost, context: MediaContext = .feed) -> CGFloat? {
        if post.hasVideo {
            if usesYouTubeFrame(for: post, context: context) {
                return YouTubeMediaLayout.aspect
            }
            if post.isReel || context == .reel {
                return reelAspect
            }
            return feedVideoAspect
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