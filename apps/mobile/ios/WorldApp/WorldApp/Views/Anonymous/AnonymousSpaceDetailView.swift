import SwiftUI
import UIKit

struct AnonymousSpaceDetailView: View {
    let slug: String
    @Environment(AppState.self) private var appState
    @State private var store = AnonymousStore.shared
    @State private var showComposer = false
    @State private var showModPanel = false
    @State private var showReport = false
    @State private var isPreparingComposer = false

    var body: some View {
        Group {
            if let space = store.currentSpace, spaceMatches(space) {
                spaceBody(space)
            } else if store.spacePostsLoading {
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AnonymousEmptyState(
                    title: MatteryaCopy.anonymousSpaceMissing,
                    message: MatteryaCopy.anonymousSpaceMissingBody,
                    systemImage: "questionmark.folder"
                )
            }
        }
        // Back + title live on MasqueradePushChrome; New post stays in the space actions body.
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.ink)
        .task {
            await store.openSpace(slug: slug)
        }
        .sheet(isPresented: $showComposer) {
            if let space = store.currentSpace {
                AnonymousComposerView(spaceId: space.id, spaceTitle: space.title)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $showModPanel) {
            AnonymousModPanelView(spaceTitle: store.currentSpace?.title ?? slug)
        }
        .matteryaReportDialog("Report Space", isPresented: $showReport) { reason in
            Task { await report(MatteryaReportCategories.slug(forLabel: reason)) }
        }
    }

