import AVFoundation
import SwiftUI

// MARK: - Shared content card in chat (minimal)

/// Quiet link card: thumbnail → title → author. Whole card opens the content.
/// No logos, brand chips, CTAs, or decorative rails.
struct ChatShareCard: View {
    @Environment(AppState.self) private var appState

    let share: Message.ShareInfo
    var isMine: Bool = false
    var onOpen: (() -> Void)? = nil

    @State private var resolved: Message.ShareInfo?

    private let cardWidth: CGFloat = 228

    private var effective: Message.ShareInfo { resolved ?? share }

    private var isSpark: Bool { ChatShareRouting.isSpark(effective) }

    /// Sparks: slightly taller. Everything else: 16:9.
    private var mediaHeight: CGFloat {
        isSpark ? cardWidth * 1.15 : cardWidth * 9 / 16
    }

    private var headline: String? {
        if let t = effective.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return ContentSanitizer.clean(t)
        }
        if let b = effective.bodyText?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
            let cleaned = b
                .replacingOccurrences(of: "__spark__|", with: "")
                .replacingOccurrences(of: "__reel__|", with: "")
                .replacingOccurrences(of: "__spark_share__|", with: "")
                .replacingOccurrences(of: "__hub_origin__|", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty { return nil }
            return ContentSanitizer.clean(String(cleaned.prefix(100)))
        }
        return nil
    }

    private var authorLine: String? {
        let name = effective.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private var accessibilityTitle: String {
        headline ?? authorLine ?? (effective.isVideo ? "Video" : "Shared post")
    }

    var body: some View {
        Button(action: handleOpen) {
            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                if !effective.note.isEmpty {
                    noteBubble
                }
                linkCard
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint("Opens shared content")
        .task(id: share.postID) {
            await hydrateIfNeeded()
        }
    }

    // MARK: Note (optional text above the card)

    private var noteBubble: some View {
        Text(effective.note)
            .font(.subheadline)
            .foregroundStyle(isMine ? Theme.paper : Theme.ink)
            .multilineTextAlignment(isMine ? .trailing : .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isMine ? Theme.accentBright : Theme.surface)
            )
            .frame(maxWidth: cardWidth + 12, alignment: isMine ? .trailing : .leading)
    }

    // MARK: Card — media + text only

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            mediaStage

            VStack(alignment: .leading, spacing: 3) {
                if let headline {
                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if let authorLine {
                    Text(authorLine)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: cardWidth, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border.opacity(0.45), lineWidth: 0.5)
        )
    }

    // MARK: Media

    private var mediaStage: some View {
        ZStack {
            Group {
                if isSpark {
                    // Sparks: always use VideoThumbnailView — real poster when present,
                    // otherwise extract a frame from the mp4 (most R2 sparks have no thumb).
                    VideoThumbnailView(
                        post: effective.asCountryPost,
                        maxPixelSize: 420,
                        contentMode: .fill,
                        showsPlayIcon: false,
                        extractFrameIfNeeded: true,
                        placeholder: AnyView(mediaPlaceholder)
                    )
                } else if let poster = effective.posterImageURL {
                    CachedAsyncImage(
                        url: poster,
                        maxPixelSize: 420,
                        contentMode: .fill,
                        placeholder: AnyView(mediaPlaceholder)
                    )
                } else if effective.playableVideoURL != nil {
                    VideoThumbnailView(
                        post: effective.asCountryPost,
                        maxPixelSize: 420,
                        contentMode: .fill,
                        showsPlayIcon: false,
                        extractFrameIfNeeded: true,
                        placeholder: AnyView(mediaPlaceholder)
                    )
                } else {
                    mediaPlaceholder
                }
            }
            .frame(width: cardWidth, height: mediaHeight)
            .clipped()

            // Play mark only for Hubs long-form shares — never on Sparks (thumbnail is enough).
            if !isSpark, effective.isHubContent || effective.kind == .hub, effective.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(9)
                    .background(Circle().fill(Color.black.opacity(0.42)))
                    .offset(x: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: cardWidth, height: mediaHeight)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12,
                style: .continuous
            )
        )
    }

    private var mediaPlaceholder: some View {
        Rectangle()
            .fill(Theme.canvasMuted)
    }

    private func handleOpen() {
        if let onOpen {
            onOpen()
            return
        }
        ChatShareRouting.open(effective, appState: appState)
    }

    private func hydrateIfNeeded() async {
        // Need a real image poster and/or a playable media URL for frame extract.
        let hasImagePoster = effective.posterImageURL != nil
        let hasVideo = effective.playableVideoURL != nil
        if hasImagePoster, hasVideo || !isSpark { return }
        guard !share.postID.isEmpty || hasVideo else { return }

        if !share.postID.isEmpty {
            if let post = try? await PostsService.shared.getPostByID(share.postID) {
                applyResolved(from: post)
                if effective.posterImageURL != nil, effective.playableVideoURL != nil { return }
            }
            if let seed = await HubVideoSeedService.shared.post(id: share.postID) {
                applyResolved(from: seed)
                if effective.posterImageURL != nil, effective.playableVideoURL != nil { return }
            }
            // Origin id on spark-share stamps (feed re-share → original Spark).
            let bodyBlob = share.bodyText ?? effective.bodyText
            if let sid = SparkShareMarker.originID(from: bodyBlob),
               sid != share.postID,
               let origin = try? await PostsService.shared.getPostByID(sid) {
                applyResolved(from: origin)
            }
        }
    }

    private func applyResolved(from post: CountryPost) {
        let media = post.playableVideoURL?.absoluteString
            ?? MediaURLResolver.resolve(post.mediaURL)?.absoluteString
            ?? share.mediaURL
            ?? effective.mediaURL

        // Prefer a real image poster; never store mp4 as poster.
        let posterCandidates: [String?] = [
            post.posterImageURL?.absoluteString,
            post.feedImageURL?.absoluteString,
            post.thumbURL,
            MediaURLResolver.posterURL(for: post)?.absoluteString,
            share.posterURL,
            effective.posterURL,
        ]
        let poster = posterCandidates
            .compactMap { $0 }
            .first { raw in
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty, !t.hasPrefix("{") else { return false }
                return !Message.looksLikeVideoURL(t)
            }

        let kind: Message.ShareInfo.Kind = {
            if share.kind == .reel || post.isReel || PlayPlatformBridge.isSparkFeedCard(post) {
                return .reel
            }
            if share.kind == .hub || PlayPlatformBridge.isHubCatalogContent(post) {
                return .hub
            }
            return share.kind
        }()
        let mediaType: String? = {
            if kind == .reel { return post.mediaType ?? share.mediaType ?? "reel" }
            return post.mediaType ?? share.mediaType ?? (post.hasVideo ? "video" : nil)
        }()
        resolved = Message.ShareInfo(
            kind: kind,
            postID: post.id.isEmpty ? share.postID : post.id,
            title: share.title ?? post.displayHeadline ?? post.displayTitle,
            bodyText: share.bodyText ?? (post.displayBody.isEmpty ? post.displayCaption : post.displayBody),
            authorName: share.authorName ?? post.authorDisplayName,
            authorID: share.authorID ?? post.authorID,
            mediaURL: media,
            posterURL: poster,
            mediaType: mediaType,
            note: share.note
        )
    }
}

