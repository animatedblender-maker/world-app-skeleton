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
    /// Hard floor/ceiling so LazyVStack never proposes infinite/zero media boxes.
    static let minFeedMediaHeight: CGFloat = 160

    /// Facebook mobile feed: full-width, tall media (~4:5 immersion, not flat 16:9).
    /// Pair with `fillsFrame: true` so the picture fills the box (no letterbox “tiny video”).
    /// Sparks + short-form use this; **not** Hubs long-form (see `hubFeedVideoHeight`).
    static func dominantFeedVideoHeight(
        forWidth width: CGFloat = UIScreen.main.bounds.width,
        screenHeight: CGFloat = UIScreen.main.bounds.height
    ) -> CGFloat {
        // Guard against zero/negative window sizes during first layout (splits, rotation).
        let w = max(200, width.isFinite ? width : UIScreen.main.bounds.width)
        let h = max(400, screenHeight.isFinite ? screenHeight : UIScreen.main.bounds.height)
        let classic16x9 = w / feedVideoAspect
        // FB mobile feed reads closer to ~4:5 than flat 16:9.
        let fbLike = w / photoPortraitAspect
        let minDominant = min(h * 0.42, maxFeedMediaHeight)
        let maxDominant = min(h * 0.62, maxFeedMediaHeight + 20)
        let preferred = max(classic16x9 * 1.15, min(fbLike, maxDominant))
        let raw = min(max(preferred, minDominant), maxDominant)
        return min(max(raw, minFeedMediaHeight), maxFeedMediaHeight + 20)
    }

    /// Hubs long-form feed card — true 16:9; film fills; chrome overlays (YT-style).
    /// Photos and Sparks must **not** use this.
    static func hubFeedVideoHeight(
        forWidth width: CGFloat = UIScreen.main.bounds.width
    ) -> CGFloat {
        let w = max(200, width.isFinite ? width : UIScreen.main.bounds.width)
        let h = w / feedVideoAspect
        return min(max(h, minFeedMediaHeight), maxFeedMediaHeight)
    }

    /// Video container = full-width 16:9 only. Timeline overlays the film; social sits under.
    static func hubFeedStageHeight(
        forWidth width: CGFloat = UIScreen.main.bounds.width
    ) -> CGFloat {
        hubFeedVideoHeight(forWidth: width)
    }

    /// Clamp aspect ratios so a bad media metadata value can't blow out the card.
    static func clampedAspect(_ aspect: CGFloat) -> CGFloat {
        guard aspect.isFinite, aspect > 0.05 else { return photoPortraitAspect }
        // 9:16 … 2.4:1
        return min(max(aspect, 0.45), 2.4)
    }

    /// Spark on feed — near **9:16** immersion (not flat 4:5). Filling a short 4:5 box
    /// crops vertical Sparks hard; full Sparks player uses the whole screen.
    static func sparkFeedCardHeight(
        forWidth width: CGFloat = UIScreen.main.bounds.width,
        screenHeight: CGFloat = UIScreen.main.bounds.height
    ) -> CGFloat {
        let w = max(200, width.isFinite ? width : UIScreen.main.bounds.width)
        let h = max(400, screenHeight.isFinite ? screenHeight : UIScreen.main.bounds.height)
        let reelH = w / reelAspect
        // Tall like IG Reels-in-feed; cap so the card doesn't eat the whole scroll view.
        let maxH = min(h * 0.70, 680)
        let minH = min(h * 0.52, 520)
        return min(max(min(reelH, maxH), minH), maxH)
    }

    static func mediaHeight(for width: CGFloat, post: CountryPost, context: MediaContext = .feed) -> CGFloat {
        if post.hasVideo {
            let isSpark = post.isReel
                || post.isSpark
                || post.isSparkFeedShare
                || context == .reel
            if isSpark {
                return sparkFeedCardHeight(forWidth: width)
            }
            // Hubs long-form: compact 16:9 so aspect-fit has no black gaps.
            if PlayPlatformBridge.isHubFeedCardVideo(post)
                || PlayPlatformBridge.showsPlayLinkInFeed(post, context: context) {
                return hubFeedVideoHeight(forWidth: width)
            }
            if usesYouTubeFrame(for: post, context: context) || context == .feed {
                return dominantFeedVideoHeight(forWidth: width)
            }
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