    @ViewBuilder
    private func spaceBody(_ space: AnonymousSpace) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    header(space)
                    rules(space)
                    actions(space)
                    Text("Posts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(Theme.pagePadding)

                postsSection
            }
        }
        .background(Theme.canvas)
        .refreshable { await store.openSpace(slug: slug) }
    }

    private func header(_ space: AnonymousSpace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("About this space")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if space.isPaid {
                    Text("Paid")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.matteDeep, in: Capsule())
                }
            }
            if let description = space.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
            }
            HStack(spacing: 12) {
                if let count = space.memberCount {
                    Text("\(count.formatted()) members")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                if let posts = space.postCount {
                    Text("\(posts.formatted()) posts")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                if let owner = space.ownerUsername {
                    Button {
                        store.pushProfile(username: owner)
                    } label: {
                        Text("Owner @\(owner)")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open @\(owner)")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func rules(_ space: AnonymousSpace) -> some View {
        if let rules = space.rules, !rules.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rules")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                ForEach(Array(rules.enumerated()), id: \.offset) { idx, rule in
                    Text("\(idx + 1). \(rule)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
    }

    private func actions(_ space: AnonymousSpace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if space.isPaid {
                Text(MatteryaCopy.anonymousPaidJoinDisabled)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                spaceChip("Join soon", systemImage: "lock.fill", style: .quiet)
                    .opacity(0.5)
            } else {
                HStack(spacing: 8) {
                    Button {
                        Task { await openComposer() }
                    } label: {
                        spaceChip(
                            isPreparingComposer ? "Joining…" : "New post",
                            systemImage: "square.and.pencil",
                            style: .primary
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPreparingComposer)

                    let joined = store.isJoined(space)
                    let busy = store.isMembershipBusy(space.id)
                    if joined {
                        Button {
                            Task { await store.leaveCurrentSpace() }
                        } label: {
                            spaceChip(
                                busy ? "Leaving…" : "Leave",
                                systemImage: "rectangle.portrait.and.arrow.right",
                                style: .quiet
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    } else {
                        Button {
                            Task { await store.joinCurrentSpace() }
                        } label: {
                            spaceChip(
                                busy ? "Joining…" : "Join",
                                systemImage: "person.badge.plus",
                                style: .outline
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }

                    Spacer(minLength: 4)

                    if space.isOwner == true || space.isModerator == true {
                        Button { showModPanel = true } label: {
                            spaceChip("Mod", systemImage: "shield", style: .quiet)
                        }
                        .buttonStyle(.plain)
                    }

                    Button { showReport = true } label: {
                        spaceChip("Report", systemImage: "flag", style: .subtle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private enum SpaceChipStyle {
        case primary, outline, quiet, subtle
    }

    /// Compact paper chips — fit the action row without full-width slabs.
    private func spaceChip(
        _ title: String,
        systemImage: String,
        style: SpaceChipStyle
    ) -> some View {
        let fg: Color = {
            switch style {
            case .primary: return Theme.surface
            case .subtle: return Theme.danger.opacity(0.85)
            case .outline, .quiet: return Theme.ink
            }
        }()
        let fill: Color = {
            switch style {
            case .primary: return Theme.ink
            case .quiet: return Theme.matteDeep.opacity(0.9)
            case .outline, .subtle: return Theme.surface
            }
        }()
        return Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(fill))
            .overlay {
                if style == .outline || style == .subtle {
                    Capsule(style: .continuous)
                        .stroke(Theme.border.opacity(style == .outline ? 1 : 0.7), lineWidth: style == .outline ? 0.8 : 0.5)
                }
            }
    }

    private func spaceMatches(_ space: AnonymousSpace) -> Bool {
        let needle = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return space.slug == slug || space.normalizedSlug == needle
    }

    @ViewBuilder
    private var postsSection: some View {
        if store.spacePostsLoading && store.spacePosts.isEmpty {
            ProgressView()
                .tint(Theme.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else if store.spacePosts.isEmpty {
            Text(MatteryaCopy.anonymousSpaceEmptyPosts)
                .font(.subheadline)
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(store.spacePosts.enumerated()), id: \.element.id) { index, post in
                    AnonymousPostCard(
                        post: post,
                        style: .feed,
                        onOpenSpace: {
                            // Already inside this Space — keep chip inert / no-op push.
                            if let slug = post.spaceSlug, !slug.isEmpty,
                               slug != store.currentSpace?.slug {
                                store.pushSpace(slug: slug)
                            }
                        },
                        onVote: { value in
                            Task { await store.vote(post: post, value: value) }
                        }
                    ) {
                        store.pushPost(post)
                    }
                    .onAppear {
                        AnonymousCommentsWarmCache.shared.warm(post.id)
                        if index >= store.spacePosts.count - 6 {
                            Task { await store.loadMoreSpacePosts() }
                        }
                    }
                }
                if store.spacePostsLoadingMore {
                    ProgressView()
                        .tint(Theme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    private func report(_ reason: String) async {
        guard let id = store.currentSpace?.id else { return }
        await store.report(targetType: "space", targetId: id, reason: reason)
        appState.showToast("Report submitted.", style: .info)
    }

    /// Join when needed, then open the composer (API requires membership to POST).
    private func openComposer() async {
        guard let space = store.currentSpace, space.slug == slug else { return }
        if space.isPaid {
            appState.showToast(AnonymousError.paidDisabled.errorDescription ?? "Paid Spaces coming soon.", style: .info)
            return
        }
        isPreparingComposer = true
        defer { isPreparingComposer = false }
        let ok = await store.ensureJoined(space)
        if ok {
            showComposer = true
        } else if let err = store.consumeError() {
            appState.showToast(err, style: .error)
        }
    }
}

/// Full-width Reddit-scale post card — Matterya paper/serif + heart engagement.
struct AnonymousPostCard: View {
    enum Style {
        /// Feed / Space list — full-bleed with hairline separator.
        case feed
        /// Thread hero — same scale, no bottom rule (comments follow).
        case thread
    }

    let post: AnonymousPost
    var style: Style = .feed
    /// Opens the Space from the feed meta chip.
    var onOpenSpace: (() -> Void)? = nil
    /// Like (1) / dislike (-1) / clear (0). Tap active side again to clear.
    var onVote: ((Int) -> Void)? = nil
    /// Opens the full post (See more / comments / media). Trailing closure target.
    var onOpenPost: (() -> Void)? = nil

    /// Short tease on feed — intrigue pulls the tap into the thread.
    private static let feedLineLimit = 6
    @Environment(AppState.self) private var appState
    @State private var videoMuted = false
    @State private var showFeedVideoPlayer = false
    @State private var showReport = false
    @State private var teasedComment: AnonymousComment?
    @State private var isPhotoPinching = false
    @State private var showPhotoLightbox = false
    /// Decoded bitmap size — sizes the media frame to the photo’s real aspect (no letterbox gaps).
    @State private var photoPixelSize: CGSize?
    private var store: AnonymousStore { AnonymousStore.shared }

    /// Width/height of the loaded photo; square until decode so the placeholder isn’t a tall empty box.
    private var photoAspect: CGFloat {
        guard let px = photoPixelSize, px.width > 1, px.height > 1 else {
            return FacebookMediaLayout.photoSquareAspect
        }
        let raw = px.width / px.height
        guard raw.isFinite, raw > 0.05 else { return FacebookMediaLayout.photoSquareAspect }
        // Allow tall memes (~1:3) and wide shots; avoid zero/infinite from bad metadata.
        return min(max(raw, 0.33), 2.5)
    }

    private var bodyText: String {
        post.displayBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsSeeMore: Bool {
        guard style == .feed, onOpenPost != nil else { return false }
        return bodyText.count > 160 || bodyText.split(whereSeparator: \.isNewline).count > 4
    }

    private var commentCount: Int { max(0, post.commentCount ?? 0) }

    private var commentsLabel: String {
        if commentCount == 0 { return "Add a comment" }
        if commentCount == 1 { return "1 comment" }
        return "\(commentCount) comments"
    }

    private var spaceLabel: String? {
        let title = post.spaceTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        let slug = post.spaceSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return slug.isEmpty ? nil : slug
    }

    private var isOfficialMatteryaAuthor: Bool {
        post.authorUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "matterya"
    }

    private var myVote: Int { post.myVote ?? 0 }

    /// 👍 score 👎 — SF Symbol thumbs in paper/ink theme (like = upvote, dislike = downvote).
    private var likeDislikeCluster: some View {
        let liked = myVote > 0
        let disliked = myVote < 0
        return HStack(spacing: 0) {
            Button {
                onVote?(liked ? 0 : 1)
            } label: {
                MatteryaThumbIcon(
                    up: true,
                    filled: liked,
                    size: 18,
                    color: liked ? Theme.ink : Theme.inkMuted
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liked ? "Remove like" : "Like")

            Text("\((post.score ?? 0))")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle((liked || disliked) ? Theme.ink : Theme.inkMuted)
                .padding(.horizontal, 2)
                .accessibilityLabel("Score \((post.score ?? 0))")

            Button {
                onVote?(disliked ? 0 : -1)
            } label: {
                MatteryaThumbIcon(
                    up: false,
                    filled: disliked,
                    size: 18,
                    color: disliked ? Theme.ink : Theme.inkMuted
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(disliked ? "Remove dislike" : "Dislike")
        }
        .background(Theme.canvasMuted, in: Capsule())
        .disabled(onVote == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Meta · title · body — padded. Media is full-bleed width-fit (never side-crop).
            VStack(alignment: .leading, spacing: 12) {
                // Meta row — community · author · time · ⋯
                // Only official Matterya keeps an avatar in Masquerade; everyone else is @username.
                HStack(spacing: 6) {
                    if isOfficialMatteryaAuthor {
                        AvatarView(url: nil, seed: "matterya", size: 22)
                    }
                    if let space = spaceLabel {
                        if let onOpenSpace {
                            Button(action: onOpenSpace) {
                                Text(space)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .buttonStyle(.plain)
                            .layoutPriority(1)
                        } else {
                            Text(space)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                        }
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    if isOfficialMatteryaAuthor {
                        Text("Matterya")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        MatteryaVerifiedBadge(size: 13)
                    } else {
                        Button {
                            store.pushProfile(username: post.authorUsername)
                        } label: {
                            Text("@\(post.authorUsername)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                        .layoutPriority(1)
                        .accessibilityLabel("Open @\(post.authorUsername)")
                    }
                    Spacer(minLength: 4)
                    Text(RelativeTime.format(post.createdAt))
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .layoutPriority(2)
                    postOverflowMenu
                }
                .frame(minWidth: 0, maxWidth: .infinity)

                if let title = post.displayTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if post.isFlagged {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Flagged")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Flagged for review")
                }

                if !bodyText.isEmpty {
                    MatteryaRichText(
                        text: bodyText,
                        font: .body,
                        color: Theme.inkSecondary,
                        lineLimit: style == .thread ? nil : Self.feedLineLimit
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                    if showsSeeMore {
                        Button {
                            onOpenPost?()
                        } label: {
                            Text("See more")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, -4)
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            mediaBlock
                .padding(.horizontal, style == .feed ? 0 : Theme.pagePadding)
                .frame(minWidth: 0, maxWidth: .infinity)
                .onAppear {
                    // Tease only — feed list owns comment prefetch (keeps scroll light).
                    refreshCommentTease()
                }

            // Matterya thumbs · score · comments — like / dislike (upvote / downvote).
            HStack(spacing: 14) {
                likeDislikeCluster

                Button {
                    onOpenPost?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 15, weight: .semibold))
                        Text(commentsLabel)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(commentCount > 0 ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.canvasMuted, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(onOpenPost == nil)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.pagePadding)

            if style == .feed, let tease = teasedComment {
                Button {
                    onOpenPost?()
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Theme.ink.opacity(0.18))
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(tease.authorUsername)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                            Text(tease.displayBody)
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.canvasMuted.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, -2)
            }
        }
        .padding(.vertical, 16)
        // LazyVStack can propose unbounded width — without minWidth:0 the card
        // grows past the screen and a parent clip cuts text + photos from the sides.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .zIndex(isPhotoPinching ? 80 : 0)
        .fullScreenCover(isPresented: $showPhotoLightbox) {
            if let url = post.mediaURLValue {
                MatteryaPhotoLightbox(urls: [url], startIndex: 0) {
                    showPhotoLightbox = false
                }
            }
        }
        .overlay(alignment: .bottom) {
            if style == .feed {
                Theme.divider.frame(height: 0.5)
            }
        }
        .matteryaReportDialog("Report post", isPresented: $showReport) { reason in
            Task { await reportPost(MatteryaReportCategories.slug(forLabel: reason)) }
        }
    }

    private func refreshCommentTease() {
        guard style == .feed, commentCount > 0 else {
            teasedComment = nil
            return
        }
        guard let warm = AnonymousCommentsWarmCache.shared.cached(post.id), !warm.isEmpty else {
            teasedComment = nil
            // Warm may still be in flight — peek again shortly.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                if let later = AnonymousCommentsWarmCache.shared.cached(post.id)?.first {
                    teasedComment = later
                }
            }
            return
        }
        teasedComment = warm.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) ?? warm.first
    }

    private var postOverflowMenu: some View {
        Menu {
            Button(role: .destructive) {
                showReport = true
            } label: {
                Label("Report", systemImage: "flag")
            }
            Button(role: .destructive) {
                Task { await blockAuthor() }
            } label: {
                Label("Block author", systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post options")
    }

    private func reportPost(_ reason: String) async {
        await store.report(targetType: "post", targetId: post.id, reason: reason)
        appState.showToast("Report submitted.", style: .info)
    }

    private func blockAuthor() async {
        let ok = await store.block(profileId: post.authorProfileId)
        if ok {
            appState.showToast("Blocked @\(post.authorUsername)", style: .info)
        } else if let msg = store.consumeError() {
            appState.showToast(msg, style: .error)
        } else {
            appState.showToast("Couldn’t block this author.", style: .error)
        }
    }

    @ViewBuilder
    private var mediaBlock: some View {
        if post.hasImage, let url = post.mediaURLValue {
            // Full-width box sized to the photo’s real aspect; photo fills that box.
            // Clear+overlay+clipped — never a paper Color behind the bitmap (that was
            // the white letterbox/pillarbox). Tall memes grow the card (Reddit-style).
            // Feed decode stays light (540) — 720 was hitching Masquerade For you scroll.
            let listPx: CGFloat = style == .thread ? 540 : 420
            let corner: CGFloat = style == .feed ? 0 : 10
            let aspect = photoAspect
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    FeedPinchZoomPhoto(
                        url: url,
                        maxPixelSize: listPx,
                        contentMode: .fill,
                        // Static muted tile — never an infinite spinner on failed/slow R2.
                        placeholder: AnyView(Theme.canvasMuted),
                        // Feed must defer decode mid-fling; thread can stay snappy.
                        urgent: style == .thread,
                        onZoomingChanged: { zooming in
                            isPhotoPinching = zooming
                        },
                        onTap: {
                            showPhotoLightbox = true
                        },
                        onImageSize: { size in
                            guard size.width > 1, size.height > 1 else { return }
                            guard photoPixelSize != size else { return }
                            var tx = Transaction()
                            tx.disablesAnimations = true
                            withTransaction(tx) { photoPixelSize = size }
                        }
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: isPhotoPinching ? 0 : corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Theme.border.opacity(style == .feed ? 0 : 0.7), lineWidth: 0.5)
                )
                .onChange(of: post.id) { _, _ in
                    photoPixelSize = nil
                }
                .onChange(of: url.absoluteString) { _, _ in
                    photoPixelSize = nil
                }
        } else if post.hasVideo, let url = post.mediaURLValue {
            let posterH: CGFloat = style == .thread ? 280 : 240
            if style == .thread {
                // Real AVPlayer — do NOT pass anonymous post id (Hubs R2PlaybackResolver
                // only understands CountryPost ids and would break signed Masquerade URLs).
                // Tall unclipped stage + chrome reserves so mute/speed/timeline stay visible.
                FeedPinchZoomContainer(
                    onZoomingChanged: { zooming in
                        isPhotoPinching = zooming
                    }
                ) {
                    MatteryaHubPlayerView(
                        url: url,
                        posterURL: post.thumbURLValue,
                        isActive: true,
                        postID: nil,
                        showsControls: true,
                        loops: true,
                        fillsFrame: false,
                        topChromeReserve: 8,
                        bottomChromeReserve: 14,
                        isMuted: $videoMuted,
                        allowsFullscreen: true
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: isPhotoPinching ? 0 : 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.border.opacity(0.7), lineWidth: 0.5)
                )
                .onAppear {
                    videoMuted = false
                    MediaPlaybackCoordinator.shared.ensurePlaybackAudioSession()
                    // Re-assert unmute after the player mounts — silence storms / warm-pool
                    // handoffs can leave AVPlayer muted while the chrome still shows speaker.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        videoMuted = false
                        MediaPlaybackCoordinator.shared.ensurePlaybackAudioSession()
                    }
                }
                .onDisappear {
                    MediaPlaybackCoordinator.shared.clearForegroundWatchProtection()
                }
            } else {
                // Outside card: client-extracted first frame (Masquerade-only).
                Button {
                    showFeedVideoPlayer = true
                } label: {
                    MasqueradeVideoPoster(
                        postID: post.id,
                        videoURL: url,
                        remotePosterURL: post.thumbURLValue,
                        height: posterH
                    )
                }
                .buttonStyle(.plain)
                .fullScreenCover(isPresented: $showFeedVideoPlayer) {
                    MasqueradeVideoPlayerCover(
                        url: url,
                        posterURL: post.thumbURLValue
                    )
                }
            }
        } else if post.hasVideo {
            // Video typed but no playable URL yet — keep poster affordance.
            let posterH: CGFloat = style == .thread ? 280 : 240
            ZStack {
                Color.black.frame(height: posterH)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: posterH)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

}

/// Feed / list poster for Masquerade videos — paints the literal first frame.
/// Uses a remote thumb only as a fast placeholder while AV extracts frame 0.
private struct MasqueradeVideoPoster: View {
    let postID: String
    let videoURL: URL
    var remotePosterURL: URL? = nil
    var height: CGFloat = 240

    @State private var firstFrame: UIImage?
    @State private var remoteFailed = false

    var body: some View {
        ZStack {
            Color.black

            if let firstFrame {
                Image(uiImage: firstFrame)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
            } else if let remote = remotePosterURL, !remoteFailed {
                CachedAsyncImage(
                    url: remote,
                    maxPixelSize: 420,
                    contentMode: .fill,
                    placeholder: AnyView(Color.black),
                    urgent: false,
                    onLoadFailed: { _ in remoteFailed = true }
                )
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border.opacity(0.7), lineWidth: 0.5)
        )
        .task(id: "\(postID)|\(videoURL.absoluteString)") {
            // Prefer remote thumb — opening every R2 MP4 for frame-0 crushed Masquerade.
            if remotePosterURL != nil, !remoteFailed { return }
            for _ in 0..<8 {
                if !ScrollBudget.isFlinging { break }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard !Task.isCancelled else { return }
            // Settle briefly so fling past cards never starts AV extract.
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, !ScrollBudget.isFlinging else { return }
            if let image = await VideoFrameCache.shared.image(
                for: postID,
                videoURL: videoURL,
                atFirstFrame: true
            ) {
                firstFrame = image
            }
        }
    }
}

/// Full-screen Masquerade video — same archive player chrome as Hubs, signed R2 MP4.
private struct MasqueradeVideoPlayerCover: View {
    let url: URL
    var posterURL: URL? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            // Keep player inside the safe area so top chrome + timeline are not
            // cropped by the notch / home indicator (ignoresSafeArea was clipping both).
            FeedPinchZoomContainer {
                MatteryaHubPlayerView(
                    url: url,
                    posterURL: posterURL,
                    isActive: true,
                    postID: nil,
                    showsControls: true,
                    loops: true,
                    fillsFrame: false,
                    topChromeReserve: 8,
                    bottomChromeReserve: 12,
                    isMuted: $muted,
                    allowsFullscreen: true
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .onAppear {
                // User tapped play — always start with sound (never inherit a stale mute).
                muted = false
                MediaPlaybackCoordinator.shared.ensurePlaybackAudioSession()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    muted = false
                    MediaPlaybackCoordinator.shared.ensurePlaybackAudioSession()
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.ink.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .safeAreaPadding(.top, 12)
            .accessibilityLabel("Close")
        }
        .statusBarHidden(true)
        .onDisappear {
            MediaPlaybackCoordinator.shared.clearForegroundWatchProtection()
        }
    }
}
