import Foundation

/// Routes content between Matterya Feed/Messages/Profile and Matterya Hubs.
enum PlayPlatformBridge {
    /// True for content that opens on Matterya Hubs / shows Hubs chrome:
    /// - The Archive catalog (R2 / seed hub videos + Sparks)
    /// - User uploads **published to** Hubs (channel marker)
    /// - Feed **shares of** Hubs videos (origin marker — does NOT create a channel)
    /// - Synthetic hub_* authors (including `hub_archive`)
    ///
    /// Plain feed videos (no channel, no hub marker) stay feed-only.
    static func isHubCatalogContent(_ post: CountryPost) -> Bool {
        if post.isStory { return false }
        if post.isHubSeedVideo { return true }
        if HubChannelPostMarker.isMarked(post.body) { return true }
        if HubOriginShareMarker.isMarked(post.body) { return true }
        if HubVideoSeedService.isArchiveChannelAuthor(post.authorID) { return true }
        let id = post.id.lowercased()
        if id.hasPrefix("ia_") || id.hasPrefix("hub_") || id.hasPrefix("hub_spark_") { return true }
        return false
    }

    /// Intentional Hubs **channel upload** only (creator/admin published to Hubs).
    /// Feed shares, re-posts, and origin stamps never count as “my channel” videos.
    static func isHubChannelUpload(_ post: CountryPost) -> Bool {
        guard post.hasVideo, !post.isStory else { return false }
        // Sharing someone else’s clip is never an upload to the sharer’s channel.
        if isHubOriginShare(post) { return false }
        if post.sharedPostID != nil { return false }
        // Requires explicit channel publish marker (createLivingVideo / hub spark publish).
        return HubChannelPostMarker.isMarked(post.body)
    }

    /// Feed share of a Hubs clip (badge + open Hubs) without granting the sharer a channel.
    static func isHubOriginShare(_ post: CountryPost) -> Bool {
        HubOriginShareMarker.isMarked(post.body)
    }

    /// Content that may appear in the Hubs catalog shelves — not necessarily “owned” by author.
    /// Excludes feed shares so they never invent a channel for the sharer.
    static func isHubCatalogOwnedContent(_ post: CountryPost) -> Bool {
        guard post.hasVideo, !post.isStory else { return false }
        if isHubOriginShare(post) { return false }
        if post.sharedPostID != nil, !isHubChannelUpload(post) { return false }
        if post.isHubSeedVideo || HubVideoSeedService.isArchiveChannelAuthor(post.authorID) {
            return true
        }
        return isHubChannelUpload(post)
    }

    /// Post model used for Hubs watch UI (original channel, not the sharer).
    /// Sync path — prefer async `resolveHubWatchPresentation` when possible.
    static func hubWatchPresentation(for post: CountryPost) -> CountryPost {
        if let origin = HubOriginShareMarker.originPresentation(from: post),
           origin.authorID != post.authorID || origin.authorID.hasPrefix("hub_") {
            return origin
        }
        return post
    }

    /// Resolve the **catalog / original** channel for a feed share or re-publish.
    /// Archive hub clips always map back to the hub persona — never the person who shared.
    @MainActor
    static func resolveHubWatchPresentation(for post: CountryPost) async -> CountryPost {
        // 1) Match media URL to hub seed catalog (strongest signal for IA videos).
        let media = post.mediaURL ?? post.playableVideoURL?.absoluteString
        if let hub = await HubVideoSeedService.shared.postMatchingMediaURL(media) {
            return overlayShareMedia(from: post, onto: hub)
        }

        // 2) Origin stamp `sid` → hub catalog id.
        if let fields = HubOriginShareMarker.parseFields(from: post.body),
           let sid = fields["sid"], !sid.isEmpty {
            if let hub = await HubVideoSeedService.shared.post(id: sid) {
                return overlayShareMedia(from: post, onto: hub)
            }
            // Server original (may still be a bad re-publish) — only trust if different author
            // or hub persona.
            if let remote = try? await PostsService.shared.getPostByID(sid) {
                if remote.authorID.hasPrefix("hub_") || remote.isHubSeedVideo {
                    return overlayShareMedia(from: post, onto: remote)
                }
                if let hub2 = await HubVideoSeedService.shared.postMatchingMediaURL(
                    remote.mediaURL ?? remote.playableVideoURL?.absoluteString
                ) {
                    return overlayShareMedia(from: post, onto: hub2)
                }
            }
        }

        // 3) Direct catalog id / seed.
        if let hub = await HubVideoSeedService.shared.post(id: post.id) {
            return hub
        }
        if post.isHubSeedVideo {
            return post
        }

        // 4) Origin stamp with non-sharer author.
        if let origin = HubOriginShareMarker.originPresentation(from: post),
           origin.authorID != post.authorID {
            return origin
        }

        return post
    }

    /// Keep playable media from the feed share row; identity from catalog/origin.
    private static func overlayShareMedia(from share: CountryPost, onto origin: CountryPost) -> CountryPost {
        CountryPost(
            id: origin.id,
            title: origin.title ?? share.title,
            body: origin.body,
            mediaType: share.mediaType ?? origin.mediaType,
            mediaURL: share.mediaURL ?? origin.mediaURL,
            thumbURL: share.thumbURL ?? origin.thumbURL,
            mediaCaption: origin.mediaCaption ?? share.mediaCaption,
            sharedPostID: share.sharedPostID,
            sharedPost: share.sharedPost,
            visibility: share.visibility,
            likeCount: origin.likeCount,
            commentCount: origin.commentCount,
            viewCount: origin.viewCount,
            likedByMe: origin.likedByMe,
            savedByMe: origin.savedByMe,
            createdAt: origin.createdAt.isEmpty ? share.createdAt : origin.createdAt,
            updatedAt: origin.updatedAt.isEmpty ? share.updatedAt : origin.updatedAt,
            authorID: origin.authorID,
            countryName: origin.countryName ?? share.countryName,
            countryCode: origin.countryCode ?? share.countryCode,
            cityName: origin.cityName ?? share.cityName,
            author: origin.author,
            externalRefType: origin.externalRefType ?? "hub",
            externalRefID: origin.externalRefID ?? origin.hubSlug
        )
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