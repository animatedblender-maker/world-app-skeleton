import PhotosUI
import SwiftUI

struct FacebookPostCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    var edgeToEdge: Bool = false
    var showsAuthorHeader: Bool = true
    var showsAuthorInJournal: Bool = false
    var mediaContext: MediaContext = .feed
    /// Home feed vs profile — same autoplay (≥25% / quarter visible, one winner).
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
    /// Instagram-style pinch on the photo — lifts above clip until release.
    @State private var isPhotoPinching = false
    /// Tap photo → fullscreen pinch/pan lightbox (Instagram).
    @State private var showPhotoLightbox = false
    @State private var lightboxStartIndex = 0

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

    private var cardPrimaryShowsVerified: Bool {
        if isFeedReshareCard {
            return post.author?.showsVerifiedBadge == true
        }
        if let author = post.author, author.showsVerifiedBadge { return true }
        let handle = (PlayPlatformBridge.displayCreator(for: post).username ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return handle == "matterya"
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

    /// Source channel / creator for feed re-shares — never brand labels like “Sparks” / “Matterya Hubs”.
    private struct OriginSource: Equatable {
        let name: String
        let authorID: String
        let username: String?
    }

    /// Clickable channel name under the sharer (opens that channel or profile).
    private var originSource: OriginSource? {
        guard isFeedReshareCard else { return nil }

        if let origin = HubOriginShareMarker.originPresentation(from: post) {
            let n = origin.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if isUsableOriginName(n) {
                return OriginSource(
                    name: n,
                    authorID: origin.authorID,
                    username: origin.author?.username
                )
            }
        }

        if let an = SparkShareMarker.originChannelName(from: post.body), isUsableOriginName(an) {
            let stampedID = SparkShareMarker.originAuthorID(from: post.body) ?? ""
            let embed = post.sharedPost?.asCountryPost
            let authorID = !stampedID.isEmpty
                ? stampedID
                : (embed?.authorID ?? "")
            let username = SparkShareMarker.originUsername(from: post.body)
                ?? (embed?.authorID == authorID ? embed?.author?.username : nil)
            return OriginSource(name: an, authorID: authorID, username: username)
        }

        if let embed = post.sharedPost?.asCountryPost {
            let n = embed.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if isUsableOriginName(n), embed.authorID != post.authorID {
                return OriginSource(
                    name: n,
                    authorID: embed.authorID,
                    username: embed.author?.username
                )
            }
        }

        // True Internet Archive seed without stamp fields → "Shared from The Archive".
        if post.isHubSeedVideo
            || HubVideoSeedService.isArchiveChannelAuthor(
                HubOriginShareMarker.originPresentation(from: post)?.authorID
                    ?? post.sharedPost?.asCountryPost.authorID
                    ?? ""
            ) {
            return OriginSource(
                name: HubVideoSeedService.archiveChannelDisplayName,
                authorID: HubVideoSeedService.archiveChannelAuthorID,
                username: HubVideoSeedService.archiveChannelUsername
            )
        }

        // Hubs long-form feed share — real channel name (Dokumentar AL, etc.), never brand.
        if isHubOriginShareCard {
            let creator = PlayPlatformBridge.displayCreator(for: post)
            let n = creator.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if isUsableOriginName(n),
               n != post.authorDisplayName,
               creator.authorID != post.authorID {
                return OriginSource(
                    name: n,
                    authorID: creator.authorID,
                    username: creator.username
                )
            }
            // Person is primary; if displayCreator collapsed to the same person, try embed.
            if let embed = post.sharedPost?.asCountryPost {
                let en = embed.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if isUsableOriginName(en), embed.authorID != post.authorID {
                    return OriginSource(
                        name: en,
                        authorID: embed.authorID,
                        username: embed.author?.username
                    )
                }
            }
        }

        return nil
    }

    private func isUsableOriginName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        let normalized = n.replacingOccurrences(of: "\u{00A0}", with: " ")
        if normalized.caseInsensitiveCompare(MatteryaCopy.sparks) == .orderedSame { return false }
        if normalized.caseInsensitiveCompare(MatteryaCopy.spark) == .orderedSame { return false }
        let hubs = MatteryaCopy.matteryaHubs.replacingOccurrences(of: "\u{00A0}", with: " ")
        if normalized.caseInsensitiveCompare(hubs) == .orderedSame { return false }
        if normalized.caseInsensitiveCompare("Matterya Hubs") == .orderedSame { return false }
        return true
    }

    @ViewBuilder
    private var originSourceLink: some View {
        if let origin = originSource {
            sharedFromOriginLink(origin)
        }
    }

    /// “Shared from {Name}” — prefix plain, name underlined + tappable (feed + journal).
    @ViewBuilder
    private func sharedFromOriginLink(_ origin: OriginSource) -> some View {
        HStack(spacing: 4) {
            Text("Shared from")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
            Button {
                openOriginSource(origin)
            } label: {
                Text(origin.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .underline(true, color: Theme.ink.opacity(0.45))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shared from \(origin.name)")
        .accessibilityHint("Opens channel or profile")
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

            // Image posts: caption above the photo (body, or headline when body empty — never both).
            if isImageOnlyPost {
                let caption = post.displayExcerpt
                if !caption.isEmpty {
                    captionBlock(text: caption, topPadding: 4, bottomPadding: 10)
                }
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
                // Video container only (16:9 film + timeline). Social row is below.
                PlayFeedLinkCard(
                    post: post,
                    onOpen: { openPlayVideo() },
                    edgeToEdge: true,
                    forceHubsBadge: true,
                    autoplaySurface: autoplaySurface
                )
            } else if post.hasMedia {
                // Full-width photo / video.
                media
            }

            // UNDER the video container — never inside it (Sparks / Hubs shares).
            if showsPlayLinkInFeed || opensAsSpark {
                actions
                    .padding(.top, 10)
                if !isImageOnlyPost, !post.displayExcerpt.isEmpty {
                    captionBlock(
                        text: post.displayExcerpt,
                        topPadding: 8,
                        bottomPadding: 4
                    )
                }
                meta
            } else {
                // Written/text: one caption line (body, or headline-only when body empty).
                if !isImageOnlyPost, !post.displayExcerpt.isEmpty {
                    captionBlock(
                        text: post.displayExcerpt,
                        topPadding: post.hasMedia || post.sharedPost != nil ? 12 : 10,
                        bottomPadding: 4
                    )
                }
                actions
                    .padding(.top, 4)
                meta
            }

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
        // Sparks / Hubs shares: do NOT clip actions into the media rounded card —
        // film clips itself; like/share/save/comments sit under on the canvas.
        // Photo pinch also skips clip so the image can grow under the fingers.
        .modifier(FeedCardClipModifier(
            shape: cardShape,
            clipWholeCard: !isPhotoPinching
                && !(edgeToEdge && (opensAsSpark || showsPlayLinkInFeed))
        ))
        .zIndex(isPhotoPinching ? 200 : 0)
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
        .fullScreenCover(isPresented: $showPhotoLightbox) {
            MatteryaPhotoLightbox(
                urls: post.feedImageURLs,
                startIndex: lightboxStartIndex
            ) {
                showPhotoLightbox = false
            }
        }

        .onAppear {
            // Seed from model (incl. origin count on shares) so the link never vanishes after tab hops.
            loadedCommentCount = max(loadedCommentCount, post.displayCommentCount)
            let threadID = commentsThreadID
            // Viewport prefetch — first page ready before Chat / expand tap.
            CommentsWarmCache.shared.warm(threadID)
            if threadID != post.id {
                CommentsWarmCache.shared.warm(post.id)
            }
            if inlineComments.isEmpty,
               let warm = CommentsWarmCache.shared.cached(threadID)
                ?? CommentsWarmCache.shared.cached(post.id) {
                inlineComments = warm
                loadedCommentCount = max(loadedCommentCount, warm.count)
            }
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
            let threadID = commentsThreadID
            CommentsWarmCache.shared.warm(threadID)
            if let warm = CommentsWarmCache.shared.cached(threadID)
                ?? CommentsWarmCache.shared.cached(post.id) {
                inlineComments = warm
                loadedCommentCount = max(loadedCommentCount, warm.count)
            }
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
                        HStack(spacing: 5) {
                            Text(cardPrimaryName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            if cardPrimaryShowsVerified {
                                MatteryaVerifiedBadge(size: 14)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if showsFollowNextToName {
                        FollowButton(userID: cardPrimaryFollowID, compact: true)
                    }
                }

                if originSource != nil {
                    originSourceLink
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
                                HStack(spacing: 5) {
                                    Text(cardPrimaryName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    if cardPrimaryShowsVerified {
                                        MatteryaVerifiedBadge(size: 14)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            if showsFollowNextToName {
                                FollowButton(userID: cardPrimaryFollowID, compact: true)
                            }
                        }

                        if originSource != nil {
                            originSourceLink
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

            // No headlines on posts — body/caption only. Keep 18+ mark when needed.
            if post.isAdultContent {
                Text("18+")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.surface)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.ink.opacity(0.85), in: Capsule())
                    .padding(.horizontal, horizontalGutter)
                    .accessibilityLabel("18 plus content")
            }

            // Hubs channel attribution — “Shared from {underlined name}”.
            if showsPlayLinkInFeed, let channel = hubChannelAttributionSource {
                sharedFromOriginLink(channel)
                    .padding(.horizontal, horizontalGutter)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, showsPlayLinkInFeed || isImageOnlyPost ? 12 : 10)
    }

    private func captionBlock(text: String, topPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        // Image cards: plain line-limited Text — ExpandableBodyText's GeometryReader +
        // UIKit truncation measure hitch Home scroll (Sparks/Hubs captions are short/absent).
        Group {
            if isImageOnlyPost {
                MatteryaRichText(
                    text: text,
                    font: .body,
                    color: Theme.inkSecondary,
                    lineSpacing: 4,
                    lineLimit: 4
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            } else {
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
            }
        }
        // Small side margin so multi-line text stays readable on full-width cards.
        .padding(.horizontal, textGutter)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .id("post-body-\(post.id)")
        .contentShape(Rectangle())
        .onTapGesture { openPrimaryDestination() }
    }

    /// Extra channel link under journal titles only when the name row does **not** already
    /// show the origin source (avoids duplicating the channel name on feed + profile cards).
    /// Native hub_* / channel posts already show the channel as the author — no extra line.
    private var hubChannelAttributionSource: OriginSource? {
        // Re-shares: only under the name once — never again under the title.
        if isFeedReshareCard { return nil }
        if originSource != nil { return nil }
        guard showsPlayLinkInFeed else { return nil }
        // Channel is already the name card for The Archive seed posts.
        if HubVideoSeedService.isArchiveChannelAuthor(post.authorID) {
            return nil
        }
        // True Archive seeds only — never rewrite live hub_slug posts to The Archive.
        if post.isHubSeedVideo {
            return OriginSource(
                name: HubVideoSeedService.archiveChannelDisplayName,
                authorID: HubVideoSeedService.archiveChannelAuthorID,
                username: HubVideoSeedService.archiveChannelUsername
            )
        }
        let creator = PlayPlatformBridge.displayCreator(for: post)
        let n = creator.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isUsableOriginName(n), creator.authorID != post.authorID {
            return OriginSource(
                name: n,
                authorID: creator.authorID,
                username: creator.username
            )
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
                } else if !post.feedImageURLs.isEmpty {
                    // Multi-photo gallery (amiuglytruth etc.) or single pinch photo.
                    // 540 decode + scroll-simultaneous pinch — image cards were freezing
                    // Home while Sparks/Hubs (no pinch overlay) stayed smooth.
                    let urls = post.feedImageURLs
                    if urls.count > 1 {
                        MatteryaImageGallery(
                            urls: urls,
                            maxPixelSize: 720,
                            onZoomingChanged: { zooming in
                                isPhotoPinching = zooming
                            },
                            onTapPage: { openPhotoLightbox(at: $0) }
                        )
                    } else if let url = urls.first {
                        FeedPinchZoomPhoto(
                            url: url,
                            maxPixelSize: 720,
                            contentMode: .fit,
                            placeholder: AnyView(mediaPlaceholder),
                            onZoomingChanged: { zooming in
                                isPhotoPinching = zooming
                            },
                            onTap: { openPhotoLightbox(at: 0) }
                        )
                    }
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
                    || isHubOriginShareCard,
                // Pinch zoom must escape the media box.
                clipsContent: !isPhotoPinching
            ))
            .zIndex(isPhotoPinching ? 80 : 0)
            .contentShape(Rectangle())
            // Videos/posters: tap opens. Photos use FeedPinchZoomPhoto.onTap (UIKit).
            .onTapGesture {
                guard !isFeedAutoplayVideo, !isPhotoPinching else { return }
                if post.feedImageURL != nil, !post.hasVideo { return }
                openMedia()
            }
            .padding(.top, usesYouTubeVideoFrame || showsAuthorHeader || !post.displayExcerpt.isEmpty ? 0 : 8)
        }
    }

    @ViewBuilder
    private func feedAutoplayVideo(url: URL) -> some View {
        // Feed: only Archive CDN needs MatteryaHubPlayer. R2 hubs use light AV path —
        // mounting the hub UIKit player on every cell froze scroll.
        let useArchivePath = ArchiveVideoPlayback.isArchiveURL(url)
        // Prefer usable Frame 0 / LongForm YouTube — feed thumb_url is often expired (403).
        let posterCandidates: [URL?] = [
            Frame0PosterCache.url(for: post.id),
            MediaURLResolver.r2LongformYouTubePosterURL(for: post),
            MediaURLResolver.posterURL(for: post),
            post.sharedPost.flatMap { MediaURLResolver.posterURL(for: $0.asCountryPost) },
            post.sharedPost.flatMap { MediaURLResolver.r2LongformYouTubePosterURL(for: $0.asCountryPost) },
        ]
        let poster: URL? = {
            for candidate in posterCandidates {
                guard let url = candidate, MediaURLResolver.isUsablePosterURL(url) else { continue }
                return url
            }
            return nil
        }()
        let isHubFilm = PlayPlatformBridge.isHubFeedCardVideo(post)
            || PlayPlatformBridge.isHubCatalogContent(post)
            || isHubOriginShareCard
        ZStack {
            Color.black
            if let poster {
                CachedAsyncImage(
                    url: poster,
                    maxPixelSize: 480,
                    contentMode: isHubFilm ? .fit : .fill,
                    placeholder: AnyView(Color.black)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
            } else {
                // No usable thumb — pack-path Frame 0 only (no full-video download).
                FrameZeroFallbackPoster(
                    postID: post.id,
                    videoURL: url,
                    fillsFrame: !isHubFilm,
                    allowClientExtract: false,
                    seedPosterURL: Frame0PosterCache.url(for: post.id)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
            InFrameVideoPlayer(
                url: url,
                posterURL: poster,
                placement: nil,
                countryCode: post.countryCode,
                contentCountryCode: post.countryCode,
                postID: post.id,
                muted: false,
                loops: true,
                preferArchivePlayer: useArchivePath,
                showsControls: true,
                // Hubs shares: fit (no zoom-crop). Sparks: fill the card.
                fillsFrame: !isHubFilm,
                bottomChromeReserve: 0,
                autoplaySurface: autoplaySurface,
                tapToRevealControls: isHubFilm,
                // Hubs on feed: FS → continuous landscape player (same buffer, no remount lag).
                allowsFullscreen: isHubFilm,
                // CC on Home-feed Hubs (light R2 path + archive path). Never Sparks.
                allowsCaptions: isHubFilm,
                onFullscreenRequest: isHubFilm ? {
                    appState.startHubPlayback(post, expanded: true)
                    appState.requestHubFullscreen()
                } : nil,
                onViewed: { Task { await PostsService.shared.recordView(post) } }
            )
        }
        .background(Color.black)
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

        }
        .padding(.horizontal, horizontalGutter)
        .padding(.bottom, 14)
    }

    private var mediaPlaceholder: some View {
        // Videos: black like Sparks (never cream/paper flash). Photos keep muted canvas.
        Rectangle()
            .fill(post.hasVideo ? Color.black : Theme.canvasMuted)
            .overlay {
                Image(systemName: post.hasVideo ? "video" : "photo")
                    .foregroundStyle(post.hasVideo ? Color.white.opacity(0.35) : Theme.inkMuted)
            }
    }

    private var feedVideoPoster: some View {
        Group {
            if usesYouTubeVideoFrame {
                // Prefer remote poster; allow Frame 0 extract when missing (Sparks parity).
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
                    // Never extract while scrolling — butter-smooth 09 (posters only).
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
        } else if !post.feedImageURLs.isEmpty {
            openPhotoLightbox(at: 0)
        } else {
            onOpenPost()
        }
    }

    private func openPhotoLightbox(at index: Int) {
        guard !post.feedImageURLs.isEmpty else {
            onOpenPost()
            return
        }
        lightboxStartIndex = min(max(0, index), post.feedImageURLs.count - 1)
        showPhotoLightbox = true
    }

    private func openReel() {
        // Prefer Feed/strip callback (passes seedPosts) — bare open forces cold catalog ranking.
        if let onOpenReel {
            onOpenReel()
            return
        }
        // Always endless Sparks from all over Matterya (up/down), never a single-clip dead end.
        let start = sparkCardPresentationPost
        if let url = start.playableVideoURL ?? MediaURLResolver.videoURL(for: start) {
            SparkWarmPool.shared.warmSingle(postID: start.id, url: url, deep: true)
        }
        appState.openGlobalSparksViewer(startingPost: start)
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

    /// Origin channel / creator under a re-share — Hubs channel when stamped as one, else profile.
    private func openOriginSource(_ source: OriginSource) {
        let id = source.authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = source.username?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            if let username, !username.isEmpty {
                appState.openPlayChannel(username: username)
            }
            return
        }
        if id.hasPrefix("hub_")
            || HubVideoSeedService.isArchiveChannelAuthor(id)
            || isHubOriginShareCard
            || PlayPlatformBridge.isHubOriginShare(post) {
            appState.openPlayChannel(authorID: id, username: username)
            return
        }
        appState.openPublicProfile(username: username, userID: id)
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

/// Outer card clip — skipped for Sparks/Hubs feed video so actions stay under the film.
private struct FeedCardClipModifier: ViewModifier {
    let shape: UnevenRoundedRectangle
    let clipWholeCard: Bool

    func body(content: Content) -> some View {
        if clipWholeCard {
            content
                .clipShape(shape)
                .clipped()
        } else {
            content
        }
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
    /// False while pinching a photo so scaleEffect can grow past the box.
    var clipsContent: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        let aspect = FacebookMediaLayout.clampedAspect(photoAspect)
        if isVideo {
            let height = isHubCompact
                ? FacebookMediaLayout.hubFeedVideoHeight()
                : FacebookMediaLayout.dominantFeedVideoHeight()
            let sized = content
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: height)
                .contentShape(Rectangle())
            if clipsContent {
                sized.clipped()
            } else {
                sized
            }
        } else {
            let sized = content
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(aspect, contentMode: .fit)
                .frame(
                    minWidth: 0,
                    maxWidth: .infinity,
                    maxHeight: usesYouTubeFrame
                        ? FacebookMediaLayout.maxFeedMediaHeight
                        : FacebookMediaLayout.maxFeedMediaHeight
                )
                .contentShape(Rectangle())
            if clipsContent {
                sized.clipped()
            } else {
                sized
            }
        }
    }
}

private extension String {
    var nilIfWhitespace: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