// MARK: - Shared routing (card + miniplayer)

enum ChatShareRouting {
    static func isSpark(_ share: Message.ShareInfo) -> Bool {
        if share.kind == .reel { return true }
        let type = (share.mediaType ?? "").lowercased()
        if type == "reel" || type == "spark" { return true }
        if share.asCountryPost.isReel { return true }
        // Feed spark re-share stamps sometimes land in chat without kind=reel.
        if SparkShareMarker.isMarked(share.bodyText) { return true }
        let body = (share.bodyText ?? "").lowercased()
        if body.contains("__spark__|") || body.contains("__reel__|") { return true }
        return false
    }

    @MainActor
    static func open(_ share: Message.ShareInfo, appState: AppState) {
        // Stop chat mini audio only — never tear down before Hubs mounts.
        MediaPlaybackCoordinator.shared.pauseAll()

        if isSpark(share) {
            // Same path as feed Spark cards: endless vertical Sparks, immediate swipe seed.
            var post = share.asCountryPost
            // Force reel typing so ranking / player treat this as a first-class Spark.
            if !post.isReel {
                post = CountryPost(
                    id: post.id,
                    title: post.title,
                    body: post.body.hasPrefix("__spark__|") || post.body.hasPrefix("__reel__|")
                        ? post.body
                        : "__spark__|\(post.body.isEmpty ? "Spark" : post.body)",
                    mediaType: "reel",
                    mediaURL: post.mediaURL ?? share.mediaURL,
                    thumbURL: post.thumbURL ?? share.posterURL,
                    mediaCaption: post.mediaCaption,
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
                    authorID: post.authorID,
                    countryName: post.countryName,
                    countryCode: post.countryCode,
                    cityName: post.cityName,
                    author: post.author,
                    externalRefType: post.externalRefType,
                    externalRefID: post.externalRefID
                )
            }
            appState.openGlobalSparksViewer(startingPost: post)
            return
        }

        // Hubs / video shares: open **immediately** from the chat payload (has media URL).
        // Waiting on getPostByID made Hubs feel dead after tap.
        if share.isHubContent || share.kind == .hub
            || (share.isVideo && share.kind != .post) {
            let instant = hubPost(from: share)
            appState.openLivingVideo(postID: instant.id, tab: .home, post: instant)
            // Enrich identity / media in background without blocking first frame.
            Task { @MainActor in
                let full = await resolvePost(for: share)
                guard full.playableVideoURL != nil || full.hasVideo else { return }
                // Same watch session — upgrade channel / URL if better, keep expanded.
                if appState.hubPlaybackPost?.id == share.postID
                    || appState.hubPlaybackPost?.id == full.id
                    || appState.hubPlaybackPost == nil {
                    appState.startHubPlayback(full, expanded: true)
                }
            }
            return
        }

        // Text / photo posts: resolve then open detail.
        Task { @MainActor in
            let post = await resolvePost(for: share)
            if post.hasVideo || !post.displayBody.isEmpty || post.hasMedia {
                appState.openPost(post)
            } else {
                await appState.openPost(id: share.postID)
            }
        }
    }

