import AVFoundation
import SwiftUI

// MARK: - Shared post / hub / spark card in chat (no play chrome)

/// Tappable share card — **no in-card playback**. Entire card opens the destination:
/// Sparks → full-screen Sparks player · Hubs video → Hubs watch · post → post detail.
/// Sparks use a portrait Shorts-style card; hubs/posts stay landscape.
struct ChatShareCard: View {
    @Environment(AppState.self) private var appState

    let share: Message.ShareInfo
    var isMine: Bool = false
    /// Opens destination (required for reliable navigation from chat).
    var onOpen: (() -> Void)? = nil

    @State private var resolved: Message.ShareInfo?

    private let cardWidth: CGFloat = 248
    private let thumbW: CGFloat = YouTubeMiniPlayerBar.videoWidth
    private let thumbH: CGFloat = YouTubeMiniPlayerBar.videoHeight

    private var effective: Message.ShareInfo { resolved ?? share }

    private var isSparkShare: Bool {
        ChatShareRouting.isSpark(effective)
    }

    var body: some View {
        Group {
            if isSparkShare {
                sparkCard
            } else {
                standardCard
            }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .task(id: share.postID) {
            await hydrateIfNeeded()
        }
    }

    // MARK: Spark — portrait Shorts-style chat share

    /// Distinct from Hubs: 9:16 frame, Sparks badge, “Watch Spark” CTA. Tap → Sparks player.
    private var sparkCard: some View {
        let portraitW: CGFloat = 168
        let portraitH: CGFloat = 280

        return Button(action: handleOpen) {
            VStack(alignment: isMine ? .trailing : .leading, spacing: 8) {
                if !effective.note.isEmpty {
                    Text(effective.note)
                        .font(.subheadline)
                        .foregroundStyle(isMine ? .white : Theme.ink)
                        .multilineTextAlignment(isMine ? .trailing : .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isMine ? Theme.accentBright : Theme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isMine ? Color.clear : Theme.border.opacity(0.6), lineWidth: 0.5)
                        )
                }

                ZStack(alignment: .bottom) {
                    // Full-bleed poster (vertical Spark frame).
                    Group {
                        if let poster = effective.posterImageURL {
                            CachedAsyncImage(
                                url: poster,
                                maxPixelSize: 560,
                                contentMode: .fill,
                                placeholder: AnyView(sparkPlaceholder)
                            )
                        } else {
                            sparkPlaceholder
                        }
                    }
                    .frame(width: portraitW, height: portraitH)
                    .clipped()

                    // Soft top vignette so badge stays readable.
                    LinearGradient(
                        colors: [Color.black.opacity(0.45), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .frame(height: 72)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                    // Bottom meta scrim.
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                    // Sparks brand chip.
                    VStack {
                        HStack {
                            SparksOriginBadge(compact: true)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(false)

                    // Caption + author + open affordance.
                    VStack(alignment: .leading, spacing: 6) {
                        if let caption = sparkCaption {
                            Text(caption)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        }

                        HStack(spacing: 6) {
                            if let author = effective.authorName, !author.isEmpty {
                                Text(author)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Watch")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Theme.reelsAccent,
                                                Theme.accentBright.opacity(0.95),
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: portraitW, height: portraitH)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.985, green: 0.753, blue: 0.176).opacity(0.85),
                                    Theme.reelsAccent.opacity(0.9),
                                    Color(red: 0.525, green: 0.224, blue: 0.796).opacity(0.7),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Theme.ink.opacity(0.14), radius: 12, y: 4)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Open \(MatteryaCopy.spark)")
        .accessibilityHint("Opens full-screen \(MatteryaCopy.sparks) player")
    }

    private var sparkCaption: String? {
        if let title = effective.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let body = effective.bodyText?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            // Strip control markers if they leaked into body text.
            let cleaned = body
                .replacingOccurrences(of: "__spark__|", with: "")
                .replacingOccurrences(of: "__reel__|", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }

    private var sparkPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.14, blue: 0.12),
                    Color(red: 0.32, green: 0.24, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: Hub / post — landscape card

    private var standardCard: some View {
        Button(action: handleOpen) {
            VStack(alignment: .leading, spacing: 8) {
                headerRow

                if !effective.note.isEmpty {
                    Text(effective.note)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let title = effective.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else if let body = effective.bodyText, !body.isEmpty, effective.note.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                if effective.isVideo || effective.posterImageURL != nil {
                    shareThumb
                }

                if let author = effective.authorName, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(width: cardWidth, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: Theme.ink.opacity(0.06), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Open \(kindLabel)")
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: kindIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.accentBright)
            Text(kindLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.accentBright)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.inkMuted)
        }
    }

    private var kindIcon: String {
        if effective.isHubContent { return "play.rectangle.fill" }
        return "doc.text.fill"
    }

    private var kindLabel: String {
        if effective.isHubContent { return MatteryaCopy.matteryaHubs }
        return "Post"
    }

    /// Poster only — no play circle (playback is not on the card).
    private var shareThumb: some View {
        Group {
            if let poster = effective.posterImageURL {
                CachedAsyncImage(
                    url: poster,
                    maxPixelSize: 420,
                    contentMode: .fill,
                    placeholder: AnyView(thumbPlaceholder)
                )
            } else {
                thumbPlaceholder
            }
        }
        .frame(width: thumbW, height: thumbH)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private var thumbPlaceholder: some View {
        Rectangle()
            .fill(Theme.canvasDeep)
            .overlay {
                Image(systemName: effective.isVideo ? "film" : "doc.richtext")
                    .font(.title3)
                    .foregroundStyle(Theme.inkMuted)
            }
    }

    private func handleOpen() {
        if let onOpen {
            onOpen()
            return
        }
        // Fallback if parent forgot the callback.
        ChatShareRouting.open(effective, appState: appState)
    }

    private func hydrateIfNeeded() async {
        if effective.playableVideoURL != nil || effective.posterImageURL != nil { return }
        guard !share.postID.isEmpty else { return }
        if let post = try? await PostsService.shared.getPostByID(share.postID) {
            applyResolved(from: post)
            return
        }
        if let seed = await HubVideoSeedService.shared.post(id: share.postID) {
            applyResolved(from: seed)
        }
    }

    private func applyResolved(from post: CountryPost) {
        let media = post.playableVideoURL?.absoluteString
            ?? MediaURLResolver.resolve(post.mediaURL)?.absoluteString
            ?? share.mediaURL
        let poster = post.posterImageURL?.absoluteString
            ?? post.feedImageURL?.absoluteString
            ?? post.thumbURL
            ?? share.posterURL
        let kind: Message.ShareInfo.Kind = {
            if share.kind == .reel || post.isReel { return .reel }
            if share.kind == .hub || PlayPlatformBridge.isHubCatalogContent(post) { return .hub }
            return share.kind
        }()
        let mediaType: String? = {
            if kind == .reel { return post.mediaType ?? share.mediaType ?? "reel" }
            return post.mediaType ?? share.mediaType ?? (post.hasVideo ? "video" : nil)
        }()
        resolved = Message.ShareInfo(
            kind: kind,
            postID: post.id,
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
        return false
    }

    @MainActor
    static func open(_ share: Message.ShareInfo, appState: AppState) {
        // Stop any chat mini audio before leaving.
        MediaPlaybackCoordinator.shared.pauseAll()

        if isSpark(share) {
            let post = share.asCountryPost
            // Endless Sparks from this clip — same as feed Spark cards.
            appState.openGlobalSparksViewer(startingPost: post)
            return
        }

        // Resolve full post on a background path so Hubs/post open has real media.
        Task { @MainActor in
            let post = await resolvePost(for: share)
            if share.isHubContent || PlayPlatformBridge.isHubCatalogContent(post) || share.kind == .hub {
                // Prefer hubs continuous watch when we have a playable video.
                if post.hasVideo || post.playableVideoURL != nil {
                    appState.openLivingVideo(postID: post.id, tab: .home, post: post)
                } else {
                    appState.openLivingVideo(postID: share.postID, tab: .home, post: nil)
                }
                return
            }
            // Normal post / feed video.
            if post.hasVideo || !post.displayBody.isEmpty || post.hasMedia {
                appState.openPost(post)
            } else {
                await appState.openPost(id: share.postID)
            }
        }
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
