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

    /// Facebook-style: full-width tall media area (same as other feed video posts).
    private var cardHeight: CGFloat {
        FacebookMediaLayout.dominantFeedVideoHeight()
    }

    /// Best playable URL: post → resolver → shared original (feed shares often only stamp origin).
    private var playURL: URL? {
        if let u = post.playableVideoURL ?? MediaURLResolver.videoURL(for: post) { return u }
        if let origin = post.sharedPost?.asCountryPost {
            return origin.playableVideoURL ?? MediaURLResolver.videoURL(for: origin)
        }
        return nil
    }

    private var posterURL: URL? {
        post.posterImageURL
            ?? post.sharedPost?.asCountryPost.posterImageURL
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.ink

            if let url = playURL {
                // Facebook: size the box, then **fill** it — no letterbox that shrinks the picture.
                // Prefer the **fast Sparks path** (VideoPlayerView + warm pool). Archive only for archive.org.
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
                    muteOnlyControls: true,
                    fillsFrame: true,
                    sharesFeedMute: true,
                    autoplaySurface: autoplaySurface,
                    onViewed: { Task { await PostsService.shared.recordView(post) } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.ink)
                .clipped()
                // Media session 09: poster only on mount — winner path installs the player.
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
                    // Expired / missing media — try a live post fetch so the card can play.
                    guard let remote = try? await PostsService.shared.getPostByID(post.id),
                          remote.playableVideoURL != nil
                    else { return }
                    // Soft publish so feed re-renders with a playable URL.
                    PostsService.shared.publishPostChange(remote)
                }
            }

            SparksOriginBadge(compact: true)
                .padding(10)
                .allowsHitTesting(false)

            // Tap opens full Sparks player; leave top strip free for mute chip.
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
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .contentShape(Rectangle())
        .overlay {
            if !edgeToEdge {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens \(MatteryaCopy.sparks) full-screen player")
    }

    private func openFullPlayer() {
        if let onOpen {
            onOpen()
            return
        }
        // Endless Sparks from all over Matterya — not a one-clip dead end.
        appState.openGlobalSparksViewer(startingPost: post)
    }
}

/// Compact Sparks brand chip — feed cards + full-screen player.
struct SparksOriginBadge: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: "sparkles")
                .font(.system(size: compact ? 9 : 11, weight: .bold))
            Text(MatteryaCopy.sparks)
                .font(.system(size: compact ? 10 : 12, weight: .bold))
                .tracking(0.3)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Theme.reelsAccent, Theme.accentBright.opacity(0.92)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
        .accessibilityLabel(MatteryaCopy.sparks)
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
                // Hubs origin share — badge + open original channel (never creates a channel for sharer).
                PlayFeedLinkCard(
                    post: sourcePost,
                    onOpen: { appState.openPost(sourcePost) },
                    edgeToEdge: edgeToEdge,
                    forceHubsBadge: true,
                    autoplaySurface: autoplaySurface
                )
                .padding(.horizontal, mediaSideInset)
                .padding(.vertical, edgeToEdge ? 0 : 8)
            } else if PlayPlatformBridge.isLongFormVideo(sourcePost) {
                // Plain long-form feed share — player only, no Hubs badge/channel claim.
                PlayFeedLinkCard(
                    post: sourcePost,
                    onOpen: { appState.openPost(sourcePost) },
                    edgeToEdge: edgeToEdge,
                    forceHubsBadge: false,
                    autoplaySurface: autoplaySurface
                )
                .padding(.horizontal, mediaSideInset)
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

                        // Hubs chip for spark / non-long-form hub shares in the standard embed path.
                        if isHub, isVideo {
                            HubsOriginBadge(compact: true)
                                .padding(10)
                                .allowsHitTesting(false)
                        }
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

    @State private var showSystemShare = false
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
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        if let headline = post.displayHeadline {
                            Text(headline)
                                .postHeadlineStyle(lineLimit: 2)
                        }
                        if let sourceCountryName {
                            Text("From \(sourceCountryName)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Outside Matterya") {
                    shareRow("Share anywhere", subtitle: "Messages, Mail, social apps", icon: "square.and.arrow.up", tint: Theme.accentBright) {
                        showSystemShare = true
                    }
                    shareRow("Copy link", subtitle: "Share the public post link", icon: "link", tint: Theme.accent) {
                        ShareService.shared.copyLink(for: .post(post))
                        appState.showToast("Link copied")
                        closeShareUI()
                    }
                }

                Section("Inside Matterya") {
                    shareRow(
                        MatteryaCopy.shareToYourFeed,
                        subtitle: shareToFeedSubtitle,
                        icon: "rectangle.stack.fill",
                        tint: Theme.accent
                    ) {
                        if appState.needsRepeatShareWarning(for: post) {
                            showRepeatShareConfirm = true
                        } else {
                            Task { await shareToCountryFeed() }
                        }
                    }
                    shareRow(
                        isSparkShare ? "Send \(MatteryaCopy.spark) in chat" : "Send in message",
                        subtitle: isSparkShare
                            ? "Friend opens full-screen \(MatteryaCopy.sparks)"
                            : "Private chat with a friend",
                        icon: isSparkShare ? "sparkles" : "paperplane",
                        tint: isSparkShare ? Theme.reelsAccent : Theme.facebookBlue
                    ) {
                        showMessagePicker = true
                    }
                    if !keepsSparksPlaying {
                        shareRow("Repost with quote", subtitle: "Write your take on your home feed", icon: "quote.bubble", tint: Theme.ink) {
                            Task { await repostWithQuote() }
                        }
                    }
                }

                if let feedback {
                    Section {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { closeShareUI() }
                }
            }
            .sheet(isPresented: $showSystemShare) {
                ShareSheet(items: ShareService.shared.activityItems(for: .post(post))) {
                    // System share finished — stay in Sparks when overlay mode.
                    closeShareUI()
                }
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
                        // Silent send — toast only, keep watching.
                        appState.showToast("Sent in message")
                        closeShareUI()
                    } else {
                        appState.openConversation(id: conversationID)
                        appState.showToast("Sent in message")
                        closeShareUI()
                    }
                }
            }
        }
        // Sheet-only chrome (feed share). Sparks uses an overlay host — no presentation detents.
        .modifier(ShareSheetPresentationModifier(enabled: !keepsSparksPlaying))
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

    private func shareRow(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            }
        }
        .disabled(busy)
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
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load messages", systemImage: "exclamationmark.bubble", description: Text(errorMessage))
                } else if conversations.isEmpty {
                    ContentUnavailableView("No conversations yet", systemImage: "bubble.left.and.bubble.right", description: Text("Start a chat from someone's profile, then share here."))
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
                            }
                        }
                    }
                }
            }
            .navigationTitle(isSparkShare ? "Send \(MatteryaCopy.spark) to…" : "Send to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
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
                .presentationDetents([.medium, .large])
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
            .frame(maxHeight: UIScreen.main.bounds.height * 0.52)
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea()
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