    /// Instant CountryPost from chat share metadata (no network).
    @MainActor
    private static func hubPost(from share: Message.ShareInfo) -> CountryPost {
        var post = share.asCountryPost
        // Ensure Hubs routing + video type when payload is thin.
        if post.mediaType == nil || post.mediaType?.isEmpty == true {
            post = CountryPost(
                id: post.id,
                title: post.title,
                body: post.body.isEmpty ? "__hub_channel__|" : post.body,
                mediaType: "video",
                mediaURL: post.mediaURL ?? share.mediaURL,
                thumbURL: post.thumbURL ?? share.posterURL,
                mediaCaption: post.mediaCaption,
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
                authorID: post.authorID,
                countryName: post.countryName,
                countryCode: post.countryCode,
                cityName: post.cityName,
                author: post.author,
                externalRefType: "hub",
                externalRefID: post.externalRefID ?? post.id
            )
        } else if post.externalRefType == nil {
            post = CountryPost(
                id: post.id,
                title: post.title,
                body: post.body,
                mediaType: post.mediaType ?? "video",
                mediaURL: post.mediaURL ?? share.mediaURL,
                thumbURL: post.thumbURL ?? share.posterURL,
                mediaCaption: post.mediaCaption,
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
                authorID: post.authorID,
                countryName: post.countryName,
                countryCode: post.countryCode,
                cityName: post.cityName,
                author: post.author,
                externalRefType: "hub",
                externalRefID: post.externalRefID ?? post.id
            )
        }
        return post
    }

    @MainActor
    private static func resolvePost(for share: Message.ShareInfo) async -> CountryPost {
        if let network = try? await PostsService.shared.getPostByID(share.postID) {
            return network
        }
        if let seed = await HubVideoSeedService.shared.post(id: share.postID) {
            return seed
        }
        var post = share.asCountryPost
        // Mark hub shares so openPost / openLivingVideo treat them as Hubs content.
        if share.isHubContent || share.kind == .hub {
            // externalRefType is set via copy if CountryPost supports it in initializer
            post = CountryPost(
                id: post.id,
                title: post.title,
                body: post.body,
                mediaType: post.mediaType ?? "video",
                mediaURL: post.mediaURL,
                thumbURL: post.thumbURL,
                mediaCaption: post.mediaCaption,
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
                authorID: post.authorID,
                countryName: post.countryName,
                countryCode: post.countryCode,
                cityName: post.cityName,
                author: post.author,
                externalRefType: "hub",
                externalRefID: post.externalRefID
            )
        }
        return post
    }
}

// MARK: - Fixed miniplayer under chat composer (user-started only)

/// Docked under the message list, above the text field / photo / send row.
/// Does **not** auto-play — user must press play. Maximize stays inside chat.
struct ChatFixedMiniPlayer: View {
    @Environment(AppState.self) private var appState

    let share: Message.ShareInfo
    @Binding var isPlaying: Bool
    @Binding var isExpanded: Bool
    var onClose: () -> Void
    var onOpenDestination: () -> Void

    @State private var isMuted = true
    @State private var resolvedURL: URL?

