import SwiftUI

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
            if let space = store.currentSpace, space.slug == slug {
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
        .confirmationDialog("Report Space", isPresented: $showReport, titleVisibility: .visible) {
            Button("Harassment", role: .destructive) { Task { await report("harassment") } }
            Button("Spam", role: .destructive) { Task { await report("spam") } }
            Button("Illegal or harmful", role: .destructive) { Task { await report("illegal") } }
            Button("Cancel", role: .cancel) {}
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

                    if space.isJoined == true {
                        Button {
                            Task { await store.leaveCurrentSpace() }
                        } label: {
                            spaceChip("Leave", systemImage: "rectangle.portrait.and.arrow.right", style: .quiet)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Task { await store.joinCurrentSpace() }
                        } label: {
                            spaceChip("Join", systemImage: "person.badge.plus", style: .outline)
                        }
                        .buttonStyle(.plain)
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

    @ViewBuilder
    private var postsSection: some View {
        if store.spacePosts.isEmpty {
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
                        onToggleLike: {
                            Task {
                                let next = (post.myVote ?? 0) > 0 ? 0 : 1
                                await store.vote(post: post, value: next)
                            }
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

/// Full-width Reddit-scale post card — Matterya paper/serif, no upvote chrome.
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
    /// Toggles like (heart) on this post.
    var onToggleLike: (() -> Void)? = nil
    /// Opens the full post (See more / comments / media). Trailing closure target.
    var onOpenPost: (() -> Void)? = nil

    /// Longer feed preview; full body lives on the thread.
    private static let feedLineLimit = 12
    @Environment(AppState.self) private var appState
    @State private var videoMuted = false
    @State private var showFeedVideoPlayer = false
    @State private var showReport = false
    private var store: AnonymousStore { AnonymousStore.shared }

    private var bodyText: String {
        post.displayBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsSeeMore: Bool {
        guard style == .feed, onOpenPost != nil else { return false }
        // Rough truncation signal — enough that 12 lines likely clips.
        return bodyText.count > 280 || bodyText.split(whereSeparator: \.isNewline).count > 8
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

    var body: some View {
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
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(space)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
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
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open @\(post.authorUsername)")
                }
                Spacer(minLength: 4)
                Text(RelativeTime.format(post.createdAt))
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                postOverflowMenu
            }

            if let title = post.displayTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !bodyText.isEmpty {
                MatteryaRichText(
                    text: bodyText,
                    font: .body,
                    color: Theme.inkSecondary,
                    lineLimit: style == .thread ? nil : Self.feedLineLimit
                )
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

            mediaBlock
                .onAppear {
                    // Prefetch first page so opening the post never shows a comments spinner.
                    AnonymousCommentsWarmCache.shared.warm(post.id)
                }

            // Like · comments → full post thread (not an in-feed expand).
            HStack(spacing: 16) {
                Button {
                    onToggleLike?()
                } label: {
                    let liked = (post.myVote ?? 0) > 0
                    Label(
                        "\((post.score ?? 0))",
                        systemImage: liked ? "heart.fill" : "heart"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(liked ? Theme.danger : Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .disabled(onToggleLike == nil)
                .accessibilityLabel((post.myVote ?? 0) > 0 ? "Unlike" : "Like")

                Button {
                    onOpenPost?()
                } label: {
                    Label("\(post.commentCount ?? 0) comments", systemImage: "bubble.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .disabled(onOpenPost == nil)

                Spacer(minLength: 0)
                if post.hasImage, post.mediaURLValue != nil {
                    Label("Photo", systemImage: "photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                } else if post.hasVideo {
                    Label("Video", systemImage: "play.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            if style == .feed {
                Theme.divider.frame(height: 0.5)
            }
        }
        .confirmationDialog("Report post", isPresented: $showReport, titleVisibility: .visible) {
            Button("Harassment", role: .destructive) { Task { await reportPost("harassment") } }
            Button("Spam", role: .destructive) { Task { await reportPost("spam") } }
            Button("Doxxing / identity", role: .destructive) { Task { await reportPost("doxxing") } }
            Button("Cancel", role: .cancel) {}
        }
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
            // Feed-list decode budget — 1080px bitmaps made Masquerade scroll laggy.
            let listPx: CGFloat = style == .thread ? 900 : 540
            let image = CachedAsyncImage(
                url: url,
                maxPixelSize: listPx,
                contentMode: .fit,
                placeholder: AnyView(
                    Rectangle()
                        .fill(Theme.canvasMuted)
                        .frame(height: 180)
                        .overlay {
                            ProgressView()
                                .tint(Theme.inkMuted)
                        }
                ),
                onLoadFailed: { _ in
                    // HTML-as-jpg scrape poison — drop the whole post; body without photo is empty context.
                    store.removeBrokenPhotoPost(id: post.id)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(maxHeight: style == .thread ? 440 : 360)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.border.opacity(0.7), lineWidth: 0.5)
            )

            if let onOpenPost, style == .feed {
                Button(action: onOpenPost) { image }
                    .buttonStyle(.plain)
            } else {
                image
            }
        } else if post.hasVideo, let url = post.mediaURLValue {
            let posterH: CGFloat = style == .thread ? 280 : 240
            if style == .thread {
                // Real AVPlayer — do NOT pass anonymous post id (Hubs R2PlaybackResolver
                // only understands CountryPost ids and would break signed Masquerade URLs).
                // Tall unclipped stage + chrome reserves so mute/speed/timeline stay visible.
                MatteryaHubPlayerView(
                    url: url,
                    posterURL: post.thumbURLValue,
                    isActive: true,
                    postID: nil,
                    showsControls: true,
                    loops: false,
                    fillsFrame: false,
                    topChromeReserve: 8,
                    bottomChromeReserve: 14,
                    isMuted: $videoMuted,
                    allowsFullscreen: true
                )
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.border.opacity(0.7), lineWidth: 0.5)
                )
            } else {
                let poster = post.thumbURLValue
                let videoPoster = ZStack {
                    if let poster {
                        CachedAsyncImage(
                            url: poster,
                            maxPixelSize: 540,
                            contentMode: .fill,
                            placeholder: AnyView(Color.black)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: posterH)
                        .clipped()
                    } else {
                        Color.black.frame(height: posterH)
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: posterH)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.border.opacity(0.7), lineWidth: 0.5)
                )

                Button {
                    showFeedVideoPlayer = true
                } label: {
                    videoPoster
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
            MatteryaHubPlayerView(
                url: url,
                posterURL: posterURL,
                isActive: true,
                postID: nil,
                showsControls: true,
                loops: false,
                fillsFrame: false,
                topChromeReserve: 8,
                bottomChromeReserve: 12,
                isMuted: $muted,
                allowsFullscreen: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 4)

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
    }
}
