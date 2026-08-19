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

    /// Reserved strip under the 16:9 film for timeline + transport (not cropped by fill).
    static let hubFeedTimelineChromePad: CGFloat = 72

    /// Hubs long-form feed card — 16:9 film (aspect-fill) + chrome pad for scrubber/buttons.
    /// Photos and Sparks must **not** use this.
    static func hubFeedVideoHeight(
        forWidth width: CGFloat = UIScreen.main.bounds.width
    ) -> CGFloat {
        let w = max(200, width.isFinite ? width : UIScreen.main.bounds.width)
        let film = w / feedVideoAspect
        let h = film + hubFeedTimelineChromePad
        return min(max(h, minFeedMediaHeight), maxFeedMediaHeight + hubFeedTimelineChromePad)
    }

    /// Pure 16:9 film height (video fill zone above the chrome pad).
    static func hubFeedFilmHeight(
        forWidth width: CGFloat = UIScreen.main.bounds.width
    ) -> CGFloat {
        let w = max(200, width.isFinite ? width : UIScreen.main.bounds.width)
        return min(max(w / feedVideoAspect, minFeedMediaHeight), maxFeedMediaHeight)
    }

    /// Clamp aspect ratios so a bad media metadata value can't blow out the card.
    static func clampedAspect(_ aspect: CGFloat) -> CGFloat {
        guard aspect.isFinite, aspect > 0.05 else { return photoPortraitAspect }
        // 9:16 … 2.4:1
        return min(max(aspect, 0.45), 2.4)
    }

    /// Spark share on feed — same Facebook tall media box as other video posts.
    static func sparkFeedCardHeight(
        forWidth width: CGFloat = UIScreen.main.bounds.width,
        screenHeight: CGFloat = UIScreen.main.bounds.height
    ) -> CGFloat {
        dominantFeedVideoHeight(forWidth: width, screenHeight: screenHeight)
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