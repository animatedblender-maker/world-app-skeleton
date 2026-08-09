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
        // User-authored row that still carries Archive/catalog media (legacy re-share).
        if isArchiveCatalogMedia(post) { return true }
        let id = post.id.lowercased()
        if id.hasPrefix("ia_") || id.hasPrefix("hub_") || id.hasPrefix("hub_spark_") { return true }
        return false
    }

    /// Internet Archive / seed-catalog media — always The Archive, never a personal upload.
    static func isArchiveCatalogMedia(_ post: CountryPost) -> Bool {
        if post.isHubSeedVideo { return true }
        if let url = post.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) {
            return true
        }
        let media = (post.mediaURL ?? "").lowercased()
        if media.contains("archive.org") { return true }
        let thumb = (post.thumbURL ?? "").lowercased()
        if thumb.contains("archive.org") { return true }
        // Catalog ids stamped onto media payloads / external refs.
        let id = post.id.lowercased()
        if id.hasPrefix("ia_") || id.hasPrefix("hub_spark_") { return true }
        if let ext = post.externalRefID?.lowercased(),
           ext.hasPrefix("ia_") || ext.hasPrefix("hub_") {
            return true
        }
        return false
    }

    /// Feed re-share of Hubs/Archive content (not an intentional channel publish).
    /// Covers origin stamps **and** legacy shares that only copied Archive media.
    static func isHubFeedReshare(_ post: CountryPost) -> Bool {
        isFeedOnlyShare(post)
    }

    /// Anything that belongs **only** on the home feed as a share card — never Hubs
    /// “For you”, channels, Sparks-for-you, library uploads, etc.
    /// Sharer identity is irrelevant on Hubs/Sparks surfaces.
    static func isFeedOnlyShare(_ post: CountryPost) -> Bool {
        if post.isStory { return false }
        // Explicit share stamps.
        if isHubOriginShare(post) { return true }
        if SparkShareMarker.isMarked(post.body) { return true }
        if post.isSparkFeedShare { return true }
        // Pointer re-post (not an intentional channel publish).
        if let shared = post.sharedPostID, !shared.isEmpty,
           !HubChannelPostMarker.isMarked(post.body) {
            return true
        }
        // Real person as author + Archive/catalog media = re-share of The Archive.
        if isArchiveCatalogMedia(post),
           !HubVideoSeedService.isArchiveChannelAuthor(post.authorID),
           !post.isHubSeedVideo {
            return true
        }
        // Live user row with video but no channel-publish marker is never a Hubs catalog item
        // (includes old shares that only copied media without stamps).
        if isLikelyLiveUserAuthor(post.authorID),
           post.hasVideo,
           !HubChannelPostMarker.isMarked(post.body),
           !post.isHubSeedVideo,
           !HubVideoSeedService.isArchiveChannelAuthor(post.authorID) {
            return true
        }
        return false
    }

    /// True UUID / live account authors (not hub_* / archive personas).
    static func isLikelyLiveUserAuthor(_ authorID: String) -> Bool {
        let id = authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        if HubVideoSeedService.isArchiveChannelAuthor(id) { return false }
        if id.hasPrefix("hub_") || id.hasPrefix("user_") || id.hasPrefix("demo_") { return false }
        return UUID(uuidString: id) != nil
    }

    /// Intentional Hubs **channel upload** only (creator/admin published to Hubs).
    /// Feed shares, re-posts, Archive media, and origin stamps never count as “my channel” videos.
    static func isHubChannelUpload(_ post: CountryPost) -> Bool {
        guard post.hasVideo, !post.isStory else { return false }
        // Sharing someone else’s clip is never an upload to the sharer’s channel.
        if isFeedOnlyShare(post) { return false }
        if post.sharedPostID != nil { return false }
        // Archive media can never become a personal channel video — even if an older
        // client/server wrongly stamped `__hub_channel__|` on a feed share.
        if isArchiveCatalogMedia(post) { return false }
        // Requires explicit channel publish marker (createLivingVideo / hub spark publish).
        return HubChannelPostMarker.isMarked(post.body)
    }

    /// Feed share of a Hubs clip (badge + open Hubs) without granting the sharer a channel.
    static func isHubOriginShare(_ post: CountryPost) -> Bool {
        HubOriginShareMarker.isMarked(post.body)
    }

    /// Single gate for **every** Hubs surface (For you, shelves, channels, library, sparks rail in Hubs).
    /// Feed-only shares never pass. Intentional channel publishes + optional Archive seeds.
    static func belongsInHubsCatalog(_ post: CountryPost) -> Bool {
        guard !post.isStory else { return false }
        let archiveOn = AppConfig.archiveContentEnabled
        // Archive / seed catalog — only when AppConfig.archiveContentEnabled.
        if post.isHubSeedVideo {
            guard archiveOn else { return false }
            return post.hasVideo || post.playableVideoURL != nil
        }
        if HubVideoSeedService.isArchiveChannelAuthor(post.authorID) {
            guard archiveOn else { return false }
            return post.hasVideo || post.playableVideoURL != nil
        }
        let id = post.id.lowercased()
        if (id.hasPrefix("ia_") || id.hasPrefix("hub_spark_"))
            && !isLikelyLiveUserAuthor(post.authorID) {
            guard archiveOn else { return false }
            return post.hasVideo || post.playableVideoURL != nil
        }
        // Live rows that only re-host archive.org media stay out while Archive is off.
        if !archiveOn, isArchiveCatalogMedia(post) { return false }
        guard post.hasVideo else { return false }
        // Hub origin shares open in Hubs but must not invent a personal channel for the sharer.
        // They still belong in For you / related rails as catalog content.
        if isHubOriginShare(post) { return true }
        if isFeedOnlyShare(post) { return false }
        // R2 longform + sparks stamped as channel publishes (country Hubs channels).
        if isHubChannelUpload(post) { return true }
        // Explicit LongForm R2 path even if marker was stripped.
        if let media = (post.mediaURL ?? post.playableVideoURL?.absoluteString)?.lowercased() {
            if media.contains("longform/") || media.contains("/longform") {
                return !post.isReel
            }
            // Other matterya-sparks media: longform videos only (not sparks path).
            if media.contains("matterya-sparks"), !post.isReel,
               !media.contains("/spark"), !media.contains("/sparks/") {
                return true
            }
        }
        return false
    }

    /// Content that may appear in the Hubs catalog shelves — not necessarily “owned” by author.
    /// Excludes feed shares so they never invent a channel for the sharer.
    static func isHubCatalogOwnedContent(_ post: CountryPost) -> Bool {
        belongsInHubsCatalog(post)
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

    /// Creator identity for list/cards: **channel**, never the person who re-shared/saved.
    /// Fixes “channel name + my profile picture” on Saved Videos.
    static func displayCreator(for post: CountryPost) -> (
        name: String,
        avatarURL: String?,
        seed: String,
        authorID: String,
        username: String?
    ) {
        // 1) Explicit hub-origin stamp (feed share of a Hubs video).
        if let origin = HubOriginShareMarker.originPresentation(from: post) {
            let name = origin.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let avatar = origin.author?.avatarURL
                ?? post.sharedPost?.asCountryPost.author?.avatarURL
            // Never fall back to the sharer's face when we know a different channel id.
            return (
                name.isEmpty ? HubVideoSeedService.archiveChannelDisplayName : name,
                avatar,
                origin.authorID,
                origin.authorID,
                origin.author?.username
            )
        }

        // 2) Archive / seed catalog — always The Archive channel.
        if isArchiveCatalogMedia(post) || HubVideoSeedService.isArchiveChannelAuthor(post.authorID) {
            return (
                HubVideoSeedService.archiveChannelDisplayName,
                nil,
                HubVideoSeedService.archiveChannelAuthorID,
                HubVideoSeedService.archiveChannelAuthorID,
                HubVideoSeedService.archiveChannelUsername
            )
        }

        // 3) Shared embed is the real channel / creator (pointer share).
        if let embed = post.sharedPost?.asCountryPost,
           !embed.authorID.isEmpty,
           embed.authorID != post.authorID,
           (embed.isHubSeedVideo || isHubCatalogContent(embed) || embed.authorID.hasPrefix("hub_")) {
            return (
                embed.authorDisplayName,
                embed.author?.avatarURL,
                embed.authorID,
                embed.authorID,
                embed.author?.username
            )
        }

        // 4) Native channel / creator row.
        return (
            post.authorDisplayName,
            post.author?.avatarURL,
            post.authorID,
            post.authorID,
            post.author?.username
        )
    }

    /// Rewrite author fields to the Hubs channel for local Saved / library display.
    /// Keeps the same post `id` so bookmarks still match the server row.
    static func withChannelIdentity(_ post: CountryPost, from channel: CountryPost) -> CountryPost {
        guard !channel.authorID.isEmpty else { return post }
        let author = channel.author ?? PostAuthor(
            userID: channel.authorID,
            displayName: channel.authorDisplayName,
            username: channel.author?.username,
            avatarURL: channel.author?.avatarURL,
            countryName: channel.countryName,
            countryCode: channel.countryCode,
            lastReadAt: nil
        )
        return CountryPost(
            id: post.id,
            title: post.title ?? channel.title,
            body: post.body,
            mediaType: post.mediaType ?? channel.mediaType,
            mediaURL: post.mediaURL ?? channel.mediaURL,
            thumbURL: post.thumbURL ?? channel.thumbURL,
            mediaCaption: post.mediaCaption ?? channel.mediaCaption,
            sharedPostID: post.sharedPostID,
            sharedPost: post.sharedPost,
            visibility: post.visibility,
            likeCount: post.likeCount,
            commentCount: post.commentCount,
            viewCount: post.viewCount,
            likedByMe: post.likedByMe,
            savedByMe: post.savedByMe,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt,
            authorID: channel.authorID,
            countryName: channel.countryName ?? post.countryName,
            countryCode: channel.countryCode ?? post.countryCode,
            cityName: post.cityName,
            author: author,
            linkURL: post.linkURL ?? channel.linkURL,
            linkTitle: post.linkTitle ?? channel.linkTitle,
            externalRefType: post.externalRefType ?? channel.externalRefType,
            externalRefID: post.externalRefID ?? channel.externalRefID
        )
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
        isPlayEligible(post) && !post.isReel && !post.isSpark && !isSparkFeedCard(post)
    }

    /// Hubs **For you** / category shelves only — never Sparks (those have their own strip).
    /// Prevents a long-form-looking row that opens the Sparks player.
    static func isHubsForYouLongForm(_ post: CountryPost) -> Bool {
        guard isPlayEligible(post), !post.isStory else { return false }
        // Any Spark identity → out of For you.
        if post.isReel || post.isSpark || isSparkFeedCard(post) { return false }
        if ReelsRankingEngine.isSparkEligible(post) { return false }
        let type = (post.mediaType ?? "").lowercased()
        if type == "reel" || type == "spark" { return false }
        // Must be hub / channel long-form (not a random feed clip).
        if post.isHubSeedVideo
            || HubVideoSeedService.isArchiveChannelAuthor(post.authorID)
            || post.id.lowercased().hasPrefix("ia_") {
            return true
        }
        return isHubCatalogContent(post)
            || isHubChannelUpload(post)
            || isHubOriginShare(post)
            || isHubFeedCardVideo(post)
    }

    /// Hub catalog long-form only — opens Hubs watch / shows Hubs badge in feed.
    /// Never Sparks or Spark re-shares (those use SparkFeedCard → infinite Sparks player).
    static func isHubFeedCardVideo(_ post: CountryPost) -> Bool {
        guard isHubCatalogContent(post), post.hasVideo, !post.isStory else { return false }
        // Spark chrome wins over Hubs chrome.
        if post.isReel || post.isSparkFeedShare || SparkShareMarker.isMarked(post.body) {
            return false
        }
        return true
    }

    static func isReelVideo(_ post: CountryPost) -> Bool {
        isPlayEligible(post) && post.isReel
    }

    /// True when the feed should show a Spark card (original or re-share).
    static func isSparkFeedCard(_ post: CountryPost) -> Bool {
        if post.isStory { return false }
        if post.isSparkFeedShare || SparkShareMarker.isMarked(post.body) { return true }
        if post.isReel || isReelVideo(post) { return true }
        if let embed = post.sharedPost?.asCountryPost, embed.isReel || isReelVideo(embed) {
            return true
        }
        return false
    }

    static func preferredPlayTab(for post: CountryPost) -> YouTubeMainTab {
        .home
    }

    static func shareURL(for post: CountryPost) -> URL {
        if isSparkFeedCard(post) {
            return URL(string: "https://matterya.com/post/\(post.sharedPostID ?? post.id)")!
        }
        if isHubCatalogContent(post), post.hasVideo {
            return URL(string: "https://matterya.com/play/watch/\(post.sharedPostID ?? post.id)")!
        }
        return URL(string: "https://matterya.com/post/\(post.sharedPostID ?? post.id)")!
    }

    /// Only true hub long-form gets the feed Hubs card + badge.
    /// Plain feed videos use the normal inline player (same controls, no badge).
    /// Sparks / Spark shares never take this path.
    static func showsPlayLinkInFeed(_ post: CountryPost, context: MediaContext = .feed) -> Bool {
        guard context == .feed else { return false }
        if isSparkFeedCard(post) { return false }
        return isHubFeedCardVideo(post)
    }

    static func channelURL(authorID: String, username: String?) -> URL {
        if let username, !username.isEmpty {
            return URL(string: "https://matterya.com/play/channel/\(username)")!
        }
        return URL(string: "https://matterya.com/play/channel/id/\(authorID)")!
    }
}