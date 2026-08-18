import PhotosUI
import SwiftUI

struct FacebookPostCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    var edgeToEdge: Bool = false
    var showsAuthorHeader: Bool = true
    var showsAuthorInJournal: Bool = false
    var mediaContext: MediaContext = .feed
    /// Home feed vs profile — same autoplay (≥50% visible, one winner).
    var autoplaySurface: FeedAutoplaySurface = .home
    var commentsInitiallyExpanded: Bool = false
    var onLikeToggle: (() -> Void)?
    var onOpenPost: () -> Void
    var onOpenVideo: (() -> Void)? = nil
    var onOpenReel: (() -> Void)? = nil
    var onPostDeleted: ((String) -> Void)?
    var onPostUpdated: ((CountryPost) -> Void)?
    /// Home feed: hide this post (local + ranking signal).
    var onHide: ((String) -> Void)? = nil
    /// Home feed: not interested (hide + author penalty + ranking signal).
    var onNotInterested: ((String) -> Void)? = nil
    /// Always expand/collapse comments on the card — never jump to post detail for comments.
    var expandsCommentsInline: Bool = true
    var viewingCountryISO: String? = nil

    @State private var commentsExpanded = false
    /// How many comments to show before “Load more” (stays on the card).
    @State private var visibleCommentLimit = 3
    @State private var inlineComments: [PostComment] = []
    /// Hydrated after load so “View N comments” survives remounts even if post.commentCount was 0.
    @State private var loadedCommentCount: Int = 0
    @State private var commentError: String?

    /// Prefer live loaded count, then origin/share max from the model.
    private var effectiveCommentCount: Int {
        max(post.displayCommentCount, loadedCommentCount, inlineComments.count)
    }
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var showReportConfirm = false
    @State private var actionBusy = false
    @State private var actionMessage: String?

    private var isOwnPost: Bool {
        guard let userID = appState.currentProfile?.userID else { return false }
        return post.authorID == userID
    }

    /// Readable side margin for text, headers, actions, comments (~16pt as before).
    /// Media / Spark / Hubs video stay full-bleed when `edgeToEdge` (card is always full width).
    private var textGutter: CGFloat {
        Theme.feedTextInset
    }

    /// Legacy alias — all chrome/text insets use the readable text gutter.
    private var horizontalGutter: CGFloat { textGutter }

    /// Spark chrome on feed: original Sparks + feed re-shares of Sparks (not long-form / Hubs).
    private var opensAsSpark: Bool {
        PlayPlatformBridge.isSparkFeedCard(post)
    }

    /// Feed re-share of a Hubs video or Spark (you shared it — not the channel posting as itself).
    private var isFeedReshareCard: Bool {
        // Explicit stamps.
        if PlayPlatformBridge.isHubOriginShare(post) { return true }
        if post.isSparkFeedShare || SparkShareMarker.isMarked(post.body) { return true }
        // Live user author + hub/spark media that isn't their channel publish.
        if PlayPlatformBridge.isFeedOnlyShare(post),
           PlayPlatformBridge.isLikelyLiveUserAuthor(post.authorID) {
            return true
        }
        return false
    }

    /// True when this card is a hub-origin long-form feed share (not a Spark).
    private var isHubOriginShareCard: Bool {
        if opensAsSpark { return false }
        if PlayPlatformBridge.isHubOriginShare(post) { return true }
        if PlayPlatformBridge.isR2LongFormMedia(post),
           PlayPlatformBridge.isLikelyLiveUserAuthor(post.authorID),
           !PlayPlatformBridge.isHubChannelUpload(post) {
            return true
        }
        if PlayPlatformBridge.isFeedOnlyShare(post),
           PlayPlatformBridge.isArchiveCatalogMedia(post),
           !opensAsSpark {
            return true
        }
        return showsPlayLinkInFeed
            && !PlayPlatformBridge.isHubChannelUpload(post)
            && !HubVideoSeedService.isArchiveChannelAuthor(post.authorID)
            && PlayPlatformBridge.isLikelyLiveUserAuthor(post.authorID)
    }

    /// Name on the card: **you (sharer)** for feed re-shares; channel only for native channel posts.
    private var cardPrimaryName: String {
        if isFeedReshareCard {
            return post.authorDisplayName
        }
        return PlayPlatformBridge.displayCreator(for: post).name
    }

    private var cardPrimaryAvatarURL: String? {
        if isFeedReshareCard {
            return post.author?.avatarURL
        }
        return PlayPlatformBridge.displayCreator(for: post).avatarURL
    }

    private var cardPrimaryAvatarSeed: String {
        if isFeedReshareCard {
            return post.authorID
        }
        return PlayPlatformBridge.displayCreator(for: post).seed
    }

    /// Follow target: the person shown on the name card (sharer for re-shares).
    private var cardPrimaryFollowID: String {
        if isFeedReshareCard {
            return post.authorID
        }
        return PlayPlatformBridge.displayCreator(for: post).authorID
    }

    private var showsFollowNextToName: Bool {
        let id = cardPrimaryFollowID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        if id == appState.currentProfile?.userID { return false }
        // Own post — no follow self.
        if isOwnPost { return false }
        return true
    }

    /// Source channel under the sharer's name: “Shared from The Archive”.
    private var sharedByLine: String? {
        guard isFeedReshareCard, let channel = originChannelDisplayName else { return nil }
        return "Shared from \(channel)"
    }

    /// Channel / creator the Hubs video or Spark originally came from.
    private var originChannelDisplayName: String? {
        if let origin = HubOriginShareMarker.originPresentation(from: post) {
            let n = origin.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { return n }
        }
        if let an = SparkShareMarker.originChannelName(from: post.body) {
            return an
        }
        if let embed = post.sharedPost?.asCountryPost {
            let n = embed.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty, embed.authorID != post.authorID {
                return n
            }
        }
        // Archive / seed media without stamp fields.
        if PlayPlatformBridge.isArchiveCatalogMedia(post)
            || post.isHubSeedVideo
            || HubVideoSeedService.isArchiveChannelAuthor(
                HubOriginShareMarker.originPresentation(from: post)?.authorID
                    ?? post.sharedPost?.asCountryPost.authorID
                    ?? ""
            ) {
            return HubVideoSeedService.archiveChannelDisplayName
        }
        // Hubs long-form feed share — prefer channel identity over generic brand.
        if isHubOriginShareCard {
            let creator = PlayPlatformBridge.displayCreator(for: post).name
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !creator.isEmpty, creator != post.authorDisplayName {
                return creator
            }
            return MatteryaCopy.matteryaHubs
        }
        if opensAsSpark {
            return MatteryaCopy.sparks
        }
        return nil
    }

    /// Subtle location under the author name (country name only — no flag).
    @ViewBuilder
    private var authorLocationLine: some View {
        if let location = post.authorLocationLabel {
            Text(location)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
                .accessibilityLabel("From \(location)")
        }
    }

    /// Stronger “away from your country” cue — only when browsing a different country.
    private var postedFromLabel: String? {
        guard let viewing = viewingCountryISO?.uppercased(),
              let postISO = post.countryCode?.uppercased(),
              !postISO.isEmpty,
              postISO != viewing
        else { return nil }

        let country = post.countryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCountry = (country?.isEmpty == false) ? country! : postISO
        if let city = post.cityName?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            return "Posted from \(city), \(resolvedCountry)"
        }
        return "Posted from \(resolvedCountry)"
    }

    @ViewBuilder
    private var postedFromBadge: some View {
        // Prefer the subtle always-on location line; keep capsule only when
        // the post is from outside the country the viewer is currently exploring.
        if postedFromLabel != nil, viewingCountryISO != nil {
            if let postedFromLabel {
                Label(postedFromLabel, systemImage: "mappin.and.ellipse")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.1), in: Capsule())
                    .accessibilityLabel(postedFromLabel)
            }
        }
    }

    /// Photo posts: caption only above the image (never duplicated below).
    private var isImageOnlyPost: Bool {
        post.hasImage && !post.hasVideo && !post.isReel && !post.isStory && post.sharedPost == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always show a name card on feed videos (YouTube-frame used to skip this and hide the author).
            if showsAuthorHeader {
                authorHeader
            } else {
                journalHeader
            }

            // Image posts: body/caption sits above the photo only.
            if isImageOnlyPost, !post.displayBody.isEmpty {
                captionBlock(text: post.displayBody, topPadding: 4, bottomPadding: 10)
            }

            // Sparks first — shared Sparks must be Spark cards (never Hubs long-form chrome).
            // Tap → infinite Matterya Sparks player (up/down).
            if opensAsSpark, mediaContext == .feed {
                SparkFeedCard(
                    post: sparkCardPresentationPost,
                    edgeToEdge: edgeToEdge,
                    autoplaySurface: autoplaySurface
                ) {
                    openReel()
                }
                // Full-width media — no side inset.
                .padding(.top, showsAuthorHeader || !post.displayExcerpt.isEmpty ? 0 : 8)
            } else if let embed = post.sharedPost {
                // Shared original — full-width media when edge-to-edge feed card.
                SharedPostEmbedView(
                    embed: embed,
                    autoplaySurface: autoplaySurface,
                    edgeToEdge: edgeToEdge
                )
            } else if post.sharedPostID != nil, !showsPlayLinkInFeed {
                // Only wait on embed when this share isn't already a stamped hub re-publish.
                SharedPostLoadingEmbed(postID: post.sharedPostID!)
                    .padding(.horizontal, textGutter)
            } else if showsPlayLinkInFeed {
                // Hub long-form or hub-origin feed share (badge). Opens original channel, never "creates" one.
                PlayFeedLinkCard(
                    post: post,
                    onOpen: { openPlayVideo() },
                    edgeToEdge: edgeToEdge,
                    forceHubsBadge: true,
                    autoplaySurface: autoplaySurface
                )
            } else if post.hasMedia {
                // Full-width photo / video.
                media
            }

            // Body text always has a small readable side margin (never edge-to-edge).
            if !isImageOnlyPost, !post.displayExcerpt.isEmpty {
                captionBlock(
                    text: post.displayExcerpt,
                    topPadding: post.hasMedia || opensAsSpark || showsPlayLinkInFeed || post.sharedPost != nil ? 12 : 10,
                    bottomPadding: 4
                )
            }

            actions
            meta

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, horizontalGutter)
                    .padding(.bottom, 8)
            }

            // Comments stay on the card — first few + load more. No navigation to post.
            if commentsExpanded {
                Divider()
                    .padding(.top, 8)

                PostCommentsView(
                    postID: commentsThreadID,
                    comments: $inlineComments,
                    showsComposer: true,
                    maxVisibleComments: visibleCommentLimit,
                    totalCommentCount: effectiveCommentCount,
                    onViewAllComments: {
                        // Load more in place — never open post detail. Grow until full thread.
                        withAnimation(.easeInOut(duration: 0.18)) {
                            visibleCommentLimit = min(
                                visibleCommentLimit + 25,
                                max(inlineComments.count, effectiveCommentCount, visibleCommentLimit + 25)
                            )
                        }
                    },
                    onError: { commentError = $0 }
                )
                .padding(.horizontal, horizontalGutter)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .onChange(of: inlineComments.count) { _, count in
                    if count > loadedCommentCount {
                        loadedCommentCount = count
                    }
                }

                if let commentError {
                    Text(commentError)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, horizontalGutter)
                        .padding(.bottom, 8)
                }
            }
        }
        // Critical containment: LazyVStack can propose unbounded width/height for some
        // own-upload media. Without minWidth:0 + clip, the whole card (buttons included)
        // lays out outside the screen frame.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(edgeToEdge ? Theme.canvas : Theme.surface)
        .clipShape(cardShape)
        .clipped()
        .overlay {
            if !edgeToEdge {
                cardShape
                    .stroke(Theme.border, lineWidth: 0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if edgeToEdge {
                Theme.divider.frame(height: 0.5)
            }
        }
        .padding(.bottom, edgeToEdge ? 10 : 0)

        .onAppear {
            // Seed from model (incl. origin count on shares) so the link never vanishes after tab hops.
            loadedCommentCount = max(loadedCommentCount, post.displayCommentCount)
            if commentsInitiallyExpanded {
                commentsExpanded = true
            }
            // Soft-hydrate count for shares / hubs that still report 0 (origin holds the thread).
            if post.displayCommentCount == 0,
               post.isSparkFeedShare
                || post.sharedPostID != nil
                || PlayPlatformBridge.isHubOriginShare(post)
                || isHubOriginShareCard {
                Task { await hydrateCommentCountIfNeeded() }
            }
        }
        .onChange(of: post.id) { _, _ in
            commentsExpanded = commentsInitiallyExpanded
            visibleCommentLimit = 3
            inlineComments = []
            loadedCommentCount = post.displayCommentCount
            commentError = nil
        }
        .onChange(of: post.commentCount) { _, newValue in
            loadedCommentCount = max(loadedCommentCount, newValue, post.displayCommentCount)
        }
        .sheet(isPresented: $showEditSheet) {
            PostEditSheet(post: post) { updated in
                onPostUpdated?(updated)
                actionMessage = "Post updated."
            }
        }
        .confirmationDialog("Delete this post?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await deletePost() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Report this post", isPresented: $showReportConfirm, titleVisibility: .visible) {
            ForEach(reportReasons, id: \.self) { reason in
                Button(reason, role: .destructive) {
                    Task { await reportPost(reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var authorHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                openAuthorProfile()
            } label: {
                // Always the hand-drawn picture frame on name cards (not the feed circle shortcut).
                AvatarView(
                    url: cardPrimaryAvatarURL,
                    seed: cardPrimaryAvatarSeed,
                    size: 36
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        openAuthorProfile()
                    } label: {
                        Text(cardPrimaryName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    if showsFollowNextToName {
                        FollowButton(userID: cardPrimaryFollowID, compact: true)
                    }
                }

                if let sharedByLine {
                    Text(sharedByLine)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                } else {
                    authorLocationLine
                }
                postTimestampRow
                postedFromBadge
            }

            Spacer(minLength: 8)
                .contentShape(Rectangle())
                .onTapGesture { openPrimaryDestination() }

            postOptionsMenu

            Button(action: openPrimaryDestination) {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, horizontalGutter)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var journalHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author row only — real title (if any) sits full-width below.
            HStack(alignment: .center, spacing: 10) {
                if showsAuthorInJournal {
                    Button {
                        openAuthorProfile()
                    } label: {
                        // Hand-drawn scrapbook frame — same as pre-perf shortcut on feed name cards.
                        AvatarView(
                            url: cardPrimaryAvatarURL,
                            seed: cardPrimaryAvatarSeed,
                            size: 36
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .center, spacing: 8) {
                            Button {
                                openAuthorProfile()
                            } label: {
                                Text(cardPrimaryName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)

                            if showsFollowNextToName {
                                FollowButton(userID: cardPrimaryFollowID, compact: true)
                            }
                        }

                        if let sharedByLine {
                            Text(sharedByLine)
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                                .lineLimit(1)
                        } else {
                            authorLocationLine
                        }
                        postedFromBadge
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        authorLocationLine
                        postedFromBadge
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 8)
                    .contentShape(Rectangle())
                    .onTapGesture { openPrimaryDestination() }

                VStack(alignment: .trailing, spacing: 8) {
                    postOptionsMenu
                    postTimestampRow
                }
            }
            .padding(.horizontal, horizontalGutter)

            // Only an explicit post title here — never a body prefix (that duplicated captions).
            if let title = post.displayTitle, !title.isEmpty {
                Text(title)
                    .postHeadlineStyle(lineLimit: 4)
                    .padding(.horizontal, horizontalGutter)
                    .contentShape(Rectangle())
                    .onTapGesture { openPrimaryDestination() }
            }

            // Hubs channel attribution under the title (share / channel long-form).
            if showsPlayLinkInFeed, let channelLine = hubChannelAttributionLine {
                Text(channelLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
                    .padding(.horizontal, horizontalGutter)
                    .padding(.top, post.displayTitle != nil ? 2 : 0)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, post.displayTitle != nil || showsPlayLinkInFeed || isImageOnlyPost ? 12 : 10)
    }

    private func captionBlock(text: String, topPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        ExpandableBodyText(
            text: text,
            collapsedLineLimit: 4,
            font: .body,
            color: Theme.inkSecondary,
            lineSpacing: 4,
            moreTitle: "See more",
            lessTitle: "See less",
            uiTextStyle: .body
        )
        // Small side margin so multi-line text stays readable on full-width cards.
        .padding(.horizontal, textGutter)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .id("post-body-\(post.id)")
        .contentShape(Rectangle())
        .onTapGesture { openPrimaryDestination() }
    }

    /// Extra channel line under journal titles only when the name row does **not** already
    /// show `sharedByLine` (avoids “Shared from …” twice on feed + profile share cards).
    /// Native hub_* posts already show the channel as the author — no extra line.
    private var hubChannelAttributionLine: String? {
        // Re-shares: only under the name once — never again under the title.
        if isFeedReshareCard { return nil }
        // Name row already has sharedByLine when present.
        if sharedByLine != nil { return nil }
        guard showsPlayLinkInFeed else { return nil }
        // Channel is already the name card for The Archive / hub seed posts.
        if HubVideoSeedService.isArchiveChannelAuthor(post.authorID) {
            return nil
        }
        if let caption = post.displayCaption, !caption.isEmpty {
            if caption.localizedCaseInsensitiveContains("from ") {
                return caption
            }
            return "From \(caption) · \(MatteryaCopy.matteryaHubs)"
        }
        if post.hubSlug != nil || post.isHubSeedVideo {
            return "From \(HubVideoSeedService.archiveChannelDisplayName) · \(MatteryaCopy.matteryaHubs)"
        }
        if HubChannelPostMarker.isMarked(post.body) {
            return "Shared from \(MatteryaCopy.matteryaHubs)"
        }
        return nil
    }

    private var postTimestampRow: some View {
        HStack(spacing: 6) {
            Text(RelativeTime.format(post.createdAt))
            if post.isEdited {
                Text("Edited")
                    .fontWeight(.semibold)
            }
            if isOwnPost, post.visibility != .public, post.visibility != .country {
                Image(systemName: post.visibility == .private ? "lock.fill" : "person.2.fill")
            }
        }
        .font(.caption2)
        .foregroundStyle(Theme.inkMuted)
    }

    private var postOptionsMenu: some View {
        Menu {
            if isOwnPost {
                Button("Edit") { showEditSheet = true }
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            }
            if !isOwnPost {
                if onHide != nil {
                    Button {
                        onHide?(post.id)
                        actionMessage = "Hidden from your feed."
                    } label: {
                        Label("Hide post", systemImage: "eye.slash")
                    }
                }
                if onNotInterested != nil {
                    Button {
                        onNotInterested?(post.id)
                        actionMessage = "We'll show less like this."
                    } label: {
                        Label("Not interested", systemImage: "hand.thumbsdown")
                    }
                }
                Button("Block \(post.authorDisplayName)", role: .destructive) {
                    appState.blockUser(
                        post.authorID,
                        username: post.author?.username,
                        displayName: post.author?.displayName
                    )
                }
            }
            Button("Report", role: .destructive) { showReportConfirm = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(actionBusy)
    }

    private var usesYouTubeVideoFrame: Bool {
        FacebookMediaLayout.usesYouTubeFrame(for: post, context: mediaContext)
    }

    private var showsPlayLinkInFeed: Bool {
        PlayPlatformBridge.showsPlayLinkInFeed(post, context: mediaContext)
    }

    private var cardShape: UnevenRoundedRectangle {
        if edgeToEdge {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        }
        if usesYouTubeVideoFrame, post.hasMedia, !showsPlayLinkInFeed {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: Theme.cardRadius,
                bottomTrailingRadius: Theme.cardRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: Theme.cardRadius,
            bottomLeadingRadius: Theme.cardRadius,
            bottomTrailingRadius: Theme.cardRadius,
            topTrailingRadius: Theme.cardRadius,
            style: .continuous
        )
    }

    /// Media for the Spark card — prefer self-contained share media, else embedded original.
    private var sparkCardPresentationPost: CountryPost {
        if post.playableVideoURL != nil { return post }
        if let embed = post.sharedPost?.asCountryPost, embed.playableVideoURL != nil {
            return embed
        }
        return post
    }

    @ViewBuilder
    private var media: some View {
        // Sparks are handled above the hub/share branches so they never become Hubs cards.
        if let aspect = FacebookMediaLayout.aspectRatio(for: post, context: mediaContext) {
            let isFeedAutoplayVideo = post.hasVideo
                && mediaContext == .feed
                && !opensAsSpark
                && post.playableVideoURL != nil

            Group {
                if post.hasVideo {
                    // Feed/profile: one autoplay winner with in-frame scrub/pause (no post navigation).
                    if isFeedAutoplayVideo, let url = post.playableVideoURL {
                        feedAutoplayVideo(url: url)
                    } else {
                        feedVideoPoster
                    }
                } else if let url = post.feedImageURL {
                    CachedAsyncImage(
                        url: url,
                        maxPixelSize: 420,
                        contentMode: .fill,
                        placeholder: AnyView(mediaPlaceholder)
                    )
                } else {
                    mediaPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .modifier(FeedMediaSizeModifier(
                isVideo: post.hasVideo && mediaContext == .feed && !opensAsSpark,
                photoAspect: aspect,
                usesYouTubeFrame: usesYouTubeVideoFrame,
                // Hubs only: compact 16:9 (no black gaps). Sparks/photos keep tall/aspect sizing.
                isHubCompact: PlayPlatformBridge.isHubFeedCardVideo(post)
                    || PlayPlatformBridge.isHubCatalogContent(post)
                    || isHubOriginShareCard
            ))
            .clipped()
            .overlay(alignment: .bottom) {
                if !post.hasVideo {
                    LinearGradient(
                        colors: [.clear, Theme.ink.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                }
            }
            .contentShape(Rectangle())
            // Autoplay video owns taps (controls/scrub). Posters/images still open media.
            .onTapGesture {
                guard !isFeedAutoplayVideo else { return }
                openMedia()
            }
            .padding(.top, usesYouTubeVideoFrame || showsAuthorHeader || !post.displayExcerpt.isEmpty ? 0 : 8)
        }
    }

    @ViewBuilder
    private func feedAutoplayVideo(url: URL) -> some View {
        let isHub = PlayPlatformBridge.isHubCatalogContent(post)
            || PlayPlatformBridge.isHubFeedCardVideo(post)
            || isHubOriginShareCard
            || ArchiveVideoPlayback.isArchiveURL(url)
        // Feed: only Archive CDN needs MatteryaHubPlayer. R2 hubs use light AV path —
        // mounting the hub UIKit player on every cell froze scroll.
        let useArchivePath = ArchiveVideoPlayback.isArchiveURL(url)
        InFrameVideoPlayer(
            url: url,
            posterURL: post.posterImageURL,
            placement: nil,
            countryCode: post.countryCode,
            contentCountryCode: post.countryCode,
            postID: post.id,
            muted: false,
            loops: true,
            preferArchivePlayer: useArchivePath,
            showsControls: true,
            // Hubs long-form: always fit (never crop). Sparks/short may fill.
            fillsFrame: !isHub,
            autoplaySurface: autoplaySurface,
            onViewed: { Task { await PostsService.shared.recordView(post) } }
        )
        .background(isHub ? Theme.ink : Color.clear)
    }

    private var actions: some View {
        HStack(spacing: 18) {
            Button { onLikeToggle?() } label: {
                Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundStyle(post.likedByMe ? Theme.like : Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                // Prefetch before expand so comments don't load *after* the user taps.
                if !commentsExpanded {
                    let threadID = commentsThreadID
                    CommentsWarmCache.shared.warm(threadID)
                    if inlineComments.isEmpty,
                       let warm = CommentsWarmCache.shared.cached(threadID) {
                        inlineComments = warm
                    }
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if !commentsExpanded {
                        visibleCommentLimit = 3
                    }
                    commentsExpanded.toggle()
                }
            } label: {
                Image(systemName: commentsExpanded ? "bubble.right.fill" : "bubble.right")
                    .font(.system(size: 22))
                    .foregroundStyle(commentsExpanded ? Theme.ink : Theme.inkMuted)
            }
            .buttonStyle(.plain)

            Button {
                appState.presentShareSheet(for: post)
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    if let error = await appState.toggleSavePost(
                        post,
                        reelPresentation: AppState.belongsInSavedSparks(post)
                    ) {
                        actionMessage = error
                    }
                }
            } label: {
                Image(systemName: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 21))
                    .foregroundStyle(appState.isPostSaved(post.id) ? Theme.ink : Theme.inkMuted)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, horizontalGutter)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 6) {
            if post.likeCount > 0 {
                Text("\(post.likeCount) \(post.likeCount == 1 ? "like" : "likes")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            // Always show the expand row when there is a thread (local or origin).
            // Survives Hubs ↔ Feed tab hops because count comes from model + hydrate, not expand state alone.
            if effectiveCommentCount > 0, !commentsExpanded {
                Button {
                    let threadID = commentsThreadID
                    CommentsWarmCache.shared.warm(threadID)
                    if inlineComments.isEmpty,
                       let warm = CommentsWarmCache.shared.cached(threadID) {
                        inlineComments = warm
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        visibleCommentLimit = 3
                        commentsExpanded = true
                    }
                } label: {
                    Text("View \(effectiveCommentCount) \(effectiveCommentCount == 1 ? "comment" : "comments")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
            }

            if showsAuthorHeader, let title = post.displayTitle {
                Text(title)
                    .postHeadlineStyle(lineLimit: 3)
            }


        }
        .padding(.horizontal, horizontalGutter)
        .padding(.bottom, 14)
    }

    private var mediaPlaceholder: some View {
        Rectangle()
            .fill(Theme.canvasMuted)
            .overlay {
                Image(systemName: post.hasVideo ? "video" : "photo")
                    .foregroundStyle(Theme.inkMuted)
            }
    }

    private var feedVideoPoster: some View {
        Group {
            if usesYouTubeVideoFrame {
                // Never extract frames while scrolling the feed — posters only.
                YouTubeVideoThumbnail(
                    post: post,
                    maxPixelSize: 420,
                    frameStyle: .feed,
                    embedsFrame: false,
                    extractFrameIfNeeded: false
                )
            } else {
                VideoThumbnailView(
                    post: post,
                    maxPixelSize: 420,
                    contentMode: .fill,
                    showsPlayIcon: false,
                    extractFrameIfNeeded: false,
                    placeholder: AnyView(mediaPlaceholder)
                )
            }
        }
    }

    private var reportReasons: [String] {
        ["Spam", "Harassment", "Misinformation", "Other"]
    }

    private func openPrimaryDestination() {
        if opensAsSpark {
            openReel()
        } else {
            onOpenPost()
        }
    }

    private func openMedia() {
        if opensAsSpark {
            openReel()
        } else if showsPlayLinkInFeed {
            openPlayVideo()
        } else if post.hasVideo, mediaContext == .feed, let onOpenVideo {
            onOpenVideo()
        } else {
            onOpenPost()
        }
    }

    private func openReel() {
        // Always endless Sparks from all over Matterya (up/down), never a single-clip dead end.
        appState.openGlobalSparksViewer(startingPost: sparkCardPresentationPost)
    }

    private func openPlayVideo() {
        if let onOpenVideo {
            onOpenVideo()
            return
        }
        // Shared Hubs long-form → continuous Hubs player immediately (same as Hubs tab).
        if PlayPlatformBridge.isHubFeedCardVideo(post)
            || PlayPlatformBridge.isHubOriginShare(post)
            || PlayPlatformBridge.isHubCatalogContent(post) {
            let quick = PlayPlatformBridge.hubWatchPresentation(for: post)
            appState.startHubPlayback(quick, expanded: true)
            return
        }
        appState.openPost(post)
    }

    private func openAuthorProfile() {
        // Feed re-share: name/avatar are the **sharer** — open their profile.
        if isFeedReshareCard {
            appState.openPublicProfile(
                username: post.author?.username,
                userID: post.authorID
            )
            return
        }
        // Native Hubs / channel posts: open the channel shown on the card.
        let creator = PlayPlatformBridge.displayCreator(for: post)
        if creator.authorID.hasPrefix("hub_")
            || HubVideoSeedService.isArchiveChannelAuthor(creator.authorID)
            || PlayPlatformBridge.isHubCatalogContent(post)
            || PlayPlatformBridge.isHubChannelUpload(post) {
            appState.openPlayChannel(authorID: creator.authorID, username: creator.username)
            return
        }
        appState.openPublicProfile(username: creator.username, userID: creator.authorID)
    }

    /// Share/hub cards: comments live on the **origin** post id when stamped.
    private var commentsThreadID: String {
        PostsService.commentThreadOriginID(for: post.id, post: post) ?? post.id
    }

    /// Pull thread size without expanding — keeps “View N comments” on share cards after tab switches.
    private func hydrateCommentCountIfNeeded() async {
        let threadID = commentsThreadID
        // Always idle-warm so the first Chat tap is filled.
        CommentsWarmCache.shared.warm(threadID)
        if threadID != post.id {
            CommentsWarmCache.shared.warm(post.id)
        }
        if let warm = CommentsWarmCache.shared.cached(threadID) ?? CommentsWarmCache.shared.cached(post.id),
           !warm.isEmpty {
            await MainActor.run {
                loadedCommentCount = max(loadedCommentCount, warm.count)
                if inlineComments.isEmpty { inlineComments = warm }
            }
        }
        guard loadedCommentCount == 0, effectiveCommentCount == 0 else { return }
        let loaded = await CommentsWarmCache.shared.load(threadID)
        guard !loaded.isEmpty else { return }
        await MainActor.run {
            loadedCommentCount = max(loadedCommentCount, loaded.count)
            // Cache lightly so expanding is instant if they tap next.
            if inlineComments.isEmpty {
                inlineComments = loaded
            }
        }
    }

    private func deletePost() async {
        actionBusy = true
        defer { actionBusy = false }
        do {
            // PostsService.deletePost tombstones + purges caches + broadcasts userPostDidDelete
            // so feed AND profile drop the card (and it stays gone after relaunch).
            let deleted = try await PostsService.shared.deletePost(post.id)
            guard deleted else {
                actionMessage = "Could not delete post."
                return
            }
            onPostDeleted?(post.id)
            actionMessage = "Post deleted."
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func reportPost(reason: String) async {
        actionBusy = true
        defer { actionBusy = false }
        do {
            let reported = try await PostsService.shared.reportPost(post.id, reason: reason)
            actionMessage = reported ? "Post reported. Thank you." : "Could not report post."
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

private struct SharedPostLoadingEmbed: View {
    let postID: String

    @State private var embed: SharedPostPreview?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let embed {
                SharedPostEmbedView(embed: embed)
            } else if loadFailed {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.bubble")
                        .foregroundStyle(Theme.inkMuted)
                    Text("Original post unavailable")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.canvasMuted)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading shared post…")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 8)
            }
        }
        .task(id: postID) {
            loadFailed = false
            if let post = try? await PostsService.shared.getPostByID(postID),
               post.hasFeedVisibleContent {
                embed = SharedPostPreview(
                    id: post.id,
                    title: post.title,
                    body: post.body,
                    mediaType: post.mediaType,
                    mediaURL: post.mediaURL,
                    thumbURL: post.thumbURL,
                    authorID: post.authorID,
                    author: post.author,
                    externalRefType: post.externalRefType,
                    externalRefID: post.externalRefID
                )
            } else {
                loadFailed = true
            }
        }
    }
}

private struct PostEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let post: CountryPost
    let onSaved: (CountryPost) -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var visibility: PostVisibility
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var removeExistingImage = false
    @State private var busy = false
    @State private var errorMessage: String?

    private var canEditImage: Bool {
        post.hasImage && !post.hasVideo && !post.isReel && !post.isStory
    }

    init(post: CountryPost, onSaved: @escaping (CountryPost) -> Void) {
        self.post = post
        self.onSaved = onSaved
        _title = State(initialValue: post.displayTitle ?? "")
        _bodyText = State(initialValue: post.displayBody)
        let initialVisibility = post.visibility == .country ? PostVisibility.public : post.visibility
        _visibility = State(initialValue: initialVisibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Optional title", text: $title)
                }
                Section("Body") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 140)
                }
                Section("Privacy") {
                    PostVisibilityControl(visibility: $visibility)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                if canEditImage {
                    Section("Photo") {
                        editImageSection
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(busy)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadSelectedPhoto(item) }
            }
        }
    }

    @ViewBuilder
    private var editImageSection: some View {
        if let previewImage {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    clearReplacementImage()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
        } else if post.hasImage, !removeExistingImage, let url = post.feedImageURL {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle().fill(Theme.canvasMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    removeExistingImage = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Replace photo", systemImage: "photo.on.rectangle.angled")
            }
        } else {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Add photo", systemImage: "photo.on.rectangle.angled")
            }

            if post.hasImage, removeExistingImage {
                Button("Restore original photo", role: .cancel) {
                    removeExistingImage = false
                }
            }
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { return }
            guard let image = UIImage(data: raw) else { return }
            let jpeg = image.jpegData(compressionQuality: 0.88) ?? raw
            imageData = jpeg
            previewImage = UIImage(data: jpeg)
            removeExistingImage = false
            selectedPhoto = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            clearReplacementImage()
        }
    }

    private func clearReplacementImage() {
        imageData = nil
        previewImage = nil
        selectedPhoto = nil
    }

    private func save() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            var mediaType: String?
            var mediaURL: String?
            var clearMedia = false

            if canEditImage {
                if let imageData {
                    let upload = try await MediaService.shared.uploadPostMedia(
                        data: imageData,
                        fileExtension: "jpg",
                        mimeType: "image/jpeg"
                    )
                    mediaType = "image"
                    mediaURL = upload.publicURL
                } else if removeExistingImage, post.hasImage {
                    clearMedia = true
                }
            }

            let updated = try await PostsService.shared.updatePost(
                post.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfWhitespace,
                body: preservedBody(from: bodyText),
                visibility: visibility,
                mediaType: mediaType,
                mediaURL: mediaURL,
                clearMedia: clearMedia
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func preservedBody(from edited: String) -> String {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard post.isStory else { return trimmed }

        let marker = post.body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("__story__|") })

        if let marker {
            return trimmed.isEmpty ? marker : "\(trimmed)\n\(marker)"
        }
        if let expires = PostStoryMarker.expiresAt(from: post.body) {
            return PostStoryMarker.buildBody(caption: trimmed, expiresAt: expires)
        }
        return trimmed
    }
}

/// Videos: full post-card width + height by kind. Photos keep aspect ratio.
/// Hubs → compact 16:9 (aspect-fit, no black bands). Sparks/other video → tall FB box.
/// Always clamps size so LazyVStack never lets media (or the whole card) escape the screen.
private struct FeedMediaSizeModifier: ViewModifier {
    let isVideo: Bool
    let photoAspect: CGFloat
    let usesYouTubeFrame: Bool
    var isHubCompact: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let aspect = FacebookMediaLayout.clampedAspect(photoAspect)
        if isVideo {
            let height = isHubCompact
                ? FacebookMediaLayout.hubFeedVideoHeight()
                : FacebookMediaLayout.dominantFeedVideoHeight()
            content
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .contentShape(Rectangle())
        } else {
            content
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(aspect, contentMode: .fit)
                .frame(
                    minWidth: 0,
                    maxWidth: .infinity,
                    maxHeight: usesYouTubeFrame
                        ? FacebookMediaLayout.maxFeedMediaHeight
                        : FacebookMediaLayout.maxFeedMediaHeight
                )
                .clipped()
                .contentShape(Rectangle())
        }
    }
}

private extension String {
    var nilIfWhitespace: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}