    private var playURL: URL? { resolvedURL ?? share.playableVideoURL }
    private var miniW: CGFloat { isExpanded ? min(UIScreen.main.bounds.width - 32, 340) : YouTubeMiniPlayerBar.videoWidth }
    private var miniH: CGFloat { miniW * 9 / 16 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                ZStack {
                    if let url = playURL {
                        playerSurface(url: url)
                        // Poster overlay until user presses play.
                        if !isPlaying {
                            posterOverlay
                                .onTapGesture { startPlayback() }
                        }
                    } else {
                        ZStack {
                            Theme.canvasDeep
                            ProgressView().tint(.white)
                        }
                    }
                }
                .frame(width: miniW, height: miniH)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
                .shadow(color: Theme.ink.opacity(0.12), radius: 8, y: 3)

                if !isExpanded {
                    metaColumn
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 10)

            if isExpanded {
                HStack(spacing: 12) {
                    metaColumn
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 8)
            }
        }
        .background(Theme.surface.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 0.5)
        }
        .task(id: share.postID) {
            await resolveURL()
            // Resolve only — do not autoplay.
            isPlaying = false
        }
        .onDisappear {
            isPlaying = false
        }
    }

    private var posterOverlay: some View {
        ZStack {
            if let poster = share.posterImageURL {
                CachedAsyncImage(
                    url: poster,
                    maxPixelSize: 420,
                    contentMode: .fill,
                    placeholder: AnyView(Color.black.opacity(0.35))
                )
            } else {
                Color.black.opacity(0.35)
            }
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(14)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
    }

    private var metaColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = share.title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            } else {
                Text(share.isHubContent ? MatteryaCopy.matteryaHubs : "Video")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            HStack(spacing: 8) {
                Button {
                    if isPlaying {
                        isPlaying = false
                    } else {
                        startPlayback()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.canvasMuted, in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.canvasMuted, in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.canvasMuted, in: Circle())
                }
                .buttonStyle(.plain)

                Button(action: onOpenDestination) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accentBright)
                        .frame(width: 32, height: 32)
                        .background(Theme.accentSoft, in: Circle())
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 32, height: 32)
                        .background(Theme.canvasMuted, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func playerSurface(url: URL) -> some View {
        if ArchiveVideoPlayback.isArchiveURL(url) || share.isHubContent {
            MatteryaHubPlayerView(
                url: url,
                posterURL: share.posterImageURL,
                isActive: isPlaying,
                startTime: 0,
                postID: share.postID,
                showsControls: isExpanded && isPlaying,
                loops: true,
                isMuted: $isMuted,
                allowsFullscreen: false,
                onReady: nil
            )
            .id("chat-fixed-hub-\(share.postID)")
        } else {
            VideoPlayerView(
                url: url,
                posterURL: share.posterImageURL,
                placement: nil,
                countryCode: nil,
                contentCountryCode: nil,
                postID: share.postID,
                adsEnabled: false,
                isActive: isPlaying,
                loops: true,
                muted: isMuted,
                showsControls: isExpanded && isPlaying,
                allowsFullscreen: false,
                startTime: 0,
                persistsPositionOnTeardown: false,
                onViewed: nil
            )
            .id("chat-fixed-vid-\(share.postID)")
        }
    }

    private func startPlayback() {
        if appState.hubPlaybackPost != nil {
            appState.hubPlaybackPlaying = false
        }
        MediaPlaybackCoordinator.shared.pauseAll()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true, options: [])
        if let url = playURL, ArchiveVideoPlayback.isArchiveURL(url) {
            ArchiveVideoPlayback.warmResolve(url)
        }
        isMuted = false
        isPlaying = true
    }

    private func resolveURL() async {
        if let url = share.playableVideoURL {
            resolvedURL = url
            return
        }
        if let post = try? await PostsService.shared.getPostByID(share.postID),
           let url = post.playableVideoURL {
            resolvedURL = url
            return
        }
        if let seed = await HubVideoSeedService.shared.post(id: share.postID),
           let url = seed.playableVideoURL {
            resolvedURL = url
        }
    }
}

// MARK: - Full-screen image lightbox

struct ChatImageLightbox: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    var title: String? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.opacity(0.96 - Double(min(abs(dragOffset) / 400, 0.35)))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer(minLength: 0)

                CachedAsyncImage(
                    url: url,
                    maxPixelSize: 1600,
                    contentMode: .fit,
                    placeholder: AnyView(
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: 320)
                    )
                )
                .scaleEffect(scale)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.height
                        }
                        .onEnded { value in
                            if abs(value.translation.height) > 120 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(value, 1), 3.5)
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                if scale < 1.05 { scale = 1 }
                            }
                        }
                )
                .padding(.horizontal, 8)

                Spacer(minLength: 0)

                Text("Pinch to zoom · swipe down to close")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 28)
            }
        }
    }
}
