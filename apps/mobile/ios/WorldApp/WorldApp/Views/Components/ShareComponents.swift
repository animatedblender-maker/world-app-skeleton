import Combine
import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ToastBanner: View {
    let message: String
    var style: ToastStyle = .info

    enum ToastStyle {
        case info, success, error

        var background: Color {
            switch self {
            case .info: Theme.ink
            case .success: Theme.accent
            case .error: Theme.danger
            }
        }
    }

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(style.background, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .padding(.horizontal, 20)
    }
}

/// In-feed Sparks surface: same full-width + dominant height as normal feed video cards,
/// with Sparks badge + mute chip; tap opens the infinite Sparks player.
struct SparkFeedCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    var edgeToEdge: Bool = false
    var autoplaySurface: FeedAutoplaySurface = .home
    var onOpen: (() -> Void)? = nil

    private var corner: CGFloat { edgeToEdge ? 0 : 12 }

    /// Best playable URL: post → resolver → shared original (feed shares often only stamp origin).
    private var playURL: URL? {
        if let u = post.playableVideoURL ?? MediaURLResolver.videoURL(for: post) { return u }
        if let origin = post.sharedPost?.asCountryPost {
            return origin.playableVideoURL ?? MediaURLResolver.videoURL(for: origin)
        }
        return nil
    }

    /// Live Frame 0 — feed/sparks thumb_url is often an expired Aug-signed webp (403).
    @State private var livePosterURL: URL?

    private var posterURL: URL? {
        let candidates: [URL?] = [
            livePosterURL,
            Frame0PosterCache.url(for: post.id),
            MediaURLResolver.posterURL(for: post),
            post.sharedPost.flatMap { MediaURLResolver.posterURL(for: $0.asCountryPost) },
        ]
        for candidate in candidates {
            guard let url = candidate, MediaURLResolver.isUsablePosterURL(url) else { continue }
            return url
        }
        return nil
    }

    /// width/height once known — drives card height so first frame isn't forced into wrong box.
    @State private var stageSize: CGSize = .zero
    @State private var mediaAspect: CGFloat? = nil
    @State private var useFill = false
    @State private var gravityLocked = false

    private var cardWidth: CGFloat {
        stageSize.width > 2 ? stageSize.width : UIScreen.main.bounds.width
    }

    /// Portrait → near 9:16; landscape → true 16:9. Unknown → 9:16 (Sparks default).
    private var cardHeight: CGFloat {
        let w = cardWidth
        guard let a = mediaAspect, a.isFinite, a > 0.05 else {
            return FacebookMediaLayout.sparkFeedCardHeight(forWidth: w)
        }
        if a >= 1.0 {
            // Landscape / square ShortForm — never keep a tall 9:16 letterbox stage.
            return FacebookMediaLayout.hubFeedVideoHeight(forWidth: w)
        }
        let natural = w / a
        let maxH = FacebookMediaLayout.sparkFeedCardHeight(forWidth: w)
        return min(max(natural, FacebookMediaLayout.minFeedMediaHeight), maxH)
    }

    private func applyVideoSize(_ size: CGSize) {
        guard !gravityLocked else { return }
        guard size.width > 2, size.height > 2 else { return }
        let aspect = size.width / size.height
        guard aspect.isFinite, aspect > 0.05 else { return }
        mediaAspect = aspect
        let w = cardWidth
        let stageH: CGFloat
        if aspect >= 1.0 {
            stageH = FacebookMediaLayout.hubFeedVideoHeight(forWidth: w)
        } else {
            let natural = w / aspect
            let maxH = FacebookMediaLayout.sparkFeedCardHeight(forWidth: w)
            stageH = min(max(natural, FacebookMediaLayout.minFeedMediaHeight), maxH)
        }
        useFill = SparksStageLayout.shouldFillWithoutCrop(
            videoSize: size,
            stageSize: CGSize(width: w, height: stageH)
        )
        gravityLocked = true
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            // Film only — clipped. Badge + mute live ABOVE this layer so fill/fit
            // never crops them off on landscape / ShortForm packs.
            Group {
                if let url = playURL {
                    ZStack {
                        Color.black
                        // Always show Frame 0 (or thumb) under the player — never leave black.
                        if let posterURL {
                            CachedAsyncImage(
                                url: posterURL,
                                // Feed scroll weight — 900px posters hitch Home; Sparks FS uses its own decode.
                                maxPixelSize: 540,
                                contentMode: useFill ? .fill : .fit,
                                placeholder: AnyView(Color.black)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .allowsHitTesting(false)
                        } else {
                            FrameZeroFallbackPoster(
                                postID: post.id,
                                videoURL: url,
                                fillsFrame: useFill,
                                allowClientExtract: false,
                                seedPosterURL: livePosterURL ?? Frame0PosterCache.url(for: post.id)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                        }
                        InFrameVideoPlayer(
                            url: url,
                            posterURL: posterURL,
                            placement: "reel",
                            countryCode: post.countryCode,
                            contentCountryCode: post.countryCode,
                            postID: post.id,
                            muted: appState.feedVideosMuted,
                            loops: true,
                            preferArchivePlayer: ArchiveVideoPlayback.isArchiveURL(url),
                            showsControls: false,
                            // Chrome is drawn by SparkFeedCard overlays on top of the film —
                            // never reserve a black strip (that was the top gap on feed Sparks).
                            muteOnlyControls: false,
                            fillsFrame: useFill,
                            topChromeReserve: 0,
                            sharesFeedMute: true,
                            autoplaySurface: autoplaySurface,
                            onViewed: { Task { await PostsService.shared.recordView(post) } },
                            onVideoSize: { applyVideoSize($0) }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipped()
                    .animation(nil, value: useFill)
                } else {
                    VideoThumbnailView(
                        post: post,
                        maxPixelSize: 720,
                        contentMode: .fill,
                        showsPlayIcon: true,
                        playIconSize: 36,
                        placeholder: AnyView(
                            Rectangle().fill(Theme.canvasDeep)
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .task {
                        guard let remote = try? await PostsService.shared.getPostByID(post.id),
                              remote.playableVideoURL != nil
                        else { return }
                        PostsService.shared.publishPostChange(remote)
                    }
                }
            }

            // Tap opens full Sparks; top strip reserved for badge + mute (not tappable-away).
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 52)
                    .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { openFullPlayer() }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: cardHeight)
        .animation(nil, value: mediaAspect)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { stageSize = geo.size }
                    .onChange(of: geo.size) { _, size in
                        stageSize = size
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(alignment: .topLeading) {
            if post.isAdultContent {
                Text("18+")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .accessibilityLabel("18 plus content")
            }
        }
        // Mute only — no Sparks/Hubs origin badges on film.
        .overlay(alignment: .topTrailing) {
            SparkFeedMuteButton()
                .padding(.horizontal, 12)
                .padding(.top, 10)
        }
        .contentShape(Rectangle())
        .overlay {
            if !edgeToEdge {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens \(MatteryaCopy.sparks) full-screen player")
        .onChange(of: post.id) { _, _ in
            mediaAspect = nil
            useFill = false
            gravityLocked = false
            livePosterURL = nil
        }
        .task(id: post.id) {
            await seedPosterAndAspect()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .frame0PostersDidUpdate)
                .receive(on: DispatchQueue.main)
        ) { note in
            guard !ScrollBudget.isFlinging else { return }
            let ids = note.userInfo?["postIDs"] as? [String]
            if let ids, !ids.isEmpty, !ids.contains(post.id) { return }
            guard let cached = Frame0PosterCache.url(for: post.id),
                  MediaURLResolver.isUsablePosterURL(cached)
            else { return }
            livePosterURL = cached
            Task { await seedAspectFromPoster(cached) }
        }
    }

    /// Resolve fresh Frame 0 and lock stage from poster pixels before AV measures.
    @MainActor
    private func seedPosterAndAspect() async {
        if let existing = posterURL {
            livePosterURL = existing
            await seedAspectFromPoster(existing)
            return
        }
        if let signed = await Frame0PosterResolver.shared.posterURL(postID: post.id),
           MediaURLResolver.isUsablePosterURL(signed) {
            livePosterURL = signed
            await seedAspectFromPoster(signed)
        }
    }

    @MainActor
    private func seedAspectFromPoster(_ url: URL) async {
        guard !gravityLocked else { return }
        guard let image = await ImageCache.shared.image(for: url, maxPixelSize: 540) else { return }
        let pixel = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        applyVideoSize(pixel)
    }

    private func openFullPlayer() {
        if let onOpen {
            onOpen()
            return
        }
        // Pre-warm origin + share ids so full-screen claim is a hit (IG-style).
        let start = ReelsRankingEngine.resolvePlayerStart(post)
        if let url = start.playableVideoURL ?? playURL {
            SparkWarmPool.shared.warmSingle(postID: start.id, url: url, deep: true)
            if start.id != post.id {
                SparkWarmPool.shared.warmSingle(postID: post.id, url: url, deep: true)
            }
        }
        appState.openGlobalSparksViewer(startingPost: post)
    }
}

/// Former Sparks origin chip on video — removed (product: no Hubs/Sparks badges on film).
struct SparksOriginBadge: View {
    var compact: Bool = false
    var body: some View { EmptyView() }
}

/// Feed Sparks mute chip — card overlay (always visible above film).
struct SparkFeedMuteButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.feedVideosMuted.toggle()
        } label: {
            Image(systemName: appState.feedVideosMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appState.feedVideosMuted ? "Unmute" : "Mute")
    }
}

struct SharedPostEmbedView: View {
    @Environment(AppState.self) private var appState

    let embed: SharedPostPreview
    var autoplaySurface: FeedAutoplaySurface = .home
    /// When true (feed cards), media is full-width; text chrome keeps a small side margin.
    var edgeToEdge: Bool = false

    private var sourcePost: CountryPost { embed.asCountryPost }

    private var mediaSideInset: CGFloat { edgeToEdge ? 0 : Theme.pagePadding }

    /// Shared hub long-form → same player + Hubs badge as native hub feed cards.
    private var isHubShareVideo: Bool {
        PlayPlatformBridge.isHubFeedCardVideo(sourcePost)
    }

    var body: some View {
        Group {
            // Sparks first — never mis-route a shared Spark into Hubs long-form chrome.
            if sourcePost.isReel
                || PlayPlatformBridge.isReelVideo(sourcePost)
                || PlayPlatformBridge.isSparkFeedCard(sourcePost) {
                SparkFeedCard(
                    post: sourcePost,
                    edgeToEdge: edgeToEdge,
                    autoplaySurface: autoplaySurface
                ) {
                    appState.openGlobalSparksViewer(startingPost: sourcePost)
                }
                .padding(.horizontal, mediaSideInset)
                .padding(.vertical, edgeToEdge ? 0 : 8)
            } else if isHubShareVideo || (PlayPlatformBridge.isLongFormVideo(sourcePost)
                && PlayPlatformBridge.isHubCatalogContent(sourcePost)) {
                // Hubs origin share — full-width 16:9 film only; parent card owns actions under it.
                PlayFeedLinkCard(
                    post: sourcePost,
                    onOpen: { appState.openPost(sourcePost) },
                    edgeToEdge: true,
                    forceHubsBadge: true,
                    autoplaySurface: autoplaySurface
                )
                .padding(.horizontal, edgeToEdge ? 0 : mediaSideInset)
                .padding(.vertical, edgeToEdge ? 0 : 8)
            } else if PlayPlatformBridge.isLongFormVideo(sourcePost) {
                // Plain long-form feed share — player only, no Hubs badge/channel claim.
                PlayFeedLinkCard(
                    post: sourcePost,
                    onOpen: { appState.openPost(sourcePost) },
                    edgeToEdge: true,
                    forceHubsBadge: false,
                    autoplaySurface: autoplaySurface
                )
                .padding(.horizontal, edgeToEdge ? 0 : mediaSideInset)
                .padding(.vertical, edgeToEdge ? 0 : 8)
            } else {
                standardEmbed
                    .padding(.horizontal, edgeToEdge ? Theme.pagePadding : Theme.pagePadding)
            }
        }
    }

    private var standardEmbed: some View {
        let post = sourcePost
        let isVideo = embed.hasVideo
        let isHub = PlayPlatformBridge.isHubCatalogContent(post)
        // Same height rules as feed cards: photos use 4:5 capped at maxFeedMediaHeight; videos 16:9 tall.
        let photoAspect = FacebookMediaLayout.aspectRatio(for: post, context: .feed)
            ?? FacebookMediaLayout.photoPortraitAspect

        return Button {
            appState.openPost(post)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    AvatarView(url: embed.author?.avatarURL, seed: embed.authorID, size: 24)
                    Text(embed.author?.displayName ?? embed.author?.username ?? "Member")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

                if embed.hasMedia {
                    ZStack(alignment: .topLeading) {
                        Group {
                            if isVideo {
                                VideoThumbnailView(
                                    post: post,
                                    maxPixelSize: 720,
                                    contentMode: .fill,
                                    showsPlayIcon: false,
                                    playIconSize: 36,
                                    placeholder: AnyView(mediaPlaceholder)
                                )
                            } else if let url = embed.feedImageURL {
                                CachedAsyncImage(
                                    url: url,
                                    maxPixelSize: 720,
                                    contentMode: .fill,
                                    placeholder: AnyView(mediaPlaceholder)
                                )
                            } else {
                                mediaPlaceholder
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .modifier(SharedEmbedMediaSizeModifier(
                            isVideo: isVideo,
                            photoAspect: photoAspect,
                            isHubCompact: isHub
                        ))
                        .clipped()

                    }
                }

                if !embed.displayExcerpt.isEmpty {
                    Text(embed.displayExcerpt)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
            .background(Theme.canvasMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
    }

    private var mediaPlaceholder: some View {
        Rectangle()
            .fill(Theme.canvas)
            .overlay {
                Image(systemName: embed.hasVideo ? "video" : "photo")
                    .foregroundStyle(Theme.inkMuted)
            }
    }
}

/// Matches `FeedMediaSizeModifier` — full card width, height from that width (never shrink width).
private struct SharedEmbedMediaSizeModifier: ViewModifier {
    let isVideo: Bool
    let photoAspect: CGFloat
    var isHubCompact: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isVideo {
            let height = isHubCompact
                ? FacebookMediaLayout.hubFeedVideoHeight()
                : FacebookMediaLayout.dominantFeedVideoHeight()
            content
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else {
            content
                .frame(maxWidth: .infinity)
                .aspectRatio(photoAspect, contentMode: .fit)
                .frame(maxHeight: FacebookMediaLayout.maxFeedMediaHeight)
        }
    }
}

struct SharePostSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let post: CountryPost
    /// When set (Sparks overlay), close via this instead of sheet dismiss — playback keeps running.
    var onClose: (() -> Void)? = nil
    /// Stay in Sparks after in-app share actions (no chat navigation / no Sparks dismiss).
    var keepsSparksPlaying: Bool = false

    @State private var showMessagePicker = false
    @State private var showRepeatShareConfirm = false
    @State private var busy = false
    @State private var feedback: String?

    private var isSparkShare: Bool {
        post.isReel || post.isSparkFeedShare || PlayPlatformBridge.isSparkFeedCard(post)
    }

    private func closeShareUI() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var homeCountryName: String {
        appState.currentProfile?.countryName ?? "your country"
    }

    private var sourceCountryName: String? {
        post.countryName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfWhitespace
    }

    var body: some View {
        VStack(spacing: 0) {
            // Matterya header — not Apple toolbar Cancel.
            HStack {
                Text("Share")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: closeShareUI) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.matte, in: Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        // No headlines — show caption/body when present.
                        if let caption = post.displayCaption ?? (post.displayBody.isEmpty ? nil : post.displayBody) {
                            Text(caption)
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(3)
                        }
                        if let sourceCountryName {
                            Text("From \(sourceCountryName)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.matte)
                    )

                    Text("On Matterya")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    matteryaShareRow(
                        title: isSparkShare ? "Send \(MatteryaCopy.spark) in chat" : "Send in Messages",
                        subtitle: isSparkShare
                            ? "Friend opens full-screen \(MatteryaCopy.sparks)"
                            : "Private chat with a friend",
                        icon: isSparkShare ? "sparkles" : "paperplane.fill"
                    ) {
                        showMessagePicker = true
                    }

                    matteryaShareRow(
                        title: isSparkShare
                            ? "Share as \(MatteryaCopy.spark)"
                            : MatteryaCopy.shareToYourFeed,
                        subtitle: isSparkShare
                            ? "Adds this clip to your feed & \(MatteryaCopy.sparks)"
                            : shareToFeedSubtitle,
                        icon: isSparkShare ? "bolt.fill" : "rectangle.stack.fill"
                    ) {
                        if appState.needsRepeatShareWarning(for: post) {
                            showRepeatShareConfirm = true
                        } else {
                            Task { await shareToCountryFeed() }
                        }
                    }

                    if !keepsSparksPlaying {
                        matteryaShareRow(
                            title: "Repost with quote",
                            subtitle: "Write your take on your home feed",
                            icon: "quote.bubble"
                        ) {
                            Task { await repostWithQuote() }
                        }
                    }

                    matteryaShareRow(
                        title: "Copy link",
                        subtitle: "Paste anywhere — still opens in Matterya",
                        icon: "link"
                    ) {
                        ShareService.shared.copyLink(for: .post(post))
                        appState.showToast("Link copied")
                        closeShareUI()
                    }

                    if let feedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                // Clear home indicator + leave room so Copy link is never clipped.
                .padding(.bottom, 28 + (keepsSparksPlaying ? Theme.tabBarHeight : 0))
            }
        }
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Keep the last share rows above the home indicator / any residual chrome.
            Color.clear.frame(height: 8)
        }
        .confirmationDialog(
            "Share again?",
            isPresented: $showRepeatShareConfirm,
            titleVisibility: .visible
        ) {
            Button("Share Again") {
                Task { await shareToCountryFeed() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(repeatShareWarningMessage)
        }
        .sheet(isPresented: $showMessagePicker) {
            ShareMessagePickerSheet(post: post) { conversationID in
                if keepsSparksPlaying {
                    appState.showToast("Sent in message")
                    closeShareUI()
                } else {
                    appState.openConversation(id: conversationID)
                    appState.showToast("Sent in message")
                    closeShareUI()
                }
            }
            // Nested sheet under Sparks dark chrome — lock paper so contact names show.
            .preferredColorScheme(.light)
            .environment(\.colorScheme, .light)
        }
        // Sheet-only chrome (feed share). Sparks uses an overlay host — no presentation detents.
        .modifier(ShareSheetPresentationModifier(enabled: !keepsSparksPlaying))
    }

    private func matteryaShareRow(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.matte)
                    .frame(width: 40, height: 40)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var shareToFeedSubtitle: String {
        "Adds this post to the main feed"
    }

    private var repeatShareWarningMessage: String {
        if let profile = appState.currentProfile,
           let countryCode = appState.homeCountryISO?.uppercased(),
           let postCountry = post.countryCode?.uppercased(),
           postCountry == countryCode,
           post.authorID == profile.userID,
           post.sharedPostID == nil {
            return "This post is already on your feed. Share it again anyway?"
        }
        return "You've shared this post before. Do you still want to add it to your feed again?"
    }

    private func shareToCountryFeed() async {
        busy = true
        defer { busy = false }
        let message = await appState.sharePostToCountryFeed(post)
        appState.showToast(message, style: message.localizedCaseInsensitiveContains("shared") ? .success : .info)
        closeShareUI()
    }

    private func repostWithQuote() async {
        busy = true
        defer { busy = false }
        guard let home = await appState.resolveHomeCountry() else {
            appState.showToast("Set your home country first", style: .error)
            return
        }
        appState.composerCountry = home
        appState.activeCreateSheet = .post
        appState.quotedSharePostID = post.sharedPostID ?? post.id
        closeShareUI()
    }
}

struct ShareMessagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let post: CountryPost
    let onSent: (String) -> Void

    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var currentUserID: String {
        AuthService.shared.currentUser?.id ?? ""
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading conversations…")
                        .tint(Theme.ink)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn't load messages",
                        systemImage: "exclamationmark.bubble",
                        description: Text(errorMessage)
                    )
                    .foregroundStyle(Theme.ink)
                } else if conversations.isEmpty {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a chat from someone's profile, then share here.")
                    )
                    .foregroundStyle(Theme.ink)
                } else {
                    List(conversations) { conversation in
                        Button {
                            Task { await send(to: conversation) }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(
                                    url: conversation.displayAvatarURL(currentUserID: currentUserID),
                                    seed: conversation.id,
                                    size: 40
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conversation.displayTitle(currentUserID: currentUserID))
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Theme.ink)
                                    if let preview = conversation.lastMessage?.previewText, !preview.isEmpty {
                                        Text(preview)
                                            .font(.caption)
                                            .foregroundStyle(Theme.inkMuted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.canvas)
                        .listRowSeparatorTint(Theme.border.opacity(0.7))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(isSparkShare ? "Send \(MatteryaCopy.spark) to…" : "Send to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
            .task { await load() }
        }
        // Sparks forces dark scheme for the film; this picker must stay paper/white
        // so Theme.ink names remain readable (dark List + ink = invisible).
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .presentationBackground(Theme.canvas)
    }

    private var isSparkShare: Bool {
        post.isReel || post.isSparkFeedShare || PlayPlatformBridge.isSparkFeedCard(post)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await MessagesService.shared.listConversations(limit: 60)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send(to conversation: Conversation) async {
        do {
            try await ShareService.shared.sendPostInMessage(post: post, conversationID: conversation.id)
            onSent(conversation.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension Conversation {
    func displayTitle(currentUserID: String) -> String {
        let other = otherMember(currentUserID: currentUserID)
        return ContentSanitizer.displayName(
            displayName: other?.displayName,
            username: other?.username
        )
    }

    func displayAvatarURL(currentUserID: String) -> String? {
        otherMember(currentUserID: currentUserID)?.avatarURL
    }
}

extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private struct ShareSheetPresentationModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                // Tall enough that Send / Share to feed / Repost / Copy link all fit
                // above the home indicator without sitting under the custom tab bar.
                .presentationDetents([.fraction(0.62), .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        } else {
            content
        }
    }
}

extension View {
    func sharePostSheet(appState: AppState) -> some View {
        // Sparks full-screen + expanded Hubs watch use in-place overlays so AVPlayer
        // never pauses and Hubs never collapses to the mini player.
        sheet(item: Binding(
            get: {
                if appState.reelsViewerContext != nil { return nil }
                if appState.hubPlaybackPost != nil, appState.hubPlaybackExpanded { return nil }
                return appState.sharePostSheet
            },
            set: { appState.sharePostSheet = $0 }
        )) { post in
            SharePostSheet(post: post)
                .withAppState(appState)
        }
    }
}

/// Bottom share card over expanded Hubs watch — continuous player keeps playing underneath.
struct HubsShareOverlay: View {
    @Environment(AppState.self) private var appState
    let post: CountryPost
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .allowsHitTesting(true)

            SharePostSheet(
                post: post,
                onClose: onClose,
                // Same as Sparks: stay on watch, no chat jump / no mini collapse.
                keepsSparksPlaying: true
            )
            .withAppState(appState)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.35), radius: 20, y: -4)
            )
            .padding(.bottom, Theme.tabBarHeight)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.58)
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            appState.hubPlaybackPlaying = true
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
        .onDisappear {
            appState.hubPlaybackPlaying = true
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
    }
}

extension UIViewController {
    func presentShareSheet(items: [Any]) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(controller, animated: true)
    }

    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController()
        }
        if let navigation = self as? UINavigationController, let visible = navigation.visibleViewController {
            return visible.topMostViewController()
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.topMostViewController()
        }
        return self
    }
}

private extension String {
    var nilIfWhitespace: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}